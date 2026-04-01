# Workflow Issues Report & Fix Plan

## Context

5 completed runs (SHRED-3256 through SHRED-3277) reveal systemic issues: rate limit exhaustion consuming 19+ hours of overhead per run, orphan check false positives, missing PR assignment, and merge state corruption. This plan consolidates all 28 identified issues across scripts, agents, schemas, and configuration into a phased fix plan.

Extends (not duplicates) the existing `HARNESS_IMPROVEMENT_PLAN.md`. Many Phase 1-4 scripts already exist but have defects or incomplete integration.

## Working Style

This is team work. The orchestrating agent must **delegate fixes to parallel subagents** — one per independent fix or logical group. Do not implement fixes sequentially yourself. Each phase should:

1. Create a new branch from `main` (one branch per phase)
2. Read all affected files to build context
3. Spawn parallel agents for independent fixes (most fixes within a phase are independent)
4. Make any remaining edits the agents couldn't complete
5. Commit, push, and create PR
6. **Update this plan** — mark phase as DONE in the progress table, strike through resolved issues in the summary table with PR reference

---

## Issues Summary

| # | Severity | Issue | File(s) |
|---|----------|-------|---------|
| 1a | CRITICAL | ~~PR auto-assignment missing~~ | ✅ PR #36 |
| 1b | CRITICAL | ~~PR feedback comments not resolved after addressing~~ | ✅ PR #36 |
| 2a | HIGH | ~~Rate limit retry exhaustion (silent failures, stale PR data)~~ | ✅ PR #36 |
| 2b | HIGH | ~~PR monitor poll interval too aggressive (default 60s, should be 10-20min)~~ | ✅ PR #36 |
| 3 | CRITICAL | ~~parse-args.sh silent JSON parse failure~~ | ✅ PR #36 |
| 4 | CRITICAL | ~~Merge state not cleaned up on abandon~~ | ✅ PR #36 |
| 5 | HIGH | ~~Orphan check false positives (cat 2 & 4 unscoped)~~ | ✅ PR #37 |
| 6 | HIGH | ~~Preflight Jira auth mismatch (PAT vs API_TOKEN)~~ | ✅ PR #37 |
| 7 | HIGH | ~~Agent learning new entries start at occurrences:2~~ | ✅ PR #37 |
| 8 | HIGH | ~~Auto-repair regex not escaped, silent fallback~~ | ✅ PR #37 |
| 9 | HIGH | ~~check-team-conflict empty AGENT_EMPLOYEE_CODE~~ | ✅ PR #37 |
| 10 | HIGH | ~~Secret scan output not validated after write~~ | ✅ PR #37 |
| 11 | HIGH | ~~repos.json missing toolchain section~~ | ✅ already on main |
| 12 | HIGH | ~~Schema validation incomplete~~ | ✅ already resolved (AJV) |
| 13 | HIGH | ~~Regression guard skipped post-conflict~~ | ✅ PR #37 |
| 14a | MEDIUM | ~~No timeout on gh commands~~ | ✅ PR #38 |
| 14b | MEDIUM | ~~8 configurable env vars missing from .env/.env.example~~ | ✅ PR #38 |
| 15 | MEDIUM | ~~Exit code inconsistency (doc says 3, never used)~~ | ✅ PR #36 |
| 16 | MEDIUM | ~~output.sh emit_error loses exit code in subshells~~ | ✅ PR #38 |
| 17 | MEDIUM | ~~Branch name strips Unicode silently~~ | ✅ PR #38 |
| 18 | MEDIUM | ~~PR size check hardcoded threshold~~ | ✅ PR #38 |
| 19 | MEDIUM | ~~Worktree init git checkout failure silently ignored~~ | ✅ PR #38 |
| 20 | MEDIUM | ~~bc not in preflight (jitter precision loss)~~ | ✅ PR #39 |
| 21 | MEDIUM | ~~Orphan check grep regex too aggressive~~ | ✅ PR #39 |
| 22 | MEDIUM | ~~pr-monitor-poll.sh confusing error messages~~ | ✅ PR #36 |
| 23 | MEDIUM | ~~abort-run.sh doesn't validate PR number numeric~~ | ✅ PR #39 |
| 24 | MEDIUM | ~~Agent learning empty (0 patterns across 5 runs)~~ | ✅ PR #39 |
| 25 | MEDIUM | ~~No file locking on JSON read-modify-write~~ | ✅ PR #39 |
| 26 | LOW | ~~flock.sh return/exit fallback kills parent~~ | ✅ PR #39 |
| 27 | LOW | ~~with-timeout.sh macOS fallback no warning~~ | ✅ PR #40 |
| 28 | LOW | ~~Rate limit check ignores PAT format~~ | ✅ PR #36 |

