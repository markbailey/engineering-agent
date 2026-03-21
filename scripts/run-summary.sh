#!/usr/bin/env bash
# run-summary.sh — Write run summary to run.log at end of ticket
#
# Usage:
#   run-summary.sh <ticket_id> <status> <tasks_total> <tasks_completed> [pr_url] [duration_info]
#
# Reads run.log to compute stats (error count, warning count, event count)
# Appends a summary block to run.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ticket_id="${1:-}"
status="${2:-unknown}"
tasks_total="${3:-0}"
tasks_completed="${4:-0}"
pr_url="${5:-}"
duration_info="${6:-}"

if [[ -z "$ticket_id" ]]; then
  echo "Usage: run-summary.sh <ticket_id> <status> <tasks_total> <tasks_completed> [pr_url] [duration_info]" >&2
  exit 1
fi

run_dir="$AGENT_ROOT/runs/$ticket_id"
log_file="$run_dir/run.log"

# Count log entries by level
error_count=0
warn_count=0
event_count=0
info_count=0

if [[ -f "$log_file" ]]; then
  error_count=$(grep -c '"level":"ERROR"' "$log_file" 2>/dev/null || echo 0)
  warn_count=$(grep -c '"level":"WARN"' "$log_file" 2>/dev/null || echo 0)
  event_count=$(grep -c '"level":"EVENT"' "$log_file" 2>/dev/null || echo 0)
  info_count=$(grep -c '"level":"INFO"' "$log_file" 2>/dev/null || echo 0)
fi

total_entries=$((error_count + warn_count + event_count + info_count))

# Build summary details JSON
summary_details="{\"type\":\"run_summary\",\"status\":\"$status\""
summary_details="$summary_details,\"tasks_total\":$tasks_total,\"tasks_completed\":$tasks_completed"
summary_details="$summary_details,\"log_entries\":$total_entries"
summary_details="$summary_details,\"errors\":$error_count,\"warnings\":$warn_count,\"events\":$event_count"

if [[ -n "$pr_url" ]]; then
  summary_details="$summary_details,\"pr_url\":\"$pr_url\""
fi
if [[ -n "$duration_info" ]]; then
  summary_details="$summary_details,\"duration\":\"$duration_info\""
fi

summary_details="$summary_details}"

# Write summary via run-log.sh
"$SCRIPT_DIR/run-log.sh" "$ticket_id" "EVENT" "summary" \
  "Run complete: $status — $tasks_completed/$tasks_total tasks, $error_count errors, $warn_count warnings" \
  "$summary_details"

# Terminal output
echo "" >&2
echo "============ RUN SUMMARY ============" >&2
echo " Ticket:    $ticket_id" >&2
echo " Status:    $status" >&2
echo " Tasks:     $tasks_completed / $tasks_total" >&2
echo " Errors:    $error_count" >&2
echo " Warnings:  $warn_count" >&2
echo " Events:    $event_count" >&2
if [[ -n "$pr_url" ]]; then
  echo " PR:        $pr_url" >&2
fi
if [[ -n "$duration_info" ]]; then
  echo " Duration:  $duration_info" >&2
fi
echo " Log:       runs/$ticket_id/run.log" >&2
echo "=====================================" >&2
echo "" >&2
