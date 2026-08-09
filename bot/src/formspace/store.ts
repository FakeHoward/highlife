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

export const MAX_FORMS = 1_000;
export const MAX_RESPONSES_PER_FORM = 5_000;
export const MAX_RESPONSES_TOTAL = 50_000;
export const MAX_JOINS = 10_000;
export const MAX_ROOMS = 2_000;
export const MAX_FIELDS_PER_FORM = 50;
export const MAX_TITLE_CHARS = 200;
export const MAX_ANSWER_JSON_CHARS = 16_384;
export const MAX_DB_BYTES = 32 * 1024 * 1024;

export type StoreLimits = {
  maxForms: number;
  maxResponsesPerForm: number;
  maxResponsesTotal: number;
  maxJoins: number;
  maxRooms: number;
  maxFieldsPerForm: number;
  maxTitleChars: number;
  maxAnswerJsonChars: number;
  maxDbBytes: number;
};

export const DEFAULT_STORE_LIMITS: StoreLimits = {
  maxForms: MAX_FORMS,
  maxResponsesPerForm: MAX_RESPONSES_PER_FORM,
  maxResponsesTotal: MAX_RESPONSES_TOTAL,
  maxJoins: MAX_JOINS,
  maxRooms: MAX_ROOMS,
  maxFieldsPerForm: MAX_FIELDS_PER_FORM,
  maxTitleChars: MAX_TITLE_CHARS,
  maxAnswerJsonChars: MAX_ANSWER_JSON_CHARS,
  maxDbBytes: MAX_DB_BYTES,
};

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
  private readonly limits: StoreLimits;

  constructor(dataDir: string, salt?: string, limits?: Partial<StoreLimits>) {
    this.path = join(dataDir, "formspace.json");
    const trimmed = salt?.trim();
    this.salt = trimmed && trimmed.length > 0 ? trimmed : randomBytes(32).toString("hex");
    this.limits = { ...DEFAULT_STORE_LIMITS, ...limits };
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
    const payload = JSON.stringify(this.db, null, 2);
    if (Buffer.byteLength(payload, "utf8") > this.limits.maxDbBytes) {
      this.db = this.load();
      throw new Error("formspace storage limit exceeded (database size)");
    }
    const tmp = `${this.path}.${process.pid}.tmp`;
    writeFileSync(tmp, payload, "utf8");
    renameSync(tmp, this.path);
  }

  private assertFormShape(input: { title: string; fields: FormDefinition["fields"] }): void {
    if (input.title.length > this.limits.maxTitleChars) {
      throw new Error(
        `formspace storage limit exceeded (title max ${this.limits.maxTitleChars} chars)`,
      );
    }
    if (input.fields.length > this.limits.maxFieldsPerForm) {
      throw new Error(
        `formspace storage limit exceeded (max ${this.limits.maxFieldsPerForm} fields per form)`,
      );
    }
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
    this.assertFormShape(input);
    const existing = input.id ? this.getForm(input.id) : undefined;
    const stamp = now();
    if (existing) {
      Object.assign(existing, input, { updatedAt: stamp });
      this.persist();
      return existing;
    }
    if (this.db.forms.length >= this.limits.maxForms) {
      throw new Error(`formspace storage limit exceeded (max ${this.limits.maxForms} forms)`);
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
    const answerChars = JSON.stringify(input.answers).length;
    if (answerChars > this.limits.maxAnswerJsonChars) {
      throw new Error(
        `formspace storage limit exceeded (answer JSON max ${this.limits.maxAnswerJsonChars} chars)`,
      );
    }
    const existing = this.responseByUser(input.formId, input.userId);
    const stamp = now();
    if (existing) {
      existing.answers = input.answers;
      existing.updatedAt = stamp;
      if (!input.anonymous) existing.userId = input.userId;
      this.persist();
      return existing;
    }
    if (this.responsesFor(input.formId).length >= this.limits.maxResponsesPerForm) {
      throw new Error(
        `formspace storage limit exceeded (max ${this.limits.maxResponsesPerForm} responses per form)`,
      );
    }
    if (this.db.responses.length >= this.limits.maxResponsesTotal) {
      throw new Error(
        `formspace storage limit exceeded (max ${this.limits.maxResponsesTotal} responses total)`,
      );
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
    if (this.db.joins.length >= this.limits.maxJoins) {
      throw new Error(`formspace storage limit exceeded (max ${this.limits.maxJoins} joins)`);
    }
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
      if (this.db.rooms.length >= this.limits.maxRooms) {
        throw new Error(`formspace storage limit exceeded (max ${this.limits.maxRooms} rooms)`);
      }
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
