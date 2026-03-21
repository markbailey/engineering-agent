#!/usr/bin/env bash
# worktree-cleanup.sh — Remove worktree(s) and branch after confirmed merge
# Args: $1=ticket_id --target-repo=PATH --repo-name=NAME [--github-repo=OWNER/REPO]
# Safety: verifies PR is merged before proceeding

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKTREES_BASE="$HOME/.claude/worktrees"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ $# -lt 1 ]]; then
  echo "Usage: worktree-cleanup.sh <ticket_id> --target-repo=PATH --repo-name=NAME [--github-repo=OWNER/REPO]" >&2
  exit 1
fi

ticket_id="$1"
target_repo=""
repo_name=""
github_repo=""

shift
for arg in "$@"; do
  case "$arg" in
    --target-repo=*) target_repo="${arg#--target-repo=}" ;;
    --repo-name=*) repo_name="${arg#--repo-name=}" ;;
    --github-repo=*) github_repo="${arg#--github-repo=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Safety check: verify PR is merged
gh_args=(pr list --search "$ticket_id" --state merged --json number,headRefName)
if [[ -n "$github_repo" ]]; then
  gh_args+=(--repo "$github_repo")
fi
pr_list=$(gh "${gh_args[@]}" 2>/dev/null || echo "[]")

if [[ "$pr_list" == "[]" || "$pr_list" == "" ]]; then
  echo "ERROR: No merged PR found for $ticket_id — refusing to clean up" >&2
  echo "Cleanup only runs after confirmed merge." >&2
  exit 1
fi

cleaned=0

if [[ -n "$repo_name" ]]; then
  # Single repo cleanup — find worktree by scanning for ticket ID in branch names
  repo_wt_dir="$WORKTREES_BASE/${repo_name}"
  if [[ -d "$repo_wt_dir" ]]; then
    ticket_lower="${ticket_id,,}"
    for wt in "$repo_wt_dir"/*/; do
      [[ -d "$wt" ]] || continue
      branch_name="$(basename "$wt")"
      if [[ "${branch_name,,}" == *"${ticket_lower}"* ]]; then
        # Remove worktree via target repo
        if [[ -n "$target_repo" ]]; then
          git -C "$target_repo" worktree remove "$wt" --force 2>/dev/null || true
          git -C "$target_repo" branch -d "$branch_name" 2>/dev/null || true
        else
          rm -rf "$wt"
        fi
        echo "Removed worktree: ${repo_name}/${branch_name}"
        cleaned=$((cleaned + 1))
      fi
    done
  fi
else
  # Clean all repos — scan all repo dirs for matching ticket ID
  ticket_lower="${ticket_id,,}"
  for repo_dir in "$WORKTREES_BASE"/*/; do
    [[ -d "$repo_dir" ]] || continue
    for wt in "$repo_dir"*/; do
      [[ -d "$wt" ]] || continue
      branch_name="$(basename "$wt")"
      if [[ "${branch_name,,}" == *"${ticket_lower}"* ]]; then
        r_name="$(basename "$repo_dir")"
        git worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
        echo "Removed worktree: ${r_name}/${branch_name}"
        cleaned=$((cleaned + 1))
      fi
    done
  done
fi

if [[ $cleaned -eq 0 ]]; then
  echo "No worktrees found for ticket $ticket_id"
else
  echo "Cleaned up $cleaned worktree(s) for $ticket_id"
fi

# Archive artifacts (ensure runs dir exists)
if [[ -d "$RUNS_DIR/$ticket_id" ]]; then
  echo "Artifacts already archived at runs/$ticket_id/"
fi

exit 0
