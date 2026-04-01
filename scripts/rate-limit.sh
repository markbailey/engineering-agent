#!/usr/bin/env bash
# rate-limit.sh — GitHub API rate limit awareness
# Source this file, then call pre_gh_check before any gh command.
# Functions:
#   check_rate_limit [ticket_id] — query rate limit, sleep if low
#   pre_gh_check [ticket_id]     — alias for check_rate_limit

RATE_LIMIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# check_rate_limit [ticket_id]
# Calls gh api rate_limit, parses remaining/reset.
# If remaining < 10: computes wait, logs, sleeps.
# Outputs JSON: {"remaining":N,"reset_at":"...","waited":true/false}
check_rate_limit() {
  local ticket_id="${1:-}"
  local waited="false"

  # Fetch rate limit from GitHub API
  local raw
  raw=$(gh api rate_limit 2>/dev/null) || {
    echo '{"remaining":-1,"reset_at":"unknown","waited":false,"error":"gh api call failed"}'
    return 0
  }

  # Parse with python3
  local remaining reset_at
  remaining=$(echo "$raw" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['rate']['remaining'])" 2>/dev/null) || remaining="-1"
  reset_at=$(echo "$raw" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['rate']['reset'])" 2>/dev/null) || reset_at="0"

  # If remaining is -1 (parse failure or unusual auth), validate token format
  if [[ "$remaining" == "-1" ]]; then
    local gh_token
    gh_token=$(gh auth token 2>/dev/null) || gh_token=""
    if [[ -n "$gh_token" ]]; then
      # PATs start with ghp_ or github_pat_; fine-grained tokens with github_pat_
      # OAuth/app tokens may be base64-like; warn if format is unrecognised
      if [[ ! "$gh_token" =~ ^(ghp_|github_pat_|gho_|ghu_|ghs_|ghr_) ]]; then
        echo "[rate-limit] Warning: GitHub token format unrecognised (not ghp_/github_pat_/gho_/ghu_/ghs_/ghr_ prefix). Rate limit check may be unreliable." >&2
      fi
    fi
  fi

  # If remaining < 10, compute wait and sleep
  if [[ "$remaining" -ge 0 && "$remaining" -lt 10 ]]; then
    local now wait_secs
    now=$(date +%s 2>/dev/null || echo "0")
    wait_secs=$((reset_at - now))
    if [[ "$wait_secs" -lt 0 ]]; then
      wait_secs=0
    fi
    # Cap wait at 120s to avoid indefinite hangs
    if [[ "$wait_secs" -gt 120 ]]; then
      wait_secs=120
    fi

    # Log if ticket_id provided
    if [[ -n "$ticket_id" ]]; then
      "$RATE_LIMIT_SCRIPT_DIR/run-log.sh" "$ticket_id" "WARN" "retry" \
        "Rate limit low ($remaining remaining). Waiting ${wait_secs}s until reset." \
        "{\"remaining\":$remaining,\"reset_at\":$reset_at,\"wait_secs\":$wait_secs}" 2>/dev/null || true
    fi

    echo "[rate-limit] Low remaining ($remaining). Sleeping ${wait_secs}s..." >&2
    if [[ "$wait_secs" -gt 0 ]]; then
      sleep "$wait_secs"
    fi
    waited="true"
  fi

  # Convert epoch reset_at to ISO string
  local reset_iso
  reset_iso=$(python3 -c "import datetime; print(datetime.datetime.utcfromtimestamp($reset_at).strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null) || reset_iso="$reset_at"

  echo "{\"remaining\":$remaining,\"reset_at\":\"$reset_iso\",\"waited\":$waited}"
}

# pre_gh_check [ticket_id] — call before any gh command
pre_gh_check() {
  check_rate_limit "${1:-}" > /dev/null
}
