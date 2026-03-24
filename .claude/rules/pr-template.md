# PR Template

```markdown
## {ticket-id}: {title}

**Jira:** {jira-url}

### Summary

{2-3 sentence description of what this PR does and why}

### Changes

{Bulleted list of changes, grouped by area}

### Testing

- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] TypeScript compilation clean
- [ ] Linting clean
- [ ] Secret scan clean

### Acceptance Criteria

{Checklist from PRD.json, each marked met/not-met}

### Review Notes

{Low-severity items from REVIEW.json that were logged but not blocking}

### Breaking Changes

{If any — description and migration path. "None" if none.}
```

PR Agent always opens as **draft** unless `--ready-pr` flag was passed.
