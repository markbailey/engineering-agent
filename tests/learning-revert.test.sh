#!/usr/bin/env bash
source "$(dirname "$0")/test-helpers.sh"
WT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== learning effectiveness & revert tests ==="

# --- Test 1: agent-learning.sh has prune action ---
echo ""
echo "-- agent-learning.sh has prune action --"
prune_match=$(grep -c "prune)" "$WT_ROOT/scripts/agent-learning.sh" || true)
assert_eq "$((prune_match > 0 ? 1 : 0))" "1" "agent-learning.sh contains prune action"

# --- Test 2: schema has effectiveness_score field ---
echo ""
echo "-- schema has effectiveness_score field --"
eff_match=$(grep -c "effectiveness_score" "$WT_ROOT/schemas/agent-learning.schema.json" || true)
assert_eq "$((eff_match > 0 ? 1 : 0))" "1" "schema contains effectiveness_score"

# --- Test 3: schema has runs_with_instruction field ---
echo ""
echo "-- schema has runs_with_instruction field --"
rwi_match=$(grep -c "runs_with_instruction" "$WT_ROOT/schemas/agent-learning.schema.json" || true)
assert_eq "$((rwi_match > 0 ? 1 : 0))" "1" "schema contains runs_with_instruction"

# --- Test 4: schema has ineffective status ---
echo ""
echo "-- schema has ineffective status enum --"
ineff_match=$(grep -c '"ineffective"' "$WT_ROOT/schemas/agent-learning.schema.json" || true)
assert_eq "$((ineff_match > 0 ? 1 : 0))" "1" "schema contains ineffective status"

# --- Test 5: parse-args.sh handles --revert flag ---
echo ""
echo "-- parse-args.sh handles --revert flag --"
revert_match=$(grep -c "\-\-revert" "$WT_ROOT/scripts/parse-args.sh" || true)
assert_eq "$((revert_match > 0 ? 1 : 0))" "1" "parse-args.sh contains --revert handling"

# Functional test: parse-args outputs mode=revert (will fail without repos.json for ticket, so just check flag parsing)
revert_flag_match=$(grep -c 'mode="revert"' "$WT_ROOT/scripts/parse-args.sh" || true)
assert_eq "$((revert_flag_match > 0 ? 1 : 0))" "1" "parse-args.sh sets mode=revert"

# --- Test 6: dependency-graph.sh outputs valid JSON for --json mode ---
echo ""
echo "-- dependency-graph.sh outputs valid JSON --"
# Create a minimal ticket.json for testing
test_ticket="DEPTEST-1"
test_run_dir="$WT_ROOT/runs/$test_ticket"
mkdir -p "$test_run_dir"
cat > "$test_run_dir/ticket.json" <<'TICKET'
{
  "ticket_id": "DEPTEST-1",
  "title": "Test ticket",
  "type": "Task",
  "status": "In Progress",
  "acceptance_criteria": ["AC1"],
  "linked_issues": [
    {"ticket_id": "DEPTEST-2", "type": "blocked_by", "status": "done"}
  ]
}
TICKET

dep_output=$(bash "$WT_ROOT/scripts/dependency-graph.sh" "$test_ticket" --json 2>/dev/null)
dep_exit=$?
assert_exit "$dep_exit" 0 "dependency-graph.sh exits 0"

# Validate JSON
echo "$dep_output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'nodes' in d and 'edges' in d" 2>/dev/null
json_exit=$?
assert_exit "$json_exit" 0 "dependency-graph.sh output is valid JSON with nodes/edges"

# Check node count
node_count=$(echo "$dep_output" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['nodes']))")
assert_eq "$node_count" "2" "dependency-graph.sh found 2 nodes"

# Cleanup test data
rm -rf "$test_run_dir"

# --- Test 7: revert-run.sh exists and is executable ---
echo ""
echo "-- revert-run.sh exists and is executable --"
assert_eq "$(test -f "$WT_ROOT/scripts/revert-run.sh" && echo 1 || echo 0)" "1" "revert-run.sh exists"
assert_eq "$(test -x "$WT_ROOT/scripts/revert-run.sh" && echo 1 || echo 0)" "1" "revert-run.sh is executable"

# --- Test 8: dependency-graph.sh exists and is executable ---
echo ""
echo "-- dependency-graph.sh exists and is executable --"
assert_eq "$(test -f "$WT_ROOT/scripts/dependency-graph.sh" && echo 1 || echo 0)" "1" "dependency-graph.sh exists"
assert_eq "$(test -x "$WT_ROOT/scripts/dependency-graph.sh" && echo 1 || echo 0)" "1" "dependency-graph.sh is executable"

test_summary
