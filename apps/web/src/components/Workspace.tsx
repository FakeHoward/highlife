import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import type { TimelineItem } from "@highlife/ui-contracts";
import { useI18n } from "../i18n";
import { useHistoryState, useMatrix, useRooms, useTimeline } from "../matrix/hooks";
import {
  acceptInvite,
  dismissToast,
  getCallCapability,
  getIncomingVerification,
  getTypingUsers,
  listSpaces,
  markRead,
  paginateRoomHistory,
  rejectInvite,
  respondToIncomingVerification,
  showLocalToast,
  subscribeIncomingVerification,
  type SasChallenge,
} from "../matrix/service";
import { parseAiomatrixPayload, type MiniAppCard } from "../protocol/aiomatrix";
import { Composer, type ComposeMode } from "./Composer";
import { IconBack, IconCall, IconMore, IconSearch } from "./Icons";
import { MessageTimeline } from "./MessageTimeline";
import { RoomSidebar } from "./RoomSidebar";
import {
  CallSurface,
  MiniAppSurface,
  RoomActions,
  RoomDetails,
  SearchSurface,
  Settings,
  ThreadSurface,
} from "./Surfaces";

type Surface =
  | "rooms"
  | "settings"
  | "details"
  | "search"
  | "call"
  | { miniApp: MiniAppCard; item: TimelineItem }
  | { thread: TimelineItem }
  | null;

export function Workspace() {
  const { t } = useI18n();
  const matrix = useMatrix();
  const [query, setQuery] = useState("");
  const rooms = useRooms(query);
  const allRooms = useRooms("");
  const [activeId, setActiveId] = useState<string | null>(null);
  const [surface, setSurface] = useState<Surface>(null);
  const [mode, setMode] = useState<ComposeMode>(null);
  const [highlightEventId, setHighlightEventId] = useState<string | null>(null);
  const [selectedSpaceId, setSelectedSpaceId] = useState<string | null>(null);
  const [sas, setSas] = useState<SasChallenge | null>(null);
  const [verificationState, setVerificationState] = useState<string | null>(null);
  const timeline = useTimeline(activeId);
  const history = useHistoryState(activeId);
  const spaces = useMemo(() => listSpaces(), [matrix.version]);
  const incoming = useSyncExternalStore(subscribeIncomingVerification, getIncomingVerification, () => null);

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

  useEffect(() => {
    if (activeId) void markRead(activeId).catch(() => undefined);
  }, [activeId, timeline.length]);

  useEffect(() => {
    const toast = matrix.toast;
    if (!toast) return;
    const timer = window.setTimeout(() => dismissToast(toast.id), toast.alert ? 6000 : 3200);
    return () => window.clearTimeout(timer);
  }, [matrix.toast]);

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
  }

  return (
    <div className={`workspace ${activeId ? "room-open" : ""}`}>
      <RoomSidebar
        rooms={filteredRooms}
        activeId={activeId}
        query={query}
        onQuery={setQuery}
        onSelect={openRoom}
        onNew={() => setSurface("rooms")}
        onSettings={() => setSurface("settings")}
        spaces={spaces}
        selectedSpaceId={selectedSpaceId}
        onSelectSpace={setSelectedSpaceId}
      />
      <main className="chat-panel">
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
              <div className="chat-avatar" aria-hidden="true">{activeRoom.name.slice(0, 1).toUpperCase()}</div>
              <button className="room-heading" type="button" onClick={() => setSurface("details")}>
                <strong>{activeRoom.name}</strong>
                <span>
                  {typingLabel
                    ?? (activeRoom.membership === "invite"
                      ? t("chat.invitation")
                      : activeRoom.isEncrypted
                        ? t("chat.encryptedRoom")
                        : activeRoom.topic ?? t("chat.matrixRoom"))}
                </span>
              </button>
              <div className="head-actions">
                <button className="icon-button" type="button" onClick={() => setSurface("search")} aria-label={t("chat.search")}>
                  <IconSearch />
                </button>
                {callCapability?.available && (
                  <button
                    className="icon-button"
                    type="button"
                    onClick={() => setSurface("call")}
                    aria-label={t("chat.call")}
                    title={callCapability.reason}
                  >
                    <IconCall />
                  </button>
                )}
                <button className="icon-button" type="button" onClick={() => setSurface("details")} aria-label={t("chat.details")}>
                  <IconMore />
                </button>
              </div>
            </header>
            {callCapability?.active && activeRoom.membership === "join" && (
              <div className="call-banner" role="status">
                <span>{t("call.bannerActive")}</span>
                <button className="button" onClick={() => setSurface("call")}>{t("call.join")}</button>
              </div>
            )}
            {activeRoom.membership === "invite" ? (
              <div className="timeline-empty invite-state">
                <strong>{t("chat.inviteTitle", { name: activeRoom.name })}</strong>
                <p>{t("chat.inviteBody")}</p>
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
                  onComposeMode={setMode}
                  onMiniApp={(miniApp, item) => setSurface({ miniApp, item })}
                  history={history}
                  onLoadOlder={() => paginateRoomHistory(activeRoom.roomId)}
                  onOpenThread={(item) => setSurface({ thread: item })}
                  highlightEventId={highlightEventId}
                />
                <Composer roomId={activeRoom.roomId} mode={mode} onMode={setMode} />
              </>
            )}
          </>
        ) : (
          <div className="welcome">
            <span className="welcome-mark" aria-hidden="true">H</span>
            <h1>{t("chat.welcomeTitle")}</h1>
            <p>{t("chat.welcomeBody")}</p>
            <button className="button primary" onClick={() => setSurface("rooms")}>{t("chat.findRoom")}</button>
          </div>
        )}
      </main>
      {surface === "rooms" && <RoomActions onClose={() => setSurface(null)} onOpen={openRoom} />}
      {surface === "settings" && <Settings onClose={() => setSurface(null)} />}
      {surface === "details" && activeRoom && <RoomDetails room={activeRoom} onClose={() => setSurface(null)} onLeft={() => { setSurface(null); setActiveId(null); }} />}
      {surface === "search" && activeId && (
        <SearchSurface
          roomId={activeId}
          onJump={(eventId) => setHighlightEventId(eventId)}
          onClose={(eventId) => {
            if (eventId) setHighlightEventId(eventId);
            setSurface(null);
          }}
        />
      )}
      {surface === "call" && activeId && <CallSurface roomId={activeId} onClose={() => setSurface(null)} />}
      {surface && typeof surface === "object" && "miniApp" in surface && <MiniAppSurface card={surface.miniApp} item={surface.item} onClose={() => setSurface(null)} />}
      {surface && typeof surface === "object" && "thread" in surface && activeId && <ThreadSurface roomId={activeId} root={surface.thread} onClose={() => setSurface(null)} />}
    </div>
  );
}
