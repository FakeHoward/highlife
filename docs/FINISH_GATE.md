# HighLife finish gate

Honest release checklist. iOS is explicitly out of scope. Play Console listing
is an operator step outside the repo.

## Client / product

- [x] RU/EN locale switch (Flutter + React), default English
- [x] Telegram-refined chat surfaces + Aiomatrix in ordinary rooms
- [x] Room basics: invites, search jump-to-event, members, sync banner, settings
- [x] Start DM + create room / space + encryption toggle (web + Flutter)
- [x] Add room to space (web); Flutter room details sheet
- [x] E2EE: devices, SAS (workspace banner on web), cross-signing, recovery UI
- [x] Media E2EE on web; upload progress UI
- [x] Polls (MSC3381) web + Flutter
- [x] Honest delivery marks (EventStatus + read receipts)
- [x] Localized timeline system/decrypt/redact copy
- [x] Session IndexedDB + crypto wipe on logout
- [x] Spaces list / filter / create
- [x] OIDC/OAuth2 + SSO (web); Flutter SSO detect + token paste
- [x] Web Push env wiring (`VITE_*`); Flutter UnifiedPush → HTTP pusher
- [x] Android CI signing secrets + AAB artifact
- [x] Flutter-web crypto hard-failure banner
- [x] Vendored `android/` `web/` `linux/` `windows/` + `pubspec.lock`
- [x] MatrixRTC Element Call + Widget API host (group-call fallback)
- [x] Isolated first-party Matrix 1:1 voice cores (web + Flutter)
- [x] First-party call cores integrated with session/chat lifecycle and localized UI
- [x] Native first-party MatrixRTC/LiveKit group media; Element Call is last-resort fallback
- [x] CI + FormSpace bot
- [ ] Play Console store listing (operator; UnifiedPush/signing ready in repo)
- [ ] iOS — out of scope

## Production ops / hardening

- [x] Federated Synapse + well-known + MatrixRTC
- [x] Caddy CSP + deploy smoke `default-src`
- [x] Registration closed by default
- [x] Bot crypto preserved on routine deploy
- [x] FormSpace CORS allowlist + optional MiniApp secret
- [x] `Caddyfile.template` domain render
- [x] Deploy auth: `DEPLOY_PASSWORD` and/or `DEPLOY_SSH_KEY` for Actions only —
      **never disables password SSH on the VPS**
- [x] Optional Synapse OIDC via env
- [x] Optional Sygnal via `ENABLE_PUSH=true` + `push.` DNS + VAPID secrets
      (`SYGNAL_VAPID_PRIVATE_KEY` / `VITE_VAPID_PUBLIC_KEY`)
- [x] Backup script `scripts/backup-highlife.sh`
- [x] Stale `raw-deploy.yml` removed

## Calling / federation / push smoke

1. DNS for `call.` / `rtc.` (and `push.` when `ENABLE_PUSH=true`)
2. Deploy → Caddy certs
3. Two-client first-party 1:1 voice call on web and one
   supported Flutter target (answer/reject/mute/hangup + remote audio)
4. Two-client first-party MatrixRTC/LiveKit group call; Element Call only if JWT/SFU fails
5. Verify TURN on UDP/TCP `3478` and relay ports `49160-49200`; TLS `443`
   belongs to Caddy and is not advertised as TURN/TLS
6. Matrix.org Federation Tester
7. Cron `scripts/backup-highlife.sh`
8. Keep `DEPLOY_PASSWORD` if you use password SSH interactively
