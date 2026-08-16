import type { RoomListItem, SpaceSummary } from "@highlife/ui-contracts";
import { useI18n } from "../i18n";
import { formatRoomListTime, partitionInvitesAndJoined } from "../matrix/messengerExtras";
import { acceptInvite, rejectInvite } from "../matrix/service";
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
  onProfile?: () => void;
  profileId?: string;
  profileName?: string;
  profileAvatar?: string;
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
  onProfile,
  profileId,
  profileName,
  profileAvatar,
  spaces = [],
  selectedSpaceId = null,
  onSelectSpace,
}: Props) {
  const { t } = useI18n();
  const { invites, joined } = partitionInvitesAndJoined(rooms, (room) => room.membership);
  const selectedSpace = spaces.find((space) => space.roomId === selectedSpaceId) ?? null;

  return (
    <div className="sidebar-cluster">
      {onSelectSpace && (
        <nav className="space-rail" aria-label={t("spaces.selectedHint")}>
          <button
            type="button"
            className={`space-rail-btn ${selectedSpaceId === null ? "active" : ""}`}
            onClick={() => onSelectSpace(null)}
            aria-pressed={selectedSpaceId === null}
            title={t("sidebar.allRooms")}
          >
            <span className="space-rail-mark">H</span>
          </button>
          {spaces.map((space) => (
            <button
              key={space.roomId}
              type="button"
              className={`space-rail-btn ${selectedSpaceId === space.roomId ? "active" : ""}`}
              onClick={() => onSelectSpace(space.roomId)}
              aria-pressed={selectedSpaceId === space.roomId}
              title={space.name}
            >
              <Avatar id={space.roomId} name={space.name} src={space.avatarUrl} size="small" />
            </button>
          ))}
          <button
            type="button"
            className="space-rail-btn add"
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
          <strong className="sidebar-title">HighLife</strong>
          <div className="head-actions">
            <button className="icon-button" type="button" onClick={onNew} aria-label={t("sidebar.createOrJoin")} title={t("sidebar.createOrJoin")}>
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
        {onSelectSpace && (
          <nav className="folder-tabs" aria-label={t("sidebar.spaces")}>
            <button
              type="button"
              className={`folder-tab ${selectedSpaceId === null ? "active" : ""}`}
              onClick={() => onSelectSpace(null)}
              aria-pressed={selectedSpaceId === null}
            >
              {t("sidebar.allRooms")}
            </button>
            {spaces.map((space) => (
              <button
                key={space.roomId}
                type="button"
                className={`folder-tab ${selectedSpaceId === space.roomId ? "active" : ""}`}
                onClick={() => onSelectSpace(space.roomId)}
                aria-pressed={selectedSpaceId === space.roomId}
              >
                {space.name}
              </button>
            ))}
            <button
              type="button"
              className="folder-tab add"
              onClick={onNewSpace}
              aria-label={t("spaces.createTitle")}
              title={t("spaces.createTitle")}
            >
              <IconFolderPlus />
            </button>
          </nav>
        )}
        {selectedSpace && (
          <div className="selected-space-panel">
            <Avatar id={selectedSpace.roomId} name={selectedSpace.name} src={selectedSpace.avatarUrl} size="small" />
            <div>
              <strong>{selectedSpace.name}</strong>
              <span>{t("spaces.selectedHint")}</span>
            </div>
          </div>
        )}
        <nav className="room-list">
          {invites.length === 0 && joined.length === 0 && (
            <div className="empty-small">
              <span className="welcome-glyph" aria-hidden="true">H</span>
              <strong>{t("sidebar.emptyTitle")}</strong>
              <span>{t("sidebar.emptyHint")}</span>
            </div>
          )}
          {invites.length > 0 && (
            <div className="invite-group">
              <p className="eyebrow">{t("sidebar.invitation")}</p>
              {invites.map((room) => (
                <div
                  key={room.roomId}
                  className={`room-row invite-row ${activeId === room.roomId ? "active" : ""}`}
                >
                  <button type="button" className="invite-open" onClick={() => onSelect(room.roomId)}>
                    <Avatar id={room.roomId} name={room.name} src={room.avatarUrl} />
                    <span className="room-copy">
                      <span className="room-title">
                        <strong>{room.name}</strong>
                      </span>
                      <span className="room-preview">{t("sidebar.invitation")}</span>
                    </span>
                  </button>
                  <span className="invite-actions">
                    <button
                      type="button"
                      className="text-button"
                      onClick={() => void acceptInvite(room.roomId)}
                    >
                      {t("chat.acceptInvite")}
                    </button>
                    <button
                      type="button"
                      className="text-button danger-text"
                      onClick={() => void rejectInvite(room.roomId)}
                    >
                      {t("chat.rejectInvite")}
                    </button>
                  </span>
                </div>
              ))}
            </div>
          )}
          {joined.map((room) => (
            <button
              key={room.roomId}
              type="button"
              className={`room-row ${activeId === room.roomId ? "active" : ""} ${room.isSpace ? "is-space" : ""} ${room.unread > 0 ? "has-unread" : ""}`}
              onClick={() => onSelect(room.roomId)}
              aria-current={activeId === room.roomId ? "page" : undefined}
            >
              <Avatar id={room.roomId} name={room.name} src={room.avatarUrl} />
              <span className="room-copy">
                <span className="room-title">
                  <strong>{room.name}</strong>
                  <time>
                    {room.lastActive
                      ? formatRoomListTime(room.lastActive, t("timeline.yesterday"))
                      : ""}
                  </time>
                </span>
                <span className="room-preview">
                  {room.isEncrypted && (
                    <span className="enc-mark" aria-label={t("sidebar.encrypted")}>
                      <IconLock />
                    </span>
                  )}
                  {room.lastMessage ?? t("sidebar.noMessages")}
                  {room.muted && <span className="mute-mark">{t("sidebar.muted")}</span>}
                </span>
              </span>
              {room.unread > 0 && <span className={`unread ${room.highlight ? "hot" : ""}`}>{room.unread}</span>}
            </button>
          ))}
        </nav>
        {onProfile && profileId && (
          <button
            type="button"
            className="sidebar-profile"
            onClick={onProfile}
            aria-label={t("sidebar.profile")}
          >
            <Avatar id={profileId} name={profileName || profileId} src={profileAvatar} size="small" />
            <span className="room-copy">
              <strong>{profileName || profileId}</strong>
              <span className="room-preview utility-id">{profileId}</span>
            </span>
          </button>
        )}
      </aside>
    </div>
  );
}
