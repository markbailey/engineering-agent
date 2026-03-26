#!/usr/bin/env bash
# cleanup-orphans.sh — Audit runs + worktrees and clean up orphaned ones end-to-end
# Removes: run directory, worktree, local branch, remote branch
# Args: [--dry-run] [--force] [--ticket=TICKET-ID]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"
WORKTREES_BASE="$HOME/.claude/worktrees"
PROTECTED_BRANCHES=("main" "master" "staging")

# Load .env
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

agent_code="${AGENT_EMPLOYEE_CODE:-}"
if [[ -z "$agent_code" ]]; then
  echo "ERROR: AGENT_EMPLOYEE_CODE not set — cannot identify agent branches" >&2
  exit 1
fi
agent_code_lower="$(echo "$agent_code" | tr '[:upper:]' '[:lower:]')"

# --- Argument parsing ---
DRY_RUN=false
FORCE=false
TARGET_TICKET=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    --ticket=*) TARGET_TICKET="${arg#--ticket=}" ;;
    *) echo "Usage: cleanup-orphans.sh [--dry-run] [--force] [--ticket=TICKET-ID]" >&2; exit 1 ;;
  esac
done

# --- Counters ---
cleaned=0
skipped=0
errors=0

# --- Helpers ---

is_protected_branch() {
  local branch="$1"
  for pb in "${PROTECTED_BRANCHES[@]}"; do
    [[ "$branch" == "$pb" ]] && return 0
  done
  return 1
}

is_agent_branch() {
  local branch="$1"
  [[ "$branch" == "${agent_code_lower}_"* ]]
}

expand_tilde() {
  local path="$1"
  echo "${path/#\~/$HOME}"
}

# Resolve repo info from ticket ID via resolve-repo.sh
# Sets: _repo_name, _repo_path, _github_repo
resolve_repo() {
  local ticket_id="$1"
  local result
  result=$("$SCRIPT_DIR/resolve-repo.sh" "$ticket_id" 2>/dev/null) || return 1
  _repo_name=$(echo "$result" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d).repo_name)")
  _repo_path=$(expand_tilde "$(echo "$result" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d).repo_path)")")
  _github_repo=$(echo "$result" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d).github_repo)")
}

# Read PRD.json repos array + overall_status
# Sets: _overall_status, _repos_json (JSON array string)
read_prd() {
  local ticket_id="$1"
  local prd_file="$RUNS_DIR/$ticket_id/PRD.json"
  if [[ ! -f "$prd_file" ]]; then
    _overall_status=""
    _repos_json="[]"
    return 1
  fi
  local result
  result=$(node -e "
const fs = require('fs');
const prd = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
console.log(JSON.stringify({
  overall_status: prd.overall_status || '',
  repos: (prd.repos || []).map(r => ({
    name: r.name || '',
    branch: r.branch || '',
    worktree_path: r.worktree_path || '',
    github_repo: ''
  }))
}));
" "$prd_file" 2>/dev/null) || return 1
  _overall_status=$(echo "$result" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d).overall_status)")
  _repos_json=$(echo "$result" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.stringify(JSON.parse(d).repos))")
}

# Get PR state for a branch: merged, closed, open, or none
get_pr_state() {
  local github_repo="$1"
  local branch="$2"
  local pr_json
  pr_json=$(gh pr list --head "$branch" --repo "$github_repo" --state all --json state --limit 1 2>/dev/null) || { echo "none"; return; }
  if [[ "$pr_json" == "[]" || -z "$pr_json" ]]; then
    echo "none"
    return
  fi
  local state
  state=$(echo "$pr_json" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');const a=JSON.parse(d);console.log(a[0]?.state?.toUpperCase()||'NONE')")
  case "$state" in
    MERGED) echo "merged" ;;
    CLOSED) echo "closed" ;;
    OPEN) echo "open" ;;
    *) echo "none" ;;
  esac
}

