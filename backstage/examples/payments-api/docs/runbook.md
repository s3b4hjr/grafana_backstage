# Runbook

## Simulate an incident (degradation)

The service has a runtime fault switch, handy for testing alerts/dashboards:

```bash
# +700ms latency and 60% errors on every route
curl "localhost:8000/admin/degrade?latency=700&errors=0.6"

# back to healthy
curl "localhost:8000/admin/heal"
```

Or via the Makefile:

```bash
make demo-degrade LAT=700 ERR=0.6
make demo-heal
make demo-test            # baseline -> degrade -> measure -> heal
```

## What to watch

```promql
# error ratio
sum(rate(traces_spanmetrics_calls_total{service="payments-api",status_code="STATUS_CODE_ERROR"}[1m]))
  / sum(rate(traces_spanmetrics_calls_total{service="payments-api"}[1m]))

# p95 latency (s)
histogram_quantile(0.95, sum by (le) (rate(traces_spanmetrics_latency_bucket{service="payments-api"}[1m])))
```

Open the **payments-api — Service Overview (RED)** dashboard in Grafana and
watch Error Rate / p95 spike, then recover after healing.
