# Engineering Agent — Master Project Plan

## Project Overview

An autonomous multi-agent engineering system built on Claude Code that reads Jira tickets, implements code changes, performs internal review, opens PRs, and monitors them through to merge-ready state — with human approval required only for merging to protected branches.

---

## System Architecture

### Agent Roster

| # | Agent | Persona | Primary Responsibility |
|---|---|---|---|
| 1 | **Orchestrator** | Calm, decisive, minimal | Workflow state management, agent delegation, escalation to human |
| 2 | **Jira Agent** | Methodical, precise | Read/parse tickets, update status, add comments |
| 3 | **Planner Agent** | Analytical, thorough | Generate PRD.json, map requirements to tasks with dependencies |
| 4 | **Developer Agent** | Focused, pragmatic | Implement tasks from PRD.json one at a time |
| 5 | **QA Agent** | Rigorous, systematic | Auto-fix (prettier, eslint --fix), then verify: tsc, lint, formatting, unit tests, integration tests |
| 6 | **The Critic** | Strict, adversarial, uncompromising | Internal code review with full context, generate REVIEW.json |
| 7 | **PR Agent** | Efficient, professional | Open PR as draft (always), write description, link Jira, push updates as draft |
| 8 | **PR Monitor** | Measured, diplomatic | Monitor CI + GitHub comments, generate FEEDBACK.json, respond to reviewers |
| 9 | **Conflict Resolution Agent** | Methodical, cautious | Merge base into feature branch, resolve conflicts file by file, never lose intentional changes |
| 10 | **Run Analyst** | Analytical, pattern-focused | Post-run pattern analysis across artefacts — detects recurring agent behavioural mistakes, generates standing instructions for AGENT_LEARNING.json |

### Core Artefacts

| File | Owner | Purpose |
|---|---|---|
| `PRD.json` | Planner Agent | Source of truth — requirements, tasks, dependencies, status |
| `REVIEW.json` | The Critic | Internal code review findings, severity, requirements coverage |
| `FEEDBACK.json` | PR Monitor | External PR feedback and CI failures to be resolved |

| `REPAIR_KNOWLEDGE.json` | Auto-Repair System | Persistent log of failed tool approaches and proven alternatives per agent + operation |
| `AGENT_LEARNING.json` | Agent Learning System | Persistent log of recurring behavioural mistakes and standing instructions injected at runtime |
| `CONFLICT.json` | Conflict Resolution Agent | Record of conflicted files, resolution strategy, and merge outcome per run |
| `SECRETS.json` | Secret Scanner | Record of detected secrets in diff — hard blocks PR until human remediates |

---

## Auto-Repair System

### Overview

If an agent repeatedly fails using a particular approach, the system detects the pattern, switches to an alternative method within the same run, and persists that knowledge so future runs never attempt the failed approach again.

Two layers:

**Layer 1 — In-run repair:** Agent fails → retry with same approach once → if still failing, consult `REPAIR_KNOWLEDGE.json` for a known alternative → try alternative → if no known alternative exists, attempt a different strategy and record the outcome.

**Layer 2 — Cross-run learning:** Any successful alternative is written back to `REPAIR_KNOWLEDGE.json` so all future runs start with that knowledge baked in.

### Failure Detection

Each agent tracks its own attempts per operation. A failure pattern is triggered when:
- Same operation fails **2 times in a row** with the same approach
- The error type is consistent (not a transient/flaky failure)

### REPAIR_KNOWLEDGE.json Schema

```json
{
  "version": 1,
  "last_updated": "2024-01-15T10:30:00Z",
  "entries": [
    {
      "id": "repair-001",
      "agent": "developer-agent",
      "operation": "install_dependencies",
      "failed_approach": "npm install",
      "failure_reason": "peer dependency conflict",
      "error_pattern": "ERESOLVE unable to resolve dependency tree",
      "successful_alternative": "npm install --legacy-peer-deps",
      "confidence": "high",
      "occurrences": 3,
      "last_seen": "2024-01-15T10:30:00Z"
    },
    {
      "id": "repair-002",
      "agent": "qa-agent",
      "operation": "run_integration_tests",
      "failed_approach": "npm run test:integration",
      "failure_reason": "port already in use",
      "error_pattern": "EADDRINUSE",
      "successful_alternative": "PORT=3001 npm run test:integration",
      "confidence": "high",
      "occurrences": 1,
      "last_seen": "2024-01-14T09:00:00Z"
    }
  ]
}
```

**Confidence levels:**

| Level | Meaning |
|---|---|
| `high` | Alternative has succeeded 3+ times, use it first |
| `medium` | Alternative has succeeded 1-2 times, try it before escalating |
| `low` | Alternative succeeded once, treat as experimental |
| `failed` | Alternative also failed — escalate to human |

### In-Run Repair Loop

```
Agent attempts operation
  → Failure detected
    → Retry once with same approach (transient error check)
      → Still failing:
        → Check REPAIR_KNOWLEDGE.json for matching agent + operation + error_pattern
          → Known alternative exists (confidence: high/medium):
              → Try alternative
                → Success: record occurrence, continue
                → Failure: mark confidence "failed", escalate to human
          → No known alternative:
              → Agent attempts a different strategy (self-reasoning)
                → Success: write new entry to REPAIR_KNOWLEDGE.json (confidence: low)
                → Failure after 2 alternative attempts: escalate to human
```

### Cross-Run Learning Rules

- `REPAIR_KNOWLEDGE.json` lives at the project root — shared across all runs and all tickets
- Every successful alternative increments `occurrences` and updates `last_updated`
- After 3 successful occurrences, confidence promotes to `high`
- Entries with `confidence: failed` are never retried — agent skips straight to escalation
- Agents read `REPAIR_KNOWLEDGE.json` at startup so they begin each run already informed
- Conflicting entries (same operation, different successful alternatives) keep both — agent tries highest confidence first

### Scope of Auto-Repair

Auto-repair applies to **tool and environment failures**, not logic or code quality issues:

| In scope | Out of scope |
|---|---|
| CLI command failures (`acli`, `gh`, `npm`, test runners) | Code the Developer Agent writes being wrong |
| Dependency installation issues | The Critic finding issues with implementation |
| Port conflicts, environment issues | PR reviewer requesting changes |
| Test runner configuration issues | Jira ticket being ambiguous |
| `gh` CLI auth or rate limit retries | Acceptance criteria not being met |

---

## Agent Learning System

### Overview

The auto-repair system handles **tool and environment failures** — wrong commands, dependency conflicts, transient errors. The agent learning system handles a different class of problem: **recurring behavioural mistakes** — an agent that repeatedly makes the same type of logical error, omission, or quality gap across multiple runs.

These are detected by the **Run Analyst** at the end of every completed run. Patterns are written to `AGENT_LEARNING.json`. On every subsequent run startup, the Orchestrator reads this file and appends relevant standing instructions to each agent's context at invocation time — without modifying the static `.md` files.

### Key Distinction from Auto-Repair

| | Auto-Repair | Agent Learning |
|---|---|---|
| **Targets** | Tool and environment failures | Recurring agent behavioural mistakes |
| **Detection** | Exit codes, error output, within a single run | Patterns across multiple runs' artefacts |
| **Fix mechanism** | Try an alternative command | Inject a standing instruction into future prompts |
| **Timing** | In-run, immediate | Cross-run, end-of-run analysis |
| **Modifies agent files** | No | No — instructions injected at runtime only |

### Run Analyst

The Run Analyst is invoked by the Orchestrator at the end of every completed run (after merge confirmed or after escalation). It analyses the last **N runs** (configurable, default 5) by reading archived artefacts from `/runs/`:

**What it looks for:**

| Source | Pattern |
|---|---|
| `REVIEW.json` | Same issue type flagged by The Critic at `high` or above, 2+ times across recent runs |
| `FEEDBACK.json` | Same feedback category requested by PR reviewers across multiple tickets |
| `run.log` | Same QA failure type recurring (same test category, same lint rule) |
| `PRD.json` | Planner Agent consistently missing the same category of task (e.g. migrations, tests for edge cases) |
| `REVIEW.json prd_adherence` | Developer Agent consistently deviating from PRD in the same way |

**Detection threshold:** A pattern is confirmed when the same issue appears in **2 or more** of the last N runs for the same agent. The Run Analyst does not raise patterns from a single occurrence — that is noise.

### AGENT_LEARNING.json Schema

```json
{
  "version": 1,
  "last_updated": "2024-01-15T10:30:00Z",
  "entries": [
    {
      "id": "learn-001",
      "agent": "developer-agent",
      "pattern_description": "Missing error handling on async operations",
      "detection_source": "the-critic REVIEW.json — 'missing error handling' flagged at high severity on PROJ-101, PROJ-118, PROJ-134",
      "standing_instruction": "Always wrap async operations in try/catch blocks. Never leave a Promise without an error handling path. This applies to all fetch calls, database queries, and file operations.",
      "first_detected": "2024-01-10T09:00:00Z",
      "last_seen": "2024-01-15T10:30:00Z",
      "occurrences": 3,
      "runs_since_instruction": 0,
      "recurrences_after_instruction": 0,
      "status": "active"
    },
    {
      "id": "learn-002",
      "agent": "planner-agent",
      "pattern_description": "Database schema changes missing migration tasks",
      "detection_source": "the-critic REVIEW.json — missing migration flagged on PROJ-089, PROJ-112",
      "standing_instruction": "When any task involves a database schema change, always include a dedicated migration task immediately before it. Migration tasks must include both up and down steps.",
      "first_detected": "2024-01-08T14:00:00Z",
      "last_seen": "2024-01-12T11:00:00Z",
      "occurrences": 2,
      "runs_since_instruction": 4,
      "recurrences_after_instruction": 0,
      "status": "resolved"
    }
  ]
}
```

