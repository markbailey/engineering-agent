#!/usr/bin/env bash
source "$(dirname "$0")/test-helpers.sh"
WT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Helper: convert path to Windows format for python3 on MSYS/Git Bash
winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    echo "$1"
  fi
}

echo "=== escalation tests ==="

# Setup temp run dir
test_ticket="ESCTEST-1"
run_dir="$WT_ROOT/runs/$test_ticket"
rm -rf "$run_dir"

# --- Test 1: escalate.sh creates valid ESCALATION.json ---
echo ""
echo "-- escalate.sh creates valid ESCALATION.json --"
output=$(bash "$WT_ROOT/scripts/escalate.sh" "$test_ticket" test_failure high developer qa "Tests failed" 2>/dev/null)
exit_code=$?
assert_exit "$exit_code" 0 "escalate.sh exits 0"
assert_contains "$output" '"escalation_id": "esc-001"' "returns esc-001 id"

# Validate against schema
schema_output=$(node "$WT_ROOT/scripts/validate-schemas.js" "$run_dir/ESCALATION.json" "escalation" 2>&1)
schema_exit=$?
assert_exit "$schema_exit" 0 "ESCALATION.json passes schema validation"

# Check fields via python (use Windows-compatible paths)
esc_file_win=$(winpath "$run_dir/ESCALATION.json")
ticket_val=$(python3 -c "import json; d=json.load(open(r'$esc_file_win')); print(d['ticket'])")
assert_eq "$ticket_val" "$test_ticket" "ticket field matches"
cat_val=$(python3 -c "import json; d=json.load(open(r'$esc_file_win')); print(d['escalations'][0]['category'])")
assert_eq "$cat_val" "test_failure" "category is test_failure"
sev_val=$(python3 -c "import json; d=json.load(open(r'$esc_file_win')); print(d['escalations'][0]['severity'])")
assert_eq "$sev_val" "high" "severity is high"

# --- Test 2: escalate.sh appends (array grows) ---
echo ""
echo "-- escalate.sh appends to existing file --"
output2=$(bash "$WT_ROOT/scripts/escalate.sh" "$test_ticket" merge_conflict medium resolver conflict "Merge failed" --details "file.ts conflict" 2>/dev/null)
exit_code2=$?
assert_exit "$exit_code2" 0 "second escalate.sh exits 0"
assert_contains "$output2" '"escalation_id": "esc-002"' "returns esc-002 id"

count=$(python3 -c "import json; d=json.load(open(r'$esc_file_win')); print(len(d['escalations']))")
assert_eq "$count" "2" "array has 2 entries"

# Re-validate after append
schema_output2=$(node "$WT_ROOT/scripts/validate-schemas.js" "$run_dir/ESCALATION.json" "escalation" 2>&1)
schema_exit2=$?
assert_exit "$schema_exit2" 0 "ESCALATION.json still valid after append"

# Check details field
det_val=$(python3 -c "import json; d=json.load(open(r'$esc_file_win')); print(d['escalations'][1]['context'].get('details',''))")
assert_eq "$det_val" "file.ts conflict" "details field preserved"

# Cleanup test 1-2
rm -rf "$run_dir"

# --- Test 3: abort-run.sh writes aborted status ---
echo ""
echo "-- abort-run.sh writes aborted status --"
test_ticket2="ESCTEST-2"
run_dir2="$WT_ROOT/runs/$test_ticket2"
rm -rf "$run_dir2"
mkdir -p "$run_dir2"

