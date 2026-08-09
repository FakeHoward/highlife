import {
  Bot,
  Command,
  CommandHelp,
  F,
  InlineKeyboard,
  Router,
  createStates,
} from "aiomatrix";

import {
  builderChatFallbackKeyboard,
  formCardKeyboard,
  formCardText,
  joinModKeyboard,
  mainMenuKeyboard,
} from "./cards.js";
import {
  canManageForm,
  canPublishForms,
  canViewRawAnswers,
  exportCsv,
  formatPrivateAnswers,
  isFormInRoom,
  normalizeBuilderFields,
  publicSummary,
  rsvpAnswers,
  validateAnswers,
} from "./engine.js";
import { FormSpaceStore } from "./store.js";
import { defaultDescription, defaultTitle, seedFields } from "./templates.js";
import type { BuilderDraft, FillerPayload, FormKind, FormPolicy, RsvpChoice } from "./types.js";

type RoomActor = {
  roomId: string;
  senderId: string;
  reply: (text: string, options?: { keyboard?: InlineKeyboard }) => Promise<unknown>;
};

const Fill = createStates("fs_fill", ["form", "field"] as const);

function isKind(value: string): value is FormKind {
  return value === "survey" || value === "rsvp" || value === "join" || value === "onboard";
}

function parseRelativeDeadline(input: string): number | null {
  const trimmed = input.trim();
  if (!trimmed) return null;
  const iso = Date.parse(trimmed);
  if (Number.isFinite(iso)) return iso;
  const match = /^(\d+)\s*(m|min|h|d)$/i.exec(trimmed);
  if (!match) return null;
  const amount = Number(match[1]);
  const unit = match[2]!.toLowerCase();
  const mult = unit.startsWith("m") ? 60_000 : unit === "h" ? 3_600_000 : 86_400_000;
  return Date.now() + amount * mult;
}

