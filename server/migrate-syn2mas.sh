#!/usr/bin/env sh
# One-time Synapse → MAS user/session migration. Safe to re-run: skips when marked.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
if [ -f "$root/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$root/.env"
  set +a
fi

compose_file="${COMPOSE_FILE:-docker-compose.prod.yml}"
marker="/data/mas-migrated"

cd "$root"

# Stop auth processes before rewriting Synapse/MAS config on an existing host.
docker compose -f "$compose_file" stop synapse mas 2>/dev/null || true

docker compose -f "$compose_file" run --rm --no-deps mas-config-generate
docker compose -f "$compose_file" run --rm --no-deps mas-db-init
docker compose -f "$compose_file" run --rm --no-deps mas-config
docker compose -f "$compose_file" run --rm --no-deps synapse-config

if docker compose -f "$compose_file" run --rm --no-deps --entrypoint /busybox/sh \
  mas-config-generate -c "test -f ${marker}"; then
  echo "MAS migration marker present; skipping syn2mas"
  exit 0
fi

echo "Running one-time syn2mas migration (Synapse/MAS downtime)"
docker compose -f "$compose_file" --profile migrate run --rm mas-migrate

docker compose -f "$compose_file" run --rm --no-deps --entrypoint /busybox/sh \
  mas-config-generate -c "touch ${marker} && chmod 644 ${marker}"

echo "syn2mas migration complete"
