#!/usr/bin/env bash
# flaky-test.sh — Flaky test detection and registry management
# Actions:
#   check  <test_name> <repo>           — lookup test in registry, returns {"flaky": true/false}
#   record <test_name> <repo> [--file path] — add/update entry in registry
#   retry  <ticket_id> <repo>           — placeholder for QA agent retry logic
# Registry: runs/flaky-tests/{repo_name}.json

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

action="${1:-}"
if [[ -z "$action" ]]; then
  echo "Usage: flaky-test.sh <check|record|retry> ..." >&2
  exit 2
fi
shift

registry_path() {
  local repo="$1"
  echo "$ROOT_DIR/runs/flaky-tests/${repo}.json"
}

ensure_registry() {
  local reg="$1"
  if [[ ! -f "$reg" ]]; then
    mkdir -p "$(dirname "$reg")"
    echo '{"version":1,"last_updated":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","entries":[]}' > "$reg"
  fi
}

case "$action" in
  check)
    test_name="${1:-}"
    repo="${2:-}"
    if [[ -z "$test_name" || -z "$repo" ]]; then
      echo "Usage: flaky-test.sh check <test_name> <repo>" >&2
      exit 2
    fi
    reg=$(registry_path "$repo")
    if [[ ! -f "$reg" ]]; then
      echo '{"flaky":false}'
      exit 0
    fi
    node -e "
      const fs = require('fs');
      const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
      const name = process.argv[2];
      const match = data.entries.find(e => e.test_name === name && (e.status === 'active' || e.status === 'permanent'));
      console.log(JSON.stringify({ flaky: !!match }));
    " "$reg" "$test_name"
    ;;

  record)
    test_name="${1:-}"
    repo="${2:-}"
    if [[ -z "$test_name" || -z "$repo" ]]; then
      echo "Usage: flaky-test.sh record <test_name> <repo> [--file path]" >&2
      exit 2
    fi
    shift 2
    file_path=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --file) file_path="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    reg=$(registry_path "$repo")
    ensure_registry "$reg"
    node -e "
      const fs = require('fs');
      const reg = process.argv[1];
      const testName = process.argv[2];
      const filePath = process.argv[3] || null;
      const repo = process.argv[4];
      const now = new Date().toISOString();

      const data = JSON.parse(fs.readFileSync(reg, 'utf8'));
      const existing = data.entries.find(e => e.test_name === testName && e.repo === repo);

      if (existing) {
        existing.occurrences += 1;
        existing.last_seen = now;
        if (filePath) existing.file = filePath;
        if (existing.status === 'resolved') existing.status = 'active';
      } else {
        const maxId = data.entries.reduce((max, e) => {
          const n = parseInt(e.id.replace('flaky-', ''), 10);
          return n > max ? n : max;
        }, 0);
        data.entries.push({
          id: 'flaky-' + String(maxId + 1).padStart(3, '0'),
          test_name: testName,
          file: filePath,
          repo: repo,
          first_seen: now,
          last_seen: now,
          occurrences: 1,
          status: 'active',
          notes: null
        });
      }

      data.last_updated = now;
      fs.writeFileSync(reg, JSON.stringify(data, null, 2) + '\n');
      console.log(JSON.stringify({ recorded: true, test_name: testName }));
    " "$reg" "$test_name" "$file_path" "$repo"
    ;;

  retry)
    ticket_id="${1:-}"
    repo="${2:-}"
    if [[ -z "$ticket_id" || -z "$repo" ]]; then
      echo "Usage: flaky-test.sh retry <ticket_id> <repo>" >&2
      exit 2
    fi
    # Placeholder — actual retry logic lives in QA agent
    echo '{"retried":0}'
    ;;

  *)
    echo "Unknown action: $action" >&2
    echo "Usage: flaky-test.sh <check|record|retry> ..." >&2
    exit 2
    ;;
esac
