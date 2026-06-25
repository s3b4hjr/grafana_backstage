# ledger-api

Double-entry ledger that posts the debit/credit pairs for each payment. Part of
the **payments-platform** system; depends on **payments-api**.

**Owner:** team-payments · **Lifecycle:** production

## Observability

Same wiring as every service in this stack:

- **Metrics**: Prometheus scrapes `ledger-api:8000/metrics` (`up{app="ledger-api"}`).
- **Traces → RED**: OTLP → Alloy → Tempo (`traces_spanmetrics_*`, `service="ledger-api"`).
- **Logs**: Alloy → Loki (filter `{job="docker"} |= "ledger-api"`).

Dashboards and alerts surface on this page via the `grafana/*` annotations.
