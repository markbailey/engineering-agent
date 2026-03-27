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

echo "=== metrics tests ==="

# --- Setup ---
test_ticket="METTEST-1"
run_dir="$WT_ROOT/runs/$test_ticket"
rm -rf "$run_dir"
mkdir -p "$run_dir"

# --- Test 1: collect-metrics.sh with mock run.log ---
echo ""
echo "-- collect-metrics.sh produces valid METRICS.json --"

cat > "$run_dir/run.log" <<'LOGEOF'
{"ts":"2026-03-26T10:00:00Z","level":"INFO","cat":"startup","msg":"Run started"}
{"ts":"2026-03-26T10:00:05Z","level":"INFO","cat":"intake","msg":"Ticket METTEST-1 validated: Story, To Do"}
{"ts":"2026-03-26T10:00:10Z","level":"INFO","cat":"planning","msg":"PRD.json generated: 2 tasks"}
{"ts":"2026-03-26T10:00:30Z","level":"INFO","cat":"implementation","msg":"Task 1 started"}
{"ts":"2026-03-26T10:01:00Z","level":"INFO","cat":"qa","msg":"Task 1 verified"}
{"ts":"2026-03-26T10:01:10Z","level":"INFO","cat":"implementation","msg":"Task 2 started"}
{"ts":"2026-03-26T10:01:30Z","level":"WARN","cat":"retry","msg":"Attempt 1/3 failed, retrying in 2s"}
{"ts":"2026-03-26T10:01:40Z","level":"INFO","cat":"qa","msg":"Task 2 verified"}
{"ts":"2026-03-26T10:02:00Z","level":"EVENT","cat":"summary","msg":"Run complete: completed — 2/2 tasks","details":{"type":"run_summary","status":"completed"}}
LOGEOF

# Create mock PRD.json
prd_win=$(winpath "$run_dir/PRD.json")
python3 -c "
import json
prd = {
    'ticket': 'METTEST-1',
    'title': 'Test ticket',
    'repos': [{'name':'test','worktree_path':'/tmp','branch':'mba_mettest-1_test_feature','base_branch':'main','base_is_dependency':False,'dependency_ticket':None,'dependency_pr':None,'ultimate_base':'main','primary':True}],
    'requirements': 'Test',
    'acceptance_criteria': ['AC1'],
    'tasks': [
        {'id':'task-1','repo':'test','description':'Do thing 1','files_affected':[],'dependencies':[],'status':'verified'},
        {'id':'task-2','repo':'test','description':'Do thing 2','files_affected':[],'dependencies':[],'status':'verified'}
    ],
    'overall_status': 'completed',
    'review_rounds': 0,
    'feedback_rounds': 0
}
with open(r'$prd_win', 'w') as f:
    json.dump(prd, f, indent=2)
"

output=$(bash "$WT_ROOT/scripts/collect-metrics.sh" "$test_ticket" 2>/dev/null)
exit_code=$?
assert_exit "$exit_code" 0 "collect-metrics.sh exits 0"

# Validate against schema
schema_output=$(node "$WT_ROOT/scripts/validate-schemas.js" "$run_dir/METRICS.json" "metrics" 2>&1)
schema_exit=$?
assert_exit "$schema_exit" 0 "METRICS.json passes schema validation"

# Check key fields
metrics_win=$(winpath "$run_dir/METRICS.json")
ticket_val=$(python3 -c "import json; m=json.load(open(r'$metrics_win')); print(m['ticket'])")
assert_eq "$ticket_val" "$test_ticket" "ticket field matches"

outcome_val=$(python3 -c "import json; m=json.load(open(r'$metrics_win')); print(m['outcome'])")
assert_eq "$outcome_val" "completed" "outcome is completed"

cycle_val=$(python3 -c "import json; m=json.load(open(r'$metrics_win')); print(m['cycle_time_seconds'])")
assert_eq "$cycle_val" "120" "cycle_time_seconds is 120 (2 min)"

tasks_total=$(python3 -c "import json; m=json.load(open(r'$metrics_win')); print(m['tasks']['total'])")
assert_eq "$tasks_total" "2" "tasks.total is 2"

tasks_completed=$(python3 -c "import json; m=json.load(open(r'$metrics_win')); print(m['tasks']['completed'])")
assert_eq "$tasks_completed" "2" "tasks.completed is 2"

# Check stages exist
stage_count=$(python3 -c "import json; m=json.load(open(r'$metrics_win')); print(len(m['stages']))")
assert_contains "$stage_count" "[1-9]" "stages array is non-empty"

# --- Test 2: collect-metrics.sh fails without run.log ---
echo ""
echo "-- collect-metrics.sh fails without run.log --"
fake_ticket="METTEST-NOFILE"
output2=$(bash "$WT_ROOT/scripts/collect-metrics.sh" "$fake_ticket" 2>&1)
exit_code2=$?
assert_exit "$exit_code2" 1 "collect-metrics.sh exits 1 without run.log"

# --- Test 3: aggregate-metrics.sh with mock METRICS.json ---
echo ""
echo "-- aggregate-metrics.sh produces valid summary --"

