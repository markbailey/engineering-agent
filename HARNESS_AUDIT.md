# Engineering Agent Harness Audit

**Date:** 2026-03-26
**Scope:** Full system review of the axomic-engineering multi-agent orchestrator
**System version:** All agents at v1.0.0 (released 2026-03-21)

---

## Executive Summary

The Engineering Agent is a well-architected autonomous system that orchestrates 10 specialized agents through a 13-stage workflow (Jira ticket to merged PR). It has strong safety foundations, structured inter-agent contracts via JSON schemas, and two adaptive learning systems. The system is production-capable but has gaps in concurrency safety, cross-platform portability, error recovery granularity, and observability depth that should be addressed before scaling beyond single-operator use.

---

## What Is Good

### 1. Agent Decomposition Is Clean

Each of the 10 agents has a single, well-defined responsibility with no overlap:

| Agent | Boundary |
|---|---|
| Jira Agent | Jira API only — never interprets requirements |
| Planner | Translates parsed ticket to PRD.json — never touches code |
| Developer | Implements one task, one commit — never reviews or plans |
| QA | Verifies, auto-fixes lint/format — never writes application code |
| The Critic | Reviews against spec — never implements fixes |
| Conflict Resolution | Merges + resolves — never writes new features |
| Secret Scanner | Scans diff — hard blocks, never auto-remediates |
| PR Agent | Opens/updates PRs — never modifies code |
| PR Monitor | Watches for events — never takes action itself |
| Run Analyst | Detects patterns — never modifies agent prompts directly |

This separation means each agent's context window stays focused, reducing drift. The orchestrator (CLAUDE.md) is the only entity that routes between agents.

### 2. JSON Schema Contracts Are Rigorous

All 8 schemas enforce strict typing, required fields, and enum constraints on inter-agent communication. Highlights:

- **prd.schema.json**: Branch name regex `^[a-z0-9]+_[a-z]+-[0-9]+_.+_(feature|bug|defect|debt|chore)$` prevents free-form naming
- **secrets.schema.json**: `secret_value` is a `const` of `"[REDACTED — never logged]"` — schema-level prevention of secret leakage
- **review.schema.json**: `proceed_to_pr` is gated by verdict — structurally impossible to open a PR without Critic approval
- **conflict.schema.json**: Covers all 5 conflict types (both_modified, modify_delete, add_add, rename_rename, rename_delete) with per-file resolution tracking

The schemas serve as both documentation and runtime contracts. This is a strong design choice.

### 3. Safety Guardrails Are Multi-Layered

The system implements defense-in-depth:

| Layer | Mechanism | Example |
|---|---|---|
| Branch protection | `validate-branch-name.sh` | Rejects pushes to main/master/staging |
| Secret scanning | `run-secret-scan.sh` | Hard block on any gitleaks finding |
| Loop limits | `check-loop-limit.sh` | Max 3 Critic rounds, then escalate |
| Retry limits | `check-retry-limit.sh` | Max 2 retries per task |
| Team conflict | `check-team-conflict.sh` | Detects human work on same ticket |
| Commit validation | `validate-commit-msg.sh` | Enforces Conventional Commits format |
| Regression guard | `regression-guard.sh` | 3-pass validation after every merge |
| Orphan detection | `orphan-check.sh` | Catches broken imports, dead exports |
| PR size check | `check-pr-size.sh` | Pauses for human approval above threshold |

The escalation-over-guessing principle is consistently applied. Agents report `blocked` or `escalated` status rather than making assumptions.

### 4. Two Adaptive Learning Systems

**Auto-Repair** (tool/environment failures):
- Cross-run knowledge base (`REPAIR_KNOWLEDGE.json`) with confidence scoring
- Evidence-based promotion: low (1 success) -> medium (2) -> high (3+)
- Failed alternatives permanently blocked — prevents infinite retry of dead-end fixes
- Per-ticket failure tracking prevents runaway loops

**Agent Learning** (behavioral patterns):
- Detects recurring mistakes across last N runs
- Injects standing instructions at runtime without modifying static agent prompts
- Lifecycle: active -> resolved (5 clean runs) -> persistent (2+ recurrences after instruction)
- Persistent patterns escalate to human for deeper prompt revision

This two-system split (tool failures vs behavioral mistakes) is a good separation of concerns.

### 5. Resumability Is First-Class

- PRD.json tracks task-level status (pending/in_progress/verified/complete)
- Worktree detection on startup enables seamless resume
- Agent version recording enables drift detection across sessions
- All artifacts persisted to `runs/{ticket_id}/` for post-mortem
- `--resume` flag explicitly supported

