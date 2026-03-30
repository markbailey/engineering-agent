#!/usr/bin/env bash
# check-loop-limit.sh — Track and enforce max iterations on feedback loops
# Args: $1=ticket_id $2=loop_name $3=max_iterations $4=action (check|increment|reset)
# Loop names: critic_review, pr_feedback, qa_retry, conflict_resolution
# Exit 0=under limit, exit 1=limit reached (escalate)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/flock.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ $# -lt 4 ]]; then
  echo "Usage: check-loop-limit.sh <ticket_id> <loop_name> <max_iterations> <check|increment|reset>" >&2
  exit 1
fi

ticket_id="$1"
loop_name="$2"
max_iterations="$3"
action="$4"

loop_file="$RUNS_DIR/$ticket_id/loops.json"

# Ensure runs dir exists
mkdir -p "$RUNS_DIR/$ticket_id"

# Initialize if missing
if [[ ! -f "$loop_file" ]]; then
  echo '{}' > "$loop_file"
fi

# Read current count
current=$(python3 -c "
import json,sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get(sys.argv[2], 0))
" "$loop_file" "$loop_name" 2>/dev/null || echo "0")

case "$action" in
  check)
    if [[ "$current" -ge "$max_iterations" ]]; then
      echo "{\"loop\":\"$loop_name\",\"iterations\":$current,\"max\":$max_iterations,\"exhausted\":true}" >&2
      exit 1
    fi
    echo "{\"loop\":\"$loop_name\",\"iterations\":$current,\"max\":$max_iterations,\"exhausted\":false}"
    exit 0
    ;;
  increment)
    new_count=$((current + 1))
    with_lock "$loop_file" python3 -c "
import json,sys
rf, ln, nc = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(rf) as f:
    data = json.load(f)
data[ln] = nc
with open(rf, 'w') as f:
    json.dump(data, f, indent=2)
" "$loop_file" "$loop_name" "$new_count" 2>/dev/null
    if [[ "$new_count" -ge "$max_iterations" ]]; then
      echo "{\"loop\":\"$loop_name\",\"iterations\":$new_count,\"max\":$max_iterations,\"exhausted\":true}" >&2
      exit 1
    fi
    echo "{\"loop\":\"$loop_name\",\"iterations\":$new_count,\"max\":$max_iterations,\"exhausted\":false}"
    exit 0
    ;;
  reset)
    with_lock "$loop_file" python3 -c "
import json,sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data.pop(sys.argv[2], None)
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
" "$loop_file" "$loop_name" 2>/dev/null
    echo "{\"loop\":\"$loop_name\",\"iterations\":0,\"max\":$max_iterations,\"exhausted\":false}"
    exit 0
    ;;
  *)
    echo "Unknown action: $action (use check|increment|reset)" >&2
    exit 1
    ;;
esac
