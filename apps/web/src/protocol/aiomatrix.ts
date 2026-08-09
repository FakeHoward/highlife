import { AIOMATRIX_CALLBACK_EVENT_TYPE } from "@highlife/ui-contracts";

export type AiomatrixButton =
  | { kind: "callback"; text: string; data: string; token?: string }
  | { kind: "command"; text: string; command: string }
  | { kind: "url"; text: string; url: string }
  | { kind: "mini_app"; text: string; url: string; startParam?: string };

export interface MiniAppCard {
  url: string;
  title: string;
  description?: string;
  appId?: string;
  botId?: string;
  startParam?: string;
}

export interface AiomatrixPayload {
  keyboard: AiomatrixButton[][] | null;
  miniApp: MiniAppCard | null;
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function string(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

export function isSafeWebUrl(value: string, allowHttp = false): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" || (allowHttp && url.protocol === "http:");
  } catch {
    return false;
  }
}

/**
 * Origins allowed for MiniApp iframes. Isolation for scripts+same-origin sandbox
 * relies on this allowlist (see MiniAppSurface). Sources:
 * - `VITE_MINIAPP_ALLOWED_ORIGINS` (comma-separated URLs or origins)
 * - origin of `VITE_DEFAULT_HOMESERVER` (prod miniapp is same-host under /miniapp/)
 * - localhost MiniApp vite port in DEV
 */
export function miniAppAllowedOrigins(env: {
  allowedOrigins?: string;
  homeserver?: string;
  dev?: boolean;
} = {}): string[] {
  const configured = env.allowedOrigins
    ?? (import.meta.env.VITE_MINIAPP_ALLOWED_ORIGINS as string | undefined);
  const homeserver = env.homeserver
    ?? (import.meta.env.VITE_DEFAULT_HOMESERVER as string | undefined);
  const dev = env.dev ?? Boolean(import.meta.env.DEV);
  const origins = new Set<string>();

  function add(raw: string | undefined) {
    const value = raw?.trim();
    if (!value) return;
    for (const part of value.split(",")) {
      const item = part.trim();
      if (!item) continue;
      try {
        const withScheme = item.includes("://") ? item : `https://${item}`;
        origins.add(new URL(withScheme).origin);
      } catch {
        // ignore malformed entries
      }
    }
  }

  add(configured);
  add(homeserver);
  if (dev) {
    add("http://localhost:4173");
    add("http://127.0.0.1:4173");
  }
  return [...origins];
}

/** True when `url` is https (or http in DEV) and its origin is on the MiniApp allowlist. */
export function isAllowedMiniAppUrl(
  url: string,
  env?: Parameters<typeof miniAppAllowedOrigins>[0],
): boolean {
  const allowHttp = env?.dev ?? Boolean(import.meta.env.DEV);
  if (!isSafeWebUrl(url, allowHttp)) return false;
  try {
    const origin = new URL(url).origin;
    const allowed = miniAppAllowedOrigins(env);
    if (allowed.length === 0) return false;
    return allowed.includes(origin);
  } catch {
    return false;
  }
}

