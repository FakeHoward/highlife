import { describe, expect, it } from "vitest";
import { renderSVG } from "../vendor/uqr.js";
import { bytesToQrText } from "../components/QrCode";

describe("QR payload", () => {
  it("encodes MSC4108 bytes as a local SVG", () => {
    const payload = bytesToQrText(new Uint8Array([0x4d, 0x41, 0x54, 0x52, 0x49, 0x58]));
    const svg = renderSVG(payload);
    expect(svg).toContain("<svg");
    expect(svg).toContain("path");
  });
});
