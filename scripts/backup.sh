#!/usr/bin/env bash
# Back up all stateful Docker volumes to ./backups/<timestamp>/.
# Config (config/, dashboards/, .env) lives in git — only the volumes hold
# runtime state, so that's what we snapshot here.
#
# Usage: ./scripts/backup.sh   (or: make backup)
# Tip:   stop the stack first for a fully consistent snapshot: make down
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; . ./.env; set +a
PROJECT="${COMPOSE_PROJECT_NAME:-observability}"
TS="$(date +%Y%m%d-%H%M%S)"
DEST="backups/${TS}"
mkdir -p "$DEST"

# Volumes declared in docker-compose.yml
VOLUMES=(grafana-data prometheus-data loki-data tempo-data alertmanager-data alloy-data)

for v in "${VOLUMES[@]}"; do
  full="${PROJECT}_${v}"
  if docker volume inspect "$full" >/dev/null 2>&1; then
    echo ">> backing up ${full}"
    docker run --rm \
      -v "${full}:/data:ro" \
      -v "$(pwd)/${DEST}:/backup" \
      alpine tar czf "/backup/${v}.tar.gz" -C /data .
  else
    echo "   skip (volume not found): ${full}"
  fi
done

echo "Backup complete -> ${DEST}/"
