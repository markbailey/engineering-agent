#!/usr/bin/env bash
# generate-branch-name.sh — Generate branch name from ticket metadata
# Args: $1=employee_code $2=issue_id $3=title $4=issue_type
# Output: branch name matching prd.schema.json branch regex

set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Usage: generate-branch-name.sh <employee_code> <issue_id> <title> <issue_type>" >&2
  exit 1
fi

employee_code="$1"
issue_id="$2"
title="$3"
issue_type="$4"

# Lowercase everything
employee_code="$(echo "$employee_code" | tr '[:upper:]' '[:lower:]')"
issue_id="$(echo "$issue_id" | tr '[:upper:]' '[:lower:]')"
title="$(echo "$title" | tr '[:upper:]' '[:lower:]')"
issue_type="$(echo "$issue_type" | tr '[:upper:]' '[:lower:]')"

# Map issue type to branch type
case "$issue_type" in
  story|task)       branch_type="feature" ;;
  bug)              branch_type="bug" ;;
  defect)           branch_type="defect" ;;
  "technical debt") branch_type="debt" ;;
  chore)            branch_type="chore" ;;
  *)                branch_type="feature" ;;
esac

# Transliterate Unicode to ASCII (e.g. ü→u, é→e); fall back to strip if iconv unavailable
if command -v iconv &>/dev/null; then
  description=$(echo "$title" | iconv -t ASCII//TRANSLIT 2>/dev/null || echo "$title")
else
  description="$title"
fi
description=$(echo "$description" | sed 's/[^a-z0-9 -]//g' | sed 's/  */ /g' | sed 's/^ //;s/ $//')

# Spaces to hyphens
description="${description// /-}"

# Collapse multiple hyphens
description=$(echo "$description" | sed 's/-\{2,\}/-/g' | sed 's/^-//;s/-$//')

# Truncate to 40 chars at word boundary (hyphen = word boundary)
if [[ ${#description} -gt 40 ]]; then
  description="${description:0:40}"
  # Cut at last hyphen to avoid partial words
  if [[ "$description" == *-* ]]; then
    description="${description%-*}"
  fi
fi

# Remove trailing hyphen
description="${description%-}"

echo "${employee_code}_${issue_id}_${description}_${branch_type}"
