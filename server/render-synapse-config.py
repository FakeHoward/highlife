#!/usr/bin/env python3
"""Turn a freshly generated Synapse config into the HighLife config."""

from __future__ import annotations

import os
from pathlib import Path

import yaml


DATA = Path(os.environ.get("SYNAPSE_DATA_DIR", "/data"))
CONFIG = DATA / "homeserver.yaml"


def required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


server_name = required("SYNAPSE_SERVER_NAME")
public_baseurl = os.environ.get("SYNAPSE_PUBLIC_BASEURL", "").strip()
if not public_baseurl:
    if server_name in {"localhost", "127.0.0.1"}:
        public_baseurl = "http://127.0.0.1:8008/"
    else:
        public_baseurl = f"https://{server_name}/"

turn_host = os.environ.get("SYNAPSE_TURN_HOST", "").strip()
if not turn_host:
    turn_host = "127.0.0.1" if server_name in {"localhost", "127.0.0.1"} else f"rtc.{server_name}"

mas_secret = required("MAS_MATRIX_SECRET")
mas_endpoint = os.environ.get("MAS_ENDPOINT", "http://mas:8080/").strip()
if not mas_endpoint.endswith("/"):
    mas_endpoint += "/"

config = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
config.update(
    {
        "server_name": server_name,
        "public_baseurl": public_baseurl,
        "pid_file": str(DATA / "homeserver.pid"),
        "signing_key_path": str(DATA / f"{server_name}.signing.key"),
        "database": {
            "name": "psycopg2",
            "args": {
                "user": "synapse",
                "password": required("POSTGRES_PASSWORD"),
                "database": "synapse",
                "host": "postgres",
                "port": 5432,
                "cp_min": 5,
                "cp_max": 10,
            },
        },
        "listeners": [
            {
                "port": 8008,
                "tls": False,
                "type": "http",
                "x_forwarded": True,
                "bind_addresses": ["0.0.0.0"],
                "resources": [{"names": ["client", "federation", "openid"], "compress": False}],
            }
        ],
        # Auth/registration are owned by Matrix Authentication Service. Keep
        # Synapse registration closed; MAS account.password_registration_*
        # is controlled by SYNAPSE_ENABLE_REGISTRATION in render-mas-config.py.
        "enable_registration": False,
        "enable_registration_without_verification": False,
        "registration_shared_secret": required("SYNAPSE_REGISTRATION_SECRET"),
        "allow_public_rooms_without_auth": False,
        "allow_public_rooms_over_federation": True,
        "trusted_key_servers": [{"server_name": "matrix.org"}],
        "suppress_key_server_warning": True,
        "turn_uris": [
            f"turn:{turn_host}:3478?transport=udp",
            f"turn:{turn_host}:3478?transport=tcp",
        ],
        "turn_shared_secret": required("TURN_SHARED_SECRET"),
        "turn_user_lifetime": 86_400_000,
        "turn_allow_guests": False,
        "matrix_authentication_service": {
            "enabled": True,
            "endpoint": mas_endpoint,
            "secret": mas_secret,
        },
        "experimental_features": {
            "msc3266_enabled": True,
            "msc3381_polls_enabled": True,
            "msc3664_enabled": True,
            "msc3773_enabled": True,
            "msc3874_enabled": True,
            "msc3912_enabled": True,
            "msc4028_push_encrypted_events": True,
            "msc4076_enabled": True,
            "msc4108_enabled": True,
            "msc4133_enabled": True,
            "msc4140_enabled": True,
            "msc4143_enabled": True,
            "msc4222_enabled": True,
            "msc4235_enabled": True,
            "msc4306_enabled": True,
            "msc4388_mode": "open",
            "msc4446_enabled": True,
            "msc4452_enabled": True,
        },
        "report_stats": False,
        "media_store_path": str(DATA / "media_store"),
        # Defaults are too tight for a public test HS plus a bot that may
        # re-login after deploys. Keep failed-attempt limits meaningful.
        "rc_login": {
            "address": {"per_second": 1.0, "burst_count": 20},
            "account": {"per_second": 1.0, "burst_count": 10},
            "failed_attempts": {"per_second": 0.5, "burst_count": 5},
        },
    }
)

# Synapse-native OIDC is incompatible with delegated MAS auth. Configure
# upstream IdPs in Matrix Authentication Service instead.
config.pop("oidc_providers", None)

CONFIG.write_text(
    "# Generated locally/deployed at runtime; never commit this file.\n"
    + yaml.safe_dump(config, sort_keys=False),
    encoding="utf-8",
)
