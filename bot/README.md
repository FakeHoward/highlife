# FormSpace bot

Privacy-native forms for Matrix on `aiomatrix@0.8.0`: Survey, RSVP, Join request, Onboarding — with MiniApp builder/filler/results, chat FSM fallback, inline keyboards, E2EE, and scheduler deadlines.

Requires **Node.js ≥ 24**.

## Setup

```powershell
cd bot
copy .env.example .env
npm install
npm start
```

Invite the bot; it auto-joins. Production MiniApp is served at `/miniapp/` with API at `/miniapp-api/`.

```powershell
npm test
npm run typecheck
```

## Environment

| Variable | Notes |
|---|---|
| `MATRIX_*` | Homeserver, user, password, crypto passphrase |
| `MATRIX_ROTATE_EVERY_MESSAGE_MAX_PEERS` | Default `32` (aiomatrix large-room peer cap) |
| `REDIS_URL` | When set, uses `createRedisSharedTokenStores` from `aiomatrix/redis` for multi-replica signed callback/query/nonce stores (+ `RedisStorage` for FSM). Prod compose uses `redis://redis:6379`. |
| `MATRIX_HANDLER_TIMEOUT_MS` | Optional dispatcher timeout (`ctx.signal`) |

## Commands

| Command | What it does |
|---|---|
| `/start` | Pitch + scenario menu |
| `/form new [survey\|rsvp\|join\|onboard]` | Open MiniApp builder (or Use template) |
| `/form list` / `close` / `results` / `export` | Manage forms |
| `/form policy` / `anonymous` / `deadline` | Privacy + schedule |
| `/form chat [id]` | Answer via FSM in chat |
| `/form target !room:server` | Join-request destination |
| `/form onboard auto on\|off` | Auto wizard on member join |

Command advertisement needs bot **PL ≥ 50** in the room.

## Protocol contracts

Fixtures in `../contracts` stay aligned with `src/showcase.ts` builders (`dev.aiomatrix.*`).

## Session recovery (aiomatrix 0.8)

Password-login bots enable `autoReloginOnAuthFailure` (mid-run password re-login when refresh fails). Startup runs `migrateStorage("./data")` for the 0.8 layout (callback maps, outbox). Soft auth stays in-process; hard `DeviceMismatchError` (or `diagnoseSession().suggestedAction === "wipe_crypto_and_relogin"`) triggers `relocateSession` using `error.recovery.keepDeviceId` when present. Ops: `npx aiomatrix doctor` / `diagnoseSession("./data")`. Keep `formspace.json` and `crypto-passphrase.json` across wipes.

Aware profile notes: `answerCallback({ text })` emits `dev.aiomatrix.callback_answer` (hosts show ephemeral toasts). Redis helpers live on **`aiomatrix/redis`**. Outbox (`outbox: true`) retries transient send failures. Middleware: `autoMarkRead`, `rateLimitBackoff`, `userFacingErrors`.