# Check if any worktree exists for a ticket by scanning worktrees base
find_worktrees_for_ticket() {
  local ticket_id="$1"
  local ticket_lower
  ticket_lower="$(echo "$ticket_id" | tr '[:upper:]' '[:lower:]')"
  local found=()
  for repo_dir in "$WORKTREES_BASE"/*/; do
    [[ -d "$repo_dir" ]] || continue
    for wt in "$repo_dir"*/; do
      [[ -d "$wt" ]] || continue
      local branch_name
      branch_name="$(basename "$wt")"
      local branch_lower
      branch_lower="$(echo "$branch_name" | tr '[:upper:]' '[:lower:]')"
      if [[ "$branch_lower" == *"${ticket_lower}"* ]]; then
        found+=("$wt")
      fi
    done
  done
  echo "${found[@]:-}"
}

# --- Cleanup function ---

cleanup_ticket() {
  local ticket_id="$1"
  local label="[${ticket_id}]"

  # Resolve repo
  if ! resolve_repo "$ticket_id"; then
    echo "  $label WARN: could not resolve repo — scanning worktrees by pattern" >&2
  fi

  # Gather branches/worktrees from PRD.json or fallback scan
  local branches=()
  local worktree_paths=()
  local repo_paths=()

  if read_prd "$ticket_id" && [[ "$_repos_json" != "[]" ]]; then
    local count
    count=$(echo "$_repos_json" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d).length)")
    for ((i=0; i<count; i++)); do
      local branch wt_path
      branch=$(echo "$_repos_json" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d)[$i].branch)")
      wt_path=$(echo "$_repos_json" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d)[$i].worktree_path)")
      wt_path=$(expand_tilde "$wt_path")
      if [[ -n "$branch" ]]; then
        branches+=("$branch")
        worktree_paths+=("$wt_path")
        repo_paths+=("${_repo_path:-}")
      fi
    done
  fi

  # Fallback: scan worktrees dir for matching ticket ID
  if [[ ${#branches[@]} -eq 0 ]]; then
    local ticket_lower
    ticket_lower="$(echo "$ticket_id" | tr '[:upper:]' '[:lower:]')"
    for repo_dir in "$WORKTREES_BASE"/*/; do
      [[ -d "$repo_dir" ]] || continue
      for wt in "$repo_dir"*/; do
        [[ -d "$wt" ]] || continue
        local bname
        bname="$(basename "$wt")"
        local bname_lower
        bname_lower="$(echo "$bname" | tr '[:upper:]' '[:lower:]')"
        if [[ "$bname_lower" == *"${ticket_lower}"* ]]; then
          branches+=("$bname")
          worktree_paths+=("$wt")
          repo_paths+=("${_repo_path:-}")
        fi
      done
    done
  fi

  # Clean each branch/worktree
  for ((i=0; i<${#branches[@]}; i++)); do
    local branch="${branches[$i]}"
    local wt_path="${worktree_paths[$i]}"
    local rpath="${repo_paths[$i]}"

    # Safety: skip protected and non-agent branches
    if is_protected_branch "$branch"; then
      echo "  $label SKIP protected branch: $branch" >&2
      continue
    fi
    if ! is_agent_branch "$branch"; then
      echo "  $label SKIP non-agent branch: $branch" >&2
      continue
    fi

    # Remove worktree
    if [[ -d "$wt_path" ]]; then
      if $DRY_RUN; then
        echo "  $label Would remove worktree: $wt_path"
      else
        if [[ -n "$rpath" ]]; then
          git -C "$rpath" worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"
        else
          rm -rf "$wt_path"
        fi
        echo "  $label Removed worktree: $wt_path"
      fi
    fi

    # Delete local branch
    if [[ -n "$rpath" ]]; then
      if $DRY_RUN; then
        echo "  $label Would delete local branch: $branch"
      else
        git -C "$rpath" branch -D "$branch" 2>/dev/null || true
        echo "  $label Deleted local branch: $branch"
      fi
    fi

    # Delete remote branch
    if [[ -n "$rpath" ]]; then
      if $DRY_RUN; then
        echo "  $label Would delete remote branch: origin/$branch"
      else
        git -C "$rpath" push origin --delete "$branch" 2>/dev/null || true
        echo "  $label Deleted remote branch: origin/$branch"
      fi
    fi
  done

  # Remove PID file
  if [[ -f "$RUNS_DIR/$ticket_id/pid.json" ]]; then
    if $DRY_RUN; then
      echo "  $label Would remove pid.json"
    else
      "$SCRIPT_DIR/pid.sh" remove "$ticket_id" 2>/dev/null || true
    fi
  fi

  # Delete run directory
  if [[ -d "$RUNS_DIR/$ticket_id" ]]; then
    if $DRY_RUN; then
      echo "  $label Would delete run directory: runs/$ticket_id/"
    else
      rm -rf "$RUNS_DIR/$ticket_id"
      echo "  $label Deleted run directory: runs/$ticket_id/"
    fi
  fi
}

# --- Orphan detection ---

is_orphaned() {
  local ticket_id="$1"

  # PID check
  local pid_result
  pid_result=$("$SCRIPT_DIR/pid.sh" check "$ticket_id" 2>/dev/null) || pid_result='{"alive":false}'
  local alive
  alive=$(echo "$pid_result" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d).alive)" 2>/dev/null || echo "false")
  if [[ "$alive" == "true" ]] && ! $FORCE; then
    echo "alive_pid"
    return
  fi

  # Read PRD
  local has_prd=true
  if ! read_prd "$ticket_id"; then
    has_prd=false
  fi

  # Check worktree existence
  local wt_exists=false
  local wt_found
  wt_found=$(find_worktrees_for_ticket "$ticket_id")
  if [[ -n "$wt_found" ]]; then
    wt_exists=true
  fi

  # No PRD.json
  if ! $has_prd; then
    if $wt_exists && ! $FORCE; then
      echo "no_prd_has_worktree"
      return
    fi
    echo "orphaned_no_prd"
    return
  fi

  # done status
  if [[ "$_overall_status" == "done" ]]; then
    echo "orphaned_done"
    return
  fi

  # Check PR state per repo
  local pr_state="none"
  if resolve_repo "$ticket_id" 2>/dev/null; then
    local count
    count=$(echo "$_repos_json" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d).length)" 2>/dev/null || echo "0")
    for ((i=0; i<count; i++)); do
      local branch
      branch=$(echo "$_repos_json" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');console.log(JSON.parse(d)[$i].branch)" 2>/dev/null)
      if [[ -n "$branch" && -n "$_github_repo" ]]; then
        pr_state=$(get_pr_state "$_github_repo" "$branch")
        break  # use first repo's PR state
      fi
    done
  fi

  # PR-based decisions
  case "$pr_state" in
    merged) echo "orphaned_merged"; return ;;
    closed) echo "orphaned_closed"; return ;;
    open)
      if $FORCE; then
        echo "orphaned_force"; return
      fi
      echo "pr_open"; return
      ;;
  esac

  # No PR — check status
  case "$_overall_status" in
    blocked_secrets|escalated)
      if $FORCE; then
        echo "orphaned_force"; return
      fi
      echo "needs_human"; return
      ;;
  esac

  # Active status with no PR
  if $wt_exists && ! $FORCE; then
    echo "active_has_worktree"
    return
  fi

  # Active status, no PR, no worktree → stale artifacts
  if ! $wt_exists; then
    echo "orphaned_stale"
    return
  fi

  # Force mode catches everything else
  if $FORCE; then
    echo "orphaned_force"
    return
  fi

  echo "unknown"
}