# Create minimal PRD.json via python (Windows-safe path)
prd_file_win=$(winpath "$run_dir2/PRD.json")
python3 -c "
import json
prd = {
    'ticket': 'ESCTEST-2',
    'title': 'Test',
    'repos': [{'name':'test','worktree_path':'/tmp','branch':'mba_esctest-2_test_feature','base_branch':'main','base_is_dependency':False,'dependency_ticket':None,'dependency_pr':None,'ultimate_base':'main','primary':True}],
    'requirements': 'Test req',
    'acceptance_criteria': ['AC1'],
    'tasks': [{'id':'task-1','repo':'test','description':'Do thing','files_affected':[],'dependencies':[],'status':'pending'}],
    'overall_status': 'in_progress',
    'review_rounds': 0,
    'feedback_rounds': 0
}
with open(r'$prd_file_win', 'w') as f:
    json.dump(prd, f, indent=2)
"

abort_output=$(bash "$WT_ROOT/scripts/abort-run.sh" "$test_ticket2" "Test abort reason" 2>/dev/null)
abort_exit=$?
assert_exit "$abort_exit" 0 "abort-run.sh exits 0"
assert_contains "$abort_output" '"prd_updated": true' "PRD updated to aborted"
assert_contains "$abort_output" '"escalation_written": true' "escalation written"

# Verify PRD status
prd_status=$(python3 -c "import json; d=json.load(open(r'$prd_file_win')); print(d['overall_status'])")
assert_eq "$prd_status" "aborted" "PRD overall_status is aborted"

# Verify ESCALATION.json exists and valid
esc_exists="false"
if [[ -f "$run_dir2/ESCALATION.json" ]]; then esc_exists="true"; fi
assert_eq "$esc_exists" "true" "ESCALATION.json created by abort"

rm -rf "$run_dir2"

# --- Test 4: abort-run.sh with no PRD.json (graceful skip) ---
echo ""
echo "-- abort-run.sh with no PRD.json --"
test_ticket3="ESCTEST-3"
run_dir3="$WT_ROOT/runs/$test_ticket3"
rm -rf "$run_dir3"

abort_output2=$(bash "$WT_ROOT/scripts/abort-run.sh" "$test_ticket3" "No PRD abort" 2>/dev/null)
abort_exit2=$?
assert_exit "$abort_exit2" 0 "abort-run.sh exits 0 without PRD"
assert_contains "$abort_output2" '"prd_updated": false' "PRD not updated (none exists)"
assert_contains "$abort_output2" '"escalation_written": true' "escalation still written"

rm -rf "$run_dir3"

# --- Test 5: schema validates correctly ---
echo ""
echo "-- schema validation --"
# Valid data
tmpfile=$(mktemp /tmp/esc-valid-XXXXXX.json)
cat > "$tmpfile" <<'JSONEOF'
{
  "ticket": "PROJ-123",
  "escalations": [{
    "id": "esc-001",
    "timestamp": "2026-01-01T00:00:00Z",
    "category": "test_failure",
    "severity": "high",
    "source_agent": "developer",
    "stage": "qa",
    "context": {"summary": "Tests failed"},
    "resolved": false,
    "resolved_at": null
  }]
}
JSONEOF
valid_out=$(node "$WT_ROOT/scripts/validate-schemas.js" "$tmpfile" "escalation" 2>&1)
valid_exit=$?
assert_exit "$valid_exit" 0 "valid escalation data passes schema"
rm -f "$tmpfile"

# Invalid data (bad category)
tmpfile2=$(mktemp /tmp/esc-invalid-XXXXXX.json)
cat > "$tmpfile2" <<'JSONEOF'
{
  "ticket": "PROJ-123",
  "escalations": [{
    "id": "esc-001",
    "timestamp": "2026-01-01T00:00:00Z",
    "category": "not_a_real_category",
    "severity": "high",
    "source_agent": "developer",
    "stage": "qa",
    "context": {"summary": "Tests failed"},
    "resolved": false,
    "resolved_at": null
  }]
}
JSONEOF
invalid_out=$(node "$WT_ROOT/scripts/validate-schemas.js" "$tmpfile2" "escalation" 2>&1)
invalid_exit=$?
assert_exit "$invalid_exit" 1 "invalid category fails schema validation"
rm -f "$tmpfile2" "${tmpfile2}.invalid.json"

echo ""
test_summary
