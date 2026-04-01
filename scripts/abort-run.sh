#!/usr/bin/env bash
# abort-run.sh — Abort a run with cleanup (does NOT remove worktree or branches)
#
# Usage:
#   abort-run.sh <ticket_id> <reason> [--github-repo=OWNER/REPO]
#
# Steps:
#   1. Close open draft PR matching ticket (if --github-repo provided)
#   2. Update PRD.json overall_status to "aborted" (if exists)
#   3. Write ESCALATION.json with category "unknown" and abort reason
#   4. Log EVENT "run aborted" to run.log
#   5. Call run-summary.sh with status "aborted" (if run.log exists)
#
# Does NOT remove worktree or delete branches.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ticket_id="${1:-}"
reason="${2:-}"
shift 2 2>/dev/null || true

# Parse optional flags
github_repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-repo=*) github_repo="${1#--github-repo=}"; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ticket_id" || -z "$reason" ]]; then
  echo "Usage: abort-run.sh <ticket_id> <reason> [--github-repo=OWNER/REPO]" >&2
  exit 1
fi

run_dir="$AGENT_ROOT/runs/$ticket_id"
mkdir -p "$run_dir"

# Track actions for JSON output
pr_closed="false"
pr_number=""
prd_updated="false"
escalation_written="false"
logged="false"
summary_written="false"

# 1. Close open draft PR matching ticket
if [[ -n "$github_repo" ]]; then
  pr_number=$(gh pr list --repo "$github_repo" --search "$ticket_id" --state open --json number,isDraft --jq '.[0].number' 2>/dev/null || echo "")
  # Validate PR number is numeric
  if [[ -n "$pr_number" && "$pr_number" != "null" && ! "$pr_number" =~ ^[0-9]+$ ]]; then
    echo "Warning: invalid PR number '$pr_number', skipping close" >&2
    pr_number=""
  fi
  if [[ -n "$pr_number" && "$pr_number" != "null" ]]; then
    if gh pr close "$pr_number" --repo "$github_repo" 2>/dev/null; then
      pr_closed="true"
    fi
  fi
fi

# 2. Write ESCALATION.json via escalate.sh (before PRD update — escalate.sh may set "escalated")
esc_output=$("$SCRIPT_DIR/escalate.sh" "$ticket_id" "unknown" "high" "orchestrator" "abort" "$reason" 2>/dev/null || echo "")
if [[ -n "$esc_output" ]]; then
  escalation_written="true"
fi

# 3. Update PRD.json overall_status to "aborted" (after escalate.sh, which may set "escalated")
prd_file="$run_dir/PRD.json"
if [[ -f "$prd_file" ]]; then
  if "$SCRIPT_DIR/update-prd-status.sh" "$ticket_id" "aborted" >/dev/null 2>&1; then
    prd_updated="true"
  fi
fi

# 4. Log EVENT "run aborted" to run.log
"$SCRIPT_DIR/run-log.sh" "$ticket_id" "EVENT" "event" "Run aborted: $reason" "{\"action\":\"abort\",\"reason\":\"$(echo "$reason" | sed 's/"/\\"/g')\"}" 2>/dev/null || true
logged="true"

# 5. Call run-summary.sh with status "aborted" (if run.log exists)
log_file="$run_dir/run.log"
if [[ -f "$log_file" ]]; then
  # Count tasks from PRD.json if available
  tasks_total=0
  tasks_completed=0
  if [[ -f "$prd_file" ]]; then
    tasks_total=$(python3 -c "import json; d=json.load(open('$prd_file')); print(len(d.get('tasks',[])))" 2>/dev/null || echo 0)
    tasks_completed=$(python3 -c "import json; d=json.load(open('$prd_file')); print(sum(1 for t in d.get('tasks',[]) if t.get('status')=='verified'))" 2>/dev/null || echo 0)
  fi
  "$SCRIPT_DIR/run-summary.sh" "$ticket_id" "aborted" "$tasks_total" "$tasks_completed" 2>/dev/null || true
  summary_written="true"
fi

# Output JSON summary
python3 -c "
import json, sys
result = {
    'ticket': sys.argv[1],
    'action': 'abort',
    'pr_closed': sys.argv[2] == 'true',
    'pr_number': sys.argv[3] if sys.argv[3] and sys.argv[3] != 'null' else None,
    'prd_updated': sys.argv[4] == 'true',
    'escalation_written': sys.argv[5] == 'true',
    'logged': sys.argv[6] == 'true',
    'summary_written': sys.argv[7] == 'true',
    'reason': sys.argv[8]
}
print(json.dumps(result, indent=2))
" "$ticket_id" "$pr_closed" "${pr_number:-null}" "$prd_updated" "$escalation_written" "$logged" "$summary_written" "$reason"
