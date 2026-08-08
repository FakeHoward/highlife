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
        # Release default is closed registration. Local compose sets
        # SYNAPSE_ENABLE_REGISTRATION=true; shared-secret bootstrap still
        # creates bot/demo accounts when public signup is off.
        "enable_registration": os.environ.get(
            "SYNAPSE_ENABLE_REGISTRATION", "false"
        ).lower()
        in {"1", "true", "yes", "on"},
        "enable_registration_without_verification": os.environ.get(
            "SYNAPSE_ENABLE_REGISTRATION", "false"
        ).lower()
        in {"1", "true", "yes", "on"},
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
        "experimental_features": {
            "msc3266_enabled": True,
            "msc4140_enabled": True,
            "msc4222_enabled": True,
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

oidc_issuer = os.environ.get("OIDC_ISSUER", "").strip()
oidc_client_id = os.environ.get("OIDC_CLIENT_ID", "").strip()
oidc_client_secret = os.environ.get("OIDC_CLIENT_SECRET", "").strip()
if oidc_issuer and oidc_client_id and oidc_client_secret:
    idp_id = os.environ.get("OIDC_IDP_ID", "").strip() or "oidc"
    idp_name = os.environ.get("OIDC_IDP_NAME", "").strip() or "OIDC"
    scopes_raw = os.environ.get("OIDC_SCOPES", "").strip()
    scopes = [s for s in scopes_raw.split() if s] if scopes_raw else [
        "openid",
        "profile",
        "email",
    ]
    localpart_template = (
        os.environ.get("OIDC_LOCALPART_TEMPLATE", "").strip()
        or "{{ user.preferred_username }}"
    )
    display_name_template = (
        os.environ.get("OIDC_DISPLAY_NAME_TEMPLATE", "").strip()
        or "{{ user.name }}"
    )
    config["oidc_providers"] = [
        {
            "idp_id": idp_id,
            "idp_name": idp_name,
            "issuer": oidc_issuer,
            "client_id": oidc_client_id,
            "client_secret": oidc_client_secret,
            "scopes": scopes,
            "user_mapping_provider": {
                "config": {
                    "localpart_template": localpart_template,
                    "display_name_template": display_name_template,
                }
            },
        }
    ]
elif any([oidc_issuer, oidc_client_id, oidc_client_secret]):
    raise RuntimeError(
        "OIDC is partially configured: set OIDC_ISSUER, OIDC_CLIENT_ID, and "
        "OIDC_CLIENT_SECRET together (or leave all unset)"
    )

CONFIG.write_text(
    "# Generated locally/deployed at runtime; never commit this file.\n"
    + yaml.safe_dump(config, sort_keys=False),
    encoding="utf-8",
)