**Entry statuses:**

| Status | Meaning |
|---|---|
| `active` | Standing instruction is being injected. Pattern still being monitored. |
| `resolved` | Pattern has not recurred for 5+ runs since instruction added. Instruction still injected but flagged as likely fixed. |
| `persistent` | Pattern recurred 2+ times after instruction was added. Escalate to human — prompt needs a deeper fix. |

### Instruction Injection

At run startup, the Orchestrator reads `AGENT_LEARNING.json` and for each `active` or `resolved` entry, appends the `standing_instruction` to the relevant agent's context package when invoking via `Task`:

```
Orchestrator invokes Developer Agent:
  → reads developer-agent.md (system prompt)
  → reads AGENT_LEARNING.json
  → filters entries where agent == "developer-agent" and status in ["active", "resolved"]
  → appends to context package:

    STANDING INSTRUCTIONS (learned from previous runs):
    1. Always wrap async operations in try/catch blocks. Never leave a Promise
       without an error handling path. This applies to all fetch calls, database
       queries, and file operations.

  → calls Task(system_prompt=developer-agent.md, input=task_context + standing_instructions)
```

Standing instructions are clearly labelled in the context so the agent knows they are persistent rules, not one-off instructions.

### Escalation: Persistent Patterns

If a pattern recurs **2 or more times after a standing instruction has been added**, the Run Analyst marks the entry as `persistent` and escalates to the human with a clear report:

```
[AGENT LEARNING] Persistent pattern detected in developer-agent:
Pattern: Missing error handling on async operations
Standing instruction has been active for 6 runs.
Pattern recurred on: PROJ-201, PROJ-215
Action required: The agent's .md file may need a deeper structural change to address this.
See AGENT_LEARNING.json entry learn-001 for full history.
```

This is the signal that runtime injection is not enough — the static prompt file needs to be revised.

### Resolution

When a pattern has not recurred for **5 consecutive runs**, the Run Analyst marks it `resolved`. The standing instruction continues to be injected (cheap insurance) but is no longer flagged as an active problem.

Human reviewers can manually mark entries as `resolved` or `dismissed` at any time via direct edit of `AGENT_LEARNING.json`.

### Run Analyst Scope

The Run Analyst only analyses **completed runs** — runs that reached at least the PR opened stage. Abandoned or interrupted runs are excluded from pattern analysis to avoid false signals from incomplete work.

It analyses a **rolling window** of the last N completed runs (default: 5, configurable via `AGENT_LEARNING_WINDOW` env var).

---

### Strategy

No rebasing under any circumstances. When the feature branch falls behind the base branch, the base branch is merged into the feature branch. Conflicts are resolved file by file by the Conflict Resolution Agent, with two mandatory post-resolution checks: **regression guard** and **orphan prevention**.

### When Conflict Resolution Runs

- Before The Critic's internal review (after all tasks complete)
- After any code changes by the Developer Agent (review rounds or feedback rounds)
- When PR Monitor detects the base branch has received new commits while the PR is open

### Conflict Resolution Loop

```
Conflict Resolution Agent: merge base branch into feature branch
  → git merge origin/main --no-ff
    → No conflicts:
        → Run regression guard
        → Run orphan check
        → If clean: continue workflow
        → If issues found: treat as post-merge issues (see below)
    → Conflicts detected:
        → For each conflicted file:
            → Load: our changes, their changes, common ancestor
            → Load: PRD.json for intent context
            → Resolve: preserve intentional feature changes, integrate base changes
            → Mark resolved, stage file
        → Run TypeScript compilation check (tsc --noEmit)
            → Compilation errors: fix before proceeding
        → Run regression guard
        → Run orphan check
        → If clean: commit merge, push, continue workflow
        → If regression or orphan found: attempt fix (one round)
            → Re-run regression guard + orphan check
            → If clean: commit merge, push, continue
            → If still failing: ESCALATE to human with full CONFLICT.json
        → If unresolvable conflict markers remain: ESCALATE immediately
```

### Regression Guard

The regression guard runs after every merge (conflicted or clean) and answers one question: **does the merged state break anything that was working before?**

It does this in three passes:

**Pass 1 — Compilation:** `tsc --noEmit` must pass. A type error after merge means something our code depended on has changed shape on the base branch — a renamed export, changed function signature, removed interface member, etc.

**Pass 2 — Diff analysis:** The agent diffs the base branch changes and identifies anything that could affect our code — deleted exports, renamed functions, changed interfaces, moved files, updated dependencies. It then cross-references these against our feature branch code to flag any direct dependencies on changed items.

**Pass 3 — Full QA suite:** Auto-fix → tsc → lint → formatting check → unit → integration. A pass here without a pass in 1 and 2 is not sufficient — compilation and diff analysis must also be clean.

If any pass fails, the Conflict Resolution Agent attempts to fix the issue before escalating. It does not hand off to the Developer Agent — the fix must be limited to reconciling the merge, not extending the feature.

### Orphan Prevention

Orphaned code is code that exists in the merged state but is no longer connected to anything — typically caused by the base branch deleting or renaming a callsite, consumer, or integration point that our feature branch added code to serve.

The orphan check runs after conflict resolution and covers:

**Deleted callsites** — if base branch removed a function call, route handler, event listener, or import that our feature was providing an implementation for, that implementation is now orphaned. The agent must either remove it cleanly or escalate if removal would affect the PRD.json scope.

**Renamed references** — if base branch renamed something our feature branch references, all references must be updated. This is not optional — a renamed reference that compiles (e.g. via `any` types) but points to the wrong thing is a silent regression.

**Dead exports** — if our feature branch added an exported function or type that was intended to be consumed by something in the base branch, and the base branch has since changed that integration point, the export may now be dead. Flag these for The Critic to review.

**Disconnected integrations** — if our feature adds middleware, a plugin, a hook, or a service registration, and the base branch has restructured the integration layer it was meant to plug into, the integration must be verified as still connected.

### Orphan Resolution Rules

- **Deleted callsites:** Remove the orphaned implementation cleanly. Update PRD.json to note the removal. If removing it conflicts with an acceptance criterion, escalate — the ticket may need to be re-evaluated.
- **Renamed references:** Update all references. Run compilation to verify. This is always safe to fix autonomously.
- **Dead exports:** Flag in CONFLICT.json as `orphan_risk`. The Critic is informed and reviews these explicitly as part of its code review pass.
- **Disconnected integrations:** Do not attempt to silently reconnect. Escalate to human — the integration strategy may have fundamentally changed.

### Updated CONFLICT.json Schema

```json
{
  "ticket": "PROJ-123",
  "base_branch": "main",
  "feature_branch": "abc_proj-123_add-auth-middleware_feature",
  "base_commit": "abc1234",
  "had_conflicts": true,
  "conflicted_files": [
    {
      "file": "src/middleware/auth.ts",
      "conflict_type": "both_modified",
      "resolution": "feature_priority",
      "status": "resolved"
    }
  ],
  "regression_guard": {
    "compilation": "pass",
    "diff_analysis": "pass",
    "test_suite": "pass",
    "issues_found": []
  },
  "orphan_check": {
    "status": "pass",
    "deleted_callsites": [],
    "renamed_references": [
      {
        "old_name": "validateToken",
        "new_name": "verifyToken",
        "files_updated": ["src/middleware/auth.ts"],
        "status": "resolved"
      }
    ],
    "dead_exports": [],
    "disconnected_integrations": []
  },
  "unresolvable_files": [],
  "escalation_reason": null,
  "overall_status": "resolved",
  "merge_commit": "def5678"
}
```

### Escalation Triggers

| Condition | Action |
|---|---|
| Unresolvable conflict markers remain | Escalate immediately |
| Regression not fixed in one round | Escalate with CONFLICT.json |
| Orphan fix would violate acceptance criteria | Escalate — ticket scope may have changed |
| Disconnected integration detected | Escalate — do not guess at reconnection strategy |
| Compilation fails after orphan fix attempt | Escalate |

### What The Critic Receives After a Merge

The Critic is always given the CONFLICT.json alongside its normal context package. It pays specific attention to:
- Any files marked `orphan_risk` (dead exports)
- The diff analysis report — changes that came in from base that affect our code
- The resolution strategy used for each conflicted file — it can disagree and flag if it believes the wrong side was prioritised

---

## Tech Stack & Environment

- **Runtime:** Claude Code with native multi-agent (Task tool) orchestration
- **Languages:** TypeScript / JavaScript
- **Repos:** Multiple GitHub repos (trunk-based branching)
- **Protected branches:** `main`, `master`, `staging` — agent never pushes directly
- **CI/CD:** GitHub Actions
- **Tests:** Unit, integration, linting / static analysis
- **Jira:** Cloud or Server/DC (auto-detect on startup)
- **Team size:** Small (2–5 engineers working alongside the agent)

---

## Worktree Management

### Strategy

All work is performed inside a dedicated git worktree per ticket. The agent creates the worktree at the start of the workflow and cleans it up after the PR is merged. This isolates each ticket's work completely, allows multiple tickets to progress concurrently without interfering with each other, and keeps the main repo checkout clean.

### Worktree Lifecycle

