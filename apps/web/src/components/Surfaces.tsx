import type { RoomListItem, TimelineItem } from "@highlife/ui-contracts";
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore, type FormEvent } from "react";
import { useI18n, type MessageKey, type MessageParams } from "../i18n";
import { JoinRoomFailure } from "../matrix/roomAddress";
import { callWidgetId } from "../matrix/callUrl";
import {
  createRoom,
  deleteOtherDevice,
  deleteServerKeyBackup,
  enableExistingKeyBackup,
  ensureOwnDeviceCrossSigned,
  fetchOpenIdToken,
  getCryptoStatus,
  getGroupCallUrl,
  getIncomingVerification,
  getJoinedMembers,
  getKeyBackupDetails,
  getOwnDisplayName,
  getOwnAvatarUrl,
  fetchProfileAbout,
  getOwnPresence,
  getRoomAliases,
  getSessionIdentity,
  invite,
  joinRoom,
  listOwnDevices,
  listSpaces,
  leaveRoom,
  logout,
  addRoomToSpace,
  rememberRecoveryKey,
  requestDeviceVerification,
  requestDesktopNotifications,
  browserNotificationPermission,
  resetKeyBackup,
  respondToIncomingVerification,
  restoreFromKeyBackup,
  searchMessages,
  sendMiniAppData,
  sendWidgetRoomEvent,
  widgetDownloadContent,
  widgetUploadContent,
  setOwnPresence,
  setupRecoveryAndKeyBackup,
  startDirectMessage,
  subscribeIncomingVerification,
  CryptoUnavailableError,
  updateProfile,
  setCanonicalAlias,
  removeRoomAlias,
  setRoomAvatar,
  createPoll,
  getUserPresence,
  getUserProfileInfo,
  isUserIgnored,
  listRoomMedia,
  mediaUrl,
  resolveMediaObjectUrl,
  enableRoomEncryption,
  requestUserVerification,
  setUserIgnored,
  fetchRoomSummary,
  knockOnRoom,
  listRoomKnocks,
  approveKnock,
  denyKnock,
  beginLinkDeviceQr,
  isQrLoginAvailable,
  type SearchHit,
  type EncryptionDevice,
  type KeyBackupDetails,
  type RoomMemberInfo,
  type SasChallenge,
} from "../matrix/service";
import { attachElementCallWidgetHost } from "../matrix/widgetHost";
import {
  extractMiniAppInitData,
  isAllowedMiniAppUrl,
  type MiniAppCard,
} from "../protocol/aiomatrix";
import { Avatar } from "./Avatar";
import { IconBack } from "./Icons";
import { QrLoginPanel } from "./QrLoginPanel";
import { applyTheme, THEME_STORAGE_KEY, type Theme } from "../theme";
import { formatPresenceLabel } from "../matrix/messengerExtras";
import type { RoomSummary } from "../matrix/specFeatures";

type Translate = (key: MessageKey, params?: MessageParams) => string;

export function Modal({ title, onClose, children, wide = false }: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
  wide?: boolean;
}) {
  const { t } = useI18n();
  const closeButton = useRef<HTMLButtonElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    const previous = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
    closeButton.current?.focus();
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") close.current();
      if (event.key !== "Tab") return;
      const modal = closeButton.current?.closest(".modal");
      const focusable = [...(modal?.querySelectorAll<HTMLElement>(
        "button:not(:disabled), input:not(:disabled), textarea:not(:disabled), a[href], iframe",
      ) ?? [])];
      if (focusable.length === 0) return;
      const first = focusable[0]!;
      const last = focusable.at(-1)!;
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      previous?.focus();
    };
  }, []);

  return (
    <div className="modal-layer" role="dialog" aria-modal="true" aria-label={title}>
      <button className="modal-backdrop" onClick={onClose} aria-label={t("common.closeNamed", { title })} />
      <section className={`modal ${wide ? "wide" : ""}`}>
        <header><h2>{title}</h2><button ref={closeButton} className="icon-button" onClick={onClose} aria-label={t("common.close")}>×</button></header>
        <div className="modal-body">{children}</div>
      </section>
    </div>
  );
}