export function createFormSpaceRouter(input: {
  bot: Bot;
  store: FormSpaceStore;
  miniAppUrl: string;
}): Router {
  const { bot, store, miniAppUrl } = input;
  const router = new Router("formspace");

  /** Best-effort command advertisement; needs PL ≥ state_default (usually 50). */
  async function tryAdvertiseCommands(roomId: string): Promise<boolean> {
    try {
      await bot.advertiseCommands(roomId);
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (message.includes("M_FORBIDDEN") || message.includes("send_level")) {
        console.warn(
          `advertiseCommands skipped in ${roomId} (bot needs moderator power for state events)`,
        );
        return false;
      }
      throw error;
    }
  }

  async function publishFormCard(formId: string): Promise<string | null> {
    const form = store.getForm(formId);
    if (!form) return null;
    const eventId = await bot.sendMessage(form.roomId, formCardText(store, form), {
      keyboard: formCardKeyboard(form, miniAppUrl),
    });
    store.setCardEventId(form.id, eventId);
    return eventId;
  }

  async function deliverResponse(formId: string, userId: string): Promise<void> {
    const form = store.getForm(formId);
    if (!form) return;
    const response = store.responseByUser(formId, userId);
    if (!response) return;

    if (form.policy === "public") {
      await bot.sendMessage(form.roomId, publicSummary(store, form));
    } else {
      await bot.sendMessage(form.roomId, `FormSpace: new response on **${form.title}** (${store.responsesFor(form.id).length} total).`);
      try {
        await bot.dm(
          form.creatorId,
          formatPrivateAnswers(form, response, form.anonymous ? "anonymous member" : userId),
        );
      } catch (error) {
        console.error("FormSpace private DM failed", error);
      }
    }

    if (form.kind === "join") {
      const join = store.createJoin(form.id, userId, response.id);
      await bot.sendMessage(
        form.roomId,
        `Join request from ${userId} for **${form.title}**.`,
        { keyboard: joinModKeyboard(join.id) },
      );
    }

    if (form.kind === "rsvp") {
      await bot.sendMessage(form.roomId, formCardText(store, form));
    }
  }

  async function openBuilder(ctx: RoomActor, kind: FormKind): Promise<void> {
    // aiomatrix aware profile: lean MiniApp card; chat actions on the card keyboard.
    await bot.sendMiniApp(ctx.roomId, {
      userId: ctx.senderId,
      title: `FormSpace builder · ${kind}`,
      description: "Design fields, privacy policy, and deadline — then publish to this room.",
      buttonText: "Open builder",
      appId: "formspace.app",
      startParam: `build:${kind}`,
      display: "sheet",
      url: miniAppUrl,
      includeLaunchKeyboard: false,
      includePlainLink: false,
      includeKeyboardFallback: false,
      keyboard: builderChatFallbackKeyboard(kind),
    });
  }

  async function publishFromTemplate(ctx: RoomActor, kind: FormKind): Promise<void> {
    const room = store.getRoom(ctx.roomId);
    const form = store.upsertForm({
      roomId: ctx.roomId,
      creatorId: ctx.senderId,
      kind,
      title: defaultTitle(kind),
      description: defaultDescription(kind),
      fields: seedFields(kind),
      policy: kind === "join" ? "moderators" : "public",
      anonymous: false,
      oneResponse: true,
      status: "open",
      deadlineMs: null,
      remindAtMs: null,
      targetRoomId: kind === "join" ? room.targetRoomId : null,
      cardEventId: null,
    });
    if (kind === "onboard") store.setOnboardAuto(ctx.roomId, true, form.id);
    await publishFormCard(form.id);
    await ctx.reply(`Published **${form.title}** (\`${form.id}\`).`);
  }

  router.message(
    Command(["start", "старт"], {
      description: "FormSpace welcome and scenario menu",
      category: "general",
    }),
    async (ctx) => {
      const advertised = await tryAdvertiseCommands(ctx.roomId);
      const lines = [
        "**FormSpace** — privacy-native forms inside Matrix.",
        "Survey · RSVP · Join request · Onboarding",
        "MiniApp builder/filler, chat FSM fallback, E2EE rooms, deadlines.",
        "Data stays on your homeserver — not Google or Telegram.",
      ];
      if (!advertised) {
        lines.push(
          "",
          "_Tip: give the bot moderator power (PL ≥ 50) so it can advertise slash commands in this room._",
        );
      }
      try {
        const eventId = await ctx.reply(lines.join("\n"), { keyboard: mainMenuKeyboard() });
        console.log(`/start reply ok room=${ctx.roomId} event=${String(eventId)}`);
      } catch (error) {
        console.error(`/start reply failed room=${ctx.roomId}`, error);
        throw error;
      }
    },
  );

  router.message(
    CommandHelp({ description: "FormSpace command help", category: "general" }),
    async (ctx) => {
      await ctx.replyHtml(
        bot.helpHtml({
          title: "FormSpace commands",
          scope: ctx.isDirect ? "direct" : "group",
          powerLevel: ctx.powerLevelOf(),
        }),
        { keyboard: mainMenuKeyboard() },
      );
    },
  );

  router.message(
    Command("form", {
      description: "FormSpace control: new|list|close|results|export|...",
      args: "<subcommand>",
      category: "forms",
    }),
    async (ctx) => {
      const [sub = "help", ...rest] = ctx.commandArgs.split(/\s+/).filter(Boolean);
      const arg = rest.join(" ");

      if (sub === "help") {
        await ctx.reply(
          [
            "/form new [survey|rsvp|join|onboard] — MiniApp builder",
            "/form list | close <id> | results <id> | export <id>",
            "/form policy <id> public|private|moderators",
            "/form anonymous <id> on|off",
            "/form deadline <id> <ISO|15m|2h|1d>",
            "/form chat [id] — answer in chat (FSM)",
            "/form target <roomId> — join-request destination",
            "/form onboard auto on|off",
          ].join("\n"),
        );
        return;
      }

      if (sub === "new") {
        const kind = isKind(rest[0] ?? "survey") ? (rest[0] as FormKind) : "survey";
        if (!canPublishForms(ctx.powerLevelOf())) {
          await ctx.reply("Need power level ≥ 50 to create forms.");
          return;
        }
        await openBuilder(ctx, kind);
        return;
      }

      if (sub === "list") {
        const forms = store.listForms(ctx.roomId);
        if (forms.length === 0) {
          await ctx.reply("No forms in this room yet. Try /form new survey");
          return;
        }
        await ctx.reply(
          forms
            .map((form) => `· \`${form.id}\` ${form.status} ${form.kind} — ${form.title}`)
            .join("\n"),
        );
        return;
      }

      if (sub === "close") {
        const form = store.getForm(arg);
        if (!isFormInRoom(form, ctx.roomId)) {
          await ctx.reply("Unknown form id.");
          return;
        }
        if (!canManageForm(form, ctx.senderId, ctx.powerLevelOf())) {
          await ctx.reply("Only the creator or a moderator can close this form.");
          return;
        }
        store.setFormStatus(form.id, "closed");
        await bot.sendMessage(form.roomId, publicSummary(store, form));
        await ctx.reply(`Closed ${form.id}`);
        return;
      }

      if (sub === "results") {
        const form = store.getForm(arg) ?? store.latestOpen(ctx.roomId);
        if (!form || form.roomId !== ctx.roomId) {
          await ctx.reply("Unknown form.");
          return;
        }
        await ctx.reply(publicSummary(store, form));
        if (canViewRawAnswers(form, ctx.senderId, ctx.powerLevelOf())) {
          await bot.sendMiniApp(ctx.roomId, {
            userId: ctx.senderId,
            title: `Results · ${form.title}`,
            description: "Detailed FormSpace results",
            buttonText: "Open results",
            appId: "formspace.app",
            startParam: `results:${form.id}`,
            display: "sheet",
            url: miniAppUrl,
            includeLaunchKeyboard: false,
            includePlainLink: false,
            includeKeyboardFallback: false,
          });
        }
        return;
      }

      if (sub === "export") {
        const form = store.getForm(arg);
        if (!form || form.roomId !== ctx.roomId) {
          await ctx.reply("Unknown form.");
          return;
        }
        if (!canViewRawAnswers(form, ctx.senderId, ctx.powerLevelOf())) {
          await ctx.reply("Not allowed to export raw answers for this policy.");
          return;
        }
        const csv = exportCsv(form, store.responsesFor(form.id));
        await bot.dm(ctx.senderId, `CSV export for ${form.title} (\`${form.id}\`):\n\`\`\`\n${csv}\n\`\`\``);
        await ctx.reply("CSV sent to your DM.");
        return;
      }

      if (sub === "policy") {
        const [formId, policy] = rest;
        const form = store.getForm(formId ?? "");
        if (!isFormInRoom(form, ctx.roomId)) {
          await ctx.reply("Usage: /form policy <id> public|private|moderators");
          return;
        }
        if (!canManageForm(form, ctx.senderId, ctx.powerLevelOf())) {
          await ctx.reply("Only the creator or a moderator can change policy.");
          return;
        }
        if (policy !== "public" && policy !== "private" && policy !== "moderators") {
          await ctx.reply("Policy must be public, private, or moderators.");
          return;
        }
        store.setPolicy(form.id, policy as FormPolicy);
        await ctx.reply(`Policy for ${form.id} → ${policy}`);
        return;
      }

      if (sub === "anonymous") {
        const [formId, flag] = rest;
        const form = store.getForm(formId ?? "");
        if (!isFormInRoom(form, ctx.roomId)) {
          await ctx.reply("Usage: /form anonymous <id> on|off");
          return;
        }
        if (!canManageForm(form, ctx.senderId, ctx.powerLevelOf())) {
          await ctx.reply("Only the creator or a moderator can change anonymity.");
          return;
        }
        store.setAnonymous(form.id, (flag ?? "").toLowerCase() === "on");
        await ctx.reply(`Anonymous ${form.id} → ${flag}`);
        return;
      }

      if (sub === "deadline") {
        const [formId, ...deadlineParts] = rest;
        const form = store.getForm(formId ?? "");
        const deadlineMs = parseRelativeDeadline(deadlineParts.join(" "));
        if (!isFormInRoom(form, ctx.roomId) || deadlineMs == null) {
          await ctx.reply("Usage: /form deadline <id> <ISO|15m|2h|1d>");
          return;
        }
        if (!canManageForm(form, ctx.senderId, ctx.powerLevelOf())) {
          await ctx.reply("Only the creator or a moderator can set a deadline.");
          return;
        }
        const remindAtMs = Math.max(Date.now() + 5_000, deadlineMs - 60_000);
        store.setDeadline(form.id, deadlineMs, remindAtMs);
        await ctx.reply(`Deadline set for ${form.id}: ${new Date(deadlineMs).toISOString()}`);
        return;
      }

      if (sub === "chat") {
        const form = (arg ? store.getForm(arg) : undefined) ?? store.latestOpen(ctx.roomId);
        if (!form || form.roomId !== ctx.roomId || form.status !== "open") {
          await ctx.reply("No open form to answer in chat.");
          return;
        }
        if (form.fields.length === 0) {
          await ctx.reply("This form has no fields.");
          return;
        }
        await ctx.state.setState(Fill.form);
        await ctx.state.updateData({ formId: form.id, index: 0, answers: {} });
        await ctx.state.setState(Fill.field);
        await ctx.reply(`Chat mode for **${form.title}**.\n${form.fields[0]!.label}`, {
          keyboard: fieldKeyboard(form.fields[0]!),
        });
        return;
      }

      if (sub === "target") {
        if (!canPublishForms(ctx.powerLevelOf())) {
          await ctx.reply("Need power level ≥ 50.");
          return;
        }
        if (!arg.startsWith("!")) {
          await ctx.reply("Usage: /form target !room:server");
          return;
        }
        store.setTargetRoom(ctx.roomId, arg);
        await ctx.reply(`Join-request target room → ${arg}`);
        return;
      }

      if (sub === "onboard" && rest[0] === "auto") {
        if (!canPublishForms(ctx.powerLevelOf())) {
          await ctx.reply("Need power level ≥ 50.");
          return;
        }
        const enabled = (rest[1] ?? "").toLowerCase() === "on";
        store.setOnboardAuto(ctx.roomId, enabled);
        await ctx.reply(`Onboarding auto → ${enabled ? "on" : "off"}`);
        return;
      }

      await ctx.reply("Unknown /form subcommand. Try /form help");
    },
  );

  router.message(
    Command("menu", { description: "FormSpace scenario menu", category: "general" }),
    async (ctx) => {
      await ctx.reply("Choose a FormSpace scenario:", { keyboard: mainMenuKeyboard() });
    },
  );

  router.message(
    Command(["echo", "say"], {
      description: "Echo arguments (aiomatrix demo)",
      args: "<text>",
      category: "tools",
    }),
    async (ctx) => {
      await ctx.reply(ctx.commandArgs || "Usage: /echo <text>");
    },
  );

  router.message(
    Command("typing", { description: "Typing indicator demo", category: "tools" }),
    async (ctx) => {
      await ctx.withTyping(async () => {
        await new Promise((resolve) => setTimeout(resolve, 350));
        await ctx.reply("Typing indicator completed.");
      });
    },
  );

  router.message(
    Command("media", { description: "Inspect the next attachment", category: "media" }),
    async (ctx) => {
      await ctx.reply("Send an image, video, audio clip or file; FormSpace will inspect it.");
    },
  );

  router.message(F.hasAttachment, async (ctx) => {
    const attachment = ctx.attachment;
    if (!attachment) return;
    const bytes = await ctx.downloadAttachment();
    await ctx.reply(
      [
        `Media: ${attachment.msgtype}`,
        `name: ${attachment.body}`,
        `mime: ${attachment.mimetype ?? "unknown"}`,
        `bytes: ${bytes.byteLength}`,
      ].join("\n"),
    );
  });

  router.message(Fill.field, F.text, async (ctx) => {
    const data = await ctx.state.getData<{
      formId?: string;
      index?: number;
      answers?: Record<string, unknown>;
    }>();
    const form = store.getForm(data.formId ?? "");
    if (!form || form.status !== "open" || !isFormInRoom(form, ctx.roomId)) {
      await ctx.state.clear();
      await ctx.reply("Form is no longer open.");
      return;
    }
    const index = data.index ?? 0;
    const field = form.fields[index];
    if (!field) {
      await ctx.state.clear();
      return;
    }
    const answers = { ...(data.answers ?? {}) };
    if (field.type === "multi") {
      answers[field.id] = ctx.text.split(",").map((part) => part.trim()).filter(Boolean);
    } else if (field.type === "number" || field.type === "scale") {
      answers[field.id] = Number(ctx.text);
    } else {
      answers[field.id] = ctx.text.trim();
    }
    const next = index + 1;
    if (next >= form.fields.length) {
      const error = validateAnswers(form, answers);
      if (error) {
        await ctx.reply(error);
        return;
      }
      if (form.oneResponse && store.responseByUser(form.id, ctx.senderId)) {
        // allow update
      }
      store.saveResponse({
        formId: form.id,
        userId: ctx.senderId,
        answers,
        anonymous: form.anonymous,
      });
      await ctx.state.clear();
      await ctx.react("👍");
      await ctx.reply("Thanks — response recorded.");
      await deliverResponse(form.id, ctx.senderId);
      return;
    }
    await ctx.state.updateData({ formId: form.id, index: next, answers });
    await ctx.reply(form.fields[next]!.label, { keyboard: fieldKeyboard(form.fields[next]!) });
  });

  router.callbackQuery(F.callback.startsWith("fs:"), async (ctx) => {
    const parts = ctx.callbackData.split(":");
    const action = parts[1];

    if (action === "new" && parts[2] && isKind(parts[2])) {
      if (!canPublishForms(ctx.powerLevelOf())) {
        await ctx.answerCallback({ text: "Need moderator power", alert: true });
        return;
      }
      await ctx.answerCallback({ text: `Builder: ${parts[2]}` });
      await openBuilder(ctx, parts[2]);
      return;
    }

    if (action === "template" && parts[2] && isKind(parts[2])) {
      if (!canPublishForms(ctx.powerLevelOf())) {
        await ctx.answerCallback({ text: "Need moderator power", alert: true });
        return;
      }
      await ctx.answerCallback({ text: "Publishing template" });
      await publishFromTemplate(ctx, parts[2]);
      return;
    }

    if (action === "chat" && parts[2]) {
      await ctx.answerCallback({ text: "Chat mode" });
      const form = store.getForm(parts[2]);
      if (!form || form.status !== "open" || !isFormInRoom(form, ctx.roomId)) {
        await ctx.reply("Form is closed.");
        return;
      }
      await ctx.state.setState(Fill.field);
      await ctx.state.updateData({ formId: form.id, index: 0, answers: {} });
      await ctx.reply(`Chat mode for **${form.title}**.\n${form.fields[0]?.label ?? ""}`, {
        keyboard: form.fields[0] ? fieldKeyboard(form.fields[0]) : undefined,
      });
      return;
    }

    if (action === "results" && parts[2]) {
      const form = store.getForm(parts[2]);
      if (!isFormInRoom(form, ctx.roomId)) {
        await ctx.answerCallback({ text: "Missing form", alert: true });
        return;
      }
      await ctx.answerCallback({ text: "Summary" });
      await ctx.reply(publicSummary(store, form));
      return;
    }

    if (action === "rsvp" && parts[2] && parts[3]) {
      const form = store.getForm(parts[2]);
      const choice = parts[3] as RsvpChoice;
      if (!form || form.status !== "open" || form.kind !== "rsvp" || !isFormInRoom(form, ctx.roomId)) {
        await ctx.answerCallback({ text: "RSVP closed", alert: true });
        return;
      }
      store.saveResponse({
        formId: form.id,
        userId: ctx.senderId,
        answers: rsvpAnswers(choice),
        anonymous: form.anonymous,
      });
      await ctx.answerCallback({
        text: `Marked ${choice}`,
        editText: formCardText(store, form),
        keyboard: formCardKeyboard(form, miniAppUrl),
      });
      return;
    }

    if (action === "join" && parts[2] && parts[3]) {
      const decision = parts[2];
      const join = store.getJoin(parts[3]);
      if (!join) {
        await ctx.answerCallback({ text: "Unknown request", alert: true });
        return;
      }
      const form = store.getForm(join.formId);
      if (!form) {
        await ctx.answerCallback({ text: "Missing form", alert: true });
        return;
      }
      if (!canManageForm(form, ctx.senderId, ctx.powerLevelOf())) {
        await ctx.answerCallback({ text: "Moderators only", alert: true });
        return;
      }
      if (decision === "ask") {
        await ctx.answerCallback({ text: "Ask more" });
        await bot.sendMessage(form.roomId, `${join.userId}: moderators need more detail on your join request.`);
        return;
      }
      if (decision === "deny") {
        store.setJoinStatus(join.id, "denied", ctx.senderId);
        await ctx.answerCallback({ text: "Denied", editText: `Join request from ${join.userId} denied.`, keyboard: null });
        return;
      }
      if (decision === "approve") {
        const target = form.targetRoomId ?? store.getRoom(form.roomId).targetRoomId;
        if (!target) {
          await ctx.answerCallback({
            text: "Set /form target !room:server first",
            alert: true,
          });
          return;
        }
        try {
          await bot.client.inviteUser(target, join.userId);
          store.setJoinStatus(join.id, "approved", ctx.senderId);
          await ctx.answerCallback({
            text: "Approved",
            editText: `Approved ${join.userId} → ${target}`,
            keyboard: null,
          });
        } catch (error) {
          console.error("Join invite failed", error);
          await ctx.answerCallback({
            text: "Invite failed — is the bot in the target room with invite power?",
            alert: true,
          });
        }
      }
    }
  });

  router.miniAppData(F.miniApp.app("formspace.app"), async (ctx) => {
    const payload = ctx.payload as BuilderDraft | FillerPayload | null;
    if (!payload || typeof payload !== "object" || !("action" in payload)) {
      await ctx.answerMiniAppQuery("FormSpace: unrecognized payload");
      return;
    }

    if (payload.action === "publish" || payload.action === "save_draft") {
      if (!canPublishForms(ctx.powerLevelOf())) {
        await ctx.answerMiniAppQuery("Need power level ≥ 50 to create forms.");
        return;
      }
      const draft = payload as BuilderDraft;
      if (!isKind(draft.kind)) {
        await ctx.answerMiniAppQuery("Invalid form kind");
        return;
      }
      const fields = normalizeBuilderFields(draft.fields ?? []);
      if (!draft.title?.trim() || fields.length === 0) {
        await ctx.answerMiniAppQuery("Title and at least one field are required");
        return;
      }
      const room = store.getRoom(ctx.roomId);
      const form = store.upsertForm({
        roomId: ctx.roomId,
        creatorId: ctx.senderId,
        kind: draft.kind,
        title: draft.title.trim(),
        description: (draft.description ?? defaultDescription(draft.kind)).trim(),
        fields,
        policy: draft.policy ?? (draft.kind === "join" ? "moderators" : "public"),
        anonymous: Boolean(draft.anonymous),
        oneResponse: draft.oneResponse !== false,
        status: payload.action === "publish" ? "open" : "draft",
        deadlineMs: draft.deadlineMs ?? null,
        remindAtMs:
          draft.deadlineMs != null ? Math.max(Date.now() + 5_000, draft.deadlineMs - 3_600_000) : null,
        targetRoomId: draft.targetRoomId ?? room.targetRoomId,
        cardEventId: null,
      });
      if (payload.action === "publish") {
        await publishFormCard(form.id);
        if (form.kind === "onboard") store.setOnboardAuto(ctx.roomId, true, form.id);
        await ctx.answerMiniAppQuery(`Published ${form.title}`);
      } else {
        await ctx.answerMiniAppQuery(`Draft saved ${form.id}`);
      }
      return;
    }

    if (payload.action === "submit" || payload.action === "rsvp") {
      const body = payload as FillerPayload;
      const form = store.getForm(body.formId);
      if (!form || form.status !== "open" || !isFormInRoom(form, ctx.roomId)) {
        await ctx.answerMiniAppQuery("Form is closed");
        return;
      }
      const answers =
        payload.action === "rsvp" && body.choice
          ? rsvpAnswers(body.choice, body.comment)
          : mapAnswers(form, body.answers ?? {});
      const error = form.kind === "rsvp" && body.choice ? null : validateAnswers(form, answers);
      if (error) {
        await ctx.answerMiniAppQuery(error);
        return;
      }
      store.saveResponse({
        formId: form.id,
        userId: ctx.senderId,
        answers,
        anonymous: form.anonymous,
      });
      await deliverResponse(form.id, ctx.senderId);
      await ctx.answerMiniAppQuery("Response recorded");
      return;
    }

    await ctx.answerMiniAppQuery("FormSpace: no handler");
  });

  router.editedMessage(F.text, async (ctx) => {
    await ctx.react("✏️");
  });

  router.reaction(F.reaction.key("👍", "❤️"), async (ctx) => {
    await ctx.reply(`Reaction ${ctx.key} noted.`);
  });

  router.membership(F.membership.joined, F.membership.isSelf, async (ctx) => {
    await tryAdvertiseCommands(ctx.roomId);
    await bot.sendMessage(
      ctx.roomId,
      "FormSpace online. Try /start — forms without Google or Telegram cloud.",
      { keyboard: mainMenuKeyboard() },
    );
  });

  router.membership(F.membership.joined, async (ctx) => {
    if (ctx.senderId === bot.selfId) return;
    const room = store.getRoom(ctx.roomId);
    if (!room.onboardAuto) return;
    const form =
      (room.onboardFormId ? store.getForm(room.onboardFormId) : undefined) ??
      store.latestOpen(ctx.roomId, "onboard");
    if (!form || form.status !== "open") return;
    await bot.sendMessage(
      ctx.roomId,
      `${ctx.senderId}: welcome! Complete onboarding for **${form.title}**.`,
      { keyboard: formCardKeyboard(form, miniAppUrl) },
    );
  });

  router.invite(F.membership.isSelf, async (ctx) => {
    await ctx.join();
  });

  return router;
}

