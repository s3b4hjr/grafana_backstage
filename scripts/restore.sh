#!/usr/bin/env bash
# Restore Docker volumes from a backup directory created by backup.sh.
# STOP THE STACK FIRST (make down) — restoring under a running Loki/Prometheus
# corrupts their TSDB.
#
# Usage: ./scripts/restore.sh backups/<timestamp>   (or: make restore SRC=backups/<timestamp>)
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; . ./.env; set +a
PROJECT="${COMPOSE_PROJECT_NAME:-observability}"
SRC="${1:?usage: restore.sh backups/<timestamp>}"
[ -d "$SRC" ] || { echo "ERROR: no such backup dir: $SRC"; exit 1; }

VOLUMES=(grafana-data prometheus-data loki-data tempo-data alertmanager-data alloy-data)

for v in "${VOLUMES[@]}"; do
  archive="${SRC}/${v}.tar.gz"
  [ -f "$archive" ] || { echo "   skip (no archive): ${archive}"; continue; }
  full="${PROJECT}_${v}"
  docker volume create "$full" >/dev/null
  echo ">> restoring ${full} from ${archive}"
  docker run --rm \
    -v "${full}:/data" \
    -v "$(pwd)/${SRC}:/backup:ro" \
    alpine sh -c "rm -rf /data/* /data/..?* 2>/dev/null || true; tar xzf /backup/${v}.tar.gz -C /data"
done

echo "Restore complete. Start the stack with: make up"
