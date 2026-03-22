# Engineering Agent — Workflow Runner
# Usage: make start ISSUE=PROJ-123 [FLAGS="--dry-run --ready-pr"]

ISSUE ?=
FLAGS  ?=

.PHONY: help start dry-run resume pause stop
.DEFAULT_GOAL := help

help:
	@echo "Engineering Agent — Workflow Runner"
	@echo ""
	@echo "Usage: make <target> ISSUE=PROJ-123"
	@echo ""
	@echo "Targets:"
	@echo "  start    Full ticket-to-PR workflow"
	@echo "  dry-run  Plan only — no code, no PR"
	@echo "  resume   Continue an interrupted run"
	@echo "  pause    Stop at next safe checkpoint"
	@echo "  stop     Immediate stop, preserve state"
	@echo "  help     Show this message"
	@echo ""
	@echo "Options:"
	@echo "  ISSUE   Jira ticket ID (required)"
	@echo '  FLAGS    Extra flags, e.g. FLAGS="--ready-pr"'

start:
ifndef ISSUE
	$(error ISSUE is required. Usage: make start ISSUE=PROJ-123)
endif
	claude "/start $(ISSUE) $(FLAGS)"

dry-run:
ifndef ISSUE
	$(error ISSUE is required. Usage: make dry-run ISSUE=PROJ-123)
endif
	claude "/start $(ISSUE) --dry-run"

resume:
ifndef ISSUE
	$(error ISSUE is required. Usage: make resume ISSUE=PROJ-123)
endif
	claude "/start $(ISSUE) --resume $(FLAGS)"

pause:
ifndef ISSUE
	$(error ISSUE is required. Usage: make pause ISSUE=PROJ-123)
endif
	claude "/start $(ISSUE) --pause"

stop:
ifndef ISSUE
	$(error ISSUE is required. Usage: make stop ISSUE=PROJ-123)
endif
	claude "/start $(ISSUE) --stop"
