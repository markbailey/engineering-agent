#!/usr/bin/env bash
# worktree-scan.sh — Detect orphaned worktrees on startup
# An orphaned worktree has no corresponding active run in /runs/
# Scans ~/.claude/worktrees/{repo_name}/{branch_name}/
# Reports findings to stdout — never auto-cleans

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKTREES_DIR="$HOME/.claude/worktrees"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ ! -d "$WORKTREES_DIR" ]]; then
  echo "No worktrees directory found at $WORKTREES_DIR"
  exit 0
fi

orphans=()

# Scan two levels: {repo_name}/{branch_name}
for repo_dir in "$WORKTREES_DIR"/*/; do
  [[ -d "$repo_dir" ]] || continue
  for wt in "$repo_dir"*/; do
    [[ -d "$wt" ]] || continue
    repo_name="$(basename "$(dirname "$wt")")"
    branch_name="$(basename "$wt")"

    # Extract ticket ID from branch name (format: {code}_{issue-id}_{desc}_{type})
    # Match PROJ-123 pattern in the branch name
    ticket_id=""
    if [[ "$branch_name" =~ ([A-Z]+-[0-9]+) ]]; then
      ticket_id="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$ticket_id" ]]; then
      orphans+=("$repo_name/$branch_name (no ticket ID detected)")
      continue
    fi

    # Check if a run directory exists for this ticket
    if [[ ! -d "$RUNS_DIR/$ticket_id" ]]; then
      orphans+=("$repo_name/$branch_name (no active run for $ticket_id)")
    fi
  done
done

if [[ ${#orphans[@]} -eq 0 ]]; then
  echo "No orphaned worktrees found."
  exit 0
fi

echo "Orphaned worktrees detected (${#orphans[@]}):"
for o in "${orphans[@]}"; do
  echo "  - $o"
done
echo ""
echo "These may contain unfinished work. Review manually before removing."
exit 0
