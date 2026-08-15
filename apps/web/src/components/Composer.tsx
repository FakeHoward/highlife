import type { TimelineItem } from "@highlife/ui-contracts";
import { useEffect, useRef, useState, type ChangeEvent, type FormEvent, type KeyboardEvent } from "react";
import { useI18n } from "../i18n";
import {
  listImagePacks,
  mediaUrl,
  sendLocation,
  sendMessage,
  sendSticker,
  setTyping,
  suggestCommands,
  uploadFile,
  CryptoUnavailableError,
} from "../matrix/service";
import { completeCommand } from "../matrix/specFeatures";
import { IconAttach, IconMic, IconSend, IconStop } from "./Icons";

export type ComposeMode = { type: "reply" | "edit"; item: TimelineItem } | null;

function composeFailure(reason: unknown, fallback: string, cryptoMessage: string): string {
  if (reason instanceof CryptoUnavailableError) return cryptoMessage;
  return reason instanceof Error ? reason.message : fallback;
}

function pickAudioMime(): string {
  if (typeof MediaRecorder === "undefined") return "";
  for (const type of ["audio/webm;codecs=opus", "audio/webm", "audio/ogg;codecs=opus"]) {
    if (MediaRecorder.isTypeSupported(type)) return type;
  }
  return "";
}

