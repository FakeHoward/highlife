import { describe, expect, it } from "vitest";
import {
  hasSendEventCapability,
  isAllowedCallEventType,
  isGrantableWidgetCapability,
  resolveWidgetSendRoomId,
} from "./widgetHost";

describe("Element Call widget grants", () => {
  it("allows call membership and message sends, refuses wildcards and arbitrary rooms", () => {
    expect(isGrantableWidgetCapability("org.matrix.msc2762.send.event:m.room.message")).toBe(true);
    expect(isGrantableWidgetCapability("org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member")).toBe(true);
    expect(isGrantableWidgetCapability("org.matrix.msc2762.send.event:*")).toBe(false);
    expect(isGrantableWidgetCapability("org.matrix.msc2762.send.event:m.room.power_levels")).toBe(false);
    expect(isAllowedCallEventType("m.call.invite")).toBe(true);
    expect(isAllowedCallEventType("m.room.topic")).toBe(false);
  });

  it("pins send_event to the host room", () => {
    expect(resolveWidgetSendRoomId("!call:hs", "!other:hs")).toBe("!call:hs");
  });

  it("requires an approved send capability for the event type", () => {
    const approved = new Set([
      "org.matrix.msc2762.send.event:m.room.message",
      "org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member",
    ]);
    expect(hasSendEventCapability(approved, "m.room.message", false)).toBe(true);
    expect(hasSendEventCapability(approved, "org.matrix.msc3401.call.member", true)).toBe(true);
    expect(hasSendEventCapability(approved, "m.room.power_levels", false)).toBe(false);
  });
});
