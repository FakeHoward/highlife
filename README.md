# HighLife

**[Aiomatrix](https://www.npmjs.com/package/aiomatrix)-native Matrix clients** — not a generic chat shell with a bot bolted on.

Inline keyboards, signed callbacks, host toasts, Mini Apps, and FormSpace in ordinary encrypted rooms. React + Flutter hosts, reference bot, Synapse deploy.

[![CI — Web](https://github.com/FakeHoward/highlife/actions/workflows/web.yml/badge.svg)](https://github.com/FakeHoward/highlife/actions/workflows/web.yml)
[![CI — Client](https://github.com/FakeHoward/highlife/actions/workflows/client.yml/badge.svg)](https://github.com/FakeHoward/highlife/actions/workflows/client.yml)
[![CI — Bot](https://github.com/FakeHoward/highlife/actions/workflows/bot.yml/badge.svg)](https://github.com/FakeHoward/highlife/actions/workflows/bot.yml)
[![CI — Infrastructure](https://github.com/FakeHoward/highlife/actions/workflows/infrastructure.yml/badge.svg)](https://github.com/FakeHoward/highlife/actions/workflows/infrastructure.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0B6E4F.svg)](./LICENSE)
[![aiomatrix](https://img.shields.io/badge/aiomatrix-0.8-222222)](https://www.npmjs.com/package/aiomatrix)
[![Matrix](https://img.shields.io/badge/transport-Matrix-000000?logo=matrix&logoColor=white)](https://matrix.org)
[![Flutter](https://img.shields.io/badge/Flutter-host-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![React](https://img.shields.io/badge/React-host-61DAFB?logo=react&logoColor=black)](https://react.dev)

Live: [`testhighlife.strangled.net`](https://testhighlife.strangled.net) · FormSpace MiniApp at `/miniapp/`

---

## What Aiomatrix support looks like here

Most Matrix clients stop at text, media, and calls. HighLife treats `dev.aiomatrix.*` as first-class room UI:

| Surface | In HighLife |
|---|---|
| Inline keyboards | Rendered in the timeline (web + Flutter) |
| `dev.aiomatrix.callback` | Signed tokens preferred; unsigned forgeable payloads rejected by default |
| Aware host | `dev.aiomatrix.host` + ephemeral `callback_answer` / toast / progress |
| Mini Apps | Cards open FormSpace builder / filler / results (`apps/miniapp`) |
| Commands state | `/commands` via `dev.aiomatrix.commands` when the bot has PL ≥ 50 |
| Contracts | JSON Schema fixtures under `contracts/` aligned with aiomatrix 0.7 |

FormSpace (survey / RSVP / join / onboarding) is the reference bot on top of the same protocol — see [`docs/FORMSPACE.md`](./docs/FORMSPACE.md) and [`bot/README.md`](./bot/README.md).

Matrix underneath stays ordinary: E2EE, Spaces, DMs, Element Call (MatrixRTC), optional Sygnal push. The point of this repo is the **Aiomatrix-aware host**, not another generic chat shell.

---

## Repo map

| Path | Role |
|---|---|
| `apps/web` | React host — Aiomatrix keyboards, MiniApp surface, MatrixRTC |
| `apps/client` | Flutter host — same protocol on Android / desktop / Flutter web |
| `apps/miniapp` | FormSpace MiniApp (builder, filler, results) |
| `bot` | FormSpace + showcase bot (`aiomatrix@^0.7`) |
| `contracts` | Interop schemas / fixtures for `dev.aiomatrix.*` |
| `packages/ui-contracts` | Shared timeline / UI types |
| `server` | Synapse + Caddy + LiveKit + coturn Compose stack |
| `docs/` | Secrets, finish gate, FormSpace notes |

---

## Quick start

### Web host

```bash
npm ci
npm test --workspace @highlife/web
npm run typecheck --workspace @highlife/web
npm run dev --workspace @highlife/web
```

### Flutter host

```bash
cd apps/client
flutter pub get
flutter test
flutter run
```

### FormSpace bot

```bash
cd bot
cp .env.example .env
npm ci
npm test
npm run typecheck
```

Homeserver / Deploy: [`server/README.md`](./server/README.md), [`docs/SECRETS.md`](./docs/SECRETS.md). Checklist: [`docs/FINISH_GATE.md`](./docs/FINISH_GATE.md).

---

## CI / Actions

| Workflow | When | What |
|---|---|---|
| `Web` | PR / path push | test, typecheck, build |
| `Client` | PR / path push | Flutter matrix (android, web, linux, windows) |
| `Bot` | PR / path push; image on `main` or `workflow_dispatch` | `ghcr.io/<owner>/highlife-formspace-bot` |
| `Infrastructure` | PR / path push | Compose / Caddy / deploy script checks |
| `Deploy HighLife` | manual (`workflow_dispatch`) | production roll — needs Environment `main` secrets |

Enable Actions after clone. Public repo runs on GitHub’s public minutes. Do not commit `.env` or VAPID PEMs.

---

## Protocol notes

- Fixtures in `contracts/` track aiomatrix 0.7 builders in `bot/src/showcase.ts`
- Aware hosts should publish capabilities and handle ephemeral answers (not only static keyboards)
- MiniApp cards stay normal `m.room.message` with plaintext/HTML fallback for dumb clients

---

## License

[MIT](./LICENSE)

<p align="center">
  <b>Aiomatrix in the room. Matrix on the wire.</b><br/>
  <a href="./contracts">contracts</a> ·
  <a href="./docs/FORMSPACE.md">FormSpace</a> ·
  <a href="https://testhighlife.strangled.net">demo</a>
</p>
