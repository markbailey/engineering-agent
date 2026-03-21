#!/usr/bin/env bash
# setup.sh — Validate environment and prerequisites for engineering-agent
# Run this before first use. Hard stops on missing critical config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Engineering Agent Setup ==="
echo ""

errors=()
warnings=()

# --- Load .env ---
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
  echo "[OK] .env loaded"
else
  errors+=(".env file not found — copy .env.example to .env and fill in values")
fi

# --- HARD STOP: AGENT_EMPLOYEE_CODE ---
if [[ -z "${AGENT_EMPLOYEE_CODE:-}" ]]; then
  echo ""
  echo "FATAL: AGENT_EMPLOYEE_CODE is not set in .env"
  echo "This is required for branch naming. Set a 3-letter lowercase code."
  exit 1
fi

if [[ ! "${AGENT_EMPLOYEE_CODE}" =~ ^[a-z]{3}$ ]]; then
  echo ""
  echo "FATAL: AGENT_EMPLOYEE_CODE must be exactly 3 lowercase letters (got: $AGENT_EMPLOYEE_CODE)"
  exit 1
fi
echo "[OK] AGENT_EMPLOYEE_CODE = $AGENT_EMPLOYEE_CODE"

# --- Check tools ---
check_tool() {
  local name="$1"
  local cmd="$2"
  if command -v "$cmd" &>/dev/null; then
    echo "[OK] $name found"
  else
    errors+=("$name ($cmd) not found in PATH")
  fi
}

check_tool "GitHub CLI" "gh"
check_tool "gitleaks" "gitleaks"
check_tool "Node.js" "node"
check_tool "npm" "npm"
check_tool "git" "git"

# --- Check gh auth ---
if command -v gh &>/dev/null; then
  if gh auth status &>/dev/null; then
    echo "[OK] gh authenticated"
  else
    errors+=("gh not authenticated — run 'gh auth login'")
  fi
fi

# --- Check Jira config ---
if [[ -n "${JIRA_URL:-}" ]]; then
  echo "[OK] JIRA_URL set"
  jira_type=$("$SCRIPT_DIR/detect-jira.sh" 2>/dev/null || echo "unknown")
  echo "     Jira type: $jira_type"
else
  errors+=("JIRA_URL not set in .env")
fi

# --- Check repos.json ---
REPOS_JSON="$AGENT_ROOT/repos.json"
if [[ -f "$REPOS_JSON" ]]; then
  # Validate JSON and check repo paths
  repo_check=$(node -e "
const fs = require('fs');
const repos = JSON.parse(fs.readFileSync('$REPOS_JSON', 'utf8'));
const keys = Object.keys(repos.repos || {});
if (keys.length === 0) { console.log('ERROR:repos.json has no repos configured'); process.exit(0); }
for (const k of keys) {
  const r = repos.repos[k];
  if (!r.path) { console.log('ERROR:' + k + ' missing path'); continue; }
  if (!r.name) { console.log('ERROR:' + k + ' missing name'); continue; }
  if (!r.github_repo) { console.log('ERROR:' + k + ' missing github_repo'); continue; }
  if (!fs.existsSync(r.path)) { console.log('WARN:' + k + ' path not found: ' + r.path); continue; }
  if (!fs.existsSync(r.path + '/.git')) { console.log('WARN:' + k + ' not a git repo: ' + r.path); continue; }
  console.log('OK:' + k + ' -> ' + r.name + ' (' + r.path + ')');
}
" 2>/dev/null || echo "ERROR:repos.json is not valid JSON")

  while IFS= read -r line; do
    case "$line" in
      OK:*) echo "[OK] Repo: ${line#OK:}" ;;
      WARN:*) warnings+=("Repo: ${line#WARN:}") ;;
      ERROR:*) errors+=("Repo: ${line#ERROR:}") ;;
    esac
  done <<< "$repo_check"
else
  errors+=("repos.json not found — create it with project-to-repo mappings")
fi

# --- Check worktrees directory ---
WORKTREES_DIR="$HOME/.claude/worktrees"
if [[ -d "$WORKTREES_DIR" ]]; then
  echo "[OK] Worktrees directory exists at $WORKTREES_DIR"
else
  warnings+=("Worktrees directory not found at $WORKTREES_DIR — will be created on first run")
fi

# --- Summary ---
echo ""
if [[ ${#errors[@]} -gt 0 ]]; then
  echo "=== ERRORS (must fix) ==="
  for e in "${errors[@]}"; do
    echo "  x $e"
  done
fi

if [[ ${#warnings[@]} -gt 0 ]]; then
  echo "=== WARNINGS ==="
  for w in "${warnings[@]}"; do
    echo "  ! $w"
  done
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  echo ""
  echo "Setup incomplete — fix errors above and re-run."
  exit 1
fi

echo "=== Setup complete ==="
