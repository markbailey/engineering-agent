#!/usr/bin/env bash
# Tests for cleanup-orphans.sh — stale tickets section
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLEANUP_SH="$SCRIPT_DIR/../scripts/cleanup-orphans.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"
TICKETS_DIR="$AGENT_ROOT/tickets"

TEST_PREFIX="TEST-CLEANUP-$$"
TEST_TICKET_DONE="${TEST_PREFIX}-1"
TEST_TICKET_ACTIVE="${TEST_PREFIX}-2"
TEST_TICKET_UNUSED="${TEST_PREFIX}-3"

cleanup() {
  rm -rf "$RUNS_DIR/$TEST_TICKET_DONE"
  rm -rf "$RUNS_DIR/$TEST_TICKET_ACTIVE"
  rm -f "$TICKETS_DIR/$TEST_TICKET_DONE.json"
  rm -f "$TICKETS_DIR/$TEST_TICKET_ACTIVE.json"
  rm -f "$TICKETS_DIR/$TEST_TICKET_UNUSED.json"
}
trap cleanup EXIT

echo "=== cleanup-orphans.sh stale tickets tests ==="

# --- Setup: create test ticket files + run dirs ---
cleanup
mkdir -p "$TICKETS_DIR"

# Done ticket — has run dir with done status
mkdir -p "$RUNS_DIR/$TEST_TICKET_DONE"
cat > "$RUNS_DIR/$TEST_TICKET_DONE/PRD.json" <<EOF
{"overall_status": "done", "repos": []}
EOF
cat > "$TICKETS_DIR/$TEST_TICKET_DONE.json" <<EOF
{"ticket_id": "$TEST_TICKET_DONE", "title": "Test done", "type": "Story", "requirements": "n/a", "acceptance_criteria": [], "repo": "HARNESS"}
EOF

# Active ticket — has run dir with active status
mkdir -p "$RUNS_DIR/$TEST_TICKET_ACTIVE"
cat > "$RUNS_DIR/$TEST_TICKET_ACTIVE/PRD.json" <<EOF
{"overall_status": "implementation", "repos": []}
EOF
cat > "$TICKETS_DIR/$TEST_TICKET_ACTIVE.json" <<EOF
{"ticket_id": "$TEST_TICKET_ACTIVE", "title": "Test active", "type": "Story", "requirements": "n/a", "acceptance_criteria": [], "repo": "HARNESS"}
EOF

# Unused ticket — no run dir
cat > "$TICKETS_DIR/$TEST_TICKET_UNUSED.json" <<EOF
{"ticket_id": "$TEST_TICKET_UNUSED", "title": "Test unused", "type": "Story", "requirements": "n/a", "acceptance_criteria": [], "repo": "HARNESS"}
EOF

# --- Test 1: dry-run reports stale done ticket ---
output=$(bash "$CLEANUP_SH" --dry-run --ticket="$TEST_TICKET_DONE" 2>&1) || true
assert_contains "$output" "Stale Tickets" "dry-run shows Stale Tickets section"
assert_contains "$output" "$TEST_TICKET_DONE" "dry-run reports done ticket"
assert_contains "$output" "STALE" "dry-run labels done ticket as STALE"
# File should still exist (dry-run)
[[ -f "$TICKETS_DIR/$TEST_TICKET_DONE.json" ]]; ec=$?
assert_exit "$ec" 0 "dry-run does not delete ticket file"

# --- Test 2: dry-run reports orphaned-stale ticket (active status but no worktree/PR) ---
output=$(bash "$CLEANUP_SH" --dry-run --ticket="$TEST_TICKET_ACTIVE" 2>&1) || true
assert_contains "$output" "ORPHANED" "dry-run reports orphaned active ticket (no worktree)"

# --- Test 3: dry-run skips unused ticket (no run dir) in stale section ---
output=$(bash "$CLEANUP_SH" --dry-run --ticket="$TEST_TICKET_UNUSED" 2>&1) || true
assert_contains "$output" "SKIP" "dry-run skips unused ticket"

# --- Test 4: real run deletes stale done ticket ---
# Re-create done ticket (may have been cleaned by previous test runs)
mkdir -p "$RUNS_DIR/$TEST_TICKET_DONE"
echo '{"overall_status":"done","repos":[]}' > "$RUNS_DIR/$TEST_TICKET_DONE/PRD.json"
echo '{"ticket_id":"'"$TEST_TICKET_DONE"'","title":"Test done","type":"Story","requirements":"n/a","acceptance_criteria":[],"repo":"HARNESS"}' > "$TICKETS_DIR/$TEST_TICKET_DONE.json"
output=$(bash "$CLEANUP_SH" --ticket="$TEST_TICKET_DONE" 2>&1) || true
[[ ! -f "$TICKETS_DIR/$TEST_TICKET_DONE.json" ]]; ec=$?
assert_exit "$ec" 0 "real run deletes stale done ticket file"

# --- Test 5: real run also deletes orphaned-stale ticket (no worktree/PR) ---
output=$(bash "$CLEANUP_SH" --ticket="$TEST_TICKET_ACTIVE" 2>&1) || true
[[ ! -f "$TICKETS_DIR/$TEST_TICKET_ACTIVE.json" ]]; ec=$?
assert_exit "$ec" 0 "real run deletes orphaned active ticket file"

# --- Test 6: real run preserves unused ticket ---
output=$(bash "$CLEANUP_SH" --ticket="$TEST_TICKET_UNUSED" 2>&1) || true
[[ -f "$TICKETS_DIR/$TEST_TICKET_UNUSED.json" ]]; ec=$?
assert_exit "$ec" 0 "real run preserves unused ticket file"

test_summary
