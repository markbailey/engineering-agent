#!/usr/bin/env bash
# worktree-init.sh — Initialise a worktree (copy env, install deps, compile check)
# Args: $1=worktree_path $2=source_repo_path [$3=project_key] [--check-only]
# --check-only: report what needs re-init, exit 0 if OK, exit 1 if needs work
# Exit codes: 0=success, 1=dependency install failed, 2=tsc failed (ESCALATE)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
  echo "Usage: worktree-init.sh <worktree_path> <source_repo_path> [project_key] [--check-only]" >&2
  exit 1
fi

wt_path="$1"
source_path="$2"
project_key=""
check_only=false

# Parse remaining args: project_key (non-flag) and --check-only
shift 2
for arg in "$@"; do
  if [[ "$arg" == "--check-only" ]]; then
    check_only=true
  elif [[ -z "$project_key" ]]; then
    project_key="$arg"
  fi
done

# Helper: resolve toolchain command or return empty (use default)
resolve_cmd() {
  local step="$1"
  if [[ -n "$project_key" ]]; then
    local result
    result=$("$SCRIPT_DIR/resolve-toolchain.sh" "$project_key" "$step" 2>/dev/null || echo '{"skip":true}')
    local skip
    skip=$(echo "$result" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).skip)))" 2>/dev/null || echo "true")
    if [[ "$skip" == "false" ]]; then
      echo "$result" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(JSON.parse(d).command))" 2>/dev/null
      return 0
    fi
    echo "__SKIP__"
    return 0
  fi
  echo ""
}

if [[ ! -d "$wt_path" ]]; then
  echo "ERROR: Worktree path does not exist: $wt_path" >&2
  exit 1
fi

if [[ ! -d "$source_path" ]]; then
  echo "ERROR: Source repo path does not exist: $source_path" >&2
  exit 1
fi

needs_env=false
needs_deps=false
needs=()

# --- Step 1: Check non-committable files ---
if [[ ! -f "$wt_path/.env" ]]; then
  needs_env=true
  needs+=("env: .env missing")
fi

# --- Step 2: Check dependencies ---
if [[ ! -d "$wt_path/node_modules" ]] || [[ -z "$(ls -A "$wt_path/node_modules" 2>/dev/null)" ]]; then
  needs_deps=true
  needs+=("deps: node_modules missing or empty")
fi

# --- Check-only mode ---
if $check_only; then
  if [[ ${#needs[@]} -eq 0 ]]; then
    echo "Worktree OK — no re-init needed."
    exit 0
  else
    echo "Worktree needs re-init:"
    for n in "${needs[@]}"; do
      echo "  - $n"
    done
    exit 1
  fi
fi

# --- Step 1: Copy non-committable files ---
if $needs_env || [[ ! -f "$wt_path/.env" ]]; then
  echo "[init] Copying non-committable files..."
  files=$("$SCRIPT_DIR/discover-non-committable.sh" "$source_path" 2>/dev/null || true)
  if [[ -n "$files" ]]; then
    while IFS= read -r src_file; do
      fname=$(basename "$src_file")
      dst="$wt_path/$fname"
      # Never overwrite existing (resume safety)
      if [[ ! -f "$dst" ]]; then
        cp -p "$src_file" "$dst"
        echo "  Copied $fname"
      fi
    done <<< "$files"
  fi
fi

# Verify .env exists after copy
if [[ ! -f "$wt_path/.env" ]]; then
  echo "WARNING: .env still missing after copy — worktree may not work correctly" >&2
fi

# --- Step 2: Install dependencies ---
if $needs_deps || [[ ! -d "$wt_path/node_modules" ]]; then
  echo "[init] Installing dependencies..."
  cd "$wt_path"

  install_rc=0
  install_cmd=$(resolve_cmd "install")
  if [[ "$install_cmd" == "__SKIP__" ]]; then
    echo "[init] Install step skipped via toolchain config"
    install_rc=0
  elif [[ -n "$install_cmd" ]]; then
    "$SCRIPT_DIR/with-timeout.sh" "${AGENT_INSTALL_TIMEOUT:-300}" $install_cmd || install_rc=$?
  elif [[ -f "pnpm-lock.yaml" ]]; then
    "$SCRIPT_DIR/with-timeout.sh" "${AGENT_INSTALL_TIMEOUT:-300}" pnpm install --frozen-lockfile || install_rc=$?
  elif [[ -f "yarn.lock" ]]; then
    "$SCRIPT_DIR/with-timeout.sh" "${AGENT_INSTALL_TIMEOUT:-300}" yarn install --frozen-lockfile || install_rc=$?
  else
    "$SCRIPT_DIR/with-timeout.sh" "${AGENT_INSTALL_TIMEOUT:-300}" npm ci || install_rc=$?
  fi

  if [[ "$install_rc" -eq 124 ]]; then
    echo "ERROR: dependency install timed out after ${AGENT_INSTALL_TIMEOUT:-300}s" >&2
    exit 1
  elif [[ "$install_rc" -ne 0 ]]; then
    echo "ERROR: dependency install failed (exit $install_rc)" >&2
    exit 1
  fi

  # Reset formatting noise introduced by dependency install (postinstall scripts, etc.)
  echo "[init] Resetting formatting drift..."
  git checkout -- . 2>/dev/null || true
fi

# Verify node_modules
if [[ ! -d "$wt_path/node_modules" ]] || [[ -z "$(ls -A "$wt_path/node_modules" 2>/dev/null)" ]]; then
  echo "ERROR: node_modules still empty after install" >&2
  exit 1
fi

# --- Step 3: TypeScript compilation check ---
typecheck_cmd=$(resolve_cmd "typecheck")
if [[ "$typecheck_cmd" == "__SKIP__" ]]; then
  echo "[init] Typecheck step skipped via toolchain config"
elif [[ -n "$typecheck_cmd" ]]; then
  echo "[init] Running baseline typecheck: $typecheck_cmd"
  cd "$wt_path"
  if ! "$SCRIPT_DIR/with-timeout.sh" "${AGENT_TSC_TIMEOUT:-120}" $typecheck_cmd 2>&1; then
    echo "ESCALATE: typecheck failed in fresh worktree — base branch is broken" >&2
    exit 2
  fi
  echo "[init] Typecheck OK"
elif [[ -f "$wt_path/tsconfig.json" ]]; then
  echo "[init] Running baseline tsc --noEmit..."
  cd "$wt_path"
  if ! "$SCRIPT_DIR/with-timeout.sh" "${AGENT_TSC_TIMEOUT:-120}" npx tsc --noEmit 2>&1; then
    echo "ESCALATE: tsc --noEmit failed in fresh worktree — base branch is broken" >&2
    exit 2
  fi
  echo "[init] TypeScript compilation OK"
else
  echo "[init] No tsconfig.json — skipping tsc check"
fi

echo "[init] Worktree initialisation complete."
exit 0
