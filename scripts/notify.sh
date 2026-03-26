#!/usr/bin/env bash
# notify.sh — Terminal notifications on key workflow events
# Also logs the event to run.log via run-log.sh
#
# Usage:
#   notify.sh <ticket_id> <event_type> <message> [details_json]
#
# Event types:
#   pr_opened, pr_updated, ci_failed, ci_passed, escalation,
#   rate_limit, secret_found, review_complete, merge_conflict,
#   task_complete, run_complete, run_failed, blocked, resumed
#
# Outputs a prominent terminal banner + logs EVENT to run.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ticket_id="${1:-}"
event_type="${2:-}"
message="${3:-}"
details="${4:-}"

if [[ -z "$ticket_id" || -z "$event_type" || -z "$message" ]]; then
  echo "Usage: notify.sh <ticket_id> <event_type> <message> [details_json]" >&2
  exit 1
fi

# Guard: detect swapped arguments (ticket_id must look like PROJ-123)
if [[ ! "$ticket_id" =~ ^[A-Z]+-[0-9]+$ ]]; then
  # Check if args were swapped (event_type in position 1, ticket_id in position 2)
  if [[ "$event_type" =~ ^[A-Z]+-[0-9]+$ ]]; then
    echo "WARN: notify.sh args appear swapped — auto-correcting ($ticket_id ↔ $event_type)" >&2
    tmp="$ticket_id"
    ticket_id="$event_type"
    event_type="$tmp"
  else
    echo "ERROR: notify.sh ticket_id '$ticket_id' doesn't match PROJ-123 format" >&2
    exit 1
  fi
fi

# Event type → severity + icon
icon="*"
severity="INFO"
case "$event_type" in
  pr_opened|pr_updated)   icon="[PR]";    severity="EVENT" ;;
  ci_failed)              icon="[CI FAIL]"; severity="ERROR" ;;
  ci_passed)              icon="[CI OK]";  severity="EVENT" ;;
  escalation)             icon="[ESCALATE]"; severity="ERROR" ;;
  rate_limit)             icon="[RATE]";   severity="WARN"  ;;
  secret_found)           icon="[SECRET]"; severity="ERROR" ;;
  review_complete)        icon="[REVIEW]"; severity="EVENT" ;;
  merge_conflict)         icon="[CONFLICT]"; severity="WARN" ;;
  task_complete)          icon="[TASK]";   severity="EVENT" ;;
  run_complete)           icon="[DONE]";   severity="EVENT" ;;
  run_failed)             icon="[FAIL]";   severity="ERROR" ;;
  blocked)                icon="[BLOCKED]"; severity="WARN" ;;
  resumed)                icon="[RESUME]"; severity="INFO"  ;;
  *)                      icon="[EVENT]";  severity="EVENT" ;;
esac

# Terminal banner
echo "" >&2
echo "========================================" >&2
echo " $icon $ticket_id" >&2
echo " $message" >&2
echo "========================================" >&2
echo "" >&2

# Build details JSON with event_type included
if [[ -n "$details" ]]; then
  event_details="{\"event_type\":\"$event_type\",$( echo "$details" | sed 's/^{//' )}"
else
  event_details="{\"event_type\":\"$event_type\"}"
fi

# Log to run.log
"$SCRIPT_DIR/run-log.sh" "$ticket_id" "$severity" "event" "$message" "$event_details"
