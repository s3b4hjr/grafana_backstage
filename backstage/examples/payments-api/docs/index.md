# payments-api

Handles payment authorization and capture. This is the demo service used to
exercise the observability stack end-to-end.

**Owner:** team-payments · **Lifecycle:** prod

## Observability

| Signal  | How                                                                       |
| ------- | ------------------------------------------------------------------------- |
| Metrics | Scraped by Prometheus (`up{app="payments-api"}`, `payments_requests_total`). |
| Traces  | OTLP → Alloy → Tempo; RED metrics via `traces_spanmetrics_*`.              |
| Logs    | Collected automatically by Alloy → Loki.                                  |

Dashboards and alerts for this service appear on its component page in the
portal (matched by the `grafana/*` annotations in `catalog-info.yaml`).

## Endpoints

- `GET /pay` — authorize a payment
- `GET /refund` — refund a payment
- `GET /metrics` — Prometheus metrics
- `GET /admin/degrade` / `GET /admin/heal` — see the [Runbook](runbook.md)
