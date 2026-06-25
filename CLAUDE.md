# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A self-contained, environment-agnostic observability stack run via Docker Compose:
Grafana + Prometheus + Alertmanager + Loki + Tempo + Grafana Alloy + exporters
(node-exporter, cAdvisor, blackbox). There is no application code — the repo is
**configuration**. The design goal is "clone and run anywhere": every host-specific
value (versions, ports, credentials, retention) is parameterized through `.env`,
and the compose file contains no hard-coded paths beyond relative `./config` mounts.

## Commands

All operations go through the `Makefile` (it reads `.env`):

- `make up` — copy `.env` from `.env.example` if missing, then start the core stack.
- `make up-all` — core stack **plus** optional services behind compose profiles (`probes`).
- `make down` / `make clean` — stop (keep volumes) / stop and delete all data volumes.
- `make config` — validate & render the merged compose config (run this after editing `docker-compose.yml` or `.env`).
- `make logs S=grafana` — tail one service; omit `S=` for all.
- `make reload-prometheus` — hot-reload Prometheus rules/scrape config without a restart (relies on `--web.enable-lifecycle`).
- `make dashboards` — download curated community dashboards (needs `jq`).
- `make backup` / `make restore SRC=backups/<ts>` — snapshot / restore the data volumes.
- `make update` — pull pinned images and recreate changed services (after bumping `*_VERSION` in `.env`).
- `make urls` — print all local service URLs/ports.

Raw compose works too, e.g. `docker compose --profile probes up -d`. Optional
services (currently `blackbox-exporter`) only start when their profile is named.

## Architecture — the data flows

Understanding the three telemetry paths is the key to working here:

- **Metrics**: Prometheus *scrapes* every component + exporter (static targets by
  compose service name in `config/prometheus/prometheus.yml`). It also *receives*
  remote-write from Tempo's metrics-generator — this is why Prometheus runs with
  `--web.enable-remote-write-receiver` in `docker-compose.yml`.
- **Logs**: Alloy auto-discovers Docker containers via the mounted
  `/var/run/docker.sock`, tails their logs, and pushes to Loki. No per-app config
  needed — any container on the host shows up in Loki with `job="docker"`.
- **Traces**: Alloy is the single OTLP gateway (host ports 4317/4318) and forwards
  to Tempo over the internal network (`tempo:4317`). Tempo's metrics-generator
  derives RED metrics + service-graph data and remote-writes them back to Prometheus.

Grafana ties it together: `config/grafana/provisioning/datasources/datasources.yml`
pre-wires trace↔logs↔metrics correlation (exemplars → Tempo, Loki derived field
`trace_id` → Tempo, Tempo `tracesToLogs`/`tracesToMetrics`/`serviceMap` → Loki/Prometheus).
**Datasource UIDs are fixed** (`prometheus`, `loki`, `tempo`, `alertmanager`) on
purpose — dashboards and correlation links reference them, so do not change them.

## Conventions & gotchas

- **Where config lives**: each service reads from `config/<service>/`, bind-mounted
  read-only. Dashboards in `dashboards/*.json` are auto-loaded by the provider in
  `config/grafana/provisioning/dashboards/dashboards.yml` (30s refresh; sub-folders
  become Grafana folders).
- **Env expansion is not uniform.** Loki and Tempo expand `${VAR}` only because they
  run with `-config.expand-env=true` (set in compose), and those vars must be passed
  into the container `environment:` block — Go's `os.Expand` has **no `${VAR:-default}`
  syntax**, so the var must always be set. **Prometheus and Alertmanager do NOT expand
  env vars in their config files** — values like `scrape_interval` are literal; only
  flags passed via compose `command:` (e.g. retention) are parameterized.
- **Durations**: Prometheus retention accepts `15d`; Loki/Tempo durations are Go
  durations (`h`/`m`/`s` only — `168h`, not `7d`).
