#!/usr/bin/env bash
# preflight.sh — Pre-flight validation of tools, auth, env, repos, Jira
# Args: $1=project_key (optional — skip repo-specific checks if omitted)
# Output: JSON { overall, checks[] } to stdout
# Exit 0 if all pass, exit 1 if any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_KEY="${1:-}"

overall="pass"

# Accumulate checks as newline-delimited JSON objects in a temp file
CHECKS_FILE=$(mktemp)
trap 'rm -f "$CHECKS_FILE"' EXIT

# Helper: append a check result (name, status, error_or_empty)
add_check() {
  local name="$1" status="$2" error="${3:-}"
  if [[ "$status" == "fail" ]]; then
    overall="fail"
  fi
  if [[ -z "$error" ]]; then
    printf '{"name":"%s","status":"%s","error":null}\n' "$name" "$status" >> "$CHECKS_FILE"
  else
    # Use node to safely JSON-encode the error message
    node -e "process.stdout.write(JSON.stringify({name:process.argv[1],status:process.argv[2],error:process.argv[3]})+'\n')" \
      "$name" "$status" "$error" >> "$CHECKS_FILE"
  fi
}

# 1. Required tools on PATH
for tool in git gh node npm gitleaks; do
  if command -v "$tool" &>/dev/null; then
    add_check "tool_${tool}" "pass"
  else
    add_check "tool_${tool}" "fail" "${tool} not found on PATH"
  fi
done

# 1b. Optional tools (soft warning, not hard fail)
if command -v bc &>/dev/null; then
  add_check "tool_bc" "pass"
else
  add_check "tool_bc" "warn" "bc not found — jitter in retry-with-backoff.sh will use integer fallback"
fi

# 2. gh auth status
if gh auth status &>/dev/null; then
  add_check "gh_auth" "pass"
else
  add_check "gh_auth" "fail" "gh is not authenticated"
fi

# 3. .env exists
ENV_FILE="$AGENT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  add_check "env_file" "pass"
else
  add_check "env_file" "fail" ".env file not found"
fi

# Source .env for remaining checks (only if it exists)
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# 4. Required env vars
missing_vars=()
for var in AGENT_EMPLOYEE_CODE JIRA_URL JIRA_EMAIL; do
  if [[ -z "${!var:-}" ]]; then
    missing_vars+=("$var")
  fi
done
# Either JIRA_API_TOKEN or JIRA_PAT must be set
if [[ -z "${JIRA_API_TOKEN:-}" && -z "${JIRA_PAT:-}" ]]; then
  missing_vars+=("JIRA_API_TOKEN or JIRA_PAT")
fi

if [[ ${#missing_vars[@]} -eq 0 ]]; then
  add_check "env_vars" "pass"
else
  add_check "env_vars" "fail" "Missing env vars: ${missing_vars[*]}"
fi

# 5. AGENT_EMPLOYEE_CODE format
if [[ "${AGENT_EMPLOYEE_CODE:-}" =~ ^[a-z]{3}$ ]]; then
  add_check "employee_code" "pass"
else
  add_check "employee_code" "fail" "AGENT_EMPLOYEE_CODE must be exactly 3 lowercase letters"
fi

# 6. repos.json exists and is valid JSON
REPOS_JSON="$AGENT_ROOT/repos.json"
if [[ ! -f "$REPOS_JSON" ]]; then
  add_check "repos_json" "fail" "repos.json not found"
else
  if node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$REPOS_JSON" &>/dev/null; then
    add_check "repos_json" "pass"
  else
    add_check "repos_json" "fail" "repos.json is not valid JSON"
  fi
fi

# 7. Target repo validation (only if project_key provided)
if [[ -n "$PROJECT_KEY" && -f "$REPOS_JSON" ]]; then
  repo_path=$(node -e "
    const repos=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    const r=repos.repos && repos.repos[process.argv[2]];
    if(r && r.path) process.stdout.write(r.path);
    else process.exit(1);
  " "$REPOS_JSON" "$PROJECT_KEY" 2>/dev/null) || repo_path=""

  # Expand leading tilde to $HOME
  repo_path="${repo_path/#\~/$HOME}"

  if [[ -z "$repo_path" ]]; then
    add_check "target_repo" "fail" "Project key $PROJECT_KEY not found in repos.json"
  elif [[ ! -d "$repo_path" ]]; then
    add_check "target_repo" "fail" "Repo path does not exist: $repo_path"
  elif [[ ! -d "$repo_path/.git" ]] && ! git -C "$repo_path" rev-parse --git-dir &>/dev/null; then
    add_check "target_repo" "fail" "Not a git repository: $repo_path"
  elif ! git -C "$repo_path" remote get-url origin &>/dev/null; then
    add_check "target_repo" "fail" "No remote 'origin' in: $repo_path"
  else
    add_check "target_repo" "pass"
  fi
fi

# 8. Jira reachable
if [[ -n "${JIRA_URL:-}" ]]; then
  jira_token="${JIRA_API_TOKEN:-${JIRA_PAT:-}}"
  if [[ -n "${JIRA_API_TOKEN:-}" ]]; then
    auth_header="Authorization: Basic $(printf '%s:%s' "${JIRA_EMAIL:-}" "$jira_token" | base64)"
  else
    auth_header="Authorization: Bearer $jira_token"
  fi
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$JIRA_URL/rest/api/2/myself" \
    -H "$auth_header" 2>/dev/null) || http_code="000"
  if [[ "$http_code" == "200" || "$http_code" == "401" || "$http_code" == "403" ]]; then
    add_check "jira_reachable" "pass"
  else
    add_check "jira_reachable" "fail" "Jira not reachable (HTTP $http_code)"
  fi
else
  add_check "jira_reachable" "fail" "JIRA_URL not set, cannot check reachability"
fi

# 9. Resolve current GitHub user (non-blocking — empty string on failure)
github_user="${GITHUB_USER:-}"
if [[ -z "$github_user" ]]; then
  github_user=$(gh api user --jq '.login' 2>/dev/null) || github_user=""
fi

# Assemble final JSON from checks file
node -e "
  const fs=require('fs');
  const lines=fs.readFileSync(process.argv[1],'utf8').trim().split('\n').filter(Boolean);
  const checks=lines.map(l=>JSON.parse(l));
  const result={overall:process.argv[2],checks,github_user:process.argv[3]};
  process.stdout.write(JSON.stringify(result,null,2)+'\n');
" "$CHECKS_FILE" "$overall" "$github_user"

if [[ "$overall" == "fail" ]]; then
  exit 1
fi
exit 0
