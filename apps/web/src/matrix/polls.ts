/** MSC3381 poll wire helpers (stable + unstable namespaces). */

export const POLL_START_UNSTABLE = "org.matrix.msc3381.poll.start";
export const POLL_START_STABLE = "m.poll.start";
export const POLL_RESPONSE_UNSTABLE = "org.matrix.msc3381.poll.response";
export const POLL_RESPONSE_STABLE = "m.poll.response";
export const POLL_END_UNSTABLE = "org.matrix.msc3381.poll.end";
export const POLL_END_STABLE = "m.poll.end";
export const POLL_TEXT_KEY = "org.matrix.msc1767.text";

export interface PollAnswerOption {
  id: string;
  text: string;
}

export interface PollStartData {
  question: string;
  answers: PollAnswerOption[];
  maxSelections: number;
  disclosed: boolean;
}

export interface PollVoteTally {
  counts: Record<string, number>;
  mySelections: string[];
  totalVoters: number;
  ended: boolean;
}

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function extensibleText(value: unknown): string | undefined {
  if (typeof value === "string") return value;
  const map = record(value);
  if (!map) return undefined;
  const text = map[POLL_TEXT_KEY] ?? map.body ?? map.text;
  return typeof text === "string" ? text : undefined;
}

export function isPollStartType(type: string): boolean {
  return type === POLL_START_UNSTABLE || type === POLL_START_STABLE;
}

export function isPollResponseType(type: string): boolean {
  return type === POLL_RESPONSE_UNSTABLE || type === POLL_RESPONSE_STABLE;
}

export function isPollEndType(type: string): boolean {
  return type === POLL_END_UNSTABLE || type === POLL_END_STABLE;
}

export function parsePollStartContent(content: Record<string, unknown>): PollStartData | null {
  const block = record(content[POLL_START_UNSTABLE]) ?? record(content[POLL_START_STABLE]);
  if (!block) return null;
  const question = extensibleText(block.question)?.trim() ?? "";
  if (!question) return null;
  const rawAnswers = block.answers;
  if (!Array.isArray(rawAnswers) || rawAnswers.length === 0) return null;
  const answers: PollAnswerOption[] = [];
  for (const item of rawAnswers) {
    const map = record(item);
    if (!map) continue;
    const id = typeof map.id === "string" ? map.id.trim() : "";
    const text = extensibleText(map)?.trim() ?? "";
    if (!id || !text) continue;
    answers.push({ id, text });
  }
  if (answers.length === 0) return null;
  const maxRaw = block.max_selections;
  const maxSelections =
    typeof maxRaw === "number"
      ? Math.max(1, Math.min(answers.length, Math.floor(maxRaw)))
      : 1;
  const kind = String(block.kind ?? "");
  return {
    question,
    answers,
    maxSelections,
    disclosed: !kind.includes("undisclosed"),
  };
}

export function pollRelationEventId(content: Record<string, unknown>): string | undefined {
  const relates = record(content["m.relates_to"]);
  if (!relates || relates.rel_type !== "m.reference") return undefined;
  return typeof relates.event_id === "string" ? relates.event_id : undefined;
}

export function parsePollResponseAnswers(content: Record<string, unknown>): string[] {
  for (const key of [POLL_RESPONSE_UNSTABLE, POLL_RESPONSE_STABLE]) {
    const block = record(content[key]);
    if (block && Array.isArray(block.answers)) {
      return block.answers.filter((id): id is string => typeof id === "string");
    }
  }
  if (Array.isArray(content["m.selections"])) {
    return content["m.selections"].filter((id): id is string => typeof id === "string");
  }
  return [];
}

export function buildPollStartContent(input: {
  question: string;
  answers: string[];
  maxSelections?: number;
}): Record<string, unknown> {
  const question = input.question.trim();
  if (!question) throw new Error("Poll question is required");
  const cleaned = input.answers.map((a) => a.trim()).filter(Boolean);
  if (cleaned.length === 0) throw new Error("Poll requires at least one answer");
  const structured = cleaned.map((text, index) => ({
    id: `answer${index}`,
    [POLL_TEXT_KEY]: text,
  }));
  const start = {
    question: { [POLL_TEXT_KEY]: question },
    kind: "org.matrix.msc3381.poll.disclosed",
    max_selections: Math.max(1, Math.min(cleaned.length, input.maxSelections ?? 1)),
    answers: structured,
  };
  return {
    [POLL_START_UNSTABLE]: start,
    [POLL_START_STABLE]: start,
    body: question,
    msgtype: "m.text",
  };
}

export function buildPollResponseContent(pollEventId: string, answerIds: string[]): Record<string, unknown> {
  const response = { answers: answerIds };
  return {
    "m.relates_to": { rel_type: "m.reference", event_id: pollEventId },
    [POLL_RESPONSE_UNSTABLE]: response,
    [POLL_RESPONSE_STABLE]: response,
  };
}

export function buildPollEndContent(pollEventId: string): Record<string, unknown> {
  const end = {};
  return {
    "m.relates_to": { rel_type: "m.reference", event_id: pollEventId },
    [POLL_END_UNSTABLE]: end,
    [POLL_END_STABLE]: end,
    body: "Poll ended",
    msgtype: "m.text",
  };
}

export function tallyPollVotes(input: {
  responses: Array<{ senderId: string; timestamp: number; answers: string[] }>;
  validAnswerIds: Set<string>;
  maxSelections: number;
  ownUserId?: string;
  ended?: boolean;
}): PollVoteTally {
  const bySender = new Map<string, { timestamp: number; answers: string[] }>();
  for (const response of input.responses) {
    const previous = bySender.get(response.senderId);
    if (previous && response.timestamp <= previous.timestamp) continue;
    bySender.set(response.senderId, {
      timestamp: response.timestamp,
      answers: response.answers,
    });
  }

  const counts: Record<string, number> = {};
  for (const id of input.validAnswerIds) counts[id] = 0;
  let totalVoters = 0;
  let mySelections: string[] = [];

  for (const [senderId, value] of bySender) {
    if (value.answers.some((id) => !input.validAnswerIds.has(id))) continue;
    const truncated = [
      ...new Set(
        value.answers
          .filter((id) => input.validAnswerIds.has(id))
          .slice(0, input.maxSelections),
      ),
    ];
    if (truncated.length === 0) continue;
    totalVoters += 1;
    for (const id of truncated) counts[id] = (counts[id] ?? 0) + 1;
    if (input.ownUserId && senderId === input.ownUserId) mySelections = truncated;
  }

  return {
    counts,
    mySelections,
    totalVoters,
    ended: Boolean(input.ended),
  };
}
