// payments-api — a tiny Go service to exercise the observability stack end-to-end.
//
// It produces all three signals the `payments-api` dashboard reads:
//   • Metrics : exposes /metrics (Prometheus scrapes it -> up{app="payments-api"})
//   • Traces  : OTel HTTP instrumentation -> OTLP/gRPC -> Alloy -> Tempo, whose
//               span-metrics generator emits traces_spanmetrics_* (the RED panels)
//   • Logs    : logs every request (Alloy tails the container -> Loki), the line
//               contains the service name so the dashboard's Loki filter matches.
//
// With SELF_TRAFFIC=true (default) it hits its own endpoints so the dashboard
// fills with no manual curl.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

var (
	tracer = otel.Tracer("payments-api")
	// Used as the log-line prefix so Loki/`container` lines read correctly per
	// service (traces/metrics already carry the name via OTEL_SERVICE_NAME).
	serviceName = env("OTEL_SERVICE_NAME", "payments-api")

	// Optional downstream service to call on each request (distributed tracing).
	// e.g. DOWNSTREAM_URL=http://payments-api:8000/pay
	downstream = env("DOWNSTREAM_URL", "")
	// Instrumented client: creates a client span + injects W3C traceparent.
	httpClient = &http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport)}

	// Custom metric exposed at /metrics (alongside the default go_*/process_*
	// collectors). The RED panels use Tempo span-metrics, but this proves the
	// scrape target is healthy and gives you something app-specific to chart.
	requests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "payments_requests_total",
		Help: "Payment requests handled, by operation and outcome.",
	}, []string{"op", "outcome"})

	// --- Runtime degradation ("chaos") knobs, toggled via /admin/* ----------
	// extraLatencyMs is added to every request; extraErrPerMille (0..1000) is
	// added to each route's base error rate. Both default to 0 (healthy).
	extraLatencyMs   atomic.Int64
	extraErrPerMille atomic.Int64
	// Exposed so you can also chart the injected fault level on a dashboard.
	chaosGauge = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "payments_chaos_level",
		Help: "Injected fault level (knob=latency_ms|error_permille).",
	}, []string{"knob"})
)

// initTracer wires an OTLP/gRPC exporter to the Alloy gateway and installs a
// global TracerProvider tagged with service.name (the `service` label Tempo's
// span-metrics processor stamps on every series). Returns a shutdown func.
func initTracer(ctx context.Context, service, endpoint string) (func(context.Context) error, error) {
	exp, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(endpoint), // host:port, no scheme
		otlptracegrpc.WithInsecure(),         // plaintext: local gateway, no TLS
	)
	if err != nil {
		return nil, fmt.Errorf("otlp exporter: %w", err)
	}

	res, err := resource.New(ctx, resource.WithAttributes(
		attribute.String("service.name", service),
		attribute.String("service.version", "1.0.0"),
		attribute.String("deployment.environment", env("ENV", "local")),
	))
	if err != nil {
		return nil, fmt.Errorf("resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))
	return tp.Shutdown, nil
}

// handle wraps a simulated handler in an otelhttp server span named `op` (that
// string becomes the span_name label in the RED panels). It fakes a downstream
// call as a child span and fails ~errRate of the time so the error panel lights.
func handle(op string, errRate float64) http.Handler {
	h := func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()

		// Child span: pretend we call a database / downstream service.
		_, child := tracer.Start(ctx, "db.query")
		latency := time.Duration(20+rand.Intn(180))*time.Millisecond +
			time.Duration(extraLatencyMs.Load())*time.Millisecond // + injected latency
		time.Sleep(latency)
		child.End()

		// Distributed trace: call a downstream service (if configured). The
		// instrumented client propagates the trace context, so one trace spans
		// both services and Tempo draws a service-graph edge.
		if downstream != "" {
			callDownstream(ctx)
		}

		effErr := errRate + float64(extraErrPerMille.Load())/1000.0 // + injected errors
		if rand.Float64() < effErr {
			// otelhttp marks 5xx as error automatically; we also set it explicitly.
			trace.SpanFromContext(ctx).SetStatus(codes.Error, "downstream failure")
			requests.WithLabelValues(op, "error").Inc()
			log.Printf("%s %s -> 500 in %s", serviceName, op, latency)
			http.Error(w, "payment failed", http.StatusInternalServerError)
			return
		}

		requests.WithLabelValues(op, "ok").Inc()
		log.Printf("%s %s -> 200 in %s", serviceName, op, latency)
		fmt.Fprintf(w, "%s ok in %s\n", op, latency)
	}
	return otelhttp.NewHandler(http.HandlerFunc(h), op)
}

