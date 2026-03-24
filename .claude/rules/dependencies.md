# Ticket Dependency Checking

## Rules

- **Strict link checking only** — only explicit "blocked by" Jira links count. No inference from descriptions.
- **Always check both** Jira ticket status AND associated PR status — Jira status may be stale.
- **One level of dependency branching** — if dependency itself has unmerged dependencies, ESCALATE.
- **Mid-workflow changes ignored** — picked up on next run, not current.

## Dependency Check Flow

```
For each "blocked by" link on the ticket:
  → Fetch blocker ticket status
      → Done: resolved, continue
      → Not Done:
          → Check for associated PR
              → No PR: comment "Blocked by X", transition to Blocked, STOP
              → PR merged: resolved (Jira status stale)
              → PR ready for review (not draft, no blocking reviews):
                  → Record dependency branch in PRD.json
                  → Create worktree from dependency branch
                  → Proceed
              → PR is draft or has blocking reviews:
                  → Comment "Blocked by X (PR not ready)", transition to Blocked, STOP
```

## Branching from Dependencies

- Worktree: `scripts/worktree-create.sh {branch} origin/{dependency-branch} --target-repo={repo_path} --repo-name={repo_name}`
- Conflict Resolution uses dependency branch as base, not main
- PRD.json records: `base_branch`, `base_is_dependency: true`, `dependency_ticket`, `dependency_pr`, `ultimate_base: "main"`
- When dependency merges to main, PR Monitor triggers conflict resolution against main
