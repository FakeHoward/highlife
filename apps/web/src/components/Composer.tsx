import type { TimelineItem } from "@highlife/ui-contracts";
import { useEffect, useRef, useState, type ChangeEvent, type FormEvent, type KeyboardEvent } from "react";
import { useI18n } from "../i18n";
import { sendMessage, setTyping, uploadFile } from "../matrix/service";
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
  const typingTimer = useRef<number | undefined>(undefined);
  const file = useRef<HTMLInputElement>(null);
  const previousRoom = useRef(roomId);
  const previousMode = useRef(mode);

  useEffect(() => {
    if (previousRoom.current !== roomId) {
      previousRoom.current = roomId;
      setText("");
      setError(null);
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

  function keyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      void submit();
    }
  }

  function change(value: string) {
    setText(value);
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
