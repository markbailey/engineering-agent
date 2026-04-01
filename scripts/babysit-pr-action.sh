#!/usr/bin/env bash
# babysit-pr-action.sh — Per-PR action handler for the babysitter
#
# Handles a single PR action: acquires lock, creates/updates worktree,
# dispatches Claude with appropriate tools, verifies result, updates state, cleans up.
#
# Usage:
#   babysit-pr-action.sh --repo=OWNER/REPO --pr=NUMBER --branch=BRANCH --action=ACTION
#
# Actions: fix_ci, address_feedback, resolve_conflicts, auto_merge
#
# Exit codes: 0=success or lock held, 1=error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "$REPO_ROOT/.env" ]] && source "$REPO_ROOT/.env"

MAX_ATTEMPTS="${BABYSIT_MAX_ATTEMPTS:-2}"
LOCK_STALE_MINUTES="${BABYSIT_LOCK_STALE_MINUTES:-60}"

LOCK_DIR="$HOME/.claude/babysit/locks"
STATE_DIR="$HOME/.claude/babysit/state"
LOG_FILE="$HOME/.claude/babysit/babysit.log"

# Ensure directories exist
mkdir -p "$LOCK_DIR" "$STATE_DIR" "$(dirname "$LOG_FILE")"

# === Parse args ===
REPO="" PR="" BRANCH="" ACTION=""
for arg in "$@"; do
  case "$arg" in
    --repo=*) REPO="${arg#*=}" ;;
    --pr=*) PR="${arg#*=}" ;;
    --branch=*) BRANCH="${arg#*=}" ;;
    --action=*) ACTION="${arg#*=}" ;;
  esac
done

if [[ -z "$REPO" || -z "$PR" || -z "$BRANCH" || -z "$ACTION" ]]; then
  echo "Usage: babysit-pr-action.sh --repo=OWNER/REPO --pr=NUMBER --branch=BRANCH --action=ACTION" >&2
  exit 1
fi

# === Logging ===
babysit_log() {
  local level="$1" msg="$2"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local entry
  entry=$(jq -n --arg ts "$ts" --arg level "$level" --arg repo "$REPO" \
    --argjson pr "$PR" --arg action "$ACTION" --arg msg "$msg" \
    '{ts:$ts,level:$level,repo:$repo,pr:$pr,action:$action,msg:$msg}')
  echo "$entry" >> "$LOG_FILE"
  echo "[$level] $REPO #$PR $ACTION: $msg" >&2
}

# === Lock ===
lockdir="$LOCK_DIR/${REPO//\//_}_${PR}.lock"

# Check for stale lock
if [[ -d "$lockdir" ]]; then
  lock_age=0
  if [[ -f "$lockdir/created" ]]; then
    lock_created=$(cat "$lockdir/created")
    now=$(date +%s)
    lock_age=$(( (now - lock_created) / 60 ))
  fi
  if (( lock_age >= LOCK_STALE_MINUTES )); then
    babysit_log "WARN" "Removing stale lock (${lock_age}m old)"
    rm -rf "$lockdir"
  fi
fi

mkdir "$lockdir" 2>/dev/null || {
  babysit_log "INFO" "Lock already held, exiting"
  exit 0
}

# Store lock creation time
date +%s > "$lockdir/created"

# Clean up lock on exit (rm -rf because we store metadata files inside)
trap 'rm -rf "$lockdir"' EXIT INT TERM

# === Resolve repo info from repos.json ===
repo_name=$(jq -r '.repos | to_entries[] | select(.value.github_repo == "'"$REPO"'") | .value.name' "$REPO_ROOT/repos.json")
repo_path=$(jq -r '.repos | to_entries[] | select(.value.github_repo == "'"$REPO"'") | .value.path' "$REPO_ROOT/repos.json")

# Expand tilde
repo_path="${repo_path/#\~/$HOME}"

if [[ -z "$repo_name" || "$repo_name" == "null" || -z "$repo_path" || "$repo_path" == "null" ]]; then
  babysit_log "ERROR" "Could not resolve repo info for $REPO"
  exit 1
fi

# === Worktree ===
wt_path="$HOME/.claude/worktrees/${repo_name}/babysit-${PR}"

# Store paths in lock dir for stale cleanup
echo "$wt_path" > "$lockdir/wt_path"
echo "$repo_path" > "$lockdir/repo_path"

if [[ ! -d "$wt_path" ]]; then
  babysit_log "INFO" "Creating worktree at $wt_path"
  git -C "$repo_path" fetch origin
  git -C "$repo_path" worktree add "$wt_path" "$BRANCH" 2>/dev/null || {
    # Branch may already be checked out elsewhere — try detach+checkout
    git -C "$repo_path" worktree add "$wt_path" "origin/$BRANCH" --detach
    git -C "$wt_path" checkout -B "$BRANCH" "origin/$BRANCH"
  }

  # Init worktree (env copy, npm ci, tsc baseline)
  "$SCRIPT_DIR/worktree-init.sh" "$wt_path" "$repo_path" || {
    babysit_log "ERROR" "Worktree init failed"
    exit 1
  }
else
  babysit_log "INFO" "Updating existing worktree"
  git -C "$wt_path" fetch origin
  git -C "$wt_path" checkout "$BRANCH" 2>/dev/null || true
  git -C "$wt_path" pull --ff-only origin "$BRANCH" || {
    babysit_log "WARN" "ff-only pull failed, recreating worktree"
    git -C "$repo_path" worktree remove "$wt_path" --force 2>/dev/null || true
    git -C "$repo_path" worktree add "$wt_path" "origin/$BRANCH" --detach
    git -C "$wt_path" checkout -B "$BRANCH" "origin/$BRANCH"
    "$SCRIPT_DIR/worktree-init.sh" "$wt_path" "$repo_path" || {
      babysit_log "ERROR" "Worktree re-init failed"
      exit 1
    }
  }
fi

cd "$wt_path"

# Record pre-action state
pre_sha=$(git rev-parse HEAD)

# === State file ===
state_file="$STATE_DIR/${REPO//\//_}_${PR}.json"

# Check attempt count before dispatching
if [[ -f "$state_file" ]]; then
  prev_state=$(cat "$state_file")
else
  prev_state='{}'
fi

attempt_key="${ACTION}_attempts"
prev_attempts=$(echo "$prev_state" | jq -r ".[\"$attempt_key\"] // 0" 2>/dev/null || echo 0)

if (( prev_attempts >= MAX_ATTEMPTS )); then
  babysit_log "WARN" "Max attempts ($MAX_ATTEMPTS) already reached for $ACTION, skipping"
  exit 0
fi

# === Dispatch Claude ===
CLAUDE_TIMEOUT="${BABYSIT_CLAUDE_TIMEOUT:-1800}" # 30 min default
exit_code=0

case "$ACTION" in
  fix_ci)
    failed=$(gh pr checks "$PR" --repo "$REPO" --json name,conclusion \
      --jq '[.[] | select(.conclusion == "FAILURE")] | map(.name) | join(", ")' 2>/dev/null || echo "unknown")
    babysit_log "INFO" "Fixing CI failures: $failed"
    "$SCRIPT_DIR/with-timeout.sh" "$CLAUDE_TIMEOUT" claude \
      --allowedTools "Bash,Read,Edit,Write,Grep,Glob,Agent" \
      "Fix CI failures on PR #$PR ($REPO). Branch: $BRANCH. Failed checks: $failed.
       Work in $(pwd). Run failing tests, diagnose, fix, commit, push. No force push. No rm -rf. No git reset --hard." \
      || exit_code=$?
    ;;
  address_feedback)
    babysit_log "INFO" "Addressing review feedback"
    "$SCRIPT_DIR/with-timeout.sh" "$CLAUDE_TIMEOUT" claude \
      --allowedTools "Bash,Read,Edit,Write,Grep,Glob,Agent,Skill" \
      "/address-feedback $PR --include-bots" \
      || exit_code=$?
    ;;
  resolve_conflicts)
    babysit_log "INFO" "Resolving merge conflicts"
    "$SCRIPT_DIR/with-timeout.sh" "$CLAUDE_TIMEOUT" claude \
      --allowedTools "Bash,Read,Edit,Write,Grep,Glob,Agent" \
      "PR #$PR ($REPO) has merge conflicts on branch $BRANCH.
       Work in $(pwd). Merge main into $BRANCH, resolve all conflicts, commit, push. No force push. No rm -rf." \
      || exit_code=$?
    ;;
  auto_merge)
    babysit_log "INFO" "Enabling auto-merge"
    gh pr merge "$PR" --repo "$REPO" --auto --merge || exit_code=$?
    ;;
  review)
    REVIEW_MODEL="${BABYSIT_REVIEW_MODEL:-opus}"
    babysit_log "INFO" "Performing code review (model=$REVIEW_MODEL)"

    # Get base branch for diff context
    pr_base=$(gh pr view "$PR" --repo "$REPO" --json baseRefName --jq .baseRefName 2>/dev/null || echo "main")

    "$SCRIPT_DIR/with-timeout.sh" "$CLAUDE_TIMEOUT" claude -p \
      --model "$REVIEW_MODEL" \
      --allowedTools "Bash,Read,Edit,Write,Grep,Glob,Agent,Skill" \
      --max-turns 50 \
      "You are reviewing PR #$PR in $REPO (branch: $BRANCH, base: $pr_base). Work in $(pwd).

