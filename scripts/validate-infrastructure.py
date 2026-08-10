#!/usr/bin/env python3
"""Static validation for the deployable Matrix infrastructure."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "server"
DOMAIN = "testhighlife.strangled.net"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        value = yaml.safe_load(handle)
    require(isinstance(value, dict), f"{path} must contain a YAML mapping")
    return value


def validate_compose(path: Path, production: bool) -> None:
    compose = load_yaml(path)
    services = compose.get("services", {})
    required = {
        "postgres",
        "mas-db-init",
        "mas-config-generate",
        "mas-config",
        "mas",
        "synapse-config",
        "synapse",
        "redis",
        "livekit",
        "lk-jwt-service",
        "element-call",
    }
    if production:
        required |= {"caddy", "bot", "coturn"}
    require(required <= set(services), f"{path}: missing services {sorted(required - set(services))}")
    require("conduit" not in services, f"{path}: Conduit must not be present")

    synapse = services["synapse"]
    require(synapse.get("image") == "matrixdotorg/synapse:v1.158.0", f"{path}: Synapse image must be pinned")
    require("healthcheck" in synapse, f"{path}: Synapse requires a healthcheck")
    require("healthcheck" in services["postgres"], f"{path}: PostgreSQL requires a healthcheck")
    require("healthcheck" in services["livekit"], f"{path}: LiveKit requires a healthcheck")
    require(
        services["mas"].get("image")
        == "ghcr.io/element-hq/matrix-authentication-service:1.22.0",
        f"{path}: MAS image must be pinned",
    )
    require("healthcheck" in services["mas"], f"{path}: MAS requires a healthcheck")
    require(
        services["element-call"].get("image") == "ghcr.io/element-hq/element-call:v0.23.0",
        f"{path}: Element Call image must be pinned",
    )

    rendered = yaml.safe_dump(compose, sort_keys=False)
    require("${SYNAPSE_REGISTRATION_SECRET" in rendered, f"{path}: registration secret must be injected")
    require("${MAS_POSTGRES_PASSWORD" in rendered, f"{path}: MAS database secret must be injected")
    require("${MAS_MATRIX_SECRET" in rendered, f"{path}: MAS shared secret must be injected")
    require("${LIVEKIT_SECRET" in rendered, f"{path}: LiveKit secret must be injected")
    require("${TURN_SHARED_SECRET" in rendered, f"{path}: TURN secret must be injected")

    if production:
        ports = services["livekit"].get("ports", [])
        require(any("50000-50100" in str(port) and "udp" in str(port) for port in ports), "LiveKit UDP range missing")
        require(any("3478" in str(port) and "udp" in str(port) for port in services["coturn"].get("ports", [])), "TURN UDP port missing")
        bot = services["bot"]
        require("/highlife-formspace-bot:" in bot.get("image", ""), "production bot image must use highlife-formspace-bot")
        bot_environment = bot.get("environment", {})
        require("highlifebot" in bot_environment.get("MATRIX_USER_ID", ""), "production bot MXID must use highlifebot")
        require(bot_environment.get("MATRIX_CRYPTO") == "true", "production bot crypto must be enabled")
        # Public client API via Caddy so login/logout/refresh hit MAS compat.
        require(
            bot_environment.get("MATRIX_HOMESERVER") == f"https://{DOMAIN}",
            "production bot must use the public homeserver URL (MAS compat)",
        )
        require(
            "${BOT_CRYPTO_STORE_PASSPHRASE" in bot_environment.get("MATRIX_CRYPTO_STORE_PASSPHRASE", ""),
            "bot crypto store passphrase must be injected",
        )
        require(
            bot_environment.get("MATRIX_MINIAPP_URL") == f"https://{DOMAIN}/miniapp/",
            "production bot MiniApp URL must be /miniapp/",
        )
        require(
            "${MATRIX_MINIAPP_SECRET" in bot_environment.get("MATRIX_MINIAPP_SECRET", ""),
            "production bot must accept optional MATRIX_MINIAPP_SECRET",
        )
        require(
            "${MATRIX_MINIAPP_CORS_ORIGIN" in bot_environment.get("MATRIX_MINIAPP_CORS_ORIGIN", ""),
            "production bot must inject MATRIX_MINIAPP_CORS_ORIGIN",
        )
        require(
            "${SYNAPSE_ENABLE_REGISTRATION" in rendered,
            f"{path}: SYNAPSE_ENABLE_REGISTRATION must be injectable",
        )
        require(
            "migrate" in (services.get("mas-migrate", {}).get("profiles") or []),
            f"{path}: mas-migrate must use Compose profile migrate",
        )
        sygnal = services.get("sygnal")
        require(isinstance(sygnal, dict), f"{path}: missing optional sygnal service")
        require(
            "push" in (sygnal.get("profiles") or []),
            f"{path}: sygnal must use Compose profile push",
        )
        require("matrixdotorg/sygnal:" in sygnal.get("image", ""), f"{path}: sygnal image must be pinned")
        require((SERVER / "sygnal.yaml").is_file(), "server/sygnal.yaml is required")


def validate_static_config() -> None:
    element = json.loads((SERVER / "element-call-config.json").read_text(encoding="utf-8"))
    homeserver = element["default_server_config"]["m.homeserver"]
    require(homeserver["server_name"] == DOMAIN, "Element Call server_name is incorrect")
    require(homeserver["base_url"] == f"https://{DOMAIN}", "Element Call base_url is incorrect")
    require(
        element["livekit"]["livekit_service_url"] == f"https://rtc.{DOMAIN}/livekit/jwt",
        "Element Call LiveKit URL is incorrect",
    )

    template = (SERVER / "Caddyfile.template").read_text(encoding="utf-8")
    require("__MATRIX_DOMAIN__" in template, "Caddyfile.template must use __MATRIX_DOMAIN__ placeholders")
    require("push.__MATRIX_DOMAIN__" in template, "Caddyfile.template must define push.__MATRIX_DOMAIN__")
    require("reverse_proxy sygnal:5000" in template, "Caddyfile.template must proxy push to sygnal")
    require("auth.__MATRIX_DOMAIN__" in template, "Caddyfile.template must define auth.__MATRIX_DOMAIN__")
    require("org.matrix.msc2965.authentication" in template, "Caddyfile.template must advertise MAS")
    require("reverse_proxy mas:8080" in template, "Caddyfile.template must proxy auth to MAS")
    rendered_from_template = template.replace("__MATRIX_DOMAIN__", DOMAIN)
    caddy = (SERVER / "Caddyfile").read_text(encoding="utf-8")
    require(
        caddy == rendered_from_template,
        "Caddyfile must match Caddyfile.template rendered with the default domain",
    )
    for fragment in (
        DOMAIN,
        f"auth.{DOMAIN}",
        f"call.{DOMAIN}",
        f"rtc.{DOMAIN}",
        f"push.{DOMAIN}",
        "/.well-known/matrix/client",
        "/.well-known/matrix/server",
        "org.matrix.msc4143.rtc_foci",
        "org.matrix.msc2965.authentication",
        "Strict-Transport-Security",
        "default-src 'self'",
        "script-src 'self' 'unsafe-inline'",
        "worker-src 'self' blob:",
        'frame-ancestors https://testhighlife.strangled.net',
        'camera=(self \\"https://call.testhighlife.strangled.net\\")',
        "handle_path /flutter/*",
        "handle_path /miniapp/*",
        "handle_path /miniapp-api/*",
        "root * /srv/react",
        "root * /srv/flutter",
        "root * /srv/miniapp",
        "reverse_proxy sygnal:5000",
        "reverse_proxy mas:8080",
    ):
        require(fragment in caddy, f"Caddyfile is missing {fragment}")

    call_block = caddy.split(f"call.{DOMAIN} {{", 1)[1].split(f"rtc.{DOMAIN} {{", 1)[0]
    require("-X-Frame-Options" in call_block, "Element Call must strip upstream X-Frame-Options")
    require(
        '\t\tX-Frame-Options "' not in call_block,
        "Element Call must not set X-Frame-Options",
    )

    render_py = (SERVER / "render-synapse-config.py").read_text(encoding="utf-8")
    require(
        "matrix_authentication_service" in render_py,
        "render-synapse-config.py must delegate authentication to MAS",
    )
    require("msc4108_enabled" in render_py, "render-synapse-config.py must enable QR login")
    require((SERVER / "render-mas-config.py").is_file(), "server/render-mas-config.py is required")

    deploy = (ROOT / ".github" / "workflows" / "deploy.yml").read_text(encoding="utf-8")
    for fragment in (
        "npm ci",
        "npm run build",
        "VITE_ELEMENT_CALL_URL: https://call.testhighlife.strangled.net",
        "VITE_DEFAULT_HOMESERVER: https://testhighlife.strangled.net",
        "--project-name highlife_client",
        "--org app.highlife",
        "--base-href /flutter/",
        "DOMAIN=",
        "m.login.password",
        "recover-bot.yml",
        "DEPLOY_SSH_KEY",
        "key: ${{ secrets.DEPLOY_SSH_KEY }}",
        "Caddyfile.template",
        "default-src",
        "sygnal.yaml",
        "MAS_POSTGRES_PASSWORD",
        "MAS_MATRIX_SECRET",
        "migrate-syn2mas.sh",
        "org.matrix.msc2965.authentication",
        "auth.${MATRIX_DOMAIN}",
    ):
        require(fragment in deploy, f"deploy workflow is missing {fragment}")
    require(
        "DEPLOY_SSH_KEY" in deploy and "or DEPLOY_PASSWORD" in deploy,
        "deploy workflow must accept DEPLOY_SSH_KEY or DEPLOY_PASSWORD",
    )
    require(
        (SERVER / "migrate-syn2mas.sh").is_file(),
        "server/migrate-syn2mas.sh is required",
    )
    require(
        (SERVER / "generate-mas-config.sh").is_file(),
        "server/generate-mas-config.sh is required",
    )
    require((SERVER / "init-mas-db.sh").is_file(), "server/init-mas-db.sh is required")
    for workflow_name in ("recover-bot.yml", "diagnose-bot.yml"):
        workflow = (ROOT / ".github" / "workflows" / workflow_name).read_text(encoding="utf-8")
        require(
            "key: ${{ secrets.DEPLOY_SSH_KEY }}" in workflow,
            f"{workflow_name} must pass DEPLOY_SSH_KEY",
        )
        require(
            "DEPLOY_SSH_KEY" in workflow and "DEPLOY_PASSWORD" in workflow,
            f"{workflow_name} must document key-or-password auth",
        )
    # Routine deploy must not actively wipe bot crypto (recover-bot keeps that).
    wipe_cmd = (
        "find /app/data -mindepth 1 -maxdepth 1 ! -name formspace.json "
        "! -name crypto-passphrase.json -exec rm -rf {} +"
    )
    active_wipe_lines = [
        line
        for line in deploy.splitlines()
        if wipe_cmd in line and not line.lstrip().startswith("#")
    ]
    require(not active_wipe_lines, "deploy workflow still has an active bot crypto wipe")
    require(
        "Intentionally not wiping crypto" in deploy or f"# {wipe_cmd}" in deploy or f"# find /app/data" in deploy,
        "deploy workflow should document that crypto wipe is disabled",
    )

    bot_workflow = (ROOT / ".github" / "workflows" / "bot.yml").read_text(encoding="utf-8")
    for fragment in ("npm test", "npm run typecheck", "/highlife-formspace-bot:"):
        require(fragment in bot_workflow, f"bot workflow is missing {fragment}")

    client_workflow = (ROOT / ".github" / "workflows" / "client.yml").read_text(encoding="utf-8")
    require("--project-name highlife_client" in client_workflow, "Flutter CI project name is incorrect")
    require("--org app.highlife" in client_workflow, "Flutter CI organization is incorrect")
    require("relay-" not in client_workflow, "Flutter CI still contains Relay artifact identifiers")


def docker_compose_config(path: Path) -> None:
    docker = shutil.which("docker")
    if not docker:
        print("docker not found; skipped docker compose config")
        return

    env = os.environ.copy()
    env.update(
        {
            "POSTGRES_PASSWORD": "validation-only",
            "SYNAPSE_REGISTRATION_SECRET": "validation-only",
            "MAS_POSTGRES_PASSWORD": "validation-only",
            "MAS_MATRIX_SECRET": "validation-only-mas-matrix-secret-32b",
            "BOT_MATRIX_PASSWORD": "validation-only",
            "BOT_CRYPTO_STORE_PASSPHRASE": "validation-only",
            "LIVEKIT_KEY": "validation-key",
            "LIVEKIT_SECRET": "validation-only",
            "TURN_SHARED_SECRET": "validation-only",
            "DEPLOY_PUBLIC_IP": "203.0.113.10",
            "GITHUB_REPOSITORY_OWNER": "validation",
            "BOT_IMAGE_TAG": "validation",
        }
    )
    subprocess.run(
        [docker, "compose", "-f", str(path), "config", "--quiet"],
        cwd=SERVER,
        env=env,
        check=True,
    )


def main() -> int:
    production = SERVER / "docker-compose.prod.yml"
    local = SERVER / "docker-compose.yml"
    validate_compose(local, production=False)
    validate_compose(production, production=True)
    validate_static_config()
    docker_compose_config(local)
    docker_compose_config(production)
    print("Infrastructure configuration is valid")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, OSError, ValueError, yaml.YAMLError, subprocess.CalledProcessError) as error:
        print(f"validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
