# Startup Sequence

On every run start (before any agent invocation):

0. Run `scripts/preflight.sh {project_key}` — validate tools, auth, env, repos. On failure: log ERROR via run-log.sh, notify human via notify.sh, abort run (no partial work).
1. Parse user input via `scripts/parse-args.sh` — extract ticket_id, mode, flags, target repo info (project_key, repo_name, repo_path, github_repo from `repos.json`), and input_source (`jira` or `local`).
2. Initialise run log: `scripts/run-log.sh {ticket_id} INFO startup "Run started"` — creates `runs/{ticket_id}/run.log`.
3. Read `REPAIR_KNOWLEDGE.json` — load known tool/environment failure alternatives.
4. Read `AGENT_LEARNING.json` — load standing instructions for each agent.
5. Run `scripts/worktree-scan.sh` — report orphaned worktrees to human (non-blocking).
6. Run `scripts/record-agent-versions.sh` — capture agent prompt versions for PRD.json.
7. Store repair knowledge + learning entries in memory for injection into agent context packages throughout the run.

## Resume Logic

On `--resume` mode (or when an existing worktree is detected for the ticket):

1. Check `~/.claude/worktrees/{repo_name}/` for existing worktree matching ticket_id branch.
2. Run `scripts/worktree-init.sh {wt_path} {repo_path} --check-only` — re-init if exit 1.
3. Run `scripts/record-agent-versions.sh --check runs/{ticket_id}/PRD.json --ticket={ticket_id}` — compare against recorded versions. Mismatches logged to run.log as WARN. Proceed (do not block).
4. Read `PRD.json` from `runs/{ticket_id}/`.
5. Find last task with `status: verified` — continue from next `pending` task.
6. Resume workflow from the appropriate stage based on `PRD.json.overall_status`.
