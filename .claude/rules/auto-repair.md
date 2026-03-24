# Auto-Repair System

Handles **tool/environment failures** (not behavioural mistakes — those are Agent Learning).

## In-Run Repair Loop

When an agent operation fails:

```
1. Track failure: `scripts/auto-repair.sh track-failure {ticket} {agent} {operation}`
2. If consecutive_failures == 1:
   → Lookup: `scripts/auto-repair.sh lookup {agent} {operation} "{error_output}"`
   → If found + confidence != failed: try the alternative
     → Success: `scripts/auto-repair.sh record ...` (updates occurrences + confidence)
     → Failure: `scripts/auto-repair.sh mark-failed {repair_id}`
   → If not found: retry once with agent self-reasoning about the error
     → Success: `scripts/auto-repair.sh record ...` (creates new entry, confidence: low)
     → Failure: ESCALATE
3. If consecutive_failures >= 2: ESCALATE (do not keep retrying)
4. On success at any point: `scripts/auto-repair.sh reset-failure {ticket} {agent} {operation}`
```

## Confidence Lifecycle

| Confidence | Meaning | Behaviour |
|---|---|---|
| `low` | First experimental fix | Used if no better match |
| `medium` | 1-2 successes | Preferred over low |
| `high` | 3+ successes | Always tried first |
| `failed` | Alternative also failed | **Skipped** — go straight to self-reasoning |

## Rules

- Never increment failure counter for rate limit retries (those use `retry-with-backoff.sh`)
- Knowledge base is read at startup and consulted on every failure
- Successful alternatives are always recorded back to `REPAIR_KNOWLEDGE.json`
- Failed alternatives are marked `failed` immediately — no second chances
