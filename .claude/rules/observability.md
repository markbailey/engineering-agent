# Observability

## Run Logging

Every run produces a structured log at `runs/{ticket_id}/run.log` in JSONL format (one JSON object per line).

**Log entry format:**
```json
{"ts":"2026-03-21T14:30:00Z","level":"INFO","cat":"startup","msg":"...","details":{}}
```

**Levels:** `INFO` (progress), `WARN` (non-blocking issues), `ERROR` (failures), `EVENT` (key milestones)

**Categories:** `startup`, `intake`, `planning`, `worktree`, `implementation`, `qa`, `review`, `secrets`, `pr`, `monitor`, `conflict`, `cleanup`, `retry`, `agent`, `summary`, `event`

## When to Log

Log at every workflow stage transition using `scripts/run-log.sh`:

| Stage | Level | Category | Example message |
|---|---|---|---|
| Run start | INFO | startup | "Run started" |
| Ticket validated | INFO | intake | "Ticket WTP-123 validated: Story, To Do" |
| Planning complete | INFO | planning | "PRD.json generated: 4 tasks" |
| Worktree created | INFO | worktree | "Worktree created at ~/.claude/worktrees/AXO471/branch_name" |
| Task started | INFO | implementation | "Task 1 started: add-pagination" |
| Task verified | INFO | qa | "Task 1 verified" |
| QA failure | ERROR | qa | "tsc --noEmit failed" |
| Critic review | INFO | review | "Critic review round 1: 2 issues" |
| Secret scan | INFO | secrets | "Secret scan clean" |
| PR opened | EVENT | pr | "PR #42 opened as draft" |
| CI failed | ERROR | monitor | "CI check 'build' failed" |
| Conflict resolution | INFO | conflict | "Merge clean, no conflicts" |
| Rate limit retry | WARN | retry | "Attempt 1/3 failed, retrying in 2s" |
| Agent version mismatch | WARN | agent | "2 agent(s) changed on resume" |
| Escalation | ERROR | event | "Escalating: QA failed after 2 retries" |
| Run complete | EVENT | summary | "Run complete: completed — 4/4 tasks" |

## Terminal Notifications

Use `scripts/notify.sh` for key events that need human attention:

- `pr_opened` / `pr_updated` — PR created or updated
- `ci_failed` / `ci_passed` — CI status change
- `escalation` — agent stopped, human action needed
- `rate_limit` — retries exhausted
- `secret_found` — hard block
- `run_complete` / `run_failed` — terminal state
- `blocked` — ticket blocked by dependency
- `task_complete` — individual task done
- `pr_ready` — PR marked ready for review (draft→ready)
- `auto_merge_enabled` — auto-merge enabled on PR
- `pr_merged` — PR merge detected

## Run Summary

At the end of every completed run (regardless of outcome), call `scripts/run-summary.sh` to write a summary entry. This counts errors, warnings, and events from the log and produces a terminal banner.
