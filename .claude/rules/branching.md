# Branching Rules

## Format

```
{employeecode}_{issue-id}_{description}_{branch-type}
```

All lowercase. Spaces → hyphens. No special characters. Description truncated to 40 chars at word boundary.

## Employee Code

Read from `AGENT_EMPLOYEE_CODE` in `.env`. If missing or empty: **hard stop** before creating any branch.

## Branch Type Mapping

| Jira Issue Type | Branch Type |
|---|---|
| Story | `feature` |
| Task | `feature` |
| Bug | `bug` |
| Defect | `defect` |
| Technical Debt | `debt` |
| Chore | `chore` |
| Unknown / unmapped | `feature` |

## Validation

Before creating any branch, validate against format. If invalid: ESCALATE, never create a malformed branch.

## Protected Branches

Never push to, merge into, or operate directly on: `main`, `master`, `staging`.
