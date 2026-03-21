#!/usr/bin/env bash
# discover-non-committable.sh — Find non-committable files to copy into worktrees
# Arg: $1=source_repo_root
# Output: list of existing files (one per line)
# Skips directories, node_modules, .git

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: discover-non-committable.sh <source_repo_root>" >&2
  exit 1
fi

source_root="$1"

if [[ ! -d "$source_root" ]]; then
  echo "ERROR: Source repo root does not exist: $source_root" >&2
  exit 1
fi

# Known default patterns
KNOWN_PATTERNS=(".env" ".env.*" "*.local" "*.pem" "*.key")

found_files=()

# Collect patterns from .gitignore (file patterns only, not directories)
gitignore_patterns=()
if [[ -f "$source_root/.gitignore" ]]; then
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    # Skip negation patterns
    [[ "$line" =~ ^! ]] && continue
    # Skip directory patterns (ending with /)
    [[ "$line" =~ /$ ]] && continue
    # Skip path patterns (containing / not at end)
    [[ "$line" =~ / ]] && continue
    # Strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] && gitignore_patterns+=("$line")
  done < "$source_root/.gitignore"
fi

# Merge known patterns + gitignore patterns, deduplicate
all_patterns=()
declare -A seen
for p in "${KNOWN_PATTERNS[@]}" "${gitignore_patterns[@]}"; do
  if [[ -z "${seen[$p]:-}" ]]; then
    all_patterns+=("$p")
    seen[$p]=1
  fi
done

# Find matching files in source root (non-recursive, files only)
for pattern in "${all_patterns[@]}"; do
  # Use bash glob expansion
  for file in "$source_root"/$pattern; do
    [[ -f "$file" ]] || continue
    basename=$(basename "$file")
    # Skip node_modules and .git (shouldn't match but safety)
    [[ "$basename" == "node_modules" || "$basename" == ".git" ]] && continue
    echo "$file"
  done
done | sort -u
