# payments-api — test service for the observability stack

A tiny Go HTTP service that emits **all three signals** so you can see the whole
stack (and the `payments-api` dashboard) light up, plus a **runtime degradation**
switch to simulate incidents.

| Signal  | How it's produced |
| ------- | ----------------- |
| Metrics | Exposes `/metrics` (Prometheus scrapes it → `up{app="payments-api"}` + `payments_requests_total`). |
| Traces  | OTel HTTP instrumentation → OTLP/gRPC → Alloy → Tempo. Tempo's span-metrics generator turns those into `traces_spanmetrics_*` (the RED panels). |
| Logs    | Logs every request; Alloy tails the container → Loki (`{job="docker"} \|= "payments-api"`). |

It also **drives its own traffic** (`SELF_TRAFFIC=true`), so data flows with zero
manual requests.

## Run it (Option B — container, recommended)

Runs on the stack's `observability` network; OTLP goes to `alloy:4317` and Alloy
captures the logs automatically.

```bash
docker compose -f examples/payments-api-go/docker-compose.yml up -d --build
```

Then make Prometheus scrape it — drop a target file (auto-reloads in ~30s):

```yaml
# config/prometheus/targets/payments-api.yml
- targets: ["payments-api:8000"]
  labels: { app: payments-api, env: local }
```

(That file is exactly what the Backstage onboarding template's PR would add.)

### Option A — run on the host

```bash
cd examples/payments-api-go && go mod tidy && go run .
```

OTLP defaults to `localhost:4317`; metrics on `:8000`. Use a
`host.docker.internal:8000` Prometheus target. Note: logs only reach Loki when run
as a **container** (Alloy tails containers, not host processes).

## Endpoints

| Path            | Behaviour |
| --------------- | --------- |
| `GET /`         | ~1% errors |
| `GET /pay`      | ~5% errors, 20–200 ms |
| `GET /refund`   | ~15% errors, 20–200 ms |
| `GET /metrics`  | Prometheus metrics (not traced) |
| `GET /healthz`  | liveness |
| `GET /admin/degrade?latency=<ms>&errors=<0..1>` | inject faults at runtime |
| `GET /admin/heal` | reset to baseline |

## Degrade the service on purpose 🔥

Make latency and errors spike, then watch the dashboard / fire alerts:

```bash
# +700ms latency and 60% errors on every route
curl "localhost:8000/admin/degrade?latency=700&errors=0.6"

# milder: just slow, no extra errors
curl "localhost:8000/admin/degrade?latency=400&errors=0"

# back to healthy
curl "localhost:8000/admin/heal"
```

Watch it react (Prometheus / Grafana Explore):

```promql
# error ratio
sum(rate(traces_spanmetrics_calls_total{service="payments-api",status_code="STATUS_CODE_ERROR"}[1m]))
  / sum(rate(traces_spanmetrics_calls_total{service="payments-api"}[1m]))

# p95 latency (seconds)
histogram_quantile(0.95, sum by (le) (rate(traces_spanmetrics_latency_bucket{service="payments-api"}[1m])))

# injected fault level (handy to overlay)
payments_chaos_level
```

Or open the **payments-api — Service Overview (RED)** dashboard in Grafana
(`http://localhost:3000`, auto-provisioned from `dashboards/payments-api.json`) and
watch the Error Rate / p95 panels jump, then recover after `/admin/heal`.

## Tear down

```bash
docker compose -f examples/payments-api-go/docker-compose.yml down
rm config/prometheus/targets/payments-api.yml   # stop scraping it
```