/** Pull signed MiniApp initData from a launch URL fragment when present. */
export function extractMiniAppInitData(url: string): string | null {
  try {
    const hash = new URL(url).hash.replace(/^#/, "");
    if (!hash) return null;
    const params = new URLSearchParams(hash);
    return params.get("matrixWebAppData") ?? params.get("tgWebAppData");
  } catch {
    return null;
  }
}

function parseButton(value: unknown): AiomatrixButton | null {
  const button = object(value);
  const text = string(button.text);
  if (!text) return null;
  const callback = string(button.callback_data) ?? string(button.data);
  if (callback !== undefined) {
    return {
      kind: "callback",
      text,
      data: callback,
      ...(string(button.token) ? { token: string(button.token) } : {}),
    };
  }
  const command = string(button.command);
  if (command) return { kind: "command", text, command };
  const url = string(button.url);
  if (!url || !isSafeWebUrl(url, import.meta.env.DEV)) return null;
  if (button.kind === "mini_app" || button.mini_app === true) {
    const startParam = string(button.start_param) ?? string(button.startParam);
    return {
      kind: "mini_app",
      text,
      url,
      ...(startParam ? { startParam } : {}),
    };
  }
  return { kind: "url", text, url };
}

function parseKeyboard(content: Record<string, unknown>): AiomatrixButton[][] | null {
  const canonical = object(content["dev.aiomatrix.keyboard"]);
  const source = Array.isArray(canonical.inline)
    ? canonical.inline
    : content["ru.studnovsu.inline_keyboard"];
  if (!Array.isArray(source)) return null;
  const rows = source
    .filter(Array.isArray)
    .map((row) => row.map(parseButton).filter((item): item is AiomatrixButton => item !== null))
    .filter((row) => row.length > 0);
  return rows.length > 0 ? rows : null;
}

function parseMiniApp(content: Record<string, unknown>): MiniAppCard | null {
  const canonical = object(content["dev.aiomatrix.mini_app"]);
  const source = Object.keys(canonical).length > 0 ? canonical : content;
  if (source !== content && !string(source.url)) return null;
  if (
    source === content &&
    content.msgtype !== "ru.studnovsu.mini_app" &&
    content.msgtype !== "dev.aiomatrix.mini_app"
  ) {
    return null;
  }
  const url = string(source.url);
  if (!url || !isSafeWebUrl(url, import.meta.env.DEV)) return null;
  return {
    url,
    title: string(source.title) ?? "MiniApp",
    ...(string(source.description) ? { description: string(source.description) } : {}),
    ...(string(source.app_id) ? { appId: string(source.app_id) } : {}),
    ...(string(source.bot_id) ? { botId: string(source.bot_id) } : {}),
    ...(string(source.start_param) ? { startParam: string(source.start_param) } : {}),
  };
}

export function parseAiomatrixPayload(content: unknown): AiomatrixPayload {
  const value = object(content);
  return { keyboard: parseKeyboard(value), miniApp: parseMiniApp(value) };
}

/**
 * Strip aiomatrix plaintext keyboard fallback (`1. Label → !cb …`) when the
 * client already renders `dev.aiomatrix.keyboard` as buttons.
 */
export function stripKeyboardFallbackText(body: string): string {
  return body
    .replace(/\n\n(?:\d+\.\s+.+(?:\n|$))+$/u, "")
    .replace(/\n\n(?:.*!cb\s+\S+(?:\n|$))+$/u, "")
    .trimEnd();
}

/** Strip the trailing `<ol>…</ol>` HTML keyboard fallback from formatted_body. */
export function stripKeyboardFallbackHtml(html: string): string {
  return html.replace(/(?:<br\s*\/?>|\s)*<ol\b[^>]*>[\s\S]*<\/ol>\s*$/i, "").trimEnd();
}

/** Drop aiomatrix MiniApp URL fallback lines when the host renders a launch card. */
export function stripMiniAppUrlFallback(body: string): string {
  return body
    .replace(/^[^\n]*:\s*https?:\/\/\S+\s*$/gmu, "")
    .replace(/https?:\/\/\S*matrixWebAppData=\S+/gu, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function kindLabel(kind: string): string {
  switch (kind) {
    case "rsvp":
      return "RSVP";
    case "survey":
      return "survey";
    case "join":
      return "join request";
    case "onboard":
      return "onboarding";
    default:
      return kind;
  }
}

function choiceLabel(choice: string): string {
  switch (choice) {
    case "going":
      return "Going";
    case "maybe":
      return "Maybe";
    case "no":
      return "Can't make it";
    default:
      return choice;
  }
}

/**
 * Turn MiniApp `sendData` JSON (and similar structured payloads) into a short
 * human line. Returns null when the text is not a recognized JSON payload.
 */
export function humanizeStructuredPayload(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed.startsWith("{")) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const payload = parsed as Record<string, unknown>;
  const action = typeof payload.action === "string" ? payload.action : "";
  if (!action) return null;
  const title = typeof payload.title === "string" ? payload.title.trim() : "";
  const kind = typeof payload.kind === "string" ? payload.kind : "";
  const choice = typeof payload.choice === "string" ? payload.choice : "";
  switch (action) {
    case "publish":
      return title
        ? `Published ${kindLabel(kind) || "form"}: ${title}`
        : `Published ${kindLabel(kind) || "form"}`;
    case "save_draft":
      return title ? `Saved draft: ${title}` : "Saved form draft";
    case "submit":
      return "Submitted a form response";
    case "rsvp":
      return choice ? `RSVP: ${choiceLabel(choice)}` : "RSVP response";
    default:
      return `MiniApp · ${action}`;
  }
}

function miniAppDataPayload(content: Record<string, unknown>): string | null {
  const nested = object(content["dev.aiomatrix.mini_app_data"]);
  if (typeof nested.data === "string" && nested.data.length > 0) return nested.data;
  if (content.msgtype === "dev.aiomatrix.mini_app_data" && typeof content.body === "string") {
    return content.body;
  }
  return null;
}

/**
 * Timeline / send body: humanize MiniApp data + strip wire fallbacks.
 * Keeps Markdown markers for the HTML renderer.
 */
export function resolveDisplayBody(content: Record<string, unknown>): string {
  const data = miniAppDataPayload(content);
  if (data != null) {
    return humanizeStructuredPayload(data) ?? (data.trim().startsWith("{") ? "MiniApp data" : data);
  }
  const body = typeof content.body === "string" ? content.body : "";
  const humanized = humanizeStructuredPayload(body);
  if (humanized) return humanized;
  const mini = parseMiniApp(content);
  if (mini) {
    return [mini.title, mini.description].filter(Boolean).join("\n\n") || body;
  }
  let text = body;
  if (content["dev.aiomatrix.keyboard"] || content["ru.studnovsu.inline_keyboard"]) {
    text = stripKeyboardFallbackText(text);
  }
  text = stripMiniAppUrlFallback(text);
  text = text.replace(/(?:^|\n).*!cb\s+\S+.*/gu, "").replace(/\n{3,}/g, "\n\n").trim();
  return text;
}

/** Single-line room-list preview (Markdown → plain, fallbacks stripped). */
export function formatMessagePreview(content: Record<string, unknown>): string {
  const display = resolveDisplayBody(content);
  return display
    .replace(/`([^`\n]+)`/g, "$1")
    .replace(/\*\*([^*\n]+)\*\*/g, "$1")
    .replace(/(^|[\s(])\*([^*\n]+)\*(?=[\s).,!?:;]|$)/g, "$1$2")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

export function buildCallbackContent(
  data: string,
  messageEventId: string,
  token?: string | null,
): Record<string, string> {
  if (token) {
    return { token, message_id: messageEventId };
  }
  return { data, message_id: messageEventId };
}

export function buildCallbackEvent(
  data: string,
  messageEventId: string,
  token?: string | null,
) {
  return {
    eventType: AIOMATRIX_CALLBACK_EVENT_TYPE,
    content: buildCallbackContent(data, messageEventId, token),
  };
}

export function buildMiniAppDataContent(input: {
  data: string;
  queryId?: string | null;
  appId?: string | null;
  messageId?: string | null;
}): Record<string, unknown> {
  const body = humanizeStructuredPayload(input.data) ?? "MiniApp data";
  return {
    msgtype: "dev.aiomatrix.mini_app_data",
    body,
    "dev.aiomatrix.mini_app_data": {
      version: 1,
      data: input.data,
      ...(input.queryId ? { query_id: input.queryId } : {}),
      ...(input.appId ? { app_id: input.appId } : {}),
      ...(input.messageId ? { message_id: input.messageId } : {}),
    },
  };
}
