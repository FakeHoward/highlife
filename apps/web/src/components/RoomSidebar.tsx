import type { RoomListItem, SpaceSummary } from "@highlife/ui-contracts";
import { useI18n } from "../i18n";
import { IconFolderPlus, IconLock, IconPlus, IconSearch, IconSettings } from "./Icons";
import { Avatar } from "./Avatar";

interface Props {
  rooms: RoomListItem[];
  activeId: string | null;
  query: string;
  onQuery: (value: string) => void;
  onSelect: (roomId: string) => void;
  onNew: () => void;
  onNewSpace: () => void;
  onSettings: () => void;
  spaces?: SpaceSummary[];
  selectedSpaceId?: string | null;
  onSelectSpace?: (spaceId: string | null) => void;
}

export function RoomSidebar({
  rooms,
  activeId,
  query,
  onQuery,
  onSelect,
  onNew,
  onNewSpace,
  onSettings,
  spaces = [],
  selectedSpaceId = null,
  onSelectSpace,
}: Props) {
  const { t } = useI18n();
  const selectedSpace = spaces.find((space) => space.roomId === selectedSpaceId) ?? null;
  return (
    <>
      {onSelectSpace && (
        <nav className="space-rail" aria-label={t("sidebar.spaces")}>
          <button
            type="button"
            className={`space-rail-button all-spaces ${selectedSpaceId === null ? "active" : ""}`}
            onClick={() => onSelectSpace(null)}
            aria-label={t("sidebar.allRooms")}
            aria-pressed={selectedSpaceId === null}
            title={t("sidebar.allRooms")}
          >
            H
          </button>
          <div className="space-rail-list">
            {spaces.map((space) => (
              <button
                key={space.roomId}
                type="button"
                className={`space-rail-button ${selectedSpaceId === space.roomId ? "active" : ""}`}
                onClick={() => onSelectSpace(space.roomId)}
                aria-label={space.name}
                aria-pressed={selectedSpaceId === space.roomId}
                title={space.name}
              >
                <Avatar id={space.roomId} name={space.name} src={space.avatarUrl} size="small" />
              </button>
            ))}
          </div>
          <button
            type="button"
            className="space-rail-button"
            onClick={onNewSpace}
            aria-label={t("spaces.createTitle")}
            title={t("spaces.createTitle")}
          >
            <IconFolderPlus />
          </button>
        </nav>
      )}
      <aside className={`sidebar ${activeId ? "has-room" : ""}`} aria-label={t("sidebar.rooms")}>
      <header className="sidebar-head">
        <div className="brand-lockup compact">
          <span className="brand-symbol" aria-hidden="true">H</span>
          <strong>HighLife</strong>
        </div>
        <div className="head-actions">
          <button className="icon-button" type="button" onClick={onNew} aria-label={t("sidebar.createOrJoin")} title={t("sidebar.createOrJoin")}>
            <IconPlus />
          </button>
          <button className="icon-button" type="button" onClick={onSettings} aria-label={t("sidebar.settings")}>
            <IconSettings />
          </button>
        </div>
      </header>
      {selectedSpace && (
        <section className="selected-space-panel" role="complementary" aria-label={selectedSpace.name}>
          <Avatar
            id={selectedSpace.roomId}
            name={selectedSpace.name}
            src={selectedSpace.avatarUrl}
            size="small"
          />
          <div>
            <strong>{selectedSpace.name}</strong>
            <span>{selectedSpace.topic ?? t("spaces.selectedHint")}</span>
          </div>
          <button
            className="icon-button"
            type="button"
            onClick={() => onSelectSpace?.(null)}
            aria-label={t("common.closeNamed", { title: selectedSpace.name })}
          >
            ×
          </button>
        </section>
      )}
      <label className="search-field">
        <IconSearch />
        <input
          value={query}
          onChange={(event) => onQuery(event.target.value)}
          placeholder={t("sidebar.search")}
          aria-label={t("sidebar.search")}
        />
      </label>
      <nav className="room-list">
        {rooms.length === 0 && (
          <div className="empty-small">
            <strong>{t("sidebar.emptyTitle")}</strong>
            <span>{t("sidebar.emptyHint")}</span>
          </div>
        )}
        {rooms.map((room) => (
          <button
            key={room.roomId}
            type="button"
            className={`room-row ${activeId === room.roomId ? "active" : ""} ${room.isSpace ? "is-space" : ""}`}
            onClick={() => onSelect(room.roomId)}
            aria-current={activeId === room.roomId ? "page" : undefined}
          >
            <Avatar id={room.roomId} name={room.name} src={room.avatarUrl} />
            <span className="room-copy">
              <span className="room-title">
                <strong>{room.name}</strong>
                <time>{room.lastActive ? new Date(room.lastActive).toLocaleDateString([], { month: "short", day: "numeric" }) : ""}</time>
              </span>
              <span className="room-preview">
                {room.isEncrypted && (
                  <span className="enc-mark" aria-label={t("sidebar.encrypted")}>
                    <IconLock />
                  </span>
                )}
                {room.membership === "invite" ? t("sidebar.invitation") : (room.lastMessage ?? t("sidebar.noMessages"))}
              </span>
            </span>
            {room.unread > 0 && <span className={`unread ${room.highlight ? "hot" : ""}`}>{room.unread}</span>}
          </button>
        ))}
      </nav>
      </aside>
    </>
  );
}