```
Workflow start:
  → git worktree add ../worktrees/PROJ-123 -b abc_proj-123_short-description_feature [base]
      → base is either: origin/main (default) or the dependency branch (see Ticket Dependencies)
  → Worktree initialisation (see Worktree Initialisation below)
  → All agent work (Developer, QA, Conflict Resolution) runs inside this worktree
  → PRD.json records the worktree path

Workflow complete (PR merged):
  → git worktree remove ../worktrees/PROJ-123 --force
  → git branch -d abc_proj-123_short-description_feature
  → Archive run artefacts (PRD.json, REVIEW.json, FEEDBACK.json, CONFLICT.json, run.log)
    → Move to /runs/PROJ-123/
  → Update PRD.json overall_status to "done"
```

### Worktree Initialisation

Immediately after `git worktree add`, before any agent work begins, the Orchestrator runs the initialisation sequence inside the new worktree. This is mandatory — without it the worktree is missing files and dependencies that are not committed to the repo.

```
Worktree initialisation sequence:
  1. Copy non-committable files from source repo root to worktree root
      → Identify files: any file present in repo root that matches .gitignore patterns
          → Always includes: .env, .env.local, .env.development, .env.test, .env.production
          → Also includes: any other .gitignore'd config files present in source repo root
      → Copy strategy: cp --preserve (preserve timestamps and permissions)
      → Never overwrite if file already exists in worktree (resume safety)

  2. Run npm install inside worktree
      → cd ../worktrees/PROJ-123
      → npm install
      → If npm install fails: auto-repair triggers (see Auto-Repair System)
      → node_modules is never copied from source — always installed fresh

  3. Validate initialisation
      → Verify .env (or equivalent) exists in worktree
      → Verify node_modules exists and is non-empty
      → Run tsc --noEmit to confirm clean baseline compile
          → If compile fails at baseline: ESCALATE to human before any work starts
            (base branch may already have a type error — not our problem to silently inherit)
      → Mark initialisation complete in PRD.json
```

### Non-Committable File Discovery

The agent determines which files to copy using this priority order:

1. **Explicit list in CLAUDE.md** — repo-specific files always copied (defined per repo in the project)
2. **`.gitignore` pattern matching** — any file in the repo root matching `.gitignore` patterns
3. **Known defaults** — `.env`, `.env.*`, `*.local`, `*.pem`, `*.key` — always copied if present

Files are discovered from the **source repo root** (the main checkout), not from another worktree. This ensures the worktree always starts from the canonical non-committed state.

### Resumed Worktrees

If a worktree already exists for a ticket on startup (interrupted run), the initialisation sequence is **skipped** — the worktree was already initialised in the previous session. The agent checks:
- Does `.env` (or equivalent) exist? If not, re-run step 1 only
- Does `node_modules` exist and is it non-empty? If not, re-run step 2 only
- Run `tsc --noEmit` to confirm still-clean baseline before resuming

### Worktree Rules

- **One worktree per ticket** — never share a worktree between tickets
- **Worktree path convention:** `../worktrees/TICKET-ID` relative to the repo root
- **Agent never operates outside its assigned worktree** — all file reads, writes, and test runs happen inside
- **node_modules is never copied** — always installed fresh via npm install
- **Non-committable files are always copied from source repo root** — never from another worktree
- **Initialisation must complete before any agent work begins** — a failed init is a hard stop
- **Cleanup only happens after confirmed merge** — PR Monitor verifies merge before triggering cleanup, never on PR close or PR decline
- **Interrupted runs** — if a worktree exists on startup, resume inside it with partial re-init check

### Worktree Stale Detection

On every startup the Orchestrator scans for orphaned worktrees (worktrees with no corresponding active run in `/runs/`). It reports these to the human and does not clean them up automatically — stale worktrees may contain unfinished work.

### Updated Project Structure

```
/engineering-agent
  CLAUDE.md
  README.md
  .env.example
  .claude.json
  .gitleaks.toml
  PROGRESS.md                        ← Build progress tracker (this file)
  /agents
    CHANGELOG.md                     ← Major prompt version change history
    jira-agent.md                    ← v1.0.0
    planner-agent.md                 ← v1.0.0
    developer-agent.md               ← v1.0.0
    qa-agent.md                      ← v1.0.0
    the-critic.md                    ← v1.0.0
    secret-scanner.md                ← v1.0.0
    pr-agent.md                      ← v1.0.0
    pr-monitor.md                    ← v1.0.0
    conflict-resolution-agent.md     ← v1.0.0
  /schemas
    prd.schema.json
    review.schema.json
    feedback.schema.json
    conflict.schema.json
    repair.schema.json
    secrets.schema.json
  /scripts
    setup.sh
    detect-jira.sh
    validate-schemas.js
    worktree-scan.sh               ← Scans for orphaned worktrees on startup
  /runs
    /PROJ-123                      ← Archived after merge
      PRD.json
      REVIEW.json
      FEEDBACK.json
      CONFLICT.json
      SECRETS.json                 ← Only present if secrets were found
      run.log

/worktrees                         ← Lives alongside /engineering-agent, outside it
  /PROJ-123-api-service            ← Active worktree — ticket PROJ-123, repo api-service
  /PROJ-123-shared-lib             ← Active worktree — ticket PROJ-123, repo shared-lib
  /PROJ-456-api-service            ← Active worktree — ticket PROJ-456, repo api-service
```

---

## Ticket Dependency Checking

### Strategy

Before starting any work, the Jira Agent checks for explicit "blocked by" links on the ticket. If a blocker exists and is not Done, the agent stops. If a blocker is an unmerged PR that is ready for review, the agent branches off that PR's branch rather than main. Dependency status is checked once at workflow start — mid-workflow status changes are picked up on the next run.

### Dependency Check Flow

```
Jira Agent: fetch ticket
  → Check all "blocked by" issue links
    → For each blocker:
        → Fetch blocker ticket status via acli
          → Status is Done: blocker resolved, continue
          → Status is not Done:
              → Check if blocker has an associated PR
                → No PR found:
                    → Comment on ticket: "Blocked by PROJ-XXX (status: In Progress). Standing by."
                    → Transition ticket to "Blocked"
                    → STOP — do not start work
                → PR found:
                    → Check PR status via gh cli
                      → PR is merged: blocker resolved, continue (Jira status may be stale)
                      → PR is ready for review (not draft, no blocking reviews):
                          → Record dependency branch in PRD.json
                          → Create worktree branching from dependency branch
                          → Add note to PRD.json: "branched from PROJ-XXX/feature branch"
                          → Proceed with work
                      → PR is draft or has blocking reviews:
                          → Comment on ticket: "Blocked by PROJ-XXX (PR open but not ready). Standing by."
                          → Transition ticket to "Blocked"
                          → STOP
    → All blockers resolved or branched: proceed to Planner Agent
```

### Branching from a Dependency Branch

When the agent branches off a dependency PR's branch rather than main:

- The worktree is created from that branch: `git worktree add ../worktrees/PROJ-123 -b abc_proj-123_short-description_feature origin/abc_proj-456_dependency-description_feature`
- The Conflict Resolution Agent treats the **dependency branch as the base branch** for merge checks, not main
- PRD.json records both the dependency branch and main so the Conflict Resolution Agent knows the full chain
- When the dependency PR eventually merges to main, the PR Monitor detects this and triggers a standard conflict resolution check against main at that point

### PRD.json Dependency Fields

```json
{
  "ticket": "PROJ-123",
  "base_branch": "abc_proj-456_dependency-description_feature",
  "base_is_dependency": true,
  "dependency_ticket": "PROJ-XXX",
  "dependency_pr": "PR-789",
  "ultimate_base": "main"
}
```

### Rules

- **Strict link checking only** — no inference from ticket descriptions or comments
- **Always check blocker ticket status AND associated PR status** — Jira status may be stale
- **Only branch from dependency when PR is ready for review** — draft PRs are not stable enough to build on
- **One level of dependency branching** — if the dependency branch itself depends on another unmerged branch, escalate to human rather than chain three levels deep
- **Mid-workflow blocker changes are ignored** — if a blocker resolves while work is in progress, it is picked up on the next workflow run, not the current one

---

## Branch Naming Convention

### Format

```
{employeecode}_{issue-id}_{description}_{branch-type}
```

All lowercase. Spaces replaced with hyphens in description. No special characters.

### Examples

```
abc_proj-123_add-auth-middleware_feature
abc_proj-456_fix-payment-service-timeout_bug
abc_proj-789_resolve-checkout-validation-error_defect
abc_proj-101_remove-unused-dependencies_debt
abc_proj-202_update-node-version_chore
```

### Branch Type Mapping

| Jira Issue Type | Branch Type | Notes |
|---|---|---|
| Story | `feature` | Default implementation work |
| Task | `feature` | Default implementation work |
| Bug | `bug` | Production bug |
| Defect | `defect` | Bug caught before production |
| Technical Debt | `debt` | Tech debt / refactoring |
| Chore | `chore` | Non-ticket maintenance work |
| Unknown / unmapped | `feature` | Safe default |

### Employee Code

Read from `AGENT_EMPLOYEE_CODE` in `.env`. This is a 3-letter code unique per employee (typically first letter of first name + first two letters of surname, but may differ where initials clash).

If `AGENT_EMPLOYEE_CODE` is missing or empty at startup, the agent stops immediately before creating any branch — this is a hard requirement.

### Description Generation

The Planner Agent generates the branch description from the ticket title by:
1. Lowercasing the full title
2. Removing special characters
3. Replacing spaces with hyphens
4. Truncating to 40 characters at a word boundary

### Branch Name Validation

Before creating any branch, the agent validates the generated name against the format. If validation fails the agent escalates rather than creating a malformed branch name.

```
Valid:   abc_proj-123_add-auth-middleware_feature    ✓
Invalid: ABC_PROJ-123_AddAuthMiddleware_feature      ✗ (uppercase)
Invalid: proj-123_add-auth-middleware_feature        ✗ (missing employee code)
Invalid: abc_proj-123_add auth middleware_feature    ✗ (spaces in description)
```

