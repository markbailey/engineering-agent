#!/usr/bin/env bash
# orphan-check.sh — Detect orphaned code after merge (4 categories)
# Args: $1=worktree_path $2=base_branch
# Output JSON matching orphan_check in conflict.schema.json
# Exit: 0=clean, 1=orphans found

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prd_path=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prd) prd_path="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done

if [[ ${#args[@]} -lt 2 ]]; then
  echo "Usage: orphan-check.sh <worktree_path> <base_branch> [--prd <path>]" >&2
  exit 2
fi

wt_path="${args[0]}"
base_branch="${args[1]}"

# If PRD provided, extract files_affected to scope analysis
prd_files=()
if [[ -n "$prd_path" && -f "$prd_path" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && prd_files+=("$f")
  done < <(node -e "
    const fs = require('fs');
    const prd = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    const files = new Set();
    (prd.tasks || []).forEach(t => (t.files_affected || []).forEach(f => files.add(f)));
    files.forEach(f => console.log(f));
  " "$prd_path" 2>/dev/null)
fi

cd "$wt_path"

deleted_callsites=()
renamed_refs=()
dead_exports=()
disconnected=()
status="pass"

merge_base=$(git merge-base HEAD~ "origin/$base_branch" 2>/dev/null || echo "")
if [[ -z "$merge_base" ]]; then
  echo '{"status":"skipped","deleted_callsites":[],"renamed_references":[],"dead_exports":[],"disconnected_integrations":[]}'
  exit 0
fi

# Files deleted by base branch
base_deleted=$(git diff --name-only --diff-filter=D "$merge_base" "origin/$base_branch" 2>/dev/null || echo "")

# Files added/modified by our feature (compare merge-base to HEAD)
feature_files=$(git diff --name-only "$merge_base" HEAD 2>/dev/null | grep -v node_modules || echo "")

# If PRD scoping active, filter feature_files to only PRD-listed files
if [[ ${#prd_files[@]} -gt 0 ]]; then
  filtered=""
  for f in $feature_files; do
    for pf in "${prd_files[@]}"; do
      if [[ "$f" == "$pf" ]]; then
        filtered+="$f"$'\n'
        break
      fi
    done
  done
  feature_files="$filtered"
fi

# --- Category 1: Deleted callsites ---
# Base deleted files that our feature code imports from
for f in $base_deleted; do
  ext="${f##*.}"
  [[ "$ext" != "ts" && "$ext" != "tsx" && "$ext" != "js" && "$ext" != "jsx" ]] && continue
  base_no_ext="${f%.*}"
  name=$(basename "$base_no_ext")
  # Check if any feature files reference the deleted file
  refs=$("$SCRIPT_DIR/with-timeout.sh" "${AGENT_GREP_TIMEOUT:-30}" grep -rlF "$name" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" . 2>/dev/null || true)
  refs=$(echo "$refs" | grep -v node_modules | grep -v ".git" || true)
  if [[ -n "$refs" ]]; then
    status="fail"
    deleted_callsites+=("$f (referenced by feature code)")
  fi
done

# --- Category 2: Renamed references ---
# Detect renames in base branch
base_renames=$(git diff --diff-filter=R --name-status "$merge_base" "origin/$base_branch" 2>/dev/null || echo "")
while IFS=$'\t' read -r _ old_name new_name; do
  [[ -z "$old_name" ]] && continue
  old_base=$(basename "${old_name%.*}")
  # Check if our feature references the old name
  refs=$("$SCRIPT_DIR/with-timeout.sh" "${AGENT_GREP_TIMEOUT:-30}" grep -rlF "$old_base" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" . 2>/dev/null || true)
  refs=$(echo "$refs" | grep -v node_modules | grep -v ".git" || true)
  if [[ -n "$refs" ]]; then
    status="fail"
    ref_files=$(echo "$refs" | tr '\n' ',' | sed 's/,$//')
    renamed_refs+=("{\"old_name\":\"$old_name\",\"new_name\":\"$new_name\",\"files_updated\":[],\"status\":\"escalated\"}")
  fi
done <<< "$base_renames"

# --- Category 3: Dead exports ---
# Exports added by our feature that nothing in the codebase imports
for f in $feature_files; do
  [[ ! -f "$f" ]] && continue
  ext="${f##*.}"
  [[ "$ext" != "ts" && "$ext" != "tsx" && "$ext" != "js" && "$ext" != "jsx" ]] && continue

  # Find new export statements in our changes
  new_exports=$(git diff "$merge_base" HEAD -- "$f" 2>/dev/null | grep "^+" | grep -E "export[[:space:]]+(const|function|class|type|interface|enum)[[:space:]]+" | sed -E 's/.*export[[:space:]]+(const|function|class|type|interface|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/' || true)
  for exp in $new_exports; do
    # Check if anything else references this export
    consumers=$("$SCRIPT_DIR/with-timeout.sh" "${AGENT_GREP_TIMEOUT:-30}" grep -rlF "$exp" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" . 2>/dev/null || true)
    consumers=$(echo "$consumers" | grep -v node_modules | grep -v ".git" | grep -v "$f" || true)
    if [[ -z "$consumers" ]]; then
      dead_exports+=("$f:$exp")
    fi
  done
done

# --- Category 4: Disconnected integrations ---
# Base restructured integration points (middleware, plugins, hooks)
integration_patterns="middleware|plugin|hook|provider|interceptor|guard|pipe|filter"
base_modified=$(git diff --name-only "$merge_base" "origin/$base_branch" 2>/dev/null || echo "")
for f in $base_modified; do
  [[ ! -f "$f" ]] && continue
  if echo "$f" | grep -qiE "$integration_patterns"; then
    # Check if our feature adds to this integration layer
    our_changes=$(git diff "$merge_base" HEAD -- "$f" 2>/dev/null | grep "^+" | head -1 || true)
    if [[ -n "$our_changes" ]]; then
      status="fail"
      disconnected+=("$f (integration layer restructured by base, feature adds to it)")
    fi
  fi
done

# --- Build JSON ---
dc_json="["
first=true
for item in "${deleted_callsites[@]+"${deleted_callsites[@]}"}"; do
  if $first; then first=false; else dc_json+=","; fi
  dc_json+="\"$(echo "$item" | sed 's/"/\\"/g')\""
done
dc_json+="]"

rr_json="["
first=true
for item in "${renamed_refs[@]+"${renamed_refs[@]}"}"; do
  if $first; then first=false; else rr_json+=","; fi
  rr_json+="$item"
done
rr_json+="]"

de_json="["
first=true
for item in "${dead_exports[@]+"${dead_exports[@]}"}"; do
  if $first; then first=false; else de_json+=","; fi
  de_json+="\"$(echo "$item" | sed 's/"/\\"/g')\""
done
de_json+="]"

di_json="["
first=true
for item in "${disconnected[@]+"${disconnected[@]}"}"; do
  if $first; then first=false; else di_json+=","; fi
  di_json+="\"$(echo "$item" | sed 's/"/\\"/g')\""
done
di_json+="]"

echo "{\"status\":\"$status\",\"deleted_callsites\":$dc_json,\"renamed_references\":$rr_json,\"dead_exports\":$de_json,\"disconnected_integrations\":$di_json}"

if [[ "$status" == "fail" ]]; then
  exit 1
fi
exit 0
