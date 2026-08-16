import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  canManageForm,
  canPublishForms,
  isFormInRoom,
} from "../src/formspace/engine.js";
import { wrapMiniAppHandler } from "../src/formspace/http.js";
import { FormSpaceStore } from "../src/formspace/store.js";
import { seedFields } from "../src/formspace/templates.js";
import type { FormDefinition } from "../src/formspace/types.js";

function sampleForm(overrides: Partial<FormDefinition> = {}): FormDefinition {
  return {
    id: "form_authz",
    roomId: "!room:example.org",
    creatorId: "@mod:example.org",
    kind: "survey",
    title: "Survey",
    description: "",
    fields: seedFields("survey"),
    policy: "private",
    anonymous: false,
    oneResponse: true,
    status: "open",
    deadlineMs: null,
    remindAtMs: null,
    targetRoomId: null,
    cardEventId: null,
    createdAt: 1,
    updatedAt: 1,
    ...overrides,
  };
}

test("low-PL filler cannot publish or save_draft", () => {
  assert.equal(canPublishForms(0), false);
  assert.equal(canPublishForms(49), false);
  assert.equal(canPublishForms(50), true);
  assert.equal(canPublishForms(100), true);
});

test("policy/anon/deadline denied for non-creator low PL", () => {
  const form = sampleForm();
  const filler = "@alice:example.org";
  assert.equal(canManageForm(form, filler, 0), false);
  assert.equal(canManageForm(form, filler, 49), false);
  assert.equal(canManageForm(form, filler, 50), true);
  assert.equal(canManageForm(form, form.creatorId, 0), true);
});

test("submit from wrong room is rejected by room bind", () => {
  const form = sampleForm({ roomId: "!a:example.org" });
  assert.equal(isFormInRoom(form, "!a:example.org"), true);
  assert.equal(isFormInRoom(form, "!b:example.org"), false);
  assert.equal(isFormInRoom(undefined, "!a:example.org"), false);
});

