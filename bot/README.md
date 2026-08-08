# FormSpace bot

Privacy-native forms for Matrix on `aiomatrix@0.7.0`: Survey, RSVP, Join request, Onboarding — with MiniApp builder/filler/results, chat FSM fallback, inline keyboards, E2EE, and scheduler deadlines.

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
| `REDIS_URL` | When set, uses `createRedisSharedTokenStores` for multi-replica signed callback/query/nonce stores. Prod compose uses `redis://redis:6379`. |
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

## Session recovery (aiomatrix 0.7)

Password-login bots enable `autoReloginOnAuthFailure` (mid-run password re-login when refresh fails). Outer `relocateSession` is reserved for `DeviceMismatchError` / spoiled crypto store. Ops can inspect `./data` with `diagnoseSession("./data")` or `npx aiomatrix doctor`. Keep `formspace.json` and `crypto-passphrase.json` across wipes.

Aware profile notes: `answerCallback({ text })` emits `dev.aiomatrix.callback_answer` (hosts show ephemeral toasts). Redis helpers ship in the package (`createRedisSharedTokenStores`). Middleware: `autoMarkRead`, `rateLimitBackoff`, `userFacingErrors`.
