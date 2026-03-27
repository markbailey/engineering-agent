# Engineering Agent — Workflow Runner
# Usage: make <target> PROJ-123

# Capture all args after the target
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ISSUE := $(word 1,$(ARGS))
EXTRA := $(wordlist 2,$(words $(ARGS)),$(ARGS))

.PHONY: help start dry-run resume revert pause stop ready-pr auto-merge address-feedback dashboard dashboard-test test test-scripts test-agent clean clean-dry
.DEFAULT_GOAL := help

help:
	@echo "Engineering Agent — Workflow Runner"
	@echo ""
	@echo "Usage: make <target> PROJ-123|./file.json [flags...]"
	@echo ""
	@echo "Targets:"
	@echo "  start             Full ticket-to-PR workflow"
	@echo "  dry-run           Plan only — no code, no PR"
	@echo "  resume            Continue an interrupted run"
	@echo "  pause             Stop at next safe checkpoint"
	@echo "  stop              Immediate stop, preserve state"
	@echo "  ready-pr          Mark PR as ready for review (not draft)"
	@echo "  revert            Revert a merged ticket's PR"
	@echo "  auto-merge        Full workflow with auto-merge enabled"
	@echo "  address-feedback  Address PR feedback including bot comments"
	@echo "  dashboard         Start the real-time dashboard server"
	@echo "  dashboard-test    Run dashboard tests"
	@echo "  test              Run all tests"
	@echo "  test-scripts      Run script unit tests"
	@echo "  test-agent        Run agent test (requires FIXTURE=path)"
	@echo "  clean             Clean orphaned runs, worktrees, stale tickets"
	@echo "  clean-dry         Dry-run clean (report only)"
	@echo "  help              Show this message"
	@echo ""
	@echo "Input:"
	@echo "  PROJ-123           Jira ticket ID"
	@echo "  ./tickets/foo.json Local JSON file (bypasses Jira)"
	@echo ""
	@echo "Examples:"
	@echo "  make start PROJ-123"
	@echo "  make start ./tickets/my-feature.json"
	@echo "  make dry-run PROJ-123"
	@echo "  make dry-run ./tickets/my-feature.json"
	@echo "  make revert PROJ-123"
	@echo "  make ready-pr PROJ-123"
	@echo "  make auto-merge PROJ-123"
	@echo "  make resume PROJ-123"
	@echo "  make address-feedback 42"
	@echo "  make address-feedback 42 -- --dry-run"

start: _require-issue
	claude --permission-mode bypassPermissions "/start $(ISSUE) $(EXTRA)"

dry-run: _require-issue
	claude --permission-mode bypassPermissions "/start $(ISSUE) --dry-run $(EXTRA)"

resume: _require-issue
	claude --permission-mode bypassPermissions "/start $(ISSUE) --resume $(EXTRA)"

pause: _require-issue
	claude --permission-mode bypassPermissions "/start $(ISSUE) --pause"

stop: _require-issue
	claude --permission-mode bypassPermissions "/start $(ISSUE) --stop"

ready-pr: _require-issue
	claude --permission-mode bypassPermissions "/start $(ISSUE) --ready-pr $(EXTRA)"

auto-merge: _require-issue
	claude --permission-mode bypassPermissions "/start $(ISSUE) --auto-merge $(EXTRA)"

revert: _require-issue
	claude --permission-mode bypassPermissions "/start $(ISSUE) --revert $(EXTRA)"

dashboard:
	node dashboard/server.js

dashboard-test:
	node --test dashboard/test/stages.test.js dashboard/test/state.test.js dashboard/test/watcher.test.js dashboard/test/integration.test.js

address-feedback: _require-issue
	claude --permission-mode bypassPermissions "/address-feedback $(ISSUE) --include-bots $(EXTRA)"

clean:
	bash scripts/cleanup-orphans.sh

clean-dry:
	bash scripts/cleanup-orphans.sh --dry-run

test: test-scripts
	@echo "All tests passed"

test-scripts:
	@echo "Running script tests..."
	@bash tests/test-scripts.sh
	@for f in tests/*.test.sh; do echo "Running $$f..."; bash "$$f" || exit 1; done

test-agent:
	@echo "Running agent test for $(FIXTURE)..."
	@echo "Note: Agent tests require dry-run mode (not yet implemented)"

_require-issue:
ifndef ISSUE
	$(error Ticket ID required. Usage: make start PROJ-123)
endif

# Prevent make from treating extra args as targets
%:
	@:
