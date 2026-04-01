---
name: start
description: 'Orchestrate multi-agent implementation of a JIRA ticket or local JSON file. Parses args, runs startup, delegates to agents per CLAUDE.md workflow. Args: TICKET-ID|FILE-PATH [--dry-run] [--resume] [--ready-pr] [--pause] [--stop]'
---

# /start — Orchestrator Entry Point

Execute the full multi-agent engineering workflow defined in CLAUDE.md.

**Input:** `$ARGUMENTS`

---

## Step 1: Parse Arguments

Run `scripts/parse-args.sh $ARGUMENTS` to extract:
- `ticket_id` (required — from Jira ID or local JSON file)
- `project_key`, `repo_name`, `repo_path`, `github_repo` (resolved from `repos.json`)
- `mode`: normal | dry_run | resume
- `ready_pr`, `pause`, `stop` flags
- `input_source`: `jira` | `local` — determines whether Jira Agent is invoked
- `input_file`: absolute path to local JSON file (null for Jira input)

Input can be a Jira ticket ID (`PROJ-123`) or a path to a local JSON file (`./ticket.json`).
File paths are detected by `.json` extension or presence of `/` or `\`.

If parse fails → STOP with error message.

---

## Step 2: Startup Sequence

Execute CLAUDE.md "Startup Sequence" in order:

0. Write PID file: `scripts/pid.sh write {ticket_id} $PPID`
1. Read `REPAIR_KNOWLEDGE.json` — store in memory
2. Read `AGENT_LEARNING.json` — store in memory
3. Run `scripts/worktree-scan.sh` — report orphans to human (non-blocking)
4. Run `scripts/record-agent-versions.sh` — store agent versions

---

## Step 3: Resume Check

If mode is `resume` OR an existing worktree is found for the ticket_id:

1. Run `scripts/worktree-init.sh {wt_path} {repo_root} --check-only`
2. If needs re-init: run `scripts/worktree-init.sh {wt_path} {repo_root}`
3. Compare agent versions against `PRD.json.agent_versions` — log mismatches
4. Read `PRD.json` from `runs/{ticket_id}/`
5. Find last verified task → resume from next pending
6. Skip to the appropriate workflow stage based on `PRD.json.overall_status`

---

## Step 4: Execute Workflow

Follow CLAUDE.md "Workflow Definition" exactly, stage by stage:

### Normal Mode (Jira: input_source == "jira")
```
TICKET INTAKE → PLANNING → WORKTREE SETUP → IMPLEMENTATION →
FULL QA → CONFLICT RESOLUTION → INTERNAL REVIEW →
SECRET SCAN → PR CREATION → PR MONITORING → POST-MERGE
```

### Normal Mode (Local: input_source == "local")
```
TICKET INTAKE (skip Jira Agent — use local JSON data) →
PLANNING → WORKTREE SETUP → IMPLEMENTATION →
FULL QA → CONFLICT RESOLUTION → INTERNAL REVIEW →
SECRET SCAN → PR CREATION (skip Jira link/transition) →
PR MONITORING (skip Jira monitoring) → POST-MERGE (skip Jira transition)
```

### Dry Run Mode
```
TICKET INTAKE → PLANNING → STOP (output PRD.json for review)
```

### Flags
- `--ready-pr`: PR Agent opens as ready (not draft)
- `--auto-merge`: enable GitHub auto-merge when PR is approved + CI green
- `--pause`: stop at next safe checkpoint (see CLAUDE.md "Safe Checkpoints"), remove PID file
- `--stop`: immediate stop, preserve PRD.json state, remove PID file

### PR Monitoring Loop (after PR CREATION)

After PR Agent opens the PR, enter the monitoring loop:

1. Set `overall_status: "pr_monitoring"` in PRD.json
2. **Poll loop:**
   - Run `scripts/pr-monitor-poll.sh {ticket_id} {pr_number}` for lightweight state check
   - If state unchanged from last poll: sleep `AGENT_PR_MONITOR_INTERVAL` (default 1200s / 20 min), continue
   - If state changed: invoke PR Monitor Agent with full context
3. **Route on `action_required`:**
   - `none` → continue polling
   - `ci_passed_draft` → PR Agent action=ready, then continue polling
   - `address_feedback` → Developer Agent → QA → Critic → PR Agent push, then continue polling
   - `conflict_resolution` → conflict-resolution.sh → QA → PR Agent push, then continue polling
   - `dependency_merged` → conflict-resolution.sh against main → QA → PR Agent push, then continue polling
   - `approved` → if `--auto-merge`: PR Agent action=merge; else notify human, continue polling
   - `merged` → break loop, proceed to POST-MERGE
   - `escalate` → ESCALATE, break loop
4. **Exit conditions:** `--pause` or `--stop` flags break at next safe checkpoint
5. Only increment `check-loop-limit.sh pr_feedback` on feedback/conflict rounds, not on every poll

### POST-MERGE (after PR Monitor detects `merged`)

1. If `input_source == "jira"`: invoke Jira Agent to transition ticket to Done
2. Cleanup worktrees: `scripts/worktree-cleanup.sh {ticket_id} --target-repo={repo_path} --repo-name={repo_name} --github-repo={github_repo}`
3. Archive artefacts to `runs/{ticket_id}/`
4. `scripts/run-summary.sh {ticket_id} "completed" {tasks_total} {tasks_completed} {pr_url}`
5. **Run Analyst** (agent learning — do not skip):
   - `scripts/agent-learning.sh gather {ticket_id}`
   - Invoke Run Analyst agent with gathered artefacts + current `AGENT_LEARNING.json`
   - `scripts/agent-learning.sh increment-runs`
   - `scripts/agent-learning.sh lifecycle {ticket_id}`
   - `scripts/agent-learning.sh escalate` — if `escalation_count > 0`: notify human via `scripts/notify.sh`
6. Remove PID file: `scripts/pid.sh remove {ticket_id}`

---

## Agent Invocation Rules

For every agent invocation, follow CLAUDE.md "Agent Invocation Pattern":

1. Fresh-read the agent's `.md` file from `agents/`
2. Filter `AGENT_LEARNING.json` for matching agent + active/resolved status
3. Append standing instructions to context
4. Assemble context package per agent's Context Contract
5. Invoke via Task tool

---

## Script Usage Reference

| Stage | Script |
|---|---|
| Arg parsing + repo resolution | `scripts/parse-args.sh` → `scripts/resolve-repo.sh` |
| Branch creation | `scripts/generate-branch-name.sh` + `scripts/validate-branch-name.sh` |
| Worktree lifecycle | `scripts/worktree-create.sh` → `scripts/worktree-init.sh` → `scripts/worktree-cleanup.sh` |
| Commit validation | `scripts/validate-commit-msg.sh` |
| Rate limit retries | `scripts/retry-with-backoff.sh` |
| Agent versions | `scripts/record-agent-versions.sh` |
| Schema validation | `scripts/validate-schemas.js` |
| Orphan detection | `scripts/worktree-scan.sh` |

---

## Error Handling

- All escalation conditions from CLAUDE.md "Escalation Conditions" apply
- On any unhandled error: preserve PRD.json state, report to human
- Rate-limited API calls: wrap with `scripts/retry-with-backoff.sh`

---

## PID Lifecycle

- **Startup:** `scripts/pid.sh write {ticket_id}` — first action after arg parsing
- **Clean exit** (workflow complete, `--pause`, `--stop`, escalation): `scripts/pid.sh remove {ticket_id}`
- Crashed processes leave stale `pid.json` — dashboard detects dead PID via `kill -0`