### 6. Observability Is Strong

- JSONL structured logging with timestamps, levels, categories
- Real-time web dashboard with SSE push (zero dependencies)
- Terminal notifications via `notify.sh` for key events
- Run summaries with error/warning counts
- Per-ticket artifact archiving

### 7. The Critic Is Comprehensive

The internal review covers 11 dimensions: requirements coverage, PRD adherence, security, performance, error handling, architecture, naming, complexity, test quality, breaking changes, and conflict resolution quality. The severity system (critical > high > medium > low) with clear gating rules is well-calibrated.

---

## What Is Bad

### 1. No Concurrency Safety

**Problem:** Multiple scripts read/write the same JSON files (`loops.json`, `retries.json`, `PRD.json`, `AGENT_LEARNING.json`) without locking. If two agents or two runs execute concurrently against the same ticket or shared knowledge base, data corruption is possible.

**Impact:** Low risk at current scale (single operator, one ticket at a time), but blocks scaling to parallel ticket execution.

**Fix:** Implement file-level advisory locking (flock) on all JSON read-modify-write operations, or move state to a lightweight DB (SQLite).

### 2. Hardcoded Node.js/TypeScript Toolchain

**Problem:** QA Agent, regression guard, and worktree init assume:
- `npm install` for dependencies
- `npx tsc --noEmit` for compilation
- `prettier --write` and `eslint --fix` for auto-fix
- `npm test` for test execution

Non-Node repos (Go, Python, Rust, Java) cannot use this system without rewriting QA logic.

**Impact:** Limits the system to JavaScript/TypeScript projects only.

**Fix:** Abstract toolchain commands into `repos.json` per-repo config:
```json
{
  "PROJ": {
    "install": "npm install",
    "typecheck": "npx tsc --noEmit",
    "lint_fix": "npx eslint --fix . && npx prettier --write .",
    "test": "npm test",
    "integration_test": "npm run test:integration"
  }
}
```

### 3. Orphan Check Is Grep-Based and Fragile

**Problem:** `orphan-check.sh` uses `grep -rl` to detect deleted callsites, renamed references, dead exports, and disconnected integrations. This is:
- Slow on large codebases (linear scan)
- Prone to false positives (string matches in comments, strings, unrelated code)
- Already documented as problematic in `REPAIR_KNOWLEDGE.json` (repair-2: scans full merge diff, flags unrelated base changes)

**Impact:** False positives cause unnecessary escalations. False negatives let broken imports through.

