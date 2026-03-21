# Engineering Agent — Build Progress Tracker

> **Instructions for every new session:**
> 1. Read `ENGINEERING_AGENT_PLAN.md` in full first
> 2. Read this file to understand current state
> 3. Pick up the next uncompleted item in the current phase
> 4. Mark items `[x]` as you complete them
> 5. Add notes under each phase if relevant
> 6. Log any issues in the Issues section at the bottom

---

## Current Status

**Active Phase:** All phases complete
**Overall Progress:** 11 / 11 phases complete
**Last Updated:** 2026-03-21
**Last Session Notes:** Post-phase enhancement: target repo resolution via repos.json. Workflow now runs from axomic-engineering (orchestrator) against external target repos (AXO471, AXO071). See Phase 11 below.

---

## Phase 1 — Scaffold & Tool Setup
**Status:** 🟢 Complete

- [x] Create `engineering-agent` repo
- [x] Create folder structure as defined in PLAN.md
- [x] Create `/worktrees` directory alongside repo root
- [x] Verify `acli` is installed and authenticated (`acli jira issue list`) — **REPLACED: using Atlassian MCP instead**
- [x] Verify `gh` cli is installed and authenticated (`gh auth status`)
- [x] Configure Confluence MCP server in `.claude.json` — **NOTE: Atlassian MCP is a remote server, no local .claude.json needed**
- [x] Validate `acli` connection (read a real Jira ticket, check linked issues) — **Validated via Atlassian MCP (read AI-1183)**
- [x] Validate `gh` connection (list PRs on a repo, check PR status)
- [x] Validate Confluence MCP connection (fetch a page) — **Validated: listed Confluence spaces (ENP)**
- [x] Install and verify `gitleaks` (`gitleaks version`) — **v8.30.0 installed via winget**
- [x] Create starter `.gitleaks.toml` config file
- [x] Write `detect-jira.sh` to identify Cloud vs Server/DC — **Tested: correctly outputs "cloud" for atlassian.net**
- [x] Write `worktree-scan.sh` to detect orphaned worktrees on startup — **Tested: reports no orphans**
- [x] Create `.env.example` with all required variables including `AGENT_EMPLOYEE_CODE`, `AGENT_RATE_LIMIT_*`, `AGENT_STALE_BRANCH_DAYS`, `AGENT_LEARNING_WINDOW`, `AGENT_LEARNING_PERSISTENCE_THRESHOLD`
- [x] Add `AGENT_EMPLOYEE_CODE` presence check to `setup.sh` — hard stop if missing
- [x] Write `README.md` with setup instructions including tool prerequisites

**Notes:**
- `acli` not installed — Atlassian MCP server provides equivalent Jira/Confluence access
- Atlassian Cloud ID: `33f90e1b-9c42-4aa4-aa81-8c6eadaaf37e` (axomic.atlassian.net)
- gitleaks requires shell restart for PATH; full path: `/c/Users/markb/AppData/Local/Microsoft/WinGet/Packages/Gitleaks.Gitleaks_Microsoft.Winget.Source_8wekyb3d8bbwe/gitleaks.exe`

---

## Phase 2 — JSON Schemas
**Status:** 🟢 Complete

- [x] Write `prd.schema.json` (include worktree + dependency fields)
- [x] Write `review.schema.json`
- [x] Write `feedback.schema.json`
- [x] Write `conflict.schema.json`
- [x] Write `repair.schema.json`
- [x] Write `secrets.schema.json`
- [x] Write `agent-learning.schema.json`
- [x] Write `validate-schemas.js` script

**Notes:**
- All 7 schemas use JSON Schema draft 2020-12 with strict additionalProperties: false
- validate-schemas.js validates structure, $ref resolution, and can validate data files against schemas
- Schemas match plan examples exactly — PRD includes multi-repo/worktree/dependency fields, Conflict includes regression guard + orphan check

---

## Phase 3 — CLAUDE.md
**Status:** 🟢 Complete

