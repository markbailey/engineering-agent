#!/usr/bin/env bash
# babysit-prs.sh — Continuous PR babysitter loop
# Monitors all open PRs (authored by current user) across repos in repos.json,
# detects actionable states, dispatches babysit-pr-action.sh to handle each.
#
# Usage: babysit-prs.sh [--once] [--dry-run]
#   --once      Single pass, no loop
#   --dry-run   Log actions, don't spawn handlers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../.env
[[ -f "$REPO_ROOT/.env" ]] && source "$REPO_ROOT/.env"
# shellcheck source=rate-limit.sh
source "$SCRIPT_DIR/rate-limit.sh"

# --- Config (from .env with defaults) ---
POLL_INTERVAL="${BABYSIT_POLL_INTERVAL:-300}"
SKIP_LABELS="${BABYSIT_SKIP_LABELS:-DO_NOT_MERGE,agent-ignore,wip,hold}"
MAX_CONCURRENT="${BABYSIT_MAX_CONCURRENT:-3}"
LOCK_STALE_MINUTES="${BABYSIT_LOCK_STALE_MINUTES:-60}"
AUTO_MERGE="${BABYSIT_AUTO_MERGE:-true}"
DRY_RUN="${BABYSIT_DRY_RUN:-false}"
MAX_ATTEMPTS="${BABYSIT_MAX_ATTEMPTS:-2}"

LOCK_DIR="$HOME/.claude/babysit/locks"
STATE_DIR="$HOME/.claude/babysit/state"
LOG_FILE="$HOME/.claude/babysit/babysit.log"

# --- Parse args ---
ONCE=false
for arg in "$@"; do
  case "$arg" in
    --once) ONCE=true ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

mkdir -p "$LOCK_DIR" "$STATE_DIR" "$(dirname "$LOG_FILE")"

# --- Logging (JSONL to babysit.log + stderr) ---
babysit_log() {
  local level="$1" repo="$2" pr="$3" action="$4" msg="$5"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local entry
  entry=$(jq -n --arg ts "$ts" --arg level "$level" --arg repo "$repo" \
    --argjson pr "$pr" --arg action "$action" --arg msg "$msg" \
    '{ts:$ts,level:$level,repo:$repo,pr:$pr,action:$action,msg:$msg}')
  echo "$entry" >> "$LOG_FILE"
  echo "[$level] $repo #$pr $action: $msg" >&2
}

# --- Child PID tracking for graceful shutdown ---
declare -a CHILD_PIDS=()
SHUTDOWN=false

cleanup_children() {
  SHUTDOWN=true
  for pid in "${CHILD_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  babysit_log "INFO" "-" 0 "shutdown" "Babysitter stopped (signal received)"
  exit 0
}
trap cleanup_children SIGINT SIGTERM

