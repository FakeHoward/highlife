#!/usr/bin/env sh
# Generate a one-time MAS base config (secrets/keys). Redeploys keep the file.
set -eu

data_dir="${MAS_DATA_DIR:-/data}"
base_config="${data_dir}/config.base.yaml"

mkdir -p "$data_dir"

if [ -s "$base_config" ]; then
  echo "MAS base config already present; keeping encryption/signing secrets"
  exit 0
fi

echo "Generating MAS base configuration with fresh secrets"
/usr/local/bin/mas-cli config generate --output "$base_config"

if [ ! -s "$base_config" ]; then
  echo "MAS base config was not created" >&2
  ls -la "$data_dir" >&2 || true
  exit 1
fi

chmod 640 "$base_config" 2>/dev/null || true
echo "MAS base configuration ready"
