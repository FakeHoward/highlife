import type { ReactionSummary, TimelineItem } from "@highlife/ui-contracts";
import DOMPurify from "dompurify";
import { useEffect, useRef, useState, Fragment } from "react";
import { useI18n } from "../i18n";
import { markdownToHtml } from "../matrix/markdown";
import {
  endPoll,
  mediaUrl,
  redact,
  resolveMediaObjectUrl,
  retryDecryptEvent,
  retryFailedEvent,
  sendCallback,
  sendMessage,
  toggleReaction,
  votePoll,
} from "../matrix/service";
import {
  parseAiomatrixPayload,
  stripKeyboardFallbackHtml,
  stripKeyboardFallbackText,
  stripMiniAppUrlFallback,
  type AiomatrixButton,
  type AiomatrixPayload,
  type MiniAppCard,
} from "../protocol/aiomatrix";
import { IconDownload, IconExternal, IconLock } from "./Icons";
import { Avatar } from "./Avatar";

const QUICK_REACTIONS = ["👍", "❤️", "😂", "🎉", "👀"] as const;

function sameCalendarDay(left: number, right: number): boolean {
  const a = new Date(left);
  const b = new Date(right);
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function dateChipLabel(timestamp: number, todayLabel: string, yesterdayLabel: string): string {
  const today = new Date();
  if (sameCalendarDay(timestamp, today.getTime())) return todayLabel;
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  if (sameCalendarDay(timestamp, yesterday.getTime())) return yesterdayLabel;
  return new Date(timestamp).toLocaleDateString(undefined, { day: "numeric", month: "long" });
}

function sanitizeHtml(html: string): string {
  return DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ["style", "iframe", "form", "input"],
  });
}

/** Prefer native keyboard/MiniApp UI: drop wire fallbacks and render Markdown. */
function displayHtml(item: TimelineItem, bot: AiomatrixPayload): string | null {
  if (item.redacted) return null;
  if (item.kind === "system" || item.kind === "poll") return null;
  if (bot.miniApp) {
    const text = [bot.miniApp.title, bot.miniApp.description].filter(Boolean).join("\n\n")
      || stripMiniAppUrlFallback(stripKeyboardFallbackText(item.body));
    return text ? sanitizeHtml(markdownToHtml(text)) : null;
  }
  if (bot.keyboard) {
    return sanitizeHtml(markdownToHtml(stripKeyboardFallbackText(item.body)));
  }
  if (item.formattedBody) {
    return sanitizeHtml(
      stripKeyboardFallbackHtml(stripMiniAppUrlFallback(item.formattedBody)),
    );
  }
  return sanitizeHtml(markdownToHtml(stripMiniAppUrlFallback(item.body)));
}

function deliveryMark(status: TimelineItem["deliveryStatus"], labels: {
  sending: string;
  sent: string;
  delivered: string;
  read: string;
  failed: string;
}): { text: string; title: string } {
  if (status === "encrypting" || status === "sending" || status === "queued") {
    return { text: "…", title: labels.sending };
  }
  if (status === "not_sent" || status === "cancelled") {
    return { text: "!", title: labels.failed };
  }
  if (status === "read") return { text: "✓✓", title: labels.read };
  if (status === "delivered") return { text: "✓", title: labels.delivered };
  if (status === "sent") return { text: "✓", title: labels.sent };
  return { text: "✓", title: labels.sent };
}

interface Props {
  items: TimelineItem[];
  roomId: string;
  onComposeMode: (mode: { type: "reply" | "edit"; item: TimelineItem }) => void;
  onMiniApp: (card: MiniAppCard, item: TimelineItem) => void;
  history: { loading: boolean; exhausted: boolean; error: string | null };
  onLoadOlder: () => Promise<void>;
  highlightEventId?: string | null;
  unreadEventId?: string | null;
  pinnedIds?: string[];
  onPin?: (item: TimelineItem) => void;
  onForward?: (item: TimelineItem) => void;
  onOpenProfile?: (item: TimelineItem) => void;
  onJumpToEvent?: (eventId: string) => void;
}

