#!/usr/bin/env bash
# revert-run.sh — Mechanical revert of a merged PR for a ticket
# Args: $1=ticket_id [--target-repo=PATH] [--repo-name=NAME] [--github-repo=OWNER/REPO]
# Steps: read PRD.json → create revert branch → git revert → test → secret scan → open PR
# Output: JSON with revert PR URL or escalation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ $# -lt 1 ]]; then
  echo "Usage: revert-run.sh <ticket_id> [--target-repo=PATH] [--repo-name=NAME] [--github-repo=OWNER/REPO]" >&2
  exit 1
fi

ticket_id="$1"
shift

target_repo=""
repo_name=""
github_repo=""

for arg in "$@"; do
  case "$arg" in
    --target-repo=*) target_repo="${arg#--target-repo=}" ;;
    --repo-name=*)   repo_name="${arg#--repo-name=}" ;;
    --github-repo=*) github_repo="${arg#--github-repo=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Load .env for AGENT_EMPLOYEE_CODE
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

employee_code="${AGENT_EMPLOYEE_CODE:-}"
if [[ -z "$employee_code" ]]; then
  echo '{"status":"error","error":"AGENT_EMPLOYEE_CODE not set in .env","escalate":true}' >&2
  exit 1
fi

# Read PRD.json to find PR number and merge commit
prd_file="$RUNS_DIR/$ticket_id/PRD.json"
if [[ ! -f "$prd_file" ]]; then
  echo "{\"status\":\"error\",\"error\":\"PRD.json not found at $prd_file\",\"escalate\":true}"
  exit 1
fi

# Extract pr_number, merge_commit, branch info from PRD.json
read_result=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    prd = json.load(f)
pr_url = prd.get('pr_url', '')
pr_number = prd.get('pr_number', '')
merge_commit = prd.get('merge_commit', '')
base_branch = prd.get('base_branch', 'main')
branch = prd.get('branch', '')
# Try to extract PR number from URL if not explicit
if not pr_number and pr_url:
    parts = pr_url.rstrip('/').split('/')
    if parts:
        pr_number = parts[-1]
print(json.dumps({
    'pr_number': str(pr_number),
    'merge_commit': merge_commit,
    'base_branch': base_branch,
    'branch': branch
}))
" "$prd_file")

pr_number=$(echo "$read_result" | python3 -c "import json,sys; print(json.load(sys.stdin)['pr_number'])")
merge_commit=$(echo "$read_result" | python3 -c "import json,sys; print(json.load(sys.stdin)['merge_commit'])")
base_branch=$(echo "$read_result" | python3 -c "import json,sys; print(json.load(sys.stdin)['base_branch'])")

if [[ -z "$merge_commit" ]]; then
  # Try to get merge commit from gh if we have pr_number and github_repo
  if [[ -n "$pr_number" && -n "$github_repo" ]]; then
    merge_commit=$(gh pr view "$pr_number" --repo "$github_repo" --json mergeCommit --jq '.mergeCommit.oid' 2>/dev/null || echo "")
  fi
fi

if [[ -z "$merge_commit" ]]; then
  echo '{"status":"error","error":"Cannot determine merge commit from PRD.json or GitHub","escalate":true}'
  exit 1
fi

# Generate revert branch name
ticket_lower=$(echo "$ticket_id" | tr '[:upper:]' '[:lower:]')
revert_branch="${employee_code}_${ticket_lower}_revert_feature"

# Create worktree
if [[ -n "$target_repo" && -n "$repo_name" ]]; then
  wt_path=$("$SCRIPT_DIR/worktree-create.sh" "$revert_branch" "origin/$base_branch" \
    --target-repo="$target_repo" --repo-name="$repo_name")
elif [[ -n "$target_repo" ]]; then
  wt_path=$("$SCRIPT_DIR/worktree-create.sh" "$revert_branch" "origin/$base_branch" \
    --target-repo="$target_repo" --repo-name="$(basename "$target_repo")")
else
  echo '{"status":"error","error":"--target-repo is required","escalate":true}'
  exit 1
fi

# Run git revert in the worktree
cd "$wt_path"
if ! git revert "$merge_commit" --no-edit -m 1 2>/dev/null; then
  # Try without -m (non-merge commit)
  if ! git revert "$merge_commit" --no-edit 2>/dev/null; then
    echo "{\"status\":\"error\",\"error\":\"git revert failed for $merge_commit — conflicts likely\",\"escalate\":true,\"worktree\":\"$wt_path\"}"
    exit 1
  fi
fi

# Run tests via resolve-toolchain if available
if [[ -n "$target_repo" ]]; then
  project_key=$(echo "$ticket_id" | sed 's/-[0-9]*$//')
  test_result=$("$SCRIPT_DIR/resolve-toolchain.sh" "$project_key" "test" 2>/dev/null || echo '{"skip":true}')
  skip=$(echo "$test_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('skip', True))" 2>/dev/null || echo "True")
  if [[ "$skip" == "False" ]]; then
    test_cmd=$(echo "$test_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('command', ''))" 2>/dev/null || echo "")
    if [[ -n "$test_cmd" ]]; then
      if ! eval "$test_cmd" >/dev/null 2>&1; then
        echo "{\"status\":\"error\",\"error\":\"Tests failed after revert\",\"escalate\":true,\"worktree\":\"$wt_path\"}"
        exit 1
      fi
    fi
  fi
fi

# Secret scan
if ! "$SCRIPT_DIR/run-secret-scan.sh" "$wt_path" "$base_branch" "$ticket_id" >/dev/null 2>&1; then
  echo "{\"status\":\"error\",\"error\":\"Secret scan found issues after revert\",\"escalate\":true,\"worktree\":\"$wt_path\"}"
  exit 1
fi

# Push branch
git push -u origin "$revert_branch" 2>/dev/null

# Open PR
pr_title="revert: ${ticket_id} (reverts PR #${pr_number})"
pr_body="## Revert of ${ticket_id}

Reverts PR #${pr_number} (merge commit ${merge_commit}).

This is a mechanical revert — no logic changes.

### Testing
- [ ] Tests pass after revert
- [ ] Secret scan clean"

if [[ -n "$github_repo" ]]; then
  pr_url=$(gh pr create --repo "$github_repo" --base "$base_branch" --head "$revert_branch" \
    --title "$pr_title" --body "$pr_body" 2>/dev/null)
else
  pr_url=$(gh pr create --base "$base_branch" --head "$revert_branch" \
    --title "$pr_title" --body "$pr_body" 2>/dev/null)
fi

echo "{\"status\":\"success\",\"revert_pr_url\":\"$pr_url\",\"revert_branch\":\"$revert_branch\",\"merge_commit_reverted\":\"$merge_commit\",\"original_pr\":\"$pr_number\",\"worktree\":\"$wt_path\"}"
