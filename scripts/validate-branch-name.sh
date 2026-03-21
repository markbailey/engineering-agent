#!/usr/bin/env bash
# validate-branch-name.sh — Validate branch name against naming convention
# Arg: $1=branch_name
# Exit 0=valid, exit 1=invalid

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

# Hard stop if AGENT_EMPLOYEE_CODE missing
if [[ -z "${AGENT_EMPLOYEE_CODE:-}" ]]; then
  echo '{"valid":false,"error":"AGENT_EMPLOYEE_CODE not set in .env"}' >&2
  exit 1
fi

if [[ ! "${AGENT_EMPLOYEE_CODE}" =~ ^[a-z]{3}$ ]]; then
  echo '{"valid":false,"error":"AGENT_EMPLOYEE_CODE must be exactly 3 lowercase letters"}' >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: validate-branch-name.sh <branch_name>" >&2
  exit 1
fi

branch="$1"

# Regex from prd.schema.json
BRANCH_REGEX='^[a-z0-9]+_[a-z]+-[0-9]+_.+_(feature|bug|defect|debt|chore)$'

if [[ ! "$branch" =~ $BRANCH_REGEX ]]; then
  echo "{\"valid\":false,\"error\":\"Branch name does not match format: {code}_{issue-id}_{desc}_{type}\"}" >&2
  exit 1
fi

# Validate prefix matches employee code
prefix="${branch%%_*}"
if [[ "$prefix" != "${AGENT_EMPLOYEE_CODE,,}" ]]; then
  echo "{\"valid\":false,\"error\":\"Branch prefix '$prefix' does not match AGENT_EMPLOYEE_CODE '${AGENT_EMPLOYEE_CODE,,}'\"}" >&2
  exit 1
fi

# Check not a protected branch
for protected in main master staging; do
  if [[ "$branch" == "$protected" ]]; then
    echo "{\"valid\":false,\"error\":\"Cannot use protected branch name: $protected\"}" >&2
    exit 1
  fi
done

echo '{"valid":true}'
exit 0
