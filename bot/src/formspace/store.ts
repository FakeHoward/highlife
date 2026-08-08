import { createHash, randomBytes } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import type {
  FormDefinition,
  FormKind,
  FormPolicy,
  FormResponse,
  FormSpaceDb,
  JoinRequest,
  JoinStatus,
  RoomSettings,
} from "./types.js";

const EMPTY: FormSpaceDb = { forms: [], responses: [], joins: [], rooms: [] };

function now(): number {
  return Date.now();
}

function id(prefix: string): string {
  return `${prefix}_${randomBytes(6).toString("hex")}`;
}

export function hashUser(userId: string, salt: string): string {
  return createHash("sha256").update(`${salt}:${userId}`).digest("hex").slice(0, 16);
}

export class FormSpaceStore {
  private db: FormSpaceDb;
  private readonly path: string;
  private readonly salt: string;

  constructor(dataDir: string, salt = "formspace") {
    this.path = join(dataDir, "formspace.json");
    this.salt = salt;
    mkdirSync(dirname(this.path), { recursive: true });
    this.db = this.load();
  }

  private load(): FormSpaceDb {
    try {
      const raw = readFileSync(this.path, "utf8");
      const parsed = JSON.parse(raw) as FormSpaceDb;
      return {
        forms: parsed.forms ?? [],
        responses: parsed.responses ?? [],
        joins: parsed.joins ?? [],
        rooms: parsed.rooms ?? [],
      };
    } catch {
      return structuredClone(EMPTY);
    }
  }

