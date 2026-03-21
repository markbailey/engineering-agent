#!/usr/bin/env bash
# worktree-init.sh — Initialise a worktree (copy env, install deps, compile check)
# Args: $1=worktree_path $2=source_repo_path [--check-only]
# --check-only: report what needs re-init, exit 0 if OK, exit 1 if needs work
# Exit codes: 0=success, 1=dependency install failed, 2=tsc failed (ESCALATE)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
  echo "Usage: worktree-init.sh <worktree_path> <source_repo_path> [--check-only]" >&2
  exit 1
fi

wt_path="$1"
source_path="$2"
check_only=false

if [[ "${3:-}" == "--check-only" ]]; then
  check_only=true
fi

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

  if [[ -f "pnpm-lock.yaml" ]]; then
    pnpm install || { echo "ERROR: pnpm install failed" >&2; exit 1; }
  elif [[ -f "yarn.lock" ]]; then
    yarn install || { echo "ERROR: yarn install failed" >&2; exit 1; }
  else
    npm install || { echo "ERROR: npm install failed" >&2; exit 1; }
  fi
fi

# Verify node_modules
if [[ ! -d "$wt_path/node_modules" ]] || [[ -z "$(ls -A "$wt_path/node_modules" 2>/dev/null)" ]]; then
  echo "ERROR: node_modules still empty after install" >&2
  exit 1
fi

# --- Step 3: TypeScript compilation check ---
if [[ -f "$wt_path/tsconfig.json" ]]; then
  echo "[init] Running baseline tsc --noEmit..."
  cd "$wt_path"
  if ! npx tsc --noEmit 2>&1; then
    echo "ESCALATE: tsc --noEmit failed in fresh worktree — base branch is broken" >&2
    exit 2
  fi
  echo "[init] TypeScript compilation OK"
else
  echo "[init] No tsconfig.json — skipping tsc check"
fi

echo "[init] Worktree initialisation complete."
exit 0
