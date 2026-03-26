#!/usr/bin/env bash
source "$(dirname "$0")/test-helpers.sh"
WT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== emit_error integration tests ==="

# Check scripts source output.sh
assert_contains "$(cat "$WT_ROOT/scripts/resolve-repo.sh")" "output.sh" "resolve-repo.sh sources output.sh"
assert_contains "$(cat "$WT_ROOT/scripts/validate-branch-name.sh")" "output.sh" "validate-branch-name.sh sources output.sh"
assert_contains "$(cat "$WT_ROOT/scripts/merge-base-into-feature.sh")" "output.sh" "merge-base-into-feature.sh sources output.sh"

# Check scripts use emit_error
assert_contains "$(cat "$WT_ROOT/scripts/resolve-repo.sh")" "emit_error" "resolve-repo.sh uses emit_error"
assert_contains "$(cat "$WT_ROOT/scripts/validate-branch-name.sh")" "emit_error" "validate-branch-name.sh uses emit_error"
assert_contains "$(cat "$WT_ROOT/scripts/merge-base-into-feature.sh")" "emit_error" "merge-base-into-feature.sh uses emit_error"

test_summary
