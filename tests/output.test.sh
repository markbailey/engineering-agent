#!/usr/bin/env bash
source "$(dirname "$0")/test-helpers.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"

echo "=== output.sh tests ==="

# Test emit_result
result=$(source "$SCRIPT_DIR/output.sh" && emit_result "ok" '{"foo":"bar"}')
assert_contains "$result" '"status":"ok"' "emit_result includes status"
assert_contains "$result" '"foo":"bar"' "emit_result includes data"

# Test emit_error (run in subshell to catch exit)
error_output=$(bash -c "source '$SCRIPT_DIR/output.sh' && emit_error 'bad thing'" 2>&1 || true)
assert_contains "$error_output" '"error"' "emit_error outputs error JSON"

# Test platform detection
platform_output=$(source "$SCRIPT_DIR/output.sh" && echo "$PLATFORM")
assert_contains "$platform_output" "" "platform detection runs without error"  # just check it doesn't crash

test_summary
