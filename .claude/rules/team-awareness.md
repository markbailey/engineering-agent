# Team Awareness

Before starting work on a ticket:

1. Check for existing branches matching the ticket ID: `git branch -r | grep {ticket-id}`
2. Check for existing PRs: `gh pr list --search {ticket-id}`
3. If human has active work on the same ticket:
   - Do NOT start a competing branch
   - ESCALATE — report conflict to human
   - Comment on Jira ticket noting the conflict
