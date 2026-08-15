/** DiceBear fallback avatars. Seed is a hash of the Matrix id, not the raw MXID. */

export const DICEBEAR_HOST = "https://api.dicebear.com";
export const DICEBEAR_VERSION = "9.x";
export const DICEBEAR_STYLE = "notionists-neutral";

const BACKGROUNDS = ["168acd", "2a9d8f", "457b9d", "6d597a", "c44536", "577590"] as const;

/** FNV-1a 32-bit, stable across web and Flutter. */
export function dicebearSeed(identity: string): string {
  let hash = 2166136261;
  const normalized = identity.trim().toLowerCase();
  for (let i = 0; i < normalized.length; i += 1) {
    hash ^= normalized.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

export function dicebearBackground(identity: string): string {
  const seed = dicebearSeed(identity);
  const nibble = Number.parseInt(seed.slice(-1), 16);
  return BACKGROUNDS[nibble % BACKGROUNDS.length]!;
}

export function dicebearAvatarUrl(identity: string, size = 128): string {
  const seed = dicebearSeed(identity);
  const params = new URLSearchParams({
    seed,
    size: String(size),
    backgroundColor: dicebearBackground(identity),
  });
  return `${DICEBEAR_HOST}/${DICEBEAR_VERSION}/${DICEBEAR_STYLE}/png?${params}`;
}
