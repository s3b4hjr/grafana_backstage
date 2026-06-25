#!/usr/bin/env bash
# Optional: download popular community dashboards from grafana.com and rewrite
# their datasource placeholders to this stack's fixed UIDs (prometheus/loki).
# They land in ./dashboards/community and are auto-loaded by Grafana provisioning.
#
# Requires: curl, jq
# Usage:    ./scripts/fetch-dashboards.sh
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="dashboards/community"
mkdir -p "$OUT"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq / apt-get install jq)"; exit 1; }

# id:slug — curated, datasource-agnostic dashboards
DASHBOARDS=(
  "1860:node-exporter-full"
  "14282:cadvisor-exporter"
  "13639:loki-logs"
  "7587:blackbox-exporter"
)

for entry in "${DASHBOARDS[@]}"; do
  id="${entry%%:*}"; slug="${entry##*:}"
  echo ">> ${slug} (gnetId ${id})"
  rev="$(curl -fsSL "https://grafana.com/api/dashboards/${id}" | jq -r '.revision')"
  curl -fsSL "https://grafana.com/api/dashboards/${id}/revisions/${rev}/download" \
    | sed -E 's/\$\{DS_PROMETHEUS\}/prometheus/g; s/\$\{DS_LOKI\}/loki/g; s/\$\{DS_TEMPO\}/tempo/g' \
    > "${OUT}/${slug}.json"
done

echo "Done. Dashboards written to ${OUT}/ — Grafana picks them up within ~30s."
