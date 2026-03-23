#!/usr/bin/env bash
# worktree-create.sh — Create a git worktree for a ticket in the target repo
# Args: $1=branch_name $2=base_branch --target-repo=PATH --repo-name=NAME
# Output: worktree absolute path
# Worktree convention: ~/.claude/worktrees/{repo_name}/{branch_name}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
  echo "Usage: worktree-create.sh <branch_name> <base_branch> --target-repo=PATH --repo-name=NAME" >&2
  exit 1
fi

branch_name="$1"
base_branch="$2"
target_repo=""
repo_name=""

shift 2
for arg in "$@"; do
  case "$arg" in
    --target-repo=*) target_repo="${arg#--target-repo=}" ;;
    --repo-name=*) repo_name="${arg#--repo-name=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ -z "$target_repo" ]]; then
  echo "ERROR: --target-repo is required" >&2
  exit 1
fi

if [[ -z "$repo_name" ]]; then
  echo "ERROR: --repo-name is required" >&2
  exit 1
fi

if [[ ! -d "$target_repo/.git" ]]; then
  echo "ERROR: Target repo is not a git repository: $target_repo" >&2
  exit 1
fi

# Validate branch name
if ! "$SCRIPT_DIR/validate-branch-name.sh" "$branch_name" >/dev/null 2>&1; then
  echo "ERROR: Branch name validation failed for: $branch_name" >&2
  "$SCRIPT_DIR/validate-branch-name.sh" "$branch_name" 2>&1 || true
  exit 1
fi

# Worktree path: ~/.claude/worktrees/{repo_name}/{branch_name}
WORKTREES_BASE="$HOME/.claude/worktrees"
wt_path="$WORKTREES_BASE/${repo_name}/${branch_name}"

# Check if worktree already exists
if [[ -d "$wt_path" ]]; then
  echo "ERROR: Worktree already exists at $wt_path" >&2
  echo "Use --resume to continue an existing run." >&2
  exit 1
fi

# Ensure parent directory exists
mkdir -p "$WORKTREES_BASE/${repo_name}"

# Fetch latest from origin (in target repo)
git -C "$target_repo" fetch origin

# Create worktree (from target repo)
git -C "$target_repo" worktree add "$wt_path" -b "$branch_name" "origin/$base_branch"

# Output absolute path
cd "$wt_path" && pwd
