#!/usr/bin/env bash
# aggregate-metrics.sh — Aggregate metrics across all runs
#
# Usage:
#   aggregate-metrics.sh
#
# Scans runs/*/METRICS.json, computes summary stats, outputs JSON to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ ! -d "$RUNS_DIR" ]]; then
  echo '{"error":"no runs directory found"}' >&2
  exit 1
fi

# Collect all METRICS.json paths
metrics_files=()
for f in "$RUNS_DIR"/*/METRICS.json; do
  [[ -f "$f" ]] && metrics_files+=("$f")
done

if [[ ${#metrics_files[@]} -eq 0 ]]; then
  echo '{"total_runs":0,"message":"no metrics files found"}'
  exit 0
fi

# Pass file list to python via stdin
printf '%s\n' "${metrics_files[@]}" | python3 - <<'PYEOF'
import json, sys

files = [line.strip() for line in sys.stdin if line.strip()]
metrics_list = []

for f in files:
    try:
        with open(f, 'r') as fh:
            metrics_list.append(json.load(fh))
    except (json.JSONDecodeError, OSError):
        continue

if not metrics_list:
    print(json.dumps({"total_runs": 0, "message": "no valid metrics files"}))
    sys.exit(0)

total_runs = len(metrics_list)

# Cycle times (exclude None)
cycle_times = [m["cycle_time_seconds"] for m in metrics_list if m.get("cycle_time_seconds") is not None]
avg_cycle_time = round(sum(cycle_times) / len(cycle_times)) if cycle_times else None

# Outcome counts
outcomes = {}
for m in metrics_list:
    o = m.get("outcome", "unknown")
    outcomes[o] = outcomes.get(o, 0) + 1

escalation_count = outcomes.get("escalated", 0)
escalation_rate = round((escalation_count / total_runs) * 100, 1) if total_runs > 0 else 0

# Task totals
total_tasks = sum(m.get("tasks", {}).get("total", 0) for m in metrics_list)
completed_tasks = sum(m.get("tasks", {}).get("completed", 0) for m in metrics_list)
retried_tasks = sum(m.get("tasks", {}).get("retried", 0) for m in metrics_list)

# Escalation categories (from stages)
esc_categories = {}
for m in metrics_list:
    for s in m.get("stages", []):
        if s.get("escalated"):
            name = s.get("name", "unknown")
            esc_categories[name] = esc_categories.get(name, 0) + 1

top_esc_categories = sorted(esc_categories.items(), key=lambda x: -x[1])[:5]

# QA totals
total_auto_fix_runs = sum(m.get("qa", {}).get("auto_fix_runs", 0) for m in metrics_list)
total_test_failures = sum(m.get("qa", {}).get("test_failures", 0) for m in metrics_list)

# Review totals
total_critic_rounds = sum(m.get("review", {}).get("critic_rounds", 0) for m in metrics_list)
total_pr_feedback = sum(m.get("review", {}).get("pr_feedback_rounds", 0) for m in metrics_list)

summary = {
    "total_runs": total_runs,
    "average_cycle_time_seconds": avg_cycle_time,
    "outcomes": outcomes,
    "escalation_rate_percent": escalation_rate,
    "most_common_escalation_categories": [{"category": c, "count": n} for c, n in top_esc_categories],
    "tasks": {
        "total": total_tasks,
        "completed": completed_tasks,
        "retried": retried_tasks
    },
    "qa": {
        "auto_fix_runs": total_auto_fix_runs,
        "test_failures": total_test_failures
    },
    "review": {
        "critic_rounds": total_critic_rounds,
        "pr_feedback_rounds": total_pr_feedback
    }
}

print(json.dumps(summary, indent=2))
PYEOF
