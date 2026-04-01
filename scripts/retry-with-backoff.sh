#!/usr/bin/env bash
# retry-with-backoff.sh — Exponential backoff retry wrapper
# Args: [--ticket=ID] $1=max_retries $2=base_delay_ms -- command args...
# Backoff: base, base*4, base*15 (≈2s, 8s, 30s with defaults)
# Exit 0 on success, exit 1 on exhaustion

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env for defaults
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

# Source rate-limit.sh once (used inside retry loop for rate-limit detection)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/rate-limit.sh"

# Optional --ticket=ID for logging
ticket_id=""
if [[ "${1:-}" =~ ^--ticket=(.+)$ ]]; then
  ticket_id="${BASH_REMATCH[1]}"
  shift
fi

max_retries="${1:-${AGENT_RATE_LIMIT_MAX_RETRIES:-3}}"
base_delay_ms="${2:-${AGENT_RATE_LIMIT_BASE_DELAY_MS:-2000}}"

# Find the -- separator
shift 2 || true
if [[ "${1:-}" == "--" ]]; then
  shift
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: retry-with-backoff.sh [--ticket=ID] [max_retries] [base_delay_ms] -- command args..." >&2
  exit 1
fi

# Log helper — logs to run.log if ticket_id is set
log_retry() {
  local level="$1" msg="$2" details="$3"
  if [[ -n "$ticket_id" ]]; then
    "$SCRIPT_DIR/run-log.sh" "$ticket_id" "$level" "retry" "$msg" "$details" 2>/dev/null || true
  fi
}

# Backoff multipliers: 1x, 4x, 15x
multipliers=(1 4 15)
cmd_str="$*"

attempt=0
stderr_tmp=$(mktemp)
while [[ $attempt -lt $max_retries ]]; do
  attempt=$((attempt + 1))

  if "$@" 2>"$stderr_tmp"; then
    if [[ $attempt -gt 1 ]]; then
      log_retry "INFO" "Retry succeeded on attempt $attempt/$max_retries: $cmd_str" \
        "{\"attempt\":$attempt,\"max_retries\":$max_retries,\"command\":\"$cmd_str\"}"
    fi
    rm -f "$stderr_tmp"
    exit 0
  fi

  # Capture stderr for rate-limit detection
  local_stderr=$(cat "$stderr_tmp" 2>/dev/null || true)
  # Forward stderr so callers still see it
  [[ -n "$local_stderr" ]] && echo "$local_stderr" >&2

  if [[ $attempt -ge $max_retries ]]; then
    break
  fi

  # Detect rate limiting (HTTP 429, "rate limit", GitHub secondary limits)
  if echo "$local_stderr" | grep -qiE 'rate limit|429|secondary rate|abuse detection'; then
    echo "[retry] Rate limit detected. Checking GitHub rate limit reset..." >&2
    check_rate_limit "$ticket_id" > /dev/null
    log_retry "WARN" "Attempt $attempt/$max_retries rate-limited, waited for reset: $cmd_str" \
      "{\"attempt\":$attempt,\"max_retries\":$max_retries,\"command\":\"$cmd_str\",\"rate_limited\":true}"
    continue
  fi

  # Calculate delay
  mult_index=$((attempt - 1))
  if [[ $mult_index -ge ${#multipliers[@]} ]]; then
    mult_index=$(( ${#multipliers[@]} - 1 ))
  fi
  delay_ms=$(( base_delay_ms * ${multipliers[$mult_index]} ))
  # Add jitter: 0-30% random addition to prevent synchronized retries
  jitter=$((RANDOM % (delay_ms * 30 / 100 + 1)))
  delay_ms=$((delay_ms + jitter))
  delay_s=$(echo "scale=1; $delay_ms / 1000" | bc 2>/dev/null || echo "$((delay_ms / 1000))")

  echo "[retry] Attempt $attempt/$max_retries failed. Retrying in ${delay_s}s..." >&2
  log_retry "WARN" "Attempt $attempt/$max_retries failed, retrying in ${delay_s}s: $cmd_str" \
    "{\"attempt\":$attempt,\"max_retries\":$max_retries,\"delay_ms\":$delay_ms,\"jitter_ms\":$jitter,\"command\":\"$cmd_str\"}"
  sleep "$((delay_ms / 1000))"
done
rm -f "$stderr_tmp"

echo "[retry] All $max_retries attempts exhausted." >&2
log_retry "ERROR" "All $max_retries attempts exhausted: $cmd_str" \
  "{\"attempt\":$max_retries,\"max_retries\":$max_retries,\"command\":\"$cmd_str\"}"

# Notify on exhaustion
if [[ -n "$ticket_id" ]]; then
  "$SCRIPT_DIR/notify.sh" "$ticket_id" "rate_limit" \
    "Rate limit retries exhausted ($max_retries attempts): $cmd_str" \
    "{\"attempts\":$max_retries}" 2>/dev/null || true
fi

exit 1
