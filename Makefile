# Engineering Agent — Workflow Runner
# Usage: make start PROJ-123 [--ready-pr ...]

# Capture all args after the target
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ISSUE := $(word 1,$(ARGS))
EXTRA := $(wordlist 2,$(words $(ARGS)),$(ARGS))

.PHONY: help start dry-run resume pause stop
.DEFAULT_GOAL := help

help:
	@echo "Engineering Agent — Workflow Runner"
	@echo ""
	@echo "Usage: make <target> PROJ-123 [flags...]"
	@echo ""
	@echo "Targets:"
	@echo "  start    Full ticket-to-PR workflow"
	@echo "  dry-run  Plan only — no code, no PR"
	@echo "  resume   Continue an interrupted run"
	@echo "  pause    Stop at next safe checkpoint"
	@echo "  stop     Immediate stop, preserve state"
	@echo "  help     Show this message"
	@echo ""
	@echo "Examples:"
	@echo "  make start PROJ-123"
	@echo "  make start PROJ-123 --ready-pr"
	@echo "  make resume PROJ-123"

start: _require-issue
	claude "/start $(ISSUE) $(EXTRA)"

dry-run: _require-issue
	claude "/start $(ISSUE) --dry-run $(EXTRA)"

resume: _require-issue
	claude "/start $(ISSUE) --resume $(EXTRA)"

pause: _require-issue
	claude "/start $(ISSUE) --pause"

stop: _require-issue
	claude "/start $(ISSUE) --stop"

_require-issue:
ifndef ISSUE
	$(error Ticket ID required. Usage: make start PROJ-123)
endif

# Prevent make from treating extra args as targets
%:
	@:
