#!/usr/bin/env bash
# Tests for with-timeout.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

TIMEOUT_SH="$SCRIPT_DIR/../scripts/with-timeout.sh"

echo "=== with-timeout.sh tests ==="

# 1. Fast command passes through
output=$(bash "$TIMEOUT_SH" 5 echo "hello" 2>&1)
exit_code=$?
assert_exit "$exit_code" 0 "fast command exits 0"
assert_contains "$output" "hello" "fast command output contains hello"

# 2. Timeout kills and exits 124
output=$(bash "$TIMEOUT_SH" 2 sleep 10 2>&1)
exit_code=$?
assert_exit "$exit_code" 124 "timed-out command exits 124"

# 3. Command exit code preserved
bash "$TIMEOUT_SH" 5 bash -c "exit 42" 2>&1
exit_code=$?
assert_exit "$exit_code" 42 "command exit code 42 preserved"

test_summary
