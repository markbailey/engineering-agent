#!/usr/bin/env bash
# check-pr-size.sh — Warn if PR diff exceeds file count threshold
# Args: $1=worktree_path $2=base_branch (e.g. origin/main)
# Exit 0=under limit, exit 2=over limit (soft warning, not hard block)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source rate limit awareness
# shellcheck disable=SC1091
source "$SCRIPT_DIR/rate-limit.sh"

# Load .env for threshold
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: check-pr-size.sh <worktree_path> <base_branch>" >&2
  exit 1
fi

worktree="$1"
base_branch="$2"
threshold="${AGENT_PR_SIZE_WARNING_FILES:-20}"

# Count changed files
file_count=$(git -C "$worktree" diff --name-only "$base_branch"...HEAD 2>/dev/null | wc -l || true)
file_count=$(echo "$file_count" | tr -d '[:space:]')
file_count="${file_count:-0}"

if [[ "$file_count" -gt "$threshold" ]]; then
  echo "{\"warning\":true,\"files_changed\":$file_count,\"threshold\":$threshold,\"message\":\"PR touches $file_count files (threshold: $threshold). Human approval required before opening PR.\"}" >&2
  exit 2
fi

echo "{\"warning\":false,\"files_changed\":$file_count,\"threshold\":$threshold}"
exit 0