# --- Main: process runs ---

echo "=== Cleanup Runs ==="
if $DRY_RUN; then
  echo "Mode: dry-run (no changes will be made)"
fi
if $FORCE; then
  echo "Mode: force (skipping safety checks)"
fi
echo ""

# Build ticket list
tickets=()
if [[ -n "$TARGET_TICKET" ]]; then
  tickets=("$TARGET_TICKET")
else
  if [[ -d "$RUNS_DIR" ]]; then
    for dir in "$RUNS_DIR"/*/; do
      [[ -d "$dir" ]] || continue
      tickets+=("$(basename "$dir")")
    done
  fi
fi

for ticket in "${tickets[@]}"; do
  result=$(is_orphaned "$ticket")
  case "$result" in
    orphaned_*)
      reason="${result#orphaned_}"
      echo "[$ticket] ORPHANED ($reason)"
      if cleanup_ticket "$ticket"; then
        cleaned=$((cleaned + 1))
      else
        errors=$((errors + 1))
      fi
      ;;
    alive_pid)
      echo "[$ticket] SKIP — process still alive"
      skipped=$((skipped + 1))
      ;;
    pr_open)
      echo "[$ticket] SKIP — PR is open"
      skipped=$((skipped + 1))
      ;;
    needs_human)
      echo "[$ticket] SKIP — needs human attention ($_overall_status)"
      skipped=$((skipped + 1))
      ;;
    active_has_worktree)
      echo "[$ticket] SKIP — active with worktree (no PR)"
      skipped=$((skipped + 1))
      ;;
    no_prd_has_worktree)
      echo "[$ticket] SKIP — no PRD but worktree exists"
      skipped=$((skipped + 1))
      ;;
    *)
      echo "[$ticket] SKIP — unknown state ($result)"
      skipped=$((skipped + 1))
      ;;
  esac
done

# --- Orphan worktrees without runs ---

echo ""
echo "=== Orphan Worktrees (no run directory) ==="

if [[ -d "$WORKTREES_BASE" ]]; then
  for repo_dir in "$WORKTREES_BASE"/*/; do
    [[ -d "$repo_dir" ]] || continue
    for wt in "$repo_dir"*/; do
      [[ -d "$wt" ]] || continue
      branch_name="$(basename "$wt")"
      repo_name="$(basename "$repo_dir")"

      # Extract ticket ID from branch name
      ticket_id=""
      branch_upper="$(echo "$branch_name" | tr '[:lower:]' '[:upper:]')"
      if [[ "$branch_upper" =~ ([A-Z]+-[0-9]+) ]]; then
        ticket_id="${BASH_REMATCH[1]}"
      fi

      if [[ -z "$ticket_id" ]]; then
        echo "[$repo_name/$branch_name] WARN — no ticket ID in branch name"
        continue
      fi

      # Skip if run dir exists (already processed above)
      if [[ -d "$RUNS_DIR/$ticket_id" ]]; then
        continue
      fi

      # Skip if targeting a specific ticket and this isn't it
      if [[ -n "$TARGET_TICKET" && "$ticket_id" != "$TARGET_TICKET" ]]; then
        continue
      fi

      # Safety
      if is_protected_branch "$branch_name"; then
        continue
      fi
      if ! is_agent_branch "$branch_name"; then
        continue
      fi

      echo "[$ticket_id] ORPHAN WORKTREE — $repo_name/$branch_name (no run dir)"

      # Resolve repo for branch operations
      local_repo_path=""
      if resolve_repo "$ticket_id" 2>/dev/null; then
        local_repo_path="$_repo_path"
      fi

      if $DRY_RUN; then
        echo "  [$ticket_id] Would remove worktree: $wt"
        [[ -n "$local_repo_path" ]] && echo "  [$ticket_id] Would delete local branch: $branch_name"
        [[ -n "$local_repo_path" ]] && echo "  [$ticket_id] Would delete remote branch: origin/$branch_name"
      else
        if [[ -n "$local_repo_path" ]]; then
          git -C "$local_repo_path" worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
          git -C "$local_repo_path" branch -D "$branch_name" 2>/dev/null || true
          git -C "$local_repo_path" push origin --delete "$branch_name" 2>/dev/null || true
        else
          rm -rf "$wt"
        fi
        echo "  [$ticket_id] Cleaned orphan worktree: $repo_name/$branch_name"
      fi
      cleaned=$((cleaned + 1))
    done
  done
fi

# --- Summary ---

echo ""
echo "=== Summary ==="
echo "Cleaned: $cleaned | Skipped: $skipped | Errors: $errors"
if $DRY_RUN; then
  echo "(dry-run — no changes were made)"
fi

exit 0
