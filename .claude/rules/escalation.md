# Escalation Conditions

All escalations are recorded via `scripts/escalate.sh`, which writes structured entries to `runs/{ticket_id}/ESCALATION.json`, logs to run.log, and notifies via notify.sh.

## Usage

```bash
scripts/escalate.sh <ticket_id> <category> <severity> <source_agent> <stage> <summary> [--details "..."] [--suggested-action "..."]
```

## Categories & Trigger Mapping

| Condition | Category | Severity | Action |
|---|---|---|---|
| Ticket has no acceptance criteria | `blocked_dependency` | `high` | Comment on ticket, STOP |
| Ticket type unsupported (Epic, sub-task) | `unknown` | `medium` | STOP with reason |
| Ticket blocked by unresolved dependency | `blocked_dependency` | `high` | Comment, transition to Blocked, STOP |
| Dependency chain > 1 level deep | `blocked_dependency` | `high` | STOP |
| `AGENT_EMPLOYEE_CODE` missing | `infra_failure` | `critical` | Hard stop before any branch creation |
| Baseline `tsc --noEmit` fails in fresh worktree | `infra_failure` | `critical` | STOP (broken base branch) |
| Test failures after 2 Developer Agent retries | `test_failure` | `high` | STOP with test output |
| The Critic issues unresolved after 3 rounds | `review_stall` | `high` | STOP with REVIEW.json |
| Unresolvable merge conflicts | `merge_conflict` | `high` | STOP with CONFLICT.json |
| Regression guard fails after fix attempt | `merge_conflict` | `high` | STOP with CONFLICT.json |
| Orphan fix would violate acceptance criteria | `merge_conflict` | `medium` | STOP |
| Disconnected integration detected | `merge_conflict` | `critical` | STOP — never guess reconnection |
| Secret detected in diff | `secret_detected` | `critical` | HARD BLOCK, STOP, notify human |
| PR feedback stalled or contradictory | `contradictory_feedback` | `high` | STOP |
| Rate limit retries exhausted (3 attempts) | `infra_failure` | `medium` | STOP |
| Persistent learning pattern (2+ recurrences) | `unknown` | `medium` | Report to human |
| Auto-merge failed (branch protection not met) | `infra_failure` | `medium` | Notify human, do not retry |
| Existing human work on same ticket | `team_conflict` | `high` | Do NOT start competing branch |

## Abort

Use `scripts/abort-run.sh` for full run abort with cleanup. See pause-stop rules.
