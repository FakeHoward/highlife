export const WEB_APP_VERSION = "0.4.5";

export const DEFAULT_LATEST_JSON_URL =
  "https://testhighlife.strangled.net/client/latest.json";

export interface WebReleaseInfo {
  version: string;
  build: number;
  notes: string;
  assets: Record<string, string>;
}

export function parseVersionParts(version: string): number[] {
  return version.split(/[.+-]/).map((part) => {
    const value = Number.parseInt(part, 10);
    return Number.isFinite(value) ? value : 0;
  });
}

export function isNewerRelease(current: string, latest: string): boolean {
  const left = parseVersionParts(current);
  const right = parseVersionParts(latest);
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    const delta = (right[index] ?? 0) - (left[index] ?? 0);
    if (delta !== 0) return delta > 0;
  }
  return false;
}

export function parseLatestJson(payload: unknown): WebReleaseInfo | null {
  if (!payload || typeof payload !== "object") return null;
  const data = payload as Record<string, unknown>;
  const version = typeof data.version === "string" ? data.version.trim() : "";
  if (!version) return null;
  const assetsRaw = data.assets;
  const assets: Record<string, string> = {};
  if (assetsRaw && typeof assetsRaw === "object") {
    for (const [key, value] of Object.entries(assetsRaw as Record<string, unknown>)) {
      if (typeof value === "string" && value) assets[key] = value;
    }
  }
  return {
    version,
    build: Number.parseInt(String(data.build ?? "0"), 10) || 0,
    notes: typeof data.notes === "string" ? data.notes : "",
    assets,
  };
}

export interface WebUpdateResult {
  updateAvailable: boolean;
  latest: WebReleaseInfo | null;
  assetUrl: string | null;
}

export async function checkWebUpdate(
  currentVersion = WEB_APP_VERSION,
  latestJsonUrl = DEFAULT_LATEST_JSON_URL,
  fetchImpl: typeof fetch = fetch,
): Promise<WebUpdateResult> {
  try {
    const response = await fetchImpl(latestJsonUrl, { cache: "no-store" });
    if (!response.ok) return { updateAvailable: false, latest: null, assetUrl: null };
    const latest = parseLatestJson(await response.json());
    if (!latest || !isNewerRelease(currentVersion, latest.version)) {
      return { updateAvailable: false, latest, assetUrl: latest?.assets.web ?? null };
    }
    return {
      updateAvailable: true,
      latest,
      assetUrl: latest.assets.web ?? latestJsonUrl.replace(/latest\.json$/, ""),
    };
  } catch {
    return { updateAvailable: false, latest: null, assetUrl: null };
  }
}
