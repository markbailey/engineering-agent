# Engineering Agent — Autonomous Multi-Agent Engineering System

## Overview

The **Engineering Agent** is an autonomous multi-agent system built on [Claude Code](https://claude.com/claude-code). It reads a Jira ticket (or local JSON file), plans the implementation, writes the code, runs QA, performs internal code review, opens a pull request, monitors it through reviewer feedback and CI, and handles post-merge cleanup — end to end, with no human intervention required outside of code review.

Instead of a single LLM doing everything, the system orchestrates **10 specialized agents** through a structured pipeline. Each agent has a focused responsibility, explicit input/output contracts, and produces validated JSON artifacts. The Orchestrator (top-level controller) never writes code — it routes, decides, and escalates.

---

## Problem Statement

Manual ticket-to-PR workflows are slow, error-prone, and cognitively expensive. Engineers context-switch between Jira, IDE, terminal, GitHub, and CI dashboards. Common failure modes include:

- Forgotten acceptance criteria
- Missing tests or broken lint
- Secrets accidentally committed
- Merge conflicts left unresolved
- PRs that go stale waiting for feedback loops

The Engineering Agent eliminates these gaps by encoding the entire workflow as a deterministic, observable, resumable pipeline — with safety gates, auto-repair, and continuous learning baked in.

---

## Architecture

### High-Level Flow

```
Jira Ticket / Local JSON
        |
        v
  +--------------+
  | Orchestrator  |  (routes, never codes)
  +--------------+
        |
        v
  STARTUP → TICKET INTAKE → PLANNING → WORKTREE SETUP
        → IMPLEMENTATION → FULL QA → CONFLICT RESOLUTION
        → INTERNAL REVIEW → SECRET SCAN → PR SIZE CHECK
        → PR CREATION → PR MONITORING → POST-MERGE
```

### Design Principles

| Principle                    | Description                                                                                 |
| ---------------------------- | ------------------------------------------------------------------------------------------- |
| **Agent Isolation**          | Each agent is stateless. Receives full context, produces JSON. No shared mutable state.     |
| **One Commit Per Task**      | Atomic, reviewable, bisectable units of work.                                               |
| **Auto-Fix First**           | If a tool can fix it (prettier, eslint), fix silently. Only report what humans must decide. |
| **Hard Blocks**              | Secrets, broken compilation, protected branch pushes — non-negotiable gates.                |
| **Escalation Over Guessing** | Uncertain? Stop and ask a human rather than making assumptions.                             |
| **Observable**               | Every decision logged to `run.log`. Dashboard provides real-time monitoring.                |
| **Resumable**                | Pause mid-workflow, resume from last verified checkpoint.                                   |
| **Self-Improving**           | Run Analyst detects recurring mistakes and generates standing instructions for future runs. |

---

## Agent Roster

The system comprises 10 specialized agents, each defined as a versioned markdown prompt in `agents/`.

| Agent                         | Role                                                                                               | Key Output                          |
| ----------------------------- | -------------------------------------------------------------------------------------------------- | ----------------------------------- |
| **Jira Agent**                | Fetches, validates, and parses Jira tickets. Checks dependencies and transitions status.           | Parsed ticket data, blocker status  |
| **Planner Agent**             | Transforms ticket requirements into an ordered task plan with branches and worktrees.              | `PRD.json`                          |
| **Developer Agent**           | Implements one task at a time. Writes production code + tests. One commit per task.                | Conventional Commit + status report |
| **QA Agent**                  | Runs the verification pipeline: auto-fix, tsc, lint, format, unit tests, integration tests.        | `QA.json`                           |
| **The Critic**                | Senior-engineer-level code review against requirements, security, performance, and architecture.   | `REVIEW.json`                       |
| **Conflict Resolution Agent** | Merges base into feature branch, resolves conflicts file-by-file, runs regression + orphan guards. | `CONFLICT.json`                     |
| **Secret Scanner**            | Runs gitleaks on the diff. Hard blocks PR creation if any findings.                                | `SECRETS.json`                      |
| **PR Agent**                  | Opens draft PRs, writes descriptions, links Jira, assigns reviewers, handles merge.                | PR URL + Jira transition            |
| **PR Monitor**                | Polls PR status — CI, reviews, base branch changes. Routes to appropriate handler.                 | `FEEDBACK.json` + action routing    |
| **Run Analyst**               | Post-run pattern detection. Identifies recurring mistakes and generates standing instructions.     | Updated `AGENT_LEARNING.json`       |

---

## Workflow Stages

### 1. Startup

- Validate environment (tools, auth, env vars, repos)
- Load `REPAIR_KNOWLEDGE.json` (known tool fixes) and `AGENT_LEARNING.json` (standing instructions)
- Scan for orphaned worktrees

### 2. Ticket Intake

- **Jira input**: Fetch ticket, validate type/status/acceptance criteria, check "blocked by" dependencies
- **Local JSON input**: Validate against schema, skip Jira entirely
- Check for existing human work on the same ticket (team conflict detection)

### 3. Planning

- Planner Agent generates `PRD.json` — ordered tasks, branch names, worktree paths, dependencies
- Branch format: `{employeecode}_{issue-id}_{description}_{branch-type}`

### 4. Worktree Setup

- Create git worktree from base branch (main or dependency branch)
- Copy non-committable files (.env, keys), install dependencies (`npm ci`), baseline `tsc --noEmit`

### 5. Implementation

- Process tasks in dependency order
- Per task: Developer Agent implements → QA Agent verifies (auto-fix → tsc → lint → format → unit tests)
- Max 2 retries per task before escalation

### 6. Full QA

- Complete test suite including integration tests

### 7. Conflict Resolution

- Merge base into feature branch
- Resolve conflicts file-by-file using PRD.json intent
- Regression guard (compilation, diff analysis, full QA)
- Orphan check (deleted callsites, renamed refs, dead exports, disconnected integrations)

### 8. Internal Review

- The Critic reviews: requirements coverage, security, performance, architecture, test quality
- Severity levels: critical / high / medium / low
- Max 3 review-fix rounds before escalation

### 9. Secret Scan

- gitleaks on full diff — **hard block** if any findings
- Never logs secret values, never auto-fixes — human must remediate

### 10. PR Creation

- Opens as draft by default (or ready if `--ready-pr`)
- Links Jira ticket, assigns reviewers, writes structured description

### 11. PR Monitoring

- Polls GitHub for: CI status, reviewer comments, base branch changes
- Routes to: feedback handler, conflict resolution, merge, or escalation
- Max 5 feedback rounds

### 12. Post-Merge

- Transition Jira to Done
- Clean up worktrees and archive artifacts to `runs/{ticket_id}/`
- Run Analyst analyses last N runs for behavioural patterns

---

## Key Features

### Self-Learning System

The **Run Analyst** agent analyses completed runs and detects recurring behavioural mistakes (e.g., "Developer Agent keeps missing error handling on async operations"). It generates **standing instructions** that are injected into agent context on future runs — enabling continuous improvement without modifying agent prompts.

**Status lifecycle**: `active` → `resolved` (5 clean runs) → or `persistent` (recurs after instruction → escalate to human)

### Auto-Repair

Tool and environment failures (e.g., npm timeouts, compilation errors on install) are tracked in `REPAIR_KNOWLEDGE.json`. On failure, the system looks up known fixes, tries alternatives, and records successful remedies with confidence scoring (`low` → `medium` → `high`).

### Real-Time Dashboard

A zero-dependency Node.js dashboard (`make dashboard`) provides:

- Live tail of run logs via Server-Sent Events
- Stage progress visualisation
- Artifact inspection (PRD, Review, Feedback, Conflicts)
- Run metrics display

### Pause / Resume / Stop

- `--pause`: finish current agent, save state, stop at next safe checkpoint
- `--resume`: detect existing worktree, continue from last verified task
- `--stop`: immediate abort with cleanup, preserves recoverable work

### Dry Run Mode

`make dry-run PROJ-123` runs the entire pipeline (planning, implementation, QA, review, secret scan) without creating PRs or modifying Jira. Validates end-to-end behaviour in isolation.

### Multi-Repo Support

Tickets spanning multiple repositories get one worktree and one PR per repo. The primary repo links to Jira; secondary repos reference the primary PR. Cross-repo task dependencies are tracked in `PRD.json`.

---

## Getting Started

### Prerequisites

| Tool           | Purpose                      |
| -------------- | ---------------------------- |
| `gh`           | GitHub CLI — PR operations   |
| `gitleaks`     | Secret scanning              |
| `node` + `npm` | Dashboard, schema validation |
| `git`          | Version control, worktrees   |
| `claude`       | Claude Code CLI              |

### Setup

```bash
# 1. Clone the repo
git clone <repo-url> && cd engineering-agent

# 2. Configure environment
cp .env.example .env
# Edit .env — set JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, AGENT_EMPLOYEE_CODE

# 3. Configure repo mappings
cp repos.json.example repos.json
# Edit repos.json — map Jira project keys to local repo paths

# 4. Install dependencies
npm install

# 5. Validate setup
bash scripts/setup.sh
bash scripts/preflight.sh <PROJECT_KEY>
```

### First Run

```bash
# Dry run (no side effects)
make dry-run PROJ-123

# Full run
make start PROJ-123

# Resume an interrupted run
make resume PROJ-123
```

---

## CLI Reference

All commands are invoked via `make` targets:

| Command                        | Purpose                                                 |
| ------------------------------ | ------------------------------------------------------- |
| `make start PROJ-123`          | Full ticket-to-PR workflow                              |
| `make dry-run PROJ-123`        | Plan + implement + QA + review — no PR, no Jira changes |
| `make resume PROJ-123`         | Continue an interrupted run                             |
| `make pause PROJ-123`          | Stop at next safe checkpoint                            |
| `make stop PROJ-123`           | Immediate abort with state preservation                 |
| `make ready-pr PROJ-123`       | Mark draft PR as ready for review                       |
| `make auto-merge PROJ-123`     | Full workflow with GitHub auto-merge enabled            |
| `make revert PROJ-123`         | Revert a merged PR (test, scan, open revert PR)         |
| `make address-feedback PR-NUM` | Address PR review feedback end-to-end                   |
| `make dashboard`               | Start real-time monitoring dashboard (port 3847)        |
| `make test`                    | Run all tests                                           |
| `make clean`                   | Clean orphaned runs, worktrees, stale branches          |
| `make clean-dry`               | Preview what `clean` would remove                       |

**Local JSON input** (bypasses Jira):

```bash
make start ./tickets/my-feature.json
```

---

## Data Artifacts

Every run produces validated JSON artifacts in `runs/{ticket_id}/`:

| Artifact          | Schema                   | Producer            | Purpose                                      |
| ----------------- | ------------------------ | ------------------- | -------------------------------------------- |
| `PRD.json`        | `prd.schema.json`        | Planner Agent       | Task plan, branch info, status tracking      |
| `REVIEW.json`     | `review.schema.json`     | The Critic          | Code review findings, verdict, PRD adherence |
| `FEEDBACK.json`   | `feedback.schema.json`   | PR Monitor          | Parsed reviewer comments + CI failures       |
| `CONFLICT.json`   | `conflict.schema.json`   | Conflict Resolution | Merge strategies, regression guard results   |
| `SECRETS.json`    | `secrets.schema.json`    | Secret Scanner      | Gitleaks findings (values always redacted)   |
| `ESCALATION.json` | `escalation.schema.json` | Any agent           | Structured escalation with context           |
| `METRICS.json`    | `metrics.schema.json`    | Metrics collector   | Duration, commits, test results              |
| `run.log`         | —                        | All stages          | Structured JSONL log of entire run           |

All schemas are in `schemas/` and validated at runtime via AJV.

---

## Safety & Security

| Rule                                 | Enforcement                                                           |
| ------------------------------------ | --------------------------------------------------------------------- |
| **Never push to protected branches** | `check-branch-before-push.sh` validates before every push             |
| **Never force push**                 | Hard-coded prohibition, no override                                   |
| **Secret scan gate**                 | gitleaks on diff before PR — hard block on findings                   |
| **Secret values never logged**       | SECRETS.json contains file/line/type only — value always `[REDACTED]` |
| **Team conflict detection**          | Checks for existing human branches/PRs before starting                |
| **Branch name validation**           | Format enforced: `{code}_{ticket}_{desc}_{type}`                      |
| **Employee code required**           | `AGENT_EMPLOYEE_CODE` must be set — hard stop if missing              |
| **Rate limit backoff**               | Exponential retry (2s → 8s → 30s), max 3 attempts                     |
| **Max retry limits**                 | 2 retries per task, 3 Critic rounds, 5 feedback rounds                |

---

## Configuration Reference

### Environment Variables (`.env`)

| Variable                       | Required     | Default | Description                              |
| ------------------------------ | ------------ | ------- | ---------------------------------------- |
| `JIRA_URL`                     | Yes          | —       | Jira instance URL                        |
| `JIRA_EMAIL`                   | Yes (Cloud)  | —       | Jira Cloud email                         |
| `JIRA_API_TOKEN`               | Yes (Cloud)  | —       | Jira Cloud API token                     |
| `JIRA_PAT`                     | Yes (Server) | —       | Jira Server/DC personal access token     |
| `AGENT_EMPLOYEE_CODE`          | Yes          | —       | 3-letter code for branch naming          |
| `AGENT_RATE_LIMIT_MAX_RETRIES` | No           | `3`     | Max API retry attempts                   |
| `AGENT_LEARNING_WINDOW`        | No           | `5`     | Runs to analyse for patterns             |
| `AGENT_STALE_BRANCH_DAYS`      | No           | `30`    | Days before branch is considered stale   |
| `AGENT_PR_SIZE_WARNING_FILES`  | No           | `20`    | File count threshold for PR size warning |
| `AGENT_PR_MONITOR_INTERVAL`    | No           | `600`   | PR poll interval in seconds              |

### Repository Mapping (`repos.json`)

```json
{
  "repos": {
    "PROJ": {
      "name": "my-repo",
      "path": "/path/to/local/repo",
      "github_repo": "org/my-repo",
      "reviewers": ["github-user-1", "github-user-2"]
    }
  }
}
```

The Jira project key (e.g., `PROJ` from `PROJ-123`) maps to the target repository. Multiple project keys can map to the same repo.

---

## Project Structure

```
engineering-agent/
├── agents/              # 10 agent prompt definitions (versioned .md)
├── schemas/             # 11 JSON schemas for artifact validation
├── scripts/             # 50+ orchestration & utility scripts
├── dashboard/           # Real-time monitoring UI (Node.js SSE)
├── tests/               # Bash + Node.js test suites
├── runs/                # Per-ticket run artifacts (gitignored)
├── tickets/             # Local test ticket fixtures
├── .claude/
│   ├── commands/        # /start, /apply-repairs slash commands
│   └── rules/           # 21 workflow rule files
├── CLAUDE.md            # Orchestrator master prompt
├── Makefile             # CLI entry point
├── repos.json           # Repo mapping config
└── .env                 # Environment config (gitignored)
```

---

## Testing

```bash
make test              # All tests (scripts + dashboard)
make test-scripts      # Shell script unit & integration tests
make dashboard-test    # Dashboard unit tests
```

Tests cover: preflight validation, worktree management, conflict resolution, secret scanning, metrics collection, schema validation, timeout handling, concurrency, flaky test detection, and dashboard state management.

---

## Integration Points

| System          | Integration Method         | Purpose                                                  |
| --------------- | -------------------------- | -------------------------------------------------------- |
| **Jira**        | Atlassian MCP / REST API   | Read tickets, validate, transition status, post comments |
| **GitHub**      | `gh` CLI                   | Create PRs, push code, monitor checks, parse reviews     |
| **Local Repos** | Git worktrees              | Isolated, concurrent workspaces without full clones      |
| **Claude Code** | Slash commands + Task tool | Agent invocation, context management                     |
| **gitleaks**    | CLI                        | Secret detection on diffs                                |

---

_Built with [Claude Code](https://claude.com/claude-code) — an autonomous engineering system that turns tickets into merged pull requests._
