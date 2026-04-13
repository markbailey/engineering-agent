---
name: create-ticket
description: 'Create a well-structured Jira ticket optimized for the autonomous multi-agent engineering system. Interactive — guides the user through requirements gathering, then creates the ticket via Jira API. Args: [--local] [--type=Task|Bug]'
---

# /create-ticket — Jira Ticket Builder for Autonomous Agents

Guide the user through creating a Jira ticket (or local JSON file) that contains enough context for the multi-agent engineering system to produce accurate results — from planning through implementation, QA, review, and PR creation.

**Input:** `$ARGUMENTS`

---

## Step 0: Parse Arguments & Resolve Repo

Extract from `$ARGUMENTS`:

- `--local` flag — output a local JSON file instead of creating a Jira ticket
- `--type=TYPE` — preset ticket type (Task or Bug). If omitted, ask the user.

### Fixed project context

All tickets target the **AXO471** repo. The Jira project key is resolved from `repos.json` — read `repos.json` to find the project key that maps to the `AXO471` repo entry, and use that as `PROJECT_KEY` for the ticket.

The repo's local path is also in `repos.json` under the `path` field. Read it at the start so you can help the user identify files and modules during the interview (Group 2, question 5). If the user is unsure which files are affected, use the repo path to browse the codebase and suggest likely candidates.

---

## Step 1: Gather Context via Interview

Ask the user the following questions **one group at a time** (do not dump all questions at once). Adapt follow-up questions based on answers. Skip questions that are already answered from arguments or prior context.

### Group 1: What and Why

Ask:
1. **What do you want to build or fix?** (one sentence)
2. **Why is this needed?** (business context, user impact, or technical motivation)
3. **Ticket type** — is this a new feature or technical task (Task), or a bug fix (Bug)?
4. **(Bug type only) Do you have any screenshots showing the issue?** (paste images, provide file paths, or skip). Use the Read tool to view any provided images. Extract concrete details from them — error messages, incorrect UI state, console errors, network responses — and incorporate these into the requirements and reproduction steps. Reference what the screenshots show in the description (e.g. "Screenshot shows 500 error in network tab when submitting the form").

From the answers, draft a **title** (concise, under 80 chars, action-oriented — e.g. "Add JWT expiry validation to auth middleware") and a **requirements summary**. Present both to the user for confirmation before continuing.

### Group 2: Detailed Requirements

Ask:
4. **Walk me through the expected behavior.** What should happen step-by-step from the user's or system's perspective? Include:
   - Input → processing → output
   - Edge cases and error scenarios
   - Any specific business rules or constraints
5. **What existing code or systems does this touch?** (files, modules, services, APIs, database tables — be specific). If the user is unsure, run the **Parallel Codebase Exploration** (see below) to identify affected files. If the user names something vague like "the auth module", use the exploration results to resolve it to actual file paths.
6. **Are there any constraints?** (backwards compatibility, performance requirements, specific libraries to use or avoid, security considerations)

If the user gives vague answers, probe deeper. The system's Developer Agent implements exactly what is specified — ambiguity causes incorrect output. Specifically watch for:
- **Vague verbs:** "handle", "manage", "process" — ask what specifically that means
- **Implicit knowledge:** "the usual auth flow" — ask them to spell it out
- **Missing error cases:** "validate the input" — ask what happens when validation fails
- **Unspecified scope:** "update the API" — ask which endpoints, which fields, what changes

#### Parallel Codebase Exploration

After the user answers questions 4-6 (or provides enough context from Group 1 to identify the feature area), launch **three sub-agents in parallel** using the Agent tool. All three must be dispatched in a single message so they run concurrently. Use the repo path from `repos.json` as the search root.

**Agent 1 — Component Locator** (`model: haiku`, `subagent_type: Explore`)
- **Goal:** Find the specific files and components the user described
- **Prompt context:** Pass the user's description of what they want to build/fix and any file/module names they mentioned
- **Search strategy:** Glob for likely file patterns, Grep for component names, class names, function names, UI text
- **Output:** List of exact file paths with a one-line description of each file's role

