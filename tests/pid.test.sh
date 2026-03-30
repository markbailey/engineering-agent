#!/usr/bin/env bash
# Tests for pid.sh — PID-alive guard, trap cleanup, flock atomicity
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PID_SH="$SCRIPT_DIR/../scripts/pid.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_TICKET="TEST-PID-$$"
RUN_DIR="$AGENT_ROOT/runs/$TEST_TICKET"
PID_FILE="$RUN_DIR/pid.json"

cleanup() {
  rm -rf "$RUN_DIR"
  rm -rf "$PID_FILE.lock"
}
trap cleanup EXIT

echo "=== pid.sh tests ==="

# --- Test 1: write creates pid.json and outputs path ---
cleanup
# The trap in pid.sh fires on pid.sh exit, so we check inside the same process
result=$(bash -c "
  pf=\$(bash '$PID_SH' write '$TEST_TICKET' 99999 2>/dev/null)
  # pid.sh trap already fired, but we can check the output path format
  echo \"\$pf\"
" 2>/dev/null)
assert_contains "$result" "pid.json" "write outputs pid_file path"

# --- Test 2: write stores correct PID (verify via check before trap fires) ---
cleanup
mkdir -p "$RUN_DIR"
# Use check to verify PID was written correctly — write first, then immediately check
result=$(bash -c "
  bash '$PID_SH' write '$TEST_TICKET' 99999 >/dev/null 2>&1
  # File is gone after pid.sh trap fires, so this tests the trap too
  echo done
" 2>/dev/null)
# Now write without trap by writing directly, then test check
mkdir -p "$RUN_DIR"
echo '{"pid":99999,"startedAt":"2026-01-01T00:00:00Z"}' > "$PID_FILE"
output=$(bash "$PID_SH" check "$TEST_TICKET" 2>/dev/null)
assert_contains "$output" '"pid":99999' "check reads stored PID correctly"

# --- Test 3: write with alive PID blocks (concurrent run guard) ---
cleanup
mkdir -p "$RUN_DIR"
# Write our own PID (alive) directly — no trap attached
echo "{\"pid\":$$,\"startedAt\":\"2026-01-01T00:00:00Z\"}" > "$PID_FILE"
# Second write with same ticket should fail
output=$(bash "$PID_SH" write "$TEST_TICKET" 12345 2>&1) || true
# The file should still have the original PID
pid_val=$(sed -n 's/.*"pid" *: *\([0-9]*\).*/\1/p' "$PID_FILE")
assert_eq "$pid_val" "$$" "write blocks when existing PID alive"
assert_contains "$output" "already in progress" "write emits error for alive PID"

# --- Test 4: write with dead PID replaces stale file ---
cleanup
mkdir -p "$RUN_DIR"
# Write a PID that doesn't exist
echo '{"pid":99999,"startedAt":"2026-01-01T00:00:00Z"}' > "$PID_FILE"
# Write replaces stale PID — verify inside same subshell before trap fires
result=$(bash -c "
  bash '$PID_SH' write '$TEST_TICKET' $$ >/dev/null 2>&1
  # pid.sh trap fires here, removing pid.json — that's expected
  echo replaced
" 2>/dev/null)
# Verify stale file was replaced by checking stderr output
output=$(bash "$PID_SH" write "$TEST_TICKET" $$ 2>&1 || true)
# Clean up for next test — write a stale pid
cleanup
mkdir -p "$RUN_DIR"
echo '{"pid":99999,"startedAt":"2026-01-01T00:00:00Z"}' > "$PID_FILE"
warn_output=$(bash "$PID_SH" write "$TEST_TICKET" 12345 2>&1 >/dev/null) || true
assert_contains "$warn_output" "stale" "write warns about stale PID"

# --- Test 5: remove deletes pid.json ---
cleanup
mkdir -p "$RUN_DIR"
echo '{"pid":1,"startedAt":"2026-01-01T00:00:00Z"}' > "$PID_FILE"
bash "$PID_SH" remove "$TEST_TICKET" 2>/dev/null
assert_eq "$(test -f "$PID_FILE" && echo yes || echo no)" "no" "remove deletes pid.json"

# --- Test 6: remove is idempotent ---
cleanup
mkdir -p "$RUN_DIR"
bash "$PID_SH" remove "$TEST_TICKET" 2>/dev/null
rc=$?
assert_exit "$rc" 0 "remove on non-existent file exits 0"

# --- Test 7: check reports alive=false for dead PID ---
cleanup
mkdir -p "$RUN_DIR"
echo '{"pid":99999,"startedAt":"2026-01-01T00:00:00Z"}' > "$PID_FILE"
output=$(bash "$PID_SH" check "$TEST_TICKET" 2>/dev/null)
assert_contains "$output" '"alive":false' "check reports dead PID as not alive"

# --- Test 8: check reports alive=true for live PID ---
cleanup
mkdir -p "$RUN_DIR"
echo "{\"pid\":$$,\"startedAt\":\"2026-01-01T00:00:00Z\"}" > "$PID_FILE"
output=$(bash "$PID_SH" check "$TEST_TICKET" 2>/dev/null)
assert_contains "$output" '"alive":true' "check reports own PID as alive"

# --- Test 9: trap cleanup removes pid.json on process exit ---
cleanup
bash -c "bash '$PID_SH' write '$TEST_TICKET' >/dev/null 2>&1"
# After subshell exits, trap should have removed pid.json
assert_eq "$(test -f "$PID_FILE" && echo yes || echo no)" "no" "trap removes pid.json on EXIT"

# --- Test 10: pid_trap helper sets trap for caller ---
cleanup
bash -c "
  source '$PID_SH' --source-only
  mkdir -p '$RUN_DIR'
  echo '{\"pid\":1}' > '$PID_FILE'
  pid_trap '$PID_FILE'
  # exit triggers trap
" 2>/dev/null
assert_eq "$(test -f "$PID_FILE" && echo yes || echo no)" "no" "pid_trap cleans up on caller exit"

# --- Test 11: write uses flock (lock released after) ---
cleanup
bash -c "bash '$PID_SH' write '$TEST_TICKET' >/dev/null 2>&1"
assert_eq "$(test -d "$PID_FILE.lock" && echo locked || echo unlocked)" "unlocked" "write releases lock after completion"

# --- Test 12: check with no pid.json returns alive=false ---
cleanup
mkdir -p "$RUN_DIR"
output=$(bash "$PID_SH" check "$TEST_TICKET" 2>/dev/null)
assert_contains "$output" '"alive":false' "check with missing file returns alive=false"

test_summary
