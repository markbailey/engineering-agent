#!/usr/bin/env bash
# pr-monitor-poll.sh — Lightweight GitHub PR state poller
# Usage: pr-monitor-poll.sh <ticket_id> <pr_number> [--github-repo=OWNER/REPO] [interval]
# Output: JSON { state, ci_status, reviews_approved, reviews_commented, mergeable, is_draft }
# Designed for cheap polling between full PR Monitor agent invocations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GITHUB_REPO=""
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --github-repo=*) GITHUB_REPO="${arg#*=}" ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
  echo '{"error":"Usage: pr-monitor-poll.sh <ticket_id> <pr_number> [--github-repo=OWNER/REPO] [interval]"}' >&2
  exit 1
fi

TICKET_ID="${POSITIONAL[0]}"
PR_NUMBER="${POSITIONAL[1]}"
INTERVAL="${POSITIONAL[2]:-${AGENT_PR_MONITOR_INTERVAL:-60}}"

REPO_FLAG=()
[[ -n "$GITHUB_REPO" ]] && REPO_FLAG=(--repo "$GITHUB_REPO")

# Fetch PR state from GitHub
pr_json=$("$SCRIPT_DIR/retry-with-backoff.sh" --ticket="$TICKET_ID" 3 2000 -- "$SCRIPT_DIR/with-timeout.sh" "${AGENT_GH_TIMEOUT:-30}" gh pr view "$PR_NUMBER" ${REPO_FLAG[@]+"${REPO_FLAG[@]}"} --json state,statusCheckRollup,reviews,comments,mergeable,isDraft 2>&1) || {
  echo "{\"error\":\"Failed to fetch PR #$PR_NUMBER: $pr_json\"}" >&2
  exit 1
}

# Parse into summary
node -e "
const pr = JSON.parse(process.argv[1]);

const ciChecks = (pr.statusCheckRollup || []);
const allPassed = ciChecks.length > 0 && ciChecks.every(c => c.conclusion === 'SUCCESS' || c.status === 'COMPLETED' && c.conclusion === 'SUCCESS');
const anyFailed = ciChecks.some(c => c.conclusion === 'FAILURE');
const ciStatus = anyFailed ? 'fail' : allPassed ? 'pass' : 'pending';

const approvals = (pr.reviews || []).filter(r => r.state === 'APPROVED').length;
const changesRequested = (pr.reviews || []).some(r => r.state === 'CHANGES_REQUESTED');
const commented = (pr.reviews || []).filter(r => r.state === 'COMMENTED').length;

console.log(JSON.stringify({
  pr_number: ${PR_NUMBER},
  state: pr.state,
  ci_status: ciStatus,
  ci_checks_total: ciChecks.length,
  ci_checks_passed: ciChecks.filter(c => c.conclusion === 'SUCCESS').length,
  ci_checks_failed: ciChecks.filter(c => c.conclusion === 'FAILURE').length,
  reviews_approved: approvals,
  reviews_commented: commented,
  changes_requested: changesRequested,
  mergeable: pr.mergeable || 'UNKNOWN',
  is_draft: pr.isDraft || false,
  poll_interval: ${INTERVAL}
}));
" "$pr_json"
