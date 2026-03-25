---
name: apply-repairs
description: 'Apply REPAIR_KNOWLEDGE.json fixes permanently to source files in this repo, create PR for review. Args: [--dry-run] [--min-confidence=low|medium|high]'
---

# /apply-repairs — Permanent Repair Application

Read `REPAIR_KNOWLEDGE.json`, apply each fix permanently to source files, verify, clean the JSON, and open a PR.

**Input:** `$ARGUMENTS`

---

## Step 1: Parse Arguments

Extract from `$ARGUMENTS`:

- `--dry-run` flag (report only, no changes)
- `--min-confidence=LEVEL` (default: `low`; options: `low`, `medium`, `high`)

Confidence hierarchy: high > medium > low. Entries with `failed` confidence are always excluded.

---

## Step 2: Read & Filter Entries

1. Read `REPAIR_KNOWLEDGE.json` from the project root.
2. If `entries` is empty → report "No repairs to apply" and STOP.
3. Exclude entries where `confidence == "failed"`.
4. Exclude entries below `--min-confidence` threshold (low=1, medium=2, high=3; keep entries >= threshold).
5. Report: "N entries to process (M filtered out)".

If no entries remain after filtering → report and STOP.

---

## Step 3: Create Worktree + Branch

**Skip this step entirely if `--dry-run`.**

1. Read `AGENT_EMPLOYEE_CODE` from `.env`. If missing → STOP with error.
2. Determine today's date as `YYYY-MM-DD`.
3. Branch name: `{EMPLOYEE_CODE}_apply-repairs-{YYYY-MM-DD}_chore`
4. Run: `scripts/worktree-create.sh {branch_name} main --target-repo=$(pwd) --repo-name=$(basename $(pwd))`
5. All subsequent file reads, edits, and commits happen **inside the worktree**.

---

## Step 4: Process Each Entry

For each filtered entry, in order:

### 4a. Resolve Target File(s)

1. Check if `scripts/{agent}.sh` exists. If yes → primary target.
2. If not found, check `agents/{agent}.md` and `agents/{agent}-agent.md`.
3. If `successful_alternative` names specific files, include those too.
4. If no target found → report "Cannot resolve target for {id}" and skip entry.

### 4b. Check If Fix Still Needed

Search target file(s) for the `failed_approach` pattern (literal string match or the `error_pattern` regex). Also use your judgement — read the file and determine whether the problem described in `failure_reason` still exists.

- If the problem no longer exists → report "{id}: already applied" and skip.

### 4c. Dry Run Output

If `--dry-run`: print for this entry and skip to next:

```
{id} | {agent}/{operation} | {target_file}
  Status: {still needed / already applied}
  Fix: {successful_alternative}
```

### 4d. Apply Fix

If not dry-run:

1. Read the target file(s) in the worktree.
2. Interpret `successful_alternative` and apply the permanent code change.
3. For `.sh` files: validate syntax with `bash -n {file}`.
4. Stage changed files and commit:
   ve` and apply the permanent code change.
5. For `.sh` files: validate syntax with `bash -n {file}`.
6. Stage changed files and commit:

   ```
   fix({agent}): {concise description derived from successful_alternative}

   Refs: {entry.id}
   ```

---

## Step 5: Verify & Clean JSON

**Skip if `--dry-run` or no entries were applied.**

For each entry that was applied in Step 4:

1. Re-read the target file(s) in the worktree.
2. Verify the `failed_approach` pattern is gone and the fix described in `successful_alternative` is present.
3. If verified → mark for removal from `REPAIR_KNOWLEDGE.json`.
4. If NOT verified → keep entry in JSON, report warning.

Then:

1. Read `REPAIR_KNOWLEDGE.json` in the worktree.
2. Remove all verified entries from `entries` array.
3. Increment `version`, update `last_updated` to now.
4. Write the updated JSON.
5. Commit: `chore: remove verified repairs from REPAIR_KNOWLEDGE.json`

---

## Step 6: Create PR

**Skip if `--dry-run` or no commits were made.**

1. Push the branch to origin.
2. Create PR via `gh pr create`:
   - Title: `chore: apply permanent repairs from REPAIR_KNOWLEDGE.json`
   - Body: list each repair entry applied (id, agent, operation, what was fixed)
   - Open as ready for review (not draft — these are mechanical fixes).

---

## Step 7: Summary

Print a results table:

```
| Entry     | Agent        | Operation  | Status              |
|-----------|--------------|------------|---------------------|
| repair-1  | orphan-check | grep       | applied + verified  |
| repair-2  | orphan-check | diff-scope | already applied     |
```

Possible statuses: `applied + verified`, `applied + unverified`, `already applied`, `skipped (no target)`, `skipped (failed confidence)`

If a PR was created, print the PR URL.
