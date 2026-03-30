#!/usr/bin/env bash
# auto-repair.sh — Auto-repair system for tool/environment failures
# Tracks consecutive failures, consults knowledge base, manages confidence
#
# Args: $1=action $2...=action-specific args
# Actions:
#   lookup <agent> <operation> <error_output>  — find known fix in knowledge base
#   record <agent> <operation> <failed_approach> <failure_reason> <error_pattern> <successful_alternative>
#   promote                                     — promote confidence for all entries
#   mark-failed <repair_id>                     — mark an alternative as failed
#   track-failure <ticket_id> <agent> <operation> — increment failure counter, return count
#   reset-failure <ticket_id> <agent> <operation> — reset failure counter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/flock.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KB_FILE="$AGENT_ROOT/REPAIR_KNOWLEDGE.json"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ $# -lt 1 ]]; then
  echo "Usage: auto-repair.sh <action> [args...]" >&2
  echo "Actions: lookup, record, promote, mark-failed, track-failure, reset-failure" >&2
  exit 1
fi

action="$1"
shift

case "$action" in

  lookup)
    # Args: <agent> <operation> <error_output>
    if [[ $# -lt 3 ]]; then
      echo "Usage: auto-repair.sh lookup <agent> <operation> <error_output>" >&2
      exit 1
    fi
    agent="$1"; operation="$2"; error_output="$3"

    python3 -c "
import json,sys,re

agent, operation, error_output = sys.argv[1], sys.argv[2], sys.argv[3]

with open(sys.argv[4]) as f:
    kb = json.load(f)

matches = []
for entry in kb['entries']:
    if entry['agent'] != agent or entry['operation'] != operation:
        continue
    if entry['confidence'] == 'failed':
        continue  # skip known-bad alternatives
    try:
        if re.search(entry['error_pattern'], error_output):
            matches.append(entry)
    except re.error:
        if entry['error_pattern'] in error_output:
            matches.append(entry)

# Sort by confidence: high > medium > low
conf_order = {'high': 0, 'medium': 1, 'low': 2}
matches.sort(key=lambda e: conf_order.get(e['confidence'], 3))

if matches:
    result = {
        'found': True,
        'repair_id': matches[0]['id'],
        'alternative': matches[0]['successful_alternative'],
        'confidence': matches[0]['confidence']
    }
else:
    result = {'found': False}

json.dump(result, sys.stdout, indent=2)
print()
" "$agent" "$operation" "$error_output" "$KB_FILE"
    ;;

  record)
    # Args: <agent> <operation> <failed_approach> <failure_reason> <error_pattern> <successful_alternative>
    if [[ $# -lt 6 ]]; then
      echo "Usage: auto-repair.sh record <agent> <operation> <failed_approach> <failure_reason> <error_pattern> <successful_alternative>" >&2
      exit 1
    fi

    with_lock "$KB_FILE" python3 -c "
import json,sys
from datetime import datetime, timezone

agent = sys.argv[1]
operation = sys.argv[2]
failed_approach = sys.argv[3]
failure_reason = sys.argv[4]
error_pattern = sys.argv[5]
alternative = sys.argv[6]
kb_file = sys.argv[7]

with open(kb_file) as f:
    kb = json.load(f)

# Check for existing entry with same agent+operation+error_pattern
existing = None
for entry in kb['entries']:
    if (entry['agent'] == agent and
        entry['operation'] == operation and
        entry['error_pattern'] == error_pattern):
        existing = entry
        break

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

if existing:
    # Update existing
    existing['successful_alternative'] = alternative
    existing['occurrences'] += 1
    existing['last_seen'] = now
    # Promote confidence
    if existing['occurrences'] >= 3:
        existing['confidence'] = 'high'
    elif existing['occurrences'] >= 1:
        existing['confidence'] = 'medium'
    result = {'action': 'updated', 'id': existing['id'], 'confidence': existing['confidence']}
else:
    # Create new entry
    max_id = 0
    for e in kb['entries']:
        try:
            num = int(e['id'].split('-')[1])
            if num > max_id:
                max_id = num
        except (IndexError, ValueError):
            pass
    new_id = f'repair-{max_id + 1}'
    new_entry = {
        'id': new_id,
        'agent': agent,
        'operation': operation,
        'failed_approach': failed_approach,
        'failure_reason': failure_reason,
        'error_pattern': error_pattern,
        'successful_alternative': alternative,
        'confidence': 'low',
        'occurrences': 1,
        'last_seen': now
    }
    kb['entries'].append(new_entry)
    result = {'action': 'created', 'id': new_id, 'confidence': 'low'}

kb['last_updated'] = now
kb['version'] += 1

with open(kb_file, 'w') as f:
    json.dump(kb, f, indent=2)

json.dump(result, sys.stdout, indent=2)
print()
" "$1" "$2" "$3" "$4" "$5" "$6" "$KB_FILE"

    # Validate output against schema
    if ! node "$SCRIPT_DIR/validate-schemas.js" "$KB_FILE" "repair" >/dev/null 2>&1; then
      echo "ERROR: Schema validation failed for $KB_FILE" >&2
      # .invalid.json is already written by validate-schemas.js
      exit 1
    fi
    ;;

  promote)
    # No args — promote all entries based on occurrences
    with_lock "$KB_FILE" python3 -c "
import json,sys
from datetime import datetime, timezone

kb_file = sys.argv[1]
with open(kb_file) as f:
    kb = json.load(f)

promoted = 0
for entry in kb['entries']:
    if entry['confidence'] == 'failed':
        continue
    old = entry['confidence']
    if entry['occurrences'] >= 3:
        entry['confidence'] = 'high'
    elif entry['occurrences'] >= 1:
        entry['confidence'] = 'medium'
    if entry['confidence'] != old:
        promoted += 1

if promoted > 0:
    kb['last_updated'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    with open(kb_file, 'w') as f:
        json.dump(kb, f, indent=2)

print(json.dumps({'promoted': promoted}))
" "$KB_FILE"
    ;;

  mark-failed)
    # Args: <repair_id>
    if [[ $# -lt 1 ]]; then
      echo "Usage: auto-repair.sh mark-failed <repair_id>" >&2
      exit 1
    fi

    with_lock "$KB_FILE" python3 -c "
import json,sys
from datetime import datetime, timezone

repair_id = sys.argv[1]
kb_file = sys.argv[2]

with open(kb_file) as f:
    kb = json.load(f)

found = False
for entry in kb['entries']:
    if entry['id'] == repair_id:
        entry['confidence'] = 'failed'
        entry['last_seen'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        found = True
        break

if found:
    kb['last_updated'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    with open(kb_file, 'w') as f:
        json.dump(kb, f, indent=2)
    print(json.dumps({'marked_failed': True, 'id': repair_id}))
else:
    print(json.dumps({'marked_failed': False, 'error': f'repair entry {repair_id} not found'}))
    sys.exit(1)
" "$1" "$KB_FILE"
    ;;

  track-failure)
    # Args: <ticket_id> <agent> <operation>
    if [[ $# -lt 3 ]]; then
      echo "Usage: auto-repair.sh track-failure <ticket_id> <agent> <operation>" >&2
      exit 1
    fi
    ticket_id="$1"; agent="$2"; operation="$3"
    failure_file="$RUNS_DIR/$ticket_id/failures.json"
    mkdir -p "$RUNS_DIR/$ticket_id"

    if [[ ! -f "$failure_file" ]]; then
      echo '{}' > "$failure_file"
    fi

    with_lock "$failure_file" python3 -c "
import json,sys

ff = sys.argv[1]
key = f'{sys.argv[2]}:{sys.argv[3]}'

with open(ff) as f:
    data = json.load(f)

data[key] = data.get(key, 0) + 1

with open(ff, 'w') as f:
    json.dump(data, f, indent=2)

print(json.dumps({'agent': sys.argv[2], 'operation': sys.argv[3], 'consecutive_failures': data[key]}))
" "$failure_file" "$agent" "$operation"
    ;;

  reset-failure)
    # Args: <ticket_id> <agent> <operation>
    if [[ $# -lt 3 ]]; then
      echo "Usage: auto-repair.sh reset-failure <ticket_id> <agent> <operation>" >&2
      exit 1
    fi
    ticket_id="$1"; agent="$2"; operation="$3"
    failure_file="$RUNS_DIR/$ticket_id/failures.json"

    if [[ ! -f "$failure_file" ]]; then
      echo '{"reset":true,"count":0}'
      exit 0
    fi

    with_lock "$failure_file" python3 -c "
import json,sys

ff = sys.argv[1]
key = f'{sys.argv[2]}:{sys.argv[3]}'

with open(ff) as f:
    data = json.load(f)

data.pop(key, None)

with open(ff, 'w') as f:
    json.dump(data, f, indent=2)

print(json.dumps({'reset': True, 'count': 0}))
" "$failure_file" "$agent" "$operation"
    ;;

  *)
    echo "Unknown action: $action" >&2
    exit 1
    ;;
esac