  private persist(): void {
    const tmp = `${this.path}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.db, null, 2), "utf8");
    renameSync(tmp, this.path);
  }

  listForms(roomId?: string): FormDefinition[] {
    return this.db.forms
      .filter((form) => (roomId ? form.roomId === roomId : true))
      .sort((a, b) => b.updatedAt - a.updatedAt);
  }

  getForm(formId: string): FormDefinition | undefined {
    return this.db.forms.find((form) => form.id === formId);
  }

  latestOpen(roomId: string, kind?: FormKind): FormDefinition | undefined {
    return this.listForms(roomId).find(
      (form) => form.status === "open" && (!kind || form.kind === kind),
    );
  }

  upsertForm(input: Omit<FormDefinition, "id" | "createdAt" | "updatedAt"> & { id?: string }): FormDefinition {
    const existing = input.id ? this.getForm(input.id) : undefined;
    const stamp = now();
    if (existing) {
      Object.assign(existing, input, { updatedAt: stamp });
      this.persist();
      return existing;
    }
    const form: FormDefinition = {
      ...input,
      id: input.id ?? id("form"),
      createdAt: stamp,
      updatedAt: stamp,
    };
    this.db.forms.push(form);
    this.persist();
    return form;
  }

  setFormStatus(formId: string, status: FormDefinition["status"]): FormDefinition | undefined {
    const form = this.getForm(formId);
    if (!form) return undefined;
    form.status = status;
    form.updatedAt = now();
    this.persist();
    return form;
  }

  setCardEventId(formId: string, cardEventId: string): void {
    const form = this.getForm(formId);
    if (!form) return;
    form.cardEventId = cardEventId;
    form.updatedAt = now();
    this.persist();
  }

  setPolicy(formId: string, policy: FormPolicy): FormDefinition | undefined {
    const form = this.getForm(formId);
    if (!form) return undefined;
    form.policy = policy;
    form.updatedAt = now();
    this.persist();
    return form;
  }

  setAnonymous(formId: string, anonymous: boolean): FormDefinition | undefined {
    const form = this.getForm(formId);
    if (!form) return undefined;
    form.anonymous = anonymous;
    form.updatedAt = now();
    this.persist();
    return form;
  }

  setDeadline(formId: string, deadlineMs: number | null, remindAtMs: number | null = null): FormDefinition | undefined {
    const form = this.getForm(formId);
    if (!form) return undefined;
    form.deadlineMs = deadlineMs;
    form.remindAtMs = remindAtMs;
    form.updatedAt = now();
    this.persist();
    return form;
  }

  responsesFor(formId: string): FormResponse[] {
    return this.db.responses.filter((response) => response.formId === formId);
  }

  responseByUser(formId: string, userId: string): FormResponse | undefined {
    const hash = hashUser(userId, this.salt);
    return this.db.responses.find(
      (response) =>
        response.formId === formId &&
        (response.userId === userId || response.userHash === hash),
    );
  }

  saveResponse(input: {
    formId: string;
    userId: string;
    answers: Record<string, unknown>;
    anonymous: boolean;
  }): FormResponse {
    const existing = this.responseByUser(input.formId, input.userId);
    const stamp = now();
    if (existing) {
      existing.answers = input.answers;
      existing.updatedAt = stamp;
      if (!input.anonymous) existing.userId = input.userId;
      this.persist();
      return existing;
    }
    const response: FormResponse = {
      id: id("resp"),
      formId: input.formId,
      userId: input.anonymous ? null : input.userId,
      userHash: hashUser(input.userId, this.salt),
      answers: input.answers,
      createdAt: stamp,
      updatedAt: stamp,
    };
    this.db.responses.push(response);
    this.persist();
    return response;
  }

  createJoin(formId: string, userId: string, responseId: string): JoinRequest {
    const existing = this.db.joins.find(
      (join) => join.formId === formId && join.userId === userId && join.status === "pending",
    );
    if (existing) return existing;
    const join: JoinRequest = {
      id: id("join"),
      formId,
      userId,
      responseId,
      status: "pending",
      moderatorId: null,
      note: null,
      createdAt: now(),
      updatedAt: now(),
    };
    this.db.joins.push(join);
    this.persist();
    return join;
  }

  getJoin(joinId: string): JoinRequest | undefined {
    return this.db.joins.find((join) => join.id === joinId);
  }

  setJoinStatus(joinId: string, status: JoinStatus, moderatorId: string, note?: string): JoinRequest | undefined {
    const join = this.getJoin(joinId);
    if (!join) return undefined;
    join.status = status;
    join.moderatorId = moderatorId;
    join.note = note ?? null;
    join.updatedAt = now();
    this.persist();
    return join;
  }

  pendingJoins(formId: string): JoinRequest[] {
    return this.db.joins.filter((join) => join.formId === formId && join.status === "pending");
  }

  getRoom(roomId: string): RoomSettings {
    let room = this.db.rooms.find((entry) => entry.roomId === roomId);
    if (!room) {
      room = { roomId, targetRoomId: null, onboardAuto: false, onboardFormId: null };
      this.db.rooms.push(room);
      this.persist();
    }
    return room;
  }

  setTargetRoom(roomId: string, targetRoomId: string | null): RoomSettings {
    const room = this.getRoom(roomId);
    room.targetRoomId = targetRoomId;
    this.persist();
    return room;
  }

  setOnboardAuto(roomId: string, enabled: boolean, formId: string | null = null): RoomSettings {
    const room = this.getRoom(roomId);
    room.onboardAuto = enabled;
    if (formId) room.onboardFormId = formId;
    this.persist();
    return room;
  }

  dueForReminder(nowMs = now()): FormDefinition[] {
    return this.db.forms.filter(
      (form) =>
        form.status === "open" &&
        form.remindAtMs != null &&
        form.remindAtMs <= nowMs &&
        (form.deadlineMs == null || form.deadlineMs > nowMs),
    );
  }

  dueForClose(nowMs = now()): FormDefinition[] {
    return this.db.forms.filter(
      (form) => form.status === "open" && form.deadlineMs != null && form.deadlineMs <= nowMs,
    );
  }

  clearRemind(formId: string): void {
    const form = this.getForm(formId);
    if (!form) return;
    form.remindAtMs = null;
    this.persist();
  }
}
