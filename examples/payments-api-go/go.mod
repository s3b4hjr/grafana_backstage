module github.com/s3b4hjr/grafana/examples/payments-api-go

go 1.22

require (
	github.com/prometheus/client_golang v1.20.5
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.59.0
	go.opentelemetry.io/otel v1.34.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.34.0
	go.opentelemetry.io/otel/sdk v1.34.0
)

// Run `go mod tidy` once to resolve go.sum + indirect dependencies.
