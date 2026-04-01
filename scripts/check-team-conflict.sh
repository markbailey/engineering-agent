#!/usr/bin/env bash
# check-team-conflict.sh — Detect existing human branches/PRs on a ticket
# Before starting work, ensure no teammate is already working on this ticket
# Args: $1=ticket_id [--target-repo=PATH] [--github-repo=OWNER/REPO]
# Exit 0=clear, exit 1=conflict found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source rate limit awareness
# shellcheck disable=SC1091
source "$SCRIPT_DIR/rate-limit.sh"

# Load .env for employee code
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: check-team-conflict.sh <ticket_id> [--target-repo=PATH] [--github-repo=OWNER/REPO]" >&2
  exit 1
fi

ticket_id="$1"
target_repo=""
github_repo=""

shift
for arg in "$@"; do
  case "$arg" in
    --target-repo=*) target_repo="${arg#--target-repo=}" ;;
    --github-repo=*) github_repo="${arg#--github-repo=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

ticket_lower="$(echo "$ticket_id" | tr '[:upper:]' '[:lower:]')"
agent_code="${AGENT_EMPLOYEE_CODE:-}"
conflicts=()

# Build git command prefix
git_cmd=(git)
if [[ -n "$target_repo" ]]; then
  git_cmd=(git -C "$target_repo")
fi

# 1. Check remote branches matching ticket ID
"$SCRIPT_DIR/with-timeout.sh" "${AGENT_GH_TIMEOUT:-30}" "${git_cmd[@]}" fetch origin --prune 2>/dev/null || true
matching_branches=$("${git_cmd[@]}" branch -r 2>/dev/null | grep -i "$ticket_lower" | sed 's/^ *//' || true)

if [[ -n "$matching_branches" ]]; then
  while IFS= read -r branch; do
    branch_trimmed=$(echo "$branch" | xargs)
    # Skip if it's our own agent branch (starts with agent employee code)
    branch_name="${branch_trimmed#origin/}"
    if [[ -n "$agent_code" && "$branch_name" == "${agent_code}_"* ]]; then
      continue
    fi
    conflicts+=("branch:$branch_trimmed")
  done <<< "$matching_branches"
fi

# 2. Check open PRs matching ticket ID
pre_gh_check "$ticket_id"
gh_args=(pr list --search "$ticket_id" --state open --json number,author,headRefName,title)
if [[ -n "$github_repo" ]]; then
  gh_args+=(--repo "$github_repo")
fi
pr_list=$("$SCRIPT_DIR/with-timeout.sh" "${AGENT_GH_TIMEOUT:-30}" gh "${gh_args[@]}" 2>/dev/null || echo "[]")

if [[ "$pr_list" != "[]" && "$pr_list" != "" ]]; then
  pr_count=$(echo "$pr_list" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  if [[ "$pr_count" -gt 0 ]]; then
    for i in $(seq 0 $((pr_count - 1))); do
      pr_info=$(echo "$pr_list" | python3 -c "
import sys,json
prs=json.load(sys.stdin)
p=prs[$i]
print(f\"PR #{p['number']} by {p['author']['login']}: {p['title']} ({p['headRefName']})\")" 2>/dev/null || true)
      if [[ -n "$pr_info" ]]; then
        pr_branch=$(echo "$pr_list" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i]['headRefName'])" 2>/dev/null || true)
        if [[ -n "$agent_code" && "$pr_branch" == "${agent_code}_"* ]]; then
          continue
        fi
        conflicts+=("pr:$pr_info")
      fi
    done
  fi
fi

# Report results
if [[ ${#conflicts[@]} -eq 0 ]]; then
  echo '{"conflict":false,"ticket":"'"$ticket_id"'"}'
  exit 0
fi

echo "CONFLICT: Existing work found for $ticket_id" >&2
for c in "${conflicts[@]}"; do
  echo "  - $c" >&2
done
echo '{"conflict":true,"ticket":"'"$ticket_id"'","items":[' >&2
first=true
for c in "${conflicts[@]}"; do
  if [[ "$first" == "true" ]]; then
    first=false
  else
    echo ',' >&2
  fi
  escaped=$(echo "$c" | sed 's/"/\\"/g')
  echo "\"$escaped\"" >&2
done
echo ']}' >&2
exit 1
