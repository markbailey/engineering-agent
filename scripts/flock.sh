#!/usr/bin/env bash
# flock.sh — Cross-platform file locking via mkdir (atomic on all platforms)
# Source this file: source "$SCRIPT_DIR/flock.sh"

# with_lock <lockfile_path> <command...>
# Acquires mkdir-based lock, runs command, releases lock.
# Lock timeout: AGENT_LOCK_TIMEOUT env var (default 10s)
# Stale lock: if lockdir older than 5 minutes, auto-remove
with_lock() {
  local lockdir="$1.lock"
  shift
  local timeout="${AGENT_LOCK_TIMEOUT:-10}"
  local elapsed=0

  # Stale lock detection: if lockdir older than 5 minutes, remove it
  if [[ -d "$lockdir" ]]; then
    local lock_age
    if [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]]; then
      # Windows: use stat with different format
      lock_age=$(( $(date +%s) - $(stat -c %Y "$lockdir" 2>/dev/null || echo "0") ))
    elif [[ "$(uname -s)" == "Darwin" ]]; then
      lock_age=$(( $(date +%s) - $(stat -f %m "$lockdir" 2>/dev/null || echo "0") ))
    else
      lock_age=$(( $(date +%s) - $(stat -c %Y "$lockdir" 2>/dev/null || echo "0") ))
    fi
    if [[ "$lock_age" -gt 300 ]]; then
      rmdir "$lockdir" 2>/dev/null || true
    fi
  fi

  # Acquire lock
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      echo "{\"status\":\"error\",\"error\":\"lock timeout on $lockdir after ${timeout}s\",\"exit_code\":1}" >&2
      return 1
    fi
  done

  # Save existing EXIT trap, then set ours
  local _prev_trap
  _prev_trap=$(trap -p EXIT || true)
  trap "rmdir '$lockdir' 2>/dev/null; ${_prev_trap:+eval \"\${_prev_trap#trap -- }\";}" EXIT

  # Run command
  "$@"
  local rc=$?

  # Release lock and restore previous trap
  rmdir "$lockdir" 2>/dev/null
  if [[ -n "$_prev_trap" ]]; then
    eval "$_prev_trap"
  else
    trap - EXIT
  fi

  return $rc
}
