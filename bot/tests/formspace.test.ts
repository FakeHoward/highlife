import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { exportCsv, rsvpAnswers, validateAnswers } from "../src/formspace/engine.js";
import { FormSpaceStore } from "../src/formspace/store.js";
import { seedFields } from "../src/formspace/templates.js";

test("store enforces one response identity and join queue", () => {
  const dir = mkdtempSync(join(tmpdir(), "formspace-"));
  try {
    const store = new FormSpaceStore(dir);
    const form = store.upsertForm({
      roomId: "!room:example.org",
      creatorId: "@mod:example.org",
      kind: "join",
      title: "Join",
      description: "Gate",
      fields: seedFields("join"),
      policy: "moderators",
      anonymous: false,
      oneResponse: true,
      status: "open",
      deadlineMs: null,
      remindAtMs: null,
      targetRoomId: "!private:example.org",
      cardEventId: null,
    });
    const first = store.saveResponse({
      formId: form.id,
      userId: "@alice:example.org",
      answers: { [form.fields[0]!.id]: "friend" },
      anonymous: false,
    });
    const second = store.saveResponse({
      formId: form.id,
      userId: "@alice:example.org",
      answers: { [form.fields[0]!.id]: "updated" },
      anonymous: false,
    });
    assert.equal(first.id, second.id);
    assert.equal(store.responsesFor(form.id).length, 1);
    const join = store.createJoin(form.id, "@alice:example.org", second.id);
    assert.equal(store.pendingJoins(form.id).length, 1);
    store.setJoinStatus(join.id, "approved", "@mod:example.org");
    assert.equal(store.pendingJoins(form.id).length, 0);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("store rejects responses over maxResponsesPerForm", () => {
  const dir = mkdtempSync(join(tmpdir(), "formspace-cap-"));
  try {
    const store = new FormSpaceStore(dir, "test-salt", { maxResponsesPerForm: 2 });
    const form = store.upsertForm({
      roomId: "!room:example.org",
      creatorId: "@mod:example.org",
      kind: "survey",
      title: "Cap",
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
    store.saveResponse({
      formId: form.id,
      userId: "@a:example.org",
      answers: { [form.fields[0]!.id]: "one" },
      anonymous: false,
    });
    store.saveResponse({
      formId: form.id,
      userId: "@b:example.org",
      answers: { [form.fields[0]!.id]: "two" },
      anonymous: false,
    });
    assert.throws(
      () =>
        store.saveResponse({
          formId: form.id,
          userId: "@c:example.org",
          answers: { [form.fields[0]!.id]: "three" },
          anonymous: false,
        }),
      /max 2 responses per form/,
    );
    assert.equal(store.responsesFor(form.id).length, 2);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("engine validates fields and exports csv", () => {
  const fields = seedFields("survey");
  const form = {
    id: "form_1",
    roomId: "!r:x",
    creatorId: "@a:x",
    kind: "survey" as const,
    title: "Survey",
    description: "",
    fields,
    policy: "public" as const,
    anonymous: false,
    oneResponse: true,
    status: "open" as const,
    deadlineMs: null,
    remindAtMs: null,
    targetRoomId: null,
    cardEventId: null,
    createdAt: 1,
    updatedAt: 1,
  };
  assert.equal(validateAnswers(form, {}), `Missing required field: ${fields[0]!.label}`);
  const answers = {
    [fields[0]!.id]: "more bots",
    [fields[1]!.id]: "Matrix",
    [fields[2]!.id]: 5,
  };
  assert.equal(validateAnswers(form, answers), null);
  const csv = exportCsv(form, [
    {
      id: "r1",
      formId: form.id,
      userId: "@a:x",
      userHash: "abc",
      answers,
      createdAt: 1,
      updatedAt: 1,
    },
  ]);
  assert.match(csv, /more bots/);
  assert.deepEqual(rsvpAnswers("going", "hi")._rsvp, "going");
});
