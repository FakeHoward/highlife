#!/usr/bin/env bash
# Backup Synapse + MAS Postgres, media, and bot/Caddy volumes on the HighLife VPS.
# Run from the compose directory (e.g. /opt/highlife) as root/cron.
set -euo pipefail

ROOT="${HIGHLIFE_ROOT:-/opt/highlife}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${HIGHLIFE_BACKUP_DIR:-/var/backups/highlife}/$STAMP"
COMPOSE="${HIGHLIFE_COMPOSE:-docker-compose.prod.yml}"

mkdir -p "$OUT"
cd "$ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

echo "Backing up to $OUT"

if docker compose -f "$COMPOSE" ps postgres >/dev/null 2>&1; then
  docker compose -f "$COMPOSE" exec -T postgres \
    pg_dump -U "${POSTGRES_USER:-synapse}" "${POSTGRES_DB:-synapse}" \
    | gzip >"$OUT/synapse.sql.gz"
  # MAS DB is owned by role `mas`, not synapse.
  docker compose -f "$COMPOSE" exec -T \
    -e PGPASSWORD="${MAS_POSTGRES_PASSWORD:?MAS_POSTGRES_PASSWORD is required}" \
    postgres \
    pg_dump -U mas -d mas \
    | gzip >"$OUT/mas.sql.gz"
fi

# Named volumes — adjust names if compose project prefix differs.
for volume in highlife_synapse-data highlife_mas-data highlife_bot-data highlife_caddy-data highlife_postgres-data; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker run --rm -v "$volume:/data:ro" -v "$OUT:/backup" alpine \
      tar czf "/backup/${volume}.tar.gz" -C /data .
  fi
done

# Keep last 14 backups (stamp dirs sort lexicographically).
backup_root="$(dirname "$OUT")"
if [[ -d "$backup_root" ]]; then
  find "$backup_root" -mindepth 1 -maxdepth 1 -type d \
    | sort \
    | head -n -14 \
    | xargs -r rm -rf
fi

echo "Backup complete: $OUT"
