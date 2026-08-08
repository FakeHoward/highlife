import { describe, expect, it } from "vitest";
import {
  joinRoomErrorMessage,
  normalizeRoomIdOrAlias,
  serverFromRoomAddress,
} from "./roomAddress";

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

describe("serverFromRoomAddress", () => {
  it("extracts the server part", () => {
    expect(serverFromRoomAddress("#matrix-dev:matrix.org")).toBe("matrix.org");
    expect(serverFromRoomAddress("!abc:example.org")).toBe("example.org");
  });
});

describe("joinRoomErrorMessage", () => {
  it("maps 404 to a not-found hint", () => {
    expect(joinRoomErrorMessage({ httpStatus: 404 }, "#brbrb:hs")).toContain("Room not found");
  });

  it("maps server-banned 403 to a homeserver ACL explanation", () => {
    const msg = joinRoomErrorMessage(
      {
        httpStatus: 403,
        errcode: "M_FORBIDDEN",
        message: "MatrixError: [403] Server is banned from room",
      },
      "#matrix-dev:matrix.org",
    );
    expect(msg).toMatch(/blocked|banned|rules/i);
    expect(msg).toMatch(/another server|matrix\.org/i);
  });

  it("localizes banned join errors in Russian", () => {
    const msg = joinRoomErrorMessage(
      {
        httpStatus: 403,
        errcode: "M_FORBIDDEN",
        message: "MatrixError: [403] Server is banned from room",
      },
      "#matrix-dev:matrix.org",
      "ru",
    );
    expect(msg).toMatch(/заблокирован|правилами/i);
    expect(msg).toMatch(/matrix\.org/);
  });
});