---

## Ticket Intake & Validation

### How the Workflow is Invoked

The workflow is always invoked with a specific ticket ID provided externally. Ticket selection and filtering is a separate concern — this system only processes tickets it is explicitly handed.

```bash
# Invocation
claude-code run --ticket PROJ-123
```

### Intake Validation

Before any work begins — before worktree creation, before planning — the Jira Agent performs a fast validation pass to confirm the ticket is workable:

| Check | Fail condition | Action |
|---|---|---|
| Ticket exists | Not found in Jira | STOP — report invalid ID |
| Ticket type | Epic, sub-task, or non-implementation type | STOP — report unsupported type |
| Ticket status | Done, Cancelled, Won't Do | STOP — nothing to do |
| Ticket status | Blocked | STOP — report blocker details |
| Active worktree | Worktree already exists for this ticket | Resume existing run, do not start fresh |
| Ticket assignee | Unassigned | Assign to agent service account, then proceed |
| Acceptance criteria | None defined | Escalate to human — cannot plan or verify without criteria |

### Supported Ticket Types

The agent handles implementation work only. Define the supported types in CLAUDE.md per project:

- `Story` — default supported
- `Task` — default supported
- `Bug` — default supported
- `Sub-task` — **not supported** — sub-tasks should be handled as tasks within their parent story's PRD.json
- `Epic` — **not supported** — epics are containers, not implementable units

### Acceptance Criteria Requirement

If a ticket has no acceptance criteria, the agent escalates immediately rather than proceeding with assumptions. This is a hard requirement — The Critic cannot verify work without criteria, and the Planner Agent cannot generate reliable tasks without them.

The Jira Agent posts a comment on the ticket explaining what's needed before work can begin.

### Invocation Modes

```bash
# Normal run
claude-code run --ticket PROJ-123

# Dry run — plan only, no code changes
claude-code run --ticket PROJ-123 --dry-run

# Resume interrupted run
claude-code run --ticket PROJ-123 --resume
```

The `--resume` flag skips intake validation and goes straight to detecting the existing worktree state.

---

```
Orchestrator receives: TICKET-ID (provided externally)

  → Orchestrator: read REPAIR_KNOWLEDGE.json + AGENT_LEARNING.json at startup
      → standing instructions and repair knowledge ready for injection throughout run

  → Orchestrator: ticket intake & validation
      → Jira Agent: fetch ticket by ID
        → Ticket not found: STOP — report invalid ticket ID
        → Ticket type not supported (e.g. Epic, sub-task): STOP — report unsupported type
        → Ticket already has an active worktree: resume existing run (do not start fresh)
        → Ticket status is Done or Cancelled: STOP — nothing to do
        → Ticket status is Blocked: STOP — report blocker, do not start
        → Ticket is valid and workable: proceed
  → Orchestrator: scan for orphaned worktrees, report if found (non-blocking)
  → Jira Agent: full parse — requirements, acceptance criteria, linked issues
      → Ticket dependency check (blocked by links + PR status)
        → Blocked and not resolvable: comment on ticket, transition to Blocked, STOP
        → Dependency PR ready for review: record dependency branch in PRD.json
        → All clear: proceed
  → Planner Agent: generate PRD.json (includes worktree path + base branch)
  → Orchestrator: create and initialise worktree
      → git worktree add ../worktrees/TICKET-ID -b {employeecode}_{ticket-id}_{description}_{branch-type} [base]
      → Copy non-committable files from source repo root (.env, .env.*, .gitignore'd configs)
      → npm install inside worktree
      → tsc --noEmit baseline compile check
          → if baseline fails: ESCALATE — do not start work on a broken base
  → Developer Agent: work through PRD.json tasks one at a time (inside worktree)
      → per task: implement → QA Agent verifies (auto-fix → tsc → lint → format → unit tests) → mark task complete → next task
  → QA Agent: run full suite (auto-fix → tsc → lint → format → unit → integration tests)
  → Conflict Resolution Check: merge base branch into feature branch
      → if no conflicts: regression guard + orphan check → continue
      → if conflicts exist: Conflict Resolution Agent resolves → QA re-verifies
      → if unresolvable: ESCALATE to human
  → The Critic: internal code review with full context + CONFLICT.json → REVIEW.json
      → if critical/high/medium issues:
          → Developer Agent resolves (max 3 rounds, inside worktree)
          → QA Agent re-verifies
          → Conflict Resolution Check re-run
          → The Critic re-reviews
          → if unresolved after 3 rounds: ESCALATE to human
      → if clean (or low severity only): proceed
  → Secret Scanner: run gitleaks on full diff
      → secrets found: generate SECRETS.json, HARD BLOCK, notify human, STOP
      → clean: proceed
  → PR Agent: open PR as draft, description, link Jira, update Jira to "In Review"
  → PR Monitor: monitor CI + GitHub PR comments
      → if base branch has moved:
          → Conflict Resolution Check re-run (inside worktree)
          → QA re-verifies
          → PR Agent pushes merge commit
      → if CI fails or changes requested:
          → generate FEEDBACK.json
          → Developer Agent resolves items (inside worktree)
          → QA Agent re-verifies
          → Conflict Resolution Check re-run
          → The Critic re-reviews (if code changes)
          → PR Agent pushes updates
          → PR Monitor re-monitors (loop)
          → if stalled or conflicting feedback: ESCALATE to human
      → if approved + CI green: notify human to merge
  → On merge confirmed:
      → Jira → Done
      → git worktree remove ../worktrees/TICKET-ID --force (all repos)
      → git branch -d {branch} (all repos)
      → Archive artefacts to /runs/TICKET-ID/
      → Run Analyst: analyse last N runs for recurring behavioural patterns
          → patterns found: update AGENT_LEARNING.json, escalate persistent patterns to human
          → no patterns: log clean run summary
```

---

## PRD.json Schema

```json
{
  "ticket": "PROJ-123",
  "title": "Short description of ticket",
  "repos": [
    {
      "name": "api-service",
      "worktree_path": "../worktrees/PROJ-123-api-service",
      "branch": "abc_proj-123_add-auth-middleware_feature",
      "base_branch": "main",
      "base_is_dependency": false,
      "dependency_ticket": null,
      "dependency_pr": null,
      "ultimate_base": "main",
      "primary": true
    },
    {
      "name": "shared-lib",
      "worktree_path": "../worktrees/PROJ-123-shared-lib",
      "branch": "abc_proj-123_add-auth-types_feature",
      "base_branch": "main",
      "base_is_dependency": false,
      "dependency_ticket": null,
      "dependency_pr": null,
      "ultimate_base": "main",
      "primary": false
    }
  ],
  "requirements": "Full requirement text from Jira",
  "acceptance_criteria": [
    "Criterion 1",
    "Criterion 2"
  ],
  "tasks": [
    {
      "id": "task-1",
      "repo": "shared-lib",
      "description": "Add AuthToken type to shared-lib",
      "files_affected": ["src/types/auth.ts"],
      "dependencies": [],
      "status": "pending"
    },
    {
      "id": "task-2",
      "repo": "api-service",
      "description": "Implement middleware using AuthToken from shared-lib",
      "files_affected": ["src/middleware/auth.ts"],
      "dependencies": ["task-1"],
      "status": "pending"
    }
  ],
  "overall_status": "pending",
  "review_rounds": 0,
  "feedback_rounds": 0
}
```

**Notes on multi-repo:**
- Each repo gets its own worktree — path uses `TICKET-ID-REPO-NAME` to avoid collisions
- Each repo gets its own branch — same naming convention, same ticket ID
- Tasks specify which `repo` they belong to — Developer Agent switches worktree context per task
- The `primary` repo is the one where the PR description will reference the ticket. All repos open PRs but the primary is the canonical link back to Jira
- Dependency ordering between repos is expressed via task `dependencies` — a task in `api-service` that depends on `task-1` in `shared-lib` will not start until `task-1` is complete and its PR is merged or at minimum open and ready for review
- Repo selection logic (how Planner Agent determines which repos a ticket needs) is defined per-project in CLAUDE.md

**Task statuses:** `pending` → `in_progress` → `verified` → `complete`

**Overall statuses:** `pending` → `in_progress` → `review` → `pr_open` → `pr_approved` → `done`

---

## REVIEW.json Schema

```json
{
  "ticket": "PROJ-123",
  "round": 1,
  "verdict": "changes_required",
  "requirements_met": {
    "overall": false,
    "criteria": [
      {
        "criterion": "Criterion text from PRD.json",
        "met": false,
        "comment": "Explanation of what is missing"
      }
    ]
  },
  "code_review": {
    "items": [
      {
        "id": "review-1",
        "severity": "critical",
        "type": "security",
        "file": "src/path/to/file.ts",
        "line": 42,
        "comment": "Detailed description of the issue",
        "status": "pending"
      }
    ]
  },
  "test_quality": {
    "verdict": "insufficient",
    "comment": "What test coverage is missing"
  },
  "prd_adherence": {
    "verdict": "partial",
    "deviations": ["List of tasks skipped or deviated from"]
  },
  "summary": "One-line summary of verdict",
  "proceed_to_pr": false
}
```

**Severity levels:**

| Severity | Examples | Action |
|---|---|---|
| `critical` | Security vulnerability, data loss, broken functionality | Hard stop, must fix |
| `high` | Hardcoded secrets, missing error handling, logic flaws | Must fix before PR |
| `medium` | Poor structure, missing test coverage, code smells | Must fix before PR |
| `low` | Naming, minor style, suggestions | Logged in PR description, not blocking |

---

## FEEDBACK.json Schema

