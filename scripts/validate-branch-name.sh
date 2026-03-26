#!/usr/bin/env bash
# validate-branch-name.sh — Validate branch name against naming convention
# Arg: $1=branch_name
# Exit 0=valid, exit 1=invalid

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/output.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

# Hard stop if AGENT_EMPLOYEE_CODE missing
if [[ -z "${AGENT_EMPLOYEE_CODE:-}" ]]; then
  emit_error "AGENT_EMPLOYEE_CODE not set in .env"
fi

if [[ ! "${AGENT_EMPLOYEE_CODE}" =~ ^[a-z]{3}$ ]]; then
  emit_error "AGENT_EMPLOYEE_CODE must be exactly 3 lowercase letters"
fi

if [[ $# -lt 1 ]]; then
  emit_error "Usage: validate-branch-name.sh <branch_name>"
fi

branch="$1"

# Regex from prd.schema.json
BRANCH_REGEX='^[a-z0-9]+_[a-z]+-[0-9]+_.+_(feature|bug|defect|debt|chore)$'

if [[ ! "$branch" =~ $BRANCH_REGEX ]]; then
  emit_error "Branch name does not match format: {code}_{issue-id}_{desc}_{type}"
fi

# Validate prefix matches employee code
prefix="${branch%%_*}"
agent_code_lower="$(echo "$AGENT_EMPLOYEE_CODE" | tr '[:upper:]' '[:lower:]')"
if [[ "$prefix" != "$agent_code_lower" ]]; then
  emit_error "Branch prefix '$prefix' does not match AGENT_EMPLOYEE_CODE '$agent_code_lower'"
fi

# Check not a protected branch
for protected in main master staging; do
  if [[ "$branch" == "$protected" ]]; then
    emit_error "Cannot use protected branch name: $protected"
  fi
done

echo '{"valid":true}'
exit 0
