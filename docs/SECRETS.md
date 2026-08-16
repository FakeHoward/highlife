# HighLife deployment requirements

The `Deploy HighLife` workflow reads Environment secrets from the GitHub
environment named `main`.

## Domain

Deploy renders `server/Caddyfile.template` and
`server/element-call-config.json.template` by replacing `__MATRIX_DOMAIN__`
with `MATRIX_DOMAIN` or `DOMAIN` (default `testhighlife.strangled.net`). The
committed `server/Caddyfile` and `server/element-call-config.json` match that
default for local use.

Optional GitHub Environment secrets (either works; `MATRIX_DOMAIN` wins when both
are set):

- `DOMAIN` — public base domain
- `MATRIX_DOMAIN` — public hostname for Caddy, well-known, Vite, Flutter
  dart-defines, Synapse `server_name`, LiveKit, coturn realm, bot MXID, and
  smoke URLs. Compose interpolates `${MATRIX_DOMAIN:-testhighlife.strangled.net}`.

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
- `SYNAPSE_REGISTRATION_SECRET`: retained Synapse shared-secret field (legacy
  helper; account creation is owned by MAS after cutover).
- `MAS_POSTGRES_PASSWORD`: password for the dedicated PostgreSQL role/database
  `mas` used by Matrix Authentication Service.
- `MAS_MATRIX_SECRET`: high-entropy shared secret between Synapse and MAS
  (`matrix.secret` / `matrix_authentication_service.secret`). Generate with
  `openssl rand -hex 64`. Do not rotate without planning a MAS/Synapse re-pair.
- `BOT_MATRIX_PASSWORD`: password for
  `@highlifebot:<MATRIX_DOMAIN>` (demo: `testhighlife.strangled.net`).
- `BOT_CRYPTO_STORE_PASSPHRASE`: stable random passphrase encrypting the bot's
  persistent Matrix crypto store. Back it up with the `bot-data` volume.
- `DEMO_MATRIX_PASSWORD`: password for
  `@demo:<MATRIX_DOMAIN>` (demo: `testhighlife.strangled.net`).
- `LIVEKIT_KEY`: LiveKit API key; use a simple URL-safe identifier.
- `LIVEKIT_SECRET`: matching LiveKit API secret.
- `TURN_SHARED_SECRET`: shared by Synapse and coturn for expiring TURN
  credentials.

Required set: host, user, public IP, the stack secrets above (including
`MAS_POSTGRES_PASSWORD` and `MAS_MATRIX_SECRET`), plus **either**
`DEPLOY_PASSWORD` or `DEPLOY_SSH_KEY` (or both). Password SSH for humans on
the VPS is never disabled by these workflows. `GITHUB_TOKEN` is supplied by
Actions and is not a manually configured secret.

## Optional secrets / env

- `REDIS_PASSWORD` (optional GitHub Environment secret): Redis `requirepass`.
  When unset, deploy generates one on the host and persists it in
  `/opt/highlife/redis.pass` so it survives later deploys.
- `MATRIX_MINIAPP_SECRET` (optional GitHub Environment secret): stable signing
  secret for FormSpace / MiniApp tokens. When unset, deploy generates one on
  the host (`/opt/highlife/miniapp.secret`) so signing survives volume rebuilds.
- `FORMSPACE_ANONYMITY_SALT` (optional): stable salt for anonymous FormSpace
  respondent hashes. When unset, the bot persists a generated salt under
  `bot-data` (`anonymity-salt`).
- `MATRIX_MINIAPP_CORS_ORIGIN` (optional; default
  `https://<MATRIX_DOMAIN>`): comma-separated allowlist for FormSpace
  HTTP `Access-Control-Allow-Origin`. Request `Origin` is reflected only when it
  matches this list.
- `SYNAPSE_ENABLE_REGISTRATION` (optional; default `false`):
  toggles MAS password self-registration (no email required on this demo). Set
  `true` only for a public demo.
- **Upstream SSO** belongs in Matrix Authentication Service, not Synapse
  `oidc_providers`. Edit the generated MAS config / add an `upstream_oauth2`
  overlay if you need an external IdP; register the IdP redirect against
  `https://auth.<MATRIX_DOMAIN>/...` per MAS docs.
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
openssl rand -hex 64   # MAS_MATRIX_SECRET
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
`DEPLOY_PUBLIC_IP` (the environment secret, not a value in git):

