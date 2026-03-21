#!/usr/bin/env bash
# agent-learning.sh — Agent learning system for recurring behavioural mistakes
# Manages AGENT_LEARNING.json: pattern detection, standing instructions, lifecycle
#
# Args: $1=action $2...=action-specific args
# Actions:
#   gather <ticket_id>                          — collect last N runs' artefacts for Run Analyst
#   filter <agent>                              — return standing instructions for an agent
#   write <agent> <pattern> <source> <instruction> — add or update entry in AGENT_LEARNING.json
#   lifecycle <ticket_id>                       — process status transitions after a run
#   escalate                                    — check for persistent patterns, return escalation messages
#   increment-runs                              — increment runs_since_instruction for all active entries

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AL_FILE="$AGENT_ROOT/AGENT_LEARNING.json"
RUNS_DIR="$AGENT_ROOT/runs"

# Default learning window
AGENT_LEARNING_WINDOW="${AGENT_LEARNING_WINDOW:-5}"
AGENT_LEARNING_PERSISTENCE_THRESHOLD="${AGENT_LEARNING_PERSISTENCE_THRESHOLD:-2}"

if [[ $# -lt 1 ]]; then
  echo "Usage: agent-learning.sh <action> [args...]" >&2
  echo "Actions: gather, filter, write, lifecycle, escalate, increment-runs" >&2
  exit 1
fi

action="$1"
shift

case "$action" in

  gather)
    # Args: <ticket_id>
    # Collects artefacts from the last N completed runs for Run Analyst analysis.
    # Returns JSON with runs array, each containing available artefact paths.
    if [[ $# -lt 1 ]]; then
      echo "Usage: agent-learning.sh gather <ticket_id>" >&2
      exit 1
    fi
    current_ticket="$1"

    python3 -c "
import json, sys, os, glob

runs_dir = sys.argv[1]
window = int(sys.argv[2])
current_ticket = sys.argv[3]

# Find completed runs (have run.log with summary or EVENT entries)
completed = []
if os.path.isdir(runs_dir):
    for entry in os.listdir(runs_dir):
        run_path = os.path.join(runs_dir, entry)
        if not os.path.isdir(run_path):
            continue
        log_file = os.path.join(run_path, 'run.log')
        if not os.path.exists(log_file):
            continue
        # Check if run completed (has summary or event category entries)
        has_completion = False
        last_ts = None
        with open(log_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    last_ts = obj.get('ts', last_ts)
                    if obj.get('cat') == 'summary':
                        has_completion = True
                    if obj.get('cat') == 'event' and 'escalat' in obj.get('msg', '').lower():
                        has_completion = True
                except json.JSONDecodeError:
                    pass
        if has_completion:
            completed.append({
                'ticket': entry,
                'path': run_path,
                'last_ts': last_ts or ''
            })

# Sort by timestamp descending, take last N (excluding current ticket)
completed = [r for r in completed if r['ticket'] != current_ticket]
completed.sort(key=lambda r: r['last_ts'], reverse=True)
completed = completed[:window]

# Collect artefact paths for each run
runs = []
for run in completed:
    artefacts = {}
    for name in ['PRD.json', 'REVIEW.json', 'FEEDBACK.json', 'run.log', 'CONFLICT.json']:
        path = os.path.join(run['path'], name)
        if os.path.exists(path):
            artefacts[name] = path
    runs.append({
        'ticket': run['ticket'],
        'artefacts': artefacts
    })

# Also include current ticket if it has artefacts
current_path = os.path.join(runs_dir, current_ticket)
if os.path.isdir(current_path):
    current_artefacts = {}
    for name in ['PRD.json', 'REVIEW.json', 'FEEDBACK.json', 'run.log', 'CONFLICT.json']:
        path = os.path.join(current_path, name)
        if os.path.exists(path):
            current_artefacts[name] = path
    runs.insert(0, {
        'ticket': current_ticket,
        'artefacts': current_artefacts,
        'current': True
    })

result = {
    'window': window,
    'runs_found': len(runs),
    'runs': runs
}

json.dump(result, sys.stdout, indent=2)
print()
" "$RUNS_DIR" "$AGENT_LEARNING_WINDOW" "$current_ticket"
    ;;

  filter)
    # Args: <agent>
    # Returns standing instructions for a specific agent (active + resolved entries).
    # Output: JSON with instructions array, ready for injection into agent context.
    if [[ $# -lt 1 ]]; then
      echo "Usage: agent-learning.sh filter <agent>" >&2
      exit 1
    fi
    agent="$1"

    python3 -c "
import json, sys

agent = sys.argv[1]
al_file = sys.argv[2]

with open(al_file) as f:
    al = json.load(f)

instructions = []
for entry in al['entries']:
    if entry['agent'] != agent:
        continue
    if entry['status'] not in ('active', 'resolved'):
        continue
    instructions.append({
        'id': entry['id'],
        'instruction': entry['standing_instruction'],
        'status': entry['status'],
        'pattern': entry['pattern_description']
    })

result = {
    'agent': agent,
    'count': len(instructions),
    'instructions': instructions
}

json.dump(result, sys.stdout, indent=2)
print()
" "$agent" "$AL_FILE"
    ;;

  write)
    # Args: <agent> <pattern_description> <detection_source> <standing_instruction>
    # Adds a new entry or updates existing if same agent+pattern already exists.
    if [[ $# -lt 4 ]]; then
      echo "Usage: agent-learning.sh write <agent> <pattern_description> <detection_source> <standing_instruction>" >&2
      exit 1
    fi

    python3 -c "
import json, sys
from datetime import datetime, timezone

agent = sys.argv[1]
pattern = sys.argv[2]
source = sys.argv[3]
instruction = sys.argv[4]
al_file = sys.argv[5]

with open(al_file) as f:
    al = json.load(f)

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

# Check for existing entry with same agent+pattern
existing = None
for entry in al['entries']:
    if entry['agent'] == agent and entry['pattern_description'] == pattern:
        existing = entry
        break

if existing:
    # Update existing: increment occurrences, update source + instruction
    existing['occurrences'] += 1
    existing['last_seen'] = now
    existing['detection_source'] = source
    existing['standing_instruction'] = instruction
    # If it was resolved but recurred, check recurrence
    if existing['status'] == 'resolved':
        existing['status'] = 'active'
        existing['recurrences_after_instruction'] += 1
    elif existing['status'] == 'active' and existing['runs_since_instruction'] > 0:
        existing['recurrences_after_instruction'] += 1
    result = {
        'action': 'updated',
        'id': existing['id'],
        'occurrences': existing['occurrences'],
        'status': existing['status'],
        'recurrences_after_instruction': existing['recurrences_after_instruction']
    }
else:
    # Create new entry
    max_id = 0
    for e in al['entries']:
        try:
            num = int(e['id'].split('-')[1])
            if num > max_id:
                max_id = num
        except (IndexError, ValueError):
            pass
    new_id = f'learn-{max_id + 1:03d}'
    new_entry = {
        'id': new_id,
        'agent': agent,
        'pattern_description': pattern,
        'detection_source': source,
        'standing_instruction': instruction,
        'first_detected': now,
        'last_seen': now,
        'occurrences': 2,
        'runs_since_instruction': 0,
        'recurrences_after_instruction': 0,
        'status': 'active'
    }
    al['entries'].append(new_entry)
    result = {
        'action': 'created',
        'id': new_id,
        'status': 'active'
    }

al['last_updated'] = now
al['version'] += 1

with open(al_file, 'w') as f:
    json.dump(al, f, indent=2)

json.dump(result, sys.stdout, indent=2)
print()
" "$1" "$2" "$3" "$4" "$AL_FILE"
    ;;

  lifecycle)
    # Args: <ticket_id>
    # Processes status transitions after a completed run.
    # - Active entries: if pattern not seen in current run → increment runs_since_instruction
    # - Active entries: if runs_since_instruction >= 5 and no recurrences → resolved
    # - Active entries: if recurrences_after_instruction >= threshold → persistent
    # Requires current run's artefacts to determine if patterns recurred.
    if [[ $# -lt 1 ]]; then
      echo "Usage: agent-learning.sh lifecycle <ticket_id>" >&2
      exit 1
    fi
    ticket_id="$1"
    persistence_threshold="$AGENT_LEARNING_PERSISTENCE_THRESHOLD"

    python3 -c "
import json, sys

ticket_id = sys.argv[1]
al_file = sys.argv[2]
threshold = int(sys.argv[3])

with open(al_file) as f:
    al = json.load(f)

transitions = []

for entry in al['entries']:
    if entry['status'] == 'persistent':
        continue  # already escalated

    if entry['status'] == 'active':
        # Check if should transition to resolved
        if (entry['runs_since_instruction'] >= 5 and
                entry['recurrences_after_instruction'] == 0):
            entry['status'] = 'resolved'
            transitions.append({
                'id': entry['id'],
                'from': 'active',
                'to': 'resolved',
                'reason': f\"5+ clean runs (runs_since_instruction={entry['runs_since_instruction']})\"
            })

        # Check if should escalate to persistent
        elif entry['recurrences_after_instruction'] >= threshold:
            entry['status'] = 'persistent'
            transitions.append({
                'id': entry['id'],
                'from': 'active',
                'to': 'persistent',
                'reason': f\"{entry['recurrences_after_instruction']} recurrences after instruction (threshold={threshold})\"
            })

    elif entry['status'] == 'resolved':
        # Resolved can go back to active if pattern recurs (handled by write action)
        pass

from datetime import datetime, timezone
if transitions:
    al['last_updated'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    with open(al_file, 'w') as f:
        json.dump(al, f, indent=2)

result = {
    'ticket': ticket_id,
    'transitions': transitions,
    'total_entries': len(al['entries']),
    'active': sum(1 for e in al['entries'] if e['status'] == 'active'),
    'resolved': sum(1 for e in al['entries'] if e['status'] == 'resolved'),
    'persistent': sum(1 for e in al['entries'] if e['status'] == 'persistent')
}

json.dump(result, sys.stdout, indent=2)
print()
" "$ticket_id" "$AL_FILE" "$persistence_threshold"
    ;;

  escalate)
    # No args — check for persistent patterns and generate escalation messages.
    python3 -c "
import json, sys

al_file = sys.argv[1]

with open(al_file) as f:
    al = json.load(f)

escalations = []
for entry in al['entries']:
    if entry['status'] != 'persistent':
        continue
    msg = (
        f\"[AGENT LEARNING] Persistent pattern in {entry['agent']}:\\n\"
        f\"Pattern: {entry['pattern_description']}\\n\"
        f\"Instruction active for {entry['runs_since_instruction']} runs.\\n\"
        f\"Recurrences after instruction: {entry['recurrences_after_instruction']}\\n\"
        f\"Action required: Agent .md file may need structural revision.\\n\"
        f\"See AGENT_LEARNING.json entry {entry['id']} for full history.\"
    )
    escalations.append({
        'id': entry['id'],
        'agent': entry['agent'],
        'pattern': entry['pattern_description'],
        'recurrences_after_instruction': entry['recurrences_after_instruction'],
        'message': msg
    })

result = {
    'escalation_count': len(escalations),
    'escalations': escalations
}

json.dump(result, sys.stdout, indent=2)
print()
" "$AL_FILE"
    ;;

  increment-runs)
    # No args — increment runs_since_instruction for all active/resolved entries.
    # Call this at the END of every completed run, BEFORE lifecycle.
    python3 -c "
import json, sys
from datetime import datetime, timezone

al_file = sys.argv[1]

with open(al_file) as f:
    al = json.load(f)

incremented = 0
for entry in al['entries']:
    if entry['status'] in ('active', 'resolved'):
        entry['runs_since_instruction'] += 1
        incremented += 1

if incremented > 0:
    al['last_updated'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    with open(al_file, 'w') as f:
        json.dump(al, f, indent=2)

print(json.dumps({'incremented': incremented}))
" "$AL_FILE"
    ;;

  *)
    echo "Unknown action: $action" >&2
    echo "Actions: gather, filter, write, lifecycle, escalate, increment-runs" >&2
    exit 1
    ;;
esac