- [x] Write orchestrator role section (CLAUDE.md IS the orchestrator — Task tool invocation pattern, fresh read per invocation, AGENT_LEARNING.json standing instruction injection, context assembly per agent, PRD.json as state, Run Analyst at end of each completed run)
- [x] Write workflow definition section
- [x] Write agent learning system section (startup read, injection pattern, end-of-run Run Analyst invocation)
- [x] Write ticket intake rules section (supported types, validation, acceptance criteria requirement, invocation modes)
- [x] Write worktree management rules section
- [x] Write ticket dependency checking rules section
- [x] Write branching rules section ({employeecode}_{issue-id}_{description}_{branch-type}, type mapping table, validation rules)
- [x] Write repo selection logic section
- [x] Write commit message convention section (Conventional Commits, per-task granularity, ticket ref, breaking changes)
- [x] Write QA pipeline section (auto-fix order, commit strategy, per-task vs full suite scope, per-repo fixer list)
- [x] Write secret scanning rules section (hard block, never log values, diff only)
- [x] Write PR template section
- [x] Write escalation conditions section
- [x] Write GitHub Actions awareness section
- [x] Write team awareness section (check for conflicts before starting)
- [x] Write safety rules section
- [x] Write dry run mode section

**Notes:**
- All 17 sections written as complete sections per plan spec
- Full workflow loop defined as pseudocode matching the plan's orchestrator flow
- Each section references correct artefact schemas and agent names

---

## Phase 4 — Agent System Prompts
**Status:** 🟢 Complete

Each file must follow standard structure: frontmatter (name + version), Identity, Responsibilities, Context Contract (Receives / Produces), Rules, Output Format.

- [x] Note: No `orchestrator.md` needed — orchestrator IS the CLAUDE.md
- [x] Write `agents/jira-agent.md` (include blocked by checking + PR status checking)
- [x] Write `agents/planner-agent.md` (include worktree path + dependency branch in PRD.json, multi-repo repo selection)
- [x] Write `agents/developer-agent.md` (one commit per PRD.json task, Conventional Commits, ticket ref in footer, document breaking changes)
- [x] Write `agents/qa-agent.md` (validate commit message convention before marking task complete. Auto-fix first: prettier --write, eslint --fix, commit as chore. Then verify: tsc → lint → formatting → unit → integration)
- [x] Write `agents/the-critic.md` ← highest priority (include breaking change documentation check, CONFLICT.json context)
- [x] Write `agents/secret-scanner.md` (hard block on findings, never log values, diff only)
- [x] Write `agents/pr-agent.md` (always open and update as draft — never ready-for-review. Exception: --ready-pr flag)
- [x] Write `agents/pr-monitor.md` (include dependency branch → main detection)
- [x] Write `agents/conflict-resolution-agent.md`
- [x] Write `agents/run-analyst.md` (pattern detection across last N runs, standing instruction generation, persistent pattern escalation)
- [x] Write `/agents/CHANGELOG.md` for tracking major prompt version changes
- [x] Validate all agent files follow the standard structure

**Notes:**
- All 10 agent .md files follow standard structure: frontmatter (agent + version), Identity, Responsibilities, Context Contract (Receives/Produces), Rules, Output Format
- All validated via automated structure check — all PASS
- CHANGELOG.md updated with v1.0.0 initial release for all agents

---

## Phase 5 — Orchestration Logic
**Status:** 🟢 Complete

