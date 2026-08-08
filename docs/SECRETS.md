# HighLife deployment requirements

The `Deploy HighLife` workflow reads Environment secrets from the GitHub
environment named `main`.

## Domain

Deploy renders `server/Caddyfile.template` → `Caddyfile` by replacing
`__MATRIX_DOMAIN__` with `MATRIX_DOMAIN` or `DOMAIN` (default
`testhighlife.strangled.net`). The committed `server/Caddyfile` matches the
default domain for local use.

Optional GitHub Environment secrets (either works; `MATRIX_DOMAIN` wins when both
are set):

- `DOMAIN` — public base domain
- `MATRIX_DOMAIN` — same value written into Caddy / well-known / smoke URLs

Compose still pins Synapse `SYNAPSE_SERVER_NAME`, LiveKit JWT homeserver, coturn
realm, and bot MXID to `testhighlife.strangled.net`. Retarget those strings in
`server/docker-compose.prod.yml` (and Element Call config) together when moving
off the test domain.

## Required GitHub Environment secrets

- `DEPLOY_HOST`: SSH hostname or IP of the VPS.
- `DEPLOY_USER`: SSH user with Docker access and permission to manage
  `/opt/highlife`.
- **Deploy auth (one of, for GitHub Actions only):**
  - `DEPLOY_PASSWORD`: SSH password for `DEPLOY_USER`. **Keep this** if you
    log into the VPS yourself with password — deploy never changes `sshd` or
    disables password authentication on the machine.
  - `DEPLOY_SSH_KEY` (optional): private key PEM used **only by Actions**
    (`appleboy` scp/ssh). When both are set, Actions prefers the key; your
    interactive password login is unchanged. Adding a key does **not** lock
    you out of password SSH.
- `DEPLOY_PUBLIC_IP`: public IPv4 address advertised by coturn.
- `POSTGRES_PASSWORD`: password for the `synapse` PostgreSQL role.
- `SYNAPSE_REGISTRATION_SECRET`: Synapse shared registration secret used only
  by the private account bootstrap helper (bot/demo). Public signup is **off**
  by default (`SYNAPSE_ENABLE_REGISTRATION=false`).
- `BOT_MATRIX_PASSWORD`: password for
  `@highlifebot:testhighlife.strangled.net`.
- `BOT_CRYPTO_STORE_PASSPHRASE`: stable random passphrase encrypting the bot's
  persistent Matrix crypto store. Back it up with the `bot-data` volume.
- `DEMO_MATRIX_PASSWORD`: password for
  `@demo:testhighlife.strangled.net`.
- `LIVEKIT_KEY`: LiveKit API key; use a simple URL-safe identifier.
- `LIVEKIT_SECRET`: matching LiveKit API secret.
- `TURN_SHARED_SECRET`: shared by Synapse and coturn for expiring TURN
  credentials.

Required set: host, user, public IP, the eleven stack secrets above, plus
**either** `DEPLOY_PASSWORD` or `DEPLOY_SSH_KEY` (or both). Password SSH for
humans on the VPS is never disabled by these workflows.
`GITHUB_TOKEN` is supplied by Actions and is not a manually configured secret.

## Optional secrets / env

- `MATRIX_MINIAPP_SECRET` (optional GitHub Environment secret): stable signing
  secret for FormSpace / MiniApp tokens. When unset, aiomatrix may persist a
  generated secret under `bot-data`. Prefer setting this so token signing
  survives volume rebuilds and stays operator-controlled. Deploy copies it into
  `.env` only when the secret is present.
- `MATRIX_MINIAPP_CORS_ORIGIN` (optional; default
  `https://testhighlife.strangled.net`): comma-separated allowlist for FormSpace
  HTTP `Access-Control-Allow-Origin`. Request `Origin` is reflected only when it
  matches this list.
- `SYNAPSE_ENABLE_REGISTRATION` (optional; default `false` in production): set
  to `true` only when intentionally opening public signup on the HS.
