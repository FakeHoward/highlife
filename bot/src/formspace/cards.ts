import { InlineKeyboard } from "aiomatrix";

import { countRsvp } from "./engine.js";
import type { FormSpaceStore } from "./store.js";
import type { FormDefinition } from "./types.js";

export function formCardText(store: FormSpaceStore, form: FormDefinition): string {
  const count = store.responsesFor(form.id).length;
  const deadline = form.deadlineMs
    ? `Deadline: ${new Date(form.deadlineMs).toLocaleString()}`
    : "No deadline";
  const lines = [
    `**FormSpace · ${form.kind.toUpperCase()}**`,
    `**${form.title}**`,
    form.description,
    "",
    `${deadline} · Responses: ${count} · Policy: ${form.policy}${form.anonymous ? " · anonymous" : ""}`,
  ];
  if (form.kind === "rsvp") {
    const counts = countRsvp(store.responsesFor(form.id));
    lines.push(`Going ${counts.going} · Maybe ${counts.maybe} · No ${counts.no}`);
  }
  if (form.status === "closed") lines.push("", "_This form is closed._");
  return lines.join("\n");
}

export function formCardKeyboard(form: FormDefinition, miniAppUrl: string): InlineKeyboard {
  const fillParam = `fill:${form.id}`;
  const resultsParam = `results:${form.id}`;
  const keyboard = new InlineKeyboard()
    .miniApp("Open form", miniAppUrl, fillParam, "primary")
    .callback("Answer in chat", `fs:chat:${form.id}`, "default")
    .callback("Results", `fs:results:${form.id}`, "link");

  if (form.kind === "rsvp" && form.status === "open") {
    keyboard
      .row()
      .callback("Going", `fs:rsvp:${form.id}:going`, "primary")
      .callback("Maybe", `fs:rsvp:${form.id}:maybe`, "default")
      .callback("No", `fs:rsvp:${form.id}:no`, "danger");
  }

  keyboard.row().miniApp("Results MiniApp", miniAppUrl, resultsParam, "link");
  return keyboard;
}

/** Extra rows under the builder MiniApp card (no second Open mini_app button). */
export function builderChatFallbackKeyboard(kind: string): InlineKeyboard {
  return new InlineKeyboard()
    .callback("Use template", `fs:template:${kind}`, "default")
    .command("Help", "/form help");
}

export function mainMenuKeyboard(): InlineKeyboard {
  return new InlineKeyboard()
    .callback("Survey", "fs:new:survey", "primary")
    .callback("RSVP", "fs:new:rsvp", "primary")
    .row()
    .callback("Join request", "fs:new:join", "default")
    .callback("Onboarding", "fs:new:onboard", "default")
    .row()
    .command("Help", "/help")
    .command("Forms", "/form list");
}

export function joinModKeyboard(joinId: string): InlineKeyboard {
  return new InlineKeyboard()
    .callback("Approve", `fs:join:approve:${joinId}`, "primary")
    .callback("Deny", `fs:join:deny:${joinId}`, "danger")
    .callback("Ask more", `fs:join:ask:${joinId}`, "default");
}
