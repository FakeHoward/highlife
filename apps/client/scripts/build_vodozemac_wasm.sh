#!/usr/bin/env bash
# Build famedly dart-vodozemac WASM into apps/client/web/pkg/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
version=$(python3 - <<'PY'
import re
from pathlib import Path
text = Path("pubspec.yaml").read_text()
m = re.search(r"flutter_vodozemac:\s*\^?([0-9.]+)", text)
print(m.group(1) if m else "0.6.0")
PY
)
rm -rf .vodozemac
git clone --depth 1 --branch "${version}" https://github.com/famedly/dart-vodozemac.git .vodozemac
cd .vodozemac
cargo install flutter_rust_bridge_codegen --locked || cargo install flutter_rust_bridge_codegen
flutter_rust_bridge_codegen build-web --dart-root dart --rust-root "$(pwd)/rust" --release
cd "$ROOT"
mkdir -p web
rm -rf web/pkg
mv .vodozemac/dart/web/pkg web/pkg
rm -rf .vodozemac
echo "Wrote $ROOT/web/pkg"
