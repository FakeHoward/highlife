# FormSpace

Privacy-native replacement for Google Forms / Typeform inside Matrix rooms, built on aiomatrix.

## Scenarios

- **Survey** — multi-step fields (text / choice / scale / …)
- **RSVP** — Going / Maybe / No + live counters
- **Join request** — questionnaire before invite; Approve / Deny / Ask more
- **Onboarding** — wizard after join (rules, role, interests)

## Paths

- Bot: `bot/src/formspace/`
- MiniApp: `apps/miniapp/` → `https://<homeserver>/miniapp/`
- MiniApp API: `https://<homeserver>/miniapp-api/` (auth, bridge.js, form JSON)

## Privacy

Policies: `public` summary, `private` answers to creator DM, `moderators` for power ≥ 50. Optional anonymous mode. Pitch: data stays on your homeserver — not Google/Telegram cloud.

## Ops notes

- Bot needs **power level ≥ 50** in the room to advertise `/commands` state (`dev.aiomatrix.commands`). Below that, `/start` still works and tips the operator.
- Stack: `aiomatrix@^0.8.0`, Node **≥ 24**, optional `REDIS_URL` for multi-instance signed callback/query stores (`aiomatrix/redis`).
- Prefer signed keyboard `token`s (default). Unsigned `content.data` callbacks are rejected unless the library opt-in is enabled.
- Persist `MATRIX_CRYPTO_STORE_PASSPHRASE` (or keep `./data/crypto-passphrase.json` across volume wipes with `formspace.json`).
