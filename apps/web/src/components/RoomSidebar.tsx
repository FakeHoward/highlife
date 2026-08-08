import type { RoomListItem, SpaceSummary } from "@highlife/ui-contracts";
import { useI18n } from "../i18n";
import { IconLock, IconPlus, IconSearch, IconSettings } from "./Icons";

interface Props {
  rooms: RoomListItem[];
  activeId: string | null;
  query: string;
  onQuery: (value: string) => void;
  onSelect: (roomId: string) => void;
  onNew: () => void;
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
  onSettings,
  spaces = [],
  selectedSpaceId = null,
  onSelectSpace,
}: Props) {
  const { t } = useI18n();
  return (
    <aside className={`sidebar ${activeId ? "has-room" : ""}`} aria-label={t("sidebar.rooms")}>
      <header className="sidebar-head">
        <div className="brand-lockup compact">
          <span className="brand-symbol" aria-hidden="true">H</span>
          <strong>HighLife</strong>
        </div>
        <div className="head-actions">
          <button className="icon-button" type="button" onClick={onNew} aria-label={t("sidebar.createOrJoin")}>
            <IconPlus />
          </button>
          <button className="icon-button" type="button" onClick={onSettings} aria-label={t("sidebar.settings")}>
            <IconSettings />
          </button>
        </div>
      </header>
      <label className="search-field">
        <IconSearch />
        <input
          value={query}
          onChange={(event) => onQuery(event.target.value)}
          placeholder={t("sidebar.search")}
          aria-label={t("sidebar.search")}
        />
      </label>
      {spaces.length > 0 && onSelectSpace && (
        <section className="spaces-section" aria-label={t("sidebar.spaces")}>
          <p className="eyebrow">{t("sidebar.spaces")}</p>
          <div className="space-list">
            <button
              type="button"
              className={`space-row ${selectedSpaceId === null ? "active" : ""}`}
              onClick={() => onSelectSpace(null)}
            >
              {t("sidebar.rooms")}
            </button>
            {spaces.map((space) => (
              <button
                key={space.roomId}
                type="button"
                className={`space-row ${selectedSpaceId === space.roomId ? "active" : ""}`}
                onClick={() => onSelectSpace(space.roomId)}
              >
                {space.avatarUrl ? (
                  <img src={space.avatarUrl} className="space-avatar" alt="" />
                ) : (
                  <span className="space-avatar fallback" aria-hidden="true">
                    {space.name.slice(0, 1).toUpperCase()}
                  </span>
                )}
                <span>{space.name}</span>
              </button>
            ))}
          </div>
        </section>
      )}
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
            {room.avatarUrl ? (
              <img src={room.avatarUrl} className="avatar" alt="" />
            ) : (
              <span className="avatar fallback" aria-hidden="true">
                {room.name.slice(0, 2).toUpperCase()}
              </span>
            )}
            <span className="room-copy">
              <span className="room-title">
                <strong>
                  {room.isSpace ? `${t("rooms.space")}: ` : ""}
                  {room.name}
                </strong>
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
  );
}