**Fix:** Use AST-aware tooling (e.g., TypeScript's `findAllReferences`, `ts-morph`, or language server queries) instead of grep for import/export analysis. Fall back to grep only for non-TS files.

### 4. No Timeout Mechanism on Any Operation

**Problem:** No script or agent invocation has a hard timeout. A hanging `npm test`, a slow `git merge` on a large repo, or an unresponsive Jira API will block the entire workflow indefinitely.

**Impact:** Silent hangs with no recovery. Operator discovers hours later.

**Fix:** Wrap all external commands in a timeout wrapper:
```bash
timeout ${AGENT_COMMAND_TIMEOUT:-300} npm test
```
Add a watchdog to the orchestrator that kills stalled subagents after a configurable threshold.

### 5. Schema Validation Is Incomplete

**Problem:** `validate-schemas.js` only checks required fields and `additionalProperties: false`. It does not validate:
- Type correctness (string vs number vs boolean)
- Pattern matching (regex constraints like branch name format)
- Enum values
- Nested object structures

**Impact:** A malformed PRD.json with `"overall_status": "banana"` passes validation.

**Fix:** Replace custom validator with `ajv` (JSON Schema validator with full draft-07 support). Single dependency, covers all schema features.

### 6. No Rollback or Revert Mechanism

**Problem:** If a merged PR introduces a regression, the system has no built-in way to revert. The post-merge stage only does cleanup (worktree removal, Jira transition, artifact archiving).

**Impact:** Human must manually create a revert PR or new fix ticket.

**Fix:** Add a `--revert TICKET-ID` mode that:
1. Looks up the merged PR from archived artifacts
2. Creates `git revert` commit
3. Opens revert PR with context from original ticket

### 7. Error Output Inconsistency

**Problem:** Some scripts exit with structured JSON, others with plain text error messages. The orchestrator must handle both formats.

**Impact:** Parsing failures when scripts are composed. Harder to aggregate errors in run.log.

**Fix:** Standardize all script output to JSON. Even error cases should output `{"error": "message", "exit_code": N}`.

### 8. Flaky Test Detection Is Subjective

**Problem:** PR Monitor's flaky test detection relies on the agent judging whether a failed test is "unrelated to changed files." This is a subjective determination that LLMs are not reliably good at.

**Impact:** Real failures may be dismissed as flaky, or flaky tests may block PRs unnecessarily.

**Fix:** Implement a flaky test registry (list of known-flaky test names/patterns). Tests on the registry get auto-retried once before failing. Tests not on the registry are always treated as real failures.

---

## Where Things Can Be Improved

### 1. Add a Pre-Flight Validation Stage

**Current state:** Startup goes straight into Jira validation. If `repos.json` is misconfigured, the target repo doesn't exist, or tools are missing, the run fails mid-stream.

**Improvement:** Add a `preflight` stage before ticket intake:
- Verify all tools installed (gh, gitleaks, node, npm, git)
- Verify target repo exists at configured path
- Verify git remote is accessible
- Verify Jira/GitHub authentication
- Verify .env has all required variables
- Output: structured preflight report (pass/fail per check)

`setup.sh` partially does this but isn't integrated into the run workflow.

### 2. Per-Repo Toolchain Abstraction

**Current state:** QA commands are hardcoded for Node.js.

**Improvement:** Extend `repos.json` with a `toolchain` section per repo:
```json
{
  "PROJ": {
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
Agents reference `toolchain.test` instead of hardcoding `npm test`. Null values skip that step.

### 3. Structured Escalation Triage

**Current state:** Escalations are terminal — the workflow stops and waits for human intervention. All escalations look the same to the operator.

**Improvement:** Categorize escalations with severity and suggested actions:

| Category | Example | Suggested Action |
|---|---|---|
| `blocked_dependency` | Upstream ticket not done | Wait or re-prioritize |
| `test_failure` | Tests fail after 2 retries | Debug test output |
| `merge_conflict` | Disconnected integration | Manual merge required |
| `review_stall` | 3 Critic rounds, issues remain | Scope reduction |
| `secret_detected` | API key in diff | Remove + rotate credential |
| `infra_failure` | npm install fails after repair | Environment issue |
| `contradictory_feedback` | Reviewer approves then blocks | Clarify with reviewer |

Add an `escalation.schema.json` with category, severity, context, and suggested_action fields.

### 4. Dry-Run Mode Should Be Deeper

**Current state:** `--dry-run` is mentioned in README but the implementation depth is unclear. It appears to stop at planning.

**Improvement:** Dry-run should simulate the full pipeline:
- Parse ticket (real)
- Generate PRD.json (real)
- Create worktree (real)
- Implement tasks (real code changes)
- Run QA (real)
- Run Critic review (real)
- **Stop before**: secret scan, PR creation, Jira transitions
- Output: full artifact set minus PR/Jira side-effects

This lets operators validate the entire pipeline before committing to external side-effects.

### 5. Add Metrics Collection

**Current state:** Run.log captures events but there's no aggregated metrics view.

**Improvement:** Track and surface:
- **Cycle time**: ticket intake to PR merged (wall clock)
- **Stage durations**: time spent in each workflow stage
- **Retry rates**: per-agent, per-operation
- **Critic round distribution**: how many rounds typically needed
- **Auto-fix rate**: % of QA runs that auto-fix resolves issues
- **Escalation rate**: % of runs that escalate (by category)
- **Learning effectiveness**: recurrence rate before/after standing instructions

Store as `runs/{ticket_id}/metrics.json`. Aggregate across runs in dashboard.

### 6. Improve Conflict Resolution Intelligence

**Current state:** Orphan check uses grep. Regression guard pass 2 (diff analysis) is vaguely defined.

**Improvement:**
- Replace grep with `ts-morph` or TypeScript compiler API for import/export analysis
- Make diff analysis concrete: extract all exports/imports changed in base, check if feature branch references any of them
- Add a "conflict preview" step before attempting merge: `git merge --no-commit --no-ff` to inspect conflicts without committing

### 7. Add Agent Self-Testing

**Current state:** Agent prompts are versioned in CHANGELOG.md but never tested against known scenarios.

**Improvement:** Create a `tests/` directory with golden-file tests:
- Input: known ticket JSON + known repo state
- Expected: specific PRD.json structure, specific review findings, specific PR description
- Run: invoke each agent in isolation against test fixtures
- Assert: output matches expected schema and key content

This catches prompt regressions when agent `.md` files are modified.

### 8. Cross-Platform Portability

**Current state:** Scripts use bash 4+ features, hardcode Windows gitleaks path, and use `grep -P` (not available on macOS).

**Improvement:**
- Replace `grep -P` with `grep -E` globally (already in REPAIR_KNOWLEDGE)
- Remove hardcoded Windows paths — use `which gitleaks || command -v gitleaks`
- Test all scripts on macOS + Linux (CI matrix)
- Document minimum bash version requirement

### 9. Add a Cancel/Abort Stage

**Current state:** `--stop` and `--pause` exist but the cleanup behavior is unclear. Interrupted runs may leave worktrees, partial commits, and draft PRs.

**Improvement:** Implement explicit abort cleanup:
- Close draft PR (if opened)
- Remove worktree (preserve artifacts)
- Transition Jira ticket back to original status
- Log abort reason in run.log
- Mark PRD.json `overall_status: "aborted"`

### 10. Dependency Chain Visualization

**Current state:** Max 1 level of blocked-by dependencies. No way to visualize the dependency graph.

**Improvement:** Add `scripts/dependency-graph.sh` that:
- Walks Jira linked issues (up to depth 3)
- Outputs DOT format or ASCII art
- Highlights which dependencies are resolved/blocked/in-progress
- Integrate into dashboard as a "Dependencies" tab

### 11. Standing Instruction Effectiveness Tracking

**Current state:** Agent Learning tracks occurrences and recurrences, but doesn't measure whether a standing instruction actually changed agent behavior.

**Improvement:** Add to each learning entry:
- `runs_with_instruction`: count of runs where instruction was injected
- `runs_without_recurrence_after_instruction`: count of clean runs post-instruction
- `effectiveness_score`: `runs_without_recurrence / runs_with_instruction`
- Auto-dismiss instructions with effectiveness < 0.5 after 10+ runs (they're not helping)

### 12. Rate Limit Awareness

**Current state:** `retry-with-backoff.sh` retries blindly. No HTTP status code parsing.

**Improvement:**
- Parse HTTP 429 responses for `Retry-After` header
- Respect rate limit windows from GitHub API (`X-RateLimit-Remaining`)
- Add jitter to backoff: `delay * (1 + random(0, 0.3))` to prevent thundering herd
- Surface rate limit events in dashboard

### 13. Multi-Ticket Parallel Execution

**Current state:** System processes one ticket at a time. No queue or scheduler.

**Improvement:** Add a lightweight job queue:
- `queue.json` with ordered ticket list
- Worker picks next ticket when current completes
- Shared resource locking (repos, worktree paths)
- Dashboard shows queue position and ETA
- Configurable parallelism (default 1, max N)

---

## Priority Matrix

| Improvement | Impact | Effort | Priority |
|---|---|---|---|
| Pre-flight validation | High | Low | **P0** |
| Operation timeouts | High | Low | **P0** |
| Per-repo toolchain abstraction | High | Medium | **P1** |
| Schema validation (use ajv) | Medium | Low | **P1** |
| Standardize error output to JSON | Medium | Low | **P1** |
| Structured escalation categories | Medium | Low | **P1** |
| Cross-platform portability fixes | Medium | Low | **P1** |
| Cancel/abort cleanup | Medium | Medium | **P1** |
| Flaky test registry | Medium | Medium | **P2** |
| AST-aware orphan check | High | High | **P2** |
| Metrics collection | Medium | Medium | **P2** |
| Dry-run depth | Medium | Medium | **P2** |
| Agent self-testing | High | High | **P2** |
| Concurrency safety (flock/SQLite) | Low now, High at scale | Medium | **P2** |
| Rate limit awareness | Low | Low | **P3** |
| Standing instruction effectiveness | Low | Low | **P3** |
| Dependency graph visualization | Low | Medium | **P3** |
| Rollback/revert mode | Low | Medium | **P3** |
| Multi-ticket parallel execution | Low now | High | **P3** |

---

## Conclusion

This is a sophisticated, well-thought-out system. The agent decomposition, schema contracts, safety guardrails, and adaptive learning systems are genuinely strong. The main weaknesses cluster around: (1) hardcoded toolchain assumptions limiting it to Node.js projects, (2) fragile text-based code analysis where AST tools would be more reliable, (3) missing operational safeguards (timeouts, pre-flight, abort cleanup), and (4) incomplete schema validation. None of these are architectural flaws — they're gaps that can be filled incrementally without restructuring the system.
