#!/usr/bin/env bash
# Tests that modified scripts reference with-timeout.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SCRIPTS_DIR="$SCRIPT_DIR/../scripts"

echo "=== timeout integration tests ==="

# 1. regression-guard.sh contains with-timeout.sh
grep -q "with-timeout.sh" "$SCRIPTS_DIR/regression-guard.sh" 2>/dev/null
assert_exit "$?" 0 "regression-guard.sh references with-timeout.sh"

# 2. worktree-init.sh contains with-timeout.sh
grep -q "with-timeout.sh" "$SCRIPTS_DIR/worktree-init.sh" 2>/dev/null
assert_exit "$?" 0 "worktree-init.sh references with-timeout.sh"

# 3. orphan-check.sh contains with-timeout.sh
grep -q "with-timeout.sh" "$SCRIPTS_DIR/orphan-check.sh" 2>/dev/null
assert_exit "$?" 0 "orphan-check.sh references with-timeout.sh"

# 4. run-secret-scan.sh contains with-timeout.sh
grep -q "with-timeout.sh" "$SCRIPTS_DIR/run-secret-scan.sh" 2>/dev/null
assert_exit "$?" 0 "run-secret-scan.sh references with-timeout.sh"

# 5. notify.sh contains timeout) case entry
grep -q 'timeout)' "$SCRIPTS_DIR/notify.sh" 2>/dev/null
assert_exit "$?" 0 "notify.sh contains timeout) case entry"

test_summary
