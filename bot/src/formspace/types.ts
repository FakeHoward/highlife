export type FormKind = "survey" | "rsvp" | "join" | "onboard";
export type FormPolicy = "public" | "private" | "moderators";
export type FormStatus = "draft" | "open" | "closed";
export type FieldType = "text" | "single" | "multi" | "number" | "date" | "scale";
export type JoinStatus = "pending" | "approved" | "denied";
export type RsvpChoice = "going" | "maybe" | "no";

export interface FormField {
  id: string;
  type: FieldType;
  label: string;
  required: boolean;
  options?: string[];
  min?: number;
  max?: number;
}

export interface FormDefinition {
  id: string;
  roomId: string;
  creatorId: string;
  kind: FormKind;
  title: string;
  description: string;
  fields: FormField[];
  policy: FormPolicy;
  anonymous: boolean;
  oneResponse: boolean;
  status: FormStatus;
  deadlineMs: number | null;
  remindAtMs: number | null;
  targetRoomId: string | null;
  cardEventId: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface FormResponse {
  id: string;
  formId: string;
  userId: string | null;
  userHash: string | null;
  answers: Record<string, unknown>;
  createdAt: number;
  updatedAt: number;
}

export interface JoinRequest {
  id: string;
  formId: string;
  userId: string;
  responseId: string;
  status: JoinStatus;
  moderatorId: string | null;
  note: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface RoomSettings {
  roomId: string;
  targetRoomId: string | null;
  onboardAuto: boolean;
  onboardFormId: string | null;
}

export interface FormSpaceDb {
  forms: FormDefinition[];
  responses: FormResponse[];
  joins: JoinRequest[];
  rooms: RoomSettings[];
}

export interface BuilderDraft {
  action: "publish" | "save_draft";
  kind: FormKind;
  title: string;
  description?: string;
  fields: FormField[];
  policy?: FormPolicy;
  anonymous?: boolean;
  oneResponse?: boolean;
  deadlineMs?: number | null;
  targetRoomId?: string | null;
}

export interface FillerPayload {
  action: "submit" | "rsvp";
  formId: string;
  answers?: Record<string, unknown>;
  choice?: RsvpChoice;
  comment?: string;
}
