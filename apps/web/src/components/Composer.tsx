import type { TimelineItem } from "@highlife/ui-contracts";
import { useEffect, useRef, useState, type ChangeEvent, type FormEvent, type KeyboardEvent } from "react";
import { useI18n } from "../i18n";
import { createPoll, sendMessage, setTyping, uploadFile } from "../matrix/service";
import { IconAttach, IconSend } from "./Icons";

export type ComposeMode = { type: "reply" | "edit"; item: TimelineItem } | null;

export function Composer({
  roomId,
  mode,
  onMode,
}: {
  roomId: string;
  mode: ComposeMode;
  onMode: (mode: ComposeMode) => void;
}) {
  const { t } = useI18n();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadRatio, setUploadRatio] = useState<number | null>(null);
  const [pollOpen, setPollOpen] = useState(false);
  const [pollQuestion, setPollQuestion] = useState("");
  const [pollAnswers, setPollAnswers] = useState("");
  const typingTimer = useRef<number | undefined>(undefined);
  const file = useRef<HTMLInputElement>(null);
  const previousRoom = useRef(roomId);
  const previousMode = useRef(mode);

  const commands = [
    { value: "/start", label: t("composer.cmdStart") },
    { value: "/help", label: t("composer.cmdHelp") },
    { value: "/settings", label: t("composer.cmdSettings") },
    { value: "/poll", label: t("composer.createPoll") },
  ];

  useEffect(() => {
    if (previousRoom.current !== roomId) {
      previousRoom.current = roomId;
      setText("");
      setError(null);
      setPollOpen(false);
      void setTyping(roomId, false).catch(() => undefined);
    }
  }, [roomId]);

  useEffect(() => {
    const previous = previousMode.current;
    previousMode.current = mode;
    if (mode?.type === "edit") {
      setText(mode.item.body);
      return;
    }
    if (previous?.type === "edit" && mode === null) {
      setText("");
    }
  }, [mode]);

  useEffect(() => () => {
    window.clearTimeout(typingTimer.current);
    void setTyping(roomId, false).catch(() => undefined);
  }, [roomId]);

  async function submit(event?: FormEvent) {
    event?.preventDefault();
    const body = text.trim();
    if (!body || busy) return;
    if (body.toLowerCase() === "/poll" || body.toLowerCase().startsWith("/poll ")) {
      setPollOpen(true);
      setText("");
      await setTyping(roomId, false);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await sendMessage(roomId, body, {
        editEventId: mode?.type === "edit" ? mode.item.eventId : undefined,
        replyEventId: mode?.type === "reply" ? mode.item.eventId : undefined,
      });
      setText("");
      onMode(null);
      await setTyping(roomId, false);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("composer.sendFailed"));
    } finally {
      setBusy(false);
    }
  }

  async function submitPoll(event: FormEvent) {
    event.preventDefault();
    const question = pollQuestion.trim();
    const answers = pollAnswers
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .slice(0, 4);
    if (!question || answers.length < 2 || busy) return;
    setBusy(true);
    setError(null);
    try {
      await createPoll(roomId, { question, answers });
      setPollQuestion("");
      setPollAnswers("");
      setPollOpen(false);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("composer.sendFailed"));
    } finally {
      setBusy(false);
    }
  }

  function keyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      void submit();
    }
  }

  function change(value: string) {
    setText(value);
    if (value.toLowerCase() === "/poll") {
      setPollOpen(true);
    }
    void setTyping(roomId, true).catch(() => undefined);
    window.clearTimeout(typingTimer.current);
    typingTimer.current = window.setTimeout(() => void setTyping(roomId, false), 6000);
  }

  async function attach(event: ChangeEvent<HTMLInputElement>) {
    const selected = event.target.files?.[0];
    if (!selected) return;
    setBusy(true);
    setError(null);
    setUploadRatio(0);
    try {
      await uploadFile(roomId, selected, {
        replyEventId: mode?.type === "reply" ? mode.item.eventId : undefined,
        onProgress: (ratio) => setUploadRatio(ratio),
      });
      if (mode?.type === "reply") onMode(null);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("composer.uploadFailed"));
    } finally {
      setBusy(false);
      setUploadRatio(null);
      event.target.value = "";
    }
  }

  const canSend = Boolean(text.trim()) && !busy;
  const matches = text.startsWith("/")
    ? commands.filter((command) => command.value.startsWith(text.toLowerCase()))
    : [];

  return (
    <div className="composer-wrap">
      {mode && (
        <div className="compose-mode">
          <span>{mode.type === "edit" ? t("composer.editing") : t("composer.replyingTo")} <strong>{mode.item.senderName}</strong>: {mode.item.body.slice(0, 80)}</span>
          <button
            type="button"
            onClick={() => {
              if (mode.type === "edit") setText("");
              onMode(null);
            }}
            aria-label={t("composer.cancel")}
          >
            ×
          </button>
        </div>
      )}
      {pollOpen && (
        <form className="poll-composer" onSubmit={submitPoll}>
          <label>
            <span>{t("composer.pollQuestion")}</span>
            <input
              value={pollQuestion}
              onChange={(event) => setPollQuestion(event.target.value)}
              placeholder={t("composer.pollQuestion")}
              required
            />
          </label>
          <label>
            <span>{t("composer.pollAnswers")}</span>
            <textarea
              rows={4}
              value={pollAnswers}
              onChange={(event) => setPollAnswers(event.target.value)}
              placeholder={"Option A\nOption B"}
              required
            />
          </label>
          <div className="poll-composer-actions">
            <button type="button" className="button" onClick={() => setPollOpen(false)}>{t("composer.cancel")}</button>
            <button type="submit" className="button primary" disabled={busy}>{t("composer.createPoll")}</button>
          </div>
        </form>
      )}
      {matches.length > 0 && (
        <div className="command-menu" role="listbox">
          {matches.map((command) => (
            <button
              key={command.value}
              type="button"
              onClick={() => {
                if (command.value === "/poll") {
                  setPollOpen(true);
                  setText("");
                  return;
                }
                setText(`${command.value} `);
              }}
            >
              <code>{command.value}</code><span>{command.label}</span>
            </button>
          ))}
        </div>
      )}
      {error && <p className="composer-error" role="alert">{error}</p>}
      {uploadRatio != null && (
        <div className="upload-progress" role="status" aria-live="polite">
          <div className="upload-progress-bar" style={{ width: `${Math.round(uploadRatio * 100)}%` }} />
          <span>{t("composer.uploadProgress", { percent: Math.round(uploadRatio * 100) })}</span>
        </div>
      )}
      <form className="composer" onSubmit={submit}>
        <input ref={file} type="file" hidden onChange={attach} />
        <button type="button" className="icon-button attach" onClick={() => file.current?.click()} aria-label={t("composer.attach")} disabled={busy}>
          <IconAttach />
        </button>
        <button
          type="button"
          className={`icon-button poll-toggle ${pollOpen ? "active" : ""}`}
          onClick={() => setPollOpen((value) => !value)}
          aria-label={t("composer.createPoll")}
          disabled={busy}
        >
          {t("composer.createPoll")}
        </button>
        <textarea
          rows={1}
          value={text}
          onChange={(event) => change(event.target.value)}
          onKeyDown={keyDown}
          placeholder={t("composer.message")}
          aria-label={t("composer.message")}
        />
        <button className="send-button" disabled={!canSend} aria-label={t("composer.send")}>
          <IconSend />
        </button>
      </form>
    </div>
  );
}
