import { describe, expect, it } from "vitest";
import { assertCryptoForEncryptedRoom, CryptoUnavailableError } from "./cryptoGuard";

describe("assertCryptoForEncryptedRoom", () => {
  it("allows plaintext rooms without crypto", () => {
    expect(() => assertCryptoForEncryptedRoom({ encrypted: false, cryptoReady: false })).not.toThrow();
  });

  it("allows encrypted rooms when rust-crypto is attached", () => {
    expect(() => assertCryptoForEncryptedRoom({ encrypted: true, cryptoReady: true })).not.toThrow();
  });

  it("refuses encrypted traffic when getCrypto() is missing", () => {
    expect(() => assertCryptoForEncryptedRoom({ encrypted: true, cryptoReady: false })).toThrow(
      CryptoUnavailableError,
    );
  });
});
