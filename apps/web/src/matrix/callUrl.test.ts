import { describe, expect, it } from "vitest";
import { buildElementCallUrl, callWidgetId } from "./callUrl";

describe("buildElementCallUrl", () => {
  const identity = {
    userId: "@me:example.org",
    deviceId: "DEVICE",
    baseUrl: "https://matrix.example.org",
  };

  it("builds a widget URL with Matrix identity params", () => {
    const url = buildElementCallUrl({
      baseUrl: "https://call.example.org",
      parentUrl: "https://app.example.org",
      roomId: "!room:example.org",
      identity,
      windowOrigin: "https://fallback.example.org",
    });
    expect(url).toBeTruthy();
    const parsed = new URL(url!);
    expect(parsed.origin).toBe("https://call.example.org");
    expect(parsed.searchParams.get("widgetId")).toBe(callWidgetId("!room:example.org"));
    expect(parsed.searchParams.get("parentUrl")).toBe("https://app.example.org");
    expect(parsed.searchParams.get("roomId")).toBe("!room:example.org");
    expect(parsed.searchParams.get("userId")).toBe(identity.userId);
    expect(parsed.searchParams.get("deviceId")).toBe(identity.deviceId);
    expect(parsed.searchParams.get("baseUrl")).toBe(identity.baseUrl);
  });

  it("returns null when Element Call URL is missing or unsafe", () => {
    expect(buildElementCallUrl({
      baseUrl: undefined,
      parentUrl: "https://app.example.org",
      roomId: "!room:example.org",
      identity,
    })).toBeNull();
    expect(buildElementCallUrl({
      baseUrl: "javascript:alert(1)",
      parentUrl: "https://app.example.org",
      roomId: "!room:example.org",
      identity,
    })).toBeNull();
  });
});
