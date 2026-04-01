#!/usr/bin/env bash
# parse-args.sh — Parse invocation arguments for the orchestrator
# Arg: $1=raw_user_input (e.g. "PROJ-123 --dry-run" or "./ticket.json --dry-run")
# Output: JSON { "ticket_id", "project_key", "repo_name", "repo_path", "github_repo", "mode", "ready_pr", "pause", "stop", "input_source", "input_file" }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: parse-args.sh <raw_input>" >&2
  echo "Example: parse-args.sh 'PROJ-123 --dry-run'" >&2
  echo "Example: parse-args.sh './ticket.json --dry-run'" >&2
  exit 1
fi

# Split input into words
input="$*"
first_arg=""
dry_run=false
resume=false
revert=false
ready_pr=false
pause=false
stop=false
auto_merge=false

for arg in $input; do
  case "$arg" in
    --dry-run)  dry_run=true ;;
    --resume)   resume=true ;;
    --revert)   revert=true ;;
    --ready-pr) ready_pr=true ;;
    --pause)    pause=true ;;
    --stop)     stop=true ;;
    --auto-merge) auto_merge=true ;;
    -*)
      echo "{\"error\":\"Unknown flag: $arg\"}" >&2
      exit 1
      ;;
    *)
      # First non-flag argument is ticket_id or file path
      if [[ -z "$first_arg" ]]; then
        first_arg="$arg"
      else
        echo "{\"error\":\"Unexpected argument: $arg (input already set to $first_arg)\"}" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$first_arg" ]]; then
  echo '{"error":"Missing ticket ID or file path"}' >&2
  exit 1
fi

# Determine mode
mode="normal"
if $dry_run; then
  mode="dry_run"
elif $resume; then
  mode="resume"
elif $revert; then
  mode="revert"
fi

# Detect input source: file path if contains . / or \
input_source="jira"
input_file="null"
ticket_id=""

if [[ "$first_arg" == *.json ]] || [[ "$first_arg" == */* ]] || [[ "$first_arg" == *\\* ]]; then
  # File path input
  input_source="local"

  # Resolve to absolute path
  if [[ "$first_arg" == /* ]]; then
    input_file="$first_arg"
  else
    input_file="$(cd "$(dirname "$first_arg")" 2>/dev/null && pwd)/$(basename "$first_arg")"
  fi

  if [[ ! -f "$input_file" ]]; then
    echo "{\"error\":\"Local ticket file not found: $first_arg\"}" >&2
    exit 1
  fi

  # Validate JSON and extract fields
  local_data=$(node -e "
const fs = require('fs');
const path = require('path');
const file = process.argv[1];
const schemaFile = path.resolve(process.argv[2], 'schemas/local-ticket.schema.json');

let data;
try { data = JSON.parse(fs.readFileSync(file, 'utf8')); }
catch (e) { console.error(JSON.stringify({error: 'Invalid JSON in ' + file + ': ' + e.message})); process.exit(1); }

let schema;
try { schema = JSON.parse(fs.readFileSync(schemaFile, 'utf8')); }
catch (e) { console.error(JSON.stringify({error: 'Cannot read schema: ' + e.message})); process.exit(1); }

// Validate required fields
const missing = schema.required.filter(f => !(f in data) || data[f] === '' || data[f] === null);
if (missing.length > 0) {
  console.error(JSON.stringify({error: 'Missing required fields: ' + missing.join(', ')}));
  process.exit(1);
}

// Validate ticket_id format
if (!/^[A-Z]+-[0-9]+\$/.test(data.ticket_id)) {
  console.error(JSON.stringify({error: 'Invalid ticket_id format: ' + data.ticket_id + ' (expected PROJ-123)'}));
  process.exit(1);
}

// Validate type
const validTypes = ['Story', 'Task', 'Bug'];
if (!validTypes.includes(data.type)) {
  console.error(JSON.stringify({error: 'Invalid type: ' + data.type + ' (expected: ' + validTypes.join(', ') + ')'}));
  process.exit(1);
}

// Validate acceptance_criteria
if (!Array.isArray(data.acceptance_criteria) || data.acceptance_criteria.length === 0) {
  console.error(JSON.stringify({error: 'acceptance_criteria must be a non-empty array'}));
  process.exit(1);
}

console.log(JSON.stringify({ticket_id: data.ticket_id, repo: data.repo}));
" "$input_file" "$AGENT_ROOT") || {
    echo "$local_data" >&2
    exit 1
  }

  ticket_id=$(echo "$local_data" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.ticket_id)") || {
    echo '{"error":"Failed to parse ticket_id from local ticket data"}' >&2
    exit 1
  }
  repo_key=$(echo "$local_data" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.repo)") || {
    echo '{"error":"Failed to parse repo from local ticket data"}' >&2
    exit 1
  }

  # Copy local JSON to runs/{ticket_id}/ticket.json for resume resilience
  runs_dir="$AGENT_ROOT/runs/$ticket_id"
  mkdir -p "$runs_dir"
  cp "$input_file" "$runs_dir/ticket.json"

  # Resolve repo using synthetic ticket ID to extract project key
  repo_json=$("$SCRIPT_DIR/resolve-repo.sh" "${repo_key}-0") || {
    echo "$repo_json" >&2
    exit 1
  }
else
  # Jira ticket ID input
  ticket_id="$first_arg"

  if [[ ! "$ticket_id" =~ ^[A-Z]+-[0-9]+$ ]]; then
    echo "{\"error\":\"Invalid ticket ID format: $ticket_id (expected PROJ-123)\"}" >&2
    exit 1
  fi

  # Resolve target repo
  repo_json=$("$SCRIPT_DIR/resolve-repo.sh" "$ticket_id") || {
    echo "$repo_json" >&2
    exit 1
  }
fi

# Merge repo fields into final output
echo "$repo_json" | node -e "
const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const extra = JSON.parse(process.argv[1]);
Object.assign(d, extra);
console.log(JSON.stringify(d));
" "{\"ticket_id\":\"$ticket_id\",\"mode\":\"$mode\",\"ready_pr\":$ready_pr,\"pause\":$pause,\"stop\":$stop,\"input_source\":\"$input_source\",\"input_file\":$( [[ "$input_file" == "null" ]] && echo 'null' || echo "\"$input_file\"" ),\"auto_merge\":$auto_merge}" || {
  echo '{"error":"Failed to assemble final output JSON"}' >&2
  exit 1
}