export function Composer({
  roomId,
  mode,
  onMode,
  threadRootId,
}: {
  roomId: string;
  mode: ComposeMode;
  onMode: (mode: ComposeMode) => void;
  threadRootId?: string;
}) {
  const { t } = useI18n();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadRatio, setUploadRatio] = useState<number | null>(null);
  const [recording, setRecording] = useState(false);
  const [recordSeconds, setRecordSeconds] = useState(0);
  const [stickersOpen, setStickersOpen] = useState(false);
  const typingTimer = useRef<number | undefined>(undefined);
  const file = useRef<HTMLInputElement>(null);
  const previousRoom = useRef(roomId);
  const previousMode = useRef(mode);
  const recorder = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);
  const stream = useRef<MediaStream | null>(null);
  const startedAt = useRef(0);
  const tick = useRef<number | undefined>(undefined);

  const commands = suggestCommands(roomId, text);
  const packs = stickersOpen ? listImagePacks().filter((item) => item.usage.includes("sticker")) : [];

  function stopTracks() {
    stream.current?.getTracks().forEach((track) => track.stop());
    stream.current = null;
    window.clearInterval(tick.current);
    tick.current = undefined;
  }

  function discardRecording() {
    try {
      if (recorder.current && recorder.current.state !== "inactive") recorder.current.stop();
    } catch {
      /* already stopped */
    }
    recorder.current = null;
    chunks.current = [];
    stopTracks();
    setRecording(false);
    setRecordSeconds(0);
  }

  useEffect(() => {
    if (previousRoom.current !== roomId) {
      previousRoom.current = roomId;
      setText("");
      setError(null);
      setStickersOpen(false);
      discardRecording();
      void Promise.resolve(setTyping(roomId, false)).catch(() => undefined);
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
    discardRecording();
    void Promise.resolve(setTyping(roomId, false)).catch(() => undefined);
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
        ...(threadRootId && mode?.type !== "edit" ? { threadRootId } : {}),
      });
      setText("");
      onMode(null);
      await setTyping(roomId, false);
    } catch (reason) {
      setError(composeFailure(reason, t("composer.sendFailed"), t("composer.cryptoUnavailable")));
    } finally {
      setBusy(false);
    }
  }

  function keyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Tab" && commands[0]) {
      event.preventDefault();
      setText(completeCommand(commands[0], text));
      return;
    }
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      void submit();
    }
  }

  function change(value: string) {
    setText(value);
    void Promise.resolve(setTyping(roomId, true)).catch(() => undefined);
    window.clearTimeout(typingTimer.current);
    typingTimer.current = window.setTimeout(
      () => void Promise.resolve(setTyping(roomId, false)).catch(() => undefined),
      6000,
    );
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
        threadRootId,
        onProgress: (ratio) => setUploadRatio(ratio),
      });
      if (mode?.type === "reply") onMode(null);
    } catch (reason) {
      setError(composeFailure(reason, t("composer.uploadFailed"), t("composer.cryptoUnavailable")));
    } finally {
      setBusy(false);
      setUploadRatio(null);
      event.target.value = "";
    }
  }

  async function shareLocation() {
    setBusy(true);
    setError(null);
    try {
      const coords = await new Promise<GeolocationCoordinates>((resolve, reject) => {
        if (!navigator.geolocation) {
          reject(new Error(t("composer.locationDenied")));
          return;
        }
        navigator.geolocation.getCurrentPosition(
          (position) => resolve(position.coords),
          () => reject(new Error(t("composer.locationDenied"))),
          { enableHighAccuracy: true, timeout: 8000 },
        );
      });
      await sendLocation(roomId, coords.latitude, coords.longitude, undefined, threadRootId);
    } catch (reason) {
      const typed = window.prompt(t("composer.locationHint"));
      if (!typed) {
        setError(reason instanceof Error ? reason.message : t("composer.locationDenied"));
        setBusy(false);
        return;
      }
      const match = typed.trim().match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
      if (!match) {
        setError(t("composer.locationDenied"));
        setBusy(false);
        return;
      }
      try {
        await sendLocation(roomId, Number(match[1]), Number(match[2]), undefined, threadRootId);
      } catch (fallback) {
        setError(composeFailure(fallback, t("composer.sendFailed"), t("composer.cryptoUnavailable")));
      }
    } finally {
      setBusy(false);
    }
  }

  async function startRecording() {
    if (busy || recording || typeof MediaRecorder === "undefined") return;
    setError(null);
    try {
      const media = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.current = media;
      chunks.current = [];
      const mime = pickAudioMime();
      const next = mime ? new MediaRecorder(media, { mimeType: mime }) : new MediaRecorder(media);
      recorder.current = next;
      next.ondataavailable = (event) => {
        if (event.data.size > 0) chunks.current.push(event.data);
      };
      startedAt.current = Date.now();
      setRecordSeconds(0);
      tick.current = window.setInterval(() => {
        setRecordSeconds(Math.floor((Date.now() - startedAt.current) / 1000));
      }, 250);
      next.start();
      setRecording(true);
    } catch (reason) {
      stopTracks();
      setError(reason instanceof Error ? reason.message : t("composer.uploadFailed"));
    }
  }

  async function finishRecording() {
    const active = recorder.current;
    if (!active) {
      discardRecording();
      return;
    }
    const mime = active.mimeType || "audio/webm";
    const durationMs = Date.now() - startedAt.current;
    const blob = await new Promise<Blob>((resolve) => {
      active.onstop = () => resolve(new Blob(chunks.current, { type: mime }));
      if (active.state !== "inactive") active.stop();
      else resolve(new Blob(chunks.current, { type: mime }));
    });
    stopTracks();
    recorder.current = null;
    chunks.current = [];
    setRecording(false);
    setRecordSeconds(0);
    if (blob.size === 0) return;
    const ext = mime.includes("ogg") ? "ogg" : "webm";
    const voice = new File([blob], `voice.${ext}`, { type: mime });
    setBusy(true);
    setError(null);
    setUploadRatio(0);
    try {
      await uploadFile(roomId, voice, {
        replyEventId: mode?.type === "reply" ? mode.item.eventId : undefined,
        threadRootId,
        voice: true,
        durationMs,
        onProgress: (ratio) => setUploadRatio(ratio),
      });
      if (mode?.type === "reply") onMode(null);
    } catch (reason) {
      setError(composeFailure(reason, t("composer.uploadFailed"), t("composer.cryptoUnavailable")));
    } finally {
      setBusy(false);
      setUploadRatio(null);
    }
  }

  const canSend = Boolean(text.trim()) && !busy;
  const canRecord = typeof MediaRecorder !== "undefined" && Boolean(navigator.mediaDevices?.getUserMedia);
  return (
    <div className="composer-wrap">
      {threadRootId && (
        <div className="compose-mode">
          <span>{t("composer.thread")}</span>
        </div>
      )}
      {mode && (
        <div className="compose-mode">
          <span>{mode.type === "edit" ? t("composer.editing") : t("composer.replyingTo")} <strong>{mode.item.senderName}</strong>: {mode.item.body.slice(0, 80)}</span>
          <button
            type="button"
            className="icon-button"
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
      {commands.length > 0 && (
        <div className="command-suggest" role="listbox" aria-label={t("composer.commands")}>
          {commands.map((command) => (
            <button
              key={command.name}
              type="button"
              role="option"
              onClick={() => setText(completeCommand(command, text))}
            >
              /{command.name}
              {command.description ? <small>{command.description}</small> : null}
            </button>
          ))}
        </div>
      )}
      {stickersOpen && (
        <div className="sticker-picker" role="listbox" aria-label={t("composer.stickers")}>
          {packs.length === 0 && <p className="muted small">{t("composer.noStickers")}</p>}
          {packs.map((item) => (
            <button
              key={`${item.shortcode}-${item.url}`}
              type="button"
              onClick={() => {
                void sendSticker(roomId, item, threadRootId).catch((reason: unknown) => {
                  setError(composeFailure(reason, t("composer.sendFailed"), t("composer.cryptoUnavailable")));
                });
                setStickersOpen(false);
              }}
            >
              <img src={mediaUrl(item.url)} alt={item.body} />
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
      {!recording && mode?.type !== "edit" && (
        <div className="composer-tools">
          <button type="button" className="text-button" onClick={() => void shareLocation()} disabled={busy}>
            {t("composer.location")}
          </button>
          <button
            type="button"
            className="text-button"
            onClick={() => setStickersOpen((open) => !open)}
            aria-expanded={stickersOpen}
            disabled={busy}
          >
            {t("composer.stickers")}
          </button>
        </div>
      )}
      <form className={`composer${recording ? " is-recording" : ""}`} onSubmit={submit}>
        <input ref={file} type="file" hidden onChange={attach} />
        {recording ? (
          <button type="button" className="icon-button attach" onClick={discardRecording} aria-label={t("composer.cancelRecord")} disabled={busy}>
            ×
          </button>
        ) : (
          <button type="button" className="icon-button attach" onClick={() => file.current?.click()} aria-label={t("composer.attach")} disabled={busy}>
            <IconAttach />
          </button>
        )}
        {recording ? (
          <p className="record-meter" role="status">{t("composer.recording", { seconds: recordSeconds })}</p>
        ) : (
          <textarea
            rows={1}
            value={text}
            onChange={(event) => change(event.target.value)}
            onKeyDown={keyDown}
            placeholder={t("composer.message")}
            aria-label={t("composer.message")}
          />
        )}
        {recording ? (
          <button type="button" className="send-button" onClick={() => void finishRecording()} aria-label={t("composer.stopRecord")} disabled={busy}>
            <IconStop />
          </button>
        ) : canSend || !canRecord || mode?.type === "edit" ? (
          <button className="send-button" disabled={!canSend} aria-label={t("composer.send")}>
            <IconSend />
          </button>
        ) : (
          <button type="button" className="send-button" onClick={() => void startRecording()} aria-label={t("composer.record")} disabled={busy}>
            <IconMic />
          </button>
        )}
      </form>
    </div>
  );
}
