# Observability Stack (Grafana LGTM + Prometheus)

A complete, **environment-agnostic** observability stack you can drop into any
project and run with Docker Compose. Nothing is hard-coded to a host — every
port, version, credential and retention window lives in `.env`.

```
┌────────────┐   metrics   ┌──────────────┐
│ exporters  │────────────▶│  Prometheus  │──┐
│ node/cAdv. │             └──────────────┘  │ alerts ┌──────────────┐
└────────────┘                    ▲          ├───────▶│ Alertmanager │
                          remote_write        │       └──────────────┘
┌────────────┐  OTLP   ┌────────┐ │ (span    │
│    apps    │────────▶│ Alloy  │─┼─metrics)  │   ┌──────────┐
└────────────┘         └────────┘ │           └──▶│ Grafana  │ :3000
   logs (docker) │   traces │     │               └──────────┘
                 ▼          ▼     │                  ▲   ▲
            ┌────────┐  ┌────────┐│  query metrics/  │   │
            │  Loki  │  │ Tempo  │┴──── logs/traces ─┘   │
            └────────┘  └────────┘                       │
                 └──────────── correlated in Grafana ────┘
```

| Service          | Role                                   | URL (default)            |
| ---------------- | -------------------------------------- | ------------------------ |
| Grafana          | dashboards & exploration               | http://localhost:3000    |
| Prometheus       | metrics store + alert rules            | http://localhost:9090    |
| Alertmanager     | classic routing (opt. — see Alerting)  | http://localhost:9093    |
| Loki             | log aggregation                        | http://localhost:3100    |
| Tempo            | distributed tracing                    | http://localhost:3200    |
| Alloy            | unified agent (logs + OTLP gateway)    | http://localhost:12345   |
| node-exporter    | host metrics                           | http://localhost:9100    |
| cAdvisor         | container metrics                      | http://localhost:8080    |
| blackbox (opt.)  | endpoint probing — profile `probes`    | http://localhost:9115    |

## Quick start

```bash
make up        # copies .env from .env.example (if needed) and starts the core stack
make urls      # print the service URLs
```

Open Grafana at http://localhost:3000 (default login `admin` / `admin`).
Datasources (Prometheus, Loki, Tempo, Alertmanager) and the **Observability
Overview** dashboard are auto-provisioned — no manual setup.

Start everything including optional probing:

```bash
make up-all    # core + blackbox-exporter (profile: probes)
```

Tear down:

```bash
make down      # stop, keep data
make clean     # stop and delete all volumes
```

## Pointing your applications at the stack

Three signals, three dead-simple paths — no rebuild of the stack required:

- **Logs — zero config.** Every container you run on the host is auto-discovered
  by Alloy and shipped to Loki (labels `job="docker"`, `container`,
  `compose_project`). Nothing to do.

- **Metrics — drop a line in a file.** Edit `config/prometheus/targets/apps.yml`
  and add your app's `/metrics` endpoint. Prometheus reloads it automatically
  (~30s) — **no restart, no editing the main config**:

  ```yaml
  - targets: ["host.docker.internal:8000"]   # app on the Docker host
    labels: { app: my-api, env: local }
  ```

- **Traces — set env vars.** Point any OpenTelemetry SDK at the Alloy OTLP
  gateway — gRPC `localhost:4317` or HTTP `localhost:4318`. Copy
  [`examples/otel.env`](examples/otel.env) into your app. Tempo turns spans into
  RED metrics + a service graph automatically (Grafana → **Explore → Service Graph**).

Running your app as its own container? See
[`examples/app-compose-snippet.yml`](examples/app-compose-snippet.yml) for joining
the `observability` network and exporting to `alloy:4318`.

In Grafana, traces ↔ logs ↔ metrics link to each other out of the box —
correlation is pre-wired in the provisioned datasources.

## Alerting (the easy way)

This stack uses **Grafana's built-in alerting** — no `alertmanager.yml` to wrangle.
You manage everything in the Grafana UI under **Alerting**:

- **Alert rules** — *Alerting → Alert rules → New*. Point-and-click a query on
  **any** datasource (Prometheus metrics, **Loki logs**, Tempo), set a threshold,
  done. No PromQL-rule files required.
