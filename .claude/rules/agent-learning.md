# Agent Learning System

## Overview

Detects recurring **behavioural mistakes** across multiple runs. Separate from auto-repair (which handles tool/environment failures).

## Startup

Read `AGENT_LEARNING.json` at startup. For each agent invocation, run `scripts/agent-learning.sh filter {agent}` to get standing instructions for injection into context.

## Standing Instruction Injection

At invocation time:

```bash
scripts/agent-learning.sh filter {agent-name}
# Returns JSON with instructions array — append to agent context package
```

Format in agent context:
```
STANDING INSTRUCTIONS (learned from previous runs):
1. {instruction from entry 1}
2. {instruction from entry 2}
```

## Run Analyst Invocation

Invoked at end of every **completed** run (reached PR stage or escalation):

```bash
# 1. Gather artefacts from last N runs
scripts/agent-learning.sh gather {ticket_id}

# 2. Invoke Run Analyst agent with gathered artefacts + current AGENT_LEARNING.json

# 3. Run Analyst produces updated AGENT_LEARNING.json entries
#    For each new pattern: scripts/agent-learning.sh write {agent} {pattern} {source} {instruction}

# 4. Increment run counter for all active/resolved entries
scripts/agent-learning.sh increment-runs

# 5. Process lifecycle transitions
scripts/agent-learning.sh lifecycle {ticket_id}

# 6. Check for persistent escalations
scripts/agent-learning.sh escalate
# If escalation_count > 0: notify human via scripts/notify.sh
```

Analyses rolling window of last N runs (`AGENT_LEARNING_WINDOW` env var, default 5).

**What it analyses:**

| Source | Pattern |
|---|---|
| `REVIEW.json` | Same issue type flagged at high+ severity, 2+ times |
| `FEEDBACK.json` | Same feedback category from reviewers across tickets |
| `run.log` | Same QA failure type recurring |
| `PRD.json` | Planner consistently missing same task category |
| `REVIEW.json prd_adherence` | Developer consistently deviating from PRD |

**Detection threshold:** 2+ occurrences across last N runs for same agent.

## Status Lifecycle

| Status | Meaning |
|---|---|
| `active` | Standing instruction injected every run |
| `resolved` | Not recurred for 5 clean runs — instruction still injected |
| `persistent` | Recurred 2+ times after instruction added — ESCALATE to human |

Managed via `scripts/agent-learning.sh lifecycle {ticket_id}` at end of each run.
