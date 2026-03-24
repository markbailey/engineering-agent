# GitHub Actions Awareness

- PR Monitor checks CI status after every push and on PR events.
- Distinguish **flaky** vs **real** failures:
  - If a test fails that is unrelated to changed files and passes on re-run: flaky. Log and proceed.
  - If a test fails on code the Developer Agent touched: real. Generate FEEDBACK.json item.
- Do not re-trigger CI manually — let GitHub Actions handle re-runs.
- If CI is pending for an extended period, log and continue monitoring (do not block).
