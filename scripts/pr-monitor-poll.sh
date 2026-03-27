#!/usr/bin/env bash
# pr-monitor-poll.sh — Lightweight GitHub PR state poller
# Usage: pr-monitor-poll.sh <ticket_id> <pr_number> [--save] [--github-repo=OWNER/REPO] [interval]
# Output: JSON { state, ci_status, reviews_approved, mergeable, is_draft }
# With --save: writes to runs/{ticket_id}/last_poll.json, adds "changed" field
# Designed for cheap polling between full PR Monitor agent invocations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 2 ]]; then
  echo '{"error":"Usage: pr-monitor-poll.sh <ticket_id> <pr_number> [--save] [--github-repo=OWNER/REPO] [interval]"}' >&2
  exit 1
fi

TICKET_ID="$1"
PR_NUMBER="$2"
INTERVAL="${AGENT_PR_MONITOR_INTERVAL:-60}"
SAVE_MODE=false
GITHUB_REPO=""

for arg in "${@:3}"; do
  case "$arg" in
    --save) SAVE_MODE=true ;;
    --github-repo=*) GITHUB_REPO="${arg#--github-repo=}" ;;
    [0-9]*) INTERVAL="$arg" ;;
  esac
done

# Fetch PR state from GitHub
gh_args=(gh pr view "$PR_NUMBER" --json state,statusCheckRollup,reviews,mergeable,isDraft)
[[ -n "$GITHUB_REPO" ]] && gh_args+=(--repo "$GITHUB_REPO")
pr_json=$("$SCRIPT_DIR/retry-with-backoff.sh" "${gh_args[@]}" 2>&1) || {
  echo "{\"error\":\"Failed to fetch PR #$PR_NUMBER: $pr_json\"}" >&2
  exit 1
}

# Parse into summary
SUMMARY=$(node -e "
const pr = JSON.parse(process.argv[1]);

const ciChecks = (pr.statusCheckRollup || []);
const allPassed = ciChecks.length > 0 && ciChecks.every(c => c.conclusion === 'SUCCESS' || c.status === 'COMPLETED' && c.conclusion === 'SUCCESS');
const anyFailed = ciChecks.some(c => c.conclusion === 'FAILURE');
const ciStatus = anyFailed ? 'fail' : allPassed ? 'pass' : 'pending';

const approvals = (pr.reviews || []).filter(r => r.state === 'APPROVED').length;
const changesRequested = (pr.reviews || []).some(r => r.state === 'CHANGES_REQUESTED');

console.log(JSON.stringify({
  pr_number: ${PR_NUMBER},
  state: pr.state,
  ci_status: ciStatus,
  ci_checks_total: ciChecks.length,
  ci_checks_passed: ciChecks.filter(c => c.conclusion === 'SUCCESS').length,
  ci_checks_failed: ciChecks.filter(c => c.conclusion === 'FAILURE').length,
  reviews_approved: approvals,
  changes_requested: changesRequested,
  mergeable: pr.mergeable || 'UNKNOWN',
  is_draft: pr.isDraft || false,
  poll_interval: ${INTERVAL}
}));
" "$pr_json")

# Without --save: just print summary and exit
if [[ "$SAVE_MODE" != "true" ]]; then
  echo "$SUMMARY"
  exit 0
fi

# --save: compare with previous poll, add "changed" + "polled_at", write to file
POLL_FILE="$AGENT_ROOT/runs/$TICKET_ID/last_poll.json"

changed=true
if [[ -f "$POLL_FILE" ]]; then
  prev_sig=$(node -e "const p=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log([p.state,p.ci_status,p.reviews_approved,p.changes_requested,p.mergeable,p.is_draft].join(','))" "$POLL_FILE" 2>/dev/null || echo "")
  curr_sig=$(echo "$SUMMARY" | node -e "const p=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log([p.state,p.ci_status,p.reviews_approved,p.changes_requested,p.mergeable,p.is_draft].join(','))")
  [[ "$prev_sig" == "$curr_sig" ]] && changed=false
fi

mkdir -p "$(dirname "$POLL_FILE")"
echo "$SUMMARY" | node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('/dev/stdin','utf8'));
data.changed = $changed;
data.polled_at = new Date().toISOString();
fs.writeFileSync(process.argv[1], JSON.stringify(data, null, 2));
console.log(JSON.stringify(data));
" "$POLL_FILE"
