import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import type { TimelineItem } from "@highlife/ui-contracts";
import { useI18n } from "../i18n";
import { useHistoryState, useMatrix, useRooms, useTimeline } from "../matrix/hooks";
import {
  acceptInvite,
  dismissToast,
  forwardMessage,
  getCallCapability,
  getIncomingVerification,
  getOwnAvatarUrl,
  getOwnDisplayName,
  getOwnReadUpTo,
  getPeerUserId,
  getPinnedEventIds,
  getSessionIdentity,
  getTypingUsers,
  getUserPresence,
  leaveMatrixRtc,
  listSpaces,
  markRead,
  paginateRoomHistory,
  paginateThreadHistory,
  rejectInvite,
  respondToIncomingVerification,
  requestUserVerification,
  setRoomMuted,
  showLocalToast,
  scrubHostCapabilitiesForRoom,
  startOutgoingCall,
  startMatrixRtc,
  subscribeIncomingVerification,
  togglePinnedEvent,
  threadTimeline,
  markThreadRead,
  fetchRoomSummary,
  unsubscribeFromThread,
  type SasChallenge,
} from "../matrix/service";
import type { RoomSummary } from "../matrix/specFeatures";
import { firstUnreadEventId, formatPresenceLabel } from "../matrix/messengerExtras";
import { checkWebUpdate, WEB_APP_VERSION } from "../matrix/updateCheck";
import { classifyDirectCallFailure, DIRECT_CALL_CRYPTO_UNAVAILABLE, DIRECT_CALL_MIC_BLOCKED } from "../matrix/directCallErrors";
import { parseAiomatrixPayload, type MiniAppCard } from "../protocol/aiomatrix";
import { Composer, type ComposeMode } from "./Composer";
import { Avatar } from "./Avatar";
import { IconBack, IconCall, IconMore, IconSearch, IconVideo } from "./Icons";
import { MessageTimeline } from "./MessageTimeline";
import { RoomSidebar } from "./RoomSidebar";
import {
  CreateSpace,
  CreatePollSurface,
  GroupCallSurface,
  MiniAppSurface,
  RoomActions,
  RoomDetails,
  SearchSurface,
  Settings,
  UserProfile,
  ForwardPicker,
} from "./Surfaces";

type Surface =
  | "rooms"
  | "createSpace"
  | "settings"
  | "details"
  | "search"
  | "poll"
  | "roomMenu"
  | "call"
  | { miniApp: MiniAppCard; item: TimelineItem }
  | null;

function roomIdFromLocation(): string | null {
  try {
    const id = new URLSearchParams(window.location.search).get("room");
    return id?.startsWith("!") ? id : null;
  } catch {
    return null;
  }
}

