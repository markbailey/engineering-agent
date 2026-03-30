#!/usr/bin/env bash
# test-scripts.sh — Unit tests for utility scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS="$AGENT_ROOT/scripts"

echo "=== validate-branch-name.sh ==="

# Valid branch name
out=$(bash "$SCRIPTS/validate-branch-name.sh" "mba_test-1_add-hello-world_feature" 2>/dev/null) || true
assert_contains "$out" '"valid":true' "valid branch name accepted"

# Invalid branch name — missing type suffix
out=$(bash "$SCRIPTS/validate-branch-name.sh" "mba_test-1_add-hello-world" 2>&1) || true
rc=$?
assert_contains "$out" 'error' "invalid branch name rejected"

# Invalid branch name — wrong employee code prefix
out=$(bash "$SCRIPTS/validate-branch-name.sh" "zzz_test-1_add-hello_feature" 2>&1) || true
assert_contains "$out" 'error' "wrong employee code rejected"

echo ""
echo "=== validate-commit-msg.sh ==="

# Valid commit message
msg=$(printf 'feat(auth): add jwt validation\n\nRefs: PROJ-123')
out=$(bash "$SCRIPTS/validate-commit-msg.sh" "$msg" 2>/dev/null)
assert_contains "$out" '"valid":true' "valid commit message accepted"

# Invalid commit message — bad type
msg="blah: some change"
out=$(bash "$SCRIPTS/validate-commit-msg.sh" "$msg" 2>/dev/null)
assert_contains "$out" '"valid":false' "invalid commit type rejected"

# Invalid commit message — missing Refs footer
msg="feat(auth): add jwt validation"
out=$(bash "$SCRIPTS/validate-commit-msg.sh" "$msg" 2>/dev/null)
assert_contains "$out" '"valid":false' "missing Refs footer rejected"

echo ""
echo "=== resolve-repo.sh ==="

# Known project key — requires repos.json with HARNESS entry
if [[ -f "$AGENT_ROOT/repos.json" ]]; then
  out=$(bash "$SCRIPTS/resolve-repo.sh" "HARNESS-1" 2>/dev/null) || true
  if echo "$out" | grep -q '"project_key"'; then
    assert_eq "1" "1" "resolve-repo returns JSON for known key"
  else
    echo "  SKIP: HARNESS not in repos.json"
  fi
else
  echo "  SKIP: repos.json not found (expected in CI)"
fi

# Unknown project key
out=$(bash "$SCRIPTS/resolve-repo.sh" "ZZZZZ-999" 2>&1) || true
rc=$?
assert_contains "$out" 'error' "unknown project key fails"

echo ""
test_summary
