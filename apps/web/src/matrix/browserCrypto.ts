export interface BrowserCryptoProbe {
  ready: boolean;
  reason: "insecure" | "wasm" | "indexeddb" | null;
}

/** Pre-login environment check for rust-crypto (WASM + IndexedDB + HTTPS). */
export function probeBrowserCrypto(
  globals: Pick<Window, "isSecureContext" | "indexedDB"> & { WebAssembly?: unknown } = window,
): BrowserCryptoProbe {
  if (!globals.isSecureContext) return { ready: false, reason: "insecure" };
  if (typeof globals.WebAssembly !== "object" && typeof globals.WebAssembly !== "function") {
    return { ready: false, reason: "wasm" };
  }
  if (!globals.indexedDB) return { ready: false, reason: "indexeddb" };
  return { ready: true, reason: null };
}