export function Workspace() {
  const { t } = useI18n();
  const matrix = useMatrix();
  const [query, setQuery] = useState("");
  const rooms = useRooms(query);
  const allRooms = useRooms("");
  const [activeId, setActiveId] = useState<string | null>(() => roomIdFromLocation());
  const [surface, setSurface] = useState<Surface>(null);
  const [mode, setMode] = useState<ComposeMode>(null);
  const [highlightEventId, setHighlightEventId] = useState<string | null>(null);
  const [profileUserId, setProfileUserId] = useState<string | null>(null);
  const [forwardEventId, setForwardEventId] = useState<string | null>(null);
  const [unreadEventId, setUnreadEventId] = useState<string | null>(null);
  const [threadRootId, setThreadRootId] = useState<string | null>(null);
  const [inviteSummary, setInviteSummary] = useState<RoomSummary | null>(null);
  const unreadCapturedFor = useRef<string | null>(null);
  const [selectedSpaceId, setSelectedSpaceId] = useState<string | null>(null);
  const [sas, setSas] = useState<SasChallenge | null>(null);
  const [verificationState, setVerificationState] = useState<string | null>(null);
  const [updateNotice, setUpdateNotice] = useState<{ version: string; url: string } | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const timeline = useTimeline(activeId);
  const history = useHistoryState(activeId);
  const threadHistory = useHistoryState(activeId, threadRootId);
  const spaces = useMemo(() => listSpaces(), [matrix.version]);
  const incoming = useSyncExternalStore(subscribeIncomingVerification, getIncomingVerification, () => null);

  useEffect(() => {
    function onPopState() {
      setActiveId(roomIdFromLocation());
    }
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  useEffect(() => {
    const source = navigator.serviceWorker;
    if (!source) return;
    function onMessage(event: MessageEvent) {
      const data = event.data as { type?: string; roomId?: string } | null;
      if (data?.type === "open-room" && typeof data.roomId === "string" && data.roomId.startsWith("!")) {
        setActiveId(data.roomId);
      }
    }
    source.addEventListener("message", onMessage);
    return () => source.removeEventListener("message", onMessage);
  }, []);

  const filteredRooms = useMemo(() => {
    const withoutSpaces = rooms.filter((room) => !room.isSpace);
    if (!selectedSpaceId) return withoutSpaces;
    const space = spaces.find((item) => item.roomId === selectedSpaceId);
    const children = new Set(space?.childRoomIds ?? []);
    return withoutSpaces.filter(
      (room) => room.spaceParentId === selectedSpaceId || children.has(room.roomId),
    );
  }, [rooms, selectedSpaceId, spaces]);

  const activeRoom = filteredRooms.find((room) => room.roomId === activeId)
    ?? rooms.find((room) => room.roomId === activeId)
    ?? allRooms.find((room) => room.roomId === activeId)
    ?? null;
  const callCapability = activeId ? getCallCapability(activeId) : null;
  const typingUsers = activeId ? getTypingUsers(activeId) : [];
  const typingLabel = typingUsers.length === 0
    ? null
    : typingUsers.length === 1
      ? t("chat.typingOne", { name: typingUsers[0]! })
      : t("chat.typingMany", { names: typingUsers.join(", ") });
  const peerId = activeRoom?.isDirect && activeId ? getPeerUserId(activeId) : null;
  const peerPresence = peerId ? getUserPresence(peerId) : null;
  const presenceLabel = peerPresence
    ? formatPresenceLabel(peerPresence.presence, peerPresence.lastActiveAgo, peerPresence.currentlyActive, {
        online: t("profile.online"),
        away: t("profile.away"),
        offline: t("user.offline"),
        lastSeen: (when) => t("user.lastSeen", { when }),
      })
    : null;
  const pinnedIds = activeId ? getPinnedEventIds(activeId) : [];
  const pinnedItem = pinnedIds.length
    ? [...timeline].reverse().find((item) => pinnedIds.includes(item.eventId)) ?? null
    : null;

  useEffect(() => {
    if (!activeId) {
      unreadCapturedFor.current = null;
      setUnreadEventId(null);
      return;
    }
    if (unreadCapturedFor.current !== activeId && timeline.length > 0) {
      unreadCapturedFor.current = activeId;
      setUnreadEventId(
        firstUnreadEventId(timeline.map((item) => item.eventId), getOwnReadUpTo(activeId)),
      );
    }
    void markRead(activeId).catch(() => undefined);
  }, [activeId, timeline.length]);

  useEffect(() => {
    setThreadRootId(null);
    setMode(null);
  }, [activeId]);

  useEffect(() => {
    if (!activeId || !threadRootId) return;
    const items = threadTimeline(activeId, threadRootId);
    const last = items[items.length - 1];
    if (last) void markThreadRead(activeId, last.eventId).catch(() => undefined);
  }, [activeId, threadRootId, matrix.version]);

  useEffect(() => {
    if (!activeRoom || activeRoom.membership !== "invite") {
      setInviteSummary(null);
      return;
    }
    let cancelled = false;
    void fetchRoomSummary(activeRoom.roomId)
      .then((summary) => {
        if (!cancelled) setInviteSummary(summary);
      })
      .catch(() => {
        if (!cancelled) setInviteSummary(null);
      });
    return () => {
      cancelled = true;
    };
  }, [activeRoom?.roomId, activeRoom?.membership]);

  useEffect(() => {
    const toast = matrix.toast;
    if (!toast) return;
    const timer = window.setTimeout(() => dismissToast(toast.id), toast.alert ? 6000 : 3200);
    return () => window.clearTimeout(timer);
  }, [matrix.toast]);

  useEffect(() => {
    let cancelled = false;
    void checkWebUpdate(WEB_APP_VERSION).then((result) => {
      if (cancelled || !result.updateAvailable || !result.latest) return;
      setUpdateNotice({
        version: result.latest.version,
        url: result.assetUrl ?? "https://testhighlife.strangled.net/client/latest.json",
      });
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (surface !== "roomMenu") return;
    function onPointer(event: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setSurface(null);
      }
    }
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") setSurface(null);
    }
    document.addEventListener("mousedown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [surface]);

  // Notify about new MiniApp cards without stealing focus (tap the card to open).
  const seenMiniApps = useRef(new Set<string>());
  const miniAppRoom = useRef<string | null>(null);
  useEffect(() => {
    if (!activeId) return;
    if (miniAppRoom.current !== activeId) {
      miniAppRoom.current = activeId;
      seenMiniApps.current = new Set(
        timeline
          .filter((item) => parseAiomatrixPayload(item.rawContent).miniApp)
          .map((item) => item.eventId),
      );
      return;
    }
    for (let index = timeline.length - 1; index >= 0; index -= 1) {
      const item = timeline[index]!;
      if (item.isOwn || seenMiniApps.current.has(item.eventId)) continue;
      const card = parseAiomatrixPayload(item.rawContent).miniApp;
      if (!card) continue;
      seenMiniApps.current.add(item.eventId);
      showLocalToast(t("timeline.miniAppAvailable", { title: card.title }));
      break;
    }
  }, [activeId, timeline, t]);

  function openRoom(roomId: string) {
    setActiveId(roomId);
    setMode(null);
    setHighlightEventId(null);
    if (surface === "settings") setSurface(null);
    scrubHostCapabilitiesForRoom(roomId);
  }

  return (
    <div className={`workspace ${activeId || surface === "settings" ? "room-open" : ""} ${spaces.length ? "has-rail" : ""}`}>
      <RoomSidebar
        rooms={filteredRooms}
        activeId={activeId}
        query={query}
        onQuery={setQuery}
        onSelect={openRoom}
        onNew={() => setSurface("rooms")}
        onNewSpace={() => setSurface("createSpace")}
        onSettings={() => setSurface("settings")}
        onProfile={() => setSurface("settings")}
        profileId={getSessionIdentity()?.userId ?? ""}
        profileName={getOwnDisplayName() || getSessionIdentity()?.userId || "HighLife"}
        profileAvatar={getOwnAvatarUrl()}
        spaces={spaces}
        selectedSpaceId={selectedSpaceId}
        onSelectSpace={setSelectedSpaceId}
      />
      <main className="chat-panel">
        {surface === "settings" ? (
          <Settings onClose={() => setSurface(null)} />
        ) : (
        <>
        {updateNotice && (
          <div className="update-banner" role="status">
            <span>{t("update.available", { version: updateNotice.version })}</span>
            <a className="text-button" href={updateNotice.url} target="_blank" rel="noreferrer">{t("update.open")}</a>
            <button type="button" className="icon-button" onClick={() => setUpdateNotice(null)} aria-label={t("common.close")}>×</button>
          </div>
        )}
        {incoming && (
          <div className="verification-banner" role="status">
            <div>
              <strong>{t("verification.banner")}</strong>
              <p className="muted small">{t("settings.fromDevice", {
                user: incoming.otherUserId,
                device: incoming.otherDeviceId ?? "—",
              })}</p>
              {verificationState && <p className="muted small">{verificationState}</p>}
            </div>
            <div className="verification-banner-actions">
              <button
                className="button primary"
                type="button"
                onClick={() => {
                  setSas(null);
                  void respondToIncomingVerification(true, setSas, setVerificationState)
                    .catch((error: Error) => setVerificationState(error.message));
                }}
              >
                {t("verification.accept")}
              </button>
              <button
                className="button danger"
                type="button"
                onClick={() => {
                  void respondToIncomingVerification(false, setSas, setVerificationState)
                    .catch((error: Error) => setVerificationState(error.message));
                }}
              >
                {t("verification.decline")}
              </button>
            </div>
          </div>
        )}
        {sas && (
          <div className="verification-banner sas-inline" role="dialog" aria-label={t("settings.compareDevices")}>
            <strong>{t("settings.compareDevices")}</strong>
            {sas.emoji.length > 0 ? (
              <div className="sas-emoji">
                {sas.emoji.map(([emoji, name]) => (
                  <span key={name} title={name}>{emoji}<small>{name}</small></span>
                ))}
              </div>
            ) : (
              <p className="sas-decimal">{sas.decimal?.join(" · ")}</p>
            )}
            <div className="verification-banner-actions">
              <button
                className="button primary"
                type="button"
                onClick={() => void sas.confirm().then(() => {
                  setVerificationState(t("settings.deviceVerified"));
                  setSas(null);
                })}
              >
                {t("settings.theyMatch")}
              </button>
              <button
                className="button danger"
                type="button"
                onClick={() => {
                  sas.mismatch();
                  setSas(null);
                }}
              >
                {t("settings.theyDoNotMatch")}
              </button>
            </div>
          </div>
        )}
        {matrix.connection !== "online" && (
          <div className={`connection ${matrix.connection}`} role="status">
            {matrix.connection === "offline"
              ? t("chat.offline")
              : matrix.connection === "error"
                ? (matrix.error ?? t("chat.syncStopped"))
                : t("chat.syncing")}
          </div>
        )}
        {matrix.connection === "online" && matrix.error && (
          <div className="connection error" role="alert">{matrix.error}</div>
        )}
        {matrix.toast && (
          <div
            className={`host-toast${matrix.toast.alert ? " is-alert" : ""}`}
            role="status"
            onClick={() => dismissToast(matrix.toast!.id)}
          >
            {matrix.toast.text}
          </div>
        )}
        {activeRoom ? (
          <>
            <header className="chat-head">
              <button className="icon-button mobile-back" type="button" onClick={() => setActiveId(null)} aria-label={t("chat.back")}>
                <IconBack />
              </button>
              <Avatar
                className="chat-avatar"
                id={activeRoom.roomId}
                name={activeRoom.name}
                src={activeRoom.avatarUrl}
                size="small"
              />
              <button className="room-heading" type="button" onClick={() => setSurface("details")}>
                <strong>{activeRoom.name}</strong>
                <span>
                  {typingLabel
                    ?? presenceLabel
                    ?? (activeRoom.membership === "invite"
                      ? t("chat.invitation")
                      : activeRoom.isEncrypted
                        ? t("chat.encryptedRoom")
                        : activeRoom.topic ?? t("chat.matrixRoom"))}
                </span>
              </button>
              <div className="head-actions">
                <button className="icon-button head-search" type="button" onClick={() => setSurface("search")} aria-label={t("chat.search")}>
                  <IconSearch />
                </button>
                {callCapability?.available && (
                  <>
                  <button
                    className="icon-button head-call"
                    type="button"
                    onClick={() => {
                      void startOutgoingCall(activeRoom.roomId).catch((error: Error) => {
                        const classified = classifyDirectCallFailure(error);
                        showLocalToast(
                          classified === DIRECT_CALL_MIC_BLOCKED
                            ? t("call.micBlocked")
                            : classified === DIRECT_CALL_CRYPTO_UNAVAILABLE
                              ? t("call.cryptoUnavailable")
                              : error.message,
                          true,
                        );
                        if (!activeRoom.isDirect) {
                          void leaveMatrixRtc();
                          setSurface("call");
                        }
                      });
                    }}
                    aria-label={t("chat.call")}
                    title={callCapability.reason}
                  >
                    <IconCall />
                  </button>
                  {activeRoom.isDirect && (
                    <button
                      className="icon-button head-call"
                      type="button"
                      onClick={() => {
                        void startOutgoingCall(activeRoom.roomId, { video: true }).catch((error: Error) => {
                          showLocalToast(error.message, true);
                        });
                      }}
                      aria-label={t("call.cameraOn")}
                    >
                      <IconVideo />
                    </button>
                  )}
                  </>
                )}
                <button
                  className="icon-button head-details"
                  type="button"
                  onClick={() => setSurface((current) => current === "roomMenu" ? null : "roomMenu")}
                  aria-label={t("chat.details")}
                  aria-expanded={surface === "roomMenu"}
                >
                  <IconMore />
                </button>
                {surface === "roomMenu" && (
                  <div className="room-menu" role="menu" ref={menuRef}>
                    <button type="button" role="menuitem" className="room-menu-compact" onClick={() => setSurface("search")}>
                      {t("chat.search")}
                    </button>
                    {callCapability?.available && (
                      <button
                        type="button"
                        role="menuitem"
                        className="room-menu-compact"
                        onClick={() => {
                          setSurface(null);
                          void startOutgoingCall(activeRoom.roomId).catch((error: Error) => {
                            const classified = classifyDirectCallFailure(error);
                            showLocalToast(
                              classified === DIRECT_CALL_MIC_BLOCKED
                                ? t("call.micBlocked")
                                : classified === DIRECT_CALL_CRYPTO_UNAVAILABLE
                                  ? t("call.cryptoUnavailable")
                                  : error.message,
                              true,
                            );
                            if (!activeRoom.isDirect) {
                              void leaveMatrixRtc();
                              setSurface("call");
                            }
                          });
                        }}
                      >
                        {t("chat.call")}
                      </button>
                    )}
                    <button type="button" role="menuitem" onClick={() => setSurface("poll")}>
                      {t("composer.createPoll")}
                    </button>
                    <button
                      type="button"
                      role="menuitem"
                      onClick={() => {
                        void setRoomMuted(activeRoom.roomId, !activeRoom.muted);
                        setSurface(null);
                      }}
                    >
                      {activeRoom.muted ? t("chat.unmute") : t("chat.mute")}
                    </button>
                    <button type="button" role="menuitem" onClick={() => setSurface("details")}>
                      {t("chat.details")}
                    </button>
                  </div>
                )}
              </div>
            </header>
            {pinnedIds.length > 0 && activeRoom.membership === "join" && (
              pinnedIds.length === 1 ? (
                <button
                  type="button"
                  className="pin-banner"
                  onClick={() => pinnedItem && setHighlightEventId(pinnedItem.eventId)}
                >
                  <span>{t("chat.pinned")}</span>
                  <strong>{pinnedItem?.body || t("chat.noPinnedBody")}</strong>
                </button>
              ) : (
                <details className="pin-banner pin-menu">
                  <summary>{t("chat.pinned")} · {pinnedIds.length}</summary>
                  {pinnedIds.map((id) => {
                    const item = timeline.find((entry) => entry.eventId === id);
                    return (
                      <button key={id} type="button" onClick={() => setHighlightEventId(id)}>
                        {item?.body || t("chat.noPinnedBody")}
                      </button>
                    );
                  })}
                </details>
              )
            )}
            {callCapability?.groupActive && activeRoom.membership === "join" && (
              <div className="call-banner" role="status">
                <span>{t("call.bannerActive")}</span>
                <button className="button" onClick={() => {
                  void startMatrixRtc(activeRoom.roomId).catch((error: Error) => {
                    showLocalToast(error.message, true);
                    void leaveMatrixRtc();
                    setSurface("call");
                  });
                }}>{t("call.join")}</button>
              </div>
            )}
            {activeRoom.membership === "invite" ? (
              <div className="timeline-empty invite-state">
                <strong>{inviteSummary?.name ?? t("chat.inviteTitle", { name: activeRoom.name })}</strong>
                <p>{inviteSummary?.topic || t("chat.inviteBody")}</p>
                {inviteSummary?.numJoinedMembers != null && (
                  <p className="muted small">{t("rooms.membersCount", { count: inviteSummary.numJoinedMembers })}</p>
                )}
                <div>
                  <button className="button primary" onClick={() => void acceptInvite(activeRoom.roomId)}>{t("chat.acceptInvite")}</button>
                  <button className="button danger" onClick={() => void rejectInvite(activeRoom.roomId).then(() => setActiveId(null))}>{t("chat.rejectInvite")}</button>
                </div>
              </div>
            ) : (
              <>
                <MessageTimeline
                  items={timeline}
                  roomId={activeRoom.roomId}
                  onComposeMode={threadRootId ? () => undefined : setMode}
                  onMiniApp={(miniApp, item) => setSurface({ miniApp, item })}
                  history={history}
                  onLoadOlder={() => paginateRoomHistory(activeRoom.roomId)}
                  highlightEventId={highlightEventId}
                  unreadEventId={unreadEventId}
                  pinnedIds={pinnedIds}
                  onPin={(item) => void togglePinnedEvent(activeRoom.roomId, item.eventId)}
                  onForward={(item) => setForwardEventId(item.eventId)}
                  onOpenProfile={(item) => setProfileUserId(item.senderId)}
                  onJumpToEvent={setHighlightEventId}
                  onOpenThread={(item) => {
                    setMode(null);
                    setThreadRootId(item.threadRootId ?? item.eventId);
                  }}
                />
                <Composer roomId={activeRoom.roomId} mode={threadRootId ? null : mode} onMode={setMode} />
                {threadRootId && (
                  <aside className="thread-panel" aria-label={t("timeline.thread")}>
                    <header className="thread-panel-head">
                      <strong>{t("timeline.thread")}</strong>
                      <div className="thread-panel-actions">
                        <button
                          type="button"
                          className="text-button"
                          onClick={() => void unsubscribeFromThread(activeRoom.roomId, threadRootId)}
                        >
                          {t("timeline.muteThread")}
                        </button>
                        <button
                          type="button"
                          className="icon-button"
                          onClick={() => setThreadRootId(null)}
                          aria-label={t("chat.threadClose")}
                        >
                          ×
                        </button>
                      </div>
                    </header>
                    <MessageTimeline
                      items={threadTimeline(activeRoom.roomId, threadRootId)}
                      roomId={activeRoom.roomId}
                      onComposeMode={setMode}
                      onMiniApp={(miniApp, item) => setSurface({ miniApp, item })}
                      history={threadHistory}
                      onLoadOlder={() => paginateThreadHistory(activeRoom.roomId, threadRootId)}
                      highlightEventId={highlightEventId}
                      onJumpToEvent={setHighlightEventId}
                      onOpenProfile={(item) => setProfileUserId(item.senderId)}
                      onForward={(item) => setForwardEventId(item.eventId)}
                      onPin={(item) => void togglePinnedEvent(activeRoom.roomId, item.eventId)}
                    />
                    <Composer
                      roomId={activeRoom.roomId}
                      mode={mode}
                      onMode={setMode}
                      threadRootId={threadRootId}
                    />
                  </aside>
                )}
              </>
            )}
          </>
        ) : (
          <div className="welcome">
            <span className="welcome-glyph" aria-hidden="true">H</span>
            <h1>{t("chat.welcomeTitle")}</h1>
            <p>{t("chat.welcomeBody")}</p>
            <button className="button primary" onClick={() => setSurface("rooms")}>{t("chat.findRoom")}</button>
          </div>
        )}
        </>
        )}
      </main>
      {surface === "rooms" && <RoomActions onClose={() => setSurface(null)} onOpen={openRoom} />}
      {surface === "createSpace" && (
        <CreateSpace
          onClose={() => setSurface(null)}
          onCreated={(spaceId) => {
            setSelectedSpaceId(spaceId);
            setSurface(null);
          }}
        />
      )}
      {surface === "details" && activeRoom && (
        <RoomDetails
          room={activeRoom}
          onClose={() => setSurface(null)}
          onLeft={() => { setSurface(null); setActiveId(null); }}
          onJump={(eventId) => {
            setHighlightEventId(eventId);
            setSurface(null);
          }}
          onOpenUser={(userId) => {
            setProfileUserId(userId);
            setSurface(null);
          }}
        />
      )}
      {surface === "search" && (
        <SearchSurface
          roomId={activeId ?? undefined}
          onJump={(eventId, roomId) => {
            if (roomId && roomId !== activeId) openRoom(roomId);
            setHighlightEventId(eventId);
          }}
          onClose={(eventId) => {
            if (eventId) setHighlightEventId(eventId);
            setSurface(null);
          }}
        />
      )}
      {surface === "poll" && activeId && <CreatePollSurface roomId={activeId} onClose={() => setSurface(null)} />}
      {surface === "call" && activeId && <GroupCallSurface roomId={activeId} onClose={() => setSurface(null)} />}
      {surface && typeof surface === "object" && "miniApp" in surface && <MiniAppSurface card={surface.miniApp} item={surface.item} onClose={() => setSurface(null)} />}
      {profileUserId && (
        <UserProfile
          userId={profileUserId}
          onClose={() => setProfileUserId(null)}
          onOpenedDm={(roomId) => {
            setProfileUserId(null);
            openRoom(roomId);
          }}
          onVerify={(userId) => {
            void requestUserVerification(userId, setSas, setVerificationState).catch((error: Error) => {
              showLocalToast(error.message, true);
            });
          }}
        />
      )}
      {forwardEventId && activeId && (
        <ForwardPicker
          rooms={allRooms.filter((room) => !room.isSpace && room.membership === "join")}
          onClose={() => setForwardEventId(null)}
          onPick={(roomId) => {
            void forwardMessage(activeId, forwardEventId, roomId)
              .then(() => {
                setForwardEventId(null);
                openRoom(roomId);
              })
              .catch((error: Error) => showLocalToast(error.message, true));
          }}
        />
      )}
    </div>
  );
}
