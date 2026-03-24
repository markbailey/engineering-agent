# QA Pipeline

## Philosophy

Auto-fix before reporting. If a tool can fix it, fix it silently and commit. Only issues remaining after auto-fix are real failures.

## Verification Sequence

```
1. Auto-fix pass
    → prettier --write .
    → eslint --fix .
    → (project-specific fixers from repo config)
    → If changes: stage + commit as "chore: auto-fix formatting and lint [QA]"

2. TypeScript compilation
    → tsc --noEmit
    → Fail: back to Developer Agent with errors

3. Lint (no --fix — auto-fix already ran)
    → eslint .
    → Fail: back to Developer Agent

4. Formatting check (after prettier --write)
    → prettier --check .
    → Fail: back to Developer Agent (rare)

5. Unit tests
    → Fail: back to Developer Agent

6. Integration tests (full suite only)
    → Fail: back to Developer Agent
```

## Scope

| Scope | Steps |
|---|---|
| Per task | 1-5 (no integration tests) |
| Full suite (all tasks done) | 1-6 |
| After conflict resolution | 1-6 |
| After feedback round | 1-6 |

## Auto-Fixer Configuration

Per-repo defaults for TypeScript/JavaScript:

| Tool | Command | Scope |
|---|---|---|
| prettier | `prettier --write .` | Formatting |
| eslint | `eslint --fix .` | Lint + style |

Additional fixers configured per-repo.
