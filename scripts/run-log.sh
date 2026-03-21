#!/usr/bin/env bash
# run-log.sh — Structured run log writer
# Writes timestamped, leveled entries to /runs/TICKET-ID/run.log
#
# Usage:
#   run-log.sh <ticket_id> <level> <category> <message> [details_json]
#
# Levels: INFO, WARN, ERROR, EVENT
# Categories: startup, intake, planning, worktree, implementation, qa, review,
#             secrets, pr, monitor, conflict, cleanup, retry, agent, summary
#
# Output format (one JSON object per line — JSONL):
#   {"ts":"2026-03-21T14:30:00Z","level":"INFO","cat":"startup","msg":"...","details":{}}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ticket_id="${1:-}"
level="${2:-INFO}"
category="${3:-general}"
message="${4:-}"
details="${5:-}"

if [[ -z "$ticket_id" || -z "$message" ]]; then
  echo "Usage: run-log.sh <ticket_id> <level> <category> <message> [details_json]" >&2
  exit 1
fi

# Validate level
case "$level" in
  INFO|WARN|ERROR|EVENT) ;;
  *) echo "Invalid level: $level (use INFO|WARN|ERROR|EVENT)" >&2; exit 1 ;;
esac

# Ensure runs directory exists
run_dir="$AGENT_ROOT/runs/$ticket_id"
mkdir -p "$run_dir"

log_file="$run_dir/run.log"

# ISO 8601 timestamp
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# Escape message for JSON
escaped_msg=$(echo "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

# Build log entry
if [[ -n "$details" ]]; then
  entry="{\"ts\":\"$ts\",\"level\":\"$level\",\"cat\":\"$category\",\"msg\":\"$escaped_msg\",\"details\":$details}"
else
  entry="{\"ts\":\"$ts\",\"level\":\"$level\",\"cat\":\"$category\",\"msg\":\"$escaped_msg\"}"
fi

# Append to log
echo "$entry" >> "$log_file"

# Also echo to stderr for terminal visibility
echo "[$level] [$category] $message" >&2
