#!/usr/bin/env bash
source "$(dirname "$0")/test-helpers.sh"
WT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== concurrency integration tests ==="

# Verify flock.sh is sourced in shared state scripts
assert_contains "$(cat "$WT_ROOT/scripts/agent-learning.sh")" "flock.sh" "agent-learning.sh sources flock.sh"
assert_contains "$(cat "$WT_ROOT/scripts/auto-repair.sh")" "flock.sh" "auto-repair.sh sources flock.sh"
assert_contains "$(cat "$WT_ROOT/scripts/check-loop-limit.sh")" "flock.sh" "check-loop-limit.sh sources flock.sh"
assert_contains "$(cat "$WT_ROOT/scripts/check-retry-limit.sh")" "flock.sh" "check-retry-limit.sh sources flock.sh"

# Verify with_lock usage
assert_contains "$(cat "$WT_ROOT/scripts/agent-learning.sh")" "with_lock" "agent-learning.sh uses with_lock"
assert_contains "$(cat "$WT_ROOT/scripts/auto-repair.sh")" "with_lock" "auto-repair.sh uses with_lock"
assert_contains "$(cat "$WT_ROOT/scripts/pid.sh")" "flock.sh" "pid.sh sources flock.sh"

test_summary