export function MessageTimeline({
  items,
  roomId,
  onComposeMode,
  onMiniApp,
  history,
  onLoadOlder,
  highlightEventId,
  unreadEventId,
  pinnedIds = [],
  onPin,
  onForward,
  onOpenProfile,
  onJumpToEvent,
}: Props) {
  const { t } = useI18n();
  const end = useRef<HTMLDivElement>(null);
  const scroll = useRef<HTMLElement>(null);
  const lastRoom = useRef(roomId);
  const lastEvent = useRef<string | undefined>(undefined);
  const pendingReactions = useRef(new Set<string>());
  const [pickerFor, setPickerFor] = useState<string | null>(null);
  const newestEventId = items.at(-1)?.eventId;
  useEffect(() => {
    const roomChanged = lastRoom.current !== roomId;
    if (roomChanged || (newestEventId !== lastEvent.current && (scroll.current?.scrollHeight ?? 0) - (scroll.current?.scrollTop ?? 0) - (scroll.current?.clientHeight ?? 0) < 180)) {
      end.current?.scrollIntoView?.({ block: "end" });
    }
    lastRoom.current = roomId;
    lastEvent.current = newestEventId;
  }, [newestEventId, roomId]);

  useEffect(() => {
    setPickerFor(null);
  }, [roomId]);

  useEffect(() => {
    if (!highlightEventId) return;
    const node = scroll.current?.querySelector(`[data-event-id="${CSS.escape(highlightEventId)}"]`);
    node?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [highlightEventId, items]);

  async function loadOlder() {
    const element = scroll.current;
    const previousHeight = element?.scrollHeight ?? 0;
    const previousTop = element?.scrollTop ?? 0;
    await onLoadOlder();
    requestAnimationFrame(() => {
      if (element) element.scrollTop = previousTop + element.scrollHeight - previousHeight;
    });
  }

  async function onToggleReaction(item: TimelineItem, key: string, existing?: ReactionSummary) {
    const guardKey = `${item.eventId}:${key}`;
    if (pendingReactions.current.has(guardKey)) return;
    pendingReactions.current.add(guardKey);
    try {
      await toggleReaction(roomId, item.eventId, key, existing ?? item.reactions.find((r) => r.key === key));
    } finally {
      pendingReactions.current.delete(guardKey);
    }
  }

  async function keyboard(button: AiomatrixButton, item: TimelineItem) {
    if (button.kind === "callback") {
      await sendCallback(roomId, button.data, item.eventId, button.token);
    }
    if (button.kind === "command") {
      await sendMessage(roomId, button.command.startsWith("/") ? button.command : `/${button.command}`);
      return;
    }
    if (button.kind === "url") window.open(button.url, "_blank", "noopener,noreferrer");
    if (button.kind === "mini_app") {
      onMiniApp(
        {
          url: button.url,
          title: button.text,
          ...(button.startParam ? { startParam: button.startParam } : {}),
        },
        item,
      );
    }
  }

  return (
    <section ref={scroll} className="timeline" aria-label={t("timeline.conversation")} aria-live="polite">
      {!history.exhausted && (
        <button className="history-button" onClick={() => void loadOlder()} disabled={history.loading}>
          {history.loading ? t("timeline.loadingOlder") : t("timeline.loadOlder")}
        </button>
      )}
      {history.error && (
        <div className="history-error" role="alert">
          {history.error}
          <button type="button" className="text-button" onClick={() => void loadOlder()}>{t("timeline.retry")}</button>
        </div>
      )}
      {items.length === 0 && (
        <div className="timeline-empty">
          <strong>{t("timeline.emptyTitle")}</strong>
          <p>{t("timeline.emptyBody")}</p>
        </div>
      )}
      {items.map((item, index) => {
        const previous = items[index - 1];
        const showDate = !previous || !sameCalendarDay(previous.timestamp, item.timestamp);
        const dateChip = showDate ? (
          <div className="date-chip">{dateChipLabel(item.timestamp, t("timeline.today"), t("timeline.yesterday"))}</div>
        ) : null;
        if (item.kind === "system") {
          return (
            <Fragment key={item.eventId}>
              {dateChip}
              <div className="system-event" data-event-id={item.eventId}>
                <span>{item.body}</span>
              </div>
            </Fragment>
          );
        }
        const grouped = previous?.senderId === item.senderId
          && previous.kind !== "system"
          && !showDate
          && item.timestamp - previous.timestamp < 300_000;
        const next = items[index + 1];
        const nextNewDay = next != null && !sameCalendarDay(item.timestamp, next.timestamp);
        const lastInGroup = !next
          || next.kind === "system"
          || next.senderId !== item.senderId
          || nextNewDay
          || next.timestamp - item.timestamp >= 300_000;
        const bot = parseAiomatrixPayload(item.rawContent);
        const html = displayHtml(item, bot);
        const keyboardRows = bot.keyboard
          ?.map((row) => row.filter((button) => !(bot.miniApp && button.kind === "mini_app")))
          .filter((row) => row.length > 0) ?? null;
        const mark = item.isOwn
          ? deliveryMark(item.deliveryStatus, {
              sending: t("timeline.sending"),
              sent: t("timeline.sent"),
              delivered: t("timeline.delivered"),
              read: t("timeline.read"),
              failed: t("timeline.sendFailed"),
            })
          : null;
        return (
          <Fragment key={item.eventId}>
            {dateChip}
            {unreadEventId === item.eventId && (
              <div className="unread-chip" role="separator">{t("timeline.unread")}</div>
            )}
            <article
            data-event-id={item.eventId}
            className={`message ${item.isOwn ? "own" : ""} ${grouped ? "grouped" : ""} ${lastInGroup ? "last-in-group" : ""} ${highlightEventId === item.eventId ? "highlight" : ""}`}
          >
            {!item.isOwn && (
              grouped
                ? <span className="message-avatar-spacer" aria-hidden="true" />
                : <button
                    type="button"
                    className="message-avatar-button"
                    onClick={() => onOpenProfile?.(item)}
                    aria-label={item.senderName}
                  >
                    <Avatar
                      className="message-avatar"
                      id={item.senderId}
                      name={item.senderName}
                      src={item.senderAvatarUrl}
                      size="small"
                    />
                  </button>
            )}
            <div className="message-stack">
              {!grouped && !item.isOwn && <header><strong>{item.senderName}</strong></header>}
              <div className="bubble">
                {item.replyToEventId && (
                  <button
                    className="relation-bar"
                    type="button"
                    onClick={() => {
                      if (item.replyToEventId) onJumpToEvent?.(item.replyToEventId);
                      onComposeMode({ type: "reply", item });
                    }}
                  >
                    {item.replyPreview
                      ? <><strong>{item.replyPreview.senderName}</strong><span>{item.replyPreview.body}</span></>
                      : <>{t("timeline.replyUnavailable")}</>}
                  </button>
                )}
                {item.redacted ? (
                  <em className="muted">{item.body}</em>
                ) : item.kind === "notice" && typeof item.rawContent?.algorithm === "string" ? (
                  <p className="decrypt-failed">
                    <IconLock width={14} height={14} /> {item.body}
                    <button
                      type="button"
                      className="text-button"
                      onClick={() => void retryDecryptEvent(roomId, item.eventId)}
                    >
                      {t("timeline.retry")}
                    </button>
                  </p>
                ) : item.poll ? (
                  <PollCard roomId={roomId} item={item} />
                ) : html ? (
                  <div className="formatted" dangerouslySetInnerHTML={{ __html: html }} />
                ) : !bot.miniApp ? (
                  <p>{item.body}</p>
                ) : null}
                {item.media && <Media item={item} />}
                {bot.miniApp && (
                  <button className="mini-card" onClick={() => onMiniApp(bot.miniApp!, item)}>
                    <span className="mini-mark">{t("timeline.miniAppBadge")}</span>
                    <span><strong>{bot.miniApp.title}</strong><small>{bot.miniApp.description ?? t("timeline.openMiniApp")}</small></span>
                    <IconExternal width={16} height={16} />
                  </button>
                )}
                {keyboardRows && keyboardRows.length > 0 && (
                  <div className="inline-keyboard">
                    {keyboardRows.map((row, rowIndex) => (
                      <div key={rowIndex}>
                        {row.map((button, buttonIndex) => (
                          <button key={`${button.text}-${buttonIndex}`} onClick={() => void keyboard(button, item)}>
                            {button.text}
                          </button>
                        ))}
                      </div>
                    ))}
                  </div>
                )}
                <footer>
                  {item.edited && <span>{t("timeline.edited")}</span>}
                  <time dateTime={new Date(item.timestamp).toISOString()}>
                    {new Date(item.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                  </time>
                  {mark && mark.text === "!" ? (
                    <button
                      type="button"
                      className="delivery-retry"
                      title={mark.title}
                      aria-label={t("timeline.retry")}
                      onClick={() => void retryFailedEvent(roomId, item.eventId)}
                    >
                      {mark.text}
                    </button>
                  ) : mark ? (
                    <span title={mark.title}>{mark.text}</span>
                  ) : null}
                </footer>
                {item.reactions.length > 0 && (
                  <div className="reactions">
                    {item.reactions.map((reaction) => (
                      <button
                        key={reaction.key}
                        type="button"
                        className={reaction.reactedByMe ? "mine" : ""}
                        aria-pressed={reaction.reactedByMe}
                        onClick={() => void onToggleReaction(item, reaction.key, reaction)}
                      >
                        {reaction.key} {reaction.count}
                      </button>
                    ))}
                  </div>
                )}
              </div>
              {!item.redacted && item.kind !== "poll" && (
                <div className="message-actions">
                  <button type="button" onClick={() => onComposeMode({ type: "reply", item })}>{t("timeline.reply")}</button>
                  <div className="reaction-picker-wrap">
                    <button
                      type="button"
                      aria-expanded={pickerFor === item.eventId}
                      onClick={() => setPickerFor((current) => (current === item.eventId ? null : item.eventId))}
                    >
                      {t("timeline.react")}
                    </button>
                    {pickerFor === item.eventId && (
                      <div className="reaction-picker" role="listbox" aria-label={t("timeline.react")}>
                        {QUICK_REACTIONS.map((emoji) => (
                          <button
                            key={emoji}
                            type="button"
                            role="option"
                            onClick={() => {
                              setPickerFor(null);
                              void onToggleReaction(item, emoji);
                            }}
                          >
                            {emoji}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                  {item.isOwn && <button type="button" onClick={() => onComposeMode({ type: "edit", item })}>{t("timeline.edit")}</button>}
                  {item.isOwn && (
                    <button
                      type="button"
                      onClick={() => {
                        if (window.confirm(t("timeline.removeConfirm"))) {
                          void redact(roomId, item.eventId);
                        }
                      }}
                    >
                      {t("timeline.remove")}
                    </button>
                  )}
                  {onPin && (
                    <button type="button" onClick={() => onPin(item)}>
                      {pinnedIds.includes(item.eventId) ? t("timeline.unpin") : t("timeline.pin")}
                    </button>
                  )}
                  {onForward && (
                    <button type="button" onClick={() => onForward(item)}>{t("timeline.forward")}</button>
                  )}
                </div>
              )}
            </div>
          </article>
          </Fragment>
        );
      })}
      <div ref={end} />
    </section>
  );
}

function PollCard({ roomId, item }: { roomId: string; item: TimelineItem }) {
  const { t } = useI18n();
  const poll = item.poll!;
  const total = Math.max(1, poll.totalVoters);
  return (
    <div className="poll-card">
      <strong>{poll.question}</strong>
      <ul>
        {poll.answers.map((answer) => {
          const count = poll.counts[answer.id] ?? 0;
          const selected = poll.mySelections.includes(answer.id);
          const pct = Math.round((count / total) * 100);
          return (
            <li key={answer.id}>
              <button
                type="button"
                className={selected ? "selected" : ""}
                disabled={poll.ended}
                onClick={() => void votePoll(roomId, item.eventId, [answer.id])}
              >
                <span>{answer.text}</span>
                <span>{poll.disclosed || poll.ended ? `${count} · ${pct}%` : ""}</span>
              </button>
            </li>
          );
        })}
      </ul>
      <footer>
        <span>{t("timeline.pollVoters", { count: poll.totalVoters })}</span>
        {poll.ended ? (
          <span>{t("timeline.pollEnded")}</span>
        ) : item.isOwn ? (
          <button type="button" className="text-button" onClick={() => void endPoll(roomId, item.eventId)}>{t("timeline.endPoll")}</button>
        ) : null}
      </footer>
    </div>
  );
}

function Media({ item }: { item: TimelineItem }) {
  const { t } = useI18n();
  const [source, setSource] = useState(() =>
    item.media && !item.media.encrypted ? mediaUrl(item.media.mxcUrl) : "",
  );
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let revoked: string | null = null;
    let cancelled = false;
    if (!item.media) return;
    if (!item.media.encrypted) {
      setSource(mediaUrl(item.media.mxcUrl));
      return;
    }
    void resolveMediaObjectUrl(item.media)
      .then((url) => {
        if (cancelled) {
          URL.revokeObjectURL(url);
          return;
        }
        revoked = url;
        setSource(url);
      })
      .catch((reason: Error) => {
        if (!cancelled) setError(reason.message || t("timeline.mediaFailed"));
      });
    return () => {
      cancelled = true;
      if (revoked) URL.revokeObjectURL(revoked);
    };
  }, [item.media, t]);

  if (error) return <p className="muted small">{error}</p>;
  if (!source) return <p className="muted small">{t("timeline.decryptingMedia")}</p>;
  if (item.kind === "image") {
    return <img className="message-media" src={source} alt={item.media?.name ?? t("timeline.image")} loading="lazy" />;
  }
  if (item.kind === "video") return <video className="message-media" src={source} controls preload="metadata" />;
  if (item.kind === "audio") {
    const seconds = item.media?.durationMs != null ? Math.round(item.media.durationMs / 1000) : null;
    return (
      <div className={item.media?.voice ? "voice-note" : undefined}>
        {item.media?.voice && <span className="voice-label">{t("timeline.voice")}{seconds != null ? ` · ${seconds}s` : ""}</span>}
        <audio src={source} controls preload="metadata" />
      </div>
    );
  }
  return (
    <a className="file-card" href={source} target="_blank" rel="noreferrer">
      <IconDownload /> <span><strong>{item.media?.name}</strong><small>{formatBytes(item.media?.size, t("timeline.attachment"))}</small></span>
    </a>
  );
}

function formatBytes(size: number | undefined, attachmentLabel: string): string {
  if (!size) return attachmentLabel;
  if (size < 1024 * 1024) return `${Math.ceil(size / 1024)} KB`;
  return `${(size / 1024 / 1024).toFixed(1)} MB`;
}
