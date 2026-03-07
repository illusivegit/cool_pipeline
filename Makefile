# ============================================================================
# OpenTelemetry Observability Lab — Makefile
# ============================================================================
#
# Single-VM Docker Compose observability stack with full lifecycle management.
#
# Quick start:
#   make up        Build and start all 10 services
#   make status    Verify endpoints are reachable
#   make health    Run 29-point health check suite
#
# Convention: Targets marked ## are user-facing (shown by 'make help').
#             Section headers use @echo in the help target.
# ============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env if present (image tags, ports, retention, project name)
-include .env
-include .env.secrets
export

PROJECT  ?= lab
LAB_HOST ?= localhost

# ── Help (default target) ───────────────────────────────────────────────────

.PHONY: help
help: ## Show this help message
	@echo "OpenTelemetry Observability Lab"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "DEPLOYMENT:"
	@printf "  \033[36m%-25s\033[0m %s\n" "up"      "Build and start all services"
	@printf "  \033[36m%-25s\033[0m %s\n" "down"    "Stop all services (preserve volumes)"
	@printf "  \033[36m%-25s\033[0m %s\n" "restart" "Restart all services (down + up)"
	@echo ""
	@echo "OPERATIONS:"
	@printf "  \033[36m%-25s\033[0m %s\n" "status"  "Show container status + endpoint checks"
	@printf "  \033[36m%-25s\033[0m %s\n" "logs"    "Tail all service logs"
	@printf "  \033[36m%-25s\033[0m %s\n" "traffic" "Generate synthetic traffic for dashboards"
	@printf "  \033[36m%-25s\033[0m %s\n" "dashboards" "Open Grafana in default browser"
	@echo ""
	@echo "VALIDATION:"
	@printf "  \033[36m%-25s\033[0m %s\n" "health"  "Run comprehensive health checks (29 checks)"
	@printf "  \033[36m%-25s\033[0m %s\n" "smoke"   "Quick smoke test (3 core endpoints)"
	@printf "  \033[36m%-25s\033[0m %s\n" "state"   "Generate post-deploy state contract artifact"
	@printf "  \033[36m%-25s\033[0m %s\n" "validate-versions" "Compare running versions against .env"
	@echo ""
	@echo "LIFECYCLE MANAGEMENT:"
	@printf "  \033[36m%-25s\033[0m %s\n" "backup"  "Snapshot all Docker volumes"
	@printf "  \033[36m%-25s\033[0m %s\n" "restore" "Restore from backup (usage: make restore SNAP=<timestamp>)"
	@echo ""
	@echo "DEVELOPMENT:"
	@printf "  \033[36m%-25s\033[0m %s\n" "lint"    "ShellCheck all bash scripts"
	@printf "  \033[36m%-25s\033[0m %s\n" "clean"   "Remove generated artifacts (state, backups, bytecode)"
	@echo ""
	@echo "CLEANUP:"
	@printf "  \033[36m%-25s\033[0m %s\n" "nuke"    "Destroy everything (containers, volumes, images, artifacts)"

# ── Config Rendering ──────────────────────────────────────────────────────

.PHONY: render-alertmanager

render-alertmanager:
	@if [ "$(ENABLE_ALERTING)" = "true" ] && [ -f .env.secrets ]; then \
		set -a && . ./.env && . ./.env.secrets && set +a && \
		envsubst < otel-collector/alertmanager.yml.tmpl > otel-collector/.alertmanager-rendered.yml && \
		echo "Alertmanager config rendered (alerting enabled)"; \
	else \
		cp otel-collector/alertmanager.yml otel-collector/.alertmanager-rendered.yml && \
		echo "Alertmanager config copied (alerting disabled — no .env.secrets or ENABLE_ALERTING!=true)"; \
	fi

# ── Deployment ──────────────────────────────────────────────────────────────

.PHONY: up down restart

up: render-alertmanager ## Build and start all services
	@DOCKER_BUILDKIT=1 docker compose -p $(PROJECT) up -d --build

down: ## Stop all services (preserve volumes)
	@docker compose -p $(PROJECT) down

restart: down up ## Restart all services

# ── Operations ──────────────────────────────────────────────────────────────

.PHONY: status logs traffic dashboards

