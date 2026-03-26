# Ticket Intake Rules

## Invocation Modes

```bash
# Normal run — full workflow (Jira ticket)
claude-code run --ticket PROJ-123

# Normal run — full workflow (local JSON file, bypasses Jira)
claude-code run --ticket ./tickets/my-feature.json

# Dry run — plan only, no code changes
claude-code run --ticket PROJ-123 --dry-run

# Resume interrupted run — skip intake, detect existing worktree
claude-code run --ticket PROJ-123 --resume

# Pause — stop at next safe checkpoint, preserve state
claude-code run --ticket PROJ-123 --pause

# Stop — immediate stop, preserve state
claude-code run --ticket PROJ-123 --stop

# Mark PR ready for review (not draft)
claude-code run --ticket PROJ-123 --ready-pr
```

## Input Source Detection

`parse-args.sh` detects input source from the first positional argument:
- `.json` extension or contains `/` or `\` → local file (`input_source: "local"`)
- Otherwise → Jira ticket ID (`input_source: "jira"`)

For local input: file is validated against `schemas/local-ticket.schema.json`, copied to `runs/{ticket_id}/ticket.json` for resume resilience.

## Intake Validation (Jira: input_source == "jira")

Before any work begins — before worktree creation, before planning — the Jira Agent validates:

| Check | Fail condition | Action |
|---|---|---|
| Ticket exists | Not found in Jira | STOP — report invalid ID |
| Ticket type | Epic, sub-task, or non-implementation type | STOP — report unsupported type |
| Ticket status | Done, Cancelled, Won't Do | STOP — nothing to do |
| Ticket status | Blocked | STOP — report blocker details |
| Active worktree | Worktree already exists for this ticket | Resume existing run |
| Ticket assignee | Unassigned | Assign to agent service account, proceed |
| Acceptance criteria | None defined | ESCALATE — post Jira comment explaining what's needed |

## Intake Validation (Local: input_source == "local")

Local tickets skip Jira Agent entirely. Validation is handled by `parse-args.sh`:

| Check | Fail condition | Action |
|---|---|---|
| File exists | Not found on disk | STOP — report invalid path |
| Valid JSON | Parse error | STOP — report parse error |
| Schema validation | Missing required fields, invalid types | STOP — report validation errors |
| ticket_id format | Does not match `^[A-Z]+-[0-9]+$` | STOP — report format error |
| Active worktree | Worktree already exists for this ticket | Resume existing run |

`check-team-conflict.sh` still runs for local tickets to detect branch name collisions on GitHub.

Dependency checking, Jira status checks, and Jira comments are all skipped for local input.

## Supported Ticket Types

- `Story` — supported (implementation work)
- `Task` — supported (implementation work)
- `Bug` — supported (bug fix)
- `Sub-task` — **NOT supported** — handled within parent story's PRD.json
- `Epic` — **NOT supported** — container, not implementable
