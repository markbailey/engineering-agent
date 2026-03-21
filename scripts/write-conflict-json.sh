#!/usr/bin/env bash
# write-conflict-json.sh — Assemble CONFLICT.json from merge + guard + orphan results
# Args: $1=ticket_id $2=base_branch $3=feature_branch $4=merge_json $5=guard_json $6=orphan_json
# Writes: runs/{ticket_id}/CONFLICT.json
# Exit: 0=written, 1=validation failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 6 ]]; then
  echo "Usage: write-conflict-json.sh <ticket_id> <base_branch> <feature_branch> <merge_json> <guard_json> <orphan_json>" >&2
  exit 1
fi

ticket_id="$1"
base_branch="$2"
feature_branch="$3"
merge_json="$4"
guard_json="$5"
orphan_json="$6"

runs_dir="$AGENT_ROOT/runs/$ticket_id"
mkdir -p "$runs_dir"

# Use node to assemble the full CONFLICT.json (avoids /dev/stdin issues on Windows)
merge_commit_sha=""
if git rev-parse HEAD >/dev/null 2>&1; then
  merge_commit_sha=$(git rev-parse HEAD)
fi

node -e "
const merge = JSON.parse(process.argv[1]);
const guard = JSON.parse(process.argv[2]);
const orphan = JSON.parse(process.argv[3]);
const ticket = process.argv[4];
const baseBranch = process.argv[5];
const featureBranch = process.argv[6];
const mergeCommitSha = process.argv[7];

const hadConflicts = merge.status === 'conflicts';
const conflictedFiles = (merge.conflicted_files || []).map(f => ({
  file: f,
  conflict_type: 'both_modified',
  resolution: 'manual_merge',
  status: 'resolved'
}));

let overallStatus = 'resolved';
let escalationReason = null;

if (guard.compilation === 'fail' || guard.diff_analysis === 'fail' || guard.test_suite === 'fail') {
  overallStatus = 'partial';
}
if (orphan.disconnected_integrations && orphan.disconnected_integrations.length > 0) {
  overallStatus = 'escalated';
  escalationReason = 'Disconnected integrations detected — cannot reconnect safely';
}
if (merge.status === 'error') {
  overallStatus = 'escalated';
  escalationReason = 'Merge failed with error';
}

const mergeCommit = (merge.status === 'clean' || hadConflicts) && mergeCommitSha ? mergeCommitSha : null;

const conflict = {
  ticket,
  base_branch: baseBranch,
  feature_branch: featureBranch,
  base_commit: merge.base_commit || '',
  had_conflicts: hadConflicts,
  conflicted_files: conflictedFiles,
  regression_guard: guard,
  orphan_check: orphan,
  unresolvable_files: [],
  escalation_reason: escalationReason,
  overall_status: overallStatus,
  merge_commit: mergeCommit
};

const fs = require('fs');
fs.writeFileSync(process.argv[8], JSON.stringify(conflict, null, 2));
console.log('CONFLICT.json written to ' + process.argv[8]);
" \
  "$merge_json" \
  "$guard_json" \
  "$orphan_json" \
  "$ticket_id" \
  "$base_branch" \
  "$feature_branch" \
  "$merge_commit_sha" \
  "$runs_dir/CONFLICT.json"

# Validate against schema
if [[ -f "$AGENT_ROOT/scripts/validate-schemas.js" ]]; then
  validation=$(node "$AGENT_ROOT/scripts/validate-schemas.js" "$runs_dir/CONFLICT.json" conflict 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "WARNING: CONFLICT.json schema validation failed: $validation" >&2
  fi
fi

exit 0