test("results HTTP from wrong room session is 403", async () => {
  const dir = mkdtempSync(join(tmpdir(), "formspace-authz-"));
  try {
    const store = new FormSpaceStore(dir, "test-salt");
    const form = store.upsertForm({
      roomId: "!home:example.org",
      creatorId: "@mod:example.org",
      kind: "survey",
      title: "Private survey",
      description: "secrets",
      fields: seedFields("survey"),
      policy: "private",
      anonymous: false,
      oneResponse: true,
      status: "open",
      deadlineMs: null,
      remindAtMs: null,
      targetRoomId: null,
      cardEventId: null,
    });
    store.saveResponse({
      formId: form.id,
      userId: "@alice:example.org",
      answers: { [form.fields[0]!.id]: "leak-me" },
      anonymous: false,
    });

    const miniServer = {
      verify: () => ({
        userId: "@mod:example.org",
        roomId: "!other:example.org",
        powerLevel: 100,
      }),
      nodeHandler: () => (_req: IncomingMessage, res: ServerResponse) => {
        res.writeHead(404);
        res.end();
      },
    };

    const handler = wrapMiniAppHandler(miniServer as never, store, () => ({
      membership: "join",
      powerLevel: 100,
    }));

    const server = createServer(handler);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    assert.ok(address && typeof address === "object");
    const port = address.port;

    try {
      const res = await fetch(`http://127.0.0.1:${port}/forms/${form.id}/results`, {
        headers: { authorization: "Bearer test" },
      });
      assert.equal(res.status, 403);
      const body = (await res.json()) as { error?: string };
      assert.equal(body.error, "forbidden");
    } finally {
      await new Promise<void>((resolve, reject) =>
        server.close((err) => (err ? reject(err) : resolve())),
      );
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("public unauthenticated GET form is schema-only (no aggregates)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "formspace-public-"));
  try {
    const store = new FormSpaceStore(dir, "test-salt");
    const form = store.upsertForm({
      roomId: "!home:example.org",
      creatorId: "@mod:example.org",
      kind: "survey",
      title: "Public fill",
      description: "ok to fill",
      fields: seedFields("survey"),
      policy: "private",
      anonymous: false,
      oneResponse: true,
      status: "open",
      deadlineMs: null,
      remindAtMs: null,
      targetRoomId: null,
      cardEventId: null,
    });
    store.saveResponse({
      formId: form.id,
      userId: "@alice:example.org",
      answers: { [form.fields[0]!.id]: "secret-answer" },
      anonymous: false,
    });

    const miniServer = {
      verify: () => {
        throw new Error("should not verify for public schema GET");
      },
      nodeHandler: () => (_req: IncomingMessage, res: ServerResponse) => {
        res.writeHead(404);
        res.end();
      },
    };

    const handler = wrapMiniAppHandler(miniServer as never, store, () => null);
    const server = createServer(handler);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    assert.ok(address && typeof address === "object");

    try {
      const res = await fetch(`http://127.0.0.1:${address.port}/forms/${form.id}`);
      assert.equal(res.status, 200);
      const body = (await res.json()) as Record<string, unknown>;
      assert.equal(body.id, form.id);
      assert.equal(body.title, "Public fill");
      assert.ok(Array.isArray(body.fields));
      assert.equal("responses" in body, false);
      assert.equal("summary" in body, false);
      assert.equal("rsvp" in body, false);
      assert.equal("creatorId" in body, false);
      const serialized = JSON.stringify(body);
      assert.equal(serialized.includes("secret-answer"), false);
    } finally {
      await new Promise<void>((resolve, reject) =>
        server.close((err) => (err ? reject(err) : resolve())),
      );
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("HTTP rate limit returns 429", async () => {
  const dir = mkdtempSync(join(tmpdir(), "formspace-rate-"));
  try {
    const store = new FormSpaceStore(dir, "test-salt");
    const form = store.upsertForm({
      roomId: "!home:example.org",
      creatorId: "@mod:example.org",
      kind: "survey",
      title: "Rate",
      description: "",
      fields: seedFields("survey"),
      policy: "public",
      anonymous: false,
      oneResponse: true,
      status: "open",
      deadlineMs: null,
      remindAtMs: null,
      targetRoomId: null,
      cardEventId: null,
    });

    const miniServer = {
      verify: () => {
        throw new Error("unused");
      },
      nodeHandler: () => (_req: IncomingMessage, res: ServerResponse) => {
        res.writeHead(404);
        res.end();
      },
    };

    const handler = wrapMiniAppHandler(miniServer as never, store, () => null, {
      publicGetLimit: 2,
      publicGetWindowMs: 60_000,
    });
    const server = createServer(handler);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    assert.ok(address && typeof address === "object");
    const previousCors = process.env.MATRIX_MINIAPP_CORS_ORIGIN;
    process.env.MATRIX_MINIAPP_CORS_ORIGIN = "https://example.org";

    try {
      const url = `http://127.0.0.1:${address.port}/forms/${form.id}`;
      const first = await fetch(url);
      const second = await fetch(url);
      const third = await fetch(url);
      assert.equal(first.status, 200);
      assert.equal(second.status, 200);
      assert.equal(third.status, 429);
      const body = (await third.json()) as { error?: string };
      assert.equal(body.error, "rate_limited");
      assert.equal(third.headers.get("access-control-allow-origin"), "https://example.org");
    } finally {
      if (previousCors === undefined) delete process.env.MATRIX_MINIAPP_CORS_ORIGIN;
      else process.env.MATRIX_MINIAPP_CORS_ORIGIN = previousCors;
      await new Promise<void>((resolve, reject) =>
        server.close((err) => (err ? reject(err) : resolve())),
      );
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("store does not use hardcoded formspace salt by default", () => {
  const dir = mkdtempSync(join(tmpdir(), "formspace-salt-"));
  try {
    const a = new FormSpaceStore(dir);
    const b = new FormSpaceStore(dir, "explicit-salt");
    const form = a.upsertForm({
      roomId: "!r:x",
      creatorId: "@a:x",
      kind: "survey",
      title: "T",
      description: "",
      fields: seedFields("survey"),
      policy: "public",
      anonymous: true,
      oneResponse: true,
      status: "open",
      deadlineMs: null,
      remindAtMs: null,
      targetRoomId: null,
      cardEventId: null,
    });
    const respA = a.saveResponse({
      formId: form.id,
      userId: "@u:x",
      answers: { [form.fields[0]!.id]: "x" },
      anonymous: true,
    });
    // Same user + different salt must not share the default public string identity.
    assert.notEqual(respA.userHash, "formspace");
    const hashExplicit = b.responseByUser(form.id, "@u:x");
    // b uses a different salt against a's persisted hash — lookup by hash fails.
    assert.equal(hashExplicit, undefined);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
