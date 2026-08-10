#!/usr/bin/env bash
# Backup Synapse DB, media, and bot data volumes on the HighLife VPS.
# Run from the compose directory (e.g. /opt/highlife) as root/cron.
set -euo pipefail

ROOT="${HIGHLIFE_ROOT:-/opt/highlife}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${HIGHLIFE_BACKUP_DIR:-/var/backups/highlife}/$STAMP"
COMPOSE="${HIGHLIFE_COMPOSE:-docker-compose.prod.yml}"

mkdir -p "$OUT"
cd "$ROOT"

echo "Backing up to $OUT"

if docker compose -f "$COMPOSE" ps postgres >/dev/null 2>&1; then
  docker compose -f "$COMPOSE" exec -T postgres \
    pg_dump -U "${POSTGRES_USER:-synapse}" "${POSTGRES_DB:-synapse}" \
    | gzip >"$OUT/synapse.sql.gz"
fi

# Named volumes — adjust names if compose project prefix differs.
for volume in highlife_synapse-data highlife_mas-data highlife_bot-data highlife_caddy-data; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker run --rm -v "$volume:/data:ro" -v "$OUT:/backup" alpine \
      tar czf "/backup/${volume}.tar.gz" -C /data .
  fi
done

# Keep last 14 backups
if [[ -d "$(dirname "$OUT")" ]]; then
  ls -1dt "$(dirname "$OUT")"/*/ 2>/dev/null | tail -n +15 | xargs -r rm -rf
fi

echo "Backup complete: $OUT"