status: ## Show container status + quick endpoint checks
	@docker compose -p $(PROJECT) ps
	@echo ""
	@echo "Endpoint checks:"
	@curl -sf http://$(LAB_HOST):$(FRONTEND_PORT)  >/dev/null 2>&1 && echo "  Frontend     : OK" || echo "  Frontend     : UNREACHABLE"
	@curl -sf http://$(LAB_HOST):$(BACKEND_PORT)/health >/dev/null 2>&1 && echo "  Backend      : OK" || echo "  Backend      : UNREACHABLE"
	@curl -sf http://$(LAB_HOST):$(GRAFANA_PORT)/api/health >/dev/null 2>&1 && echo "  Grafana      : OK" || echo "  Grafana      : UNREACHABLE"
	@curl -sf http://$(LAB_HOST):$(PROMETHEUS_PORT)/-/healthy >/dev/null 2>&1 && echo "  Prometheus   : OK" || echo "  Prometheus   : UNREACHABLE"
	@curl -sf http://$(LAB_HOST):$(TEMPO_PORT)/ready >/dev/null 2>&1 && echo "  Tempo        : OK" || echo "  Tempo        : UNREACHABLE"
	@curl -sf http://$(LAB_HOST):$(LOKI_PORT)/ready  >/dev/null 2>&1 && echo "  Loki         : OK" || echo "  Loki         : UNREACHABLE"
	@curl -sf http://$(LAB_HOST):$(ALERTMANAGER_PORT)/-/healthy >/dev/null 2>&1 && echo "  Alertmanager : OK" || echo "  Alertmanager : UNREACHABLE"

logs: ## Tail all service logs
	@docker compose -p $(PROJECT) logs -f

traffic: ## Generate synthetic traffic for dashboards
	@echo "Generating traffic..."
	@for i in $$(seq 1 20); do \
		curl -sf http://$(LAB_HOST):$(BACKEND_PORT)/api/tasks >/dev/null; \
		curl -sf -X POST -H 'Content-Type: application/json' \
			-d "{\"title\":\"load-test-$$i\",\"description\":\"auto\"}" \
			http://$(LAB_HOST):$(BACKEND_PORT)/api/tasks >/dev/null; \
	done
	@echo "Sent 40 requests (20 GET + 20 POST)."

dashboards: ## Open Grafana in default browser
	@xdg-open "http://$(LAB_HOST):$(GRAFANA_PORT)" 2>/dev/null || \
		open "http://$(LAB_HOST):$(GRAFANA_PORT)" 2>/dev/null || \
		echo "Open http://$(LAB_HOST):$(GRAFANA_PORT) in your browser"

# ── Validation ──────────────────────────────────────────────────────────────

.PHONY: health smoke state validate-versions

health: ## Run comprehensive health checks
	@bash scripts/health-checks.sh

smoke: ## Quick smoke test (subset of health)
	@echo "Smoke test — verifying core endpoints..."
	@curl -sf http://$(LAB_HOST):$(FRONTEND_PORT)  >/dev/null && echo "PASS  Frontend"
	@curl -sf http://$(LAB_HOST):$(GRAFANA_PORT)/api/health >/dev/null && echo "PASS  Grafana"
	@curl -sf http://$(LAB_HOST):$(PROMETHEUS_PORT)/-/ready >/dev/null && echo "PASS  Prometheus"

state: ## Generate post-deploy state contract artifact
	@bash scripts/state-contract.sh

validate-versions: ## Compare running versions against .env
	@bash scripts/validate-versions.sh

# ── Lifecycle Management ────────────────────────────────────────────────────

.PHONY: backup restore

backup: ## Snapshot all Docker volumes
	@bash scripts/backup.sh

restore: ## Restore from latest (or SNAP=<timestamp>) backup
	@bash scripts/restore.sh $(SNAP)

# ── Development ─────────────────────────────────────────────────────────────

.PHONY: lint clean

lint: ## ShellCheck all bash scripts
	@echo "Running ShellCheck..."
	@find lib/ scripts/ -name '*.sh' -exec shellcheck -x -P SCRIPTDIR {} + && echo "ShellCheck: all clean"

clean: ## Remove generated artifacts (state contracts, backups, bytecode)
	@rm -rf artifacts/state/*/
	@rm -rf backups/*/
	@find . -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name '*.pyc' -delete 2>/dev/null || true
	@echo "Removed: artifacts/state/*, backups/*, __pycache__, *.pyc"

# ── Cleanup ─────────────────────────────────────────────────────────────────

.PHONY: nuke

nuke: ## Destroy everything (containers, volumes, images, artifacts)
	@docker compose -p $(PROJECT) down -v --remove-orphans --rmi local 2>/dev/null || true
	@docker volume ls -q | grep -E "^($(PROJECT)_|otel-observability-lab_|opentelemetry_observability_lab_)" | xargs -r docker volume rm 2>/dev/null || true
	@docker image rm $(shell docker compose -p $(PROJECT) config --images 2>/dev/null) 2>/dev/null || true
	@rm -rf artifacts/state/*/
	@rm -rf backups/*/
	@find . -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name '*.pyc' -delete 2>/dev/null || true
	@echo "Nuked: containers, volumes, images, artifacts."
