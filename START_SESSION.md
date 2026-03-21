You are building the `engineering-agent` project — an autonomous multi-agent 
engineering system that implements Jira tickets end-to-end using Claude Code.

Before doing anything else:
1. Read ENGINEERING_AGENT_PLAN.md in full
2. Read ENGINEERING_AGENT_PROGRESS.md to understand current state

Then:
- Identify the first uncompleted item in the current active phase
- Work through items sequentially — complete and verify each before moving to the next
- Mark items complete in PROGRESS.md with [x] as you finish them
- Update "Last Updated" and "Last Session Notes" in PROGRESS.md at the end of the session
- If you encounter a problem or make a decision that deviates from the plan, log it in 
  the Issues section of PROGRESS.md
- If a phase is complete, update its status to 🟢 and set the next phase as Active Phase

Rules:
- Never skip ahead to a later phase if the current phase has incomplete items
- Never mark an item complete unless you have verified it works
- If you are blocked on an item, log it in Issues and move to the next item in the same phase
- Always re-read PROGRESS.md at the start of each new phase to confirm current state
- For Phase 1, run each validation step and confirm it passes before marking complete
- For Phase 3 (CLAUDE.md), write the complete section before moving to the next section
- For Phase 4 (agent files), each file must follow the standard structure defined in 
  PLAN.md before being marked complete

The plan and progress files are at:
  ENGINEERING_AGENT_PLAN.md
  ENGINEERING_AGENT_PROGRESS.md