```json
{
  "pr": "PR-456",
  "round": 1,
  "source": "reviewer_comments",
  "items": [
    {
      "id": "feedback-1",
      "type": "change_request",
      "file": "src/path/to/file.ts",
      "line": 42,
      "comment": "Reviewer's comment",
      "status": "pending"
    },
    {
      "id": "feedback-2",
      "type": "ci_failure",
      "test": "test name > description",
      "error": "error output",
      "status": "pending"
    }
  ]
}
```

---

## CLAUDE.md Contents (to be created in Phase 3)

The CLAUDE.md must cover:

1. **Orchestrator role** — CLAUDE.md IS the Orchestrator. Read REPAIR_KNOWLEDGE.json and AGENT_LEARNING.json at startup. Maintain workflow state via PRD.json. Invoke subagents via Task tool (fresh read of agent .md file each invocation + standing instruction injection from AGENT_LEARNING.json). Assemble context packages, route based on output, handle all escalation conditions. Invoke Run Analyst at end of every completed run. Never do implementation work itself.
2. **Workflow definition** — the full loop described above
2. **Ticket intake rules** — supported types, validation checks, acceptance criteria requirement, invocation modes
3. **Worktree management** — create on start, initialise (copy non-committable files + npm install + baseline compile), operate inside, clean up on merge confirmed only. Define explicit list of non-committable files to always copy per repo.
3. **Ticket dependency checking** — strict blocked by link checking, PR status rules, one level of branching only
4. **Branching rules** — format: `{employeecode}_{issue-id}_{description}_{branch-type}` all lowercase. Branch type inferred from Jira issue type (see Branch Naming Convention). Employee code read from `AGENT_EMPLOYEE_CODE` env var. Never touch `main` / `master` / `staging` directly.
5. **Repo selection logic** — how the Planner Agent determines which repos a ticket touches (Jira component, label, or explicit mapping). Single-repo default. Multi-repo supported — each gets its own worktree and branch, tasks specify which repo they belong to.
6. **Commit message convention** — Conventional Commits, one commit per PRD.json task, ticket ref in footer, breaking changes documented. QA Agent validates every Developer Agent commit.
7. **QA pipeline** — auto-fix first (prettier --write, eslint --fix), then verify (tsc, lint, formatting check, unit tests, integration tests). Auto-fix changes committed as separate `chore: auto-fix` commit. Per-repo fixer list defined here.
7. **PR template** — structure, Jira link, description format, checklist, low-severity review notes
8. **Escalation conditions** — when to stop and surface to human vs proceed autonomously
9. **GitHub Actions awareness** — monitor CI checks, distinguish flaky vs real failures, react appropriately
10. **Team awareness** — check for existing PRs or branches on a ticket before starting to avoid conflicts
11. **Safety rules** — never push to protected branches, never force push, always create from latest base
12. **Dry run mode** — plan and describe what would happen without executing (for validation)

---

## Commit Message Convention

### Standard

All commits follow **Conventional Commits** (`conventionalcommits.org`). This enables automated changelog generation, clear git history, and consistent PR descriptions.

### Format

```
{type}({scope}): {short description}

{optional body — what and why, not how}

{optional footer — breaking changes, ticket reference}
```

### Commit Types

| Type | When used |
|---|---|
| `feat` | New feature or behaviour |
| `fix` | Bug fix |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `chore` | Maintenance — dependency updates, config changes, tooling |
| `debt` | Tech debt reduction, code cleanup |
| `perf` | Performance improvement |
| `docs` | Documentation only |
| `ci` | CI/CD configuration changes |

### Scope

Scope is the area of the codebase being changed — typically a module, service, or component name. Inferred from the files changed in each task. Optional but strongly preferred.

Examples: `auth`, `payments`, `api`, `middleware`, `config`

### Ticket Reference

Every commit by the Developer Agent includes the Jira ticket ID in the footer:

```
feat(auth): add jwt expiry validation

Validates token expiry on every request and returns 401 if expired.

Refs: PROJ-123
```

### Commit Granularity

- **One commit per PRD.json task** — the Developer Agent commits after each task completes QA verification
- **Auto-fix commits** are separate: `chore: auto-fix formatting and lint [QA]` — no ticket ref needed
- **Merge commits** use git's default message format, not conventional commits — they are structural, not semantic
- **Feedback round commits** follow the same convention — the type reflects what changed, not that it was a review fix

### Breaking Changes

If a task introduces a breaking change (changed API contract, removed export, changed function signature), the Developer Agent adds `BREAKING CHANGE:` to the commit footer:

```
refactor(api): rename validateToken to verifyToken

Renamed for consistency with the auth service naming convention.

BREAKING CHANGE: validateToken is no longer exported. Use verifyToken instead.
Refs: PROJ-123
```

The Critic checks for breaking changes as part of its review and flags any that are undocumented in the commit.

### Commit Message Validation

The QA Agent validates every Developer Agent commit message against the convention before marking a task complete. Invalid messages are rejected and the Developer Agent must rewrite them. The auto-fix commit is exempt from this validation.

---

## QA Verification Pipeline

### Philosophy

Auto-fix before reporting. If a tool can fix an issue automatically, it should do so silently and commit the result. Only issues that remain after all auto-fixers have run are treated as failures. This avoids Developer Agent round-trips for mechanical issues that tools can handle themselves.

### Verification Order

The QA Agent runs the following sequence — both per-task and on the full suite:

```
QA Agent verification sequence:
  1. Auto-fix pass (run all auto-fixers, stage changes, commit if any fixes applied)
      → prettier --write .            ← format all files
      → eslint --fix .                ← fix all auto-fixable lint issues
      → (any other project-specific auto-fixers defined in CLAUDE.md)

  2. TypeScript compilation
      → tsc --noEmit
      → If fails: back to Developer Agent with compiler errors

  3. Lint / static analysis (after auto-fix — remaining issues are real failures)
      → eslint . (no --fix flag — auto-fix already ran)
      → If fails: back to Developer Agent with lint errors

  4. Formatting verification (after prettier --write — any remaining issues are real failures)
      → prettier --check .
      → If fails: back to Developer Agent (should be rare — prettier --write should catch all)

  5. Unit tests
      → If fails: back to Developer Agent with test output

  6. Integration tests (full suite only — not per individual task)
      → If fails: back to Developer Agent with test output
```

### Auto-Fix Commit Strategy

When auto-fixers make changes, those changes are committed immediately as a separate commit with a standardised message:

```
chore: auto-fix formatting and lint [QA]
```

This keeps auto-fix changes clearly separated from Developer Agent changes in the git history, making the diff easier to review. The Critic and human reviewers can easily identify and skip these commits if needed.

### Auto-Fixer Configuration

Auto-fixers are configured per-repo in CLAUDE.md. The QA Agent reads this list on startup rather than assuming which tools are available. Defaults for TypeScript/JavaScript repos:

| Tool | Command | Scope |
|---|---|---|
| prettier | `prettier --write .` | Formatting |
| eslint | `eslint --fix .` | Lint + some style rules |

Additional fixers (e.g. `sort-imports`, custom codemods) can be added to the repo's CLAUDE.md section.

### What Happens if Auto-Fix Changes Acceptance-Critical Code

Auto-fixers only touch formatting and mechanical style — they never change logic. However if an eslint rule auto-fixes something in a file that is central to the PRD.json acceptance criteria, the QA Agent flags the changed file in the run log so The Critic is aware the file was touched by auto-fix, not just the Developer Agent.

### Per-Task vs Full Suite

| Scope | Steps run |
|---|---|
| Per task (after each Developer Agent task) | 1 (auto-fix), 2 (tsc), 3 (lint), 4 (formatting), 5 (unit tests) |
| Full suite (after all tasks complete) | All 6 steps including integration tests |
| After conflict resolution | All 6 steps |
| After feedback round changes | All 6 steps |

Integration tests are expensive — running them per-task would slow the workflow significantly. Unit tests catch per-task regressions; integration tests catch system-level issues once all tasks are done.

---

## Secret & Credential Scanning

### Strategy

Before any PR is opened, the full diff is scanned for accidentally committed secrets using **gitleaks**. This is a hard block — if a secret is detected, no PR opens under any circumstances and the human is notified immediately. The scan covers the diff only, not git history.

This gate sits between The Critic's approval and the PR Agent opening the PR.

### When Scanning Runs

- Once, pre-PR, after The Critic approves and before PR Agent acts
- Not on every push — one gate is sufficient

### Secret Scan Flow

```
The Critic approves (or approves with low severity only)
  → Secret Scanner: run gitleaks on full diff (worktree changes vs base branch)
      → Clean: proceed to PR Agent
      → Secret detected:
          → Generate SECRETS.json (file, line, secret type — never the value itself)
          → HARD BLOCK — do not open PR
          → Notify human immediately with SECRETS.json
          → Mark PRD.json overall_status: "blocked_secrets"
          → STOP — human must remediate before workflow can continue
```

### SECRETS.json Schema

```json
{
  "ticket": "PROJ-123",
  "scanned_at": "2024-01-15T10:30:00Z",
  "tool": "gitleaks",
  "scan_target": "diff",
  "findings": [
    {
      "id": "secret-1",
      "rule_id": "generic-api-key",
      "description": "Generic API Key detected",
      "file": "src/services/payment.ts",
      "line": 42,
      "commit": "abc1234",
      "secret_type": "api_key",
      "secret_value": "[REDACTED — never logged]"
    }
  ],
  "status": "blocked"
}
```

**Note:** The actual secret value is never written to any log, artefact, or notification. SECRETS.json records type, location, and rule only.

### Rules