function fieldKeyboard(field: { type: string; options?: string[] }): InlineKeyboard | undefined {
  if ((field.type === "single" || field.type === "multi") && field.options?.length) {
    const keyboard = new InlineKeyboard();
    field.options.forEach((option, index) => {
      if (index > 0 && index % 2 === 0) keyboard.row();
      keyboard.callback(option, `fs:noop`, "default");
    });
    // For chat FSM, users type answers; options are shown as hints via text.
    return undefined;
  }
  return undefined;
}

function mapAnswers(
  form: { fields: { id: string; label: string }[] },
  answers: Record<string, unknown>,
): Record<string, unknown> {
  const mapped: Record<string, unknown> = { ...answers };
  for (const field of form.fields) {
    if (mapped[field.id] === undefined && mapped[field.label] !== undefined) {
      mapped[field.id] = mapped[field.label];
    }
  }
  return mapped;
}

export async function tickDeadlines(bot: Bot, store: FormSpaceStore): Promise<void> {
  for (const form of store.dueForReminder()) {
    await bot.sendMessage(
      form.roomId,
      `Reminder: **${form.title}** closes at ${new Date(form.deadlineMs!).toLocaleString()}.`,
    );
    store.clearRemind(form.id);
  }
  for (const form of store.dueForClose()) {
    store.setFormStatus(form.id, "closed");
    await bot.sendMessage(form.roomId, publicSummary(store, form));
  }
}
