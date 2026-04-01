#!/usr/bin/env bash
# run-secret-scan.sh — Run gitleaks on diff, output SECRETS.json
# Args: $1=worktree_path $2=base_branch $3=ticket_id
# Exit 0=clean, exit 1=findings (hard block)
# NEVER outputs secret values — always [REDACTED]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ $# -lt 3 ]]; then
  echo "Usage: run-secret-scan.sh <worktree_path> <base_branch> <ticket_id>" >&2
  exit 1
fi

worktree="$1"
base_branch="$2"
ticket_id="$3"

output_dir="$RUNS_DIR/$ticket_id"
mkdir -p "$output_dir"
output_file="$output_dir/SECRETS.json"
scan_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Locate gitleaks dynamically (no hardcoded paths)
GITLEAKS_BIN=$(command -v gitleaks 2>/dev/null || which gitleaks 2>/dev/null || echo "")


# If gitleaks not found, hard block (never skip scan)
if [[ -z "$GITLEAKS_BIN" ]]; then
  python3 -c "
import json,sys
doc = {
  'ticket': sys.argv[1],
  'scanned_at': sys.argv[2],
  'tool': 'gitleaks',
  'scan_target': 'diff',
  'findings': [{
    'id': 'secret-1',
    'rule_id': 'tool-failure',
    'description': 'gitleaks not found — scan could not run, treating as blocked',
    'file': 'N/A',
    'line': 1,
    'commit': 'N/A',
    'secret_type': 'unknown',
    'secret_value': '[REDACTED — never logged]'
  }],
  'status': 'blocked'
}
json.dump(doc, sys.stdout, indent=2)
" "$ticket_id" "$scan_time" > "$output_file"
  echo "BLOCKED: gitleaks not installed — cannot skip secret scan" >&2
  exit 1
fi

# Config file
config_flag=""
if [[ -f "$AGENT_ROOT/.gitleaks.toml" ]]; then
  config_flag="--config=$AGENT_ROOT/.gitleaks.toml"
fi

# Run gitleaks on diff — capture report as JSON
report_file=$(mktemp)
scan_exit=0
"$SCRIPT_DIR/with-timeout.sh" "${AGENT_GITLEAKS_TIMEOUT:-120}" \
  "$GITLEAKS_BIN" detect \
  --source "$worktree" \
  --log-opts="${base_branch}..HEAD" \
  --report-format=json \
  --report-path="$report_file" \
  $config_flag \
  --no-banner 2>/dev/null || scan_exit=$?

# Timeout: treat as blocked — never skip a scan
if [[ "$scan_exit" -eq 124 ]]; then
  echo "BLOCKED: gitleaks timed out — treating as blocked" >&2
  python3 -c "
import json,sys
doc = {
  'ticket': sys.argv[1],
  'scanned_at': sys.argv[2],
  'tool': 'gitleaks',
  'scan_target': 'diff',
  'findings': [{
    'id': 'secret-1',
    'rule_id': 'timeout',
    'description': 'gitleaks timed out — scan could not complete, treating as blocked',
    'file': 'N/A',
    'line': 1,
    'commit': 'N/A',
    'secret_type': 'unknown',
    'secret_value': '[REDACTED — never logged]'
  }],
  'status': 'blocked'
}
json.dump(doc, sys.stdout, indent=2)
" "$ticket_id" "$scan_time" > "$output_file"
  rm -f "$report_file"
  exit 1
fi

# Parse gitleaks output and build SECRETS.json (NEVER include secret values)
python3 -c "
import json,sys

ticket_id = sys.argv[1]
scan_time = sys.argv[2]
report_file = sys.argv[3]
scan_exit = int(sys.argv[4])

findings = []

# gitleaks exit 1 = findings, exit 0 = clean
if scan_exit != 0:
    try:
        with open(report_file) as f:
            raw = json.load(f)
        for i, item in enumerate(raw):
            findings.append({
                'id': f'secret-{i+1}',
                'rule_id': item.get('RuleID', 'unknown'),
                'description': item.get('Description', 'Secret detected'),
                'file': item.get('File', 'unknown'),
                'line': item.get('StartLine', 1),
                'commit': item.get('Commit', 'unknown'),
                'secret_type': item.get('RuleID', 'unknown'),
                'secret_value': '[REDACTED — never logged]'
            })
    except Exception:
        findings.append({
            'id': 'secret-1',
            'rule_id': 'parse-error',
            'description': 'Could not parse gitleaks report — treating as blocked',
            'file': 'N/A',
            'line': 1,
            'commit': 'N/A',
            'secret_type': 'unknown',
            'secret_value': '[REDACTED — never logged]'
        })

doc = {
    'ticket': ticket_id,
    'scanned_at': scan_time,
    'tool': 'gitleaks',
    'scan_target': 'diff',
    'findings': findings,
    'status': 'blocked' if findings else 'clean'
}
json.dump(doc, sys.stdout, indent=2)
print()
" "$ticket_id" "$scan_time" "$report_file" "$scan_exit" > "$output_file"

# Verify output was written successfully
if [[ ! -s "$output_file" ]]; then
  echo "ERROR: SECRETS.json was not written or is empty" >&2
  rm -f "$report_file"
  exit 1
fi

rm -f "$report_file"

# Validate output against schema
if ! node "$SCRIPT_DIR/validate-schemas.js" "$output_file" "secrets" >/dev/null 2>&1; then
  echo "ERROR: Schema validation failed for $output_file" >&2
  # .invalid.json is already written by validate-schemas.js
  exit 1
fi

# Check outcome
status=$(python3 -c "
import json,sys
with open(sys.argv[1]) as f:
    print(json.load(f)['status'])
" "$output_file")

if [[ "$status" == "blocked" ]]; then
  finding_count=$(python3 -c "
import json,sys
with open(sys.argv[1]) as f:
    print(len(json.load(f)['findings']))
" "$output_file")
  echo "BLOCKED: $finding_count secret(s) found — see $output_file" >&2
  echo "SECRETS.json written to: $output_file" >&2
  exit 1
fi

echo "Clean — no secrets found in diff"
echo "SECRETS.json written to: $output_file"
exit 0
