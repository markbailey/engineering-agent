#!/usr/bin/env bash
# detect-jira.sh — Identify whether JIRA_URL points to Cloud or Server/DC
# Outputs: "cloud" or "server"
# Exit 1 if JIRA_URL is not set or unreachable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if present
if [[ -f "$AGENT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$AGENT_ROOT/.env"
fi

if [[ -z "${JIRA_URL:-}" ]]; then
  echo "ERROR: JIRA_URL is not set" >&2
  exit 1
fi

# Cloud instances use *.atlassian.net
if [[ "$JIRA_URL" =~ \.atlassian\.net ]]; then
  echo "cloud"
  exit 0
fi

# Try Server/DC detection via REST API
# Server/DC exposes /rest/api/2/serverInfo without auth
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "${JIRA_URL}/rest/api/2/serverInfo" \
  --max-time 10 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
  echo "server"
  exit 0
fi

echo "ERROR: Cannot determine Jira type for $JIRA_URL (HTTP $HTTP_CODE)" >&2
exit 1
