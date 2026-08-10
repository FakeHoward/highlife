#!/usr/bin/env python3
"""Overlay HighLife runtime settings onto a generated MAS base config."""

from __future__ import annotations

import os
import urllib.parse
from pathlib import Path

import yaml


DATA = Path(os.environ.get("MAS_DATA_DIR", "/data"))
BASE = DATA / "config.base.yaml"
OUTPUT = DATA / "config.yaml"


def required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


def truthy(name: str, default: str = "false") -> bool:
    return os.environ.get(name, default).lower() in {"1", "true", "yes", "on"}


server_name = required("SYNAPSE_SERVER_NAME")
mas_password = required("MAS_POSTGRES_PASSWORD")
matrix_secret = required("MAS_MATRIX_SECRET")

if server_name in {"localhost", "127.0.0.1"}:
    public_base = os.environ.get("MAS_PUBLIC_BASE", "http://127.0.0.1:8083/").strip()
else:
    public_base = os.environ.get(
        "MAS_PUBLIC_BASE", f"https://auth.{server_name}/"
    ).strip()
if not public_base.endswith("/"):
    public_base += "/"

if not BASE.is_file() or BASE.stat().st_size == 0:
    raise RuntimeError(f"Missing MAS base config at {BASE}")

config = yaml.safe_load(BASE.read_text(encoding="utf-8"))
if not isinstance(config, dict):
    raise RuntimeError("MAS base config must be a YAML mapping")

# Preserve secrets.keys / secrets.encryption from the generated base.
http = config.setdefault("http", {})
http["public_base"] = public_base
http["issuer"] = public_base
http["listeners"] = [
    {
        "name": "web",
        "resources": [
            {"name": "discovery"},
            {"name": "human"},
            {"name": "oauth"},
            {"name": "compat"},
            {"name": "graphql", "playground": False},
            {"name": "assets"},
            {"name": "health"},
        ],
        "binds": [{"address": "[::]:8080"}],
    }
]

password_quoted = urllib.parse.quote(mas_password, safe="")
config["database"] = {
    "uri": f"postgresql://mas:{password_quoted}@postgres:5432/mas?sslmode=disable",
}

config["matrix"] = {
    "kind": "synapse",
    "homeserver": server_name,
    "endpoint": "http://synapse:8008/",
    "secret": matrix_secret,
}

config["passwords"] = {
    "enabled": True,
    "schemes": [
        {
            "version": 1,
            "algorithm": "bcrypt",
            "unicode_normalization": True,
        },
        {
            "version": 2,
            "algorithm": "argon2id",
        },
    ],
}

account = config.setdefault("account", {})
account["password_registration_enabled"] = truthy(
    "SYNAPSE_ENABLE_REGISTRATION", "true"
)
account["password_registration_email_required"] = False
account["password_recovery_enabled"] = False
account["login_with_email_allowed"] = False

OUTPUT.write_text(
    "# Generated at runtime; never commit this file.\n"
    + yaml.safe_dump(config, sort_keys=False),
    encoding="utf-8",
)
OUTPUT.chmod(0o640)
print(f"MAS configuration ready for {server_name} ({public_base})")