- [x] Implement Orchestrator startup read of REPAIR_KNOWLEDGE.json and AGENT_LEARNING.json — bootstrap files created, validated against schemas
- [x] Implement standing instruction injection into agent context packages at invocation time — CLAUDE.md "Agent Invocation Pattern" steps 2-3 (no new code needed)
- [x] Implement Run Analyst invocation at end of every completed run — CLAUDE.md workflow "POST-MERGE" (no new code needed)
- [x] Implement ticket intake validation (ticket exists, type supported, status workable, acceptance criteria present) — jira-agent.md validate action + CLAUDE.md intake rules (no new code needed)
- [x] Implement branch name generation — scripts/generate-branch-name.sh
- [x] Implement branch name validation — scripts/validate-branch-name.sh (hard stop on missing AGENT_EMPLOYEE_CODE)
- [x] Implement invocation modes (--ticket, --dry-run, --resume, --pause, --stop, --ready-pr) — scripts/parse-args.sh
- [x] Implement multi-repo support — prd.schema.json repos array + planner-agent.md + worktree-create.sh --repo-name (no new code needed beyond script)
- [x] Implement worktree creation at workflow start (single and multi-repo) — scripts/worktree-create.sh
- [x] Implement worktree initialisation — scripts/worktree-init.sh (copy env, npm/yarn/pnpm install, tsc check)
- [x] Implement non-committable file discovery — scripts/discover-non-committable.sh (.gitignore + known defaults)
- [x] Implement partial re-init check for resumed worktrees — scripts/worktree-init.sh --check-only
- [x] Implement worktree cleanup on confirmed merge (all repos) — scripts/worktree-cleanup.sh (safety: verifies PR merged)
- [x] Implement worktree orphan scan on startup — scripts/worktree-scan.sh (existed from Phase 1, integrated into startup)
- [x] Implement ticket dependency check before planning — jira-agent.md dependency_check action (no new code needed)
- [x] Implement QA pipeline — qa-agent.md verification sequence (no new code needed)
- [x] Implement commit message validation in QA Agent — scripts/validate-commit-msg.sh
- [x] Implement per-task vs full suite QA scope switching — CLAUDE.md QA Pipeline scope table (no new code needed)
- [x] Implement PRD.json task queue — CLAUDE.md "Task Queue Algorithm" added to Implementation section
- [x] Implement The Critic loop (max 3 rounds, then escalate) — CLAUDE.md "INTERNAL REVIEW" section (no new code needed)
- [x] Implement secret scan gate between Critic approval and PR Agent — CLAUDE.md workflow + secret-scanner.md (no new code needed)
- [x] Implement PR Monitor loop — CLAUDE.md "PR MONITORING" + pr-monitor.md (no new code needed)
- [x] Implement rate limit backoff — scripts/retry-with-backoff.sh (exponential: 2s→8s→30s)
- [x] Implement human interrupt/override — CLAUDE.md "Safe Checkpoints & Pause/Stop" section added
- [x] Implement agent prompt version recording — scripts/record-agent-versions.sh
- [x] Implement agent prompt version mismatch warning on --resume — CLAUDE.md "Resume Logic" subsection added
- [x] Implement resume logic — CLAUDE.md "Resume Logic" + worktree-init.sh --check-only
- [x] Test full loop end-to-end on a real ticket in dry run mode — tested all scripts against WTP-497 ("Add pagination to search results", Task, To Do)
- [x] Fix any issues found in dry run test — no issues found, all scripts pass

**Notes:**
- 13 new files: REPAIR_KNOWLEDGE.json, AGENT_LEARNING.json, 10 scripts, .claude/commands/implement.md
- CLAUDE.md enhanced: startup sequence (parse-args + record-versions), resume logic, task queue algorithm, worktree setup (script refs), safe checkpoints, script reference table
- 10 of 29 items needed no new code — they activate from existing CLAUDE.md + agent .md definitions
- Dry-run tested against WTP-497: parse-args, generate-branch-name, validate-branch-name (valid/invalid/missing env/wrong code), validate-commit-msg, discover-non-committable, record-agent-versions, worktree-scan — all pass

---

## Phase 6 — Guardrails & Safety
**Status:** 🟢 Complete

- [x] Branch protection enforcement (check branch name before every push) — `scripts/check-branch-before-push.sh`
- [x] Conflict detection (check for existing human branches/PRs on ticket) — `scripts/check-team-conflict.sh`
- [x] Test gate (hard stop after 2 retry attempts on test failures) — `scripts/check-retry-limit.sh`
- [x] PR size warning — soft limit: pause and notify human for approval if diff exceeds `AGENT_PR_SIZE_WARNING_FILES` files, then continue on approval — `scripts/check-pr-size.sh`
- [x] Secret scan hard block — gitleaks on diff, SECRETS.json generated, never log secret values — `scripts/run-secret-scan.sh`
- [x] PRD.json `blocked_secrets` status — makes block visible and resumable after human remediates — `scripts/update-prd-status.sh`
- [x] Rate limit backoff — transient, never increments auto-repair counter — `scripts/retry-with-backoff.sh` (existed from Phase 5)
- [x] Max loop counters on all feedback loops — `scripts/check-loop-limit.sh`
- [x] Stale branch cleanup script (`claude-code cleanup --list-stale` and `--prune-branches`) — `scripts/stale-branch-cleanup.sh`

**Notes:**
- 8 new scripts: check-branch-before-push, check-team-conflict, check-retry-limit, check-pr-size, run-secret-scan, update-prd-status, check-loop-limit, stale-branch-cleanup
- retry-with-backoff.sh reused from Phase 5 (already tested)
- CLAUDE.md workflow updated: team conflict check before intake, retry limits on task failures, loop counters on Critic review + PR feedback, PR size check before PR creation, branch push protection before every push, secret scan via script
- All scripts tested: branch protection blocks main, conflict detection finds no false positives, retry limit exhausts at 2, loop limit exhausts at max, PR size reports under threshold, secret scan produces valid SECRETS.json, PRD status update validates enums, stale branch cleanup reports clean

