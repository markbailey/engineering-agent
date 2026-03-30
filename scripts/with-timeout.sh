#!/usr/bin/env bash
# with-timeout.sh — Cross-platform command timeout wrapper
#
# Usage:
#   with-timeout.sh <timeout_seconds> <command...>
#
# Platform detection:
#   Linux:              GNU coreutils `timeout`
#   macOS:              `gtimeout` (brew install coreutils)
#   Windows/MSYS/Git Bash: background process + sleep + kill
#
# On timeout: kills process tree, exits 124
# On success: passthrough stdout/stderr, exits with command's exit code
#
# Env override: AGENT_COMMAND_TIMEOUT overrides <timeout_seconds> if set

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: with-timeout.sh <timeout_seconds> <command...>" >&2
  exit 1
fi

timeout_secs="$1"
shift

# Env override
if [[ -n "${AGENT_COMMAND_TIMEOUT:-}" ]]; then
  timeout_secs="$AGENT_COMMAND_TIMEOUT"
fi

# Validate timeout is a positive integer
if ! [[ "$timeout_secs" =~ ^[0-9]+$ ]] || [[ "$timeout_secs" -eq 0 ]]; then
  echo "Error: timeout must be a positive integer, got '$timeout_secs'" >&2
  exit 1
fi

# Detect platform
detect_platform() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)
      # Fallback: check for common Windows env vars
      if [[ -n "${MSYSTEM:-}" || -n "${WINDIR:-}" ]]; then
        echo "windows"
      else
        echo "unknown"
      fi
      ;;
  esac
}

PLATFORM="$(detect_platform)"

# Kill process tree helper (best-effort, errors suppressed)
kill_tree() {
  local pid="$1"
  local signal="${2:-TERM}"

  case "$PLATFORM" in
    windows)
      # On Windows/MSYS, use taskkill for tree kill if available
      if command -v taskkill.exe &>/dev/null; then
        taskkill.exe //F //T //PID "$pid" &>/dev/null || true
      else
        kill -"$signal" "$pid" &>/dev/null || true
      fi
      ;;
    *)
      # POSIX: kill the process group
      kill -"$signal" -- -"$pid" &>/dev/null || true
      ;;
  esac
}

# --- Linux: GNU timeout with --kill-after for cleanup ---
if [[ "$PLATFORM" == "linux" ]]; then
  if command -v timeout &>/dev/null; then
    set +e
    timeout --kill-after=5 "$timeout_secs" "$@"
    exit_code=$?
    set -e
    exit "$exit_code"
  fi
fi

# --- macOS: gtimeout from coreutils ---
if [[ "$PLATFORM" == "macos" ]]; then
  if command -v gtimeout &>/dev/null; then
    set +e
    gtimeout --kill-after=5 "$timeout_secs" "$@"
    exit_code=$?
    set -e
    exit "$exit_code"
  fi
  # Fallback to background approach if gtimeout not installed
fi

# --- Fallback: background process + sleep + kill (Windows/MSYS/unknown) ---

# Use a marker file to reliably detect timeout (MSYS wait doesn't report signals)
TIMEOUT_MARKER="$(mktemp "${TMPDIR:-/tmp}/with-timeout.XXXXXX")"
rm -f "$TIMEOUT_MARKER"
trap 'rm -f "$TIMEOUT_MARKER"' EXIT

# Run command in background in its own process group where possible
set +e
if [[ "$PLATFORM" != "windows" ]]; then
  if command -v setsid &>/dev/null; then
    setsid "$@" &
  else
    "$@" &
  fi
else
  "$@" &
fi
CMD_PID=$!
set -e

# Watchdog: sleep then kill, create marker to signal timeout occurred
(
  sleep "$timeout_secs"
  touch "$TIMEOUT_MARKER"
  kill_tree "$CMD_PID" TERM
  # Grace period then force kill
  sleep 2
  kill_tree "$CMD_PID" KILL
) &>/dev/null &
WATCHDOG_PID=$!

# Wait for the command to finish
set +e
wait "$CMD_PID"
CMD_EXIT=$?
set -e

# Clean up watchdog — command finished before timeout
kill "$WATCHDOG_PID" &>/dev/null || true
wait "$WATCHDOG_PID" &>/dev/null || true

# If marker exists, timeout occurred — exit 124 regardless of wait's reported code
if [[ -f "$TIMEOUT_MARKER" ]]; then
  rm -f "$TIMEOUT_MARKER"
  exit 124
fi

# Also check signal-killed exit codes (128+SIGTERM=143, 128+SIGKILL=137)
if [[ $CMD_EXIT -eq 143 || $CMD_EXIT -eq 137 ]]; then
  exit 124
fi

exit "$CMD_EXIT"
