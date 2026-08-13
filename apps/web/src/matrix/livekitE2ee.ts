import { BaseKeyProvider } from "livekit-client";
import {
  MatrixRTCSessionEvent,
  type MatrixRTCSession,
} from "matrix-js-sdk/lib/matrixrtc";

/** Same ratcheting window Element Call uses for per-participant LiveKit keys. */
export const ELEMENT_CALL_KEY_PROVIDER_OPTIONS = {
  sharedKey: false,
  ratchetWindowSize: 10,
  keyringSize: 256,
} as const;

export type MatrixRtcSessionKeys = Pick<MatrixRTCSession, "on" | "off" | "reemitEncryptionKeys">;

/**
 * Bridges MatrixRTC to-device media keys into LiveKit frame encryption.
 * Identity is `rtcBackendIdentity` (`userId:deviceId` unless sticky-event hashing is on).
 */
export class MatrixLivekitKeyProvider extends BaseKeyProvider {
  private session: MatrixRtcSessionKeys | null = null;

  constructor() {
    super({ ...ELEMENT_CALL_KEY_PROVIDER_OPTIONS });
  }

  attach(session: MatrixRtcSessionKeys): void {
    this.detach();
    this.session = session;
    session.on(MatrixRTCSessionEvent.EncryptionKeyChanged, this.onEncryptionKeyChanged);
    session.reemitEncryptionKeys();
  }

  detach(): void {
    this.session?.off(MatrixRTCSessionEvent.EncryptionKeyChanged, this.onEncryptionKeyChanged);
    this.session = null;
  }

  applyRawKey(key: Uint8Array, encryptionKeyIndex: number, rtcBackendIdentity: string): Promise<void> {
    const buffer = new ArrayBuffer(key.byteLength);
    new Uint8Array(buffer).set(key);
    return crypto.subtle
      .importKey("raw", buffer, "HKDF", false, ["deriveBits", "deriveKey"])
      .then((keyMaterial) => {
        this.onSetEncryptionKey(keyMaterial, rtcBackendIdentity, encryptionKeyIndex);
      });
  }

  private onEncryptionKeyChanged = (
    encryptionKey: Uint8Array,
    encryptionKeyIndex: number,
    _membership: { userId: string; deviceId: string; memberId: string },
    rtcBackendIdentity: string,
  ): void => {
    void this.applyRawKey(encryptionKey, encryptionKeyIndex, rtcBackendIdentity).catch(() => undefined);
  };
}

