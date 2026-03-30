# Dry Run Mode

When invoked with `--dry-run`:

1. Jira Agent reads and validates the ticket (normal).
2. Dependency check runs (normal).
3. Planner Agent generates PRD.json with `dry_run: true` (normal).
4. Worktree created and initialised (normal).
5. Implementation — Developer Agent executes all tasks (normal).
6. Full QA — auto-fix, tsc, lint, format, unit tests, integration tests (normal).
7. Conflict Resolution — merge base, regression guard, orphan check (normal).
8. Internal Review — Critic reviews, Developer resolves (normal).
9. Secret Scan — gitleaks on diff (normal).
10. **STOP HERE** — no PR creation, no Jira transitions, no `gh` commands that create/modify PRs.

All artifacts are written to `runs/{ticket_id}/` as usual: PRD.json, REVIEW.json, SECRETS.json, CONFLICT.json, etc. PRD.json contains `dry_run: true` so downstream agents can check.

Generate a human-readable report: `scripts/dry-run-report.sh {ticket_id}`.

## What is skipped

- PR Agent checks `dry_run` flag in PRD.json and skips if true
- No `gh pr create` or `gh pr merge` commands
- No Jira status transitions (In Review, Done)
- No PR monitoring loop
- No post-merge cleanup

## Purpose

Deep dry-run validates the entire pipeline end-to-end — planning, implementation, QA, review, secret scan — without creating external side effects. Use it to verify agent behavior, test fixtures, and catch issues before real runs.
