import type { IncomingMessage, ServerResponse } from "node:http";

import { MiniAppAuthError, type MiniAppServer } from "aiomatrix";
import { assertMiniAppPowerLive } from "aiomatrix/miniapp";

import { canViewRawAnswers, countRsvp, publicSummary } from "./engine.js";
import type { FormSpaceStore } from "./store.js";

const DEFAULT_CORS_ORIGIN = "https://testhighlife.strangled.net";

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
): (req: IncomingMessage, res: ServerResponse) => void {
  const inner = miniServer.nodeHandler();
  return (req, res) => {
    const url = readUrl(req);
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
            let power =
              typeof session.powerLevel === "number" ? session.powerLevel : 0;
            if (session.userId !== form.creatorId && form.policy !== "public") {
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
            }
            const allowed =
              session.userId === form.creatorId ||
              canViewRawAnswers(form, session.userId, power) ||
              form.policy === "public";
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