- **`$` in compose**: escape literal dollar signs as `$$` inside `docker-compose.yml`
  (e.g. node-exporter's filesystem-exclude regex). Files that are merely *mounted*
  (the `config/**` files, dashboards) are not interpolated by compose — write `$` normally there.
- **Host scraping**: Prometheus and Alloy have `extra_hosts: host.docker.internal:host-gateway`
  so `host.docker.internal:<port>` targets resolve on Linux as well as Docker Desktop.
- **Healthchecks vs. ordering**: `depends_on` uses `condition: service_started` (not
  `service_healthy`) to avoid boot deadlocks if a minimal image lacks `wget`; Grafana
  reconnects to datasources as they come up. Healthchecks are still defined for `ps` visibility.
- **Pinned versions**: all images are pinned in `.env`. Bump a version there, then
  `make pull && make up`. Don't introduce `:latest`.

## Onboarding applications (the intended simple paths)

- **Metrics**: do NOT edit `prometheus.yml`. Prometheus has a `file_sd_configs`
  job (`applications`) watching `config/prometheus/targets/*.yml` with a 30s
  refresh — drop the app's `/metrics` endpoint there and it's picked up with no
  reload/restart. Editing `prometheus.yml` itself still requires `make reload-prometheus`.
- **Logs**: automatic — Alloy tails all containers. Nothing to add.
- **Traces**: apps export OTLP to the Alloy gateway (`localhost:4317/4318`, or
  `alloy:4317/4318` from inside the network). See `examples/otel.env` and
  `examples/app-compose-snippet.yml`.

## State, backups & upgrades

- **Stateless config vs. stateful volumes**: everything in `config/`, `dashboards/`
  and `.env` is git-tracked and reproducible. Runtime state lives only in the six
  named volumes (grafana/prometheus/loki/tempo/alertmanager/alloy). `scripts/backup.sh`
  tars each `${COMPOSE_PROJECT_NAME}_<volume>` via a throwaway `alpine` container.
  `grafana-data` is the one that holds *unrecoverable* state (UI-built dashboards,
  users) — file-provisioned dashboards are already in git.
- **Restore** must run with the stack stopped (`make down`) — restoring under a live
  Loki/Prometheus corrupts the TSDB.
- **Upgrades**: bump `*_VERSION` in `.env`, then `make update`. Versions are
  intentionally pinned (no `:latest`); upgrade one component at a time across majors.

## Alerting

Default = **Grafana unified alerting** (Grafana evaluates rules against any
datasource and routes via its embedded Alertmanager). It's provisioned in
`config/grafana/provisioning/alerting/` (`contactpoints.yml`, `policies.yml`,
`rules.yml`) and also editable in the Grafana UI (UI-created alerts persist in
`grafana-data`; file-provisioned ones are read-only with a "Provisioned" badge).
Each provisioned rule is a query (`refId A`, instant) + a threshold expression
(`refId C`, `datasourceUid: __expr__`); `condition: C`. Datasource UIDs in rules
must match the provisioned datasources (`prometheus`, `loki`).

The standalone **Alertmanager is optional** — gated behind the `classic-alerting`
compose profile and OFF by default. The Prometheus `alerting:`/`rule_files:` blocks
in `prometheus.yml` are commented out to match; the classic rules in
`config/prometheus/rules/*.yml` only apply when you enable that profile and uncomment them.

- **A new alert (easy)**: Grafana UI → Alerting → New alert rule. Or add a rule to
  `config/grafana/provisioning/alerting/rules.yml` and `make restart S=grafana`.
- **A new optional service**: give it a `profiles: ["<name>"]` in `docker-compose.yml`
  so it stays off by default, and add a Make target if it needs its own profile to start.
- **A new dashboard**: drop a JSON into `dashboards/` using datasource refs by the fixed UIDs.

## AWS / CloudWatch dashboards

Provisioned under `dashboards/aws/` (Grafana folder "aws"), generated by
`scripts/gen-aws-dashboards.py` (edit generator → re-run → provider reloads in ~30s).
They target a user-created CloudWatch datasource via a `datasource` template
variable + a custom `region` variable — no hardcoded UID in panels.

Proven CloudWatch query model (verified against a live datasource via `/api/ds/query`):
- **Standard metric**: `{queryMode:"Metrics", region, namespace, metricName, statistic, dimensions, matchExact:false, metricQueryType:0, metricEditorMode:0, period}` — `matchExact:false` makes Grafana emit a `SEARCH(...)` so all series in a small namespace show with no per-resource config.
- **Metrics Insights (SQL)**: `{..., statistic, metricQueryType:1, metricEditorMode:1, sqlExpression:"SELECT ..."}`. Used for large namespaces (EC2/EBS/SQS/DynamoDB/Lambda) to get cost-cheap **Top-N in one query** instead of pulling thousands of series.

Gotchas learned the hard way:
- Every CloudWatch query **must** include a `statistic` field — even Metrics Insights (else `query must have either statistic or statistics field`).
- In Metrics Insights SQL, reserved-keyword metric names must be double-quoted — `SUM("Count")` (API Gateway), `"5XXError"`/`"4XXError"`.
- Dashboards use `refresh: 5m` on purpose — CloudWatch `GetMetricData` bills per metric pulled; don't crank the refresh.
- S3 `BucketSizeBytes` is a daily metric — those panels need a ≥2-day time range.