**Agent 2 — Dependency Tracer** (`model: sonnet`, `subagent_type: Explore`)
- **Goal:** From the feature area the user described, trace imports, exports, consumers, and upstream/downstream dependencies to map the blast radius
- **Prompt context:** Pass the user's description plus any file/module names they mentioned
- **Search strategy:** Find the core files, then read imports/exports, grep for usages across the codebase, identify connected services or APIs
- **Output:** Dependency map — which files import the affected code, which services/APIs are upstream/downstream, potential side effects

**Agent 3 — Test & Pattern Scout** (`model: haiku`, `subagent_type: Explore`)
- **Goal:** Find existing tests for the affected code, and similar patterns elsewhere in the codebase that could inform the approach or acceptance criteria
- **Prompt context:** Pass the user's description plus any file/module names they mentioned
- **Search strategy:** Glob for test files near affected code (`*.test.*`, `*.spec.*`, `__tests__/`), grep for test descriptions mentioning the feature, search for similar implementations in other parts of the codebase
- **Output:** List of relevant test files, what behaviors they cover, and any similar patterns found elsewhere

**Merging results:** After all three agents return, synthesize their findings into:
1. A consolidated list of **affected files** (from Locator + Dependency Tracer) — present to the user for confirmation
2. **Blast radius summary** (from Dependency Tracer) — highlight any surprising dependencies the user may not have considered
3. **Test coverage gaps** (from Test Scout) — use these to suggest additional acceptance criteria in Group 3
4. **Similar patterns** (from Test Scout) — reference these when helping the user write requirements ("there's a similar toolbar in X that handles this by...")

Present the merged findings to the user as part of question 5, and use them to enrich the Technical Context section of the ticket.

### Group 3: Acceptance Criteria

This is the most critical section. The Critic agent verifies every criterion, and tasks map 1:1 to criteria. Explain this to the user:

> Each acceptance criterion becomes a task for the Developer Agent — one commit per criterion. The Critic agent verifies every single one before the PR opens. Be specific and testable.

Ask:
7. **What are the acceptance criteria?** Help the user write them in this format:
   - Each criterion must be **independently testable** (the QA Agent runs tests per task)
   - Each criterion must be **specific and unambiguous** (the Developer Agent implements literally what is stated)
   - Each criterion should describe **one behavior or outcome** (maps to one commit)
   - Use the pattern: "Given [context], when [action], then [expected result]"

Guide the user to refine vague criteria. Transform statements like:
- "Authentication works" → "Given a valid JWT token, when a request is made to a protected endpoint, then the request succeeds with 200. Given an expired JWT token, when a request is made to a protected endpoint, then the response is 401 with error body `{ error: 'token_expired' }`."
- "Tests pass" → Not a criterion (tests are automatic). Ask what behavior the tests should verify.
- "Code is clean" → Not a criterion (the Critic handles code quality). Ask what functional outcome they want.

**Minimum 2 acceptance criteria.** If the user provides only 1, probe for edge cases, error handling, or integration points that need their own criterion.

### Group 4: Dependencies and Context (optional)

Ask:
8. **Does this depend on any other tickets or PRs?** (the system checks "blocked by" links and waits for dependencies)
9. **Are there any related tickets?** (for linked_issues — logged as warnings)
10. **Who should review the PR?** (GitHub usernames — merged with repo-level reviewers from repos.json)
11. **Any breaking changes expected?** (the system documents these in commit footers and the PR)

---

## Step 2: Compose the Ticket

Assemble the ticket from gathered information.

### Title
- Under 80 characters
- Action-oriented: starts with a verb (Add, Fix, Update, Remove, Refactor)
- Specific: mentions the component/feature

### Description (Requirements)

**IMPORTANT: Jira uses wiki markup, NOT Markdown.** The description sent via the REST API v2 must use Jira wiki notation. Markdown syntax (`##`, `-`, `**`) will render as plain text.

