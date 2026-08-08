import type { FormDefinition, FormField, FormResponse, RsvpChoice } from "./types.js";
import type { FormSpaceStore } from "./store.js";

export function validateAnswers(
  form: FormDefinition,
  answers: Record<string, unknown>,
): string | null {
  for (const field of form.fields) {
    const value = answers[field.id];
    if (
      field.required &&
      (value === undefined ||
        value === null ||
        value === "" ||
        (Array.isArray(value) && value.length === 0))
    ) {
      return `Missing required field: ${field.label}`;
    }
    if (value === undefined || value === null || value === "") continue;
    const err = validateField(field, value);
    if (err) return err;
  }
  return null;
}

function validateField(field: FormField, value: unknown): string | null {
  switch (field.type) {
    case "text":
    case "date":
      if (typeof value !== "string") return `${field.label} must be text`;
      return null;
    case "number":
    case "scale": {
      const num = typeof value === "number" ? value : Number(value);
      if (!Number.isFinite(num)) return `${field.label} must be a number`;
      if (field.min != null && num < field.min) return `${field.label} is too low`;
      if (field.max != null && num > field.max) return `${field.label} is too high`;
      return null;
    }
    case "single":
      if (typeof value !== "string") return `${field.label} must be a single choice`;
      if (field.options && !field.options.includes(value)) return `Invalid choice for ${field.label}`;
      return null;
    case "multi":
      if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
        return `${field.label} must be a list of choices`;
      }
      if (field.options && value.some((item) => !field.options!.includes(item))) {
        return `Invalid choices for ${field.label}`;
      }
      return null;
  }
}

export function rsvpAnswers(choice: RsvpChoice, comment?: string): Record<string, unknown> {
  const label =
    choice === "going" ? "Going" : choice === "maybe" ? "Maybe" : "Can't make it";
  return {
    attendance: label,
    comment: comment?.trim() || "",
    _rsvp: choice,
  };
}

export function countRsvp(responses: FormResponse[]): Record<RsvpChoice, number> {
  const counts: Record<RsvpChoice, number> = { going: 0, maybe: 0, no: 0 };
  for (const response of responses) {
    const choice = response.answers._rsvp;
    if (choice === "going" || choice === "maybe" || choice === "no") counts[choice] += 1;
    else {
      const attendance = String(response.answers.attendance ?? "");
      if (attendance.startsWith("Going")) counts.going += 1;
      else if (attendance.startsWith("Maybe")) counts.maybe += 1;
      else counts.no += 1;
    }
  }
  return counts;
}

export function publicSummary(store: FormSpaceStore, form: FormDefinition): string {
  const responses = store.responsesFor(form.id);
  const lines = [
    `**${form.title}**`,
    form.description,
    "",
    `Status: ${form.status}`,
    `Responses: ${responses.length}`,
    `Policy: ${form.policy}${form.anonymous ? " · anonymous" : ""}`,
  ];
  if (form.deadlineMs) {
    lines.push(`Deadline: ${new Date(form.deadlineMs).toISOString()}`);
  }
  if (form.kind === "rsvp") {
    const counts = countRsvp(responses);
    lines.push("", `Going: ${counts.going} · Maybe: ${counts.maybe} · No: ${counts.no}`);
  } else {
    for (const field of form.fields.filter((item) => item.type === "single" || item.type === "scale")) {
      const tallies = new Map<string, number>();
      for (const response of responses) {
        const value = response.answers[field.id];
        if (value === undefined || value === null || value === "") continue;
        const key = String(value);
        tallies.set(key, (tallies.get(key) ?? 0) + 1);
      }
      if (tallies.size === 0) continue;
      lines.push("", `${field.label}:`);
      for (const [key, count] of [...tallies.entries()].sort((a, b) => b[1] - a[1])) {
        lines.push(`· ${key}: ${count}`);
      }
    }
  }
  return lines.join("\n");
}

export function formatPrivateAnswers(form: FormDefinition, response: FormResponse, userLabel: string): string {
  const lines = [`Answer from ${userLabel} on **${form.title}**:`, ""];
  for (const field of form.fields) {
    const value = response.answers[field.id] ?? response.answers[field.label] ?? "—";
    lines.push(`**${field.label}**: ${Array.isArray(value) ? value.join(", ") : String(value)}`);
  }
  if (response.answers.comment) lines.push(`**Comment**: ${String(response.answers.comment)}`);
  return lines.join("\n");
}

export function exportCsv(form: FormDefinition, responses: FormResponse[]): string {
  const headers = ["response_id", "user_id", "user_hash", "created_at", ...form.fields.map((field) => field.label)];
  const rows = responses.map((response) => {
    const cells = [
      response.id,
      response.userId ?? "",
      response.userHash ?? "",
      new Date(response.createdAt).toISOString(),
      ...form.fields.map((field) => {
        const value = response.answers[field.id];
        if (Array.isArray(value)) return value.join("|");
        return value == null ? "" : String(value);
      }),
    ];
    return cells.map(csvEscape).join(",");
  });
  return [headers.map(csvEscape).join(","), ...rows].join("\n");
}

function csvEscape(value: string): string {
  if (/[",\n]/.test(value)) return `"${value.replaceAll('"', '""')}"`;
  return value;
}

export function canViewRawAnswers(
  form: FormDefinition,
  viewerId: string,
  powerLevel: number,
): boolean {
  if (viewerId === form.creatorId) return true;
  if (form.policy === "private") return false;
  if (form.policy === "moderators") return powerLevel >= 50;
  // public
  return !form.anonymous || powerLevel >= 50;
}

export function normalizeBuilderFields(fields: FormField[]): FormField[] {
  return fields.map((field, index) => ({
    id: field.id || `f_${index + 1}`,
    type: field.type,
    label: field.label.trim(),
    required: Boolean(field.required),
    options: field.options?.map((option) => option.trim()).filter(Boolean),
    min: field.min,
    max: field.max,
  }));
}
