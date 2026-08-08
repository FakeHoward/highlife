import { describe, expect, it } from "vitest";
import { joinRoomErrorMessage, normalizeRoomIdOrAlias } from "./roomAddress";

describe("normalizeRoomIdOrAlias", () => {
  it("keeps full aliases and room ids", () => {
    expect(normalizeRoomIdOrAlias("#brbrb:testhighlife.strangled.net")).toBe(
      "#brbrb:testhighlife.strangled.net",
    );
    expect(normalizeRoomIdOrAlias("!abc:testhighlife.strangled.net")).toBe(
      "!abc:testhighlife.strangled.net",
    );
  });

  it("adds homeserver to bare localparts and partial aliases", () => {
    expect(normalizeRoomIdOrAlias("brbrb", "testhighlife.strangled.net")).toBe(
      "#brbrb:testhighlife.strangled.net",
    );
    expect(normalizeRoomIdOrAlias("#brbrb", "testhighlife.strangled.net")).toBe(
      "#brbrb:testhighlife.strangled.net",
    );
  });
});

describe("joinRoomErrorMessage", () => {
  it("maps 404 to a not-found hint", () => {
    expect(joinRoomErrorMessage({ httpStatus: 404 }, "#brbrb:hs")).toContain("Room not found");
  });
});
