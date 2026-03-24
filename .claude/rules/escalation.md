# Escalation Conditions

The agent stops and surfaces to human when:

| Condition | Action |
|---|---|
| Ticket has no acceptance criteria | Comment on ticket, STOP |
| Ticket type unsupported (Epic, sub-task) | STOP with reason |
| Ticket is blocked by unresolved dependency | Comment, transition to Blocked, STOP |
| Dependency chain > 1 level deep | ESCALATE |
| `AGENT_EMPLOYEE_CODE` missing | Hard stop before any branch creation |
| Baseline `tsc --noEmit` fails in fresh worktree | ESCALATE (broken base branch) |
| Test failures after 2 Developer Agent retries | ESCALATE with test output |
| The Critic issues unresolved after 3 rounds | ESCALATE with REVIEW.json |
| Unresolvable merge conflicts | ESCALATE with CONFLICT.json |
| Regression guard fails after fix attempt | ESCALATE with CONFLICT.json |
| Orphan fix would violate acceptance criteria | ESCALATE |
| Disconnected integration detected | ESCALATE — never guess reconnection |
| Secret detected in diff | HARD BLOCK, STOP, notify human |
| PR feedback stalled or contradictory | ESCALATE |
| Rate limit retries exhausted (3 attempts) | ESCALATE |
| Persistent learning pattern (2+ recurrences after instruction) | Report to human |
