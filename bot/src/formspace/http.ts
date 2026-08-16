import type { IncomingMessage, ServerResponse } from "node:http";

import { MiniAppAuthError, type MiniAppServer } from "aiomatrix";
import { assertMiniAppPowerLive } from "aiomatrix/miniapp";

import { canViewRawAnswers, countRsvp, isFormInRoom, publicSummary } from "./engine.js";
import type { FormSpaceStore } from "./store.js";

const DEFAULT_CORS_ORIGIN = "";

const HTTP_RATE_LIMIT = 60;
const HTTP_RATE_WINDOW_MS = 60_000;
const HTTP_PUBLIC_GET_LIMIT = 30;
const HTTP_PUBLIC_GET_WINDOW_MS = 60_000;

export type MiniAppRateLimitOptions = {
  limit?: number;
  windowMs?: number;
  publicGetLimit?: number;
  publicGetWindowMs?: number;
  now?: () => number;
};

type RateBucket = { count: number; windowStart: number };

function readUrl(req: IncomingMessage): URL {
  return new URL(req.url ?? "/", "http://localhost");
}

function corsAllowlist(): string[] {
  const raw = process.env.MATRIX_MINIAPP_CORS_ORIGIN?.trim();
  const source = raw && raw.length > 0 ? raw : DEFAULT_CORS_ORIGIN;
  return source
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

/** Reflect Origin only when it is on the allowlist; otherwise use the primary origin. */
function resolveCorsOrigin(req: IncomingMessage): string {
  const allowlist = corsAllowlist();
  const primary = allowlist[0] ?? DEFAULT_CORS_ORIGIN;
  const originHeader = req.headers.origin;
  const origin = typeof originHeader === "string" ? originHeader.trim() : "";
  if (origin && allowlist.includes(origin)) {
    return origin;
  }
  return primary;
}

function sendJson(
  res: ServerResponse,
  status: number,
  body: unknown,
  req: IncomingMessage,
): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": resolveCorsOrigin(req),
    "access-control-allow-headers": "authorization, content-type",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    vary: "Origin",
  });
  res.end(payload);
}

function clientIp(req: IncomingMessage): string {
  const xff = req.headers["x-forwarded-for"];
  const raw = typeof xff === "string" ? xff : Array.isArray(xff) ? xff.join(",") : "";
  const hops = raw.split(",").map((part) => part.trim()).filter(Boolean);
  // Caddy appends the connecting client; the last hop is the trusted peer.
  if (hops.length > 0) return hops[hops.length - 1]!;
  return req.socket.remoteAddress ?? "unknown";
}

function rateLimitKey(req: IncomingMessage, includeAuthPrefix: boolean): string {
  const ip = clientIp(req);
  if (!includeAuthPrefix) return ip;
  const auth = req.headers.authorization;
  if (typeof auth === "string" && auth.length > 0) {
    return `${ip}|${auth.slice(0, 24)}`;
  }
  return ip;
}

function isPublicFormSchemaGet(req: IncomingMessage, url: URL): boolean {
  if (req.method !== "GET") return false;
  const parts = url.pathname.split("/").filter(Boolean);
  return parts.length === 2 && parts[0] === "forms";
}

function takeToken(
  buckets: Map<string, RateBucket>,
  key: string,
  limit: number,
  windowMs: number,
  nowMs: number,
): boolean {
  let bucket = buckets.get(key);
  if (!bucket || nowMs - bucket.windowStart >= windowMs) {
    bucket = { count: 0, windowStart: nowMs };
    buckets.set(key, bucket);
  }
  if (bucket.count >= limit) return false;
  bucket.count += 1;
  return true;
}