- **Contact points** (where to notify) — *Alerting → Contact points*: Slack,
  email, Discord, Telegram, PagerDuty, webhook, … Test with one click.
- **Notification policies** (how to route/group) — *Alerting → Notification policies*.

It ships ready to use: example rules are pre-provisioned in the **Observability
Alerts** folder — host down, high CPU, high memory, and an **error-log spike**
rule that alerts straight off Loki logs. These live in
`config/grafana/provisioning/alerting/` (version-controlled, shown with a
"Provisioned" badge). Anything you build in the UI is stored in `grafana-data`.

Wiring notifications:
- **Slack/Discord/Telegram/webhook** — uncomment a block in
  `config/grafana/provisioning/alerting/contactpoints.yml`, then `make restart S=grafana`.
  (Or just add it in the UI.)
- **Email** — set `GF_SMTP_*` in `.env` and `make up`.

> Prefer the classic Prometheus + standalone Alertmanager flow? It's still here,
> just optional: `docker compose --profile classic-alerting up -d`, then
> uncomment the `alerting:`/`rule_files:` blocks in `config/prometheus/prometheus.yml`.
> Rules for that path live in `config/prometheus/rules/`.

## Updating to newer versions

Every image is **pinned in `.env`** — upgrades are explicit and reversible.

```bash
# 1. Edit the *_VERSION lines in .env to the tags you want
# 2. Pull and recreate only what changed:
make update          # = docker compose pull + up -d
```

Find the latest tags on each project's releases page (Grafana, Prometheus,
Loki, Tempo, Alloy, exporters). Bump one component at a time and skim its
changelog for breaking config changes before a major jump (e.g. Loki/Tempo
storage-schema bumps). To roll back, restore the previous tag in `.env` and
`make update` again. **Back up first** (below) before a major upgrade.

## Backups

Your **config lives in git** (`config/`, `dashboards/`, `.env`) — only runtime
state sits in Docker volumes. Back those up:

| Volume                 | Holds                                             |
| ---------------------- | ------------------------------------------------- |
| `grafana-data`         | UI-created dashboards, users, API keys, settings  |
| `prometheus-data`      | metrics TSDB                                       |
| `loki-data`            | logs                                              |
| `tempo-data`           | traces                                            |
| `alertmanager-data`    | silences & notification state                     |
| `alloy-data`           | agent WAL / positions                             |

```bash
make backup                          # -> ./backups/<timestamp>/*.tar.gz
make down                            # stop for a consistent restore
make restore SRC=backups/<timestamp> # restore, then:
make up
```

The most important to keep is `grafana-data` (your dashboards) — anything
provisioned from files is already in git. Metrics/logs/traces are
time-windowed by retention, so back them up only if you need historical replay.

## Configuration

Everything is in `.env` (copy of `.env.example`):

- **Versions** — every image is pinned; bump deliberately, then `make pull && make up`.
- **Ports** — change the host-side port of any service.
- **Credentials** — `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`.
- **Retention** — `PROMETHEUS_RETENTION_TIME`, `LOKI_RETENTION_PERIOD`,
  `TEMPO_RETENTION` (Loki/Tempo use Go durations: `h`/`m`/`s`, no `d`).

Per-environment overrides without touching tracked files:

```bash
cp .env.example .env.prod && edit ...        # separate env file
docker compose --env-file .env.prod up -d
# or drop a docker-compose.override.yml (gitignored) for structural tweaks
```

## More dashboards

```bash
make dashboards   # downloads Node Exporter Full, cAdvisor, Loki, Blackbox
                  # dashboards and rewires them to this stack's datasource UIDs
```

## Production notes

- Services publish on `0.0.0.0`. Put Grafana behind TLS / a reverse proxy
  (set `GRAFANA_ROOT_URL`) and bind the rest to `127.0.0.1` or an internal
  network before exposing anything.
- The filesystem backends (Loki/Tempo) and single-replica setup suit a single
  host. For scale, switch `storage` blocks to S3/GCS/Azure and run the
  components in microservices mode.
- Set a real `GRAFANA_ADMIN_PASSWORD` and configure an Alertmanager receiver
  in `config/alertmanager/alertmanager.yml`.
```