- **Hard block — no exceptions** — no PR opens if `findings` is non-empty
- **Never auto-fix** — the agent does not attempt to remove the secret, rewrite history, or rotate credentials. Human must do this.
- **Never log the secret value** — SECRETS.json, run.log, and notifications contain file/line/type only
- **Diff only** — git history is not scanned. If a secret was committed in a previous run and removed in this one, it is not flagged.
- **PRD.json status set to `blocked_secrets`** — makes the block visible to the Orchestrator and resumable once human has resolved it
- **Resuming after remediation** — once human confirms remediation, the workflow resumes from the secret scan step (re-runs gitleaks before proceeding to PR Agent)

### gitleaks Configuration

A `.gitleaks.toml` config file should be added to the `engineering-agent` project to tune the ruleset for your codebase — suppress known false positives (e.g. test fixture data, example keys in documentation) and add custom rules for internal token formats.

---

## Tooling

### 1. acli (Atlassian CLI) — Jira
- **Tool:** `acli` — Atlassian command line interface
- **Used for:** Read issues, transition status, add comments, search issues (JQL)
- **Config:** `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` (Cloud) or `JIRA_PAT` (Server/DC)
- **Notes:** Agents invoke `acli` commands directly via Claude Code's bash tool

### 2. Confluence MCP — Documentation
- **Tool:** Confluence MCP server
- **Used for:** Read specs, architecture docs, team conventions linked from Jira tickets
- **Notes:** Planner Agent and The Critic can pull Confluence pages for additional context when tickets reference them
- **Config:** Configured via `.claude.json` MCP server config

### 3. gh cli (GitHub CLI) — GitHub
- **Tool:** `gh` — official GitHub CLI
- **Used for:** Create branches, open PRs, read PR comments, check CI status, push updates
- **Config:** `gh auth login` — uses existing authenticated session
- **Notes:** Agents invoke `gh` commands directly via Claude Code's bash tool

### 4. gitleaks — Secret Scanning
- **Tool:** `gitleaks` — fast, configurable secret scanner
- **Used for:** Pre-PR diff scanning for accidentally committed secrets, tokens, keys
- **Config:** `.gitleaks.toml` in `engineering-agent` project root — tune false positives, add custom rules
- **Notes:** Invoked via bash tool on the diff between feature branch and base branch

---

## Agent Architecture

### How Agents Work at Runtime

All agents are defined as **static `.md` files** stored in `/agents/`. They are version controlled, independently testable, and completely separate from orchestration logic. Nothing is instantiated until the Orchestrator explicitly invokes it.

At runtime, the Orchestrator uses Claude Code's native **`Task` tool** to spawn each subagent on demand. The flow for every agent invocation is:

```
Orchestrator
  → reads /agents/{agent-name}.md from disk (fresh read every invocation)
  → assembles context package for this step (ticket, PRD.json, diff, etc.)
  → calls Task(system_prompt = file contents, input = context package)
    → subagent runs, produces output (JSON artefact or action)
    → subagent exits — it holds no state
  → Orchestrator reads output, updates PRD.json, decides next step
```

### Why Static Files, Not Dynamic Generation

| Concern | Static files | Fully dynamic |
|---|---|---|
| Version control | ✓ Every change tracked and reviewable | ✗ Generated prompts invisible to git |
| Debuggability | ✓ Always know exactly what prompt ran | ✗ Hard to reproduce a failure |
| Testability | ✓ Each agent testable in isolation | ✗ Behaviour depends on orchestrator state |
| Prompt versioning | ✓ Version in file header, recorded in PRD.json | ✗ No stable version to record |
| Separation of concerns | ✓ Agent identity separate from workflow logic | ✗ Orchestrator becomes bloated |
| Tuning | ✓ Improve The Critic without touching orchestrator | ✗ Changes ripple through orchestrator |

### Fresh Read Per Invocation

The Orchestrator reads each agent file fresh every time it spawns a subagent — it does not cache file contents at startup. This means:
- Agent prompts can be updated without restarting a run
- The prompt versioning system records what was actually on disk at invocation time
- No stale state — every subagent starts from the canonical file

### Context Injection

The agent `.md` file defines static identity and behaviour. Runtime context is always injected dynamically at invocation time. The Orchestrator assembles the context package for each step:

| Agent | Static (from .md file) | Dynamic (injected at runtime) |
|---|---|---|
| Jira Agent | Persona, output format, rules | Ticket ID to fetch |
| Planner Agent | Persona, PRD.json schema, rules | Parsed ticket, repo structure |
| Developer Agent | Persona, commit convention, rules | PRD.json task, relevant files |
| QA Agent | Persona, pipeline order, fixer list | Worktree path, task being verified |
| The Critic | Persona, severity rules, output format | Ticket, PRD.json, diff, test results, CONFLICT.json, previous rounds |
| Secret Scanner | Rules, SECRETS.json schema | Diff to scan |
| PR Agent | Persona, PR template, draft rules | PRD.json, branch, Jira ticket |
| PR Monitor | Persona, escalation rules | PR URL, CI status, comments |
| Conflict Resolution | Persona, resolution rules | Conflicted files, PRD.json, base/feature diffs |

### Agent File Structure

Each `.md` file follows a consistent structure so the Orchestrator and build sessions know exactly what to expect:

```markdown
---
agent: agent-name
version: 1.0.0
---

## Identity
{Who this agent is and its core persona}

## Responsibilities
{What this agent is responsible for — and explicitly what it is NOT responsible for}

## Context Contract
### Receives
{Exactly what input this agent expects}

### Produces
{Exactly what output this agent returns — always a specific JSON schema or defined action}

## Rules
{Behaviour rules, escalation conditions, hard limits}

## Output Format
{Schema or format spec for the output — agent outputs ONLY this, nothing else}
```

### Orchestrator's Role

The Orchestrator (CLAUDE.md) is the only agent that does not have its own `.md` file — it IS the CLAUDE.md file. It:
- Maintains workflow state via PRD.json
- Decides which agent to invoke next based on current state
- Assembles the correct context package per agent
- Reads agent outputs and routes accordingly
- Handles all escalation conditions

The Orchestrator never does implementation work itself — it delegates everything to subagents.

## Agent System Prompts (Summary)

### The Critic (most important to get right)
```
You are a senior engineer with 15 years of experience who has seen every 
possible mistake. Your job is to find everything wrong with this code before 
anyone else sees it. You are not here to be encouraging — you are here to 
be thorough. You review against:

1. The original Jira ticket requirements
2. Every acceptance criterion in the PRD.json
3. The planned tasks — flag any deviations or skipped tasks
4. Code quality: security, performance, architecture, naming, complexity
5. Test quality: coverage, meaningfulness, edge cases

Severity: critical (hard stop), high (must fix), medium (must fix), 
low (log but do not block).

You receive: Jira ticket, PRD.json, full diff, test results, repo 
conventions (CLAUDE.md), CONFLICT.json, previous REVIEW.json rounds.

Output ONLY valid REVIEW.json. Nothing else.
```

---

## Build Phases

### Phase 1 — Scaffold & Tool Setup
**Goal:** Project structure and tool connections working

- [ ] Create `engineering-agent` repo
- [ ] Create folder structure as defined in Worktree Management section
- [ ] Create `/worktrees` directory alongside repo root
- [ ] Verify `acli` is installed and authenticated (`acli jira issue list`)
- [ ] Verify `gh` cli is installed and authenticated (`gh auth status`)
- [ ] Configure Confluence MCP server in `.claude.json`
- [ ] Validate `acli` connection (read a real Jira ticket, check linked issues)
- [ ] Validate `gh` connection (list PRs on a repo, check PR status)
- [ ] Validate Confluence MCP connection (fetch a page)
- [ ] Install and verify `gitleaks` (`gitleaks version`)
- [ ] Create starter `.gitleaks.toml` config file
- [ ] Write `detect-jira.sh` to identify Cloud vs Server/DC
- [ ] Write `worktree-scan.sh` to detect orphaned worktrees on startup
- [ ] Create `.env.example` with all required variables including `AGENT_EMPLOYEE_CODE`
- [ ] Add `AGENT_EMPLOYEE_CODE` presence check to `setup.sh` — hard stop if missing
- [ ] Write `README.md` with setup instructions including tool prerequisites

### Phase 2 — JSON Schemas
**Goal:** Define contracts between agents

- [ ] Write `prd.schema.json` (include worktree + dependency fields)
- [ ] Write `review.schema.json`
- [ ] Write `feedback.schema.json`
- [ ] Write `conflict.schema.json`
- [ ] Write `repair.schema.json`
- [ ] Write `secrets.schema.json`
- [ ] Write `validate-schemas.js` script

### Phase 3 — CLAUDE.md
**Goal:** Write the rules before any agent code

- [ ] Write orchestrator role section (CLAUDE.md IS the orchestrator — Task tool invocation pattern, fresh read per invocation, context assembly per agent, PRD.json as state)
- [ ] Write workflow definition section
- [ ] Write ticket intake rules section (supported types, validation, acceptance criteria requirement, invocation modes)
- [ ] Write worktree management rules section
- [ ] Write ticket dependency checking rules section
- [ ] Write branching rules section ({employeecode}_{issue-id}_{description}_{branch-type}, type mapping table, validation rules)
- [ ] Write repo selection logic section
- [ ] Write commit message convention section (Conventional Commits, per-task granularity, ticket ref, breaking changes)
- [ ] Write secret scanning rules section (hard block, never log values, diff only)
- [ ] Write PR template section (include note if secrets scan produced warnings)
- [ ] Write escalation conditions section
- [ ] Write GitHub Actions awareness section
- [ ] Write team awareness section
- [ ] Write safety rules section
- [ ] Write dry run mode section

