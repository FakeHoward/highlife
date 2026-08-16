import { describe, expect, it } from "vitest";
import { matrixRtcCameraOptions, outgoingCallMode } from "./callRouting";

describe("outgoingCallMode", () => {
  it("uses MatrixRTC for DMs so Element X can join when a focus exists", () => {
    expect(
      outgoingCallMode({
        isDirect: true,
        encrypted: true,
        cryptoReady: true,
        matrixRtcAvailable: true,
      }),
    ).toBe("matrixrtc");
  });

  it("uses MatrixRTC for group rooms when a focus exists", () => {
    expect(
      outgoingCallMode({
        isDirect: false,
        encrypted: true,
        cryptoReady: true,
        matrixRtcAvailable: true,
      }),
    ).toBe("matrixrtc");
  });

  it("does not assume MatrixRTC without an explicit focus", () => {
    expect(outgoingCallMode({ isDirect: true, encrypted: true, cryptoReady: true })).toBe("direct");
    expect(outgoingCallMode({ isDirect: false, encrypted: true, cryptoReady: true })).toBe("blocked");
  });

  it("falls back to classic 1:1 WebRTC only when MatrixRTC is unavailable in a DM", () => {
    expect(
      outgoingCallMode({
        isDirect: true,
        encrypted: true,
        cryptoReady: true,
        matrixRtcAvailable: false,
      }),
    ).toBe("direct");
  });

  it("refuses classic encrypted invites when crypto is not ready", () => {
    expect(
      outgoingCallMode({
        isDirect: true,
        encrypted: true,
        cryptoReady: false,
        matrixRtcAvailable: false,
      }),
    ).toBe("blocked");
  });

  it("maps the chat video flag onto MatrixRTC camera options", () => {
    expect(matrixRtcCameraOptions()).toBeUndefined();
    expect(matrixRtcCameraOptions({ video: true })).toEqual({ camera: true });
    expect(matrixRtcCameraOptions({ video: false })).toEqual({ camera: false });
  });
});
