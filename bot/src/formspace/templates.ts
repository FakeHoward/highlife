import { randomBytes } from "node:crypto";

import type { FormField, FormKind } from "./types.js";

function field(
  type: FormField["type"],
  label: string,
  extra: Partial<FormField> = {},
): FormField {
  return {
    id: `f_${randomBytes(3).toString("hex")}`,
    type,
    label,
    required: extra.required ?? true,
    options: extra.options,
    min: extra.min,
    max: extra.max,
  };
}

export function seedFields(kind: FormKind): FormField[] {
  switch (kind) {
    case "survey":
      return [
        field("text", "What should we improve?"),
        field("single", "How did you hear about us?", {
          options: ["Friend", "Matrix", "Telegram", "Other"],
        }),
        field("scale", "Overall satisfaction", { min: 1, max: 5 }),
      ];
    case "rsvp":
      return [
        field("single", "Attendance", {
          options: ["Going", "Maybe", "Can't make it"],
        }),
        field("text", "Comment (optional)", { required: false }),
      ];
    case "join":
      return [
        field("text", "How do you know this community?"),
        field("text", "Why do you want to join?"),
        field("single", "Preferred language", {
          options: ["English", "Русский", "Other"],
        }),
      ];
    case "onboard":
      return [
        field("single", "I accept the room rules", {
          options: ["Yes, I accept"],
        }),
        field("single", "Your role", {
          options: ["Member", "Organizer", "Guest"],
        }),
        field("multi", "Interests", {
          options: ["Events", "Dev", "Privacy", "Art", "Other"],
          required: false,
        }),
      ];
  }
}

export function defaultTitle(kind: FormKind): string {
  switch (kind) {
    case "survey":
      return "Community survey";
    case "rsvp":
      return "Event RSVP";
    case "join":
      return "Join request";
    case "onboard":
      return "Welcome onboarding";
  }
}

export function defaultDescription(kind: FormKind): string {
  switch (kind) {
    case "survey":
      return "Multi-step survey. Answers stay on this homeserver.";
    case "rsvp":
      return "Who is coming? Tap a button or open the form.";
    case "join":
      return "Fill this questionnaire before moderators invite you in.";
    case "onboard":
      return "Quick wizard after you join: rules, role, interests.";
  }
}