### Phase 4 — Agent System Prompts
**Goal:** Define each agent's identity, context contract, and output format using the standard agent file structure

Each file must include: frontmatter (agent name + version), Identity, Responsibilities, Context Contract (Receives / Produces), Rules, Output Format.

- [ ] Write `agents/orchestrator.md` — not needed, orchestrator IS the CLAUDE.md. Ensure CLAUDE.md covers all orchestration responsibilities explicitly.
- [ ] Write `agents/jira-agent.md` (include blocked by checking + PR status checking)
- [ ] Write `agents/planner-agent.md` (include worktree path + dependency branch in PRD.json, multi-repo repo selection)
- [ ] Write `agents/developer-agent.md` (one commit per PRD.json task, Conventional Commits, ticket ref in footer, document breaking changes)
- [ ] Write `agents/qa-agent.md` (validate commit message convention before marking task complete. Auto-fix first: prettier --write, eslint --fix, commit as chore. Then verify: tsc → lint → formatting → unit → integration)
- [ ] Write `agents/the-critic.md` ← highest priority (include breaking change documentation check, CONFLICT.json context)
- [ ] Write `agents/secret-scanner.md` (hard block on findings, never log values, diff only)
- [ ] Write `agents/pr-agent.md` (always open and update as draft — never ready-for-review. Exception: --ready-pr flag)
- [ ] Write `agents/pr-monitor.md` (include dependency branch → main detection)
- [ ] Write `agents/conflict-resolution-agent.md`
- [ ] Validate all agent files follow the standard structure
- [ ] Write `/agents/CHANGELOG.md` for tracking major prompt version changes

### Phase 5 — Orchestration Logic
**Goal:** Wire agents together into the full workflow loop

- [ ] Implement Orchestrator task delegation logic in CLAUDE.md
- [ ] Implement ticket intake validation (ticket exists, type supported, status workable, acceptance criteria present)
- [ ] Implement branch name generation — {employeecode}_{issue-id}_{description}_{branch-type} from AGENT_EMPLOYEE_CODE + Jira type mapping
- [ ] Implement branch name validation before any branch creation — hard stop if format invalid or AGENT_EMPLOYEE_CODE missing
- [ ] Implement invocation modes (--ticket, --dry-run, --resume, --pause, --stop, --ready-pr)
- [ ] Implement multi-repo support — multiple worktrees per ticket, task-level repo routing
- [ ] Implement worktree creation at workflow start (single and multi-repo)
- [ ] Implement worktree initialisation — non-committable file copy, npm install, baseline tsc check
- [ ] Implement non-committable file discovery (CLAUDE.md explicit list + .gitignore patterns + known defaults)
- [ ] Implement partial re-init check for resumed worktrees
- [ ] Implement worktree cleanup on confirmed merge (all repos)
- [ ] Implement worktree orphan scan on startup
- [ ] Implement ticket dependency check before planning
- [ ] Implement QA pipeline — auto-fix pass with commit, then tsc → lint → formatting → unit → integration
- [ ] Implement commit message validation in QA Agent (Conventional Commits format check per task)
- [ ] Implement per-task vs full suite QA scope switching
- [ ] Implement PRD.json task queue (one at a time, dependency-aware, cross-repo dependencies)
- [ ] Implement The Critic loop (max 3 rounds, then escalate)
- [ ] Implement secret scan gate between Critic approval and PR Agent
- [ ] Implement PR Monitor loop (escalate on stall or conflicting feedback)
- [ ] Implement rate limit backoff — exponential retry on 429s, log to run.log
- [ ] Implement human interrupt/override — --pause, --stop, safe checkpoints
- [ ] Implement agent prompt version recording in PRD.json on run start
- [ ] Implement agent prompt version mismatch warning on --resume
- [ ] Implement resume logic — detect existing worktree on startup and resume inside it
- [ ] Test full loop end-to-end on a real Jira ticket in dry run mode

### Phase 6 — Guardrails & Safety
**Goal:** Safe to run alongside a real team

- [ ] Branch protection enforcement (check branch name before every push)
- [ ] Conflict detection (check for existing human branches/PRs on ticket)
- [ ] Test gate (hard stop after 2 retry attempts on test failures)
- [ ] PR size warning — soft limit: if diff exceeds `AGENT_PR_SIZE_WARNING_FILES` files, pause and notify human for approval before opening PR. Do not block or fail — wait for explicit approval then continue.
- [ ] Secret scan hard block — gitleaks on diff, SECRETS.json generated, never log secret values
- [ ] PRD.json `blocked_secrets` status — makes block visible and resumable after human remediates
- [ ] Rate limit backoff — transient, never increments auto-repair counter
- [ ] Max loop counters on all feedback loops
- [ ] Stale branch cleanup script (`claude-code cleanup --list-stale` and `--prune-branches`)

### Phase 7 — Observability
**Goal:** Know what the agent is doing at all times

- [ ] Structured run log per ticket (`/runs/TICKET-ID/run.log`)
- [ ] Terminal notifications on key events (PR opened, CI failed, escalation, rate limit retries)
- [ ] Run summary written to log at end of each ticket
- [ ] Agent version mismatch warnings logged on --resume
- [ ] Rate limit retry events logged with delay durations

### Phase 8 — Auto-Repair System
**Goal:** Self-healing agents that learn from failures across runs

- [ ] Create `REPAIR_KNOWLEDGE.json` with empty entries array and schema version
- [ ] Write `repair.schema.json` in `/schemas`
- [ ] Implement failure detection — track consecutive failures per agent + operation
- [ ] Implement in-run repair loop — retry once, then consult knowledge base, then self-reason
- [ ] Implement knowledge base writer — successful alternatives written back to `REPAIR_KNOWLEDGE.json`
- [ ] Implement confidence promotion logic (low → medium → high after 3 successes)
- [ ] Implement failed confidence short-circuit — skip straight to escalation
- [ ] Add knowledge base read to agent startup sequence
- [ ] Test auto-repair with a simulated failure scenario in dry run mode

### Phase 9 — Conflict Resolution
**Goal:** Safe, reliable merge conflict handling with regression guard and orphan prevention

- [ ] Write `agents/conflict-resolution-agent.md` system prompt
- [ ] Write `conflict.schema.json` in `/schemas` (updated schema with regression + orphan fields)
- [ ] Implement merge trigger — `git merge origin/main --no-ff` before Critic review
- [ ] Implement per-file conflict resolution loop with PRD.json context
- [ ] Implement regression guard — Pass 1 (tsc --noEmit), Pass 2 (diff analysis), Pass 3 (full QA suite)
- [ ] Implement orphan check — deleted callsites, renamed references, dead exports, disconnected integrations
- [ ] Implement orphan resolution rules — autonomous fixes for safe cases, escalation for unsafe ones
- [ ] Implement CONFLICT.json writer with regression + orphan fields
- [ ] Implement QA re-verification after merge
- [ ] Add conflict check to PR Monitor (detects base branch moving while PR is open)
- [ ] Pass CONFLICT.json to The Critic as part of its context package
- [ ] Add all escalation triggers
- [ ] Test regression scenario — base branch changes a function signature our code depends on
- [ ] Test orphan scenario — base branch deletes a callsite our feature was serving
- [ ] Test clean merge scenario — no conflicts, regression guard and orphan check pass cleanly

### Phase 10 — Agent Learning System
**Goal:** Self-improving agents that detect and correct recurring behavioural mistakes across runs

- [ ] Write `agents/run-analyst.md` system prompt (pattern detection across artefacts, standing instruction generation, escalation for persistent patterns)
- [ ] Write `agent-learning.schema.json` in `/schemas`
- [ ] Create `AGENT_LEARNING.json` with empty entries array and schema version
- [ ] Implement Run Analyst invocation at end of every completed run
- [ ] Implement pattern detection — scan last N REVIEW.json, FEEDBACK.json, run.log files for recurring issues
- [ ] Implement standing instruction generation from detected patterns
- [ ] Implement AGENT_LEARNING.json writer
- [ ] Implement status lifecycle (active → resolved after 5 clean runs, active → persistent after 2 recurrences post-instruction)
- [ ] Implement Orchestrator startup read of AGENT_LEARNING.json
- [ ] Implement standing instruction injection into agent context packages at invocation time
- [ ] Implement persistent pattern escalation to human
- [ ] Test pattern detection with simulated recurring REVIEW.json findings
- [ ] Test instruction injection — verify standing instructions appear correctly in agent context
- [ ] Test resolution — verify pattern marked resolved after 5 clean runs

---

## Recommended Build Order

1. Phase 1 (scaffold + tool setup) — nothing works without this
2. Phase 2 (schemas) — define contracts early
3. Phase 3 (CLAUDE.md) — write the rules before any agent code
4. Phase 4 (agent prompts) — define agents
5. Phase 5 (orchestration) — wire it together, includes worktree + dependency logic
6. Phase 6 (guardrails) — harden it
7. Phase 7 (observability) — make it transparent
8. Phase 8 (auto-repair) — make it self-healing for tool failures
9. Phase 9 (conflict resolution) — make it resilient to team activity
10. Phase 10 (agent learning) — make it self-improving over time

---

## Team Build Strategy (Parallel Sessions)

To speed up development, phases can be distributed across parallel Claude Code sessions. Each session should be given this PLAN.md and the current PROGRESS.md at the start.

**Suggested parallel tracks:**

