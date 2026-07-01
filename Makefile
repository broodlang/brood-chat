# chat — dev tasks. `make check` is the full gate (unit tests + networked repros).
.PHONY: check test repro fmt run help

help:
	@echo "make test   — unit tests (nest test)"
	@echo "make repro  — networked regressions (mesh + tcp + nodedown)"
	@echo "make check  — test + repro (the full gate; use in CI)"
	@echo "make fmt    — format sources (nest format)"
	@echo "make run    — launch the app (nest run)"

test:
	nest test

repro:
	./repro/all.sh

# Full gate: fast pure tests first, then the live-node regressions.
check: test repro
	@echo "✓ check passed"

fmt:
	nest format

run:
	nest run