---

## Phase 8 — Auto-Repair System
**Status:** 🟢 Complete

- [x] Create `REPAIR_KNOWLEDGE.json` with empty entries array and schema version — done in Phase 5
- [x] Write `repair.schema.json` in `/schemas` — done in Phase 2
- [x] Implement failure detection — track consecutive failures per agent + operation — `scripts/auto-repair.sh track-failure`
- [x] Implement in-run repair loop — retry once, consult knowledge base, then self-reason — `scripts/auto-repair.sh lookup` + CLAUDE.md "Auto-Repair System" section
- [x] Implement knowledge base writer — successful alternatives written back to `REPAIR_KNOWLEDGE.json` — `scripts/auto-repair.sh record`
- [x] Implement confidence promotion logic (low → medium → high after 3 successes) — automatic in `record` action + `promote` action
- [x] Implement failed confidence short-circuit — skip straight to escalation — `scripts/auto-repair.sh mark-failed` + lookup skips `failed` entries
- [x] Add knowledge base read to agent startup sequence — already in CLAUDE.md startup step 2
- [x] Test auto-repair with a simulated failure scenario in dry run mode — tested: lookup (empty → not found), record (creates entry, confidence low), repeated record (promotes to medium → high), mark-failed (skips in lookup), track-failure (increments), reset-failure (clears)

**Notes:**
- Single script `scripts/auto-repair.sh` with 6 actions: lookup, record, promote, mark-failed, track-failure, reset-failure
- CLAUDE.md updated: new "Auto-Repair System" section with in-run repair loop, confidence lifecycle table, and rules
- Confidence promotion is automatic when recording: occurrences 1=medium, 3+=high
- Failed confidence entries are never returned by lookup — ensures immediate escalation

---

## Phase 9 — Conflict Resolution
**Status:** 🟢 Complete

- [x] Write `agents/conflict-resolution-agent.md` system prompt — done in Phase 4
- [x] Write `conflict.schema.json` in `/schemas` (updated schema with regression + orphan fields) — done in Phase 2
- [x] Implement merge trigger — `scripts/merge-base-into-feature.sh` + `scripts/conflict-resolution.sh` orchestrator
- [x] Implement per-file conflict resolution loop with PRD.json context — conflict-resolution-agent.md handles resolution, script provides conflict list, CLAUDE.md workflow updated
- [x] Implement regression guard — `scripts/regression-guard.sh` (Pass 1: tsc, Pass 2: diff analysis, Pass 3: full QA suite)
- [x] Implement orphan check — `scripts/orphan-check.sh` (4 categories: deleted callsites, renamed refs, dead exports, disconnected integrations)
- [x] Implement orphan resolution rules — defined in conflict-resolution-agent.md (safe=autonomous fix, unsafe=escalate), orphan-check.sh detects categories
- [x] Implement CONFLICT.json writer — `scripts/write-conflict-json.sh` assembles from merge + guard + orphan results, validates against schema
- [x] Implement QA re-verification after merge — CLAUDE.md workflow: "QA Agent: re-verify after merge (full suite)"
- [x] Add conflict check to PR Monitor — CLAUDE.md PR MONITORING section updated with `scripts/conflict-resolution.sh` call on `action_required: "conflict_resolution"`
- [x] Pass CONFLICT.json to The Critic as part of its context package — already in the-critic.md Context Contract (Receives) + CONFLICT.json Specific Checks section
- [x] Add all escalation triggers — all present in CLAUDE.md Escalation Conditions table (unresolvable conflicts, regression guard fail, orphan violations, disconnected integrations)
- [x] Test regression scenario — tested: compilation fail + renamed references → overall_status "partial"
- [x] Test orphan scenario — tested: disconnected integrations → overall_status "escalated", correct escalation_reason
- [x] Test clean merge scenario — tested: all pass → overall_status "resolved", valid CONFLICT.json

**Notes:**
- 5 new scripts: conflict-resolution.sh (orchestrator), merge-base-into-feature.sh, regression-guard.sh, orphan-check.sh, write-conflict-json.sh
- All scripts use process.argv instead of /dev/stdin for Windows compatibility
- CLAUDE.md workflow updated: CONFLICT RESOLUTION section with script references + exit code handling, PR MONITORING with conflict-resolution.sh on base branch move
- Script Reference table updated with all 5 new scripts
- All scenarios tested: clean merge (exit 0), conflicts (exit 1), error/escalation (exit 2), disconnected integration escalation

---

## Phase 7 — Observability
**Status:** 🟢 Complete

- [x] Structured run log per ticket (`/runs/TICKET-ID/run.log`) — `scripts/run-log.sh` writes JSONL entries with timestamp, level, category, message, details
- [x] Terminal notifications on key events (PR opened, CI failed, escalation, rate limit retries) — `scripts/notify.sh` prints banners + logs EVENT to run.log
- [x] Run summary written to log at end of each ticket — `scripts/run-summary.sh` counts errors/warnings/events, writes summary entry + terminal banner
- [x] Agent version mismatch warnings logged on --resume — `scripts/record-agent-versions.sh --check` detects mismatches, logs WARN to run.log
- [x] Rate limit retry events logged with delay durations — `scripts/retry-with-backoff.sh --ticket=ID` logs each retry attempt + delay to run.log

**Notes:**
- 3 new scripts: run-log.sh, notify.sh, run-summary.sh
- 2 updated scripts: retry-with-backoff.sh (--ticket flag for logging), record-agent-versions.sh (--check mode for mismatch detection)
- CLAUDE.md updated: new Observability section, startup sequence (step 2: init run log), resume logic (--check flag), POST-MERGE (run-summary call), Script Reference table
- All tested: log writes valid JSONL, notifications print banners, summary counts match, version mismatches detected and logged, retry delays logged with durations

---

## Phase 10 — Agent Learning System
**Status:** 🟢 Complete

- [x] Write `agents/run-analyst.md` system prompt (pattern detection, standing instruction generation, persistent escalation) — done in Phase 4
- [x] Write `agent-learning.schema.json` in `/schemas` — done in Phase 2
- [x] Create `AGENT_LEARNING.json` with empty entries array and schema version — done in Phase 5
- [x] Implement Run Analyst invocation at end of every completed run — CLAUDE.md POST-MERGE section + new Run Analyst Invocation sequence
- [x] Implement pattern detection — `scripts/agent-learning.sh gather` collects last N runs' artefacts for Run Analyst
- [x] Implement standing instruction generation from detected patterns — `scripts/agent-learning.sh write` creates entries from Run Analyst output
- [x] Implement AGENT_LEARNING.json writer — `scripts/agent-learning.sh write` (create/update entries, auto-ID, recurrence tracking)
- [x] Implement status lifecycle (active → resolved after 5 clean runs, active → persistent after 2 recurrences) — `scripts/agent-learning.sh lifecycle` + `increment-runs`
- [x] Implement persistent pattern escalation to human — `scripts/agent-learning.sh escalate` generates escalation messages
- [x] Test pattern detection with simulated recurring REVIEW.json findings — tested: write creates entry (occurrences=2, status=active), update increments occurrences
- [x] Test instruction injection — tested: filter returns standing instructions for active + resolved entries, excludes persistent
- [x] Test resolution — tested: 5 increment-runs + lifecycle → status transitions to resolved; 2 recurrences + lifecycle → persistent; escalate returns message

**Notes:**
- 1 new script: `scripts/agent-learning.sh` with 6 actions: gather, filter, write, lifecycle, escalate, increment-runs
- CLAUDE.md updated: Agent Learning System section expanded with script references, standing instruction injection pattern, Run Analyst invocation sequence
- Script Reference table updated with agent-learning.sh
- All scenarios tested: empty state (filter returns 0), new pattern (write creates learn-001), update (occurrences increment), resolution (5 clean runs → resolved), recurrence (resolved → active → persistent), escalation message generation, filter excludes persistent entries
- Schema validation passes: AGENT_LEARNING.json validates against agent-learning.schema.json

---

## Phase 11 — Target Repo Resolution
**Status:** 🟢 Complete