| Track | Phases | Sessions |
|---|---|---|
| **Infrastructure** | Phase 1 (scaffold + tool setup) | Session A |
| **Contracts** | Phase 2 (schemas) + Phase 3 (CLAUDE.md) | Session B |
| **Agents** | Phase 4 (agent prompts) | Session C (can split per agent) |
| **Logic** | Phase 5 (orchestration + worktree + dependency) | Session D — starts after A + B + C complete |
| **Safety + Observability** | Phase 6 + Phase 7 | Session E — runs alongside D |
| **Auto-Repair** | Phase 8 | Session F — runs alongside D and E |
| **Conflict Resolution** | Phase 9 | Session G — runs alongside D, E and F |
| **Agent Learning** | Phase 10 | Session H — starts after Phase 7 observability complete (needs run.log structure) |

**Session startup instructions:**
> "You are building the `engineering-agent` project. Read PLAN.md for full context and PROGRESS.md for current status. Your task for this session is [specific phase/task]. Mark items complete in PROGRESS.md as you finish them."

---

## Escalation Conditions (Human Required)

The agent must stop and notify the human when:

- Secret detected in diff by gitleaks — hard block, human must remediate before workflow resumes
- Ticket is blocked by an unresolved Jira issue with no associated PR
- Ticket is blocked by a PR that is still in draft or has blocking reviews
- Blocker dependency chain is more than one level deep
- Orphaned worktrees detected on startup (report only, do not auto-clean)
- The Critic finds unresolved issues after 3 review rounds
- PR Monitor detects conflicting reviewer feedback that cannot be reconciled
- PR Monitor detects a stalled PR (no activity for configurable period)
- A task fails QA after 2 retry attempts
- A diff touches more files than `AGENT_PR_SIZE_WARNING_FILES` — soft limit, pause and wait for human approval before opening PR
- Jira ticket is ambiguous and cannot be parsed into clear tasks
- Any attempt to interact with a protected branch is detected
- GitHub Actions reports a failure the agent cannot diagnose
- Conflict resolution finds a disconnected integration
- Orphan fix would violate an acceptance criterion

---

## Environment Variables Required

```bash
# Jira (via acli)
JIRA_URL=https://yourcompany.atlassian.net
JIRA_EMAIL=your@email.com
JIRA_API_TOKEN=your_api_token         # Jira Cloud
JIRA_PAT=your_personal_access_token  # Jira Server/DC (alternative)

# GitHub (via gh cli — authenticate separately with: gh auth login)
# No token needed in .env — gh cli uses its own auth session

# Agent identity
AGENT_EMPLOYEE_CODE=abc              # 3-letter employee code used in branch names (lowercase)

# Agent config
AGENT_MAX_REVIEW_ROUNDS=3
AGENT_MAX_FEEDBACK_ROUNDS=5
AGENT_PR_SIZE_WARNING_FILES=10
AGENT_DRY_RUN=false                      # Set true to plan without executing
AGENT_RATE_LIMIT_BASE_DELAY_MS=2000      # Initial backoff delay for rate limit retries
AGENT_RATE_LIMIT_MAX_RETRIES=3           # Max retries on rate limit before escalation
AGENT_STALE_BRANCH_DAYS=30               # Days before a branchless merged branch is considered stale
AGENT_LEARNING_WINDOW=5                  # Number of recent completed runs the Run Analyst analyses for patterns
AGENT_LEARNING_PERSISTENCE_THRESHOLD=2  # Recurrences after instruction before escalating as persistent

# Notifications (optional)
SLACK_WEBHOOK_URL=your_webhook_url
```

**Prerequisites (must be installed and authenticated before running):**
- `acli` — Atlassian CLI, authenticated against your Jira instance
- `gh` — GitHub CLI, authenticated via `gh auth login`
- Confluence MCP server — configured in `.claude.json`
- `AGENT_EMPLOYEE_CODE` set in `.env` — required before any branch can be created

---

## Rate Limiting & Backoff (Point 8)

All external CLI tool calls (`acli`, `gh`, Confluence MCP) are subject to rate limits. The agent must handle 429 responses gracefully rather than failing hard.

### Strategy

Rate limit errors are treated as a special case of the auto-repair system — they are transient by definition and always retried with exponential backoff before escalating.

```
CLI call fails with rate limit (HTTP 429 or equivalent error message):
  → Wait: 2s → retry
  → Still failing: wait 8s → retry
  → Still failing: wait 30s → retry
  → Still failing after 3 retries: ESCALATE to human — service may be degraded
```

### Per-Tool Backoff Config

Add to `.env`:

```bash
AGENT_RATE_LIMIT_BASE_DELAY_MS=2000    # Initial backoff in ms
AGENT_RATE_LIMIT_MAX_RETRIES=3         # Max retries before escalation
```

Rate limit retries are logged in `run.log` but do not increment the auto-repair failure counter — they are expected transient failures, not tool behaviour problems.

---

## Human Interrupt & Override (Point 9)

There must be a way to pause or stop an in-progress run gracefully without losing state.

### Interrupt Modes

```bash
# Pause — agent stops at the next safe checkpoint, state preserved in PRD.json
claude-code run --ticket PROJ-123 --pause

# Stop — agent stops immediately, state preserved, worktree kept intact
claude-code run --ticket PROJ-123 --stop

# Override — force a specific status on the current run
claude-code run --ticket PROJ-123 --override-status review
```

### Safe Checkpoints

The agent only pauses at safe checkpoints — between tasks, never mid-task. Safe checkpoints are:
- After a task is marked complete in PRD.json
- After the full QA suite completes
- After The Critic writes REVIEW.json
- After a PR is opened
- After PR Monitor detects a state change

Mid-task interrupts use `--stop` which writes `overall_status: "interrupted"` to PRD.json. On next startup with `--resume`, the agent detects this and re-runs the current in-progress task from scratch.

---

## Draft PR Strategy (Point 10)

PRs are opened as **draft by default** — both on creation and on every subsequent push. This gives the team visibility into work in progress without triggering review requests prematurely. The PR is only converted to ready-for-review when the human explicitly approves the merge.

The `--draft-pr` flag is therefore no longer needed — draft is always the behaviour. A `--ready-pr` flag is available for the rare case where you want to skip draft and open directly as ready-for-review:

```bash
# Open PR directly as ready-for-review (skips draft)
claude-code run --ticket PROJ-123 --ready-pr
```

### Draft Lifecycle

```
PR Agent opens PR as draft
  → All subsequent pushes (feedback rounds, conflict resolution updates) also push to the same draft PR
  → PR Monitor monitors CI and comments on the draft PR
  → When approved + CI green: notify human to merge
  → Human merges (or marks ready-for-review if team review is required first)
```

### Why Draft by Default

- Prevents accidental review requests before all feedback rounds are complete
- Gives teammates visibility into what the agent is working on
- Reduces noise — reviewers are not pinged until the human decides the work is ready
- Consistent behaviour — no need to remember to pass a flag

---

## Stale Branch Cleanup (Point 11)

Over time, abandoned feature branches accumulate. A cleanup script runs on demand (not on a schedule — the agent doesn't run autonomously without a ticket).

```bash
# List stale branches (merged or older than threshold, no open PR)
claude-code cleanup --list-stale

# Clean up stale branches (interactive — confirms each before deleting)
claude-code cleanup --prune-branches
```

A branch is considered stale if:
- It has been merged to main/master/staging, OR
- It is older than `AGENT_STALE_BRANCH_DAYS` (default: 30) and has no open PR

Add to `.env`:
```bash
AGENT_STALE_BRANCH_DAYS=30
```

---

## Breaking Change Detection (Point 12)

Already covered in the Commit Message Convention section — The Critic checks for undocumented breaking changes as part of its review. The Developer Agent is required to document breaking changes in the commit footer.

Additionally, The Critic's review explicitly checks for:
- Exported function signature changes
- Removed or renamed exports
- Changed interface or type definitions used across repos
- Modified API contracts (request/response shapes)

If a breaking change is found that is **not documented** in the commit footer, The Critic raises it as a `high` severity finding — not `medium` — because it directly affects teammates consuming the changed code.

If the ticket spans multiple repos, The Critic pays particular attention to the shared/upstream repo changes and verifies the downstream repo tasks correctly account for them.

---

## Agent Prompt Versioning (Point 13)

When an agent's system prompt is updated, in-flight runs started with the old version should not be silently switched mid-run.

### Strategy

PRD.json records the agent prompt versions at the time the run started. If a run is resumed and the prompt versions have changed, the agent logs a warning but does not block — the diff between prompt versions is typically small enough that mid-run continuity is safe.

Add version field to PRD.json:

```json
{
  "agent_versions": {
    "orchestrator": "1.0.0",
    "planner": "1.0.0",
    "developer": "1.2.0",
    "qa": "1.1.0",
    "critic": "2.0.0",
    "pr-agent": "1.0.0",
    "pr-monitor": "1.0.0",
    "conflict-resolution": "1.0.0",
    "secret-scanner": "1.0.0"
  }
}
```

Each agent `.md` file has a version comment at the top. On resume, if any version differs from what PRD.json recorded, a warning is written to `run.log`:

```
[WARN] Agent version mismatch on resume: critic was 1.0.0, now 2.0.0. Continuing with current version.
```

Major version bumps (breaking prompt changes) should increment the major version and are noted in a `CHANGELOG.md` in `/agents/`.

---

## Notes for New Sessions

- Always read this PLAN.md in full before starting work
- Always read PROGRESS.md to understand current state
- Always update PROGRESS.md when completing a task
- Never modify completed items in PROGRESS.md — only mark pending items complete
- If you find an issue with the plan, note it in PROGRESS.md under "Issues" and continue
- Run in dry run mode (`AGENT_DRY_RUN=true`) when testing the full loop for the first time
- The Critic and CLAUDE.md are the two most important artefacts — invest the most care here
