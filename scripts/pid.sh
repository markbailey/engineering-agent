#!/usr/bin/env bash
# pid.sh — Manage PID files for agent runs
#
# Usage:
#   pid.sh write <ticket_id> [pid]  — write pid.json with PID-alive guard (atomic via flock)
#   pid.sh remove <ticket_id>       — delete pid.json and verify removal
#   pid.sh check <ticket_id>        — check if PID is alive (returns JSON)
#
# Write outputs the pid_file path on stdout for trap setup by the caller:
#   pid_file=$(pid.sh write TICKET-1)
#   trap "rm -f '$pid_file'" EXIT INT TERM
#
# Source this file for the pid_trap helper:
#   source scripts/pid.sh --source-only
#   pid_file=$(scripts/pid.sh write TICKET-1)
#   pid_trap "$pid_file"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/flock.sh"

# pid_trap — set EXIT/INT/TERM trap to remove a pid file
# Usage: pid_trap /path/to/pid.json
pid_trap() {
  local pf="$1"
  trap "rm -f '$pf'" EXIT INT TERM
}

# If sourced with --source-only, export helpers and return
if [[ "${1:-}" == "--source-only" ]]; then
  return 0 2>/dev/null || exit 0
fi

subcommand="${1:-}"
ticket_id="${2:-}"

if [[ -z "$subcommand" || -z "$ticket_id" ]]; then
  echo "Usage: pid.sh <write|remove|check> <ticket_id>" >&2
  exit 1
fi

run_dir="$AGENT_ROOT/runs/$ticket_id"
pid_file="$run_dir/pid.json"

# Internal: atomic check-and-write (called under lock)
_pid_write_inner() {
  local target_pid="$1"

  # Check for existing PID file
  if [[ -f "$pid_file" ]]; then
    local existing_pid
    existing_pid=$(sed -n 's/.*"pid" *: *\([0-9]*\).*/\1/p' "$pid_file")
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      echo "{\"status\":\"error\",\"error\":\"Run already in progress for ticket $ticket_id (PID: $existing_pid)\"}" >&2
      return 1
    fi
    # Stale PID — remove and proceed
    echo "{\"status\":\"warn\",\"message\":\"Removing stale pid.json (PID $existing_pid dead)\"}" >&2
    rm -f "$pid_file"
  fi

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  echo "{\"pid\":$target_pid,\"startedAt\":\"$ts\"}" > "$pid_file"
}

case "$subcommand" in
  write)
    target_pid="${3:-$$}"
    mkdir -p "$run_dir"
    with_lock "$pid_file" _pid_write_inner "$target_pid"

    # Output pid_file path so caller can set trap
    echo "$pid_file"

    # Set trap for this process (useful when script is the long-running process)
    trap "rm -f '$pid_file'" EXIT INT TERM
    ;;

  remove)
    rm -f "$pid_file"
    # Verify removal
    if [[ -f "$pid_file" ]]; then
      echo "{\"status\":\"error\",\"error\":\"Failed to remove $pid_file\"}" >&2
      exit 1
    fi
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
