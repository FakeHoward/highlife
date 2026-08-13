import { describe, expect, it } from "vitest";
import {
  isActiveCallMemberContent,
  livekitFocusFromCallMemberContent,
  pickIncomingRtcCall,
  userIdFromCallMember,
} from "./rtcMembership";

describe("MSC3401 / MSC4143 call membership", () => {
  it("treats Element X slot events as an active call", () => {
    expect(
      isActiveCallMemberContent({
        application: "m.call",
        call_id: "",
        device_id: "EXDEVICE",
        foci_preferred: [
          { type: "livekit", livekit_service_url: "https://rtc.element.io/livekit/jwt" },
        ],
        focus_active: { type: "livekit", focus_selection: "oldest_membership" },
      }),
    ).toBe(true);
  });

  it("treats nested MSC3401 memberships as an active call", () => {
    expect(
      isActiveCallMemberContent({
        memberships: [{ device_id: "DEV", membership: "join" }],
      }),
    ).toBe(true);
  });

  it("ignores leftover m.call keys and empty hangups", () => {
    expect(isActiveCallMemberContent({ "m.call": { id: "x" }, devices: { DEV: {} } })).toBe(false);
    expect(isActiveCallMemberContent({})).toBe(false);
    expect(isActiveCallMemberContent({ memberships: [] })).toBe(false);
    expect(
      isActiveCallMemberContent({
        memberships: [{ device_id: "DEV", membership: "join", expires_ts: 1 }],
      }, 100),
    ).toBe(false);
  });

  it("reads the LiveKit URL Element X published, not HighLife's fallback", () => {
    expect(
      livekitFocusFromCallMemberContent({
        application: "m.call",
        foci_preferred: [
          { type: "livekit", livekit_service_url: "https://rtc.element.io/livekit/jwt/" },
        ],
        focus_active: { type: "livekit", focus_selection: "oldest_membership" },
      }),
    ).toEqual({
      type: "livekit",
      livekit_service_url: "https://rtc.element.io/livekit/jwt",
    });
  });

  it("parses the MSC3401 state key HighLife and Element X both use", () => {
    expect(userIdFromCallMember("_@ada:example.org_DEVICE", "@other:example.org")).toBe(
      "@ada:example.org",
    );
  });

  it("rings only when someone else is in MatrixRTC and we are not", () => {
    expect(
      pickIncomingRtcCall({
        selfUserId: "@me:example.org",
        dismissedRoomIds: [],
        rooms: [
          {
            roomId: "!dm:example.org",
            name: "Ada",
            members: [
              {
                stateKey: "_@ada:example.org_EX",
                sender: "@ada:example.org",
                content: { application: "m.call", device_id: "EX" },
              },
            ],
          },
        ],
      }),
    ).toEqual({
      roomId: "!dm:example.org",
      name: "Ada",
      peerUserId: "@ada:example.org",
    });

    expect(
      pickIncomingRtcCall({
        selfUserId: "@me:example.org",
        dismissedRoomIds: [],
        rooms: [
          {
            roomId: "!dm:example.org",
            name: "Ada",
            members: [
              {
                stateKey: "_@ada:example.org_EX",
                sender: "@ada:example.org",
                content: { application: "m.call", device_id: "EX" },
              },
              {
                stateKey: "_@me:example.org_HL",
                sender: "@me:example.org",
                content: { application: "m.call", device_id: "HL" },
              },
            ],
          },
        ],
      }),
    ).toBeNull();
  });
});
