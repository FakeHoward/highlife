/** Thrown when a room has Megolm enabled but rust-crypto never attached. */
export class CryptoUnavailableError extends Error {
  readonly code = "crypto_unavailable" as const;

  constructor() {
    super("crypto_unavailable");
    this.name = "CryptoUnavailableError";
  }
}

export function assertCryptoForEncryptedRoom(input: {
  encrypted: boolean;
  cryptoReady: boolean;
}): void {
  if (input.encrypted && !input.cryptoReady) {
    throw new CryptoUnavailableError();
  }
}
