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

Immediate stop. PRD.json may be mid-update — a task might show `in_progress`. On `--resume`, the Orchestrator detects in-progress tasks and re-runs them from scratch (Developer Agent re-implements, QA re-verifies).

## Natural Exit Points

The workflow naturally exits (not a pause — a clean termination) at:

- **PR creation complete** — after opening the draft PR and saving initial poll state, the workflow exits. Resume via `make resume` or `scripts/pr-monitor-cron.sh --trigger`.

This is distinct from `--pause`: natural exits are expected workflow behaviour, not interruptions. PRD.json `overall_status` reflects the stage (`pr_monitoring`), and resume picks up from there.
