#!/usr/bin/env bash
# resolve-repo.sh — Resolve target repo from ticket ID via repos.json
# Args: $1=ticket_id (e.g. SHRED-123)
# Output: JSON { "project_key", "repo_name", "repo_path", "github_repo" }
# Exit 1 if project key not found in repos.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/output.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_JSON="$AGENT_ROOT/repos.json"

if [[ $# -lt 1 ]]; then
  emit_error "Usage: resolve-repo.sh <ticket_id>"
fi

ticket_id="$1"

# Extract project key (everything before first hyphen)
project_key="${ticket_id%%-*}"

if [[ -z "$project_key" ]]; then
  emit_error "Cannot extract project key from: $ticket_id"
fi

if [[ ! -f "$REPOS_JSON" ]]; then
  emit_error "repos.json not found at $REPOS_JSON"
fi

# Lookup repo in repos.json
result=$(node -e "
const fs = require('fs');
const reposFile = process.argv[1];
const key = process.argv[2];
const repos = JSON.parse(fs.readFileSync(reposFile, 'utf8'));
if (!repos.repos[key]) {
  console.error(JSON.stringify({error: 'Project key not found in repos.json: ' + key}));
  process.exit(1);
}
const r = repos.repos[key];
console.log(JSON.stringify({
  project_key: key,
  repo_name: r.name,
  repo_path: r.path,
  github_repo: r.github_repo
}));
" "$REPOS_JSON" "$project_key") || exit 1

echo "$result"
