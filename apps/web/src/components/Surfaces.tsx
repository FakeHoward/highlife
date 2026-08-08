import type { RoomListItem, TimelineItem } from "@highlife/ui-contracts";
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore, type FormEvent } from "react";
import { useI18n, type MessageKey, type MessageParams } from "../i18n";
import { buildElementCallUrl, callWidgetId } from "../matrix/callUrl";
import { attachElementCallWidgetHost } from "../matrix/widgetHost";
import { JoinRoomFailure } from "../matrix/roomAddress";
import {
  createRoom,
  deleteServerKeyBackup,
  enableExistingKeyBackup,
  fetchOpenIdToken,
  getCallCapability,
  getCryptoStatus,
  getIncomingVerification,
  getJoinedMembers,
  getKeyBackupDetails,
  getOwnDisplayName,
  getSessionIdentity,
  invite,
  joinRoom,
  listOwnDevices,
  listSpaces,
  loadThread,
  leaveRoom,
  logout,
  addRoomToSpace,
  paginateThread,
  rememberRecoveryKey,
  requestDeviceVerification,
  resetKeyBackup,
  respondToIncomingVerification,
  restoreFromKeyBackup,
  searchMessages,
  sendMessage,
  sendMiniAppData,
  sendWidgetRoomEvent,
  setupRecoveryAndKeyBackup,
  startDirectMessage,
  subscribeIncomingVerification,
  updateProfile,
  type SearchHit,
  type EncryptionDevice,
  type KeyBackupDetails,
  type RoomMemberInfo,
  type SasChallenge,
} from "../matrix/service";
import { extractMiniAppInitData, type MiniAppCard } from "../protocol/aiomatrix";

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
  const [tab, setTab] = useState<"join" | "create" | "dm">("join");
  const [value, setValue] = useState("");
  const [topic, setTopic] = useState("");
  const [encrypted, setEncrypted] = useState(true);
  const [error, setError] = useState<string | null>(null);

  function switchTab(next: typeof tab) {
    setTab(next);
    setValue("");
    setTopic("");
    setError(null);
    setEncrypted(true);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      let roomId: string;
      if (tab === "join") {
        roomId = await joinRoom(value.trim());
      } else if (tab === "dm") {
        roomId = await startDirectMessage(value.trim(), encrypted);
      } else {
        roomId = await createRoom({
          name: value.trim(),
          topic: topic.trim() || undefined,
          encrypted,
        });
      }
      onOpen(roomId);
      onClose();
    } catch (reason) {
      if (reason instanceof JoinRoomFailure) {
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
    ? t("rooms.joinRoom")
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
        {tab === "create" && (
          <>
            <label>
              <span>{t("rooms.topic")}</span>
              <input value={topic} onChange={(event) => setTopic(event.target.value)} placeholder={t("rooms.topicPlaceholder")} />
            </label>
            <label className="check">
              <input type="checkbox" checked={encrypted} onChange={(event) => setEncrypted(event.target.checked)} />
              {" "}{t("rooms.enableE2ee")}
            </label>
          </>
        )}
        {tab === "dm" && (
          <label className="check">
            <input type="checkbox" checked={encrypted} onChange={(event) => setEncrypted(event.target.checked)} />
            {" "}{t("rooms.enableE2ee")}
          </label>
        )}
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
  const [theme, setTheme] = useState(localStorage.getItem("highlife.theme") ?? "system");
  const [displayName, setDisplayName] = useState(() => getOwnDisplayName());
  const [backup, setBackup] = useState<KeyBackupDetails | null>(null);
  const [devices, setDevices] = useState<EncryptionDevice[]>([]);
  const [verification, setVerification] = useState<string | null>(null);
  const [sas, setSas] = useState<SasChallenge | null>(null);
  const [recoveryKeyInput, setRecoveryKeyInput] = useState("");
  const [newRecoveryKey, setNewRecoveryKey] = useState<string | null>(null);
  const [cryptoBusy, setCryptoBusy] = useState(false);
  const [cryptoMessage, setCryptoMessage] = useState<string | null>(null);
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
    refreshCrypto();
  }, [refreshCrypto]);

  function changeTheme(value: string) {
    setTheme(value);
    localStorage.setItem("highlife.theme", value);
    document.documentElement.dataset.theme = value;
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
    <Modal title={t("settings.title")} onClose={onClose}>
      <div className="settings-section">
        <p className="eyebrow">{t("settings.profile")}</p>
        <form className="inline-form" onSubmit={(event) => { event.preventDefault(); void updateProfile(displayName); }}>
          <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder={t("settings.displayNamePlaceholder")} aria-label={t("settings.displayName")} />
          <button className="button" type="submit">{t("settings.save")}</button>
        </form>
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
      <details className="settings-section settings-advanced">
        <summary>
          <span className="eyebrow">{t("settings.encryption")}</span>
          <span className="muted small">{t("settings.encryptionSummary")}</span>
        </summary>
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
          </div>
        )}
        {cryptoMessage && <p className="muted small" role="status">{cryptoMessage}</p>}
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
              </article>
            ))
          )}
        </div>
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
      </details>
      <button className="button danger" type="button" onClick={() => void logout()}>{t("settings.signOut")}</button>
    </Modal>
  );
}

