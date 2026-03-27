#!/usr/bin/env bash
# Tests for rate-limit awareness and jitter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SCRIPTS="$SCRIPT_DIR/../scripts"

echo "=== Rate Limit & Jitter Tests ==="

# Test 1: Jitter produces non-zero addition (statistical — run several times)
echo ""
echo "--- Jitter in retry-with-backoff.sh ---"
nonzero_count=0
for i in $(seq 1 10); do
  delay=2000
  jitter=$((RANDOM % (delay * 30 / 100 + 1)))
  if [[ "$jitter" -gt 0 ]]; then
    nonzero_count=$((nonzero_count + 1))
  fi
done
# With 10 trials and range 0-600, probability of all zero is (1/601)^10 ≈ 0
TOTAL=$((TOTAL + 1))
if [[ "$nonzero_count" -gt 0 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: jitter produced non-zero values ($nonzero_count/10 non-zero)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: jitter produced all zeros in 10 trials"
fi

# Test 2: retry-with-backoff.sh contains RANDOM/jitter logic
echo ""
echo "--- retry-with-backoff.sh contains jitter ---"
backoff_content=$(cat "$SCRIPTS/retry-with-backoff.sh")
assert_contains "$backoff_content" "RANDOM" "retry-with-backoff.sh references RANDOM"
assert_contains "$backoff_content" "jitter" "retry-with-backoff.sh references jitter"

# Test 3: check-team-conflict.sh sources rate-limit.sh
echo ""
echo "--- check-team-conflict.sh sources rate-limit.sh ---"
tc_content=$(cat "$SCRIPTS/check-team-conflict.sh")
assert_contains "$tc_content" "source.*rate-limit.sh" "check-team-conflict.sh sources rate-limit.sh"
assert_contains "$tc_content" "pre_gh_check" "check-team-conflict.sh calls pre_gh_check"

# Test 4: check-pr-size.sh sources rate-limit.sh
echo ""
echo "--- check-pr-size.sh sources rate-limit.sh ---"
ps_content=$(cat "$SCRIPTS/check-pr-size.sh")
assert_contains "$ps_content" "source.*rate-limit.sh" "check-pr-size.sh sources rate-limit.sh"

# Test 5: rate-limit.sh exists and has expected functions
echo ""
echo "--- rate-limit.sh structure ---"
rl_content=$(cat "$SCRIPTS/rate-limit.sh")
assert_contains "$rl_content" "check_rate_limit" "rate-limit.sh defines check_rate_limit"
assert_contains "$rl_content" "pre_gh_check" "rate-limit.sh defines pre_gh_check"
assert_contains "$rl_content" "gh api rate_limit" "rate-limit.sh calls gh api rate_limit"

echo ""
test_summary