# Create a second metrics file for aggregation
test_ticket2="METTEST-2"
run_dir2="$WT_ROOT/runs/$test_ticket2"
rm -rf "$run_dir2"
mkdir -p "$run_dir2"

metrics2_win=$(winpath "$run_dir2/METRICS.json")
python3 -c "
import json
m = {
    'ticket': 'METTEST-2',
    'started_at': '2026-03-26T11:00:00Z',
    'completed_at': '2026-03-26T11:05:00Z',
    'outcome': 'escalated',
    'cycle_time_seconds': 300,
    'stages': [{'name':'startup','started_at':'2026-03-26T11:00:00Z','completed_at':'2026-03-26T11:05:00Z','duration_seconds':300,'retries':0,'escalated':True}],
    'tasks': {'total': 3, 'completed': 1, 'retried': 1, 'blocked': 1},
    'qa': {'auto_fix_runs': 1, 'auto_fix_resolved': 0, 'test_failures': 2, 'test_retries': 1},
    'review': {'critic_rounds': 1, 'pr_feedback_rounds': 0, 'escalations': 1},
    'learning': {'standing_instructions_injected': 0, 'patterns_detected': 0, 'repairs_applied': 0}
}
with open(r'$metrics2_win', 'w') as f:
    json.dump(m, f, indent=2)
"

agg_output=$(bash "$WT_ROOT/scripts/aggregate-metrics.sh" 2>/dev/null)
agg_exit=$?
assert_exit "$agg_exit" 0 "aggregate-metrics.sh exits 0"
assert_contains "$agg_output" '"total_runs"' "output contains total_runs"
assert_contains "$agg_output" '"average_cycle_time_seconds"' "output contains average_cycle_time"
assert_contains "$agg_output" '"escalation_rate_percent"' "output contains escalation_rate"

# Check total_runs >= 2
total_runs=$(echo "$agg_output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['total_runs'])")
# Should be at least 2 (METTEST-1 + METTEST-2)
if [[ "$total_runs" -ge 2 ]]; then
  TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo "  PASS: total_runs >= 2"
else
  TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo "  FAIL: total_runs >= 2 (got $total_runs)"
fi

# --- Test 4: run-summary.sh references collect-metrics.sh ---
echo ""
echo "-- run-summary.sh calls collect-metrics.sh --"
summary_content=$(cat "$WT_ROOT/scripts/run-summary.sh")
assert_contains "$summary_content" "collect-metrics.sh" "run-summary.sh references collect-metrics.sh"
assert_contains "$summary_content" "Cycle" "run-summary.sh banner includes cycle time"
assert_contains "$summary_content" "Escalat" "run-summary.sh banner includes escalation count"

# --- Test 5: schema validates correctly ---
echo ""
echo "-- schema validation: valid metrics data passes --"
tmpfile=$(mktemp /tmp/metrics-valid-XXXXXX.json)
cat > "$tmpfile" <<'JSONEOF'
{
  "ticket": "PROJ-99",
  "started_at": "2026-01-01T00:00:00Z",
  "completed_at": "2026-01-01T01:00:00Z",
  "outcome": "completed",
  "cycle_time_seconds": 3600,
  "stages": [],
  "tasks": {"total": 1, "completed": 1, "retried": 0, "blocked": 0},
  "qa": {"auto_fix_runs": 0, "auto_fix_resolved": 0, "test_failures": 0, "test_retries": 0},
  "review": {"critic_rounds": 0, "pr_feedback_rounds": 0, "escalations": 0},
  "learning": {"standing_instructions_injected": 0, "patterns_detected": 0, "repairs_applied": 0}
}
JSONEOF
valid_out=$(node "$WT_ROOT/scripts/validate-schemas.js" "$tmpfile" "metrics" 2>&1)
valid_exit=$?
assert_exit "$valid_exit" 0 "valid metrics data passes schema"
rm -f "$tmpfile"

# Invalid data (bad outcome)
echo ""
echo "-- schema validation: invalid outcome fails --"
tmpfile2=$(mktemp /tmp/metrics-invalid-XXXXXX.json)
cat > "$tmpfile2" <<'JSONEOF'
{
  "ticket": "PROJ-99",
  "started_at": "2026-01-01T00:00:00Z",
  "completed_at": null,
  "outcome": "invalid_outcome",
  "cycle_time_seconds": null,
  "stages": [],
  "tasks": {"total": 0, "completed": 0, "retried": 0, "blocked": 0},
  "qa": {"auto_fix_runs": 0, "auto_fix_resolved": 0, "test_failures": 0, "test_retries": 0},
  "review": {"critic_rounds": 0, "pr_feedback_rounds": 0, "escalations": 0},
  "learning": {"standing_instructions_injected": 0, "patterns_detected": 0, "repairs_applied": 0}
}
JSONEOF
invalid_out=$(node "$WT_ROOT/scripts/validate-schemas.js" "$tmpfile2" "metrics" 2>&1)
invalid_exit=$?
assert_exit "$invalid_exit" 1 "invalid outcome fails schema validation"
rm -f "$tmpfile2" "${tmpfile2}.invalid.json"

# Cleanup
rm -rf "$run_dir" "$run_dir2"

echo ""
test_summary
