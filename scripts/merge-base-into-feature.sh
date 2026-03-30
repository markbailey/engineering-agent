#!/usr/bin/env bash
# merge-base-into-feature.sh — Merge base branch into feature branch inside a worktree
# Args: $1=worktree_path $2=base_branch
# Output JSON: { "status": "clean|conflicts|error", "conflicted_files": [...], "base_commit": "sha" }
# Exit: 0=clean merge, 1=conflicts (resolve needed), 2=error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/output.sh"

if [[ $# -lt 2 ]]; then
  emit_error "Usage: merge-base-into-feature.sh <worktree_path> <base_branch>" 2
fi

wt_path="$1"
base_branch="$2"

if [[ ! -d "$wt_path/.git" && ! -f "$wt_path/.git" ]]; then
  emit_error "Not a git worktree: $wt_path" 2
fi

cd "$wt_path"

# Fetch latest
git fetch origin 2>/dev/null

# Record base commit SHA
base_commit=$(git rev-parse "origin/$base_branch" 2>/dev/null) || true
if [[ -z "$base_commit" ]] || ! git cat-file -t "$base_commit" >/dev/null 2>&1; then
  emit_error "Cannot resolve origin/$base_branch" 2
fi

# Check if already up to date
merge_base=$(git merge-base HEAD "origin/$base_branch" 2>/dev/null)
if [[ "$merge_base" == "$base_commit" ]]; then
  echo "{\"status\":\"clean\",\"conflicted_files\":[],\"base_commit\":\"$base_commit\"}"
  exit 0
fi

# Attempt merge --no-ff
merge_output=$(git merge "origin/$base_branch" --no-ff --no-edit 2>&1)
merge_exit=$?

if [[ $merge_exit -eq 0 ]]; then
  echo "{\"status\":\"clean\",\"conflicted_files\":[],\"base_commit\":\"$base_commit\"}"
  exit 0
fi

# Merge had conflicts — enumerate conflicted files
conflicted=$(git diff --name-only --diff-filter=U 2>/dev/null | while IFS= read -r f; do
  printf '"%s",' "$f"
done)
# Remove trailing comma, wrap in array
conflicted="[${conflicted%,}]"

echo "{\"status\":\"conflicts\",\"conflicted_files\":$conflicted,\"base_commit\":\"$base_commit\"}"
exit 1