export function RoomDetails({ room, onClose, onLeft }: { room: RoomListItem; onClose: () => void; onLeft: () => void }) {
  const { t } = useI18n();
  const [userId, setUserId] = useState("");
  const [spaceId, setSpaceId] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [members, setMembers] = useState<RoomMemberInfo[]>([]);
  const spaces = listSpaces().filter((space) => space.roomId !== room.roomId);

  useEffect(() => {
    setMembers(getJoinedMembers(room.roomId));
  }, [room.roomId]);

  return (
    <Modal title={room.name} onClose={onClose}>
      {room.topic && <p>{room.topic}</p>}
      <dl className="status-list">
        <div><dt>{t("rooms.roomId")}</dt><dd>{room.roomId}</dd></div>
        <div><dt>{t("rooms.encryption")}</dt><dd>{room.isEncrypted ? t("rooms.enabled") : t("rooms.off")}</dd></div>
      </dl>
      <div className="settings-section">
        <p className="eyebrow">{t("rooms.members")}</p>
        <div className="member-list" data-testid="member-list">
          {members.length === 0 && <p className="muted small">{t("rooms.noMembers")}</p>}
          {members.map((member) => (
            <article key={member.userId}>
              <div>
                <strong>{member.displayName}</strong>
                <small>{member.userId}</small>
              </div>
              <span>{t("rooms.power", { level: member.powerLevel })}</span>
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
  roomId: string;
  onClose: (eventId?: string) => void;
  onJump?: (eventId: string) => void;
}) {
  const { t } = useI18n();
  const [query, setQuery] = useState("");
  const [hits, setHits] = useState<SearchHit[]>([]);
  const [busy, setBusy] = useState(false);
  const [searched, setSearched] = useState(false);
  async function run(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      setHits(await searchMessages(query, roomId));
      setSearched(true);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title={t("search.title")} onClose={() => onClose()}>
      <form className="inline-form" onSubmit={run}>
        <input autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder={t("search.placeholder")} />
        <button className="button">{busy ? t("search.busy") : t("search.action")}</button>
      </form>
      <div className="search-results">
        {!searched && !busy && <p className="muted small">{t("search.emptyHint")}</p>}
        {searched && hits.length === 0 && <p className="muted small">{t("search.noResults")}</p>}
        {hits.map((hit) => (
          <button
            key={hit.eventId}
            type="button"
            className="search-hit"
            onClick={() => {
              onJump?.(hit.eventId);
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

export function CallSurface({ roomId, onClose }: { roomId: string; onClose: () => void }) {
  const { t } = useI18n();
  const capability = getCallCapability(roomId);
  const base = import.meta.env.VITE_ELEMENT_CALL_URL as string | undefined;
  const configuredParent = import.meta.env.VITE_ELEMENT_CALL_PARENT_URL as string | undefined;
  const identity = getSessionIdentity();
  const frame = useRef<HTMLIFrameElement>(null);
  const [widgetReady, setWidgetReady] = useState(false);
  const [slowLoad, setSlowLoad] = useState(false);
  const url = useMemo(() => buildElementCallUrl({
    baseUrl: base,
    parentUrl: configuredParent,
    roomId,
    identity,
    allowHttpInDev: import.meta.env.DEV,
    windowOrigin: window.location.origin,
  }), [base, configuredParent, identity, roomId]);
  const targetOrigin = useMemo(() => {
    if (!url) return null;
    try { return new URL(url).origin; } catch { return null; }
  }, [url]);

  useEffect(() => {
    if (!url || !targetOrigin) return;
    setWidgetReady(false);
    setSlowLoad(false);
    const timer = window.setTimeout(() => setSlowLoad(true), 8000);
    const detach = attachElementCallWidgetHost({
      widgetId: callWidgetId(roomId),
      roomId,
      targetOrigin,
      getContentWindow: () => frame.current?.contentWindow,
      sendEvent: sendWidgetRoomEvent,
      getOpenIdToken: fetchOpenIdToken,
      onCapabilityChange: () => {
        setWidgetReady(true);
        window.clearTimeout(timer);
      },
    });
    return () => {
      window.clearTimeout(timer);
      detach();
    };
  }, [roomId, targetOrigin, url]);

  return (
    <Modal title={t("call.title")} onClose={onClose} wide>
      {!capability.available ? (
        <div className="capability-error">
          <strong>{t("call.unavailableTitle")}</strong>
          <p>{capability.reason}</p>
        </div>
      ) : !url ? (
        <div className="capability-error">
          <strong>{t("call.configTitle")}</strong>
          <p>{t("call.configBody", { state: capability.active ? t("call.active") : t("call.idle") })}</p>
        </div>
      ) : (
        <>
          <div className="call-toolbar">
            <p className="call-notice">
              {t("call.notice")}
              {widgetReady ? ` · ${t("call.widgetReady")}` : slowLoad ? ` · ${t("call.stillLoading")}` : ""}
            </p>
            <a className="button" href={url} target="_blank" rel="noreferrer">
              {t("call.openExternal")}
            </a>
          </div>
          <iframe
            ref={frame}
            className="call-frame"
            src={url}
            title={t("call.frameTitle")}
            allow="camera; microphone; fullscreen; display-capture"
            sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
          />
        </>
      )}
    </Modal>
  );
}

export function ThreadSurface({ roomId, root, onClose }: {
  roomId: string;
  root: TimelineItem;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const [items, setItems] = useState<TimelineItem[]>([]);
  const [text, setText] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setItems(await loadThread(roomId, root.threadRootId ?? root.eventId));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("thread.failed"));
    } finally {
      setLoading(false);
    }
  }, [roomId, root.eventId, root.threadRootId, t]);

  useEffect(() => { void refresh(); }, [refresh]);

  return (
    <Modal title={t("thread.title")} onClose={onClose}>
      <div className="thread-list">
        {loading && <p className="muted">{t("thread.loading")}</p>}
        {error && <p className="error" role="alert">{error}</p>}
        {items.map((item) => (
          <article key={item.eventId}>
            <strong>{item.senderName}</strong>
            <p>{item.body}</p>
            <time>{new Date(item.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</time>
          </article>
        ))}
        {!loading && items.length === 0 && <p className="muted">{t("thread.empty")}</p>}
      </div>
      <button className="button" onClick={() => void paginateThread(roomId, root.threadRootId ?? root.eventId).then(refresh)}>{t("thread.loadEarlier")}</button>
      <form className="inline-form" onSubmit={(event) => {
        event.preventDefault();
        const body = text.trim();
        if (!body) return;
        void sendMessage(roomId, body, { threadRootId: root.threadRootId ?? root.eventId }).then(() => {
          setText("");
          return refresh();
        });
      }}>
        <input value={text} onChange={(event) => setText(event.target.value)} placeholder={t("thread.replyPlaceholder")} aria-label={t("thread.replyLabel")} />
        <button className="button primary">{t("thread.send")}</button>
      </form>
    </Modal>
  );
}

export function MiniAppSurface({ card, item, onClose }: { card: MiniAppCard; item: TimelineItem; onClose: () => void }) {
  const { t } = useI18n();
  const frame = useRef<HTMLIFrameElement>(null);
  const targetOrigin = useMemo(() => new URL(card.url).origin, [card.url]);
  useEffect(() => {
    function receive(event: MessageEvent) {
      if (event.source !== frame.current?.contentWindow || event.origin !== targetOrigin || typeof event.data !== "object" || !event.data) return;
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
        }, targetOrigin);
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
          <iframe
            ref={frame}
            className="mini-frame"
            src={card.url}
            title={card.title}
            sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
            allow="clipboard-write; fullscreen"
          />
        </div>
      </section>
    </div>
  );
}
