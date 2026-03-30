#!/usr/bin/env bash
source "$(dirname "$0")/test-helpers.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
source "$SCRIPT_DIR/flock.sh"

echo "=== flock.sh tests ==="

TMPDIR=$(mktemp -d)

# Test 1: with_lock runs command successfully
output=$(with_lock "$TMPDIR/test1" echo "locked_output")
assert_contains "$output" "locked_output" "with_lock passes through command output"

# Test 2: lock is released after command
with_lock "$TMPDIR/test2" true
if [[ ! -d "$TMPDIR/test2.lock" ]]; then
  echo "  PASS: lock released after command"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1))
else
  echo "  FAIL: lock not released"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1))
fi

# Test 3: exit code preserved
with_lock "$TMPDIR/test3" bash -c "exit 42" || exit_code=$?
assert_exit "${exit_code:-0}" 42 "with_lock preserves exit code"

# Test 4: stale lock detection (create old lockdir)
mkdir -p "$TMPDIR/test4.lock"
# Touch with old timestamp (> 5 min ago)
touch -t 202601010000 "$TMPDIR/test4.lock" 2>/dev/null || true
output4=$(AGENT_LOCK_TIMEOUT=2 with_lock "$TMPDIR/test4" echo "stale_cleaned")
assert_contains "$output4" "stale_cleaned" "stale lock auto-cleaned"

# Test 5: lock timeout
mkdir -p "$TMPDIR/test5.lock"
AGENT_LOCK_TIMEOUT=2 with_lock "$TMPDIR/test5" echo "should_not_reach" 2>/dev/null
timeout_exit=$?
assert_exit "$timeout_exit" 1 "lock timeout returns 1"
rmdir "$TMPDIR/test5.lock" 2>/dev/null

rm -rf "$TMPDIR"
test_summary
