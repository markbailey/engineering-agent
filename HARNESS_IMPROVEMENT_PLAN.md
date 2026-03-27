# Engineering Agent — Harness Improvement Plan

## Overview

Phased plan to address gaps identified in `HARNESS_AUDIT.md`. Each phase is self-contained and delivers independently testable value. Phases ordered by priority (P0 first). Within each phase, items are ordered by dependency.

**Delegation model:** The orchestrator (CLAUDE.md) delegates each item to a subagent via the Task tool.

### Resolved Design Decisions

| # | Question | Decision | Reason |
|---|---|---|---|
| 1 | Toolchain config location | In `repos.json` | Per-repo config alongside path/reviewers |
| 2 | AJV installation | Standalone bundle (`scripts/ajv-bundle.js`) | No package.json in orchestrator repo |
| 3 | Orphan check TS API | Standalone bundle | No dependency on target repo devDependencies |
| 4 | Flaky test registry scope | Per-repo (`runs/flaky-tests/{repo_name}.json`) | Tests can be flaky in one repo but stable in another |
| 5 | File locking strategy | mkdir-based primary (cross-platform) | Must work on Windows (Git Bash), macOS, Linux |
| 6 | Multi-ticket queue | Dropped | Each session works on a single ticket only |
| 7 | Revert mode review | Tests + secret scan only | Mechanical undo, not new code — skip Critic |
| 8 | Revert CLI format | `PROJ-123 --revert` (same as --resume, --dry-run) | Consistent with existing CLI pattern |
| 9 | Script file structure | All scripts flat in `scripts/` | Consistent with existing structure, no `lib/` subdirectory |

---

## Phase 1 — Pre-Flight & Timeouts (P0)

**Goal:** Eliminate silent failures from missing tools, bad config, and hanging operations.
**Estimated items:** 9

### 1.1 Pre-Flight Validation Script
**Delegate to:** General-purpose agent

- [ ] Create `scripts/preflight.sh` that validates:
  - All required tools installed and on PATH: `git`, `gh`, `node`, `npm`, `gitleaks`
  - `gh auth status` returns authenticated
  - `.env` exists and contains all required vars (`AGENT_EMPLOYEE_CODE`, `JIRA_URL`, etc.)
  - `AGENT_EMPLOYEE_CODE` is exactly 3 lowercase letters
  - `repos.json` exists and is valid JSON
  - For the target repo: directory exists, is a git repo, has remote `origin`
  - Jira reachable (Cloud: `curl -s -o /dev/null -w "%{http_code}" $JIRA_URL` returns 200/401/403)
- [ ] Output: JSON with `overall` (pass/fail) + `checks[]` (name, status, error)
- [ ] Exit 0 on pass, exit 1 on any failure
- [ ] Add preflight call to CLAUDE.md startup sequence as step 1 (before parse-args)

### 1.2 Command Timeout Wrapper
**Delegate to:** General-purpose agent

- [ ] Create `scripts/with-timeout.sh` wrapper:
  - Args: `<timeout_seconds> <command...>`
  - Uses `timeout` (GNU coreutils) on Linux, `gtimeout` on macOS (via coreutils), `Start-Process` fallback on Windows/MSYS
  - On timeout: kill process tree, log to run.log, exit 124 (standard timeout exit)
  - Env var override: `AGENT_COMMAND_TIMEOUT` (default 300s for tests, 120s for tsc, 60s for lint)
- [ ] Output: passthrough stdout/stderr from wrapped command

### 1.3 Integrate Timeouts Into Existing Scripts
**Delegate to:** General-purpose agent

- [ ] Update `regression-guard.sh`: wrap `npx tsc --noEmit`, `npm test` in with-timeout.sh
- [ ] Update `worktree-init.sh`: wrap `npm install` in with-timeout.sh
- [ ] Update `orphan-check.sh`: wrap grep operations in with-timeout.sh (30s default)
- [ ] Update `run-secret-scan.sh`: wrap gitleaks in with-timeout.sh
- [ ] Add timeout events to `notify.sh` event type map (icon: clock, severity: ERROR)
- [ ] Log all timeout events to run.log via run-log.sh

### 1.4 Update CLAUDE.md Startup Sequence
**Delegate to:** General-purpose agent

- [ ] Insert preflight as mandatory step 1 in startup sequence
- [ ] On preflight failure: log error, notify human, abort run (no partial work)
- [ ] Update script reference table with preflight.sh and with-timeout.sh

### 1.5 Test Phase 1
**Delegate to:** General-purpose agent

- [ ] Test preflight with all tools present (expect pass)
- [ ] Test preflight with gitleaks removed from PATH (expect fail + clear error)
- [ ] Test preflight with missing .env var (expect fail + identifies which var)
- [ ] Test preflight with non-existent repo path (expect fail + identifies repo)
- [ ] Test with-timeout.sh with a fast command (expect passthrough)
- [ ] Test with-timeout.sh with `sleep 10` and 2s timeout (expect kill + exit 124)
- [ ] Test regression-guard.sh timeout integration (expect timeout logged to run.log)

