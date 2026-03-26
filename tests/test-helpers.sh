#!/usr/bin/env bash
PASS=0; FAIL=0; TOTAL=0
assert_eq() { TOTAL=$((TOTAL+1)); if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); echo "  PASS: $3"; else FAIL=$((FAIL+1)); echo "  FAIL: $3 (expected '$2', got '$1')"; fi; }
assert_exit() { TOTAL=$((TOTAL+1)); if [[ "$1" -eq "$2" ]]; then PASS=$((PASS+1)); echo "  PASS: $3"; else FAIL=$((FAIL+1)); echo "  FAIL: $3 (expected exit $2, got $1)"; fi; }
assert_contains() { TOTAL=$((TOTAL+1)); if echo "$1" | grep -q "$2"; then PASS=$((PASS+1)); echo "  PASS: $3"; else FAIL=$((FAIL+1)); echo "  FAIL: $3 (output did not contain '$2')"; fi; }
test_summary() { echo ""; echo "Results: $PASS/$TOTAL passed, $FAIL failed"; [[ $FAIL -eq 0 ]]; }
