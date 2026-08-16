import { describe, expect, it } from "vitest";
import { isInvalidCredentialsError, localpartOf } from "./identity";

describe("localpartOf", () => {
  it("strips MXID to localpart like the Android client", () => {
    expect(localpartOf("@viewer:testhighlife.strangled.net")).toBe("viewer");
    expect(localpartOf("viewer")).toBe("viewer");
    expect(localpartOf("  @viewer:testhighlife.strangled.net  ")).toBe("viewer");
    expect(localpartOf("@viewer")).toBe("viewer");
  });

  it("returns empty for blank input", () => {
    expect(localpartOf("")).toBe("");
    expect(localpartOf("   ")).toBe("");
    expect(localpartOf("@")).toBe("");
  });
});

describe("isInvalidCredentialsError", () => {
  it("detects Matrix 403 password failures", () => {
    expect(
      isInvalidCredentialsError({
        httpStatus: 403,
        errcode: "M_FORBIDDEN",
        message: "MatrixError: [403] Invalid username/password",
      }),
    ).toBe(true);
    expect(isInvalidCredentialsError({ message: "timeout" })).toBe(false);
  });
});
