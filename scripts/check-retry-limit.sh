#!/usr/bin/env bash
# check-retry-limit.sh — Track and enforce retry limits per task
# Args: $1=ticket_id $2=task_id $3=action (check|increment|reset)
# check: exit 0 if retries remaining, exit 1 if exhausted
# increment: bump retry count, exit 0 if still under limit, exit 1 if now exhausted
# reset: clear retry count for task
# Max retries default: 2 (configurable via AGENT_MAX_TASK_RETRIES)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ $# -lt 3 ]]; then
  echo "Usage: check-retry-limit.sh <ticket_id> <task_id> <check|increment|reset>" >&2
  exit 1
fi

ticket_id="$1"
task_id="$2"
action="$3"

max_retries="${AGENT_MAX_TASK_RETRIES:-2}"
retry_file="$RUNS_DIR/$ticket_id/retries.json"

# Ensure runs dir exists
mkdir -p "$RUNS_DIR/$ticket_id"

# Initialize retry file if missing
if [[ ! -f "$retry_file" ]]; then
  echo '{}' > "$retry_file"
fi

# Read current count using python3 with args (avoids path escaping issues)
current=$(python3 -c "
import json,sys
rf, tid = sys.argv[1], sys.argv[2]
with open(rf) as f:
    data = json.load(f)
print(data.get(tid, 0))
" "$retry_file" "$task_id" 2>/dev/null || echo "0")

case "$action" in
  check)
    if [[ "$current" -ge "$max_retries" ]]; then
      echo "{\"task\":\"$task_id\",\"retries\":$current,\"max\":$max_retries,\"exhausted\":true}" >&2
      exit 1
    fi
    echo "{\"task\":\"$task_id\",\"retries\":$current,\"max\":$max_retries,\"exhausted\":false}"
    exit 0
    ;;
  increment)
    new_count=$((current + 1))
    python3 -c "
import json,sys
rf, tid, nc = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(rf) as f:
    data = json.load(f)
data[tid] = nc
with open(rf, 'w') as f:
    json.dump(data, f, indent=2)
" "$retry_file" "$task_id" "$new_count" 2>/dev/null
    if [[ "$new_count" -ge "$max_retries" ]]; then
      echo "{\"task\":\"$task_id\",\"retries\":$new_count,\"max\":$max_retries,\"exhausted\":true}" >&2
      exit 1
    fi
    echo "{\"task\":\"$task_id\",\"retries\":$new_count,\"max\":$max_retries,\"exhausted\":false}"
    exit 0
    ;;
  reset)
    python3 -c "
import json,sys
rf, tid = sys.argv[1], sys.argv[2]
with open(rf) as f:
    data = json.load(f)
data.pop(tid, None)
with open(rf, 'w') as f:
    json.dump(data, f, indent=2)
" "$retry_file" "$task_id" 2>/dev/null
    echo "{\"task\":\"$task_id\",\"retries\":0,\"max\":$max_retries,\"exhausted\":false}"
    exit 0
    ;;
  *)
    echo "Unknown action: $action (use check|increment|reset)" >&2
    exit 1
    ;;
esac
