# HighLife Matrix infrastructure

The production stack is a fresh federated Synapse deployment for
`testhighlife.strangled.net`. It includes PostgreSQL, Caddy TLS, Redis,
LiveKit, the MatrixRTC JWT service, Element Call, coturn, and the HighLife bot.
Public registration is **disabled by default** in production
(`SYNAPSE_ENABLE_REGISTRATION=false`). Set it to `true` in `/opt/highlife/.env`
only when intentionally opening signup. Local `docker-compose.yml` defaults
registration to on for development/CI. Bot/demo accounts are still created with
Synapse's shared-secret registration helper.

Caddy hostnames come from `Caddyfile.template` (`__MATRIX_DOMAIN__`). Deploy
renders them from the `MATRIX_DOMAIN` / `DOMAIN` secret (default
`testhighlife.strangled.net`). The committed `Caddyfile` matches that default.

## Local development

Docker Desktop is required. The helper generates random secrets in the
gitignored `server/.env`, starts Synapse and MatrixRTC, waits for health, and
creates `alice`, `bob`, and `bot`:

```powershell
.\scripts\stack.ps1
```

Local endpoints:

- Synapse: `http://localhost:8008`
- Element Call: `http://localhost:8081`
- LiveKit JWT service: `http://localhost:8082`
- LiveKit signalling: `ws://localhost:7880`
- LiveKit media: TCP `7881`, UDP `50000-50100`
- coturn: TCP/UDP `3478`, relay UDP `49160-49200`

Create another private account:

```powershell
cd server
.\register.ps1 -Username charlie -Password "local-password"
```

Stop without deleting data:

```powershell
docker compose down
```

Use `docker compose down -v` only when you intentionally want to destroy the
local development data.

## Production routing

- `https://testhighlife.strangled.net/`: primary React client, Matrix client
  API, federation API, and Matrix well-known discovery
- `https://testhighlife.strangled.net/flutter/`: Flutter web client
- `https://call.testhighlife.strangled.net`: Element Call
- `https://rtc.testhighlife.strangled.net/livekit/jwt`: MatrixRTC
  authorization
- `wss://rtc.testhighlife.strangled.net/livekit/sfu`: LiveKit signalling
- `rtc.testhighlife.strangled.net:3478`: coturn (UDP/TCP)
- `https://push.testhighlife.strangled.net/_matrix/push/v1/notify`: optional
  Matrix Push Gateway (Sygnal) when Compose profile `push` is enabled

Caddy obtains and renews public certificates automatically. Synapse listens
only on the internal Compose network in production. Federation is exposed
through Caddy on port 443, and `.well-known/matrix/server` delegates to that
port. The client well-known document publishes the MatrixRTC focus.

### Optional OIDC

When `/opt/highlife/.env` sets `OIDC_ISSUER`, `OIDC_CLIENT_ID`, and
`OIDC_CLIENT_SECRET` together, `render-synapse-config.py` writes an
`oidc_providers` block into Synapse's homeserver config. Register the IdP
callback as `https://<domain>/_synapse/client/oidc/callback`. See
`docs/SECRETS.md`.

### Optional push gateway (Sygnal)

Matrix `m.pusher` HTTP requires a Matrix Push Gateway (Sygnal), **not** raw
ntfy. Enable the optional service:

```bash
# DNS: push.testhighlife.strangled.net A -> DEPLOY_PUBLIC_IP
docker compose -f docker-compose.prod.yml --profile push up -d
```

Point the React build at
`VITE_PUSH_GATEWAY_URL=https://push.testhighlife.strangled.net/_matrix/push/v1/notify`
(plus `VITE_VAPID_PUBLIC_KEY` for web push). Fill `apps` in `sygnal.yaml` for
FCM/APNs before expecting real delivery, or use an external Sygnal instead.

The React client embeds Element Call from the trusted `call.` origin. The
primary response delegates camera, microphone, and display capture only to
that origin; Element Call allows framing only by the primary HighLife origin.
Other public endpoints retain deny/same-origin framing policies.

coturn remains useful for classic Matrix VoIP clients and difficult NATs.
MatrixRTC media itself uses LiveKit's TCP `7881` and UDP `50000-50100` paths.
The production HighLife bot enables Matrix E2EE and keeps its encrypted crypto
store in the persistent `bot-data` volume.

## Fresh Conduit cutover

This is intentionally a fresh deployment, not a Conduit migration:

1. The deploy workflow removes the legacy Compose containers, so they cannot
   retain ports or run a duplicate bot.
2. It does **not** remove any Docker volume.
3. Synapse uses new `highlife_postgres-data` and `highlife_synapse-data`
   volumes and never mounts the old Conduit volume.
4. Keep the old volume until the new deployment has been verified and backed
   up. Delete it later only through an explicit operator action.

Do not run destructive volume commands as part of routine deployment.

## Verification

```bash
curl -fsS https://testhighlife.strangled.net/_matrix/client/versions
curl -fsS https://testhighlife.strangled.net/_matrix/federation/v1/version
curl -fsS https://testhighlife.strangled.net/.well-known/matrix/server
curl -fsS https://testhighlife.strangled.net/.well-known/matrix/client
curl -fsS https://testhighlife.strangled.net/
curl -fsS https://testhighlife.strangled.net/flutter/
curl -fsS https://call.testhighlife.strangled.net/
curl -fsS https://rtc.testhighlife.strangled.net/livekit/jwt/healthz
```

Also run the Matrix.org Federation Tester against
`testhighlife.strangled.net`, place a federated room call between two networks,
and confirm UDP media or TCP fallback in browser WebRTC diagnostics.

Static and Compose checks:

```bash
python -m pip install PyYAML==6.0.2
python scripts/validate-infrastructure.py
```
