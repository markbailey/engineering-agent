# Commit Message Convention

## Standard

All commits follow **Conventional Commits** (`conventionalcommits.org`).

## Format

```
{type}({scope}): {short description}

{optional body — what and why, not how}

{optional footer — breaking changes, ticket reference}
```

## Commit Types

| Type | When used |
|---|---|
| `feat` | New feature or behaviour |
| `fix` | Bug fix |
| `refactor` | Code change — not a fix, not a feature |
| `test` | Adding or updating tests |
| `chore` | Maintenance — deps, config, tooling |
| `debt` | Tech debt reduction |
| `perf` | Performance improvement |
| `docs` | Documentation only |
| `ci` | CI/CD changes |

## Ticket Reference

Every Developer Agent commit includes Jira ticket in footer:
```
feat(auth): add jwt expiry validation

Validates token expiry and returns 401 if expired.

Refs: PROJ-123
```

## Granularity

- **One commit per PRD.json task** — atomic, traceable, reviewable
- **Auto-fix commits** are separate: `chore: auto-fix formatting and lint [QA]`
- **Merge commits** use git's default message
- **Feedback round commits** follow same convention — type reflects what changed

## Breaking Changes

Document in commit footer:
```
BREAKING CHANGE: validateToken is no longer exported. Use verifyToken instead.
Refs: PROJ-123
```

The Critic flags undocumented breaking changes at **high** severity.

## Claude Co-Authorship

Every commit produced by the workflow — Developer Agent task commits, QA auto-fix commits, conflict-resolution merges, revert commits — is attributed to Claude as a co-author via the trailer:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```

Enforcement is automatic: `scripts/worktree-init.sh` installs a per-worktree `prepare-commit-msg` hook (via `scripts/install-coauthor-hook.sh`) that idempotently appends the trailer using `git interpret-trailers --if-exists doNothing`. Agents do not need to add the trailer manually — the hook handles every commit source (message, template, merge, squash, amend).

The hook lives in the worktree's per-worktree git-dir (`.git/worktrees/<name>/hooks/prepare-commit-msg`) so it applies only to agent worktrees and never to a human's personal checkout of the same repo.

If the target repo's local config has `core.hooksPath` set (e.g., for Husky), git would normally redirect hook lookup away from our per-worktree folder and the trailer would be silently dropped. The installer detects this via `git rev-parse --git-path hooks` and, when an override is present, enables `extensions.worktreeConfig` on the shared repo and pins `core.hooksPath` at per-worktree scope so our hook still runs. This is scoped to the agent worktree only — the user's personal checkout is not modified.

## Commit Validation

QA Agent validates every Developer Agent commit against this convention before marking task complete. Invalid → rejected, Developer Agent rewrites.
