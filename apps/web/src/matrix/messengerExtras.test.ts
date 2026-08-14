import { describe, expect, it } from "vitest";
import {
  firstUnreadEventId,
  formatForwardedBody,
  formatForwardedMedia,
  formatPresenceLabel,
  isRoomMutedByPushRules,
  isVoiceMessageContent,
  togglePinnedIds,
  formatRoomListTime,
  partitionInvitesAndJoined,
  notificationTargetFromPush,
} from "./messengerExtras";

describe("messenger extras", () => {
  it("treats a room-specific dont_notify rule as mute", () => {
    expect(isRoomMutedByPushRules([{ rule_id: "!a:x", actions: ["dont_notify"] }], "!a:x")).toBe(true);
    expect(isRoomMutedByPushRules([{ rule_id: "!a:x", enabled: false, actions: ["dont_notify"] }], "!a:x")).toBe(false);
    expect(isRoomMutedByPushRules([], "!a:x")).toBe(false);
  });

  it("toggles pinned event ids", () => {
    expect(togglePinnedIds(["$a"], "$b")).toEqual(["$a", "$b"]);
    expect(togglePinnedIds(["$a", "$b"], "$a")).toEqual(["$b"]);
  });

  it("finds the first event after the local read marker", () => {
    expect(firstUnreadEventId(["$a", "$b", "$c"], "$a")).toBe("$b");
    expect(firstUnreadEventId(["$a", "$b"], "$b")).toBeNull();
    expect(firstUnreadEventId(["$a", "$b"], null)).toBe("$a");
  });

  it("formats presence and forwarded quote text", () => {
    expect(
      formatPresenceLabel("online", undefined, true, {
        online: "Online",
        away: "Away",
        offline: "Offline",
        lastSeen: (when) => `Last seen ${when}`,
      }),
    ).toBe("Online");
    expect(formatForwardedBody("Ada", "hello")).toBe("Ada:\nhello");
    expect(formatForwardedMedia("Ada", "image")).toBe("Ada:\n[image]");
    expect(isVoiceMessageContent({ "org.matrix.msc3245.voice": {} })).toBe(true);
  });

  it("splits invites from joined rooms", () => {
    const parts = partitionInvitesAndJoined(
      [{ id: "a", membership: "join" }, { id: "b", membership: "invite" }],
      (item) => item.membership,
    );
    expect(parts.invites.map((item) => item.id)).toEqual(["b"]);
    expect(parts.joined.map((item) => item.id)).toEqual(["a"]);
  });

  it("deep-links push notifications into a room when room_id is present", () => {
    expect(notificationTargetFromPush({ room_id: "!chat:example.org" })).toBe("/?room=%21chat%3Aexample.org");
    expect(notificationTargetFromPush({})).toBe("/");
  });

  it("formats room list times as clock, yesterday, or date", () => {
    const now = new Date(2026, 7, 14, 15, 30).getTime();
    expect(formatRoomListTime(new Date(2026, 7, 14, 9, 5).getTime(), "Yesterday", now)).toBe("09:05");
    expect(formatRoomListTime(new Date(2026, 7, 13, 22, 1).getTime(), "Yesterday", now)).toBe("Yesterday");
    expect(formatRoomListTime(new Date(2026, 6, 3, 8, 0).getTime(), "Yesterday", now)).toBe("03.07");
  });
});
