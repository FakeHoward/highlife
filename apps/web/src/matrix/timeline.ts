import type {
  DeliveryStatus,
  MediaDescriptor,
  MessageKind,
  PollDescriptor,
  ReactionSummary,
  TimelineItem,
} from "@highlife/ui-contracts";
import { readStoredLocale, translate, type MessageKey, type MessageParams } from "../i18n/messages";
import { resolveDisplayBody } from "../protocol/aiomatrix";
import { encryptedFileFromContent } from "./encryptedMedia";
import {
  isPollEndType,
  isPollResponseType,
  isPollStartType,
  parsePollResponseAnswers,
  parsePollStartContent,
  pollRelationEventId,
  tallyPollVotes,
} from "./polls";

export interface RawTimelineEvent {
  eventId: string;
  type: string;
  sender: string;
  timestamp: number;
  content: Record<string, unknown>;
  redacted?: boolean;
  status?: DeliveryStatus | null;
}

interface NormalizeContext {
  roomId: string;
  ownUserId: string;
  memberNames: Record<string, string>;
  memberAvatars?: Record<string, string>;
}

type Relation = {
  rel_type?: string;
  event_id?: string;
  key?: string;
  is_falling_back?: boolean;
  "m.in_reply_to"?: { event_id?: string };
};

const SYSTEM_TYPES = new Set([
  "m.room.member",
  "m.room.name",
  "m.room.topic",
  "m.room.avatar",
  "m.room.pinned_events",
  "m.room.encryption",
  "m.room.canonical_alias",
  "m.space.child",
  "m.space.parent",
]);

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function text(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function miniAppDataish(content: Record<string, unknown>): boolean {
  return (
    content.msgtype === "dev.aiomatrix.mini_app_data" ||
    Boolean(content["dev.aiomatrix.mini_app_data"])
  );
}

function relation(content: Record<string, unknown>): Relation {
  return record(content["m.relates_to"]) as Relation;
}

function kindFor(msgtype?: string): MessageKind {
  if (msgtype === "m.image") return "image";
  if (msgtype === "m.video") return "video";
  if (msgtype === "m.audio") return "audio";
  if (msgtype === "m.file") return "file";
  if (msgtype === "m.notice") return "notice";
  return "text";
}

function mediaFor(content: Record<string, unknown>): MediaDescriptor | undefined {
  const encrypted = encryptedFileFromContent(content);
  const mxcUrl = encrypted?.url ?? text(content.url);
  if (!mxcUrl?.startsWith("mxc://")) return undefined;
  const info = record(content.info);
  return {
    mxcUrl,
    name: text(content.body) ?? "Attachment",
    ...(text(info.mimetype) ? { mimeType: text(info.mimetype) } : {}),
    ...(typeof info.size === "number" ? { size: info.size } : {}),
    ...(typeof info.w === "number" ? { width: info.w } : {}),
    ...(typeof info.h === "number" ? { height: info.h } : {}),
    ...(encrypted
      ? {
          encrypted: {
            mxcUrl,
            key: encrypted.key as Record<string, unknown>,
            iv: encrypted.iv,
            sha256: encrypted.hashes.sha256,
            v: encrypted.v,
          },
        }
      : {}),
  };
}

function t(key: MessageKey, params?: MessageParams): string {
  return translate(readStoredLocale(), key, params);
}

function systemBody(event: RawTimelineEvent, names: Record<string, string>): string {
  const content = event.content;
  const sender = names[event.sender] ?? event.sender;
  if (event.type === "m.room.member") {
    const membership = text(content.membership) ?? "join";
    const target = text(content.displayname) ?? event.eventId;
    if (membership === "join") return t("timeline.systemJoined", { name: sender });
    if (membership === "leave") return t("timeline.systemLeft", { name: sender });
    if (membership === "invite") return t("timeline.systemInvited", { name: sender, target });
    if (membership === "ban") return t("timeline.systemBanned", { name: sender });
    if (membership === "knock") return t("timeline.systemKnock", { name: sender });
    return t("timeline.systemMembership", { name: sender, membership });
  }
  if (event.type === "m.room.name") {
    const name = text(content.name);
    return name
      ? t("timeline.systemRenamed", { name: sender, roomName: name })
      : t("timeline.systemNameCleared", { name: sender });
  }
  if (event.type === "m.room.topic") {
    const topic = text(content.topic);
    return topic
      ? t("timeline.systemTopicSet", { name: sender })
      : t("timeline.systemTopicCleared", { name: sender });
  }
  if (event.type === "m.room.encryption") return t("timeline.systemEncryption", { name: sender });
  if (event.type === "m.room.avatar") return t("timeline.systemAvatar", { name: sender });
  if (event.type === "m.room.canonical_alias") {
    const alias = text(content.alias);
    return alias
      ? t("timeline.systemAliasSet", { name: sender, alias })
      : t("timeline.systemAliasCleared", { name: sender });
  }
  if (event.type === "m.space.child") return t("timeline.systemSpace", { name: sender });
  return t("timeline.systemState", { name: sender });
}

export function normalizeTimeline(
  events: RawTimelineEvent[],
  context: NormalizeContext,
): TimelineItem[] {
  const edits = new Map<string, RawTimelineEvent>();
  const reactions = new Map<
    string,
    Map<string, { senders: Set<string>; ownEventId?: string }>
  >();
  const pollResponses = new Map<
    string,
    Array<{ senderId: string; timestamp: number; answers: string[] }>
  >();
  const endedPolls = new Set<string>();

  for (const event of events) {
    if (event.redacted) continue;
    const rel = relation(event.content);
    if (rel.rel_type === "m.replace" && rel.event_id) edits.set(rel.event_id, event);
    if (event.type === "m.reaction" && rel.rel_type === "m.annotation" && rel.event_id && rel.key) {
      const grouped = reactions.get(rel.event_id) ?? new Map();
      const current = grouped.get(rel.key) ?? { senders: new Set<string>() };
      current.senders.add(event.sender);
      if (event.sender === context.ownUserId) {
        current.ownEventId = event.eventId;
      }
      grouped.set(rel.key, current);
      reactions.set(rel.event_id, grouped);
    }
    if (isPollResponseType(event.type)) {
      const pollId = pollRelationEventId(event.content);
      if (!pollId) continue;
      const list = pollResponses.get(pollId) ?? [];
      list.push({
        senderId: event.sender,
        timestamp: event.timestamp,
        answers: parsePollResponseAnswers(event.content),
      });
      pollResponses.set(pollId, list);
    }
    if (isPollEndType(event.type)) {
      const pollId = pollRelationEventId(event.content);
      if (pollId) endedPolls.add(pollId);
    }
  }
  const eventIndex = new Map(events.map((event) => [event.eventId, event]));

  return events
    .filter((event) => {
      if (event.type === "m.room.encrypted") return true;
      if (isPollStartType(event.type)) return true;
      if (SYSTEM_TYPES.has(event.type)) return true;
      if (event.type !== "m.room.message") return false;
      return relation(event.content).rel_type !== "m.replace";
    })
    .map((event): TimelineItem => {
      if (event.type === "m.room.encrypted") {
        return {
          eventId: event.eventId,
          roomId: context.roomId,
          senderId: event.sender,
          senderName: context.memberNames[event.sender] ?? event.sender,
          ...(context.memberAvatars?.[event.sender]
            ? { senderAvatarUrl: context.memberAvatars[event.sender] }
            : {}),
          timestamp: event.timestamp,
          body: t("timeline.decryptFailed"),
          kind: "notice",
          isOwn: event.sender === context.ownUserId,
          edited: false,
          redacted: Boolean(event.redacted),
          reactions: [],
          rawContent: event.content,
          ...(event.status ? { deliveryStatus: event.status } : {}),
        };
      }

      if (SYSTEM_TYPES.has(event.type)) {
        return {
          eventId: event.eventId,
          roomId: context.roomId,
          senderId: event.sender,
          senderName: context.memberNames[event.sender] ?? event.sender,
          ...(context.memberAvatars?.[event.sender]
            ? { senderAvatarUrl: context.memberAvatars[event.sender] }
            : {}),
          timestamp: event.timestamp,
          body: systemBody(event, context.memberNames),
          kind: "system",
          isOwn: false,
          edited: false,
          redacted: false,
          reactions: [],
          rawContent: event.content,
        };
      }

      if (isPollStartType(event.type)) {
        const start = parsePollStartContent(event.content);
        const valid = new Set(start?.answers.map((a) => a.id) ?? []);
        const tally = tallyPollVotes({
          responses: pollResponses.get(event.eventId) ?? [],
          validAnswerIds: valid,
          maxSelections: start?.maxSelections ?? 1,
          ownUserId: context.ownUserId,
          ended: endedPolls.has(event.eventId),
        });
        const poll: PollDescriptor | undefined = start
          ? {
              question: start.question,
              answers: start.answers,
              maxSelections: start.maxSelections,
              disclosed: start.disclosed,
              ended: tally.ended,
              counts: tally.counts,
              mySelections: tally.mySelections,
              totalVoters: tally.totalVoters,
            }
          : undefined;
        return {
          eventId: event.eventId,
          roomId: context.roomId,
          senderId: event.sender,
          senderName: context.memberNames[event.sender] ?? event.sender,
          ...(context.memberAvatars?.[event.sender]
            ? { senderAvatarUrl: context.memberAvatars[event.sender] }
            : {}),
          timestamp: event.timestamp,
          body: start?.question ?? text(event.content.body) ?? "Poll",
          kind: "poll",
          isOwn: event.sender === context.ownUserId,
          edited: false,
          redacted: Boolean(event.redacted),
          reactions: [...(reactions.get(event.eventId)?.entries() ?? [])].map(([key, item]) => ({
            key,
            count: item.senders.size,
            reactedByMe: Boolean(item.ownEventId),
            ...(item.ownEventId ? { ownEventId: item.ownEventId } : {}),
          })),
          ...(poll ? { poll } : {}),
          rawContent: event.content,
          ...(event.status ? { deliveryStatus: event.status } : {}),
        };
      }

      const originalRelation = relation(event.content);
      const edit = edits.get(event.eventId);
      const editedContent = edit ? record(edit.content["m.new_content"]) : event.content;
      const redacted = Boolean(event.redacted);
      const reactionList: ReactionSummary[] = [...(reactions.get(event.eventId)?.entries() ?? [])]
        .map(([key, item]) => ({
          key,
          count: item.senders.size,
          reactedByMe: Boolean(item.ownEventId),
          ...(item.ownEventId ? { ownEventId: item.ownEventId } : {}),
        }));
      const msgtype = text(editedContent.msgtype);
      const item: TimelineItem = {
        eventId: event.eventId,
        roomId: context.roomId,
        senderId: event.sender,
        senderName: context.memberNames[event.sender] ?? event.sender,
        ...(context.memberAvatars?.[event.sender]
          ? { senderAvatarUrl: context.memberAvatars[event.sender] }
          : {}),
        timestamp: event.timestamp,
        body: redacted ? t("timeline.messageRemoved") : resolveDisplayBody(editedContent),
        kind: kindFor(msgtype),
        isOwn: event.sender === context.ownUserId,
        edited: Boolean(edit),
        redacted,
        reactions: reactionList,
        rawContent: event.content,
        ...(event.status ? { deliveryStatus: event.status } : {}),
      };
      const formatted = text(editedContent.formatted_body);
      if (!redacted && formatted && !miniAppDataish(editedContent)) {
        item.formattedBody = formatted;
      }
      const reply = originalRelation["m.in_reply_to"]?.event_id
        ?? (originalRelation.rel_type === "m.thread" ? originalRelation.event_id : undefined);
      if (reply) {
        item.replyToEventId = reply;
        const target = eventIndex.get(reply);
        if (target) {
          const targetEdit = edits.get(reply);
          const targetContent = targetEdit
            ? record(targetEdit.content["m.new_content"])
            : target.content;
          item.replyPreview = {
            senderId: target.sender,
            senderName: context.memberNames[target.sender] ?? target.sender,
            body: target.redacted
              ? t("timeline.messageRemoved")
              : resolveDisplayBody(targetContent) || t("timeline.attachment"),
          };
        }
      }
      const media = redacted ? undefined : mediaFor(editedContent);
      if (media) item.media = media;
      return item;
    });
}
