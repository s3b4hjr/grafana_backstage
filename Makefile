# Observability stack — common operations.
# `make help` lists targets. All commands read configuration from .env.

COMPOSE ?= docker compose
PROFILES ?=

# Backstage developer portal (separate Node app; not part of the compose stack)
BACKSTAGE_DIR  ?= backstage-app
BACKSTAGE_PORT ?= 3001
BACKSTAGE_NODE ?= 22

# payments-api demo/test app (examples/payments-api-go)
APP_DIR  ?= examples/payments-api-go
APP_PORT ?= 8000

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: init
init: ## Create .env from .env.example if missing
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")

.PHONY: config
config: ## Validate & render the merged compose configuration
	$(COMPOSE) config

.PHONY: up
up: init ## Start the core stack (detached)
	$(COMPOSE) up -d

.PHONY: up-all
up-all: init ## Start core stack + all optional profiles (probes)
	$(COMPOSE) --profile probes up -d

.PHONY: down
down: ## Stop the stack (keep volumes)
	$(COMPOSE) down

.PHONY: clean
clean: ## Stop the stack and DELETE all data volumes
	$(COMPOSE) down -v

.PHONY: restart
restart: ## Restart all services
	$(COMPOSE) restart

.PHONY: ps
ps: ## Show service status
	$(COMPOSE) ps

.PHONY: logs
logs: ## Tail logs (use S=grafana to filter one service)
	$(COMPOSE) logs -f $(S)

.PHONY: pull
pull: ## Pull the pinned images
	$(COMPOSE) --profile probes pull

.PHONY: reload-prometheus
reload-prometheus: ## Hot-reload Prometheus config (no restart)
	curl -fsSL -X POST http://localhost:$$(grep -E '^PROMETHEUS_PORT=' .env | cut -d= -f2)/-/reload && echo "reloaded"

.PHONY: dashboards
dashboards: ## Download curated community dashboards (needs jq)
	./scripts/fetch-dashboards.sh

.PHONY: backup
backup: ## Snapshot all data volumes to ./backups/<timestamp>
	./scripts/backup.sh

.PHONY: restore
restore: ## Restore volumes from a backup: make restore SRC=backups/<timestamp>
	@test -n "$(SRC)" || (echo "Usage: make restore SRC=backups/<timestamp>"; exit 1)
	./scripts/restore.sh $(SRC)

.PHONY: update
update: ## Pull pinned images and recreate changed services
	$(COMPOSE) --profile probes pull
	$(COMPOSE) up -d

.PHONY: urls
urls: ## Print the local service URLs
	@. ./.env; \
	echo "Grafana       http://localhost:$$GRAFANA_PORT  (login: $$GRAFANA_ADMIN_USER)"; \
	echo "Prometheus    http://localhost:$$PROMETHEUS_PORT"; \
	echo "Alertmanager  http://localhost:$$ALERTMANAGER_PORT"; \
	echo "Loki          http://localhost:$$LOKI_PORT"; \
	echo "Tempo         http://localhost:$$TEMPO_PORT"; \
	echo "Alloy UI      http://localhost:$$ALLOY_PORT"; \
	echo "OTLP gRPC     localhost:$$OTLP_GRPC_PORT   OTLP HTTP  localhost:$$OTLP_HTTP_PORT"; \
	test -d $(BACKSTAGE_DIR) && echo "Backstage     http://localhost:$(BACKSTAGE_PORT)  (make backstage)" || true

# ---------------------------------------------------------------------------
# Backstage portal — dev server. Needs Node $(BACKSTAGE_NODE)+ (auto-selected via nvm
# if present). Native modules need a libc++ fix on recent macOS; backstage-install
# handles it. Run `make up` first so Grafana is reachable.
# ---------------------------------------------------------------------------
.PHONY: backstage-install
backstage-install: ## Install Backstage deps (Node 22 + macOS native-build fix)
	@bash -c 'set -e; \
	  export NVM_DIR="$$HOME/.nvm"; [ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh" >/dev/null 2>&1 && { nvm install $(BACKSTAGE_NODE) >/dev/null 2>&1 || true; nvm use $(BACKSTAGE_NODE) >/dev/null 2>&1 || true; }; \
	  if [ "$$(uname)" = "Darwin" ]; then export SDKROOT="$$(xcrun --show-sdk-path)"; export CPLUS_INCLUDE_PATH="$$SDKROOT/usr/include/c++/v1"; fi; \
	  cd $(BACKSTAGE_DIR); echo "node $$(node -v) — installing…"; \
	  yarn install && yarn rebuild better-sqlite3 isolated-vm'

