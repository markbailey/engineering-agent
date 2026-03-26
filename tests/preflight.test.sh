#!/usr/bin/env bash
# Tests for preflight.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PREFLIGHT_SH="$SCRIPT_DIR/../scripts/preflight.sh"

echo "=== preflight.sh tests ==="

# Run preflight (may exit non-zero if checks fail — that's OK)
output=$(bash "$PREFLIGHT_SH" 2>/dev/null) || true

# 1. Output is valid JSON
node -e "JSON.parse(process.argv[1])" "$output" &>/dev/null
assert_exit "$?" 0 "output is valid JSON"

# 2. Output has 'overall' field
has_overall=$(node -e "const o=JSON.parse(process.argv[1]); process.stdout.write(typeof o.overall === 'string' ? 'yes' : 'no')" "$output" 2>/dev/null) || has_overall="no"
assert_eq "$has_overall" "yes" "output has 'overall' field"

# 3. Output has 'checks' array
has_checks=$(node -e "const o=JSON.parse(process.argv[1]); process.stdout.write(Array.isArray(o.checks) ? 'yes' : 'no')" "$output" 2>/dev/null) || has_checks="no"
assert_eq "$has_checks" "yes" "output has 'checks' array"

test_summary
