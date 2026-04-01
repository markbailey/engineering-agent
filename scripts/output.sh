#!/usr/bin/env bash
# output.sh — Standardized script output helpers
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/output.sh"

# Emit structured JSON result to stdout
# Usage: emit_result '{"key":"value"}'
emit_result() {
  local status="${1:-ok}"
  local data="${2:-null}"
  echo "{\"status\":\"$status\",\"data\":$data}"
}

# Emit structured JSON error to stderr and exit
# Usage: emit_error "something went wrong" [exit_code]
# WARNING: Do not call emit_error inside $() — exit only terminates the subshell.
# Instead: result=$(some_cmd) || emit_error "some_cmd failed"
emit_error() {
  local msg="$1"
  local code="${2:-1}"
  # Escape quotes in message
  msg=$(echo "$msg" | sed 's/"/\\"/g')
  echo "{\"status\":\"error\",\"error\":\"$msg\",\"exit_code\":$code}" >&2
  exit "$code"
}

# Platform detection (used by scripts needing OS-specific behavior)
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
IS_WINDOWS=false; IS_MACOS=false; IS_LINUX=false
case "$PLATFORM" in
  mingw*|msys*|cygwin*) IS_WINDOWS=true ;;
  darwin*) IS_MACOS=true ;;
  linux*) IS_LINUX=true ;;
esac
