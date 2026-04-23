# Commit Message Convention

## Standard

All commits follow **Conventional Commits** (`conventionalcommits.org`).

## Format

```
{type}({scope}): {short description}

{optional body — what and why, not how}

{required footer for Developer Agent commits — Refs: TICKET-ID and any breaking changes; agent signature is recommended but not enforced by the validator}
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

Every Developer Agent commit includes a Jira ticket in the footer, optionally followed by the agent signature:
```
feat(auth): add jwt expiry validation

Validates token expiry and returns 401 if expired.

Refs: PROJ-123
{agent signature}
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
{agent signature}
```

The Critic flags undocumented breaking changes at **high** severity.

## Commit Validation

QA Agent validates every Developer Agent commit against this convention before marking task complete. Invalid → rejected, Developer Agent rewrites. Validation enforces commit type, description format, line length, and `Refs: TICKET-ID` footer. The agent signature is recommended but not currently enforced by the validator.