---

## Phase 2 — Toolchain Abstraction (P1)

**Goal:** Decouple QA/regression from Node.js. Enable any language/framework per repo.
**Estimated items:** 11

### 2.1 Extend repos.json Schema
**Delegate to:** General-purpose agent

- [ ] Add `toolchain` object to repos.json per-repo config:
  ```json
  {
    "PROJ": {
      "name": "repo-name",
      "path": "/local/path",
      "github_repo": "org/repo-name",
      "reviewers": ["user1"],
      "toolchain": {
        "install": "npm ci",
        "typecheck": "npx tsc --noEmit",
        "lint": "npx eslint .",
        "lint_fix": "npx eslint --fix . && npx prettier --write .",
        "format_check": "npx prettier --check .",
        "test": "npm test",
        "integration_test": "npm run test:integration",
        "build": null
      }
    }
  }
  ```
- [ ] Null values mean "skip this step"
- [ ] Update `repos.json.example` with toolchain section
- [ ] Add toolchain validation to `preflight.sh` (warn if commands not found)

### 2.2 Create Toolchain Resolver Script
**Delegate to:** General-purpose agent

- [ ] Create `scripts/resolve-toolchain.sh`:
  - Args: `<project_key> <step>` (e.g., `SHRED test`)
  - Reads repos.json, extracts toolchain command for step
  - If null or missing: output `{"skip": true, "reason": "not configured"}`
  - If present: output `{"skip": false, "command": "npm test"}`
- [ ] Exit 0 always (null is valid — means skip)

### 2.3 Update QA Agent Scripts
**Delegate to:** General-purpose agent

- [ ] Update `regression-guard.sh`:
  - Replace hardcoded `npx tsc --noEmit` with `resolve-toolchain.sh $PROJECT_KEY typecheck`
  - Replace hardcoded `npm test` with `resolve-toolchain.sh $PROJECT_KEY test`
  - Replace hardcoded prettier/eslint with `resolve-toolchain.sh $PROJECT_KEY lint_fix`
  - Skip any step where resolve-toolchain returns `skip: true`
- [ ] Update `worktree-init.sh`:
  - Replace hardcoded `npm install` with `resolve-toolchain.sh $PROJECT_KEY install`
  - Replace hardcoded `npx tsc --noEmit` baseline check with `resolve-toolchain.sh $PROJECT_KEY typecheck`

### 2.4 Update Agent Prompts for Toolchain Awareness
**Delegate to:** General-purpose agent

- [ ] Update `agents/qa-agent.md`: reference toolchain config instead of hardcoded npm/tsc commands
- [ ] Update `agents/developer-agent.md`: note that test commands come from toolchain config
- [ ] Update `agents/conflict-resolution-agent.md`: regression guard uses toolchain config

### 2.5 Update CLAUDE.md
**Delegate to:** General-purpose agent

- [ ] Add toolchain resolution to worktree setup section
- [ ] Update QA pipeline section to reference toolchain config
- [ ] Update script reference table with resolve-toolchain.sh

### 2.6 Test Phase 2
**Delegate to:** General-purpose agent

- [ ] Test resolve-toolchain.sh with existing SHRED config (expect npm commands)
- [ ] Test resolve-toolchain.sh with null step (expect skip)
- [ ] Test resolve-toolchain.sh with unknown project (expect error)
- [ ] Test regression-guard.sh with toolchain resolution (expect same behavior as before for Node repos)
- [ ] Test regression-guard.sh with all-null toolchain (expect all steps skipped, overall pass)

---

## Phase 3 — Schema Validation & Error Standardization (P1)

**Goal:** Full JSON Schema validation. Consistent error output from all scripts.
**Estimated items:** 8

### 3.1 Replace Custom Validator with Standalone AJV
**Delegate to:** General-purpose agent

- [ ] Bundle AJV + ajv-formats as standalone script:
  - Use `esbuild` to create single-file `scripts/ajv-bundle.js`
  - Self-contained — runs with just `node scripts/ajv-bundle.js`
- [ ] Rewrite `scripts/validate-schemas.js`:
  - Use bundled AJV with draft 2020-12 support
  - Validate types, patterns, enums, nested objects, $ref resolution
  - Mode 1 (no args): validate all schema files are valid schemas
  - Mode 2 (`data.json schema_name`): validate data file against named schema
  - Output: JSON with `valid` (bool), `errors[]` (path, message, expected)
- [ ] Preserve existing exit codes (0=valid, 1=invalid)

### 3.2 Add Schema Validation to Write Points
**Delegate to:** General-purpose agent

- [ ] Update `scripts/write-conflict-json.sh`: validate output against conflict.schema.json before writing
- [ ] Update `scripts/run-secret-scan.sh`: validate SECRETS.json against secrets.schema.json before writing
- [ ] Update `scripts/update-prd-status.sh`: validate PRD.json after status update
- [ ] Update `scripts/auto-repair.sh record`: validate entry against repair.schema.json
- [ ] Update `scripts/agent-learning.sh write`: validate entry against agent-learning.schema.json
- [ ] On validation failure: log ERROR, write invalid data to `{file}.invalid.json` for debugging, exit 1

