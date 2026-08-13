import { describe, expect, it } from "vitest";
import { hasActiveCommandsState, isLikelyBotUserId, roomNeedsHostHandshake } from "./hostHandshake";

describe("roomNeedsHostHandshake", () => {
  it("skips encrypted DMs and ordinary group chats", () => {
    expect(
      roomNeedsHostHandshake({
        isDirect: true,
        memberUserIds: ["@me:example.org", "@ada:example.org"],
      }),
    ).toBe(false);
    expect(
      roomNeedsHostHandshake({
        isDirect: false,
        memberUserIds: ["@me:example.org", "@ada:example.org", "@bob:example.org"],
      }),
    ).toBe(false);
  });

  it("advertises only where an aiomatrix bot or commands state is present", () => {
    expect(
      roomNeedsHostHandshake({
        isDirect: true,
        memberUserIds: ["@me:example.org", "@highlifebot:example.org"],
      }),
    ).toBe(true);
    expect(
      roomNeedsHostHandshake({
        isDirect: false,
        memberUserIds: ["@me:example.org"],
        hasCommandsState: true,
      }),
    ).toBe(true);
  });

  it("treats highlifebot and *bot localparts as bots", () => {
    expect(isLikelyBotUserId("@highlifebot:example.org")).toBe(true);
    expect(isLikelyBotUserId("@formspacebot:example.org")).toBe(true);
    expect(isLikelyBotUserId("@ada:example.org")).toBe(false);
  });

  it("ignores empty or redacted commands leftovers", () => {
    expect(hasActiveCommandsState([{}, undefined, null])).toBe(false);
    expect(hasActiveCommandsState([{ commands: [{ name: "start" }] }])).toBe(true);
  });
});
