# Engineering Agent

Autonomous multi-agent engineering system built on Claude Code. Reads Jira tickets, implements code changes, performs internal review, opens PRs, and monitors them through to merge-ready state.

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| `gh` | GitHub CLI | `winget install GitHub.cli` |
| `gitleaks` | Secret scanning | `winget install Gitleaks.Gitleaks` |
| `node` / `npm` | JS/TS toolchain | `winget install OpenJS.NodeJS.LTS` |
| `git` | Version control | `winget install Git.Git` |

Atlassian access is via the Atlassian MCP server (configured in `.claude.json`).

## Setup

1. Copy `.env.example` to `.env` and fill in values
2. Set `AGENT_EMPLOYEE_CODE` (3-letter lowercase code) — **required**
3. Run `bash scripts/setup.sh` to validate environment
4. Ensure worktrees directory exists at `../worktrees/`

## Project Structure

```
/engineering-agent
  CLAUDE.md              ← Orchestrator instructions
  .env.example           ← Environment template
  .gitleaks.toml         ← Secret scanning config
  /agents                ← Agent system prompts (versioned .md files)
  /schemas               ← JSON schemas for artefacts
  /scripts               ← Setup, validation, and utility scripts
  /runs                  ← Per-ticket run artifacts (PRD.json, REVIEW.json, etc.)

../worktrees             ← Git worktrees per ticket (outside repo)
```

## Usage

```bash
# Implement a Jira ticket
claude-code --ticket PROJ-123

# Dry run (no commits, no PRs)
claude-code --ticket PROJ-123 --dry-run

# Resume interrupted work
claude-code --ticket PROJ-123 --resume
```

## Environment Variables

See `.env.example` for all required and optional variables.

| Variable | Required | Description |
|---|---|---|
| `AGENT_EMPLOYEE_CODE` | Yes | 3-letter lowercase code for branch naming |
| `JIRA_URL` | Yes | Jira instance URL |
| `JIRA_EMAIL` | Yes* | Jira Cloud email (*Cloud only) |
| `JIRA_API_TOKEN` | Yes* | Jira Cloud API token (*Cloud only) |
| `JIRA_PAT` | Yes* | Jira Server/DC PAT (*Server only) |
| `AGENT_LEARNING_WINDOW` | No | Runs to analyze for patterns (default: 5) |
| `AGENT_STALE_BRANCH_DAYS` | No | Days before branch is stale (default: 30) |