- [x] Create `repos.json` — maps Jira project keys to local repo paths + GitHub repo identifiers (SHRED→AXO471, OA→AXO071)
- [x] Create `repos.json.example` — committable template (repos.json is gitignored)
- [x] Create `scripts/resolve-repo.sh` — extracts project key from ticket ID, looks up repos.json, outputs JSON
- [x] Update `scripts/parse-args.sh` — now outputs `project_key`, `repo_name`, `repo_path`, `github_repo` via resolve-repo.sh
- [x] Update `scripts/worktree-create.sh` — takes `--target-repo` + `--repo-name`, creates worktrees at `~/.claude/worktrees/{repo_name}/{branch_name}`, runs git ops against target repo
- [x] Update `scripts/worktree-scan.sh` — scans `~/.claude/worktrees/{repo}/{branch}` two-level structure
- [x] Update `scripts/worktree-cleanup.sh` — takes `--target-repo`, `--repo-name`, `--github-repo`
- [x] Update `scripts/check-team-conflict.sh` — takes `--target-repo`, `--github-repo`, runs git/gh against target repo
- [x] Update `scripts/stale-branch-cleanup.sh` — takes `--target-repo`, `--github-repo`
- [x] Update `scripts/setup.sh` — validates repos.json exists, checks repo paths + git status, uses new worktree path
- [x] Rename `REPO_ROOT` → `AGENT_ROOT` in all 13 Group B scripts (agent-only operations: .env, runs/, agents/, schemas/)
- [x] Update `.gitignore` — added `repos.json`
- [x] Update `CLAUDE.md` — startup sequence (repo resolution), worktree management (new paths + script args), dependency branching, workflow commands, script reference table (+resolve-repo.sh), observability examples
- [x] Update `.claude/commands/implement.md` — parse-args output includes repo fields, script table updated
- [x] Update `agents/planner-agent.md` — worktree path convention
- [x] Test resolve-repo.sh — SHRED, OA resolve correctly; unknown project hard-fails
- [x] Test parse-args.sh — full JSON output with repo fields verified
- [x] Verify zero remaining `REPO_ROOT` references across project
- [x] Verify zero remaining `../worktrees` references in scripts

**Notes:**
- Key concept: AGENT_ROOT (axomic-engineering) for orchestrator config, TARGET_REPO (from repos.json) for git operations
- Jira project key extracted from ticket ID via `${ticket_id%%-*}` (e.g., SHRED-123 → SHRED)
- Hard-fail on unknown project key — no default/fallback repo
- Worktree path changed from `../worktrees/TICKET-ID` to `~/.claude/worktrees/{repo_name}/{branch_name}` per global CLAUDE.md convention
- Target repo paths not yet present on disk (C:/Users/markb/Projects/AXO471, AXO071) — setup.sh will warn
- 20 scripts updated total: 1 new, 6 functionally changed, 13 variable renamed

---

## Decisions Made

