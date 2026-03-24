#!/usr/bin/env bash
# check-branch-before-push.sh — Verify branch name is valid before any push
# Run this before every git push to enforce branch naming and protected branch rules
# Args: $1=worktree_path (optional, defaults to cwd)
# Exit 0=safe to push, exit 1=blocked

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

worktree="${1:-.}"
# symbolic-ref works on empty repos too; rev-parse --abbrev-ref needs at least one commit
branch=$(git -C "$worktree" symbolic-ref --short HEAD 2>/dev/null || \
         git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
  echo '{"allowed":false,"error":"Cannot determine current branch (detached HEAD?)"}' >&2
  exit 1
fi

# Protected branch check
for protected in main master staging; do
  if [[ "$branch" == "$protected" ]]; then
    echo "{\"allowed\":false,\"error\":\"BLOCKED: cannot push to protected branch '$protected'\"}" >&2
    exit 1
  fi
done

# Validate branch name format
if ! "$SCRIPT_DIR/validate-branch-name.sh" "$branch" >/dev/null 2>&1; then
  echo "{\"allowed\":false,\"error\":\"Branch '$branch' does not match naming convention — push blocked\"}" >&2
  exit 1
fi

echo '{"allowed":true,"branch":"'"$branch"'"}'
exit 0
