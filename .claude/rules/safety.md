# Safety Rules

- **Never push to protected branches** — `main`, `master`, `staging`
- **Never force push** — under any circumstances
- **Never rebase shared branches** — merge only
- **Always create from latest base** — `git fetch origin` before branching
- **Never delete branches that have open PRs** — cleanup only after confirmed merge
- **Never modify files outside the assigned worktree**
- **Never run destructive git operations** — `reset --hard`, `clean -f`, etc.
- **Always validate branch name** before creating
- **Always validate `AGENT_EMPLOYEE_CODE`** before any branch operation
- **Rate limit backoff** — exponential retry (2s → 8s → 30s), max 3, then escalate. Never increments auto-repair failure counter.
