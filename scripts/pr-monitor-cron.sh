#!/usr/bin/env bash
# pr-monitor-cron.sh — Poll all active PRs, optionally trigger resume for changed ones
# Usage: pr-monitor-cron.sh [--trigger]
# Output: JSON array of ticket_ids with changes detected
# With --trigger: invokes `claude /start {ticket} --resume` for each changed ticket

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"

TRIGGER=false
for arg in "$@"; do
  [[ "$arg" == "--trigger" ]] && TRIGGER=true
done

resume_list=()

# Find all runs with pr_monitoring status
for prd_file in "$RUNS_DIR"/*/PRD.json; do
  [[ -f "$prd_file" ]] || continue

  # Extract status, pr_number, github_repo, ticket_id
  eval "$(node -e "
const prd = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
if (prd.overall_status !== 'pr_monitoring') process.exit(1);
const pr = prd.pr_number || '';
const repo = prd.github_repo || '';
const ticket = prd.ticket_id || '';
console.log('STATUS=pr_monitoring');
console.log('PR_NUMBER=' + pr);
console.log('GITHUB_REPO=' + repo);
console.log('TICKET_ID=' + ticket);
" "$prd_file" 2>/dev/null)" || continue

  [[ -z "$PR_NUMBER" || -z "$TICKET_ID" ]] && continue

  # Build poll args
  poll_args=("$TICKET_ID" "$PR_NUMBER" "--save")
  [[ -n "$GITHUB_REPO" ]] && poll_args+=("--github-repo=$GITHUB_REPO")

  # Poll
  poll_result=$("$SCRIPT_DIR/pr-monitor-poll.sh" "${poll_args[@]}" 2>/dev/null) || continue

  # Check if draft — skip drafts
  is_draft=$(echo "$poll_result" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log(d.is_draft)" 2>/dev/null || echo "false")
  [[ "$is_draft" == "true" ]] && continue

  # Check if changed
  changed=$(echo "$poll_result" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log(d.changed)" 2>/dev/null || echo "false")
  [[ "$changed" == "true" ]] && resume_list+=("$TICKET_ID")
done

# Output JSON array of changed ticket IDs
node -e "console.log(JSON.stringify($(printf '%s\n' "${resume_list[@]:-}" | node -e "
const lines = require('fs').readFileSync('/dev/stdin','utf8').trim().split('\n').filter(Boolean);
console.log(JSON.stringify(lines));
" 2>/dev/null || echo '[]')))"

# Trigger resume for each changed ticket
if [[ "$TRIGGER" == "true" && ${#resume_list[@]} -gt 0 ]]; then
  for ticket in "${resume_list[@]}"; do
    echo "Triggering resume for $ticket..."
    claude --permission-mode bypassPermissions "/start $ticket --resume" &
  done
  wait
fi
