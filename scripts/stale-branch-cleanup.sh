#!/usr/bin/env bash
# stale-branch-cleanup.sh — List or prune stale agent branches
# Args: $1=action (list-stale|prune-branches) [--target-repo=PATH] [--github-repo=OWNER/REPO]
# Stale = no commits in AGENT_STALE_BRANCH_DAYS (default 30) and no open PR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: stale-branch-cleanup.sh <list-stale|prune-branches> [--target-repo=PATH] [--github-repo=OWNER/REPO]" >&2
  exit 1
fi

action="$1"
target_repo=""
github_repo=""

shift
for arg in "$@"; do
  case "$arg" in
    --target-repo=*) target_repo="${arg#--target-repo=}" ;;
    --github-repo=*) github_repo="${arg#--github-repo=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

stale_days="${AGENT_STALE_BRANCH_DAYS:-30}"
agent_code="${AGENT_EMPLOYEE_CODE:-}"

if [[ -z "$agent_code" ]]; then
  echo "ERROR: AGENT_EMPLOYEE_CODE not set — cannot identify agent branches" >&2
  exit 1
fi

# Build git command prefix
git_cmd=(git)
if [[ -n "$target_repo" ]]; then
  git_cmd=(git -C "$target_repo")
fi

# Fetch latest remote state
"${git_cmd[@]}" fetch origin --prune 2>/dev/null || true

# Find agent branches (remote branches starting with agent code)
stale_branches=()
# Portable epoch arithmetic: current epoch minus stale_days in seconds
current_epoch=$(date +%s)
cutoff_epoch=$(( current_epoch - stale_days * 86400 ))

while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  branch_name="${ref#origin/}"

  # Skip if not an agent branch
  [[ "$branch_name" != "${agent_code}_"* ]] && continue

  # Get last commit date
  last_commit_epoch=$("${git_cmd[@]}" log -1 --format="%ct" "origin/$branch_name" 2>/dev/null || echo "0")

  if [[ "$last_commit_epoch" -lt "$cutoff_epoch" ]]; then
    # Check for open PR
    gh_args=(pr list --head "$branch_name" --state open --json number)
    if [[ -n "$github_repo" ]]; then
      gh_args+=(--repo "$github_repo")
    fi
    has_pr=$(gh "${gh_args[@]}" 2>/dev/null || echo "[]")
    if [[ "$has_pr" == "[]" || "$has_pr" == "" ]]; then
      last_date=$("${git_cmd[@]}" log -1 --format="%ci" "origin/$branch_name" 2>/dev/null || echo "unknown")
      stale_branches+=("$branch_name|$last_date")
    fi
  fi
done < <("${git_cmd[@]}" branch -r --format='%(refname:short)' 2>/dev/null | grep "^origin/${agent_code}_" || true)

case "$action" in
  list-stale)
    if [[ ${#stale_branches[@]} -eq 0 ]]; then
      echo "No stale agent branches found (threshold: ${stale_days} days)"
      exit 0
    fi
    echo "Stale agent branches (no commits in ${stale_days}+ days, no open PR):"
    for entry in "${stale_branches[@]}"; do
      branch="${entry%%|*}"
      date="${entry##*|}"
      echo "  - $branch (last commit: $date)"
    done
    echo ""
    echo "Total: ${#stale_branches[@]} stale branch(es)"
    echo "Run with 'prune-branches' to delete them."
    exit 0
    ;;
  prune-branches)
    if [[ ${#stale_branches[@]} -eq 0 ]]; then
      echo "No stale branches to prune."
      exit 0
    fi
    pruned=0
    for entry in "${stale_branches[@]}"; do
      branch="${entry%%|*}"
      if "${git_cmd[@]}" push origin --delete "$branch" 2>/dev/null; then
        echo "Deleted remote: origin/$branch"
        pruned=$((pruned + 1))
      else
        echo "Failed to delete: origin/$branch" >&2
      fi
      "${git_cmd[@]}" branch -d "$branch" 2>/dev/null || true
    done
    echo "Pruned $pruned of ${#stale_branches[@]} stale branch(es)"
    exit 0
    ;;
  *)
    echo "Unknown action: $action (use list-stale|prune-branches)" >&2
    exit 1
    ;;
esac
