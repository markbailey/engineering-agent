#!/usr/bin/env bash
# record-agent-versions.sh — Read version from frontmatter of each agents/*.md
# Output: JSON object { "agent-name": "version", ... }
#
# Usage:
#   record-agent-versions.sh                        # Output current versions
#   record-agent-versions.sh --check <prd_json> [--ticket=ID]  # Compare against PRD.json versions, log mismatches

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$AGENT_ROOT/agents"

# Parse args
check_mode=false
prd_file=""
ticket_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check_mode=true; prd_file="${2:-}"; shift 2 ;;
    --ticket=*) ticket_id="${1#--ticket=}"; shift ;;
    *) shift ;;
  esac
done

# Collect current versions
json="{"
first=true

for md_file in "$AGENTS_DIR"/*.md; do
  [[ -f "$md_file" ]] || continue
  filename=$(basename "$md_file")

  # Skip non-agent files (e.g. CHANGELOG.md)
  [[ "$filename" == "CHANGELOG.md" ]] && continue

  # Extract agent name from frontmatter
  agent_name=""
  version=""

  # Read frontmatter (between --- delimiters)
  in_frontmatter=false
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if $in_frontmatter; then
        break
      else
        in_frontmatter=true
        continue
      fi
    fi
    if $in_frontmatter; then
      if [[ "$line" =~ ^agent:\ *(.+)$ ]]; then
        agent_name="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^version:\ *(.+)$ ]]; then
        version="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$md_file"

  # Use filename as fallback agent name
  if [[ -z "$agent_name" ]]; then
    agent_name="${filename%.md}"
  fi

  if [[ -n "$version" ]]; then
    if ! $first; then
      json="$json,"
    fi
    json="$json\"$agent_name\":\"$version\""
    first=false
  fi
done

json="$json}"

# If not in check mode, just output current versions
if ! $check_mode; then
  echo "$json"
  exit 0
fi

# Check mode: compare against PRD.json agent_versions
if [[ -z "$prd_file" || ! -f "$prd_file" ]]; then
  echo "Error: PRD file not found: $prd_file" >&2
  exit 1
fi

# Extract agent_versions from PRD.json using node — single invocation, no /dev/stdin
mismatch_output=$(node -e "
const prd = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
const recorded = prd.agent_versions || {};
const current = JSON.parse(process.argv[2]);
const mismatches = [];
for (const [agent, oldVer] of Object.entries(recorded)) {
  const newVer = current[agent];
  if (newVer && newVer !== oldVer) {
    mismatches.push({ agent, old: oldVer, new: newVer });
  }
}
console.log(JSON.stringify({ count: mismatches.length, mismatches }));
" "$prd_file" "$json" 2>/dev/null || echo '{"count":0,"mismatches":[]}')

mismatch_count=$(node -e "console.log(JSON.parse(process.argv[1]).count)" "$mismatch_output" 2>/dev/null || echo 0)
mismatches=$(node -e "console.log(JSON.stringify(JSON.parse(process.argv[1]).mismatches))" "$mismatch_output" 2>/dev/null || echo "[]")

if [[ "$mismatch_count" -gt 0 ]]; then
  echo "[WARN] Agent version mismatches detected:" >&2

  # Parse and log each mismatch
  node -e "
    JSON.parse(process.argv[1]).forEach(m =>
      console.error('  Agent ' + m.agent + ' version changed: ' + m.old + ' -> ' + m.new));
  " "$mismatches"

  # Log to run.log if ticket provided
  if [[ -n "$ticket_id" ]]; then
    "$SCRIPT_DIR/run-log.sh" "$ticket_id" "WARN" "agent" \
      "Agent version mismatches on resume: $mismatch_count agent(s) changed" \
      "{\"mismatches\":$mismatches}" 2>/dev/null || true
  fi
fi

# Always output current versions
echo "$json"