STEPS:
1. Run: gh pr diff $PR --repo $REPO
2. Read all changed files fully for context (don't just rely on the diff)
3. Invoke /coding-guidelines for review standards
4. Analyze: correctness, security (OWASP top 10), performance, readability, test coverage, edge cases

POSTING YOUR REVIEW:
Post a single review with inline file comments via the GitHub API. Write a JSON file using: review_file=\$(mktemp /tmp/review-${REPO//\//_}-$PR-XXXXXX.json)
{
  \"body\": \"## Code Review\\n\\nSummary of findings.\\n\\n🤖 Reviewed by [Claude Code](https://claude.com/claude-code)\",
  \"event\": \"REQUEST_CHANGES or APPROVE\",
  \"comments\": [
    {\"path\": \"relative/file.ts\", \"line\": 42, \"body\": \"Issue description\"}
  ]
}

Then submit: gh api repos/$REPO/pulls/$PR/reviews --input \$review_file

VERDICT RULES:
- If ANY correctness, security, or logic issues found → REQUEST_CHANGES with inline comments
- If only minor style/naming suggestions and no real issues → APPROVE (put suggestions in body, not as blocking)
- Empty comments array is valid for APPROVE

RULES:
- Be concise, actionable, specific in each comment
- Don't nitpick formatting/style that linters handle (prettier, eslint)
- Don't flag import order or whitespace
- Focus on logic bugs, security holes, missing edge cases, untested paths
- Always end review body with: 🤖 Reviewed by [Claude Code](https://claude.com/claude-code)
- Clean up \$review_file after posting" \
      || exit_code=$?
    ;;
  *)
    babysit_log "ERROR" "Unknown action: $ACTION"
    exit 1
    ;;
esac

# === Verify action succeeded ===
git fetch origin 2>/dev/null || true
post_sha=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "$pre_sha")
action_succeeded=false

case "$ACTION" in
  fix_ci|resolve_conflicts)
    # Success if a new commit was pushed
    if [[ "$pre_sha" != "$post_sha" && "$exit_code" -eq 0 ]]; then
      action_succeeded=true
    fi
    ;;
  address_feedback)
    # Success if threads resolved OR new commit pushed
    remaining=$(gh pr view "$PR" --repo "$REPO" --json reviewThreads \
      --jq '[.reviewThreads[] | select(.isResolved == false)] | length' 2>/dev/null || echo "-1")
    if [[ ("$remaining" -eq 0 || "$pre_sha" != "$post_sha") && "$exit_code" -eq 0 ]]; then
      action_succeeded=true
    fi
    ;;
  auto_merge)
    # gh pr merge --auto is idempotent
    if [[ "$exit_code" -eq 0 ]]; then
      action_succeeded=true
    fi
    ;;
  review)
    # Success if a review was submitted by us (check latest review on the PR)
    if [[ "$exit_code" -eq 0 ]]; then
      # Verify review was actually posted by checking the API
      github_user=$(gh api user --jq .login 2>/dev/null || echo "")
      if [[ -n "$github_user" ]]; then
        review_state=$(gh api "repos/$REPO/pulls/$PR/reviews" \
          --jq "[.[] | select(.user.login == \"$github_user\")] | sort_by(.submitted_at) | last | .state // empty" 2>/dev/null || echo "")
        if [[ "$review_state" == "APPROVED" || "$review_state" == "CHANGES_REQUESTED" ]]; then
          action_succeeded=true
        fi
      else
        # Can't verify, trust exit code
        action_succeeded=true
      fi
    fi
    ;;
esac

# === Update state file ===
current_head=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid 2>/dev/null || echo "$post_sha")

if [[ "$action_succeeded" == "true" ]]; then
  babysit_log "INFO" "Action succeeded"
  echo "$prev_state" | jq \
    --arg key "$attempt_key" \
    --arg event "$current_head" \
    '.[$key] = 0 | .last_event = $event | .last_result = "success"' \
    > "$state_file"
else
  new_attempts=$((prev_attempts + 1))
  babysit_log "ERROR" "Action failed (attempt $new_attempts/$MAX_ATTEMPTS)"
  echo "$prev_state" | jq \
    --arg key "$attempt_key" \
    --argjson val "$new_attempts" \
    --arg event "$current_head" \
    '.[$key] = $val | .last_event = $event | .last_result = "failure"' \
    > "$state_file"

  if (( new_attempts >= MAX_ATTEMPTS )); then
    "$SCRIPT_DIR/notify.sh" "BABYSIT" "escalation" \
      "PR #$PR ($REPO): $ACTION failed after $MAX_ATTEMPTS attempts — needs human attention" \
      "{\"pr\":$PR,\"repo\":\"$REPO\",\"action\":\"$ACTION\",\"attempts\":$new_attempts}" \
      2>/dev/null || true
  fi
fi

# === Cleanup worktree on success (keep on failure for debugging) ===
if [[ "$action_succeeded" == "true" && "$ACTION" != "address_feedback" ]]; then
  babysit_log "INFO" "Cleaning up worktree"
  git -C "$repo_path" worktree remove "$wt_path" --force 2>/dev/null || true
fi

babysit_log "INFO" "Handler complete (success=$action_succeeded)"
