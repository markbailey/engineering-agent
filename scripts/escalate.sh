#!/usr/bin/env bash
# escalate.sh — Structured escalation writer
# Writes/appends escalation entries to runs/{ticket_id}/ESCALATION.json
#
# Usage:
#   escalate.sh <ticket_id> <category> <severity> <source_agent> <stage> <summary> [--details "..."] [--suggested-action "..."]
#
# Categories: blocked_dependency, test_failure, merge_conflict, review_stall,
#             secret_detected, infra_failure, contradictory_feedback, team_conflict, unknown
# Severities: critical, high, medium

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse positional args
ticket_id="${1:-}"
category="${2:-}"
severity="${3:-}"
source_agent="${4:-}"
stage="${5:-}"
summary="${6:-}"
shift 6 2>/dev/null || true

# Parse optional flags
details=""
suggested_action=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --details) details="$2"; shift 2 ;;
    --suggested-action) suggested_action="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ticket_id" || -z "$category" || -z "$severity" || -z "$source_agent" || -z "$stage" || -z "$summary" ]]; then
  echo "Usage: escalate.sh <ticket_id> <category> <severity> <source_agent> <stage> <summary> [--details '...'] [--suggested-action '...']" >&2
  exit 1
fi

# Validate category
valid_categories="blocked_dependency test_failure merge_conflict review_stall secret_detected infra_failure contradictory_feedback team_conflict unknown"
if ! echo "$valid_categories" | tr ' ' '\n' | grep -qx "$category"; then
  echo "ERROR: Invalid category '$category'. Valid: $valid_categories" >&2
  exit 1
fi

# Validate severity
valid_severities="critical high medium"
if ! echo "$valid_severities" | tr ' ' '\n' | grep -qx "$severity"; then
  echo "ERROR: Invalid severity '$severity'. Valid: $valid_severities" >&2
  exit 1
fi

run_dir="$AGENT_ROOT/runs/$ticket_id"
mkdir -p "$run_dir"
esc_file="$run_dir/ESCALATION.json"

# Use python3 for JSON manipulation
python3 -c "
import json, sys, os
from datetime import datetime, timezone

esc_file = sys.argv[1]
ticket_id = sys.argv[2]
category = sys.argv[3]
severity = sys.argv[4]
source_agent = sys.argv[5]
stage = sys.argv[6]
summary = sys.argv[7]
details = sys.argv[8]
suggested_action = sys.argv[9]

# Load or create
if os.path.exists(esc_file):
    with open(esc_file) as f:
        data = json.load(f)
else:
    data = {'ticket': ticket_id, 'escalations': []}

# Compute next ID
existing_ids = [int(e['id'].replace('esc-','')) for e in data['escalations'] if e.get('id','').startswith('esc-')]
next_num = max(existing_ids, default=0) + 1
esc_id = f'esc-{next_num:03d}'

# Build context
context = {'summary': summary}
if details:
    context['details'] = details
if suggested_action:
    context['suggested_action'] = suggested_action

entry = {
    'id': esc_id,
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'category': category,
    'severity': severity,
    'source_agent': source_agent,
    'stage': stage,
    'context': context,
    'resolved': False,
    'resolved_at': None
}

data['escalations'].append(entry)

with open(esc_file, 'w') as f:
    json.dump(data, f, indent=2)

# Output confirmation
print(json.dumps({'escalation_id': esc_id, 'file': esc_file, 'category': category, 'severity': severity}))
" "$esc_file" "$ticket_id" "$category" "$severity" "$source_agent" "$stage" "$summary" "$details" "$suggested_action"

esc_id=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['escalations'][-1]['id'])" "$esc_file")

# Log EVENT to run.log
"$SCRIPT_DIR/run-log.sh" "$ticket_id" "EVENT" "event" "Escalation $esc_id: [$severity] $category — $summary" "{\"escalation_id\":\"$esc_id\",\"category\":\"$category\",\"severity\":\"$severity\",\"source_agent\":\"$source_agent\"}"

# Notify via notify.sh
"$SCRIPT_DIR/notify.sh" "$ticket_id" "escalation" "Escalation $esc_id: [$severity] $category — $summary"

# Update PRD.json status if it exists
prd_file="$run_dir/PRD.json"
if [[ -f "$prd_file" ]]; then
  "$SCRIPT_DIR/update-prd-status.sh" "$ticket_id" "escalated" >/dev/null 2>&1 || true
fi