- `<MATRIX_DOMAIN>` — present
- `auth.<MATRIX_DOMAIN>` — **required** for Matrix Authentication
  Service / Element X
- `call.<MATRIX_DOMAIN>` — Element Call
- `rtc.<MATRIX_DOMAIN>` — LiveKit JWT / SFU
- `push.<MATRIX_DOMAIN>` — **optional** (only when enabling Compose
  profile `push` for on-host Sygnal)

`auth` / `call` / `rtc` DNS must resolve before deploy so Caddy can finish
ACME. Re-run `Deploy HighLife` after stack changes; then smoke Element X
login/signup, two-client MatrixRTC, and the federation tester.

Only publish `AAAA` records if the VPS, Docker port publishing, firewall, and
LiveKit media paths are all working over that IPv6 address. Remove stale
records. Wait for public resolution before deploy so Caddy can complete
ACME validation and obtain certificates.

Before the first HighLife deploy, let the `Bot` workflow finish successfully
so GHCR contains `highlife-formspace-bot:<last-bot-source-commit>`. Deploy pins
that content tag rather than using `latest`. The image owner is
`${GITHUB_REPOSITORY_OWNER}` (required in compose; no hardcoded namespace).

## Firewall actions

Allow inbound traffic to the VPS:

- TCP `22` from trusted administration/Actions source ranges as practical.
- TCP `80`, `443` for ACME, HTTPS, Matrix client API, and federation.
- UDP `443` for HTTP/3 (optional but configured by Caddy).
- TCP and UDP `3478` for coturn.
- TCP `7881` for LiveKit ICE-over-TCP fallback.
- UDP `50000-50100` for LiveKit media.
- UDP `49160-49200` for coturn relayed media.

coturn listens on `3478` with `--no-tls --no-dtls`. Public HTTPS/443 is Caddy;
do not enable coturn TLS on 443. `turns:` is a residual demo limit unless you
add a dedicated TURN certificate and `ENABLE_TURN_TLS` later.

Do not expose PostgreSQL `5432`, Redis `6379`, Synapse `8008`, MAS `8080`,
LiveKit signalling `7880`, JWT service `8080`, or Sygnal `5000`; those stay
on the Compose network (public MAS traffic terminates on Caddy `:443`).
Allow normal outbound DNS, HTTPS/federation TCP `443`, STUN/UDP, and NTP.

## Post-deploy checks

1. Confirm all services are running with
   `docker compose -f /opt/highlife/docker-compose.prod.yml ps`.
2. Confirm valid certificates for `auth.` / `call.` / `rtc.` (plus `push.` if
   enabled).
3. Fetch Matrix client versions and federation version endpoints.
4. Verify both well-known documents, `org.matrix.msc4143.rtc_foci`, and
   `org.matrix.msc2965.authentication` pointing at
   `https://auth.testhighlife.strangled.net/`.
5. Confirm `https://auth…/.well-known/openid-configuration` and homeserver
   `auth_metadata` advertise that issuer.
6. Load the React client at `/` and Flutter at `/flutter/`; confirm React can
   embed `https://call.testhighlife.strangled.net`.
7. Confirm the primary response sends a real CSP (`default-src 'self'`, etc.)
   and delegates camera/microphone only to the trusted call origin; the call
   response has matching `frame-ancestors` and no `X-Frame-Options`. Deploy
   smoke asserts primary CSP contains `default-src`.
8. Confirm MAS registration/login (Element X or compat `/register` → `200` /
   UIA `401` when open; `403` when `SYNAPSE_ENABLE_REGISTRATION=false`).
   Confirm `highlifebot` / `demo` can log in through the public HS URL.
9. Run the Matrix.org Federation Tester for
   `testhighlife.strangled.net`.
10. Make an Element Call between separate networks and verify UDP media,
   then test a restricted network for TCP/TURN fallback.
11. Back up PostgreSQL, Synapse media, MAS, and bot volumes with
   `scripts/backup-highlife.sh` (cron on the VPS). Retain the old Conduit
   volume during the acceptance period; it is not migrated or deleted by the
   workflow.
12. Verify the HighLife bot joins and decrypts an encrypted room after a
   **routine redeploy** (crypto store preserved) and after a deliberate
   `Recover bot` wipe when needed.
