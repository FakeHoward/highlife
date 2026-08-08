#!/usr/bin/env sh
# Idempotently create private accounts through Synapse's shared-secret helper.
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

  echo "Ensuring @${localpart}:testhighlife.strangled.net exists"
  if output="$(docker compose -f "$compose_file" exec -T synapse \
    register_new_matrix_user \
    --config /data/homeserver.yaml \
    --user "$localpart" \
    --password "$password" \
    --no-admin \
    http://127.0.0.1:8008 2>&1)"; then
    echo "${label} account created"
    return 0
  fi

  if printf '%s' "$output" | grep -qiE 'already exists|M_USER_IN_USE|already taken'; then
    echo "${label} account already exists"
    return 0
  fi

  printf '%s\n' "$output" >&2
  return 1
}

register_account "${BOT_LOCALPART:-highlifebot}" "${BOT_MATRIX_PASSWORD:?BOT_MATRIX_PASSWORD is required}" "Bot"

if [ -n "${DEMO_MATRIX_PASSWORD:-}" ]; then
  register_account "${DEMO_LOCALPART:-demo}" "$DEMO_MATRIX_PASSWORD" "Demo"
fi