Structure the description in this exact format using **Jira wiki markup** (the Jira Agent and Planner Agent parse this):

```
h2. Summary

{2-3 sentences: what this does and why}

h2. Requirements

* {Requirement 1 — specific, actionable}
* {Requirement 2 — specific, actionable}
* {Error handling / edge cases}
* {Constraints and boundaries}

h2. Technical Context

* Affected files:
** {file path 1}
** {file path 2}
* Related services: {upstream/downstream dependencies}
* Database: {any schema changes}
* API changes: {any endpoint modifications}

h2. Constraints

{Performance, compatibility, security, library constraints}

h2. Breaking Changes

{None | Description of what breaks and migration path}

Reviewers: {comma-separated GitHub usernames}
```

**Jira wiki markup quick reference:**
| Markdown | Jira wiki markup |
|---|---|
| `## Heading` | `h2. Heading` |
| `### Heading` | `h3. Heading` |
| `- bullet` | `* bullet` |
| `  - nested bullet` | `** nested bullet` |
| `1. numbered` | `# numbered` |
| `` `inline code` `` | `{{inline code}}` |
| `**bold**` | `*bold*` |
| `_italic_` | `_italic_` |
| ` ``` code block ``` ` | `{code}...{code}` |

### Acceptance Criteria
- Array of specific, testable criteria
- Each maps to one Developer Agent task and one commit
- Written in Given/When/Then or equivalent testable format

### Type
- `Task` — new feature, behavior or technical work (refactoring, infrastructure, config)
- `Bug` — fixing incorrect behavior (include: steps to reproduce, expected vs actual)

For **Bug** type, ensure the requirements include:
- Steps to reproduce
- Expected behavior
- Actual behavior
- Environment/conditions where it occurs

---

## Step 3: Review with User

Present the complete ticket in a readable format:

```
=== TICKET PREVIEW ===

Title: {title}
Type: {type}
Project: {project_key}

--- Description ---
{full structured description}

--- Acceptance Criteria ---
1. {criterion 1}
2. {criterion 2}
...

--- Reviewers ---
{reviewers or "None specified (repo defaults will be used)"}

--- Dependencies ---
{blocked-by tickets or "None"}
```

Ask: "Does this look right? Anything to add, change, or remove?"

Iterate until the user confirms.

---

## Step 4: Quality Check

Before creating the ticket, verify internally:

| Check | Pass condition |
|---|---|
| Title length | Under 80 characters |
| Title is action-oriented | Starts with a verb |
| Type is valid | Task or Bug |
| Requirements are specific | No vague verbs ("handle", "manage") without clarification |
| Acceptance criteria count | At least 2 |
| Each criterion is testable | Describes a specific behavior/outcome, not a process |
| Each criterion is atomic | One behavior per criterion (mappable to one commit) |
| Error cases covered | At least one criterion covers an error/edge case |
| Technical context present | Files or modules mentioned |
| Bug has repro steps | (Bug type only) Steps, expected, actual are present |
| Breaking changes stated | Explicitly "None" or described |

If any check fails, suggest improvements to the user before proceeding.

---

## Step 5: Create the Ticket

### If `--local` flag is set:

Generate a JSON file conforming to `schemas/local-ticket.schema.json`:

```json
{
  "ticket_id": "{PROJECT_KEY}-{next_number}",
  "title": "{title}",
  "type": "{Task|Bug}",
  "requirements": "{full structured description as a single string}",
  "acceptance_criteria": ["{criterion 1}", "{criterion 2}"],
  "repo": "{PROJECT_KEY}",
  "components": [],
  "labels": [],
  "linked_issues": ["{PROJ-XXX}"]
}
```

Use the project key from `repos.json` that maps to the AXO471 repo for `ticket_id` and `repo`. Ask the user for the ticket number (since there is no Jira to auto-assign). Write the file to `./tickets/{ticket_id}.json`. Validate it against the schema using `node scripts/validate-schemas.js schemas/local-ticket.schema.json tickets/{ticket_id}.json`.