// callDownstream makes a trace-propagating GET so a single trace spans this
// service and the downstream one (and Tempo draws a service-graph edge).
func callDownstream(ctx context.Context) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, downstream, nil)
	if err != nil {
		return
	}
	if resp, err := httpClient.Do(req); err == nil {
		_ = resp.Body.Close()
	}
}

// generateTraffic hammers our own endpoints so the dashboard has data without
// any manual requests. Disable with SELF_TRAFFIC=false.
func generateTraffic(addr string) {
	base := "http://127.0.0.1" + addr
	paths := []string{"/", "/pay", "/refund"}
	client := &http.Client{Timeout: 3 * time.Second}
	time.Sleep(2 * time.Second) // give the server a moment to come up
	for range time.NewTicker(400 * time.Millisecond).C {
		resp, err := client.Get(base + paths[rand.Intn(len(paths))])
		if err == nil {
			resp.Body.Close()
		}
	}
}

// setChaos updates the runtime knobs and mirrors them onto a gauge.
func setChaos(latencyMs, errPerMille int64) {
	extraLatencyMs.Store(latencyMs)
	extraErrPerMille.Store(errPerMille)
	chaosGauge.WithLabelValues("latency_ms").Set(float64(latencyMs))
	chaosGauge.WithLabelValues("error_permille").Set(float64(errPerMille))
	log.Printf("%s CHAOS set: +%dms latency, +%.0f%% errors", serviceName, latencyMs, float64(errPerMille)/10)
}

// degradeHandler injects faults: /admin/degrade?latency=<ms>&errors=<0..1>
func degradeHandler(w http.ResponseWriter, r *http.Request) {
	lat := extraLatencyMs.Load()
	if v := r.URL.Query().Get("latency"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			lat = n
		}
	}
	errPM := extraErrPerMille.Load()
	if v := r.URL.Query().Get("errors"); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			errPM = int64(f * 1000) // 0.5 -> 500 per mille
		}
	}
	setChaos(lat, errPM)
	fmt.Fprintf(w, "degraded: +%dms latency, +%.0f%% errors\n", lat, float64(errPM)/10)
}

func healHandler(w http.ResponseWriter, _ *http.Request) {
	setChaos(0, 0)
	fmt.Fprintln(w, "healed: back to baseline")
}

func main() {
	service := serviceName
	otlp := env("OTLP_ENDPOINT", "localhost:4317") // alloy:4317 from inside the network
	addr := env("LISTEN_ADDR", ":8000")

	ctx := context.Background()
	shutdown, err := initTracer(ctx, service, otlp)
	if err != nil {
		log.Fatalf("tracer init: %v", err)
	}
	defer func() { _ = shutdown(context.Background()) }()

	mux := http.NewServeMux()
	mux.Handle("/", handle("GET /", 0.01))
	mux.Handle("/pay", handle("GET /pay", 0.05))
	mux.Handle("/refund", handle("GET /refund", 0.15))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/admin/degrade", degradeHandler) // inject latency/errors
	mux.HandleFunc("/admin/heal", healHandler)        // reset to baseline
	mux.Handle("/metrics", promhttp.Handler())        // not traced

	srv := &http.Server{Addr: addr, Handler: mux}

	if env("SELF_TRAFFIC", "true") == "true" {
		go generateTraffic(addr)
	}

	go func() {
		log.Printf("%s listening on %s — metrics at %s/metrics, traces -> %s",
			service, addr, addr, otlp)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("shutting down…")
	ctxTimeout, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctxTimeout)
}
