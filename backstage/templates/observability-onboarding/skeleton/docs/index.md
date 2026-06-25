# ${{ values.name }}

${{ values.description }}

**Owner:** ${{ values.owner }}

## Observability

This service is wired into the shared observability stack:

| Signal  | How                                                                   |
| ------- | --------------------------------------------------------------------- |
| Metrics | Scraped by Prometheus via a `file_sd` target (`app=${{ values.name }}`). |
| Logs    | Collected automatically by Grafana Alloy (every container is tailed). |
| Traces  | Export OTLP to the Alloy gateway (`alloy:4317` / `:4318`).            |

Dashboards and alerts for this service show up on its page in the developer
portal — dashboards are matched by the `${{ values.name }}` tag and alerts by the
`app=${{ values.name }}` label (see the `grafana/*` annotations in `catalog-info.yaml`).

> To get traces flowing, drop the variables from the stack's `examples/otel.env`
> into this service's environment. No code changes needed for an OTel-instrumented app.
