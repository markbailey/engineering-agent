#!/usr/bin/env bash
# Tests for flaky-test.sh, orphan-check.sh --prd, conflict-resolution.sh TS fallback

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLAKY="$ROOT/scripts/flaky-test.sh"

# Setup: clean registry dir
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== flaky-test.sh tests ==="

# Test 1: check unknown test returns flaky: false
echo "--- Test: check unknown test ---"
out=$(bash "$FLAKY" check "some.unknown.test" "test-repo" 2>&1)
flaky=$(echo "$out" | node -e "process.stdin.on('data',d=>console.log(JSON.parse(d).flaky))")
assert_eq "$flaky" "false" "unknown test returns flaky: false"

# Test 2: record + check cycle
echo "--- Test: record then check ---"
bash "$FLAKY" record "my.flaky.test" "test-repo" --file "src/test.ts" > /dev/null 2>&1
out=$(bash "$FLAKY" check "my.flaky.test" "test-repo" 2>&1)
flaky=$(echo "$out" | node -e "process.stdin.on('data',d=>console.log(JSON.parse(d).flaky))")
assert_eq "$flaky" "true" "recorded test returns flaky: true"

# Test 3: record increments occurrences
echo "--- Test: record increments occurrences ---"
bash "$FLAKY" record "my.flaky.test" "test-repo" > /dev/null 2>&1
reg="$ROOT/runs/flaky-tests/test-repo.json"
occ=$(node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(d.entries[0].occurrences)" "$reg")
assert_eq "$occ" "2" "occurrences incremented to 2"

# Test 4: retry placeholder
echo "--- Test: retry placeholder ---"
out=$(bash "$FLAKY" retry "TEST-1" "test-repo" 2>&1)
retried=$(echo "$out" | node -e "process.stdin.on('data',d=>console.log(JSON.parse(d).retried))")
assert_eq "$retried" "0" "retry returns retried: 0"

# Test 5: orphan-check.sh accepts --prd flag
echo "--- Test: orphan-check.sh --prd flag ---"
out=$(grep -c "\-\-prd" "$ROOT/scripts/orphan-check.sh")
assert_contains "$out" "[1-9]" "orphan-check.sh contains --prd handling"

# Test 6: conflict-resolution.sh has TS orphan check fallback
echo "--- Test: conflict-resolution.sh TS fallback ---"
assert_contains "$(cat "$ROOT/scripts/conflict-resolution.sh")" "orphan-check-ts.js" "conflict-resolution.sh references orphan-check-ts.js"
assert_contains "$(cat "$ROOT/scripts/conflict-resolution.sh")" "falling back" "conflict-resolution.sh has fallback logic"

# Cleanup test registry
rm -rf "$ROOT/runs/flaky-tests/test-repo.json"

test_summary
