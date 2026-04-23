# Worktree Management

## Repo Resolution

Target repo is resolved from `repos.json` via the Jira project key (e.g., `SHRED-123` → `SHRED` → `AXO471`).

`parse-args.sh` outputs: `project_key`, `repo_name`, `repo_path`, `github_repo` — these are passed to all downstream scripts via `--target-repo=PATH`, `--repo-name=NAME`, `--github-repo=OWNER/REPO` flags.

## Creation

At workflow start, after planning:

```bash
scripts/worktree-create.sh {branch} {base_branch} --target-repo={repo_path} --repo-name={repo_name}
```

- `base_branch` is `main` (default) or a dependency branch
- Worktree path: `~/.claude/worktrees/{repo_name}/{branch_name}`
- Multi-repo: one worktree per repo per ticket

## Initialisation Sequence

Mandatory before any agent work:

1. **Copy non-committable files** from source repo root to worktree:
   - Priority: explicit list in project CLAUDE.md > .gitignore pattern matches > known defaults
   - Known defaults: `.env`, `.env.*`, `*.local`, `*.pem`, `*.key`
   - Source: always from main repo checkout, never from another worktree
   - Strategy: `cp --preserve`, never overwrite existing (resume safety)

2. **Install dependencies:**
   - `npm ci` inside worktree (not `npm install` — avoids lockfile rewrites)
   - Never copy `node_modules` — always install fresh
   - After install: `git checkout -- .` to reset formatting drift from postinstall scripts
   - If fails: auto-repair system triggers

3. **Install commit hooks:**
   - `scripts/install-coauthor-hook.sh {wt_path}` — idempotently installs a per-worktree `prepare-commit-msg` hook that auto-appends `Co-Authored-By: Claude <noreply@anthropic.com>` to every commit message (task commits, QA auto-fix, merges, reverts)
   - Runs on every init (fresh or resumed) so resuming an older worktree picks up the hook
   - Failure is non-fatal (logged as a warning) — commits proceed but may miss the trailer

4. **Validate:**
   - Verify `.env` exists
   - Verify `node_modules` is non-empty
   - `tsc --noEmit` — baseline compile check
   - If compile fails: ESCALATE (base branch is broken, not our problem)

## Resumed Worktrees

If worktree exists on startup (interrupted run):
- Check `.env` — if missing, re-run step 1 only
- Check `node_modules` — if missing/empty, re-run step 2 only
- Always run `tsc --noEmit` baseline check before resuming

## Cleanup

Only on **confirmed merge** (PR Monitor verifies merge status):
- `scripts/worktree-cleanup.sh {ticket_id} --target-repo={repo_path} --repo-name={repo_name} --github-repo={github_repo}`
- Archive artefacts to `/runs/TICKET-ID/`
- Update `PRD.json overall_status` to `done`

## Rules

- One worktree per ticket per repo
- Path convention: `~/.claude/worktrees/{repo_name}/{branch_name}`
- Agent never operates outside its assigned worktree
- Never clean up on PR close/decline — may contain recoverable work
- Orphaned worktrees reported to human on startup, never auto-cleaned