export function wrapMiniAppHandler(
  miniServer: MiniAppServer,
  store: FormSpaceStore,
  resolveRoomAuth: (
    userId: string,
    roomId: string,
  ) =>
    | { membership: string | null; powerLevel: number | null }
    | Promise<{ membership: string | null; powerLevel: number | null } | null>
    | null,
  rateLimit?: MiniAppRateLimitOptions,
): (req: IncomingMessage, res: ServerResponse) => void {
  const inner = miniServer.nodeHandler();
  const buckets = new Map<string, RateBucket>();
  const limit = rateLimit?.limit ?? HTTP_RATE_LIMIT;
  const windowMs = rateLimit?.windowMs ?? HTTP_RATE_WINDOW_MS;
  const publicGetLimit = rateLimit?.publicGetLimit ?? HTTP_PUBLIC_GET_LIMIT;
  const publicGetWindowMs = rateLimit?.publicGetWindowMs ?? HTTP_PUBLIC_GET_WINDOW_MS;
  const nowFn = rateLimit?.now ?? Date.now;

  return (req, res) => {
    const url = readUrl(req);
    const publicSchema = isPublicFormSchemaGet(req, url);
    const allowed = publicSchema
      ? takeToken(
          buckets,
          `pub:${rateLimitKey(req, false)}`,
          publicGetLimit,
          publicGetWindowMs,
          nowFn(),
        )
      : takeToken(
          buckets,
          `all:${rateLimitKey(req, true)}`,
          limit,
          windowMs,
          nowFn(),
        );
    if (!allowed) {
      sendJson(res, 429, { error: "rate_limited" }, req);
      return;
    }

    if (req.method === "OPTIONS") {
      sendJson(res, 204, {}, req);
      return;
    }

    if (req.method === "GET" && url.pathname.startsWith("/forms/")) {
      const parts = url.pathname.split("/").filter(Boolean);
      const formId = parts[1];
      const form = formId ? store.getForm(formId) : undefined;
      if (!form || (form.status === "draft" && parts[2] !== "results")) {
        sendJson(res, 404, { error: "form_not_found" }, req);
        return;
      }

      if (parts[2] === "results") {
        void (async () => {
          try {
            const session = miniServer.verify(req.headers.authorization);
            if (!session.roomId || !isFormInRoom(form, session.roomId)) {
              sendJson(res, 403, { error: "forbidden" }, req);
              return;
            }
            let power =
              typeof session.powerLevel === "number" ? session.powerLevel : 0;
            try {
              const fresh = await assertMiniAppPowerLive(session, 0, resolveRoomAuth);
              power =
                typeof fresh.powerLevel === "number" ? fresh.powerLevel : power;
            } catch (error) {
              if (error instanceof MiniAppAuthError) {
                sendJson(res, 403, { error: "forbidden" }, req);
                return;
              }
              throw error;
            }
            const allowed =
              session.userId === form.creatorId ||
              canViewRawAnswers(form, session.userId, power);
            if (!allowed) {
              sendJson(res, 403, { error: "forbidden" }, req);
              return;
            }
            const responses = store.responsesFor(form.id).map((response) => ({
              id: response.id,
              userId: form.anonymous ? null : response.userId,
              answers: response.answers,
              createdAt: response.createdAt,
            }));
            sendJson(
              res,
              200,
              {
                form: {
                  id: form.id,
                  title: form.title,
                  kind: form.kind,
                  policy: form.policy,
                  anonymous: form.anonymous,
                  status: form.status,
                  fields: form.fields,
                },
                summary: publicSummary(store, form),
                rsvp: form.kind === "rsvp" ? countRsvp(store.responsesFor(form.id)) : null,
                responses: form.policy === "public" && form.anonymous ? [] : responses,
              },
              req,
            );
          } catch {
            sendJson(res, 401, { error: "unauthorized" }, req);
          }
        })();
        return;
      }

      sendJson(
        res,
        200,
        {
          id: form.id,
          title: form.title,
          description: form.description,
          kind: form.kind,
          status: form.status,
          policy: form.policy,
          anonymous: form.anonymous,
          oneResponse: form.oneResponse,
          deadlineMs: form.deadlineMs,
          fields: form.fields,
        },
        req,
      );
      return;
    }

    inner(req, res);
  };
}
