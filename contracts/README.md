# HighLife protocol contracts

These JSON Schemas describe the interoperable payloads emitted and consumed by `aiomatrix@0.8.0`. They are language-neutral Draft 7 schemas; filenames match the Matrix event type or content key.

Note: as of 0.6.0 unsigned `dev.aiomatrix.callback` payloads (forgeable `data` without a valid HMAC `token`) are rejected by the bot unless `allowUnsignedCallbacks` is explicitly enabled. Clients should prefer `token` + `message_id`.

Aware hosts (0.6.2+) should also handle ephemeral `dev.aiomatrix.callback_answer` / `toast` / `progress` and may publish `dev.aiomatrix.host` capabilities.

- `schemas/` contains schemas for keyboard blocks, callback event content, advertised command state, MiniApp cards, MiniApp data, host toasts/progress/callback answers, and `dev.aiomatrix.host` capabilities.
- `fixtures/` contains valid examples generated from the bot's showcase builders.
- `bot/tests/showcase.test.ts` validates every fixture and compares builder-backed fixtures with actual library output.

Compatibility rules:

1. Event type names and existing fields are additive contracts; consumers must tolerate unknown fields.
2. `dev.aiomatrix.callback` requires a signed/opaque `token`. Unsigned `data`-only payloads are rejected unless `allowUnsignedCallbacks` is explicitly enabled.
3. Callback keyboard buttons may contain both raw `data` and a generated `token`; fallback clients send `!cb <token>`.
4. MiniApp cards remain ordinary `m.room.message` events with plaintext and HTML fallback.
