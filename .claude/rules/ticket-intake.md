# Ticket Intake Rules

## Invocation Modes

```bash
# Normal run — full workflow
claude-code run --ticket PROJ-123

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

## Intake Validation

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

## Supported Ticket Types

- `Story` — supported (implementation work)
- `Task` — supported (implementation work)
- `Bug` — supported (bug fix)
- `Sub-task` — **NOT supported** — handled within parent story's PRD.json
- `Epic` — **NOT supported** — container, not implementable
