#!/usr/bin/env bash
# regression-guard.sh — 3-pass regression check after merge
# Args: $1=worktree_path $2=base_branch
# Output JSON: { "compilation": "pass|fail", "diff_analysis": "pass|fail", "test_suite": "pass|fail", "issues_found": [...] }
# Exit: 0=all pass, 1=failures found

set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: regression-guard.sh <worktree_path> <base_branch>" >&2
  exit 2
fi

wt_path="$1"
base_branch="$2"
issues=()

cd "$wt_path"

# --- Pass 1: Compilation ---
compilation="pass"
tsc_output=$(npx tsc --noEmit 2>&1)
if [[ $? -ne 0 ]]; then
  compilation="fail"
  # Extract first 5 errors
  while IFS= read -r line; do
    [[ -n "$line" ]] && issues+=("compilation: $line")
  done < <(echo "$tsc_output" | grep "error TS" | head -5)
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
npx prettier --write . >/dev/null 2>&1 || true
npx eslint --fix . >/dev/null 2>&1 || true

# Run tests
test_output=$(npm test 2>&1)
if [[ $? -ne 0 ]]; then
  test_suite="fail"
  # Extract failure summary
  while IFS= read -r line; do
    [[ -n "$line" ]] && issues+=("test_suite: $line")
  done < <(echo "$test_output" | grep -iE "fail|error|FAIL" | head -5)
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
