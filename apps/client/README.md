# HighLife Flutter client

Cross-platform Matrix client (`highlife_client`) with Aiomatrix keyboards,
callbacks, Mini Apps (manual open), MSC3381 polls, Markdown message bodies,
aware-host handshake (`dev.aiomatrix.host`), first-party Matrix 1:1 voice,
first-party MatrixRTC/LiveKit group calls, Element Call as last-resort
fallback, and E2EE (native / WASM on web).

## Local

Platform trees `android/`, `web/`, `windows/`, `linux/` and `pubspec.lock` are
**vendored in git** (iOS remains out of scope / gitignored). CI still runs a
safe `flutter create` refresh before builds.

```bash
flutter pub get
flutter test
flutter run
```

Homeserver field defaults to empty; override the prefill with `--dart-define=HIGHLIFE_DEFAULT_HOMESERVER=https://…`.
Group calls use LiveKit/MatrixRTC first (`--dart-define=HIGHLIFE_LIVEKIT_JWT_URL=https://rtc…/livekit/jwt`).
Element Call is last-resort fallback when that path fails:
`https://call.testhighlife.strangled.net` (override with
`--dart-define=HIGHLIFE_ELEMENT_CALL_URL=...`).
Push gateway (optional): `--dart-define=HIGHLIFE_PUSH_GATEWAY_URL=https://push…/_matrix/push/v1/notify`.

CI builds: `.github/workflows/client.yml`.
