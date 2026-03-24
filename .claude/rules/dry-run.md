# Dry Run Mode

When invoked with `--dry-run`:

1. Jira Agent reads and validates the ticket (normal).
2. Dependency check runs (normal).
3. Planner Agent generates PRD.json (normal).
4. **STOP HERE** — no worktree, no code, no PR.
5. Output the full PRD.json to the human for review.
6. Log what would have happened at each workflow step.

Dry run is for validation and plan review before committing to execution.
