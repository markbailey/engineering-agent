#!/usr/bin/env bash
# parse-args.sh — Parse invocation arguments for the orchestrator
# Arg: $1=raw_user_input (e.g. "PROJ-123 --dry-run")
# Output: JSON { "ticket_id", "project_key", "repo_name", "repo_path", "github_repo", "mode", "ready_pr", "pause", "stop" }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: parse-args.sh <raw_input>" >&2
  echo "Example: parse-args.sh 'PROJ-123 --dry-run'" >&2
  exit 1
fi

# Split input into words
input="$*"
ticket_id=""
dry_run=false
resume=false
ready_pr=false
pause=false
stop=false

for arg in $input; do
  case "$arg" in
    --dry-run)  dry_run=true ;;
    --resume)   resume=true ;;
    --ready-pr) ready_pr=true ;;
    --pause)    pause=true ;;
    --stop)     stop=true ;;
    -*)
      echo "{\"error\":\"Unknown flag: $arg\"}" >&2
      exit 1
      ;;
    *)
      # First non-flag argument is ticket_id
      if [[ -z "$ticket_id" ]]; then
        ticket_id="$arg"
      else
        echo "{\"error\":\"Unexpected argument: $arg (ticket_id already set to $ticket_id)\"}" >&2
        exit 1
      fi
      ;;
  esac
done

# Validate ticket_id
if [[ -z "$ticket_id" ]]; then
  echo '{"error":"Missing ticket ID"}' >&2
  exit 1
fi

if [[ ! "$ticket_id" =~ ^[A-Z]+-[0-9]+$ ]]; then
  echo "{\"error\":\"Invalid ticket ID format: $ticket_id (expected PROJ-123)\"}" >&2
  exit 1
fi

# Determine mode
mode="normal"
if $dry_run; then
  mode="dry_run"
elif $resume; then
  mode="resume"
fi

# Resolve target repo
repo_json=$("$SCRIPT_DIR/resolve-repo.sh" "$ticket_id") || {
  echo "$repo_json" >&2
  exit 1
}

# Merge repo fields into final output
echo "$repo_json" | node -e "
const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const extra = JSON.parse(process.argv[1]);
Object.assign(d, extra);
console.log(JSON.stringify(d));
" "{\"ticket_id\":\"$ticket_id\",\"mode\":\"$mode\",\"ready_pr\":$ready_pr,\"pause\":$pause,\"stop\":$stop}"
