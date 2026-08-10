# HighLife

Matrix clients and a small self-host stack built around [aiomatrix](https://www.npmjs.com/package/aiomatrix).

React and Flutter apps speak ordinary Matrix (E2EE, Spaces, DMs, Element Call) and also render `dev.aiomatrix.*` room UI: inline keyboards, signed callbacks, host toasts/progress, Mini Apps, and FormSpace. The `bot` package is the FormSpace reference bot. `server/` is Synapse + Caddy + LiveKit + coturn for a deployable homeserver.

Demo: [testhighlife.strangled.net](https://testhighlife.strangled.net) (MiniApp at `/miniapp/`).

[![Web](https://github.com/FakeHoward/highlife/actions/workflows/web.yml/badge.svg)](https://github.com/FakeHoward/highlife/actions/workflows/web.yml)
[![Client](https://github.com/FakeHoward/highlife/actions/workflows/client.yml/badge.svg)](https://github.com/FakeHoward/highlife/actions/workflows/client.yml)
[![Bot](https://github.com/FakeHoward/highlife/actions/workflows/bot.yml/badge.svg)](https://github.com/FakeHoward/highlife/actions/workflows/bot.yml)
[![Infrastructure](https://github.com/FakeHoward/highlife/actions/workflows/infrastructure.yml/badge.svg)](https://github.com/FakeHoward/highlife/actions/workflows/infrastructure.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

## Layout

| Path | Role |
|---|---|
| `apps/web` | React client |
| `apps/client` | Flutter client (Android, desktop, Flutter web) |
| `apps/miniapp` | FormSpace MiniApp |
| `bot` | FormSpace / aiomatrix bot |
| `contracts` | JSON Schema fixtures for `dev.aiomatrix.*` |
| `packages/ui-contracts` | Shared timeline / UI types |
| `server` | Production Compose stack |
| `docs/` | Deploy secrets, FormSpace notes, finish gate |

Aiomatrix surfaces and FormSpace flows: [`docs/FORMSPACE.md`](./docs/FORMSPACE.md), [`bot/README.md`](./bot/README.md).

## Accounts and federation

HighLife is a normal Matrix client: sign in to **any** homeserver URL.

Some rooms ban whole servers via Matrix `m.room.server_acl` (spam control by room mods). A `403 Server is banned from room` is that ACL, not a client bug. Your account on `testhighlife.strangled.net` cannot join a room that lists that server as banned; use an account on an allowed server (for example matrix.org). Enabling signup on your Synapse does not change another room’s ACL.

The demo homeserver runs **Matrix Authentication Service** for Element X and
other OIDC-native clients (`auth.testhighlife.strangled.net`). Public password
registration is controlled by `SYNAPSE_ENABLE_REGISTRATION` (see
[`server/README.md`](./server/README.md)). HighLife still speaks ordinary Matrix
password login via the MAS compatibility layer; servers that need captcha or
external SSO need that configured on their own auth stack.

## Develop

### Web

```bash
npm ci
npm test --workspace @highlife/web
npm run typecheck --workspace @highlife/web
npm run dev --workspace @highlife/web
```

### Flutter

```bash
cd apps/client
flutter pub get
flutter test
flutter run
```

### Bot

```bash
cd bot
cp .env.example .env
npm ci
npm test
npm start
```

### Homeserver (local)

```bash
cd server
docker compose up -d
```

Production deploy uses the manual `Deploy HighLife` workflow. Secrets: [`docs/SECRETS.md`](docs/SECRETS.md). Operator notes: [`server/README.md`](./server/README.md). Checklist: [`docs/FINISH_GATE.md`](./docs/FINISH_GATE.md).

## CI

| Workflow | What |
|---|---|
| `Web` | Vitest, typecheck, Vite build |
| `Client` | Flutter test / analyze / multi-platform builds |
| `Bot` | typecheck, tests, GHCR image |
| `Infrastructure` | Compose / Caddy validation |
| `Deploy HighLife` | manual production roll (`environment: main`) |

## License

[MIT](./LICENSE)