export function RoomActions({ onClose, onOpen }: { onClose: () => void; onOpen: (roomId: string) => void }) {
  const { t } = useI18n();
  const cryptoReady = getCryptoStatus().enabled;
  const [tab, setTab] = useState<"join" | "create" | "dm">("join");
  const [value, setValue] = useState("");
  const [topic, setTopic] = useState("");
  const [alias, setAlias] = useState("");
  const [encrypted, setEncrypted] = useState(cryptoReady);
  const [error, setError] = useState<string | null>(null);
  const [preview, setPreview] = useState<RoomSummary | null>(null);
  const [knocked, setKnocked] = useState(false);

  function switchTab(next: typeof tab) {
    setTab(next);
    setValue("");
    setTopic("");
    setAlias("");
    setError(null);
    setEncrypted(cryptoReady);
    setPreview(null);
    setKnocked(false);
  }

  useEffect(() => {
    if (tab !== "join") return;
    const address = value.trim();
    if (!address) {
      setPreview(null);
      return;
    }
    let cancelled = false;
    const timer = window.setTimeout(() => {
      void fetchRoomSummary(address)
        .then((summary) => {
          if (!cancelled) setPreview(summary);
        })
        .catch(() => {
          if (!cancelled) setPreview(null);
        });
    }, 400);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [tab, value]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      let roomId: string;
      if (tab === "join") {
        if (preview?.joinRule === "knock" || preview?.joinRule === "knock_restricted") {
          await knockOnRoom(value.trim());
          setKnocked(true);
          return;
        }
        roomId = await joinRoom(value.trim());
      } else if (tab === "dm") {
        roomId = await startDirectMessage(value.trim(), encrypted && cryptoReady);
      } else {
        roomId = await createRoom({
          name: value.trim(),
          topic: topic.trim() || undefined,
          alias: alias.trim() || undefined,
          encrypted: encrypted && cryptoReady,
        });
      }
      onOpen(roomId);
      onClose();
    } catch (reason) {
      if (reason instanceof CryptoUnavailableError) {
        setError(t("composer.cryptoUnavailable"));
        return;
      }
      if (reason instanceof JoinRoomFailure) {
        if (reason.kind === "forbidden" && tab === "join") {
          try {
            await knockOnRoom(value.trim());
            setKnocked(true);
            setError(null);
            return;
          } catch {
            /* fall through to join error */
          }
        }
        const key =
          reason.kind === "banned"
            ? "rooms.joinBanned"
            : reason.kind === "forbidden"
              ? "rooms.joinForbidden"
              : reason.kind === "not_found"
                ? "rooms.joinNotFound"
                : reason.kind === "bad_request"
                  ? "rooms.joinBadRequest"
                  : "rooms.requestFailed";
        setError(
          reason.kind === "unknown"
            ? reason.message || t("rooms.requestFailed")
            : t(key, { room: reason.attempted }),
        );
        return;
      }
      setError(reason instanceof Error ? reason.message : t("rooms.requestFailed"));
    }
  }

  const submitLabel = tab === "join"
    ? (preview?.joinRule === "knock" || preview?.joinRule === "knock_restricted" || knocked
      ? t("rooms.knock")
      : t("rooms.joinRoom"))
    : tab === "dm"
      ? t("rooms.startDm")
      : t("rooms.createRoom");

  return (
    <Modal title={t("rooms.title")} onClose={onClose}>
      <div className="tabs tabs-3" role="tablist" aria-label={t("rooms.title")}>
        <button type="button" role="tab" aria-selected={tab === "join"} className={tab === "join" ? "active" : ""} onClick={() => switchTab("join")}>{t("rooms.join")}</button>
        <button type="button" role="tab" aria-selected={tab === "create"} className={tab === "create" ? "active" : ""} onClick={() => switchTab("create")}>{t("rooms.create")}</button>
        <button type="button" role="tab" aria-selected={tab === "dm"} className={tab === "dm" ? "active" : ""} onClick={() => switchTab("dm")}>{t("rooms.dm")}</button>
      </div>
      <form className="stack-form" onSubmit={submit}>
        <label>
          <span>
            {tab === "join"
              ? t("rooms.address")
              : tab === "dm"
                ? t("rooms.directMessage")
                : t("rooms.name")}
          </span>
          <input
            value={value}
            onChange={(event) => setValue(event.target.value)}
            placeholder={
              tab === "join"
                ? t("rooms.addressPlaceholder")
                : tab === "dm"
                  ? t("rooms.userIdPlaceholder")
                  : t("rooms.namePlaceholder")
            }
            required
          />
        </label>
        {tab === "join" && <p className="muted small">{t("rooms.joinHint")}</p>}
        {tab === "join" && preview && (
          <div className="room-preview">
            <strong>{preview.name ?? preview.roomId}</strong>
            {preview.topic && <p className="muted small">{preview.topic}</p>}
            {preview.numJoinedMembers != null && (
              <p className="muted small">{t("rooms.membersCount", { count: preview.numJoinedMembers })}</p>
            )}
          </div>
        )}
        {knocked && <p className="muted small" role="status">{t("rooms.knockSent")}</p>}
        {tab === "create" && (
          <>
            <label>
              <span>{t("rooms.topic")}</span>
              <input value={topic} onChange={(event) => setTopic(event.target.value)} placeholder={t("rooms.topicPlaceholder")} />
            </label>
            <label>
              <span>{t("rooms.aliasOptional")}</span>
              <input value={alias} onChange={(event) => setAlias(event.target.value)} placeholder={t("rooms.aliasPlaceholder")} />
            </label>
            <label className="check">
              <input
                type="checkbox"
                checked={encrypted && cryptoReady}
                disabled={!cryptoReady}
                onChange={(event) => setEncrypted(event.target.checked)}
              />
              {" "}{t("rooms.enableE2ee")}
            </label>
            {!cryptoReady && <p className="muted small">{t("rooms.e2eeNeedsCrypto")}</p>}
          </>
        )}
        {tab === "dm" && (
          <label className="check">
            <input
              type="checkbox"
              checked={encrypted && cryptoReady}
              disabled={!cryptoReady}
              onChange={(event) => setEncrypted(event.target.checked)}
            />
            {" "}{t("rooms.enableE2ee")}
          </label>
        )}
        {tab === "dm" && !cryptoReady && <p className="muted small">{t("rooms.e2eeNeedsCrypto")}</p>}
        {error && <p className="error" role="alert">{error}</p>}
        <button className="button primary">{submitLabel}</button>
      </form>
    </Modal>
  );
}

/** Dedicated Space (= folder) creation — not mixed with chat create/join. */
export function CreateSpace({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: (spaceId: string) => void;
}) {
  const { t } = useI18n();
  const [name, setName] = useState("");
  const [topic, setTopic] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const spaceId = await createRoom({
        name: name.trim(),
        topic: topic.trim() || undefined,
        encrypted: false,
        isSpace: true,
      });
      onCreated(spaceId);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("rooms.requestFailed"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title={t("spaces.createTitle")} onClose={onClose}>
      <p className="muted">{t("spaces.blurb")}</p>
      <form className="stack-form" onSubmit={submit}>
        <label>
          <span>{t("spaces.name")}</span>
          <input
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder={t("spaces.namePlaceholder")}
            required
            autoFocus
          />
        </label>
        <label>
          <span>{t("spaces.topicOptional")}</span>
          <input
            value={topic}
            onChange={(event) => setTopic(event.target.value)}
            placeholder={t("spaces.topicPlaceholder")}
          />
        </label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="button primary" disabled={busy || !name.trim()}>
          {busy ? t("login.connecting") : t("spaces.createAction")}
        </button>
      </form>
    </Modal>
  );
}

function backupLabel(details: KeyBackupDetails, t: Translate): string {
  if (details.status === "unavailable") return t("settings.backupUnavailable");
  if (details.status === "missing") return t("settings.backupMissing");
  if (details.status === "enabled" && details.activeVersion) {
    return t("settings.backupEnabled", { version: details.activeVersion });
  }
  return t("settings.backupConfigured");
}