### 3.3 Standardize Script Error Output
**Delegate to:** General-purpose agent

- [ ] Create `scripts/output.sh` sourced by all scripts:
  ```bash
  emit_result() { echo "{\"status\":\"$1\",\"data\":$2}"; }
  emit_error()  { echo "{\"status\":\"error\",\"error\":\"$1\",\"exit_code\":${2:-1}}"; exit ${2:-1}; }
  ```
- [ ] Update all scripts to use `emit_error` for error exits instead of plain `echo` or `exit`
- [ ] Prioritize scripts that compose (called by other scripts): resolve-repo.sh, resolve-toolchain.sh, validate-branch-name.sh, merge-base-into-feature.sh

### 3.4 Test Phase 3
**Delegate to:** General-purpose agent

- [ ] Test AJV validator against all existing schema files (expect all valid)
- [ ] Test AJV validator with intentionally malformed PRD.json (expect specific error messages)
- [ ] Test AJV validator with invalid enum value (e.g., `overall_status: "banana"`) (expect pattern/enum error)
- [ ] Test schema validation at write points (expect invalid data caught before disk write)
- [ ] Test standardized error output from 3+ scripts (expect consistent JSON structure)

---

## Phase 4 — Structured Escalation & Abort Cleanup (P1)

**Goal:** Categorize escalations for faster triage. Clean abort without orphaned state.
**Estimated items:** 10

### 4.1 Escalation Schema
**Delegate to:** General-purpose agent

- [ ] Create `schemas/escalation.schema.json`:
  ```json
  {
    "ticket": "PROJ-123 format",
    "escalations": [{
      "id": "esc-NNN",
      "timestamp": "ISO 8601",
      "category": "enum: blocked_dependency | test_failure | merge_conflict | review_stall | secret_detected | infra_failure | contradictory_feedback | team_conflict | unknown",
      "severity": "enum: critical | high | medium",
      "source_agent": "string",
      "stage": "string (workflow stage where escalation occurred)",
      "context": {
        "summary": "string (one-line description)",
        "details": "string (full context for human)",
        "artifacts": ["string (paths to relevant files)"],
        "suggested_action": "string"
      },
      "resolved": "boolean (default false)",
      "resolved_at": "nullable ISO 8601"
    }]
  }
  ```
- [ ] Validate with AJV (Phase 3 dependency)

### 4.2 Escalation Writer Script
**Delegate to:** General-purpose agent

- [ ] Create `scripts/escalate.sh`:
  - Args: `<ticket_id> <category> <severity> <source_agent> <stage> <summary> [--details "..."] [--suggested-action "..."]`
  - Writes `runs/{ticket_id}/ESCALATION.json` (appends to array if file exists)
  - Logs EVENT to run.log
  - Calls `notify.sh` with escalation event
  - Updates PRD.json status to "escalated" via update-prd-status.sh
  - Output: structured JSON confirmation

### 4.3 Replace Ad-Hoc Escalations
**Delegate to:** General-purpose agent

- [ ] Update CLAUDE.md: replace all "ESCALATE" instructions with `escalate.sh` calls, specifying category + severity
- [ ] Map existing escalation triggers to categories:
  | Current trigger | Category | Severity |
  |---|---|---|
  | Upstream ticket not done | blocked_dependency | medium |
  | Tests fail after 2 retries | test_failure | high |
  | Disconnected integrations | merge_conflict | critical |
  | 3 Critic rounds, unresolved | review_stall | high |
  | Gitleaks finding | secret_detected | critical |
  | npm install fails after repair | infra_failure | high |
  | Approve then block on same PR | contradictory_feedback | medium |
  | Human branch exists for ticket | team_conflict | medium |

### 4.4 Abort/Cancel Cleanup
**Delegate to:** General-purpose agent

- [ ] Create `scripts/abort-run.sh`:
  - Args: `<ticket_id> <reason>`
  - Steps:
    1. Check for open draft PR → close it (`gh pr close`)
    2. Update PRD.json `overall_status: "aborted"`
    3. Write ESCALATION.json with category "unknown" and the abort reason
    4. Log EVENT "run aborted" to run.log
    5. Call run-summary.sh with status "aborted"
    6. If input_source is jira: transition ticket back to original status, post comment
  - Does NOT remove worktree (preserves for resume or inspection)
  - Does NOT delete branches (may contain recoverable work)
- [ ] Output: JSON summary of cleanup actions taken

### 4.5 Integrate Abort Into Pause/Stop
**Delegate to:** General-purpose agent

- [ ] Update CLAUDE.md "Safe Checkpoints & Pause/Stop":
  - `--stop` now calls `abort-run.sh` for full cleanup
  - `--pause` checkpoints state but does NOT abort (existing behavior)
- [ ] Update `parse-args.sh` to pass abort reason if provided

