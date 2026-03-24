# Agent Invocation Pattern

Every time you invoke an agent via the Task tool:

1. **Fresh read** the agent's `.md` file from `agents/` — never cache between invocations.
2. Filter `AGENT_LEARNING.json` entries where `agent` matches and `status` is `active` or `resolved`.
3. Append standing instructions to the context package:
   ```
   STANDING INSTRUCTIONS (learned from previous runs):
   1. {standing_instruction from entry 1}
   2. {standing_instruction from entry 2}
   ```
4. Assemble the context package (ticket data, PRD.json state, diffs, etc.) per agent's Context Contract.
5. Invoke via Task tool with: system prompt = agent .md content, input = context package + standing instructions.

## Agent Prompt Versioning

- At run start, record each agent's `.md` file version (from frontmatter) in `PRD.json.agent_versions`.
- On `--resume`, compare current versions against recorded versions.
- If mismatch: log warning, proceed (do not block).
