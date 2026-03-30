#!/usr/bin/env bash
# portability.test.sh — Cross-platform portability checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Portability Tests ==="

# Test 1: No grep -P in any script
grep_p_count=$(grep -r 'grep -P' "$REPO_ROOT/scripts/"*.sh 2>/dev/null | wc -l || true)
assert_eq "$(echo "$grep_p_count" | tr -d '[:space:]')" "0" "no grep -P in scripts"

# Test 2: No hardcoded C:\ paths in any script
hardcoded_paths=$(grep -rE 'C:\\|/c/Users/' "$REPO_ROOT/scripts/"*.sh 2>/dev/null | wc -l || true)
assert_eq "$(echo "$hardcoded_paths" | tr -d '[:space:]')" "0" "no hardcoded Windows paths in scripts"

# Test 3: No date -d in any script
date_d_count=$(grep -rE 'date -d ' "$REPO_ROOT/scripts/"*.sh 2>/dev/null | wc -l || true)
assert_eq "$(echo "$date_d_count" | tr -d '[:space:]')" "0" "no GNU-only date -d in scripts"

# Test 4: output.sh has platform detection vars
has_is_windows=$(grep -c 'IS_WINDOWS' "$REPO_ROOT/scripts/output.sh" 2>/dev/null || echo "0")
has_is_macos=$(grep -c 'IS_MACOS' "$REPO_ROOT/scripts/output.sh" 2>/dev/null || echo "0")
has_is_linux=$(grep -c 'IS_LINUX' "$REPO_ROOT/scripts/output.sh" 2>/dev/null || echo "0")
TOTAL=$((TOTAL+1))
if [[ "$has_is_windows" -gt 0 && "$has_is_macos" -gt 0 && "$has_is_linux" -gt 0 ]]; then
  PASS=$((PASS+1)); echo "  PASS: output.sh has platform detection vars"
else
  FAIL=$((FAIL+1)); echo "  FAIL: output.sh missing platform detection vars"
fi

# Test 5: run-secret-scan.sh uses dynamic gitleaks resolution
has_command_v=$(grep -c 'command -v gitleaks' "$REPO_ROOT/scripts/run-secret-scan.sh" 2>/dev/null || echo "0")
TOTAL=$((TOTAL+1))
if [[ "$has_command_v" -gt 0 ]]; then
  PASS=$((PASS+1)); echo "  PASS: run-secret-scan.sh uses dynamic gitleaks resolution"
else
  FAIL=$((FAIL+1)); echo "  FAIL: run-secret-scan.sh missing dynamic gitleaks resolution"
fi

test_summary