export function Settings({ onClose }: { onClose: () => void }) {
  const { t, locale, setLocale } = useI18n();
  const [theme, setTheme] = useState<Theme>(
    document.documentElement.dataset.theme === "light"
      || document.documentElement.dataset.theme === "dark"
      ? document.documentElement.dataset.theme
      : "system",
  );
  const [displayName, setDisplayName] = useState(() => getOwnDisplayName());
  const [about, setAbout] = useState("");
  const [avatar, setAvatar] = useState<File | undefined>();
  const [avatarUrl, setAvatarUrl] = useState(() => getOwnAvatarUrl());
  const [backup, setBackup] = useState<KeyBackupDetails | null>(null);
  const [devices, setDevices] = useState<EncryptionDevice[]>([]);
  const [verification, setVerification] = useState<string | null>(null);
  const [sas, setSas] = useState<SasChallenge | null>(null);
  const [recoveryKeyInput, setRecoveryKeyInput] = useState("");
  const [newRecoveryKey, setNewRecoveryKey] = useState<string | null>(null);
  const [cryptoBusy, setCryptoBusy] = useState(false);
  const [cryptoMessage, setCryptoMessage] = useState<string | null>(null);
  const [presence, setPresence] = useState(getOwnPresence);
  const [copiedMxid, setCopiedMxid] = useState(false);
  const [copiedHs, setCopiedHs] = useState(false);
  const [notif, setNotif] = useState(browserNotificationPermission);
  const [sessionPassword, setSessionPassword] = useState("");
  const [qrOpen, setQrOpen] = useState(false);
  const identity = getSessionIdentity();
  const crypto = getCryptoStatus();
  const incoming = useSyncExternalStore(subscribeIncomingVerification, getIncomingVerification, () => null);

  const refreshCrypto = useCallback(() => {
    void getKeyBackupDetails().then(setBackup).catch(() => setBackup({
      serverInfo: null,
      activeVersion: null,
      secretStorageReady: false,
      status: "unavailable",
    }));
    void listOwnDevices().then(setDevices).catch(() => setDevices([]));
  }, []);

  useEffect(() => {
    setDisplayName(getOwnDisplayName());
    const userId = getSessionIdentity()?.userId;
    if (userId) void fetchProfileAbout(userId).then(setAbout).catch(() => setAbout(""));
    refreshCrypto();
  }, [refreshCrypto]);

  function changeTheme(value: Theme) {
    setTheme(value);
    localStorage.setItem(THEME_STORAGE_KEY, value);
    applyTheme(value);
  }

  function beginVerification(deviceId?: string) {
    setVerification(t("settings.sendingVerification"));
    setSas(null);
    void requestDeviceVerification(deviceId, setSas, setVerification)
      .then((request) => setVerification(t("settings.verificationWaiting", {
        id: request.transactionId ?? "sent",
        device: request.otherDeviceId ?? t("settings.anotherDevice"),
      })))
      .catch((error: Error) => setVerification(error.message));
  }

  async function runCrypto(action: () => Promise<void>): Promise<void> {
    setCryptoBusy(true);
    setCryptoMessage(null);
    try {
      await action();
      refreshCrypto();
    } catch (error) {
      setCryptoMessage(error instanceof Error ? error.message : t("settings.genericError"));
    } finally {
      setCryptoBusy(false);
    }
  }

  return (
    <section className="profile-page" aria-label={t("profile.title")}>
      <header className="profile-head">
        <button className="icon-button" type="button" onClick={onClose} aria-label={t("chat.back")}>
          <IconBack />
        </button>
        <strong>{t("profile.title")}</strong>
      </header>
      <div className="profile-body">
      <div className="profile-hero">
        <Avatar
          id={identity?.userId ?? displayName}
          name={displayName || t("settings.profile")}
          src={avatarUrl}
          size="large"
        />
        <strong>{displayName || t("settings.profile")}</strong>
        {identity?.userId && (
          <button
            type="button"
            className="profile-mxid"
            onClick={() => {
              void navigator.clipboard.writeText(identity.userId).then(() => {
                setCopiedMxid(true);
                window.setTimeout(() => setCopiedMxid(false), 1600);
              });
            }}
          >
            {copiedMxid ? t("profile.copied") : identity.userId}
          </button>
        )}
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("settings.profile")}</p>
        <form className="profile-form" onSubmit={(event) => {
          event.preventDefault();
          void updateProfile(displayName, avatar, about).then(() => {
            setAvatar(undefined);
            setAvatarUrl(getOwnAvatarUrl());
          });
        }}>
          <div>
            <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder={t("settings.displayNamePlaceholder")} aria-label={t("settings.displayName")} />
            <textarea
              value={about}
              onChange={(event) => setAbout(event.target.value)}
              placeholder={t("settings.aboutPlaceholder")}
              aria-label={t("settings.about")}
              rows={3}
            />
            <label className="button file-button">
              {t("settings.chooseAvatar")}
              <input type="file" accept="image/*" onChange={(event) => setAvatar(event.target.files?.[0])} />
            </label>
            {avatar && <small className="muted">{avatar.name}</small>}
          </div>
          <button className="button" type="submit">{t("settings.save")}</button>
        </form>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("profile.account")}</p>
        <dl className="status-list">
          {identity?.userId && (
            <div>
              <dt>{t("login.userId")}</dt>
              <dd>{identity.userId}</dd>
            </div>
          )}
          {identity?.baseUrl && (
            <div>
              <dt>{t("profile.homeserver")}</dt>
              <dd>
                <button
                  type="button"
                  className="profile-mxid"
                  onClick={() => {
                    void navigator.clipboard.writeText(identity.baseUrl).then(() => {
                      setCopiedHs(true);
                      window.setTimeout(() => setCopiedHs(false), 1600);
                    });
                  }}
                >
                  {copiedHs ? t("profile.copied") : identity.baseUrl}
                </button>
              </dd>
            </div>
          )}
          {identity?.deviceId && (
            <div>
              <dt>{t("settings.device")}</dt>
              <dd>{identity.deviceId}</dd>
            </div>
          )}
        </dl>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("profile.presence")}</p>
        <div className="segmented">
          {([
            ["online", "profile.online"],
            ["unavailable", "profile.away"],
            ["offline", "profile.offline"],
          ] as const).map(([value, key]) => (
            <button
              key={value}
              type="button"
              className={presence === value ? "active" : ""}
              onClick={() => {
                setPresence(value);
                void setOwnPresence(value);
              }}
            >
              {t(key)}
            </button>
          ))}
        </div>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("settings.appearance")}</p>
        <div className="segmented">
          {([
            ["system", "settings.themeSystem"],
            ["light", "settings.themeLight"],
            ["dark", "settings.themeDark"],
          ] as const).map(([value, key]) => (
            <button key={value} type="button" className={theme === value ? "active" : ""} onClick={() => changeTheme(value)}>
              {t(key)}
            </button>
          ))}
        </div>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("settings.language")}</p>
        <div className="segmented">
          <button type="button" className={locale === "en" ? "active" : ""} onClick={() => setLocale("en")}>{t("settings.languageEn")}</button>
          <button type="button" className={locale === "ru" ? "active" : ""} onClick={() => setLocale("ru")}>{t("settings.languageRu")}</button>
        </div>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("profile.notifications")}</p>
        {notif === "unsupported" ? (
          <p className="muted small">{t("profile.notificationsUnsupported")}</p>
        ) : notif === "granted" ? (
          <p className="muted small">{t("profile.notificationsOn")}</p>
        ) : notif === "denied" ? (
          <p className="muted small">{t("profile.notificationsBlocked")}</p>
        ) : (
          <button
            className="button"
            type="button"
            onClick={() => {
              void requestDesktopNotifications().then(setNotif);
            }}
          >
            {t("profile.notificationsEnable")}
          </button>
        )}
        <p className="muted small">{t("profile.notificationsHint")}</p>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("settings.encryption")}</p>
        <p className="muted small">{t("settings.encryptionSummary")}</p>
        <dl className="status-list">
          <div><dt>{t("settings.rustCrypto")}</dt><dd>{crypto.enabled ? t("settings.ready") : t("settings.unavailable")}</dd></div>
          <div><dt>{t("settings.device")}</dt><dd>{crypto.deviceId ?? t("settings.unknown")}</dd></div>
          <div><dt>{t("settings.keyBackup")}</dt><dd>{backup ? backupLabel(backup, t) : t("settings.checking")}</dd></div>
          <div><dt>{t("settings.secretStorage")}</dt><dd>{backup ? (backup.secretStorageReady ? t("settings.ready") : t("settings.unavailable")) : "…"}</dd></div>
          <div><dt>{t("settings.activeBackup")}</dt><dd>{backup?.activeVersion ?? t("settings.none")}</dd></div>
        </dl>
        <p className="muted small">{t("settings.encryptionNote")}</p>
        {cryptoBusy && <p className="muted small" role="status">{t("settings.cryptoBusy")}</p>}
        <div className="crypto-actions">
          <button className="button" type="button" disabled={cryptoBusy || !crypto.enabled} onClick={() => void runCrypto(async () => {
            const result = await setupRecoveryAndKeyBackup();
            setNewRecoveryKey(result.recoveryKey);
            setCryptoMessage(t("settings.setupDone"));
          })}>{t("settings.setupRecovery")}</button>
          <button className="button" type="button" disabled={cryptoBusy || !crypto.enabled} onClick={() => void runCrypto(async () => {
            await resetKeyBackup();
            setCryptoMessage(t("settings.resetDone"));
          })}>{t("settings.resetBackup")}</button>
          <button className="button" type="button" disabled={cryptoBusy || !crypto.enabled} onClick={() => void runCrypto(async () => {
            await enableExistingKeyBackup();
            setCryptoMessage(t("settings.enabledBackup"));
          })}>{t("settings.enableBackup")}</button>
          <button className="button" type="button" disabled={cryptoBusy || !crypto.enabled} onClick={() => void runCrypto(async () => {
            const result = await restoreFromKeyBackup();
            setCryptoMessage(t("settings.restored", result));
          })}>{t("settings.restoreBackup")}</button>
          <button className="button danger" type="button" disabled={cryptoBusy || !crypto.enabled} onClick={() => void runCrypto(async () => {
            await deleteServerKeyBackup();
            setCryptoMessage(t("settings.deletedBackup"));
          })}>{t("settings.deleteBackup")}</button>
        </div>
        <label className="stack-field">
          <span>{t("settings.recoveryKey")}</span>
          <textarea
            value={recoveryKeyInput}
            onChange={(event) => setRecoveryKeyInput(event.target.value)}
            placeholder={t("settings.recoveryKeyHint")}
            rows={2}
          />
        </label>
        <button className="button" type="button" disabled={!recoveryKeyInput.trim() || cryptoBusy} onClick={() => {
          void runCrypto(async () => {
            rememberRecoveryKey(recoveryKeyInput);
            setRecoveryKeyInput("");
            try {
              const result = await restoreFromKeyBackup();
              setCryptoMessage(t("settings.restored", result));
            } catch {
              setCryptoMessage(t("settings.recoveryKeySaved"));
            }
          });
        }}>{t("settings.useRecoveryKey")}</button>
        {newRecoveryKey && (
          <div className="recovery-key-panel" role="status">
            <strong>{t("settings.newRecoveryKey")}</strong>
            <code>{newRecoveryKey}</code>
            <button className="button" type="button" onClick={() => void navigator.clipboard.writeText(newRecoveryKey)}>{t("settings.copyKey")}</button>
            <button className="button" type="button" onClick={() => setNewRecoveryKey(null)}>{t("settings.dismissRecoveryKey")}</button>
          </div>
        )}
        {cryptoMessage && <p className="muted small" role="status">{cryptoMessage}</p>}
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("profile.sessions")}</p>
        <p className="muted small">{t("settings.linkNewDeviceHint")}</p>
        {qrOpen ? (
          <QrLoginPanel start={beginLinkDeviceQr} onClose={() => setQrOpen(false)} />
        ) : (
          <button
            type="button"
            className="button"
            onClick={() => {
              void isQrLoginAvailable().then((available) => {
                if (available) setQrOpen(true);
                else setCryptoMessage(t("login.qrUnavailable"));
              }).catch(() => setQrOpen(true));
            }}
          >
            {t("settings.linkNewDevice")}
          </button>
        )}
        {incoming && (
          <div className="incoming-verification">
            <strong>{t("settings.incomingVerification")}</strong>
            <p className="muted small">{t("settings.fromDevice", {
              user: incoming.otherUserId,
              device: incoming.otherDeviceId ?? "—",
            })}</p>
            <div>
              <button className="button primary" type="button" onClick={() => {
                setSas(null);
                void respondToIncomingVerification(true, setSas, setVerification).catch((error: Error) => setVerification(error.message));
              }}>{t("settings.accept")}</button>
              <button className="button danger" type="button" onClick={() => {
                void respondToIncomingVerification(false, setSas, setVerification).catch((error: Error) => setVerification(error.message));
              }}>{t("settings.decline")}</button>
            </div>
          </div>
        )}
        <div className="device-list">
          {devices.length === 0 ? (
            <p className="muted small">{t("settings.noDevices")}</p>
          ) : (
            devices.map((device) => (
              <article key={device.deviceId}>
                <div>
                  <strong>{(device.displayName || t("settings.unnamedDevice"))}{device.current ? ` · ${t("settings.thisDevice")}` : ""}</strong>
                  <small>{device.deviceId} · {device.fingerprint?.slice(0, 20) ?? t("settings.noFingerprint")}</small>
                </div>
                <span>{device.verified ? t("settings.verified") : device.dehydrated ? t("settings.dehydrated") : t("settings.unverified")}</span>
                {!device.current && !device.verified && <button className="button" type="button" onClick={() => beginVerification(device.deviceId)}>{t("settings.verify")}</button>}
                {!device.current && (
                  <button
                    className="text-button danger-text"
                    type="button"
                    onClick={() => void runCrypto(async () => {
                      await deleteOtherDevice(device.deviceId, sessionPassword || undefined);
                      setSessionPassword("");
                      setCryptoMessage(t("settings.deviceSignedOut"));
                    })}
                  >
                    {t("settings.signOutDevice")}
                  </button>
                )}
              </article>
            ))
          )}
        </div>
        {devices.some((device) => device.current && !device.signedByOwner) && (
          <p className="muted small">{t("settings.thisDeviceUnsigned")}</p>
        )}
        <label>
          <span className="muted small">{t("settings.passwordToConfirm")}</span>
          <input
            type="password"
            value={sessionPassword}
            onChange={(event) => setSessionPassword(event.target.value)}
            autoComplete="current-password"
          />
        </label>
        <p className="muted small">{t("settings.signOutDeviceHint")}</p>
        {devices.some((device) => device.current && !device.signedByOwner) && (
          <button
            className="button"
            type="button"
            disabled={cryptoBusy || !crypto.enabled}
            onClick={() => void runCrypto(async () => {
              await ensureOwnDeviceCrossSigned(sessionPassword || undefined);
              setSessionPassword("");
            })}
          >
            {t("settings.signThisDevice")}
          </button>
        )}
        {devices.some((device) => !device.current) && <button className="button" type="button" onClick={() => beginVerification()}>{t("settings.verifyOther")}</button>}
        {verification && <p className="muted small" role="status">{verification}</p>}
        {sas && <div className="sas-panel">
          <strong>{t("settings.compareDevices")}</strong>
          {sas.emoji.length > 0 ? <div className="sas-emoji">{sas.emoji.map(([emoji, name]) => <span key={name} title={name}>{emoji}<small>{name}</small></span>)}</div> : <p className="sas-decimal">{sas.decimal?.join(" · ")}</p>}
          <div>
            <button className="button primary" type="button" onClick={() => void sas.confirm().then(() => setVerification(t("settings.deviceVerified")))}>{t("settings.theyMatch")}</button>
            <button className="button danger" type="button" onClick={() => { sas.mismatch(); setSas(null); }}>{t("settings.theyDoNotMatch")}</button>
          </div>
        </div>}
      </div>
      <div className="settings-section settings-section-last">
        <button className="button danger" type="button" onClick={() => void logout()}>{t("settings.signOut")}</button>
      </div>
      </div>
    </section>
  );
}