- **Synapse OIDC** (optional; all three required together). Deploy writes them
  into `/opt/highlife/.env`; `render-synapse-config.py` emits `oidc_providers`
  when present:
  - `OIDC_ISSUER` — IdP issuer URL (may end with `/`)
  - `OIDC_CLIENT_ID`
  - `OIDC_CLIENT_SECRET`
  - Optional: `OIDC_IDP_ID` (default `oidc`), `OIDC_IDP_NAME` (default `OIDC`),
    `OIDC_SCOPES` (space-separated; default `openid profile email`),
    `OIDC_LOCALPART_TEMPLATE`, `OIDC_DISPLAY_NAME_TEMPLATE`
  Register the IdP redirect URI as
  `https://<MATRIX_DOMAIN>/_synapse/client/oidc/callback`.
  - `ENABLE_PUSH` (optional; `true`/`1`): start Compose profile `push` (Sygnal)
    on deploy and expect DNS `push.<MATRIX_DOMAIN>`. Deploy auto-sets
    `VITE_PUSH_GATEWAY_URL=https://push.<domain>/_matrix/push/v1/notify` when
    this is true (unless you override the secret).
  - **Web Push / Matrix push gateway** (pair with `ENABLE_PUSH`):
  - `SYGNAL_VAPID_PRIVATE_KEY` — PKCS#8 PEM private key for Sygnal webpush
    (`server/sygnal-vapid.pem` on the host). Required when `ENABLE_PUSH=true`.
  - `VITE_VAPID_PUBLIC_KEY` — matching uncompressed P-256 public key, base64url
    (no padding). Required for the React web client to subscribe.
  - `VITE_PUSH_GATEWAY_URL` — optional override; must be a **Matrix Push Gateway**
    (Sygnal) implementing `/_matrix/push/v1/notify`, e.g.
    `https://push.testhighlife.strangled.net/_matrix/push/v1/notify`
  - **Not ntfy:** raw ntfy does not speak the Matrix `m.pusher` HTTP API.
    Do not point `VITE_PUSH_GATEWAY_URL` at an ntfy URL.
  - On-host Sygnal (Compose profile `push`):

    ```bash
    # DNS first: push.<MATRIX_DOMAIN> A -> DEPLOY_PUBLIC_IP
    # Secrets: ENABLE_PUSH=true + SYGNAL_VAPID_PRIVATE_KEY + VITE_VAPID_PUBLIC_KEY
    cd /opt/highlife
    docker compose -f docker-compose.prod.yml --profile push up -d
    ```

    Config is `server/sygnal.yaml` (apps `im.highlife.web` + `app.highlife.android`).
    Operators may instead use an external Sygnal and set `VITE_PUSH_GATEWAY_URL`
    to that gateway's notify URL at client build time.
- Flutter push compile-time: `--dart-define=HIGHLIFE_PUSH_GATEWAY_URL=...`
  (same Matrix push gateway URL shape as above).
