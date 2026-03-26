# Script Reference

| Script | Purpose |
|---|---|
| `scripts/parse-args.sh` | Parse invocation input → ticket_id, mode, flags, repo info |
| `scripts/resolve-repo.sh` | Resolve target repo from ticket ID via repos.json |
| `scripts/generate-branch-name.sh` | Generate branch name from ticket metadata |
| `scripts/validate-branch-name.sh` | Validate branch name format + employee code |
| `scripts/discover-non-committable.sh` | Find .env, .pem, etc. to copy into worktrees |
| `scripts/worktree-create.sh` | Create git worktree for a ticket |
| `scripts/worktree-init.sh` | Initialise worktree (env, deps, tsc) |
| `scripts/worktree-cleanup.sh` | Remove worktree + branch after merge |
| `scripts/worktree-scan.sh` | Detect orphaned worktrees |
| `scripts/validate-commit-msg.sh` | Validate Conventional Commits format |
| `scripts/retry-with-backoff.sh` | Exponential backoff retry wrapper |
| `scripts/record-agent-versions.sh` | Capture agent prompt versions |
| `scripts/validate-schemas.js` | Validate JSON schemas and data files |
| `scripts/detect-jira.sh` | Detect Jira Cloud vs Server |
| `scripts/setup.sh` | Environment validation and prerequisites |
| `scripts/check-branch-before-push.sh` | Verify branch name + protected branch check before push |
| `scripts/check-team-conflict.sh` | Detect existing human branches/PRs on a ticket |
| `scripts/check-retry-limit.sh` | Track and enforce max 2 retries per task |
| `scripts/check-pr-size.sh` | Warn if PR diff exceeds file count threshold |
| `scripts/run-secret-scan.sh` | Run gitleaks on diff, produce SECRETS.json |
| `scripts/update-prd-status.sh` | Update PRD.json overall_status field |
| `scripts/check-loop-limit.sh` | Track and enforce max iterations on feedback loops |
| `scripts/stale-branch-cleanup.sh` | List or prune stale agent branches |
| `scripts/auto-repair.sh` | Auto-repair system: lookup, record, promote, mark-failed, track/reset failures |
| `scripts/conflict-resolution.sh` | Full conflict resolution pipeline: merge → guards → CONFLICT.json |
| `scripts/merge-base-into-feature.sh` | Merge base branch into feature branch, report conflicts |
| `scripts/regression-guard.sh` | 3-pass regression check: compilation, diff analysis, test suite |
| `scripts/orphan-check.sh` | Detect orphaned code: deleted callsites, renames, dead exports, disconnected integrations |
| `scripts/write-conflict-json.sh` | Assemble and write CONFLICT.json from merge + guard + orphan results |
| `scripts/run-log.sh` | Structured JSONL logger — writes to runs/TICKET-ID/run.log |
| `scripts/notify.sh` | Terminal notifications on key events + logs EVENT to run.log |
| `scripts/run-summary.sh` | Write run summary (stats, counts) to run.log at end of ticket |
| `scripts/pr-monitor-poll.sh` | Lightweight GitHub PR state poller for monitoring loop |
| `scripts/agent-learning.sh` | Agent learning system: gather, filter, write, lifecycle, escalate, increment-runs |
| `scripts/cleanup-orphans.sh` | Audit runs + worktrees, clean up orphaned ones (worktree, branches, run dir) |
