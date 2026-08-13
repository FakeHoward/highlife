import { describe, expect, it } from "vitest";
import {
  firstUnreadEventId,
  formatForwardedBody,
  formatPresenceLabel,
  isRoomMutedByPushRules,
  isVoiceMessageContent,
  togglePinnedIds,
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
    expect(isVoiceMessageContent({ "org.matrix.msc3245.voice": {} })).toBe(true);
  });
});
