#!/usr/bin/env bash
# resolve-toolchain.sh — Resolve toolchain command for a project+step
# Args: $1=project_key (e.g. SHRED) $2=step (e.g. typecheck, test, lint_fix, install)
# Reads repos.json, extracts toolchain.<step> command
# Output: {"skip": true, "reason": "..."} or {"skip": false, "command": "..."}
# Exit 0 always (null/missing is valid — means skip)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_JSON="$AGENT_ROOT/repos.json"

if [[ $# -lt 2 ]]; then
  echo '{"skip": true, "reason": "usage: resolve-toolchain.sh <project_key> <step>"}' >&2
  exit 0
fi

project_key="$1"
step="$2"

if [[ ! -f "$REPOS_JSON" ]]; then
  echo '{"skip": true, "reason": "repos.json not found"}'
  exit 0
fi

node -e "
const fs = require('fs');
const reposFile = process.argv[1];
const key = process.argv[2];
const step = process.argv[3];

let repos;
try {
  repos = JSON.parse(fs.readFileSync(reposFile, 'utf8'));
} catch (e) {
  console.log(JSON.stringify({ skip: true, reason: 'repos.json parse error' }));
  process.exit(0);
}

const repo = repos.repos && repos.repos[key];
if (!repo) {
  console.log(JSON.stringify({ skip: true, reason: 'project key not found: ' + key }));
  process.exit(0);
}

const toolchain = repo.toolchain;
if (!toolchain) {
  console.log(JSON.stringify({ skip: true, reason: 'no toolchain section for ' + key }));
  process.exit(0);
}

const cmd = toolchain[step];
if (cmd === undefined || cmd === null) {
  console.log(JSON.stringify({ skip: true, reason: step + ' not configured' }));
  process.exit(0);
}

console.log(JSON.stringify({ skip: false, command: cmd }));
" "$REPOS_JSON" "$project_key" "$step"