- Android Play signing (Client workflow secrets, optional until store ship):
  - `ANDROID_KEYSTORE_BASE64` (base64 of upload keystore `.jks`/`.keystore`)
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`

Generate independent values locally; never paste the examples into GitHub:

```bash
openssl rand -base64 36 | tr -d '\n'
openssl rand -hex 32
# VAPID for Sygnal + web push (Node):
node -e "const c=require('crypto'),fs=require('fs');const {privateKey,publicKey}=c.generateKeyPairSync('ec',{namedCurve:'prime256v1'});const pem=privateKey.export({type:'pkcs8',format:'pem'});const u=publicKey.export({type:'spki',format:'der'}).subarray(-65);fs.writeFileSync('sygnal-vapid.pem',pem);console.log(u.toString('base64url'));"
# Put PEM into SYGNAL_VAPID_PRIVATE_KEY; printed line into VITE_VAPID_PUBLIC_KEY.
# SSH deploy key (optional for Actions; does not disable password login):
ssh-keygen -t ed25519 -f highlife-deploy -N "" -C "highlife-deploy"
# Install highlife-deploy.pub on the VPS (authorized_keys). Keep password
# login enabled in sshd if you still want interactive password access.
# Put highlife-deploy private key PEM into GitHub secret DEPLOY_SSH_KEY.
```

Use single-line values without spaces, quotes, `$`, or line breaks because the
workflow writes a shell-compatible `/opt/highlife/.env` (SSH keys are multi-line
and used only by the Actions SSH client, not written into `.env`). Use a distinct
random value for every password/secret. A suitable `LIVEKIT_KEY` is 16-32
alphanumeric characters; its secret should have at least 32 random bytes.

Do not rotate `POSTGRES_PASSWORD` by changing only GitHub: PostgreSQL does not
change an existing role password when its container restarts. Update the
database role and deployment secret together. Likewise, rotate LiveKit and
TURN key pairs atomically. Do not rotate `BOT_CRYPTO_STORE_PASSPHRASE`
without resetting or re-encrypting the bot crypto store; otherwise the bot
cannot decrypt its persisted device keys.

## Bot crypto across deploys

Routine `Deploy HighLife` **preserves** the `bot-data` crypto/session store
(only `mkdir` + `chown`). It does **not** wipe Olm/session files on every
deploy. If the bot fails after a device/session mismatch, run the
`Recover bot` workflow (`.github/workflows/recover-bot.yml`), which clears
crypto state while keeping `formspace.json` / `crypto-passphrase.json`.

## DNS actions

Before the first deploy, create DNS `A` records pointing to
`DEPLOY_PUBLIC_IP` (currently `178.215.236.95`):

- `testhighlife.strangled.net` — present
- `call.testhighlife.strangled.net` — **live** (`A` → `178.215.236.95`)
- `rtc.testhighlife.strangled.net` — **live** (`A` → `178.215.236.95`)
- `push.testhighlife.strangled.net` — **optional** (only when enabling Compose
  profile `push` for on-host Sygnal)

`call` / `rtc` DNS is live. Re-run `Deploy HighLife` after stack changes so
Caddy refreshes certs; then smoke two-client MatrixRTC and federation tester.

Only publish `AAAA` records if the VPS, Docker port publishing, firewall, and
LiveKit media paths are all working over that IPv6 address. Remove stale
records. Wait for public resolution before deploy so Caddy can complete
ACME validation and obtain certificates.

Before the first HighLife deploy, let the `Bot` workflow finish successfully
so GHCR contains `highlife-bot:<last-bot-source-commit>`. Deploy pins that
content tag rather than using `latest`.

## Firewall actions

Allow inbound traffic to the VPS:

- TCP `22` from trusted administration/Actions source ranges as practical.
- TCP `80`, `443` for ACME, HTTPS, Matrix client API, and federation.
- UDP `443` for HTTP/3 (optional but configured by Caddy).
- TCP and UDP `3478` for coturn.
- TCP `7881` for LiveKit ICE-over-TCP fallback.
- UDP `50000-50100` for LiveKit media.
- UDP `49160-49200` for coturn relayed media.

Do not expose PostgreSQL `5432`, Redis `6379`, Synapse `8008`, LiveKit
signalling `7880`, JWT service `8080`, or Sygnal `5000`; those stay on the
Compose network. Allow normal outbound DNS, HTTPS/federation TCP `443`,
STUN/UDP, and NTP.

## Post-deploy checks

1. Confirm all services are running with
   `docker compose -f /opt/highlife/docker-compose.prod.yml ps`.
2. Confirm valid certificates for all three hostnames (plus `push.` if enabled).
3. Fetch Matrix client versions and federation version endpoints.
4. Verify both well-known documents and the
   `org.matrix.msc4143.rtc_foci` entry.
5. Load the React client at `/` and Flutter at `/flutter/`; confirm React can
   embed `https://call.testhighlife.strangled.net`.
6. Confirm the primary response sends a real CSP (`default-src 'self'`, etc.)
   and delegates camera/microphone only to the trusted call origin; the call
   response has matching `frame-ancestors` and no `X-Frame-Options`. Deploy
   smoke asserts primary CSP contains `default-src`.
7. Confirm public registration is closed by default (`/register` → `403`),
   unless you intentionally set `SYNAPSE_ENABLE_REGISTRATION=true` (then
   expect `200` or UIA `401`). Confirm `highlifebot` / `demo` can log in.
8. Run the Matrix.org Federation Tester for
   `testhighlife.strangled.net`.
9. Make an Element Call between separate networks and verify UDP media,
   then test a restricted network for TCP/TURN fallback.
10. Back up PostgreSQL, Synapse media, and bot volumes with
   `scripts/backup-highlife.sh` (cron on the VPS). Retain the old Conduit
   volume during the acceptance period; it is not migrated or deleted by the
   workflow.
11. Verify the HighLife bot joins and decrypts an encrypted room after a
   **routine redeploy** (crypto store preserved) and after a deliberate
   `Recover bot` wipe when needed.
