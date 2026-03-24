# Secret Scanning Rules

## Gate

Runs once, between Critic approval and PR Agent. Not on every push.

## Flow

```
The Critic approves → Secret Scanner: gitleaks on full diff
  → Clean: proceed to PR Agent
  → Finding(s):
      → Generate SECRETS.json (file, line, type — NEVER the value)
      → HARD BLOCK — do not open PR
      → Notify human with SECRETS.json
      → Set PRD.json overall_status: "blocked_secrets"
      → STOP — human must remediate
```

## Rules

- **Hard block — no exceptions** — no PR opens if findings exist
- **Never auto-fix** — do not remove secrets, rewrite history, or rotate credentials
- **Never log secret values** — SECRETS.json, run.log, notifications contain file/line/type only
- **Diff only** — git history not scanned
- **Resumable** — after human remediates, workflow re-runs from secret scan step
