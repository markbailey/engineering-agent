# Repo Selection Logic

The Planner Agent determines which repos a ticket touches. Configuration per project:

- **Default:** single repo (the repo where the ticket's component is mapped)
- **Multi-repo:** when ticket spans shared libs and consumers
- **Mapping:** Jira component → repo, Jira label → repo, or explicit mapping in project config

## Multi-repo Rules

- Each repo gets its own worktree (`TICKET-ID-REPO-NAME`)
- Each repo gets its own branch (same naming convention, same ticket ID)
- Tasks specify which `repo` they belong to
- `primary` repo is the one where the PR links back to Jira
- Cross-repo task dependencies expressed via PRD.json task `dependencies`
