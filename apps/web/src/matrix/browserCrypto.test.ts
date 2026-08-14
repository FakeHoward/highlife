import { describe, expect, it } from "vitest";
import { probeBrowserCrypto } from "./browserCrypto";

describe("browser crypto probe", () => {
  it("accepts a secure WASM browser", () => {
    expect(
      probeBrowserCrypto({
        isSecureContext: true,
        indexedDB: {} as IDBFactory,
        WebAssembly: {},
      }),
    ).toEqual({ ready: true, reason: null });
  });

  it("rejects insecure or incomplete environments", () => {
    expect(
      probeBrowserCrypto({ isSecureContext: false, indexedDB: {} as IDBFactory, WebAssembly: {} }),
    ).toEqual({ ready: false, reason: "insecure" });
    expect(
      probeBrowserCrypto({ isSecureContext: true, indexedDB: {} as IDBFactory }),
    ).toEqual({ ready: false, reason: "wasm" });
  });
});