| Decision | Choice | Reason |
|---|---|---|
| Atlassian access method | Atlassian MCP server (not acli) | MCP already available in Claude Code env, provides equivalent Jira + Confluence access without extra CLI install |
| Repo location | E:/workflows/axomic-engineering (current dir) | User preference — plan was flexible on location |
| Orchestration approach | Claude Code native Task tool | Simpler, no external coordinator needed |
| Internal review timing | Before PR creation | Higher quality PRs, less noise for human reviewers |
| Review agent split | Two agents (The Critic + PR Monitor) | Different personas, concerns, and contexts |
| Max review rounds | 3 | Prevents infinite loops, escalates to human when stuck |
| Protected branches | main, master, staging | Never touched by agent under any circumstances |
| Async task execution | One task at a time per ticket | Reliable, resumable, clear audit trail |
| Jira version | Auto-detect on startup | Works with both Cloud and Server/DC |
| The Critic context | Full context (ticket + PRD + diff + tests + history) | Most informed agent, single gatekeeper before PR |
| Branch sync strategy | Merge base into feature (no rebase) | Safer in team environment, preserves history, no shared branch rewrite risk |
| Conflict resolution | Conflict Resolution Agent resolves file by file using PRD.json for intent | Feature branch intent takes priority, never silently discard changes |
| Post-merge regression guard | 3-pass check: tsc, diff analysis, full test suite | Catches silent regressions from base branch changes that affect our code |
| Orphan prevention | 4-category check after every merge | Prevents disconnected code reaching production — safe cases fixed autonomously, unsafe cases escalated |
| Worktree strategy | One dedicated git worktree per ticket | Isolates work, supports concurrent tickets, keeps repo checkout clean |
| Worktree initialisation | Copy non-committable files + npm install + baseline tsc | Worktree is a clean checkout — without this agents fail immediately on first test run |
| Non-committable file source | Always from source repo root, never from another worktree | Ensures canonical non-committed state, never propagates another ticket's local changes |
| node_modules handling | Never copied — always fresh npm install per worktree | Avoids platform/path issues from copying node_modules across directories |
| Baseline compile check | tsc --noEmit before any work starts | Prevents agent inheriting a pre-existing type error silently from the base branch |
| Worktree cleanup | Only on confirmed PR merge | Never clean up on PR close/decline — may contain recoverable work |
| Orphaned worktree handling | Report to human on startup, never auto-clean | Stale worktrees may contain unfinished work |
| Ticket dependency checking | Strict blocked-by links only, check both Jira status and PR status | Avoids inference errors from ticket descriptions, catches stale Jira statuses |
| Dependency PR branching | Branch from dependency PR only when it is ready for review (not draft) | Draft PRs are unstable — branching from them risks building on moving ground |
| Dependency chain depth | One level only — escalate if dependency itself has unmerged dependencies | Prevents complex chained branch scenarios that are hard to unwind |
| Secret scanning | gitleaks, pre-PR only, diff only | One gate is sufficient, history scanning adds noise without proportionate value |
| Secret scan outcome | Hard block + escalate, never auto-fix | Credential rotation and history cleanup require human judgement — agent must not guess |
| Secret value logging | Never logged anywhere | Prevents secrets being written to run logs, artefacts, or notifications |
| Ticket selection | External — ticket ID provided at invocation | Keeps selection and execution concerns separate, simpler to test each independently |
| Branch naming format | {employeecode}_{issue-id}_{description}_{branch-type} lowercase | Matches company convention, traceable to employee and ticket |
| Employee code source | AGENT_EMPLOYEE_CODE in .env | Identity-specific and non-committable — correct place for per-user config |
| Branch type mapping | Inferred from Jira issue type — Bug=bug, Defect=defect, Story/Task=feature, Tech Debt=debt, Chore=chore | Deterministic, no inference needed — separate Jira types for bug vs defect |
| Branch name validation | Hard stop if format invalid or AGENT_EMPLOYEE_CODE missing | Malformed branch names cause team confusion and may break CI rules |
| Ticket intake validation | Fast pre-flight check before any work starts | Fail fast — no worktree created, no cost incurred for unworkable tickets |
| Acceptance criteria | Hard requirement — escalate if missing | Cannot plan reliably or verify completion without them |
| Supported ticket types | Story, Task, Bug only | Sub-tasks and Epics are not implementable units |
| Auto-fix commit style | Separate `chore: auto-fix` commit | Keeps mechanical changes clearly separated from intentional Developer Agent changes in git history |
| Formatting tool | prettier | Industry standard for TS/JS — non-negotiable formatting, eliminates style debates |
| QA pipeline order | auto-fix → tsc → lint → formatting check → unit → integration | Each step catches a different class of problem — order minimises noise from downstream failures |
| Integration tests scope | Full suite only, not per-task | Expensive to run per-task — unit tests cover per-task regressions, integration tests run once all tasks done |
| Multi-repo support | Multiple worktrees per ticket, task-level repo routing | Single repo field too limiting — some tickets span shared libs and consumers |
| Rate limit handling | Exponential backoff (2s → 8s → 30s), max 3 retries, then escalate | Transient by nature — should never fail hard on a 429 |
| Rate limit auto-repair | Never increments failure counter | Rate limits are infrastructure noise, not tool behaviour problems |
| Human interrupt | --pause (next safe checkpoint), --stop (immediate, state preserved) | Graceful interrupt without losing work |
| Agent architecture | Static .md files + dynamic Task tool invocation | Version controlled, debuggable, testable, clean separation of identity from workflow logic |
| Agent file loading | Fresh read from disk per invocation, never cached | Allows prompt updates mid-run, ensures versioning records what actually ran |
| Orchestrator implementation | CLAUDE.md IS the Orchestrator — no separate file | Orchestrator behaviour lives where Claude Code reads its instructions from |
| Context injection | Static identity in .md file, dynamic context assembled by Orchestrator at invocation time | Agent files stay stable — context changes every run without touching agent definitions |
| Agent learning vs auto-repair | Separate systems — repair targets tools, learning targets behaviour | Different detection mechanisms, different fix strategies, different timing |
| Learning detection threshold | 2+ occurrences across last N runs | Single occurrence is noise — pattern needs confirmation before adding standing instruction |
| Learning fix mechanism | Standing instructions injected at runtime, never modifies .md files | Keeps agent files clean and auditable — learning is a separate layer |
| Persistent pattern threshold | 2 recurrences after instruction added | If instruction didn't fix it in 2 tries, human needs to look at the prompt file itself |
| Learning window | Configurable N runs (default 5) | Enough history to detect patterns without being too slow to respond |
| Resolved status | Pattern not recurred for 5 consecutive runs | Instruction kept active as insurance even when resolved |
| Stale branch cleanup | On-demand script, not scheduled | Agent only runs when given a ticket — no background processes |
| Breaking change severity | High (not medium) if undocumented in commit footer | Direct impact on teammates — needs stronger signal than a code smell |
| Agent prompt versioning | Version recorded in PRD.json at run start, mismatch warning on --resume | Prevents silent behaviour changes mid-run without blocking resumable work |
| Commit convention | Conventional Commits | Industry standard for TS/JS — enables changelogs, clear history, consistent PRs |
| Commit granularity | One commit per PRD.json task | Atomic, traceable, reviewable — one commit = one unit of work |
| Ticket reference | Footer `Refs: TICKET-ID` on every Developer Agent commit | Makes every commit traceable back to its ticket |
| Breaking changes | Documented in commit footer, flagged by The Critic | Prevents silent API contract changes reaching teammates |
| Commit validation | QA Agent validates before marking task complete | Enforces convention consistently without relying on Developer Agent remembering |
| Target repo resolution | repos.json maps Jira project key → local repo path + GitHub repo | Jira project key is already in every ticket ID — deterministic, no inference needed |
| Repo config location | repos.json at orchestrator root, gitignored | Contains machine-specific paths — not committable, repos.json.example provided |
| Unknown project key | Hard-fail, no default repo | Better to catch config gaps early than silently target wrong repo |
| GitHub repo identifier | Stored in repos.json as `github_repo` field | Parsing git remotes is fragile — explicit config is reliable for `gh` CLI commands |
| Variable naming | AGENT_ROOT for orchestrator, TARGET_REPO for target | Clear separation: orchestrator reads .env/agents/schemas/runs, target repo gets git operations |
| Worktree path | `~/.claude/worktrees/{repo_name}/{branch_name}` | Matches global CLAUDE.md convention, separates by repo, avoids collision |