### 4.6 Escalation Dashboard Tab
**Delegate to:** General-purpose agent

- [ ] Update `dashboard/server.js`: include ESCALATION.json in artifact merge
- [ ] Update `dashboard/index.html`:
  - Add "Escalations" tab per ticket
  - Display: category badge, severity color, summary, suggested action, timestamp
  - Sort by severity (critical first)
  - Highlight unresolved escalations

### 4.7 Test Phase 4
**Delegate to:** General-purpose agent

- [ ] Test escalate.sh with each category (expect valid ESCALATION.json)
- [ ] Test escalate.sh appending to existing escalation file (expect array grows)
- [ ] Test abort-run.sh with open draft PR (expect PR closed)
- [ ] Test abort-run.sh with no PR (expect graceful skip)
- [ ] Test abort-run.sh preserves worktree (expect directory still exists)
- [ ] Test dashboard renders escalation tab (expect categories displayed)

---

## Phase 5 — Cross-Platform Portability (P1)

**Goal:** Scripts work on Windows (MSYS/Git Bash), macOS, and Linux without modification.
**Estimated items:** 7

### 5.1 Audit and Fix grep Usage
**Delegate to:** General-purpose agent

- [ ] Replace all `grep -P` with `grep -E` across all scripts (already documented in REPAIR_KNOWLEDGE)
- [ ] Verify no `grep` flags incompatible with macOS default grep
- [ ] Update REPAIR_KNOWLEDGE.json: promote repair-1 to "high" confidence, mark as applied

### 5.2 Fix Hardcoded Paths
**Delegate to:** General-purpose agent

- [ ] Replace hardcoded Windows gitleaks path in `run-secret-scan.sh` with:
  ```bash
  GITLEAKS=$(command -v gitleaks 2>/dev/null || which gitleaks 2>/dev/null)
  ```
