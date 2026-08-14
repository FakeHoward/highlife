export type FieldType = "text" | "single" | "multi" | "number" | "date" | "scale";
export type FormKind = "survey" | "rsvp" | "join" | "onboard";

export interface Field {
  id: string;
  type: FieldType;
  label: string;
  required: boolean;
  options?: string[];
  min?: number;
  max?: number;
}

export function parseStartParam(input: {
  search: string;
  bridgeParam?: string | null;
}): string {
  if (input.bridgeParam) return input.bridgeParam;
  const query = input.search.startsWith("?") ? input.search.slice(1) : input.search;
  return new URLSearchParams(query).get("start") ?? "build:survey";
}

export function seedFields(kind: FormKind, id: (prefix: string) => string): Field[] {
  if (kind === "rsvp") {
    return [
      { id: id("f"), type: "single", label: "Attendance", required: true, options: ["Going", "Maybe", "Can't make it"] },
      { id: id("f"), type: "text", label: "Comment (optional)", required: false },
    ];
  }
  if (kind === "join") {
    return [
      { id: id("f"), type: "text", label: "How do you know this community?", required: true },
      { id: id("f"), type: "text", label: "Why do you want to join?", required: true },
    ];
  }
  if (kind === "onboard") {
    return [
      { id: id("f"), type: "single", label: "I accept the room rules", required: true, options: ["Yes, I accept"] },
      { id: id("f"), type: "single", label: "Your role", required: true, options: ["Member", "Organizer", "Guest"] },
      { id: id("f"), type: "multi", label: "Interests", required: false, options: ["Events", "Dev", "Privacy", "Art"] },
    ];
  }
  return [
    { id: id("f"), type: "text", label: "What should we improve?", required: true },
    { id: id("f"), type: "single", label: "How did you hear about us?", required: true, options: ["Friend", "Matrix", "Telegram", "Other"] },
    { id: id("f"), type: "scale", label: "Overall satisfaction", required: true, min: 1, max: 5 },
  ];
}

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