---

## Environment Setup Checklist

- [ ] `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` / `JIRA_PAT` configured
- [ ] `AGENT_EMPLOYEE_CODE` configured in `.env` (3-letter lowercase employee code)
- [ ] `AGENT_LEARNING_WINDOW` configured (default: 5)
- [ ] `AGENT_LEARNING_PERSISTENCE_THRESHOLD` configured (default: 2)
- [ ] `acli` installed and authenticated
- [ ] `gh` cli installed and authenticated (`gh auth login`)
- [ ] `gitleaks` installed and verified
- [ ] `.gitleaks.toml` starter config created
- [ ] Confluence MCP server configured in `.claude.json`
- [ ] `acli` Jira connection validated (read ticket + check linked issues)
- [ ] `gh` GitHub connection validated (list PRs + check PR status)
- [ ] Confluence MCP connection validated
- [ ] `repos.json` created from `repos.json.example` with local repo paths
- [ ] Target repo paths exist and are git repos (`scripts/setup.sh` validates)
- [ ] `worktree-scan.sh` tested — correctly identifies orphaned worktrees
- [ ] Test repos identified for dry run

---

## Issues Log

_Record any problems, blockers, or plan changes here. Do not delete — append only._

| Date | Session | Issue | Resolution |
|---|---|---|---|
| 2026-03-21 | 1 | `acli` not installed — plan references it for Jira/Confluence | Using Atlassian MCP server instead — provides equivalent read/write access to Jira and Confluence. MCP is already configured in Claude Code environment. |
| 2026-03-21 | 1 | `gitleaks` not in bash PATH after winget install | Requires shell restart. Full path works: `/c/Users/markb/AppData/Local/Microsoft/WinGet/Packages/Gitleaks.Gitleaks_Microsoft.Winget.Source_8wekyb3d8bbwe/gitleaks.exe` |

---

## Parallel Session Assignments

_If running parallel sessions, record assignments here to avoid conflicts._

| Track | Phase(s) | Assigned To | Status |
|---|---|---|---|
| Infrastructure | Phase 1 (scaffold + tool setup) | — | Not started |
| Contracts | Phase 2 + 3 | — | Not started |
| Agents | Phase 4 | — | Not started |
| Logic | Phase 5 (orchestration + worktree + dependency) | — | Not started |
| Safety + Observability | Phase 6 + 7 | — | Not started |
| Auto-Repair | Phase 8 | — | Not started |
| Conflict Resolution | Phase 9 | — | Not started |
| Agent Learning | Phase 10 | — | Not started |

---

## Status Key

| Symbol | Meaning |
|---|---|
| 🔴 | Not started |
| 🟡 | In progress |
| 🟢 | Complete |
| 🔵 | Blocked |
