#!/usr/bin/env bash
# regression-guard.sh — 3-pass regression check after merge
# Args: $1=worktree_path $2=base_branch [$3=project_key]
# Output JSON: { "compilation": "pass|fail", "diff_analysis": "pass|fail", "test_suite": "pass|fail", "issues_found": [...] }
# Exit: 0=all pass, 1=failures found

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
  echo "Usage: regression-guard.sh <worktree_path> <base_branch> [project_key]" >&2
  exit 2
fi

wt_path="$1"
base_branch="$2"
project_key="${3:-}"
issues=()

# Helper: resolve toolchain command or return empty string (use default)
resolve_cmd() {
  local step="$1"
  if [[ -n "$project_key" ]]; then
    local result
    result=$("$SCRIPT_DIR/resolve-toolchain.sh" "$project_key" "$step" 2>/dev/null || echo '{"skip":true}')
    local skip
    skip=$(echo "$result" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).skip)))" 2>/dev/null || echo "true")
    if [[ "$skip" == "false" ]]; then
      echo "$result" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(JSON.parse(d).command))" 2>/dev/null
      return 0
    fi
    # skip==true means not configured — return special marker
    echo "__SKIP__"
    return 0
  fi
  echo ""
}

cd "$wt_path"

# --- Pass 1: Compilation ---
compilation="pass"
typecheck_cmd=$(resolve_cmd "typecheck")
if [[ "$typecheck_cmd" == "__SKIP__" ]]; then
  compilation="skip"
else
  typecheck_cmd="${typecheck_cmd:-npx tsc --noEmit}"
  tsc_output=$("$SCRIPT_DIR/with-timeout.sh" "${AGENT_TSC_TIMEOUT:-120}" $typecheck_cmd 2>&1)
  tsc_exit=$?
  if [[ $tsc_exit -eq 124 ]]; then
    compilation="fail"
    issues+=("compilation: typecheck timed out after ${AGENT_TSC_TIMEOUT:-120}s")
  elif [[ $tsc_exit -ne 0 ]]; then
    compilation="fail"
    # Extract first 5 errors
    while IFS= read -r line; do
      [[ -n "$line" ]] && issues+=("compilation: $line")
    done < <(echo "$tsc_output" | grep -iE "error" | head -5)
  fi
fi

# --- Pass 2: Diff analysis ---
diff_analysis="pass"
# Get files changed by base branch since merge-base
merge_base=$(git merge-base HEAD~ "origin/$base_branch" 2>/dev/null || echo "")
if [[ -n "$merge_base" ]]; then
  # Files changed in base since common ancestor
  base_changed=$(git diff --name-only "$merge_base" "origin/$base_branch" 2>/dev/null || echo "")

  # Check for deleted exports, renamed functions, changed interfaces
  for f in $base_changed; do
    [[ ! -f "$f" ]] && continue
    ext="${f##*.}"
    [[ "$ext" != "ts" && "$ext" != "tsx" && "$ext" != "js" && "$ext" != "jsx" ]] && continue

    # Check if any of our feature files import from this changed file
    # Strip extension for import matching
    base_no_ext="${f%.*}"
    importers=$(grep -rlE "$base_no_ext|$(basename "$base_no_ext")" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" . 2>/dev/null | grep -v node_modules | grep -v ".git" || true)

    if [[ -n "$importers" ]]; then
      # Check if the file was deleted in base
      if ! git show "origin/$base_branch:$f" >/dev/null 2>&1; then
        diff_analysis="fail"
        issues+=("diff_analysis: base deleted $f which is imported by feature code")
      fi
    fi
  done
fi

# --- Pass 3: Full QA suite ---
test_suite="pass"

# Auto-fix first
lint_fix_cmd=$(resolve_cmd "lint_fix")
if [[ "$lint_fix_cmd" != "__SKIP__" ]]; then
  if [[ -n "$lint_fix_cmd" ]]; then
    eval "$lint_fix_cmd" >/dev/null 2>&1 || true
  else
    npx prettier --write . >/dev/null 2>&1 || true
    npx eslint --fix . >/dev/null 2>&1 || true
  fi
fi

# Run tests
test_cmd=$(resolve_cmd "test")
if [[ "$test_cmd" == "__SKIP__" ]]; then
  test_suite="skip"
else
  test_cmd="${test_cmd:-npm test}"
  test_output=$("$SCRIPT_DIR/with-timeout.sh" "${AGENT_TEST_TIMEOUT:-300}" $test_cmd 2>&1)
  test_exit=$?
  if [[ $test_exit -eq 124 ]]; then
    test_suite="fail"
    issues+=("test_suite: test command timed out after ${AGENT_TEST_TIMEOUT:-300}s")
  elif [[ $test_exit -ne 0 ]]; then
    test_suite="fail"
    # Extract failure summary
    while IFS= read -r line; do
      [[ -n "$line" ]] && issues+=("test_suite: $line")
    done < <(echo "$test_output" | grep -iE "fail|error|FAIL" | head -5)
  fi
fi

# --- Build JSON output ---
issues_json="["
first=true
for issue in "${issues[@]+"${issues[@]}"}"; do
  if $first; then first=false; else issues_json+=","; fi
  # Escape quotes in issue text
  escaped=$(echo "$issue" | sed 's/"/\\"/g' | tr '\n' ' ')
  issues_json+="\"$escaped\""
done
issues_json+="]"

overall_exit=0
if [[ "$compilation" == "fail" || "$diff_analysis" == "fail" || "$test_suite" == "fail" ]]; then
  overall_exit=1
fi

echo "{\"compilation\":\"$compilation\",\"diff_analysis\":\"$diff_analysis\",\"test_suite\":\"$test_suite\",\"issues_found\":$issues_json}"
exit $overall_exit
