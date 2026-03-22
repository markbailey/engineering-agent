# Plan: Local JSON File Input for /start

## Context

Currently the workflow only accepts Jira ticket IDs (e.g., `SHRED-123`). The user wants to also accept a filepath to a local JSON file containing ticket data, bypassing Jira entirely. This enables running the workflow without Jira access or for ad-hoc work not tracked in Jira.

## Detection Logic

In `parse-args.sh`, the first positional arg is checked: if it ends in `.json` or contains `/` or `\`, treat as file path. Otherwise, validate as ticket ID. Unambiguous — Jira IDs never contain dots or slashes.

## Local Ticket Schema

New file: `schemas/local-ticket.schema.json`

```json
{
  "ticket_id": "LOCAL-001",       // required, must match ^[A-Z]+-[0-9]+$
  "title": "Short description",   // required
  "type": "Story",                // required: Story|Task|Bug
  "requirements": "Full text",    // required
  "acceptance_criteria": ["..."], // required, min 1
  "repo": "SHRED",               // required — key in repos.json
  "components": [],               // optional
  "labels": [],                   // optional
  "linked_issues": []             // optional — logged as warning, not resolved
}
```

`ticket_id` keeps `^[A-Z]+-[0-9]+$` format so all downstream tooling (branch names, run dirs, PRD.json, commit footers) works unchanged.

## Changes by File

### 1. `schemas/local-ticket.schema.json` — NEW
Define JSON Schema per above. Tests first via `validate-schemas.js`.

### 2. `scripts/parse-args.sh`
- After extracting first positional arg, branch on file vs ticket ID
- File path: validate exists -> read JSON -> validate against schema -> extract `ticket_id` + `repo` -> call `resolve-repo.sh` with synthetic ID `{repo}-0` -> replace `ticket_id` in output with real value from JSON
- Copy local JSON to `runs/{ticket_id}/ticket.json` so `--resume` works even if original file moves
- Add to output: `"input_source": "jira"|"local"`, `"input_file": "<path>"|null`

### 3. `scripts/resolve-repo.sh`
No changes needed. `parse-args.sh` passes `{repo}-0` which extracts project key correctly.

### 4. `schemas/prd.schema.json`
- Add optional `input_source` field: `enum: ["jira", "local"]`
- Update `ticket` description to note it can be a local ID

### 5. `scripts/validate-schemas.js`
Register `local-ticket.schema.json`.

### 6. `CLAUDE.md` — Orchestrator logic
- **Invocation Modes**: add local file example
- **Startup Sequence**: note `input_source` field from parse-args
- **Workflow Definition -> TICKET INTAKE**: add branch:
  - `input_source == "local"`: skip Jira Agent (validate, full_parse, dependency_check), construct ticket_data from local JSON, proceed to PLANNING. Still run `check-team-conflict.sh` to catch branch name collisions on GitHub.
  - `input_source == "jira"`: existing flow unchanged
- **Throughout workflow**: conditional Jira ops — PR Agent skips Jira link/transition, PR Monitor skips Jira monitoring, post-merge skips Jira transition, escalation skips Jira comments

### 7. `.claude/commands/start.md`
- Update description + Step 1 to show file path as valid input
- Note `input_source` / `input_file` in parse-args output
- Step 4: note TICKET INTAKE branching

### 8. `agents/pr-agent.md`
- When `input_source: "local"`: omit Jira URL line entirely from PR description, skip Jira transition

### 9. `Makefile`
Replace named `ISSUE=` variable with positional arg pattern. Usage becomes:

```bash
make start PROJ-123                    # Jira ticket
make start ./tickets/my-feature.json   # local file
make dry-run PROJ-123
make resume PROJ-123
```

Implementation: targets use `$(filter-out $@,$(MAKECMDGOALS))` to capture the positional arg after the target name. Add a catch-all `%:` target that does nothing (prevents "No rule to make target" errors for the positional arg). Remove the `ISSUE` variable entirely.

Help text updated to show both input forms without any named variable.

## What Stays Unchanged
- `resolve-repo.sh` — no changes
- `agents/jira-agent.md` — simply not invoked for local input
- `agents/planner-agent.md` — receives same data shape regardless of source
- All other agents — work from PRD.json, unaware of input source
- Branch naming, commit conventions, QA pipeline — all identical

## Verification
1. `scripts/validate-schemas.js` — validates local-ticket.schema.json
2. `parse-args.sh ./test-ticket.json` — outputs correct JSON with `input_source: "local"`
3. `parse-args.sh SHRED-123` — still works unchanged with `input_source: "jira"`
4. `make start ./test-ticket.json` — runs through intake + planning, skips Jira
5. `make dry-run SHRED-123` — positional arg works with all targets

## Resolved Decisions
- Local JSON copied to `runs/{ticket_id}/ticket.json` at intake for `--resume` resilience
- `check-team-conflict.sh` still runs for local tickets to catch branch collisions
- PR description omits Jira line entirely for local tickets