Report the file path and how to run it:
```
Ticket written to: tickets/{ticket_id}.json
Run with: /start tickets/{ticket_id}.json
Dry run: /start tickets/{ticket_id}.json --dry-run
```

### If creating a Jira ticket:

**Verify Jira credentials are configured** — check that `JIRA_URL`, `JIRA_EMAIL`, and `JIRA_API_TOKEN` (or `JIRA_PAT`) are set in `.env`. If not, offer to fall back to `--local` mode.

**Resolve custom field IDs** (first run only — cache the IDs for subsequent calls):

```bash
source .env

# Find the custom field IDs for Technology and Team()
curl -s "${JIRA_URL}/rest/api/2/field" \
  -H "Authorization: Basic $(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)" \
  | jq '.[] | select(.name == "Technology" or .name == "Team()") | {name, id}'
```

Replace `customfield_XXXXX` (Technology) and `customfield_YYYYY` (Team()) in the payload below with the actual IDs returned.

Create the Jira ticket using the Jira REST API:

```bash
source .env

# Create the ticket
curl -s -X POST \
  "${JIRA_URL}/rest/api/2/issue" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)" \
  -d '{
    "fields": {
      "project": { "key": "{PROJECT_KEY}" },
      "summary": "{title}",
      "issuetype": { "name": "{type}" },
      "description": "{structured description in Jira wiki markup — h2. for headings, * for bullets, ** for nested bullets, # for numbered lists}",
      "labels": [{labels}],
      "customfield_XXXXX": { "value": "Frontend" },
      "customfield_YYYYY": { "value": "Shred Squad 03" }
    }
  }'
```

After creation:
1. Extract the ticket key from the response (e.g. `PROJ-456`)
2. If there are "blocked by" dependencies, create issue links:
   ```bash
   curl -s -X POST "${JIRA_URL}/rest/api/2/issueLink" \
     -H "Content-Type: application/json" \
     -H "Authorization: Basic ..." \
     -d '{"type":{"name":"Blocks"},"inwardIssue":{"key":"{blocker}"},"outwardIssue":{"key":"{new_ticket}"}}'
   ```
3. Report the ticket:
   ```
   Ticket created: {PROJ-456}
   URL: {JIRA_URL}/browse/{PROJ-456}
   Run with: /start {PROJ-456}
   Dry run: /start {PROJ-456} --dry-run
   ```

---

## Anti-Patterns to Catch

During the interview, actively steer the user away from these common problems that cause agent failures:

| Anti-pattern | Why it fails | What to do |
|---|---|---|
| "Make it work like X" (with no specification) | Developer Agent has no context on X | Ask user to describe the behavior explicitly |
| Single vague acceptance criterion | Maps to one under-specified task | Break into multiple specific criteria |
| Implementation instructions instead of requirements | Over-constrains the Planner, may not match codebase | Capture as constraints, let requirements describe behavior |
| Missing error/edge cases | Developer Agent only implements what is specified | Probe for failure modes |
| Scope too large (10+ acceptance criteria) | PR becomes huge, review is slow, conflicts likely | Suggest splitting into multiple tickets |
| "Refactor everything" | Unbounded scope, no testable outcome | Ask for specific refactoring goals with measurable criteria |
| No technical context | Planner Agent guesses file impacts | Ask which files/modules are involved |
| Ambiguous pronouns ("it should update it") | Developer Agent may pick the wrong "it" | Ask user to use specific names |

---

## Tips for the User

If the user asks for guidance, share these tips:

1. **Be specific about behavior, not implementation** — say "return 401 when token is expired" not "add an if statement to check the token"
2. **One ticket = one PR** — if the work touches more than ~8 files or has 6+ acceptance criteria, consider splitting
3. **Error cases are first-class criteria** — the agent only handles errors you specify
4. **Technical context saves time** — naming the files and modules up front helps the Planner produce accurate `files_affected`
5. **The agent reads exactly what you write** — there is no "obvious" behavior. If you want it, specify it.
