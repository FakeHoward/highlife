import { describe, expect, it, vi } from "vitest";

vi.mock("matrix-js-sdk/lib/matrixrtc", () => ({
  MatrixRTCSessionEvent: {
    EncryptionKeyChanged: "encryption_key_changed",
  },
}));

import { MatrixRTCSessionEvent } from "matrix-js-sdk/lib/matrixrtc";
import { ELEMENT_CALL_KEY_PROVIDER_OPTIONS, MatrixLivekitKeyProvider } from "./livekitE2ee";

describe("MatrixLivekitKeyProvider", () => {
  it("matches Element Call ratcheting options", () => {
    expect(ELEMENT_CALL_KEY_PROVIDER_OPTIONS).toEqual({
      sharedKey: false,
      ratchetWindowSize: 10,
      keyringSize: 256,
    });
  });

  it("subscribes to MatrixRTC key changes and reemits the current ring", () => {
    const provider = new MatrixLivekitKeyProvider();
    const session = {
      on: vi.fn(),
      off: vi.fn(),
      reemitEncryptionKeys: vi.fn(),
    };

    provider.attach(session);
    expect(session.on).toHaveBeenCalledWith(
      MatrixRTCSessionEvent.EncryptionKeyChanged,
      expect.any(Function),
    );
    expect(session.reemitEncryptionKeys).toHaveBeenCalledTimes(1);

    provider.detach();
    expect(session.off).toHaveBeenCalledWith(
      MatrixRTCSessionEvent.EncryptionKeyChanged,
      expect.any(Function),
    );
  });
});
