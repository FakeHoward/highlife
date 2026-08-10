# HighLife Matrix infrastructure

The production stack is a federated Synapse deployment for
`testhighlife.strangled.net` with **Matrix Authentication Service (MAS)** for
OIDC-native clients (Element X and others). It also includes PostgreSQL, Caddy
TLS, Redis, LiveKit, the MatrixRTC JWT service, Element Call, coturn, and the
HighLife bot.

Public registration is controlled by `SYNAPSE_ENABLE_REGISTRATION` (default
**true** after the MAS cutover). It toggles MAS
`account.password_registration_enabled` (no email required on this demo host).
Bot/demo accounts are created with `mas-cli manage register-user`.

Caddy hostnames come from `Caddyfile.template` (`__MATRIX_DOMAIN__`). Deploy
renders them from the `MATRIX_DOMAIN` / `DOMAIN` secret (default
`testhighlife.strangled.net`). The committed `Caddyfile` matches that default.

## Local development

Docker Desktop is required. The helper generates random secrets in the
gitignored `server/.env`, starts Synapse, MAS, and MatrixRTC, waits for health,
and creates `alice`, `bob`, and `bot`:

```powershell
.\scripts\stack.ps1
```

Local endpoints:

- Synapse: `http://localhost:8008`
- MAS (OIDC + login/register compat): `http://localhost:8083`
- Element Call: `http://localhost:8081`
- LiveKit JWT service: `http://localhost:8082`
- LiveKit signalling: `ws://localhost:7880`
- LiveKit media: TCP `7881`, UDP `50000-50100`
- coturn: TCP/UDP `3478`, relay TCP/UDP `49160-49200`

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
- `https://auth.testhighlife.strangled.net`: Matrix Authentication Service
  (OIDC issuer + account UI)
- `https://call.testhighlife.strangled.net`: Element Call
- `https://rtc.testhighlife.strangled.net/livekit/jwt`: MatrixRTC
  authorization
- `wss://rtc.testhighlife.strangled.net/livekit/sfu`: LiveKit signalling
- `rtc.testhighlife.strangled.net:3478`: coturn (UDP/TCP)
- `https://push.testhighlife.strangled.net/_matrix/push/v1/notify`: optional
  Matrix Push Gateway (Sygnal) when Compose profile `push` is enabled

Caddy obtains and renews public certificates automatically. Synapse and MAS
listen only on the internal Compose network in production. Federation is
exposed through Caddy on port 443, and `.well-known/matrix/server` delegates to
that port. The client well-known document publishes the MatrixRTC focus and
`org.matrix.msc2965.authentication` (MAS issuer).

Legacy password login/register for older clients is proxied from the homeserver
host (`/_matrix/client/*/login|logout|refresh`) to MAS. OIDC-native clients
discover MAS via well-known / `auth_metadata` and use `auth.` directly.

### Matrix Authentication Service

First deploy runs `migrate-syn2mas.sh` once (marker in the `mas-data` volume) to
import existing Synapse users/sessions into MAS. Later deploys skip migration.

Register a user on the host:

```bash
docker compose -f docker-compose.prod.yml exec -T mas \
  /usr/local/bin/mas-cli --config /data/config.yaml manage register-user \
  --yes --password '...' --no-admin \
  --ignore-password-complexity alice
```

Or use the GitHub Actions workflow **Provision account**.

Upstream SSO IdPs belong in MAS (`upstream_oauth2`), not in Synapse
`oidc_providers`. Synapse-native OIDC is disabled when MAS is enabled.

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

The first-party React origin is permitted to use its own camera and microphone.
It may also delegate camera, microphone, and display capture to the trusted
`call.` origin for foreign/Element clients. Element Call allows framing only by
the primary HighLife origin. Other public endpoints retain deny/same-origin
framing policies. The primary CSP serves fonts locally and has no Google Fonts
allowlist.

HighLife has first-party classic Matrix 1:1 voice (`matrix-js-sdk` /
`matrix` VoIP + `flutter_webrtc`) and first-party MatrixRTC/LiveKit group
calls. Element Call remains a last-resort fallback when the LiveKit JWT/SFU
path fails, and for foreign clients that still embed it. MSC3401 membership
stays compatible with Element.

coturn serves classic Matrix VoIP clients and difficult NATs on UDP/TCP `3478`
with relay ports `49160-49200` on both transports. Authentication nonces expire
after 600 seconds. TURN/TLS is not advertised on `443`: that address belongs to
Caddy on the same host. A future `turns:` listener should use a separately
provisioned certificate and port such as `5349`.
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
curl -fsS https://auth.testhighlife.strangled.net/.well-known/openid-configuration
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
