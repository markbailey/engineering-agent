#!/usr/bin/env bash
# validate-commit-msg.sh — Validate commit message against Conventional Commits
# Arg: $1=commit_message (or reads from stdin)
# Output: JSON { "valid": true/false, "issues": [...] }

set -euo pipefail

if [[ $# -ge 1 ]]; then
  msg="$1"
else
  msg=$(cat)
fi

issues=()

# Extract first line
first_line=$(echo "$msg" | head -n1)

# Valid types
VALID_TYPES="feat|fix|refactor|test|chore|debt|perf|docs|ci"

# Check format: type(scope): description  OR  type: description
if [[ "$first_line" =~ ^($VALID_TYPES)(\([a-zA-Z0-9_-]+\))?:\ .+ ]]; then
  : # valid format
else
  issues+=("First line must match: {type}({scope}): {description}")
fi

# Check first line length (72 char limit, conventional)
if [[ ${#first_line} -gt 72 ]]; then
  issues+=("First line exceeds 72 characters (${#first_line})")
fi

# Check for Refs: footer (only for non-QA, non-merge commits)
if [[ ! "$first_line" =~ ^chore:\ auto-fix ]] && [[ ! "$first_line" =~ ^Merge ]]; then
  if ! echo "$msg" | grep -qE '^Refs: [A-Z]+-[0-9]+'; then
    issues+=("Missing 'Refs: TICKET-ID' footer")
  fi
fi

# Build JSON output
if [[ ${#issues[@]} -eq 0 ]]; then
  echo '{"valid":true,"issues":[]}'
else
  # Build issues array
  json_issues=""
  for i in "${issues[@]}"; do
    escaped=$(echo "$i" | sed 's/"/\\"/g')
    if [[ -n "$json_issues" ]]; then
      json_issues="$json_issues,"
    fi
    json_issues="$json_issues\"$escaped\""
  done
  echo "{\"valid\":false,\"issues\":[$json_issues]}"
fi
