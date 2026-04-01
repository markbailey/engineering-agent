# Workflow Definition

```
Orchestrator receives: TICKET-ID or FILE-PATH (provided externally)

  → Startup: read REPAIR_KNOWLEDGE.json + AGENT_LEARNING.json
  → Startup: scan for orphaned worktrees (report to human, non-blocking)

  → TICKET INTAKE
      → Run `scripts/check-team-conflict.sh {ticket_id} --target-repo={repo_path} --github-repo={github_repo}` — detect existing human work
          → Conflict found: ESCALATE (do not start competing branch)
      → If input_source == "local":
          → Construct ticket_data from local JSON (already validated by parse-args.sh)
          → Skip Jira Agent (validate, full_parse, dependency_check)
          → Log linked_issues as warning if present (not resolved)
          → If active worktree exists: resume existing run
          → Proceed to PLANNING
      → If input_source == "jira":
          → Jira Agent: fetch ticket, validate (see Ticket Intake Rules)
          → If invalid/blocked/unsupported: STOP with reason
          → If active worktree exists: resume existing run
          → Jira Agent: full parse — requirements, acceptance criteria, linked issues
          → Dependency check (blocked-by links + PR status)
              → Blocked: comment, transition ticket to Blocked, STOP
              → Dependency PR ready: record dependency branch
              → Clear: proceed

  → PLANNING
      → Planner Agent: generate PRD.json (worktree paths, branches, tasks, dependencies)

  → WORKTREE SETUP
      → Run `scripts/worktree-create.sh {branch} {base_branch} --target-repo={repo_path} --repo-name={repo_name}`
      → Run `scripts/worktree-init.sh {wt_path} {repo_path}` — copies env, installs deps, tsc check
      → If init exit 2: ESCALATE (broken base branch)
      → If init exit 1: trigger auto-repair, retry once, then ESCALATE

  → IMPLEMENTATION (Task Queue Algorithm)
      → Process tasks in dependency order:
          → Skip task if status != pending
          → Skip task if any dependency task status != verified
          → Set task status to in_progress in PRD.json
          → Developer Agent: implement task (inside worktree)
          → QA Agent: per-task verification (auto-fix → tsc → lint → format → unit tests)
          → If QA fails: `scripts/check-retry-limit.sh {ticket} {task} increment`
              → Retries remaining: retry Developer Agent
              → Exhausted (2 retries): ESCALATE with test output
          → Set task status to verified → next task

  → FULL QA
      → QA Agent: full suite (auto-fix → tsc → lint → format → unit → integration tests)

  → CONFLICT RESOLUTION
      → Run `scripts/conflict-resolution.sh {wt_path} {base_branch} {feature_branch} {ticket} --prd runs/{ticket}/PRD.json`
          → Exit 0 (clean): no conflicts, guards passed — proceed
          → Exit 1 (conflicts or guard issues):
              → If conflicts: Conflict Resolution Agent resolves file by file using PRD.json
                  → After resolution: `git add . && git commit` to complete merge
                  → Re-run `scripts/conflict-resolution.sh` to produce fresh CONFLICT.json with actual guard results
              → If guard/orphan issues: Conflict Resolution Agent attempts one fix round
                  → Re-run guards after fix
                  → Still failing: ESCALATE
          → Exit 2 (escalate): disconnected integrations or merge error — ESCALATE
      → QA Agent: re-verify after merge (full suite)

  → INTERNAL REVIEW
      → `scripts/check-loop-limit.sh {ticket} critic_review 3 increment`
      → The Critic: full review (ticket + PRD + diff + tests + CONFLICT.json) → REVIEW.json
          → Critical/high/medium issues found:
              → Developer Agent resolves
              → QA Agent re-verifies
              → Conflict Resolution re-run
              → The Critic re-reviews (loop limit enforced by check-loop-limit.sh)
              → Loop exhausted (3 rounds): ESCALATE
          → Clean (or low-severity only): proceed

  → SECRET SCAN
      → Run `scripts/run-secret-scan.sh {worktree} {base_branch} {ticket}`
          → Findings: SECRETS.json generated, `scripts/update-prd-status.sh {ticket} blocked_secrets`, HARD BLOCK, STOP
          → Clean: proceed

  → PR SIZE CHECK
      → Run `scripts/check-pr-size.sh {worktree} {base_branch}`
          → Over threshold: pause, notify human for approval, wait for explicit approval, then continue
          → Under threshold: proceed

  → PR CREATION
      → Run `scripts/check-branch-before-push.sh {worktree}` — final push safety check
      → PR Agent: open PR as draft, write description
          → Pass `current_github_user` (from preflight output) in PR Agent context
          → If input_source == "jira": link Jira, update Jira to "In Review"
          → If input_source == "local": omit Jira link, skip Jira transition
      → Exception: if --ready-pr flag was passed, mark as ready for review

  → PR MONITORING (polling loop — runs until terminal state)
      → Set overall_status: "pr_monitoring"
      → Loop:
          → Poll: `scripts/pr-monitor-poll.sh {ticket_id} {pr_number} {AGENT_PR_MONITOR_INTERVAL}`
          → If no change from last poll: sleep {AGENT_PR_MONITOR_INTERVAL} (default 1200s / 20 min, configurable via AGENT_PR_MONITOR_INTERVAL), continue loop
          → If change detected: invoke PR Monitor Agent with full context
          → Route on action_required:
              → "none": continue loop
              → "ci_passed_draft": PR Agent action=ready → mark PR ready for review
              → "address_feedback":
                  → `scripts/check-loop-limit.sh {ticket} pr_feedback 5 increment`
                  → Generate FEEDBACK.json
                  → Developer Agent resolves
                  → QA re-verify
                  → Conflict Resolution re-run
                  → The Critic re-reviews (if code changes)
                  → `scripts/check-branch-before-push.sh {worktree}` before push
                  → PR Agent pushes updates
                  → PR Agent action=resolve_feedback → reply to each addressed comment and resolve thread. For wont_fix items, reply with reason and resolve.
                  → If stalled or conflicting feedback: ESCALATE
                  → Continue loop
              → "conflict_resolution":
                  → Run `scripts/conflict-resolution.sh {wt_path} {base_branch} {feature_branch} {ticket}`
                  → Handle exit codes per CONFLICT RESOLUTION workflow above
                  → QA Agent: re-verify (full suite)
                  → `scripts/check-branch-before-push.sh {worktree}` before push
                  → PR Agent pushes merge commit
                  → Continue loop
              → "dependency_merged":
                  → Note: GitHub auto-retargets PR to main when dependency branch is deleted on merge
                  → Run `scripts/conflict-resolution.sh {wt_path} main {feature_branch} {ticket}`
                  → Update PRD.json: base_branch → main, base_is_dependency → false
                  → QA Agent: re-verify (full suite)
                  → `scripts/check-branch-before-push.sh {worktree}` before push
                  → PR Agent pushes merge commit
                  → Continue loop
              → "approved":
                  → If --auto-merge flag set: PR Agent action=merge → `gh pr merge --auto --merge`
                  → Else: notify human, continue loop
              → "merged": break loop → POST-MERGE
              → "escalate": ESCALATE, break loop
          → If --pause/--stop received: break loop at safe checkpoint

  → POST-MERGE (PR Monitor detects state: "MERGED" via gh pr view --json state)
      → If input_source == "jira": Jira Agent: transition ticket to Done
      → Cleanup worktrees (all repos)
      → Archive artefacts to /runs/TICKET-ID/
      → `scripts/run-summary.sh {ticket_id} {status} {tasks_total} {tasks_completed} [pr_url]`
      → Run Analyst: analyse last N runs for patterns → update AGENT_LEARNING.json
          → Persistent patterns: escalate to human
```
