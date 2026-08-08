/**
 * Matrix encrypted attachments (AES-CTR v2) using Web Crypto.
 * Spec: https://spec.matrix.org/v1.11/client-server-api/#extensions-to-mroommessage-msgtypes
 */

export interface EncryptedAttachmentInfo {
  v: "v2";
  key: JsonWebKey;
  iv: string;
  hashes: { sha256: string };
  url?: string;
}

function toBase64(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (let i = 0; i < view.length; i += 1) binary += String.fromCharCode(view[i]!);
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array {
  const binary = atob(value);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
  return out;
}

async function sha256Base64(data: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", data);
  return toBase64(digest);
}

/** Encrypt plaintext bytes for an encrypted room attachment. */
export async function encryptAttachment(
  data: ArrayBuffer,
): Promise<{ ciphertext: ArrayBuffer; info: EncryptedAttachmentInfo }> {
  const iv = new Uint8Array(16);
  crypto.getRandomValues(iv.subarray(0, 8));
  // Matrix AES-CTR: upper 64 bits random, lower 64 bits zeroed counter.
  const key = await crypto.subtle.generateKey({ name: "AES-CTR", length: 256 }, true, [
    "encrypt",
    "decrypt",
  ]);
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-CTR", counter: iv, length: 64 },
    key,
    data,
  );
  const jwk = await crypto.subtle.exportKey("jwk", key);
  return {
    ciphertext,
    info: {
      v: "v2",
      key: jwk,
      iv: toBase64(iv),
      hashes: { sha256: await sha256Base64(ciphertext) },
    },
  };
}

/** Decrypt ciphertext using the Matrix `file` block from event content. */
export async function decryptAttachment(
  ciphertext: ArrayBuffer,
  info: EncryptedAttachmentInfo,
): Promise<ArrayBuffer> {
  const expected = info.hashes?.sha256;
  if (expected) {
    const actual = await sha256Base64(ciphertext);
    if (actual !== expected) {
      throw new Error("Encrypted attachment hash mismatch");
    }
  }
  const key = await crypto.subtle.importKey(
    "jwk",
    info.key,
    { name: "AES-CTR" },
    false,
    ["decrypt"],
  );
  const iv = fromBase64(info.iv);
  return crypto.subtle.decrypt(
    { name: "AES-CTR", counter: iv as BufferSource, length: 64 },
    key,
    ciphertext as BufferSource,
  );
}

export function encryptedFileFromContent(
  content: Record<string, unknown>,
): EncryptedAttachmentInfo | undefined {
  const file = content.file;
  if (!file || typeof file !== "object" || Array.isArray(file)) return undefined;
  const record = file as Record<string, unknown>;
  const key = record.key;
  const iv = record.iv;
  const hashes = record.hashes;
  if (!key || typeof key !== "object" || typeof iv !== "string" || !hashes || typeof hashes !== "object") {
    return undefined;
  }
  const sha = (hashes as Record<string, unknown>).sha256;
  if (typeof sha !== "string") return undefined;
  return {
    v: "v2",
    key: key as JsonWebKey,
    iv,
    hashes: { sha256: sha },
    ...(typeof record.url === "string" ? { url: record.url } : {}),
  };
}
