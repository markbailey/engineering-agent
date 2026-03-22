---
name: start
description: 'Orchestrate multi-agent implementation of a JIRA ticket. Parses args, runs startup, delegates to agents per CLAUDE.md workflow. Args: TICKET-ID [--dry-run] [--resume] [--ready-pr] [--pause] [--stop]'
---

# /start — Orchestrator Entry Point

Execute the full multi-agent engineering workflow defined in CLAUDE.md.

**Input:** `$ARGUMENTS`

---

## Step 1: Parse Arguments

Run `scripts/parse-args.sh $ARGUMENTS` to extract:
- `ticket_id` (required)
- `project_key`, `repo_name`, `repo_path`, `github_repo` (resolved from `repos.json`)
- `mode`: normal | dry_run | resume
- `ready_pr`, `pause`, `stop` flags

If parse fails → STOP with error message.

---

## Step 2: Startup Sequence

Execute CLAUDE.md "Startup Sequence" in order:

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

### Normal Mode
```
TICKET INTAKE → PLANNING → WORKTREE SETUP → IMPLEMENTATION →
FULL QA → CONFLICT RESOLUTION → INTERNAL REVIEW →
SECRET SCAN → PR CREATION → PR MONITORING → POST-MERGE
```

### Dry Run Mode
```
TICKET INTAKE → PLANNING → STOP (output PRD.json for review)
```

### Flags
- `--ready-pr`: PR Agent opens as ready (not draft)
- `--pause`: stop at next safe checkpoint (see CLAUDE.md "Safe Checkpoints")
- `--stop`: immediate stop, preserve PRD.json state

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