# --- Count active (non-stale) locks ---
count_active_locks() {
  local count=0
  for lockdir in "$LOCK_DIR"/*.lock; do
    [[ -d "$lockdir" ]] || continue
    count=$((count + 1))
  done
  echo "$count"
}

# --- Clean stale locks (and their worktrees) ---
clean_stale_locks() {
  for lockdir in "$LOCK_DIR"/*.lock; do
    [[ -d "$lockdir" ]] || continue
    # Check if lock dir is older than threshold
    if find "$lockdir" -maxdepth 0 -mmin +"$LOCK_STALE_MINUTES" 2>/dev/null | grep -q .; then
      # Stale — clean up associated worktree if recorded
      local wt_path
      wt_path=$(cat "$lockdir/wt_path" 2>/dev/null || echo "")
      if [[ -n "$wt_path" && -d "$wt_path" ]]; then
        local wt_repo_path
        wt_repo_path=$(cat "$lockdir/repo_path" 2>/dev/null || echo "")
        if [[ -n "$wt_repo_path" ]]; then
          git -C "$wt_repo_path" worktree remove "$wt_path" --force 2>/dev/null || true
        fi
      fi
      local lock_name
      lock_name=$(basename "$lockdir")
      babysit_log "WARN" "-" 0 "stale_lock" "Cleaned stale lock: $lock_name"
      rm -rf "$lockdir"
    fi
  done
}

# --- Reap finished child processes ---
reap_children() {
  local alive=()
  for pid in "${CHILD_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      alive+=("$pid")
    fi
  done
  CHILD_PIDS=("${alive[@]+"${alive[@]}"}")
}

# --- Check retry budget for a PR+action ---
check_retry_budget() {
  local repo="$1" pr="$2" action="$3"
  local state_file="$STATE_DIR/${repo//\//_}_${pr}.json"

  if [[ ! -f "$state_file" ]]; then
    return 0  # no state = no attempts = OK
  fi

  local attempts
  attempts=$(jq -r ".${action}_attempts // 0" "$state_file" 2>/dev/null || echo 0)

  # Reset budget if HEAD has changed since last attempt
  local last_head current_head
  last_event=$(jq -r ".last_event // \"\"" "$state_file" 2>/dev/null || echo "")
  pre_gh_check "BABYSIT" 2>/dev/null || true
  current_head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid 2>/dev/null || echo "")
  if [[ -n "$current_head" && "$current_head" != "$last_event" ]]; then
    return 0  # new commit resets budget
  fi

  if (( attempts >= MAX_ATTEMPTS )); then
    return 1  # budget exhausted
  fi
  return 0
}

# --- Determine action from poll output + thread count ---
determine_action() {
  local poll_json="$1" unresolved_threads="$2"

  local ci_status changes_requested mergeable reviews_approved
  ci_status=$(echo "$poll_json" | jq -r '.ci_status // "unknown"')
  changes_requested=$(echo "$poll_json" | jq -r '.changes_requested // false')
  mergeable=$(echo "$poll_json" | jq -r '.mergeable // "UNKNOWN"')
  reviews_approved=$(echo "$poll_json" | jq -r '.reviews_approved // 0')

  # Priority order
  if [[ "$ci_status" == "fail" ]]; then
    echo "fix_ci"
  elif [[ "$changes_requested" == "true" || "$unresolved_threads" -gt 0 ]]; then
    echo "address_feedback"
  elif [[ "$mergeable" == "CONFLICTING" ]]; then
    echo "resolve_conflicts"
  elif [[ "$ci_status" == "pass" && "$reviews_approved" -gt 0 && "$changes_requested" != "true" \
          && "$unresolved_threads" -eq 0 && "$mergeable" == "MERGEABLE" && "$AUTO_MERGE" == "true" ]]; then
    echo "auto_merge"
  else
    echo "none"
  fi
}

# --- Check if PR has any skip labels ---
has_skip_label() {
  local pr_labels_json="$1"
  IFS=',' read -ra skip_arr <<< "$SKIP_LABELS"
  for label in "${skip_arr[@]}"; do
    label=$(echo "$label" | xargs)  # trim whitespace
    if echo "$pr_labels_json" | jq -e --arg l "$label" 'map(.name) | index($l) != null' >/dev/null 2>&1; then
      return 0  # has skip label
    fi
  done
  return 1  # no skip labels
}

# === Main Loop ===
babysit_log "INFO" "-" 0 "startup" "Babysitter started (once=$ONCE, dry_run=$DRY_RUN)"

while true; do
  [[ "$SHUTDOWN" == true ]] && break

  reap_children
  clean_stale_locks

  # Get all repos from repos.json
  readarray -t ALL_REPOS < <(jq -r '.repos | to_entries[] | .value.github_repo' "$REPO_ROOT/repos.json" 2>/dev/null)

  for REPO in "${ALL_REPOS[@]}"; do
    [[ "$SHUTDOWN" == true ]] && break
    [[ -z "$REPO" ]] && continue

    # Rate limit check
    pre_gh_check "BABYSIT" 2>/dev/null || true

    # List open PRs authored by me
    pr_list=$(gh pr list --repo "$REPO" --author "@me" --state open \
      --json number,title,labels,headRefName,isDraft 2>/dev/null) || {
      babysit_log "ERROR" "$REPO" 0 "list" "Failed to list PRs"
      continue
    }

    pr_count=$(echo "$pr_list" | jq 'length')
    [[ "$pr_count" -eq 0 ]] && continue

    # Read into array to avoid subshell (CHILD_PIDS must update in parent)
    readarray -t pr_items < <(echo "$pr_list" | jq -c '.[]')

    for pr_json in "${pr_items[@]}"; do
      [[ "$SHUTDOWN" == true ]] && break
      [[ -z "$pr_json" ]] && continue

      pr_number=$(echo "$pr_json" | jq -r '.number')
      pr_branch=$(echo "$pr_json" | jq -r '.headRefName')
      pr_draft=$(echo "$pr_json" | jq -r '.isDraft')
      pr_labels=$(echo "$pr_json" | jq -c '.labels')

      # Skip drafts
      if [[ "$pr_draft" == "true" ]]; then
        babysit_log "INFO" "$REPO" "$pr_number" "skip" "Draft PR"
        continue
      fi

      # Skip labeled PRs
      if has_skip_label "$pr_labels"; then
        babysit_log "INFO" "$REPO" "$pr_number" "skip" "Skip label matched"
        continue
      fi

      # Skip if locked (in-progress handler)
      local_lockdir="$LOCK_DIR/${REPO//\//_}_${pr_number}.lock"
      if [[ -d "$local_lockdir" ]]; then
        babysit_log "INFO" "$REPO" "$pr_number" "skip" "Locked (in progress)"
        continue
      fi

      # Skip if at max concurrency
      active=$(count_active_locks)
      if (( active >= MAX_CONCURRENT )); then
        babysit_log "INFO" "$REPO" "$pr_number" "skip" "Max concurrent ($active/$MAX_CONCURRENT)"
        continue
      fi

      # Poll PR state
      pre_gh_check "BABYSIT" 2>/dev/null || true
      poll_output=$("$SCRIPT_DIR/pr-monitor-poll.sh" "BABYSIT" "$pr_number" --github-repo="$REPO" 2>/dev/null) || {
        babysit_log "WARN" "$REPO" "$pr_number" "poll" "Poll failed"
        continue
      }

      # Check unresolved review threads
      pre_gh_check "BABYSIT" 2>/dev/null || true
      unresolved_threads=$(gh pr view "$pr_number" --repo "$REPO" --json reviewThreads \
        --jq '[.reviewThreads[] | select(.isResolved == false)] | length' 2>/dev/null || echo 0)

      action=$(determine_action "$poll_output" "$unresolved_threads")

      if [[ "$action" == "none" ]]; then
        babysit_log "INFO" "$REPO" "$pr_number" "none" "No action needed"
        continue
      fi

      # Check retry budget
      if ! check_retry_budget "$REPO" "$pr_number" "$action"; then
        babysit_log "WARN" "$REPO" "$pr_number" "$action" "Attempts exhausted ($MAX_ATTEMPTS/$MAX_ATTEMPTS) — skipping"
        "$SCRIPT_DIR/notify.sh" "BABYSIT" "escalation" \
          "PR #$pr_number ($REPO): $action failed after $MAX_ATTEMPTS attempts — needs human attention" \
          "{\"pr\":$pr_number,\"repo\":\"$REPO\",\"action\":\"$action\"}" 2>/dev/null || true
        continue
      fi

      if [[ "$DRY_RUN" == "true" ]]; then
        babysit_log "INFO" "$REPO" "$pr_number" "$action" "[DRY RUN] Would dispatch"
        continue
      fi

      # Dispatch handler in background
      babysit_log "INFO" "$REPO" "$pr_number" "$action" "Dispatching handler"
      "$SCRIPT_DIR/babysit-pr-action.sh" \
        --repo="$REPO" --pr="$pr_number" --branch="$pr_branch" --action="$action" &
      CHILD_PIDS+=($!)
      babysit_log "INFO" "$REPO" "$pr_number" "$action" "Spawned handler (PID $!)"

    done  # pr loop
  done  # repo loop

  # --- Review-requested PRs (PRs others authored, requesting review from me) ---
  for REPO in "${ALL_REPOS[@]}"; do
    [[ "$SHUTDOWN" == true ]] && break
    [[ -z "$REPO" ]] && continue

    pre_gh_check "BABYSIT" 2>/dev/null || true

    review_list=$(gh pr list --repo "$REPO" --search "review-requested:@me" --state open \
      --json number,title,labels,headRefName,isDraft,author 2>/dev/null) || {
      babysit_log "ERROR" "$REPO" 0 "list" "Failed to list review-requested PRs"
      continue
    }

    review_count=$(echo "$review_list" | jq 'length')
    [[ "$review_count" -eq 0 ]] && continue

    readarray -t review_items < <(echo "$review_list" | jq -c '.[]')

    for pr_json in "${review_items[@]}"; do
      [[ "$SHUTDOWN" == true ]] && break
      [[ -z "$pr_json" ]] && continue

      pr_number=$(echo "$pr_json" | jq -r '.number')
      pr_branch=$(echo "$pr_json" | jq -r '.headRefName')
      pr_draft=$(echo "$pr_json" | jq -r '.isDraft')
      pr_labels=$(echo "$pr_json" | jq -c '.labels')

      # Skip drafts
      if [[ "$pr_draft" == "true" ]]; then
        babysit_log "INFO" "$REPO" "$pr_number" "skip" "Draft PR (review)"
        continue
      fi

      # Skip labeled PRs
      if has_skip_label "$pr_labels"; then
        babysit_log "INFO" "$REPO" "$pr_number" "skip" "Skip label matched (review)"
        continue
      fi

      # Skip if locked (in-progress handler)
      local_lockdir="$LOCK_DIR/${REPO//\//_}_${pr_number}.lock"
      if [[ -d "$local_lockdir" ]]; then
        babysit_log "INFO" "$REPO" "$pr_number" "skip" "Locked (review in progress)"
        continue
      fi

      # Skip if at max concurrency
      active=$(count_active_locks)
      if (( active >= MAX_CONCURRENT )); then
        babysit_log "INFO" "$REPO" "$pr_number" "skip" "Max concurrent ($active/$MAX_CONCURRENT)"
        continue
      fi

      # Check retry budget for review
      if ! check_retry_budget "$REPO" "$pr_number" "review"; then
        babysit_log "WARN" "$REPO" "$pr_number" "review" "Attempts exhausted ($MAX_ATTEMPTS/$MAX_ATTEMPTS) — skipping"
        continue
      fi

      if [[ "$DRY_RUN" == "true" ]]; then
        babysit_log "INFO" "$REPO" "$pr_number" "review" "[DRY RUN] Would dispatch review"
        continue
      fi

      # Dispatch review handler in background
      babysit_log "INFO" "$REPO" "$pr_number" "review" "Dispatching review handler"
      "$SCRIPT_DIR/babysit-pr-action.sh" \
        --repo="$REPO" --pr="$pr_number" --branch="$pr_branch" --action="review" &
      CHILD_PIDS+=($!)
      babysit_log "INFO" "$REPO" "$pr_number" "review" "Spawned review handler (PID $!)"

    done  # review pr loop
  done  # review repo loop

  if [[ "$ONCE" == "true" ]]; then
    # Wait for all handlers to finish in --once mode
    wait 2>/dev/null || true
    break
  fi

  babysit_log "INFO" "-" 0 "sleep" "Sleeping ${POLL_INTERVAL}s"
  sleep "$POLL_INTERVAL"
done

babysit_log "INFO" "-" 0 "shutdown" "Babysitter stopped"
