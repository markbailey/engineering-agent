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

project_key=""
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --project-key=*) project_key="${arg#--project-key=}" ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
  echo "Usage: check-pr-size.sh <worktree_path> <base_branch> [--project-key=KEY]" >&2
  exit 1
fi

worktree="${POSITIONAL[0]}"
base_branch="${POSITIONAL[1]}"

# Threshold priority: repos.json per-repo > env var > default 20
threshold="${AGENT_PR_SIZE_WARNING_FILES:-20}"
if [[ -n "$project_key" && -f "$AGENT_ROOT/repos.json" ]]; then
  repo_threshold=$(node -e "
    const r = require(process.argv[1]);
    const t = (r.repos[process.argv[2]] || {}).pr_size_threshold;
    if (t) process.stdout.write(String(t));
  " "$AGENT_ROOT/repos.json" "$project_key" 2>/dev/null || true)
  if [[ -n "$repo_threshold" ]]; then
    threshold="$repo_threshold"
  fi
fi

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