.PHONY: backstage-token
backstage-token: ## Create a Grafana service-account token -> backstage-app/grafana.env
	@. ./.env; url="http://localhost:$$GRAFANA_PORT"; \
	  echo "creating service account on $$url …"; \
	  id=$$(curl -s -u $$GRAFANA_ADMIN_USER:$$GRAFANA_ADMIN_PASSWORD -H 'Content-Type: application/json' -X POST $$url/api/serviceaccounts -d '{"name":"backstage","role":"Viewer"}' | sed -nE 's/.*"id":([0-9]+).*/\1/p'); \
	  [ -n "$$id" ] || id=$$(curl -s -u $$GRAFANA_ADMIN_USER:$$GRAFANA_ADMIN_PASSWORD "$$url/api/serviceaccounts/search?query=backstage" | sed -nE 's/.*"id":([0-9]+).*/\1/p' | head -1); \
	  tok=$$(curl -s -u $$GRAFANA_ADMIN_USER:$$GRAFANA_ADMIN_PASSWORD -H 'Content-Type: application/json' -X POST "$$url/api/serviceaccounts/$$id/tokens" -d "{\"name\":\"backstage-make-$$(date +%s)\"}" | sed -nE 's/.*"key":"([^"]+)".*/\1/p'); \
	  if [ -n "$$tok" ]; then printf 'GRAFANA_URL=%s\nGRAFANA_TOKEN=%s\n' "$$url" "$$tok" > $(BACKSTAGE_DIR)/grafana.env; echo "wrote $(BACKSTAGE_DIR)/grafana.env"; else echo "failed — is Grafana up? (make up)"; exit 1; fi

.PHONY: backstage
backstage: ## Start the Backstage portal on :3001 (foreground; Ctrl+C to stop)
	@bash -c 'set -e; \
	  export NVM_DIR="$$HOME/.nvm"; [ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh" >/dev/null 2>&1 && nvm use $(BACKSTAGE_NODE) >/dev/null 2>&1 || true; \
	  maj=$$(node -v 2>/dev/null | sed -E "s/v([0-9]+).*/\1/"); \
	  if [ -z "$$maj" ] || [ "$$maj" -lt $(BACKSTAGE_NODE) ]; then echo "Node $(BACKSTAGE_NODE)+ required (found: $$(node -v 2>/dev/null || echo none)). Try: nvm install $(BACKSTAGE_NODE)"; exit 1; fi; \
	  cd $(BACKSTAGE_DIR); \
	  [ -d node_modules ] || { echo "deps not installed — run: make backstage-install"; exit 1; }; \
	  if [ -f grafana.env ]; then set -a; . ./grafana.env; set +a; else echo "WARN: no grafana.env (Grafana cards will be empty) — run: make backstage-token"; fi; \
	  echo "Backstage -> http://localhost:$(BACKSTAGE_PORT)  (sign in as guest; Ctrl+C to stop)"; \
	  yarn start'

.PHONY: backstage-stop
backstage-stop: ## Stop a running Backstage dev server (frees :3001/:7007)
	@for p in $(BACKSTAGE_PORT) 7007; do pid=$$(lsof -ti tcp:$$p 2>/dev/null); [ -n "$$pid" ] && kill $$pid 2>/dev/null && echo "stopped pid $$pid on :$$p" || true; done; echo "done"

# ---------------------------------------------------------------------------
# payments-api demo app — a Go service that emits metrics+traces+logs, with a
# runtime degradation switch, to exercise the stack end-to-end. Run `make up` first.
# ---------------------------------------------------------------------------
.PHONY: demo-up
demo-up: ## Build & start the demo apps (payments-api, ledger-api) + Prometheus targets
	$(COMPOSE) -f $(APP_DIR)/docker-compose.yml up -d --build
	@for s in payments-api ledger-api; do f=config/prometheus/targets/$$s.yml; \
	  test -f $$f || printf -- '- targets: ["%s:8000"]\n  labels: { app: %s, env: local }\n' "$$s" "$$s" > $$f; done
	@echo "demo apps up (payments-api :8000, ledger-api :8001) — Prometheus auto-discovers in ~30s"

.PHONY: demo-down
demo-down: ## Stop the demo apps and remove their Prometheus targets
	$(COMPOSE) -f $(APP_DIR)/docker-compose.yml down
	@rm -f config/prometheus/targets/payments-api.yml config/prometheus/targets/ledger-api.yml && echo "removed scrape targets"

.PHONY: demo-logs
demo-logs: ## Tail the test app logs
	$(COMPOSE) -f $(APP_DIR)/docker-compose.yml logs -f

.PHONY: demo-degrade
demo-degrade: ## Inject faults: make demo-degrade LAT=700 ERR=0.6
	@curl -s "http://localhost:$(APP_PORT)/admin/degrade?latency=$(or $(LAT),700)&errors=$(or $(ERR),0.6)"; echo

.PHONY: demo-heal
demo-heal: ## Reset the test app to baseline
	@curl -s "http://localhost:$(APP_PORT)/admin/heal"; echo

.PHONY: demo-test
demo-test: ## Degradation test (vars: SERVICE APP_PORT LAT ERR WAIT). E.g. SERVICE=ledger-api APP_PORT=8001
	@APP_PORT=$(APP_PORT) SERVICE="$(SERVICE)" LAT="$(LAT)" ERR="$(ERR)" WAIT="$(WAIT)" ./$(APP_DIR)/loadtest.sh
