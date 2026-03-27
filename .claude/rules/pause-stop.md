# Safe Checkpoints & Pause/Stop

## Safe Pause Points

The workflow can safely pause at these points (PRD.json is consistent):

- Between tasks (after a task reaches `verified` status)
- After full QA pass
- After each Critic review round
- After PR creation
- After each PR Monitor feedback cycle

## --pause Behaviour

Finish the current agent invocation, save PRD.json to `runs/{ticket_id}/`, then stop. The next `--resume` picks up from the last verified checkpoint.

## --stop Behaviour

Immediate stop. Calls `scripts/abort-run.sh <ticket_id> <reason>` to:

1. Close any open draft PR for the ticket
2. Set PRD.json `overall_status` to `"aborted"`
3. Write structured escalation to `ESCALATION.json`
4. Log abort event to run.log
5. Write run summary with status `"aborted"`

Does NOT remove worktree or delete branches — recoverable work is preserved.

On `--resume`, the Orchestrator detects aborted/in-progress tasks and re-runs them from scratch (Developer Agent re-implements, QA re-verifies).
