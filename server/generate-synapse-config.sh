#!/usr/bin/env sh
set -eu

data_dir="${SYNAPSE_DATA_DIR:-/data}"
config="${data_dir}/homeserver.yaml"
render_script="${RENDER_SYNAPSE_CONFIG:-/config/render-synapse-config.py}"

: "${SYNAPSE_SERVER_NAME:?SYNAPSE_SERVER_NAME is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${SYNAPSE_REGISTRATION_SECRET:?SYNAPSE_REGISTRATION_SECRET is required}"
: "${TURN_SHARED_SECRET:?TURN_SHARED_SECRET is required}"

key="${data_dir}/${SYNAPSE_SERVER_NAME}.signing.key"

mkdir -p "$data_dir"
echo "Generating Synapse homeserver for ${SYNAPSE_SERVER_NAME}"

# The official generator creates per-install secrets and the federation signing
# key. Existing keys are retained so redeploys do not break federation.
if [ ! -s "$config" ] || [ ! -s "$key" ]; then
  if [ -x /start.py ] || [ -f /start.py ]; then
    SYNAPSE_CONFIG_DIR="$data_dir" \
    SYNAPSE_CONFIG_PATH="$config" \
    SYNAPSE_SERVER_NAME="$SYNAPSE_SERVER_NAME" \
    SYNAPSE_REPORT_STATS=no \
      /start.py generate
  else
    python -m synapse.app.homeserver \
      --server-name "$SYNAPSE_SERVER_NAME" \
      --config-path "$config" \
      --generate-config \
      --report-stats=no
  fi
fi

if [ ! -s "$config" ]; then
  echo "homeserver.yaml was not created" >&2
  ls -la "$data_dir" >&2 || true
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  python3 "$render_script"
else
  python "$render_script"
fi

if [ ! -s "$key" ]; then
  found="$(find "$data_dir" -maxdepth 1 -type f -name '*.signing.key' | head -n 1 || true)"
  if [ -n "$found" ] && [ "$found" != "$key" ]; then
    cp "$found" "$key"
  fi
fi

chown -R 991:991 "$data_dir" 2>/dev/null || true
chmod 600 "$config" 2>/dev/null || true
if [ -s "$key" ]; then
  chmod 600 "$key" 2>/dev/null || true
fi
echo "Synapse configuration ready for ${SYNAPSE_SERVER_NAME}"
