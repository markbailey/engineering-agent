# Engineering Agent — Workflow Runner
# Usage: make <target> PROJ-123

# Capture all args after the target
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ISSUE := $(word 1,$(ARGS))
EXTRA := $(wordlist 2,$(words $(ARGS)),$(ARGS))

.PHONY: help start dry-run resume pause stop ready-pr address-feedback dashboard dashboard-test
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
	@echo "  address-feedback  Address PR feedback including bot comments"
	@echo "  dashboard         Start the real-time dashboard server"
	@echo "  dashboard-test    Run dashboard tests"
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
	@echo "  make ready-pr PROJ-123"
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

dashboard:
	node dashboard/server.js

dashboard-test:
	node --test dashboard/test/stages.test.js dashboard/test/state.test.js dashboard/test/watcher.test.js dashboard/test/integration.test.js

address-feedback: _require-issue
	claude --permission-mode bypassPermissions "/address-feedback $(ISSUE) --include-bots $(EXTRA)"

_require-issue:
ifndef ISSUE
	$(error Ticket ID required. Usage: make start PROJ-123)
endif

# Prevent make from treating extra args as targets
%:
	@:
