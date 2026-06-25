#!/usr/bin/env bash
# Degradation test for the payments-api demo service:
#   baseline -> inject faults -> measure (via Prometheus) -> heal.
# Reads PROMETHEUS_PORT from .env. Override knobs with env vars:
#   LAT (ms, default 700)  ERR (0..1, default 0.6)  WAIT (s, default 60)
#   APP_PORT (default 8000)
set -euo pipefail
cd "$(dirname "$0")/../.." # repo root

# shellcheck disable=SC1091
[ -f .env ] && . ./.env
PROM="http://localhost:${PROMETHEUS_PORT:-9090}"
APP="http://localhost:${APP_PORT:-8000}"
LAT="${LAT:-700}"; ERR="${ERR:-0.6}"; WAIT="${WAIT:-60}"
SVC="${SERVICE:-payments-api}"   # which service to drive/measure (payments-api | ledger-api)

# Instant PromQL query -> scalar value (or "n/a" when no series yet).
q() {
  curl -s -G "$PROM/api/v1/query" --data-urlencode "query=$1" | python3 -c '
import sys, json
r = json.load(sys.stdin).get("data", {}).get("result", [])
print(round(float(r[0]["value"][1]), 4) if r else "n/a")'
}

ERRQ="sum(rate(traces_spanmetrics_calls_total{service=\"$SVC\",status_code=\"STATUS_CODE_ERROR\"}[1m]))/sum(rate(traces_spanmetrics_calls_total{service=\"$SVC\"}[1m]))"
P95Q="histogram_quantile(0.95, sum by (le) (rate(traces_spanmetrics_latency_bucket{service=\"$SVC\"}[1m])))"

if ! curl -sf -o /dev/null "$APP/healthz"; then
  echo "✗ $SVC not reachable at $APP — run 'make demo-up' first"; exit 1
fi
echo "testing service=$SVC at $APP"

printf '%-12s err_ratio=%s  p95=%ss\n' "baseline:" "$(q "$ERRQ")" "$(q "$P95Q")"
printf '%-12s +%sms latency, +%.0f%% errors for %ss…\n' "degrading:" "$LAT" "$(python3 -c "print($ERR*100)")" "$WAIT"
curl -s "$APP/admin/degrade?latency=$LAT&errors=$ERR" >/dev/null

sleep "$WAIT"
printf '%-12s err_ratio=%s  p95=%ss\n' "under load:" "$(q "$ERRQ")" "$(q "$P95Q")"

curl -s "$APP/admin/heal" >/dev/null
printf '%-12s back to baseline (watch it recover in Grafana / the payments-api dashboard)\n' "healed:"
