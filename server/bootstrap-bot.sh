#!/usr/bin/env sh
# Idempotently create private accounts through Matrix Authentication Service.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
if [ -f "$root/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$root/.env"
  set +a
fi

compose_file="${COMPOSE_FILE:-docker-compose.prod.yml}"

register_account() {
  localpart="$1"
  password="$2"
  label="$3"

  [ -n "$password" ] || {
    echo "${label} password is required" >&2
    return 1
  }

  echo "Ensuring @${localpart}:testhighlife.strangled.net exists via MAS"
  # Image ENTRYPOINT is mas-cli.
  if output="$(docker compose -f "$compose_file" exec -T mas \
    --config /data/config.yaml manage register-user \
    --yes \
    --username "$localpart" \
    --password "$password" \
    --no-admin \
    --ignore-password-complexity 2>&1)"; then
    echo "${label} account created"
    return 0
  fi

  if printf '%s' "$output" | grep -qiE 'already exists|already taken|M_USER_IN_USE|Username already taken|user already exists'; then
    echo "${label} account already exists"
    return 0
  fi

  printf '%s\n' "$output" >&2
  return 1
}

# Wait briefly for MAS to accept management commands after compose up.
ready=0
for _ in $(seq 1 30); do
  if docker compose -f "$compose_file" exec -T mas \
    --config /data/config.yaml config check >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [ "$ready" != 1 ]; then
  echo "MAS is not ready for account bootstrap" >&2
  docker compose -f "$compose_file" ps mas || true
  docker compose -f "$compose_file" logs --tail=80 mas || true
  exit 1
fi

register_account "${BOT_LOCALPART:-highlifebot}" "${BOT_MATRIX_PASSWORD:?BOT_MATRIX_PASSWORD is required}" "Bot"

if [ -n "${DEMO_MATRIX_PASSWORD:-}" ]; then
  register_account "${DEMO_LOCALPART:-demo}" "$DEMO_MATRIX_PASSWORD" "Demo"
fi
