#!/usr/bin/env bash
# pid.sh — Manage PID files for agent runs
#
# Usage:
#   pid.sh write <ticket_id>    — write pid.json with current PID
#   pid.sh remove <ticket_id>   — delete pid.json
#   pid.sh check <ticket_id>    — check if PID is alive (returns JSON)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

subcommand="${1:-}"
ticket_id="${2:-}"

if [[ -z "$subcommand" || -z "$ticket_id" ]]; then
  echo "Usage: pid.sh <write|remove|check> <ticket_id>" >&2
  exit 1
fi

run_dir="$AGENT_ROOT/runs/$ticket_id"
pid_file="$run_dir/pid.json"

case "$subcommand" in
  write)
    mkdir -p "$run_dir"
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"pid\":$$,\"startedAt\":\"$ts\"}" > "$pid_file"
    ;;

  remove)
    rm -f "$pid_file"
    ;;

  check)
    if [[ ! -f "$pid_file" ]]; then
      echo '{"alive":false}'
      exit 0
    fi

    # Parse pid and startedAt from JSON (minimal, no jq dependency)
    pid=$(sed -n 's/.*"pid" *: *\([0-9]*\).*/\1/p' "$pid_file")
    startedAt=$(sed -n 's/.*"startedAt" *: *"\([^"]*\)".*/\1/p' "$pid_file")

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      alive=true
    else
      alive=false
    fi

    echo "{\"alive\":$alive,\"pid\":$pid,\"startedAt\":\"$startedAt\"}"
    ;;

  *)
    echo "Unknown subcommand: $subcommand (use write|remove|check)" >&2
    exit 1
    ;;
esac