- [ ] Replace any hardcoded path separators (`\`) with `/` (bash handles forward slashes on Windows)
- [ ] Audit all scripts for `C:\` or Windows-specific paths

### 5.3 Fix Bash Version Compatibility
**Delegate to:** General-purpose agent

- [ ] Audit all scripts for bash 4+ features (associative arrays `declare -A`, `mapfile`, `readarray`, `${var,,}` lowercase)
- [ ] Replace with POSIX-compatible alternatives where possible
- [ ] Where bash 4+ is required: add version check at script top:
  ```bash
  if ((BASH_VERSINFO[0] < 4)); then emit_error "bash 4+ required"; fi
  ```
- [ ] Document minimum bash version in README.md prerequisites

### 5.4 Fix date Command Portability
**Delegate to:** General-purpose agent

- [ ] Audit all scripts using `date` — macOS uses BSD date, Linux uses GNU date
- [ ] Replace `date -d` (GNU) with portable alternative:
  ```bash
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u "+%Y-%m-%dT%H:%M:%SZ"
  ```
- [ ] Test timestamp generation on both platforms

### 5.5 Add Platform Detection
**Delegate to:** General-purpose agent

- [ ] Add platform detection to `scripts/output.sh`:
  ```bash
  PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
  IS_WINDOWS=false; IS_MACOS=false; IS_LINUX=false
  case "$PLATFORM" in
    mingw*|msys*|cygwin*) IS_WINDOWS=true ;;
    darwin*) IS_MACOS=true ;;
    linux*) IS_LINUX=true ;;
  esac
  ```
- [ ] Scripts that need platform-specific behavior source this file

### 5.6 Test Phase 5
**Delegate to:** General-purpose agent

- [ ] Run all scripts through `shellcheck` (static analysis for portability issues)
- [ ] Test gitleaks path resolution with gitleaks in PATH vs not in PATH
- [ ] Test timestamp generation matches ISO 8601 format
- [ ] Verify no `grep -P` remains in any script
- [ ] Verify no hardcoded Windows paths remain

---

## Phase 6 — Flaky Test Registry & Improved Orphan Check (P2)

**Goal:** Reduce false positives from flaky tests and grep-based orphan detection.
**Estimated items:** 9

### 6.1 Flaky Test Registry Schema
**Delegate to:** General-purpose agent

- [ ] Create `schemas/flaky-tests.schema.json`:
  ```json
  {
    "version": "integer",
    "last_updated": "ISO 8601",
    "entries": [{
      "id": "flaky-NNN",
      "test_name": "string (full test name or pattern)",
      "file": "nullable string",
      "repo": "string (project key)",
      "first_seen": "ISO 8601",
      "last_seen": "ISO 8601",
      "occurrences": "integer >= 1",
      "status": "enum: active | resolved | permanent",
      "notes": "nullable string"
    }]
  }
  ```

### 6.2 Flaky Test Detection Script
**Delegate to:** General-purpose agent

- [ ] Create `scripts/flaky-test.sh`:
  - Actions:
    - `check <test_name> <repo>` — returns `{"flaky": true/false}` based on registry
    - `record <test_name> <repo> [--file path]` — add/update entry in per-repo registry at `runs/flaky-tests/{repo_name}.json`
    - `retry <ticket_id> <repo>` — re-run failed tests that match flaky registry, return results
  - Flaky tests get one automatic retry before being treated as real failures
  - Non-flaky test failures are always real

### 6.3 Integrate Flaky Tests Into QA Pipeline
**Delegate to:** General-purpose agent

- [ ] Update `agents/qa-agent.md`: after test failure, check flaky registry before reporting fail
- [ ] Update CLAUDE.md QA pipeline: add flaky test check step between test failure and retry/escalation
- [ ] Update `agents/pr-monitor.md`: CI failures checked against flaky registry before routing to Developer Agent

### 6.4 Standalone Orphan Check with TypeScript Compiler API
**Delegate to:** General-purpose agent

- [ ] Create `scripts/orphan-check-ts.js` as standalone (bundled `typescript` compiler API):
  - For each file changed by base branch:
    - Find all exports removed/renamed
    - Find all references to those exports in feature branch files
    - Report: file, export name, referencing files, reference count
  - Falls back to `orphan-check.sh` (grep-based) for non-TypeScript repos
- [ ] Output: same JSON format as orphan-check.sh for compatibility

### 6.5 Scope Orphan Check to Feature Files Only
**Delegate to:** General-purpose agent

- [ ] Update `orphan-check.sh`: filter analysis to only files listed in PRD.json `files_affected`
- [ ] Accept PRD.json path as argument
- [ ] This addresses repair-2 in REPAIR_KNOWLEDGE.json (false positives from base-only changes)
- [ ] Update REPAIR_KNOWLEDGE.json: promote repair-2 to "high" confidence, mark as applied

### 6.6 Update Conflict Resolution Pipeline
**Delegate to:** General-purpose agent

- [ ] Update `conflict-resolution.sh`: try `orphan-check-ts.js` first, fall back to `orphan-check.sh`
- [ ] Selection based on: does `tsconfig.json` exist in worktree? Yes → TS checker. No → grep fallback.

### 6.7 Test Phase 6
**Delegate to:** General-purpose agent

- [ ] Test flaky-test.sh record + check cycle (expect registry populated, check returns true)
- [ ] Test flaky-test.sh with unknown test (expect flaky: false)
- [ ] Test orphan-check-ts.js with a known deleted export (expect detected)
- [ ] Test orphan-check-ts.js with a renamed export (expect detected)
- [ ] Test orphan-check.sh with PRD.json scoping (expect no false positives from base-only changes)
- [ ] Test fallback path (no tsconfig.json → grep-based orphan check)

---

## Phase 7 — Metrics Collection (P2)

**Goal:** Track cycle time, stage durations, retry rates, and learning effectiveness.
**Estimated items:** 8

### 7.1 Metrics Schema
**Delegate to:** General-purpose agent

- [ ] Create `schemas/metrics.schema.json`:
  ```json
  {
    "ticket": "PROJ-123",
    "started_at": "ISO 8601",
    "completed_at": "nullable ISO 8601",
    "outcome": "enum: completed | escalated | aborted",
    "cycle_time_seconds": "nullable integer",
    "stages": [{
      "name": "string",
      "started_at": "ISO 8601",
      "completed_at": "ISO 8601",
      "duration_seconds": "integer",
      "retries": "integer",
      "escalated": "boolean"
    }],
    "tasks": {
      "total": "integer",
      "completed": "integer",
      "retried": "integer",
      "blocked": "integer"
    },
    "qa": {
      "auto_fix_runs": "integer",
      "auto_fix_resolved": "integer",
      "test_failures": "integer",
      "test_retries": "integer"
    },
    "review": {
      "critic_rounds": "integer",
      "pr_feedback_rounds": "integer",
      "escalations": "integer"
    },
    "learning": {
      "standing_instructions_injected": "integer",
      "patterns_detected": "integer",
      "repairs_applied": "integer"
    }
  }
  ```

### 7.2 Metrics Collection Script
**Delegate to:** General-purpose agent

- [ ] Create `scripts/collect-metrics.sh`:
  - Args: `<ticket_id>`
  - Parses run.log (JSONL) to extract:
    - Stage transitions (timestamps from category changes)
    - Retry counts (grep for "retry" category entries)
    - Error counts
  - Reads PRD.json for task counts
  - Reads REVIEW.json for critic round count
  - Reads FEEDBACK.json for PR feedback round count
  - Reads ESCALATION.json for escalation count
  - Computes cycle time from first to last log entry
  - Computes per-stage durations
- [ ] Writes `runs/{ticket_id}/METRICS.json`
- [ ] Validates against metrics.schema.json

### 7.3 Aggregate Metrics Script
**Delegate to:** General-purpose agent

- [ ] Create `scripts/aggregate-metrics.sh`:
  - Scans all `runs/*/METRICS.json`
  - Computes:
    - Average cycle time (overall + per stage)
    - Escalation rate (% of runs)
    - Most common escalation categories
    - Retry rate per agent
    - Auto-fix resolution rate
    - Critic rounds distribution (1/2/3)
    - Learning system effectiveness (recurrence rate before/after instructions)
  - Output: JSON summary

### 7.4 Integrate Metrics Into Run Summary
**Delegate to:** General-purpose agent

- [ ] Update `run-summary.sh`: call `collect-metrics.sh` at end of every run
- [ ] Add key metrics to terminal banner (cycle time, task completion, escalations)

### 7.5 Dashboard Metrics Tab
**Delegate to:** General-purpose agent

- [ ] Update `dashboard/server.js`: serve METRICS.json + aggregate metrics
- [ ] Update `dashboard/index.html`:
  - Add "Metrics" tab (global, not per-ticket)
  - Display: cycle time trend, escalation rate, retry heatmap, learning effectiveness
  - Per-ticket: stage duration breakdown, task progress

### 7.6 Test Phase 7
**Delegate to:** General-purpose agent

- [ ] Test collect-metrics.sh with a completed run's run.log (expect valid METRICS.json)
- [ ] Test collect-metrics.sh with an escalated run (expect outcome: "escalated")
- [ ] Test aggregate-metrics.sh with multiple runs (expect averages computed)
- [ ] Test dashboard metrics tab renders (expect charts/tables visible)

---

## Phase 8 — Dry-Run Depth & Agent Self-Testing (P2)

**Goal:** Full pipeline simulation without side effects. Golden-file tests for agent prompts.
**Estimated items:** 10

### 8.1 Deep Dry-Run Mode
**Delegate to:** General-purpose agent

- [ ] Update CLAUDE.md dry-run behavior:
  - Parse ticket (real Jira read or local file)
  - Generate PRD.json (real planning)
  - Create worktree (real)
  - Implement tasks (real code changes)
  - Run QA (real tests)
  - Run Critic review (real)
  - Run conflict resolution (real merge)
  - Run secret scan (real)
  - **STOP before**: PR creation, Jira status transitions, reviewer assignment
  - **STOP before**: any `gh` command that creates/modifies PRs or issues
  - Write all artifacts to `runs/{ticket_id}/` with `dry_run: true` flag in PRD.json
- [ ] Update `parse-args.sh`: `--dry-run` sets `dry_run: true` in output
- [ ] Update PR Agent invocation in CLAUDE.md: check dry_run flag, skip if true

### 8.2 Dry-Run Report
**Delegate to:** General-purpose agent

- [ ] Create `scripts/dry-run-report.sh`:
  - Args: `<ticket_id>`
  - Reads all artifacts from `runs/{ticket_id}/`
  - Generates human-readable summary:
    - PRD.json task list + acceptance criteria coverage
    - Code changes (diff summary per task)
    - QA results (pass/fail per step)
    - Critic verdict + issues
    - Secret scan result
    - Conflict resolution result (if applicable)
    - Estimated PR size (files changed, lines added/removed)
  - Output: formatted text to stdout

### 8.3 Agent Test Fixtures Directory
**Delegate to:** General-purpose agent

- [ ] Create `tests/` directory structure:
  ```
  tests/
    fixtures/
      tickets/           <- sample ticket JSONs (local-ticket format)
      repos/             <- minimal git repos for testing
      expected/          <- golden-file expected outputs
    run-agent-test.sh    <- test runner
  ```
- [ ] Create 3 fixture tickets:
  - `simple-feature.json` — single-file, single-task Story
  - `multi-task-bug.json` — multi-file Bug with dependencies
  - `cross-repo-story.json` — multi-repo Story

### 8.4 Agent Test Runner
**Delegate to:** General-purpose agent

- [ ] Create `tests/run-agent-test.sh`:
  - Args: `<fixture_name>` or `all`
  - For each fixture:
    1. Run full pipeline in dry-run mode against fixture ticket
    2. Compare PRD.json structure against expected (task count, branch name format, repo mapping)
    3. Compare REVIEW.json structure against expected (verdict, issue categories present)
    4. Validate all artifacts against their schemas (using AJV validator)
  - Output: pass/fail per fixture + per check
  - Exit 0 if all pass, exit 1 if any fail

### 8.5 Script Unit Tests
**Delegate to:** General-purpose agent

- [ ] Create `tests/test-scripts.sh`:
  - Tests each utility script in isolation:
    - generate-branch-name.sh with various inputs
    - validate-branch-name.sh with valid/invalid names
    - validate-commit-msg.sh with valid/invalid messages
    - resolve-repo.sh with known/unknown project keys
    - resolve-toolchain.sh with various configs
    - preflight.sh with mock environment
  - Uses assert helpers (compare expected vs actual JSON output)
  - Exit 0 if all pass

### 8.6 Makefile Integration
**Delegate to:** General-purpose agent

- [ ] Add to Makefile:
  ```makefile
  test: test-scripts test-agents
  test-scripts:
  	bash tests/test-scripts.sh
  test-agents:
  	bash tests/run-agent-test.sh all
  test-agent:
  	bash tests/run-agent-test.sh $(FIXTURE)
  ```

### 8.7 Test Phase 8
**Delegate to:** General-purpose agent

- [ ] Run `make test-scripts` (expect all script tests pass)
- [ ] Run `make test-agents` with simple-feature fixture (expect dry-run completes, artifacts valid)
- [ ] Verify dry-run-report.sh produces readable output
- [ ] Verify dry-run mode creates NO PRs or Jira transitions (check gh/Jira state before/after)

---

## Phase 9 — Concurrency Safety (P2)

**Goal:** Prevent data corruption when multiple runs access shared state files.
**Estimated items:** 6

### 9.1 Cross-Platform File Locking
**Delegate to:** General-purpose agent

- [ ] Create `scripts/flock.sh`:
  - Primary: mkdir-based locking (atomic on all platforms including Windows/MSYS, macOS, Linux):
    ```bash
    with_lock() {
      local lockdir="$1.lock"; shift
      local timeout=${AGENT_LOCK_TIMEOUT:-10}
      local elapsed=0
      while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 1; elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$timeout" ]; then
          emit_error "lock timeout on $lockdir"; return 1
        fi
      done
      trap "rmdir '$lockdir' 2>/dev/null" EXIT
      "$@"
      local rc=$?
      rmdir "$lockdir" 2>/dev/null
      trap - EXIT
      return $rc
    }
    ```
  - Stale lock detection: if lockdir exists and is older than 5 minutes, remove it (dead process)
  - Lock timeout configurable via `AGENT_LOCK_TIMEOUT` (default 10s)

### 9.2 Protect Shared State Files
**Delegate to:** General-purpose agent

- [ ] Wrap all read-modify-write operations on shared files with `with_lock`:
  - `AGENT_LEARNING.json` — used by agent-learning.sh (write, lifecycle, increment-runs)
  - `REPAIR_KNOWLEDGE.json` — used by auto-repair.sh (record, promote, mark-failed)
  - `runs/{ticket_id}/loops.json` — used by check-loop-limit.sh
  - `runs/{ticket_id}/retries.json` — used by check-retry-limit.sh
  - `runs/{ticket_id}/failures.json` — used by auto-repair.sh track-failure

### 9.3 PID-Based Run Exclusion
**Delegate to:** General-purpose agent

- [ ] Update `scripts/pid.sh`:
  - On run start: write PID file to `runs/{ticket_id}/pid.json`
  - Before writing PID: check if existing PID is still running
  - If existing PID alive for same ticket: abort new run with "already running" error
  - On run end (normal/abort): remove PID file
- [ ] Prevent two concurrent runs on the same ticket

### 9.4 Test Phase 9
**Delegate to:** General-purpose agent

- [ ] Test with_lock with concurrent writes (expect no corruption)
- [ ] Test stale lock detection (create old lockdir, expect auto-cleanup)
- [ ] Test PID exclusion: start run, attempt second run on same ticket (expect rejection)
- [ ] Test lock timeout: hold lock, attempt second lock with short timeout (expect timeout error)
- [ ] Test on Windows (Git Bash) and macOS (expect same behavior)

---

## Phase 10 — Rate Limit Awareness (P3)

**Goal:** Respect API rate limits. Add jitter to prevent thundering herd.
**Estimated items:** 5

### 10.1 Rate Limit Header Parsing
**Delegate to:** General-purpose agent

- [ ] Create `scripts/rate-limit.sh`:
  - Parse GitHub API rate limit headers from `gh api` output:
    - `X-RateLimit-Remaining`
    - `X-RateLimit-Reset`
    - `Retry-After`
  - If remaining < 10: preemptive backoff until reset time
  - Log rate limit state to run.log

### 10.2 Add Jitter to Backoff
**Delegate to:** General-purpose agent

- [ ] Update `scripts/retry-with-backoff.sh`:
  - Add jitter: `delay * (1 + random(0, 0.3))`
  - Jitter via: `$(( delay + RANDOM % (delay * 30 / 100) ))`
  - Prevents synchronized retries from parallel runs

### 10.3 Integrate Rate Limit Awareness
**Delegate to:** General-purpose agent

- [ ] Update scripts that call `gh`: check-team-conflict.sh, worktree-cleanup.sh, check-pr-size.sh
- [ ] Before `gh` calls: check rate limit state, preemptive wait if near limit
- [ ] After `gh` calls: parse response headers, update rate limit state
- [ ] Add rate limit event to dashboard (new event type in notify.sh)

### 10.4 Test Phase 10
**Delegate to:** General-purpose agent

- [ ] Test jitter produces different delays across runs (expect non-deterministic)
- [ ] Test preemptive backoff when remaining=5 (expect wait logged)
- [ ] Test retry-with-backoff.sh with jitter enabled (expect increasing but varied delays)

---

## Phase 11 — Learning Effectiveness, Dependency Viz & Revert Mode (P3)

**Goal:** Measure standing instruction impact. Visualize ticket dependencies. Mechanical undo for bad merges.
**Estimated items:** 9

### 11.1 Learning Effectiveness Scoring
**Delegate to:** General-purpose agent

- [ ] Update `agent-learning.schema.json`: add fields:
  - `runs_with_instruction`: integer (count of runs where instruction was active)
  - `effectiveness_score`: number 0-1 (runs_without_recurrence / runs_with_instruction)
- [ ] Update `scripts/agent-learning.sh`:
  - `increment-runs` now also increments `runs_with_instruction` for active entries
  - `lifecycle` computes effectiveness_score on every transition
  - New action `prune`: auto-dismiss entries with effectiveness < 0.5 after 10+ runs (mark as "ineffective")
- [ ] Add "ineffective" to status enum in schema

### 11.2 Dependency Graph Script
**Delegate to:** General-purpose agent

- [ ] Create `scripts/dependency-graph.sh`:
  - Args: `<ticket_id>`
  - Walks Jira linked issues (blocked-by, blocks) up to depth 3
  - For each linked ticket: fetch status + PR status
  - Output modes:
    - `--json`: structured JSON (nodes + edges)
    - `--ascii`: ASCII art tree
    - `--dot`: DOT format for Graphviz
  - Color coding: green=done, yellow=in-progress, red=blocked, grey=not-started

### 11.3 Dashboard Dependencies Tab
**Delegate to:** General-purpose agent

- [ ] Update dashboard:
  - Add "Dependencies" tab per ticket
  - Render dependency graph (simple SVG or text-based rendering)
  - Show status of each linked ticket
  - Highlight blocking path

### 11.4 Revert Mode
**Delegate to:** General-purpose agent

- [ ] Add `--revert` flag to `parse-args.sh` (usage: `PROJ-123 --revert`)
  - Sets `mode: "revert"` in output JSON
  - Consistent with existing `--resume`, `--dry-run` flags
- [ ] Create `scripts/revert-run.sh`:
  - Args: `<ticket_id>`
  - Steps:
    1. Look up archived artifacts in `runs/{ticket_id}/`
    2. Find merged PR number + merge commit from PRD.json
    3. Create revert branch: `{code}_{ticket_id}_revert_{type}`
    4. Create worktree at standard path
    5. Run `git revert <merge_commit> --no-edit` in worktree
    6. Run tests via toolchain (`resolve-toolchain.sh test`) — fail = escalate
    7. Run secret scan (`run-secret-scan.sh`) — fail = escalate
    8. **Skip Critic review entirely** (mechanical undo)
    9. Open PR linking to original PR, with revert context in description
    10. If input_source is jira: post comment on ticket noting revert
  - Output: revert PR URL
- [ ] Add to CLAUDE.md: revert mode section describing the lightweight pipeline

### 11.5 Add Revert to Makefile
**Delegate to:** General-purpose agent

- [ ] Add to Makefile:
  ```makefile
  revert:
  	claude --permission-mode bypassPermissions "/start $(TICKET) --revert"
  ```

### 11.6 Test Phase 11
**Delegate to:** General-purpose agent

- [ ] Test effectiveness scoring after 10 runs with no recurrence (expect score ~1.0)
- [ ] Test prune action on low-effectiveness entry (expect status: "ineffective")
- [ ] Test dependency-graph.sh output formats (expect valid JSON/ASCII/DOT)
- [ ] Test revert mode with a previously merged ticket (expect revert PR opened, no Critic invocation)
- [ ] Test revert mode with test failure (expect escalation, no PR)

---

## Summary

| Phase | Priority | Items | Dependencies |
|---|---|---|---|
| 1. Pre-Flight & Timeouts | P0 | 9 | None |
| 2. Toolchain Abstraction | P1 | 11 | Phase 1 |
| 3. Schema Validation & Error Standardization | P1 | 8 | None |
| 4. Structured Escalation & Abort Cleanup | P1 | 10 | Phase 3 |
| 5. Cross-Platform Portability | P1 | 7 | Phase 3 |
| 6. Flaky Tests & Orphan Check | P2 | 9 | Phase 2, 3 |
| 7. Metrics Collection | P2 | 8 | Phase 3, 4 |
| 8. Dry-Run Depth & Self-Testing | P2 | 10 | Phase 2, 3 |
| 9. Concurrency Safety | P2 | 6 | None |
| 10. Rate Limit Awareness | P3 | 5 | Phase 9 |
| 11. Learning, Dependency Viz & Revert | P3 | 9 | Phase 4, 7 |

**Total items:** 92

### Execution Order

```
         Phase 1 (P0)
              |
     +--------+--------+
     |        |        |
  Phase 2   Phase 3  Phase 9
  (P1)      (P1)     (P2)
     |      +-+-+      |
     |  Phase 4  Phase 5
     |  (P1)    (P1)   |
     |      +-+-+      |
     +----+---+        |
     +----+----+       |
  Phase 6 Phase 7 Phase 8
  (P2)    (P2)    (P2) |
     +----+----+       |
       Phase 10 -------+
       (P3)
          |
       Phase 11
       (P3)
```