---

## Progress

| Phase | Status | Branch | PR |
|-------|--------|--------|-----|
| A | **DONE** | `mba_workflow-fixes-phase-a_feature` | [#36](https://github.com/markbailey/engineering-agent/pull/36) |
| B | **DONE** | `mba_workflow-fixes-phase-b_feature` | [#37](https://github.com/markbailey/engineering-agent/pull/37) |
| C | **DONE** | `mba_workflow-fixes-phase-c_feature` | [#38](https://github.com/markbailey/engineering-agent/pull/38) |
| D | **DONE** | `mba_workflow-fixes-phase-d_feature` | [#39](https://github.com/markbailey/engineering-agent/pull/39) |
| E | **DONE** | `mba_workflow-fixes-phase-e_feature` | [#40](https://github.com/markbailey/engineering-agent/pull/40) |

---

## Phase A: Critical Run Failures (#1-4) — DONE

### A.1 PR Auto-Assignment to Current User (#1)

1. **`scripts/preflight.sh`** — resolve current GitHub user via `gh api user --jq '.login'`, include in preflight output as `github_user`
2. **`scripts/parse-args.sh`** — include `current_github_user` in merged output JSON (from preflight or `GITHUB_USER` env var)
3. **`agents/pr-agent.md`** — add `current_github_user` to Receives contract; add rule: `gh pr edit {pr_number} --add-assignee {current_github_user}` after create; update output schema with `"assignee"` field
4. **`.claude/rules/workflow.md`** — PR CREATION section: pass `current_github_user` to PR Agent context
5. **`.env.example`** — document optional `GITHUB_USER` override

### A.1b PR Feedback Comments Resolved After Addressing (#1b)

After the Developer Agent addresses feedback (or the orchestrator decides not to address it), each PR comment should be marked as resolved and get a reply explaining what was done.

Currently the workflow at `.claude/rules/workflow.md:104-113` generates FEEDBACK.json, Developer resolves, QA re-verifies, PR Agent pushes — but no step resolves/replies to the original PR review comments.

1. **`agents/pr-agent.md`** — add new action `resolve_feedback` to context contract:
   - Receives: FEEDBACK.json (with items marked `addressed` or `wont_fix` + reason)
   - For each feedback item: reply to the comment via `gh api` GraphQL (`addPullRequestReviewComment` for reply, or REST `POST /repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`)
   - Then resolve the thread via GraphQL `resolveReviewThread` mutation (requires `threadId` from the comment)
   - Output: list of comment IDs resolved
2. **`agents/pr-monitor.md`** — when parsing review comments into FEEDBACK.json, also capture `comment_id` and `thread_id`. Add GraphQL query to fetch thread node IDs:
   ```graphql
   query($owner: String!, $repo: String!, $pr: Int!) {
     repository(owner: $owner, name: $repo) {
       pullRequest(number: $pr) {
         reviewThreads(last: 100) {
           nodes { id isResolved comments(first: 1) { nodes { databaseId body } } }
         }
       }
     }
   }
   ```
   Map each FEEDBACK.json item to its thread via `databaseId` match on comment.
3. **`schemas/feedback.schema.json`** — add optional `comment_id` (integer) and `thread_id` (string, GraphQL node ID) fields per feedback item
4. **`.claude/rules/workflow.md:112`** — after "PR Agent pushes updates", add: "PR Agent action=resolve_feedback → reply to each addressed comment and resolve thread. For wont_fix items, reply with reason and resolve."

### A.2 Rate Limit Retry Exhaustion (#2, #22, #28)

Real impact: `gh pr view` fails 3x per poll cycle (~30s wasted per cycle), errors swallowed, workflow continues on stale/missing PR data. The 68,860s in METRICS.json is mostly legitimate PR review wait time, not retry overhead. Root cause of `gh` failure unknown — `2>&1` merges stderr into stdout, masking the actual error.

**Step 1 — Diagnose:** Fix stderr capture first (separate stdout/stderr in pr-monitor-poll.sh and retry-with-backoff.sh). Run a poll cycle and inspect the raw error. Then fix the root cause based on what we find.

1. **`scripts/pr-monitor-poll.sh:33`** — separate stdout/stderr capture (temp file for stderr). Source `rate-limit.sh` and call `pre_gh_check` before `gh pr view`
2. **`scripts/retry-with-backoff.sh:55`** — don't merge stderr into stdout. After failed attempt, parse stderr for "rate limit" / 429 indicators. Call rate-limit.sh to wait for reset instead of blind backoff
3. **`scripts/rate-limit.sh:20-23`** — when `remaining` is `-1`, validate token format (ghp_/github_pat_ for PAT, base64 for API token). Emit warning on format mismatch

### A.2b PR Monitor Poll Interval Too Aggressive (#2b)

`.env` already has `AGENT_PR_MONITOR_INTERVAL=600` (10 min), but `pr-monitor-poll.sh:27` hardcodes default to `60` when env var missing. Docs also say "default 60s". This causes over-polling and contributes to rate limit exhaustion.

1. **`scripts/pr-monitor-poll.sh:27`** — change default from `60` to `1200`:
   `INTERVAL="${POSITIONAL[2]:-${AGENT_PR_MONITOR_INTERVAL:-1200}}"`
2. **`.env:29`** — update to `AGENT_PR_MONITOR_INTERVAL=1200`
3. **`.env.example:29`** — update to `AGENT_PR_MONITOR_INTERVAL=1200` with comment: `# Poll interval in seconds (default: 1200 = 20 min)`
4. **`.claude/rules/workflow.md:99`** — update "default 60s" to "default 1200s (20 min), configurable via AGENT_PR_MONITOR_INTERVAL"
5. **`.claude/commands/start.md:94`** — same doc fix

### A.3 parse-args.sh Silent JSON Parse Failure (#3)

**`scripts/parse-args.sh:137-138`** — add exit code checks after both node invocations:
```bash
ticket_id=$(echo "$local_data" | node -e "...") || { emit_error "Failed to parse ticket_id"; }
```
Or consolidate into the single node call at lines 91-132.

### A.4 Merge State Cleanup on Abandon (#4)

**`scripts/conflict-resolution.sh`**:
- After line 43 (conflicts detected): add `git -C "$wt_path" merge --abort 2>/dev/null || true`
- After line 38 (error branch): add same abort before exit 2
- Line 5: update exit code doc (remove unused exit 3)

---

## Phase B: High-Impact Defects (#5-13)

### B.1 Orphan Check PRD Scoping (#5)

**`scripts/orphan-check.sh`**:
- Lines 93-106 (category 2, renamed_references): filter `$refs` to only prd_files when PRD scoping active
- Lines 128-141 (category 4, disconnected_integrations): filter `$base_modified` to prd_files when active
- **`scripts/conflict-resolution.sh:80`**: pass `--prd "$AGENT_ROOT/runs/$ticket_id/PRD.json"` to orphan-check.sh

### B.2 Preflight Jira Auth Mismatch (#6)

**`scripts/preflight.sh:131`**: use `jira_token="${JIRA_API_TOKEN:-${JIRA_PAT:-}}"`. Detect token format for correct auth scheme (Basic vs Bearer).

### B.3 Agent Learning Occurrences Bug (#7)

**`scripts/agent-learning.sh:248`**: change `'occurrences': 2` to `'occurrences': 1`.

### B.4 Auto-Repair Regex Escaping (#8)

**`scripts/auto-repair.sh:55-59`**: log warning on regex fallback to literal match. Validate regex at record time (around line 88).

### B.5 check-team-conflict Empty Employee Code (#9)

**`scripts/check-team-conflict.sh`**: add early guard after line 41 — fail explicitly if `$agent_code` is empty.

### B.6 Secret Scan Output Validation (#10)

**`scripts/run-secret-scan.sh`**: after line 153, verify `$output_file` exists and is non-empty before proceeding to schema validation.

### B.7 repos.json Toolchain Section (#11)

**`repos.json`**: add toolchain for SHRED:
```json
"toolchain": {
  "install": "npm ci",
  "typecheck": "npx tsc --noEmit",
  "lint": "npx eslint .",
  "lint_fix": "npx eslint --fix . && npx prettier --write .",
  "format_check": "npx prettier --check .",
  "test": "npm test",
  "integration_test": null,
  "build": null
}
```

### B.8 Schema Validation (#12) — ALREADY RESOLVED

AJV bundle exists at `scripts/ajv-bundle.js`, validator already uses it. Verify with test run.

### B.9 Regression Guard Skipped Post-Conflict (#13)

**`.claude/rules/workflow.md`**: clarify that after Conflict Resolution Agent resolves, re-run `conflict-resolution.sh` to produce fresh CONFLICT.json with actual guard results (not "skipped").

---

## Phase C: Medium-Priority Hardening (#14-19) — DONE

### C.1a Timeout Integration (#14a)
- `pr-monitor-poll.sh:33` — wrap `gh pr view` in with-timeout.sh
- `check-team-conflict.sh:51,72` — wrap `git fetch` and `gh pr list`
- `abort-run.sh:52,54` — wrap `gh pr list` and `gh pr close`

### C.1b Surface All Configurable Env Vars (#14b)

Scripts already support these env vars but they're not in `.env` or `.env.example`. Add them with documented defaults:

```
# === Timeouts (seconds) ===
AGENT_COMMAND_TIMEOUT=        # Global override for all timeouts (leave blank to use per-command defaults)
AGENT_TSC_TIMEOUT=120         # TypeScript compilation
AGENT_TEST_TIMEOUT=300        # Test suite execution
AGENT_INSTALL_TIMEOUT=300     # Dependency install (npm ci, etc.)
AGENT_GITLEAKS_TIMEOUT=120    # Secret scan
AGENT_GREP_TIMEOUT=30         # Orphan check grep operations

# === Retry Limits ===
AGENT_MAX_TASK_RETRIES=2      # Max retries per failed task before escalation

# === Locking ===
AGENT_LOCK_TIMEOUT=10         # File lock acquisition timeout
```

Also update `check-loop-limit.sh` to read max iterations from env vars with fallback to the arg value:
- `AGENT_MAX_CRITIC_ROUNDS=3`
- `AGENT_MAX_PR_FEEDBACK_ROUNDS=5`

### C.2 Exit Code Inconsistency (#15)
- `conflict-resolution.sh:5` — update comment to remove unused exit 3

### C.3 output.sh Subshell Issue (#16)
- `output.sh` — document that emit_error must not be called inside `$()`. Provide caller pattern.

### C.4 Unicode Branch Names (#17)
- `generate-branch-name.sh:35` — add `iconv -t ASCII//TRANSLIT` before sed, or add explanatory comment.

### C.5 PR Size Per-Repo Threshold (#18)
- `check-pr-size.sh:28` — accept optional project_key arg, read threshold from repos.json. Fallback to env var.
- `repos.json` — add optional `pr_size_threshold` per repo.

### C.6 Worktree Init Checkout Failure (#19)
- `worktree-init.sh:141` — replace `2>/dev/null || true` with warning on failure.

---

## Phase D: Low-Medium Polish (#20-25) — DONE

### D.1 bc in Preflight (#20) — soft warning, not hard fail
### D.2 Orphan Check grep -F (#21) — use `grep -rlF` for file path matching
### D.3 pr-monitor-poll.sh Error Messages (#22) — addressed in A.2
### D.4 abort-run.sh PR Number Validation (#23) — regex check `^[0-9]+$`
### D.5 Agent Learning Empty (#24) — Run Analyst never invoked

Confirmed via run.log: zero analyst/learning entries across all 5 runs. POST-MERGE does Jira transition + summary but skips Run Analyst entirely. The workflow doc specifies it but orchestrator doesn't execute it.

**Fix:** Ensure POST-MERGE in `.claude/rules/workflow.md` and `.claude/commands/start.md` explicitly invoke Run Analyst after cleanup:
1. `scripts/agent-learning.sh gather {ticket_id}`
2. Invoke Run Analyst agent with gathered artifacts + current AGENT_LEARNING.json
3. `scripts/agent-learning.sh increment-runs`
4. `scripts/agent-learning.sh lifecycle {ticket_id}`
5. `scripts/agent-learning.sh escalate` — notify if persistent patterns
### D.6 Concurrency Safety (#25) — fix flock.sh EXIT trap stacking

---

## Phase E: Low-Priority (#26-28)

### E.1 flock.sh return/exit (#26) — save/restore EXIT trap
### E.2 with-timeout.sh macOS warning (#27) — emit warning when gtimeout missing
### E.3 Rate limit PAT format (#28) — addressed in A.2

---

## Verification Plan

1. **Phase A**: Run a dry-run on a SHRED ticket. Verify: PR gets assignee, no rate limit exhaustion, parse-args fails cleanly on malformed JSON, merge --abort called on conflicts
2. **Phase B**: Run orphan-check on a repo with base-only renames. Verify no false positives. Run preflight with JIRA_PAT only. Verify Jira reachable.
3. **Phase C**: Kill a gh command mid-execution. Verify timeout fires and logs properly.
4. **Phase D-E**: Run existing test suite (`tests/*.test.sh`). Verify all pass.
5. **End-to-end**: Full run on a real SHRED ticket. Compare retry count, cycle time, and METRICS.json against SHRED-3277 baseline.

---

## Resolved Questions

All resolved. For rate limit: diagnose root cause by capturing raw `gh` stderr (fix in A.2a). For GraphQL thread IDs: add query to pr-monitor to fetch thread node IDs from PR comments (fix in A.1b).
