#!/usr/bin/env bash
# update-prd-status.sh — Update PRD.json overall_status field
# Args: $1=ticket_id $2=new_status
# Valid statuses: pending, in_progress, review, pr_open, pr_approved, done, blocked_secrets, escalated

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ $# -lt 2 ]]; then
  echo "Usage: update-prd-status.sh <ticket_id> <new_status>" >&2
  exit 1
fi

ticket_id="$1"
new_status="$2"

# Validate status
valid_statuses="pending in_progress review pr_open pr_approved done blocked_secrets escalated"
if ! echo "$valid_statuses" | tr ' ' '\n' | grep -qx "$new_status"; then
  echo "ERROR: Invalid status '$new_status'. Valid: $valid_statuses" >&2
  exit 1
fi

prd_file="$RUNS_DIR/$ticket_id/PRD.json"

if [[ ! -f "$prd_file" ]]; then
  echo "ERROR: PRD.json not found at $prd_file" >&2
  exit 1
fi

# Update status
python3 -c "
import json,sys
prd_file, new_status = sys.argv[1], sys.argv[2]
with open(prd_file) as f:
    prd = json.load(f)
old_status = prd.get('overall_status', 'unknown')
prd['overall_status'] = new_status
with open(prd_file, 'w') as f:
    json.dump(prd, f, indent=2)
print(f'{old_status} -> {new_status}')
" "$prd_file" "$new_status"

# Validate output against schema
if ! node "$SCRIPT_DIR/validate-schemas.js" "$prd_file" "prd" >/dev/null 2>&1; then
  echo "ERROR: Schema validation failed for $prd_file" >&2
  # .invalid.json is already written by validate-schemas.js
  exit 1
fi

exit 0
