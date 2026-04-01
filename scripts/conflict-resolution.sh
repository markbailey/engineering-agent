#!/usr/bin/env bash
# conflict-resolution.sh — Full conflict resolution pipeline
# Orchestrates: merge → regression guard → orphan check → CONFLICT.json
# Args: $1=worktree_path $2=base_branch $3=feature_branch $4=ticket_id
# Exit: 0=resolved, 1=needs agent resolution (conflicts), 2=escalate, 3=error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prd_flag=""
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prd=*) prd_flag="--prd ${1#--prd=}"; shift ;;
    --prd) prd_flag="--prd $2"; shift 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done

if [[ ${#positional[@]} -lt 4 ]]; then
  echo "Usage: conflict-resolution.sh <worktree_path> <base_branch> <feature_branch> <ticket_id> [--prd <path>]" >&2
  exit 3
fi

wt_path="${positional[0]}"
base_branch="${positional[1]}"
feature_branch="${positional[2]}"
ticket_id="${positional[3]}"

echo "=== Conflict Resolution: $ticket_id ==="
echo "Worktree: $wt_path"
echo "Base: $base_branch → Feature: $feature_branch"

# Step 1: Merge
echo "--- Step 1: Merge origin/$base_branch --no-ff ---"
merge_json=$("$SCRIPT_DIR/merge-base-into-feature.sh" "$wt_path" "$base_branch" 2>/dev/null)
merge_exit=$?

merge_status=$(echo "$merge_json" | node -e "console.log(JSON.parse(process.argv[1]).status)" "$merge_json")

if [[ "$merge_status" == "error" ]]; then
  echo "ERROR: Merge failed" >&2
  # Write CONFLICT.json with error status
  guard_json='{"compilation":"skipped","diff_analysis":"skipped","test_suite":"skipped","issues_found":[]}'
  orphan_json='{"status":"skipped","deleted_callsites":[],"renamed_references":[],"dead_exports":[],"disconnected_integrations":[]}'
  "$SCRIPT_DIR/write-conflict-json.sh" "$ticket_id" "$base_branch" "$feature_branch" "$merge_json" "$guard_json" "$orphan_json"
  exit 2
fi

if [[ "$merge_status" == "conflicts" ]]; then
  echo "Conflicts detected — agent resolution required"
  echo "$merge_json"
  # Don't run guards yet — Conflict Resolution Agent resolves first, then Orchestrator re-runs this
  guard_json='{"compilation":"skipped","diff_analysis":"skipped","test_suite":"skipped","issues_found":[]}'
  orphan_json='{"status":"skipped","deleted_callsites":[],"renamed_references":[],"dead_exports":[],"disconnected_integrations":[]}'
  "$SCRIPT_DIR/write-conflict-json.sh" "$ticket_id" "$base_branch" "$feature_branch" "$merge_json" "$guard_json" "$orphan_json"
  exit 1
fi

echo "Clean merge — proceeding to guards"

# Step 2: Regression guard
echo "--- Step 2: Regression Guard ---"
cd "$wt_path"
guard_json=$("$SCRIPT_DIR/regression-guard.sh" "$wt_path" "$base_branch" 2>/dev/null)
guard_exit=$?

if [[ $guard_exit -ne 0 ]]; then
  echo "Regression guard found issues"
fi

# Step 3: Orphan check (prefer TS-aware check if available)
echo "--- Step 3: Orphan Check ---"
orphan_json=""
orphan_exit=0

if [[ -f "$wt_path/tsconfig.json" && -f "$SCRIPT_DIR/orphan-check-ts.js" ]]; then
  echo "TS project detected — trying orphan-check-ts.js"
  orphan_json=$(node "$SCRIPT_DIR/orphan-check-ts.js" "$wt_path" "$base_branch" 2>/dev/null)
  orphan_exit=$?
  if [[ $orphan_exit -ne 0 || -z "$orphan_json" ]]; then
    echo "TS orphan check failed or empty — falling back to grep-based check"
    orphan_json=""
    orphan_exit=0
  fi
fi

if [[ -z "$orphan_json" ]]; then
  orphan_json=$("$SCRIPT_DIR/orphan-check.sh" "$wt_path" "$base_branch" $prd_flag 2>/dev/null)
  orphan_exit=$?
fi

if [[ $orphan_exit -ne 0 ]]; then
  echo "Orphan check found issues"
fi

# Step 4: Write CONFLICT.json
echo "--- Step 4: Write CONFLICT.json ---"
"$SCRIPT_DIR/write-conflict-json.sh" "$ticket_id" "$base_branch" "$feature_branch" "$merge_json" "$guard_json" "$orphan_json"

# Determine overall exit
if [[ $guard_exit -ne 0 || $orphan_exit -ne 0 ]]; then
  # Check if disconnected integrations (hard escalate)
  disconnected=$(echo "$orphan_json" | node -e "console.log(JSON.parse(process.argv[1]).disconnected_integrations.length)" "$orphan_json")
  if [[ "$disconnected" -gt 0 ]]; then
    echo "ESCALATE: Disconnected integrations detected"
    exit 2
  fi
  echo "Issues found but potentially fixable — agent can attempt one fix round"
  exit 1
fi

echo "=== Conflict Resolution: CLEAN ==="
exit 0
