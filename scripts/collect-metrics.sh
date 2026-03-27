#!/usr/bin/env bash
# collect-metrics.sh — Collect run metrics from run.log and PRD.json
#
# Usage:
#   collect-metrics.sh <ticket_id>
#
# Reads runs/{ticket_id}/run.log (JSONL) and PRD.json
# Writes runs/{ticket_id}/METRICS.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ticket_id="${1:-}"

if [[ -z "$ticket_id" ]]; then
  echo "Usage: collect-metrics.sh <ticket_id>" >&2
  exit 1
fi

run_dir="$AGENT_ROOT/runs/$ticket_id"
log_file="$run_dir/run.log"
prd_file="$run_dir/PRD.json"
esc_file="$run_dir/ESCALATION.json"
metrics_file="$run_dir/METRICS.json"

if [[ ! -f "$log_file" ]]; then
  echo "ERROR: run.log not found at $log_file" >&2
  exit 1
fi

# Use python for robust JSONL/JSON parsing
python3 - "$ticket_id" "$log_file" "$prd_file" "$esc_file" "$metrics_file" <<'PYEOF'
import json, sys, os
from datetime import datetime

ticket_id = sys.argv[1]
log_file = sys.argv[2]
prd_file = sys.argv[3]
esc_file = sys.argv[4]
metrics_file = sys.argv[5]

# Parse run.log JSONL
entries = []
with open(log_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue

if not entries:
    print("ERROR: no valid log entries", file=sys.stderr)
    sys.exit(1)

# Timestamps
started_at = entries[0].get("ts", "")
completed_at = entries[-1].get("ts", "")

# Cycle time
cycle_time = None
try:
    fmt = "%Y-%m-%dT%H:%M:%SZ"
    t0 = datetime.strptime(started_at, fmt)
    t1 = datetime.strptime(completed_at, fmt)
    cycle_time = int((t1 - t0).total_seconds())
except (ValueError, TypeError):
    pass

# Determine outcome from last summary entry or overall status
outcome = "completed"
for e in reversed(entries):
    msg = e.get("msg", "").lower()
    details = e.get("details", {})
    if isinstance(details, dict):
        status = details.get("status", "")
        if status == "escalated":
            outcome = "escalated"
            break
        elif status == "aborted":
            outcome = "aborted"
            break
    if "escalat" in msg:
        outcome = "escalated"
        break

# Stage tracking: group by category transitions
stage_map = {}
stage_order = []
for e in entries:
    cat = e.get("cat", "general")
    ts = e.get("ts", "")
    if cat not in stage_map:
        stage_map[cat] = {"name": cat, "started_at": ts, "completed_at": ts, "retries": 0, "escalated": False}
        stage_order.append(cat)
    else:
        stage_map[cat]["completed_at"] = ts
    if e.get("cat") == "retry":
        # Attribute retry to previous stage if possible
        stage_map[cat]["retries"] += 1
    if e.get("level") == "ERROR" and "escalat" in e.get("msg", "").lower():
        stage_map[cat]["escalated"] = True

stages = []
fmt = "%Y-%m-%dT%H:%M:%SZ"
for cat in stage_order:
    s = stage_map[cat]
    dur = None
    try:
        t0 = datetime.strptime(s["started_at"], fmt)
        t1 = datetime.strptime(s["completed_at"], fmt)
        dur = int((t1 - t0).total_seconds())
    except (ValueError, TypeError):
        pass
    stages.append({
        "name": s["name"],
        "started_at": s["started_at"],
        "completed_at": s["completed_at"],
        "duration_seconds": dur,
        "retries": s["retries"],
        "escalated": s["escalated"]
    })

# Retry count from log
retry_count = sum(1 for e in entries if e.get("cat") == "retry")
error_count = sum(1 for e in entries if e.get("level") == "ERROR")

# Task counts from PRD.json
tasks = {"total": 0, "completed": 0, "retried": 0, "blocked": 0}
if os.path.isfile(prd_file):
    try:
        with open(prd_file, 'r') as f:
            prd = json.load(f)
        task_list = prd.get("tasks", [])
        tasks["total"] = len(task_list)
        for t in task_list:
            st = t.get("status", "")
            if st == "verified":
                tasks["completed"] += 1
            elif st == "blocked":
                tasks["blocked"] += 1
        # retried = tasks that had retry log entries (heuristic from retry count)
        tasks["retried"] = min(retry_count, tasks["total"])
    except (json.JSONDecodeError, KeyError):
        pass

# QA metrics from log
qa = {"auto_fix_runs": 0, "auto_fix_resolved": 0, "test_failures": 0, "test_retries": 0}
for e in entries:
    msg = e.get("msg", "").lower()
    cat = e.get("cat", "")
    if cat == "qa":
        if "auto-fix" in msg or "auto_fix" in msg:
            qa["auto_fix_runs"] += 1
            if "resolved" in msg or "clean" in msg or "fixed" in msg:
                qa["auto_fix_resolved"] += 1
        if "test" in msg and ("fail" in msg or "error" in msg):
            qa["test_failures"] += 1
        if "retry" in msg or "re-run" in msg:
            qa["test_retries"] += 1

# Review metrics
review = {"critic_rounds": 0, "pr_feedback_rounds": 0, "escalations": 0}
for e in entries:
    cat = e.get("cat", "")
    msg = e.get("msg", "").lower()
    if cat == "review" and "critic" in msg and "round" in msg:
        review["critic_rounds"] += 1
    if cat == "monitor" and "feedback" in msg:
        review["pr_feedback_rounds"] += 1

# Escalation count
if os.path.isfile(esc_file):
    try:
        with open(esc_file, 'r') as f:
            esc = json.load(f)
        review["escalations"] = len(esc.get("escalations", []))
    except (json.JSONDecodeError, KeyError):
        pass
else:
    review["escalations"] = sum(1 for e in entries if "escalat" in e.get("msg", "").lower() and e.get("level") == "ERROR")

# Learning metrics
learning = {"standing_instructions_injected": 0, "patterns_detected": 0, "repairs_applied": 0}
for e in entries:
    msg = e.get("msg", "").lower()
    if "standing instruction" in msg:
        learning["standing_instructions_injected"] += 1
    if "pattern" in msg and "detect" in msg:
        learning["patterns_detected"] += 1
    if "repair" in msg and ("applied" in msg or "success" in msg):
        learning["repairs_applied"] += 1

# Build metrics
metrics = {
    "ticket": ticket_id,
    "started_at": started_at,
    "completed_at": completed_at,
    "outcome": outcome,
    "cycle_time_seconds": cycle_time,
    "stages": stages,
    "tasks": tasks,
    "qa": qa,
    "review": review,
    "learning": learning
}

with open(metrics_file, 'w') as f:
    json.dump(metrics, f, indent=2)
    f.write('\n')

print(json.dumps({"status": "ok", "metrics_file": metrics_file}))
PYEOF
