import { describe, expect, it, vi } from "vitest";
import {
  isNewerRelease,
  parseLatestJson,
  checkWebUpdate,
} from "./updateCheck";

describe("web update checker", () => {
  it("compares dotted versions", () => {
    expect(isNewerRelease("0.4.0", "0.4.1")).toBe(true);
    expect(isNewerRelease("0.4.1", "0.4.1")).toBe(false);
    expect(isNewerRelease("0.4.1", "0.4.0")).toBe(false);
  });

  it("reads latest.json payloads", () => {
    expect(parseLatestJson({ version: "0.4.1", build: 16, assets: { web: "https://example.org/web.zip" } })).toEqual({
      version: "0.4.1",
      build: 16,
      notes: "",
      assets: { web: "https://example.org/web.zip" },
    });
    expect(parseLatestJson({})).toBeNull();
  });

  it("flags an available web build", async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: true,
      json: async () => ({ version: "0.5.0", build: 20, assets: { web: "https://example.org/web.zip" } }),
    })) as unknown as typeof fetch;
    const result = await checkWebUpdate("0.4.1", "https://example.org/latest.json", fetchImpl);
    expect(result.updateAvailable).toBe(true);
    expect(result.assetUrl).toBe("https://example.org/web.zip");
  });
});
