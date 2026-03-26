#!/usr/bin/env bash
source "$(dirname "$0")/test-helpers.sh"
WT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== validate-schemas.js tests ==="

# Mode 1: all schemas valid
output=$(node "$WT_ROOT/scripts/validate-schemas.js" 2>&1)
exit_code=$?
assert_exit "$exit_code" 0 "all schemas compile successfully"
assert_contains "$output" '"valid": true' "mode 1 reports valid"

# Mode 2: valid data (use a simple test)
# Create temp valid JSON matching a known schema
tmpfile=$(mktemp /tmp/test-valid-XXXXXX.json)
echo '{"version":1,"last_updated":"2026-01-01T00:00:00Z","entries":[]}' > "$tmpfile"
output2=$(node "$WT_ROOT/scripts/validate-schemas.js" "$tmpfile" "agent-learning" 2>&1)
exit_code2=$?
assert_exit "$exit_code2" 0 "valid data passes validation"
rm -f "$tmpfile"

# Mode 2: invalid data
tmpfile2=$(mktemp /tmp/test-invalid-XXXXXX.json)
echo '{"version":"not-a-number"}' > "$tmpfile2"
output3=$(node "$WT_ROOT/scripts/validate-schemas.js" "$tmpfile2" "agent-learning" 2>&1)
exit_code3=$?
assert_exit "$exit_code3" 1 "invalid data fails validation"
# Check .invalid.json was created
if [[ -f "${tmpfile2}.invalid.json" ]]; then
  echo "  PASS: .invalid.json created"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1))
else
  echo "  FAIL: .invalid.json not created"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1))
fi
rm -f "$tmpfile2" "${tmpfile2}.invalid.json"

test_summary