export function RoomDetails({
  room,
  onClose,
  onLeft,
  onJump,
  onOpenUser,
}: {
  room: RoomListItem;
  onClose: () => void;
  onLeft: () => void;
  onJump?: (eventId: string) => void;
  onOpenUser?: (userId: string) => void;
}) {
  const { t } = useI18n();
  const [userId, setUserId] = useState("");
  const [spaceId, setSpaceId] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [members, setMembers] = useState<RoomMemberInfo[]>([]);
  const [alias, setAlias] = useState("");
  const [aliases, setAliases] = useState(() => getRoomAliases(room.roomId));
  const [roomAvatar, setRoomAvatarFile] = useState<File | undefined>();
  const media = listRoomMedia(room.roomId);
  const spaces = listSpaces().filter((space) => space.roomId !== room.roomId);
  const [knocks, setKnocks] = useState(() => listRoomKnocks(room.roomId));

  useEffect(() => {
    setMembers(getJoinedMembers(room.roomId));
    setAliases(getRoomAliases(room.roomId));
    setKnocks(listRoomKnocks(room.roomId));
  }, [room.roomId]);

  return (
    <Modal title={room.name} onClose={onClose}>
      <div className="room-profile">
        <Avatar id={room.roomId} name={room.name} src={room.avatarUrl} size="large" />
        <div>
          <strong>{room.name}</strong>
          <span className="muted small">{aliases.canonicalAlias ?? room.roomId}</span>
        </div>
      </div>
      {room.topic && <p>{room.topic}</p>}
      <dl className="status-list">
        <div><dt>{t("rooms.roomId")}</dt><dd className="utility-id">{room.roomId}</dd></div>
        <div>
          <dt>{t("rooms.canonicalAlias")}</dt>
          <dd>
            {aliases.canonicalAlias ?? t("rooms.noAlias")}
            {aliases.canonicalAlias && (
              <button
                className="text-button"
                type="button"
                onClick={() => void navigator.clipboard.writeText(aliases.canonicalAlias!)}
              >
                {t("rooms.copyAlias")}
              </button>
            )}
          </dd>
        </div>
        <div><dt>{t("rooms.encryption")}</dt><dd>{room.isEncrypted ? t("rooms.enabled") : t("rooms.off")}</dd></div>
      </dl>
      {!room.isEncrypted && (
        <button
          className="button"
          type="button"
          onClick={() => {
            if (!window.confirm(t("rooms.encryptConfirm"))) return;
            void enableRoomEncryption(room.roomId)
              .then(() => setStatus(t("rooms.enabled")))
              .catch((error: Error) => setStatus(error.message || t("rooms.encryptFailed")));
          }}
        >
          {t("rooms.enableE2ee")}
        </button>
      )}
      <div className="settings-section">
        <p className="eyebrow">{t("rooms.roomAvatar")}</p>
        <form className="inline-form" onSubmit={(event) => {
          event.preventDefault();
          if (!roomAvatar) return;
          void setRoomAvatar(room.roomId, roomAvatar)
            .then(() => {
              setRoomAvatarFile(undefined);
              setStatus(t("rooms.avatarUpdated"));
            })
            .catch((error: Error) => setStatus(error.message));
        }}>
          <label className="button file-button">
            {t("rooms.roomAvatar")}
            <input
              type="file"
              accept="image/*"
              aria-label={t("rooms.roomAvatar")}
              onChange={(event) => setRoomAvatarFile(event.target.files?.[0])}
            />
          </label>
          <button className="button" disabled={!roomAvatar}>{t("settings.save")}</button>
        </form>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("rooms.aliases")}</p>
        <form className="inline-form" onSubmit={(event) => {
          event.preventDefault();
          void setCanonicalAlias(room.roomId, alias)
            .then(() => {
              setAliases(getRoomAliases(room.roomId));
              setAlias("");
              setStatus(t("rooms.aliasUpdated"));
            })
            .catch((error: Error) => setStatus(error.message));
        }}>
          <input
            value={alias}
            onChange={(event) => setAlias(event.target.value)}
            placeholder={t("rooms.aliasPlaceholder")}
            aria-label={t("rooms.canonicalAlias")}
            required
          />
          <button className="button" disabled={!alias.trim()}>{t("rooms.setAlias")}</button>
        </form>
        {aliases.aliases.map((item) => (
          <div className="alias-row" key={item}>
            <code>{item}</code>
            <button type="button" className="text-button" onClick={() => void navigator.clipboard.writeText(item)}>
              {t("rooms.copyAlias")}
            </button>
            <button type="button" className="text-button danger-text" onClick={() => {
              void removeRoomAlias(room.roomId, item)
                .then(() => setAliases(getRoomAliases(room.roomId)))
                .catch((error: Error) => setStatus(error.message));
            }}>
              {t("rooms.removeAlias")}
            </button>
          </div>
        ))}
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("rooms.members")}</p>
        <div className="member-list" data-testid="member-list">
          {members.length === 0 && <p className="muted small">{t("rooms.noMembers")}</p>}
          {members.map((member) => (
            <article key={member.userId}>
              <button
                type="button"
                className="member-open"
                onClick={() => onOpenUser?.(member.userId)}
              >
                <Avatar id={member.userId} name={member.displayName} src={member.avatarUrl} size="small" />
                <div>
                  <strong>{member.displayName}</strong>
                  <small>{member.userId}</small>
                </div>
              </button>
              <span>{t("rooms.power", { level: member.powerLevel })}</span>
            </article>
          ))}
        </div>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("rooms.pendingKnocks")}</p>
        <div className="member-list">
          {knocks.length === 0 && <p className="muted small">{t("rooms.noKnocks")}</p>}
          {knocks.map((knock) => (
            <article key={knock.userId}>
              <div>
                <strong>{knock.name}</strong>
                <small>{knock.userId}</small>
              </div>
              <button
                type="button"
                className="button"
                onClick={() => {
                  void approveKnock(room.roomId, knock.userId)
                    .then(() => setKnocks(listRoomKnocks(room.roomId)))
                    .catch((error: Error) => setStatus(error.message));
                }}
              >
                {t("rooms.approveKnock")}
              </button>
              <button
                type="button"
                className="text-button danger-text"
                onClick={() => {
                  void denyKnock(room.roomId, knock.userId)
                    .then(() => setKnocks(listRoomKnocks(room.roomId)))
                    .catch((error: Error) => setStatus(error.message));
                }}
              >
                {t("rooms.denyKnock")}
              </button>
            </article>
          ))}
        </div>
      </div>
      <div className="settings-section">
        <p className="eyebrow">{t("rooms.invite")}</p>
        <form className="stack-form" onSubmit={(event) => {
          event.preventDefault();
          void invite(room.roomId, userId)
            .then(() => setStatus(t("rooms.invitationSent")))
            .catch((error: Error) => setStatus(error.message));
        }}>
          <label>
            <span>{t("rooms.inviteUser")}</span>
            <input value={userId} onChange={(event) => setUserId(event.target.value)} placeholder={t("rooms.invitePlaceholder")} required />
          </label>
          <button className="button" type="submit">{t("rooms.invite")}</button>
        </form>
      </div>
      {!room.isSpace && (
        <div className="settings-section">
          <p className="eyebrow">{t("rooms.folderSection")}</p>
          <p className="muted small">{t("rooms.folderHint")}</p>
          {spaces.length === 0 ? (
            <p className="muted small">{t("rooms.noSpacesYet")}</p>
          ) : (
            <form
              className="stack-form"
              onSubmit={(event) => {
                event.preventDefault();
                const target = spaceId.trim();
                if (!target) return;
                void addRoomToSpace(target, room.roomId)
                  .then(() => {
                    setStatus(t("rooms.addToSpaceDone"));
                    setSpaceId("");
                  })
                  .catch((error: Error) => setStatus(error.message));
              }}
            >
              <label>
                <span>{t("rooms.addToSpace")}</span>
                <select
                  value={spaceId}
                  onChange={(event) => setSpaceId(event.target.value)}
                  required
                >
                  <option value="">{t("rooms.addToSpacePlaceholder")}</option>
                  {spaces.map((space) => (
                    <option key={space.roomId} value={space.roomId}>{space.name}</option>
                  ))}
                </select>
              </label>
              <button className="button" type="submit" disabled={!spaceId.trim()}>
                {t("rooms.addToFolder")}
              </button>
            </form>
          )}
        </div>
      )}
      <div className="settings-section">
        <p className="eyebrow">{t("rooms.sharedMedia")}</p>
        {media.length === 0 ? (
          <p className="muted small">{t("rooms.noSharedMedia")}</p>
        ) : (
          <ul className="shared-media-list">
            {media.map((item) => (
              <li key={item.eventId}>
                <button type="button" onClick={() => onJump?.(item.eventId)}>
                  <SharedMediaThumb item={item} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      {status && <p className="muted" role="status">{status}</p>}
      <div className="settings-section settings-section-last">
        <button
          className="button danger"
          type="button"
          onClick={() => {
            if (!window.confirm(t("rooms.leaveConfirm"))) return;
            void leaveRoom(room.roomId).then(onLeft);
          }}
        >
          {t("rooms.leave")}
        </button>
      </div>
    </Modal>
  );
}

export function SearchSurface({
  roomId,
  onClose,
  onJump,
}: {
  roomId?: string;
  onClose: (eventId?: string) => void;
  onJump?: (eventId: string, roomId?: string) => void;
}) {
  const { t } = useI18n();
  const [query, setQuery] = useState("");
  const [hits, setHits] = useState<SearchHit[]>([]);
  const [busy, setBusy] = useState(false);
  const [searched, setSearched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scopeAll, setScopeAll] = useState(!roomId);
  async function run(event?: FormEvent) {
    event?.preventDefault();
    setBusy(true);
    setError(null);
    try {
      setHits(await searchMessages(query, scopeAll ? undefined : roomId));
      setSearched(true);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("search.failed"));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title={t("search.title")} onClose={() => onClose()}>
      <form className="inline-form" onSubmit={run}>
        <input autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder={scopeAll ? t("search.placeholderAll") : t("search.placeholder")} />
        <button className="button">{busy ? t("search.busy") : t("search.action")}</button>
      </form>
      {roomId && (
        <div className="segmented" role="group">
          <button type="button" className={scopeAll ? "" : "active"} onClick={() => setScopeAll(false)}>
            {t("search.scopeRoom")}
          </button>
          <button type="button" className={scopeAll ? "active" : ""} onClick={() => setScopeAll(true)}>
            {t("search.scopeAll")}
          </button>
        </div>
      )}
      {error && (
        <p className="error" role="alert">
          {error}{" "}
          <button type="button" className="text-button" onClick={() => void run()}>
            {t("search.retry")}
          </button>
        </p>
      )}
      <div className="search-results">
        {!searched && !busy && <p className="muted small">{t("search.emptyHint")}</p>}
        {searched && hits.length === 0 && !error && <p className="muted small">{t("search.noResults")}</p>}
        {hits.map((hit) => (
          <button
            key={hit.eventId}
            type="button"
            className="search-hit"
            onClick={() => {
              onJump?.(hit.eventId, hit.roomId);
              onClose(hit.eventId);
            }}
          >
            <strong>{hit.sender}</strong>
            <p>{hit.body}</p>
            <time>{new Date(hit.timestamp).toLocaleString()}</time>
          </button>
        ))}
      </div>
    </Modal>
  );
}

export function CreatePollSurface({ roomId, onClose }: {
  roomId: string;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const [question, setQuestion] = useState("");
  const [answers, setAnswers] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const options = answers.split("\n").map((item) => item.trim()).filter(Boolean).slice(0, 4);
    if (!question.trim() || options.length < 2) return;
    setBusy(true);
    setError(null);
    try {
      await createPoll(roomId, { question: question.trim(), answers: options });
      onClose();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("composer.sendFailed"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title={t("composer.createPoll")} onClose={onClose}>
      <form className="stack-form" onSubmit={submit}>
        <label>
          <span>{t("composer.pollQuestion")}</span>
          <input value={question} onChange={(event) => setQuestion(event.target.value)} required autoFocus />
        </label>
        <label>
          <span>{t("composer.pollAnswers")}</span>
          <textarea
            rows={4}
            value={answers}
            onChange={(event) => setAnswers(event.target.value)}
            placeholder={t("composer.pollAnswersPlaceholder")}
            required
          />
        </label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="button primary" disabled={busy}>
          {busy ? t("login.connecting") : t("composer.createPoll")}
        </button>
      </form>
    </Modal>
  );
}

export function MiniAppSurface({ card, item, onClose }: { card: MiniAppCard; item: TimelineItem; onClose: () => void }) {
  const { t } = useI18n();
  const frame = useRef<HTMLIFrameElement>(null);
  const trusted = useMemo(() => isAllowedMiniAppUrl(card.url), [card.url]);
  const targetOrigin = useMemo(() => {
    if (!trusted) return null;
    try { return new URL(card.url).origin; } catch { return null; }
  }, [card.url, trusted]);
  useEffect(() => {
    const origin = targetOrigin;
    if (!origin) return;
    function receive(event: MessageEvent) {
      if (event.source !== frame.current?.contentWindow || event.origin !== origin || typeof event.data !== "object" || !event.data) return;
      const data = event.data as { type?: string; payload?: { data?: string } };
      if (data.type === "close") onClose();
      if (data.type === "sendData" && typeof data.payload?.data === "string") {
        void sendMiniAppData(item.roomId, data.payload.data, { appId: card.appId, messageId: item.eventId }).then(onClose);
      }
      if (data.type === "bridgeReady" || data.type === "requestInit") {
        const initData = extractMiniAppInitData(card.url);
        frame.current?.contentWindow?.postMessage({
          source: "aiomatrix-miniapp",
          type: "init",
          payload: {
            platform: "matrix",
            colorScheme: document.documentElement.dataset.theme ?? "light",
            ...(initData ? { initData } : {}),
            matrix: {
              roomId: item.roomId,
              botId: card.botId,
              startParam: card.startParam,
            },
          },
        }, origin);
      }
    }
    window.addEventListener("message", receive);
    return () => window.removeEventListener("message", receive);
  }, [card, item, onClose, targetOrigin]);
  return (
    <div className="modal-layer miniapp-layer" role="dialog" aria-modal="true" aria-label={card.title}>
      <button className="modal-backdrop" onClick={onClose} aria-label={t("common.closeNamed", { title: card.title })} />
      <section className="modal miniapp-shell">
        <header>
          <h2>{card.title}</h2>
          <button className="icon-button" onClick={onClose} aria-label={t("common.close")}>×</button>
        </header>
        <div className="modal-body">
          {!trusted || !targetOrigin ? (
            <div className="capability-error">
              <strong>{t("timeline.miniAppBlockedTitle")}</strong>
              <p>{t("timeline.miniAppBlockedBody")}</p>
            </div>
          ) : (
            // scripts+same-origin is required for the local MiniApp bridge (postMessage
            // + same-origin storage). That combination weakens iframe sandbox isolation;
            // trust instead comes from isAllowedMiniAppUrl (homeserver / VITE_MINIAPP_ALLOWED_ORIGINS).
            <iframe
              ref={frame}
              className="mini-frame"
              src={card.url}
              title={card.title}
              sandbox="allow-scripts allow-same-origin allow-forms"
              allow="clipboard-write; fullscreen"
            />
          )}
        </div>
      </section>
    </div>
  );
}

export function GroupCallSurface({ roomId, onClose }: { roomId: string; onClose: () => void }) {
  const { t } = useI18n();
  const frame = useRef<HTMLIFrameElement>(null);
  const [ready, setReady] = useState(false);
  const url = getGroupCallUrl(roomId);
  const targetOrigin = useMemo(() => {
    if (!url) return "";
    try {
      return new URL(url).origin;
    } catch {
      return "";
    }
  }, [url]);

  useEffect(() => {
    if (!url || !targetOrigin) return;
    return attachElementCallWidgetHost({
      widgetId: callWidgetId(roomId),
      roomId,
      targetOrigin,
      getContentWindow: () => frame.current?.contentWindow,
      sendEvent: sendWidgetRoomEvent,
      getOpenIdToken: fetchOpenIdToken,
      uploadContent: widgetUploadContent,
      downloadContent: widgetDownloadContent,
      onCapabilityChange: () => setReady(true),
    });
  }, [roomId, targetOrigin, url]);

  return (
    <Modal title={t("call.title")} onClose={onClose} wide>
      {!url ? (
        <div className="capability-error">
          <strong>{t("call.configTitle")}</strong>
          <p>{t("call.configBody", { state: t("call.idle") })}</p>
        </div>
      ) : (
        <>
          <p className="call-notice">{ready ? t("call.widgetReady") : t("call.stillLoading")}</p>
          <p>
            <a className="button" href={url} target="_blank" rel="noreferrer">
              {t("call.openExternal")}
            </a>
          </p>
          <iframe
            ref={frame}
            className="call-frame"
            src={url}
            title={t("call.frameTitle")}
            allow="camera; microphone; display-capture; autoplay; fullscreen"
          />
        </>
      )}
    </Modal>
  );
}

export function UserProfile({
  userId,
  onClose,
  onOpenedDm,
  onVerify,
}: {
  userId: string;
  onClose: () => void;
  onOpenedDm: (roomId: string) => void;
  onVerify?: (userId: string) => void;
}) {
  const { t } = useI18n();
  const profile = getUserProfileInfo(userId);
  const presence = getUserPresence(userId);
  const self = getSessionIdentity()?.userId;
  const ignored = isUserIgnored(userId);
  const [status, setStatus] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [about, setAbout] = useState("");
  useEffect(() => {
    let cancelled = false;
    void fetchProfileAbout(userId).then((value) => {
      if (!cancelled) setAbout(value);
    }).catch(() => {
      if (!cancelled) setAbout("");
    });
    return () => {
      cancelled = true;
    };
  }, [userId]);
  const presenceLabel = formatPresenceLabel(
    presence.presence,
    presence.lastActiveAgo,
    presence.currentlyActive,
    {
      online: t("profile.online"),
      away: t("profile.away"),
      offline: t("user.offline"),
      lastSeen: (when) => t("user.lastSeen", { when }),
    },
  );

  return (
    <Modal title={t("user.profile")} onClose={onClose}>
      <div className="room-profile">
        <Avatar id={userId} name={profile.displayName} src={profile.avatarUrl} size="large" />
        <div>
          <strong>{profile.displayName}</strong>
          <button
            type="button"
            className="profile-mxid"
            onClick={() => {
              void navigator.clipboard.writeText(userId).then(() => {
                setCopied(true);
                window.setTimeout(() => setCopied(false), 1600);
              });
            }}
          >
            {copied ? t("profile.copied") : userId}
          </button>
          <span className="muted small">{presenceLabel}</span>
          {about ? <p className="profile-about">{about}</p> : null}
        </div>
      </div>
      {status && <p className="muted small" role="status">{status}</p>}
      {self !== userId && (
        <div className="settings-section">
          <button
            className="button primary"
            type="button"
            onClick={() => {
              void startDirectMessage(userId)
                .then(onOpenedDm)
                .catch((error: Error) => setStatus(error.message));
            }}
          >
            {t("user.startDm")}
          </button>
          <button
            className="button"
            type="button"
            onClick={() => {
              void setUserIgnored(userId, !ignored)
                .then(() => setStatus(ignored ? t("user.unignore") : t("user.ignore")))
                .catch((error: Error) => setStatus(error.message));
            }}
          >
            {ignored ? t("user.unignore") : t("user.ignore")}
          </button>
          {onVerify && (
            <button
              className="button"
              type="button"
              onClick={() => {
                setStatus(t("user.verifying"));
                onVerify(userId);
              }}
            >
              {t("user.verify")}
            </button>
          )}
        </div>
      )}
    </Modal>
  );
}

export function ForwardPicker({
  rooms,
  onClose,
  onPick,
}: {
  rooms: RoomListItem[];
  onClose: () => void;
  onPick: (roomId: string) => void;
}) {
  const { t } = useI18n();
  return (
    <Modal title={t("forward.title")} onClose={onClose}>
      <nav className="forward-list">
        {rooms.map((room) => (
          <button key={room.roomId} type="button" onClick={() => onPick(room.roomId)}>
            <Avatar id={room.roomId} name={room.name} src={room.avatarUrl} size="small" />
            <span>{room.name}</span>
          </button>
        ))}
      </nav>
    </Modal>
  );
}

function SharedMediaThumb({ item }: { item: TimelineItem }) {
  const { t } = useI18n();
  const [source, setSource] = useState(() =>
    item.media && !item.media.encrypted ? mediaUrl(item.media.mxcUrl) : "",
  );

  useEffect(() => {
    let revoked: string | null = null;
    let cancelled = false;
    if (!item.media) return;
    if (!item.media.encrypted) {
      setSource(mediaUrl(item.media.mxcUrl));
      return;
    }
    void resolveMediaObjectUrl(item.media)
      .then((url) => {
        if (cancelled) {
          URL.revokeObjectURL(url);
          return;
        }
        revoked = url;
        setSource(url);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
      if (revoked) URL.revokeObjectURL(revoked);
    };
  }, [item.media]);

  if (item.kind === "image" && source) {
    return <img src={source} alt={item.media?.name ?? t("timeline.image")} />;
  }
  return <span>{item.media?.voice ? t("timeline.voice") : item.media?.name || item.body}</span>;
}
