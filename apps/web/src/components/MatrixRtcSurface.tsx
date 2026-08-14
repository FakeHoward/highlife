import { useEffect, useRef, useState } from "react";
import type { MatrixRtcSnapshot } from "../matrix/matrixRtc";
import { IconCall } from "./Icons";

export interface MatrixRtcLabels {
  dialog: string;
  connecting: string;
  connected: string;
  failed: string;
  mute: string;
  unmute: string;
  hangup: string;
  fallback: string;
  participants: string;
  cameraOn?: string;
  cameraOff?: string;
}

interface Props {
  snapshot: MatrixRtcSnapshot;
  onHangup: () => void;
  onToggleMicrophone: () => void;
  onToggleCamera?: () => void;
  onFallback: () => void;
  labels: MatrixRtcLabels;
}

function useCallElapsed(active: boolean): string {
  const started = useRef<number | null>(null);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) {
      started.current = null;
      return;
    }
    started.current ??= Date.now();
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [active]);
  if (!active || started.current == null) return "";
  const seconds = Math.max(0, Math.floor((now - started.current) / 1000));
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

export function MatrixRtcSurface({
  snapshot,
  onHangup,
  onToggleMicrophone,
  onToggleCamera,
  onFallback,
  labels,
}: Props) {
  const remoteAudio = useRef<HTMLAudioElement>(null);
  const remoteVideo = useRef<HTMLVideoElement>(null);
  const localVideo = useRef<HTMLVideoElement>(null);
  const elapsed = useCallElapsed(snapshot.phase === "connected");
  const hasVideo = Boolean(
    (snapshot.remoteStream && typeof snapshot.remoteStream.getVideoTracks === "function"
      && snapshot.remoteStream.getVideoTracks().length > 0)
    || (snapshot.localStream && typeof snapshot.localStream.getVideoTracks === "function"
      && snapshot.localStream.getVideoTracks().length > 0)
    || snapshot.cameraMuted === false,
  );

  useEffect(() => {
    const element = remoteAudio.current;
    if (!element) return;
    element.srcObject = snapshot.remoteStream;
    if (snapshot.remoteStream) void element.play().catch(() => undefined);
    return () => {
      element.srcObject = null;
    };
  }, [snapshot.remoteStream]);

  useEffect(() => {
    const remote = remoteVideo.current;
    if (remote) {
      remote.srcObject = snapshot.remoteStream;
      if (snapshot.remoteStream) void remote.play().catch(() => undefined);
    }
    const local = localVideo.current;
    if (local) {
      local.srcObject = snapshot.localStream ?? null;
      if (snapshot.localStream) void local.play().catch(() => undefined);
    }
  }, [snapshot.remoteStream, snapshot.localStream]);

  if (snapshot.phase === "idle") return null;

  const status =
    snapshot.phase === "connected"
      ? elapsed || labels.connected
      : snapshot.phase === "error"
        ? labels.failed
        : labels.connecting;

  return (
    <section className={`call-stage${snapshot.phase === "error" ? " is-error" : ""}`} role="dialog" aria-label={labels.dialog}>
      <audio ref={remoteAudio} autoPlay />
      {hasVideo ? (
        <div className="call-stage-video">
          <video ref={remoteVideo} autoPlay playsInline />
          <video ref={localVideo} autoPlay playsInline muted className="is-local" />
        </div>
      ) : (
        <div className="call-stage-mark" aria-hidden="true"><IconCall /></div>
      )}
      <div className="call-stage-copy">
        <strong>{labels.participants.replace("{count}", String(snapshot.participantCount))}</strong>
        <span>{status}</span>
      </div>
      <div className="call-stage-actions">
        {snapshot.phase !== "error" && (
          <>
            <button
              type="button"
              className={`call-round mute${snapshot.microphoneMuted ? " is-on" : ""}`}
              onClick={onToggleMicrophone}
              aria-label={snapshot.microphoneMuted ? labels.unmute : labels.mute}
            >
              {snapshot.microphoneMuted ? labels.unmute : labels.mute}
            </button>
            {onToggleCamera && labels.cameraOn && labels.cameraOff && (
              <button
                type="button"
                className={`call-round mute${snapshot.cameraMuted ? " is-on" : ""}`}
                onClick={onToggleCamera}
                aria-label={snapshot.cameraMuted ? labels.cameraOn : labels.cameraOff}
              >
                {snapshot.cameraMuted ? labels.cameraOn : labels.cameraOff}
              </button>
            )}
          </>
        )}
        <button type="button" className="call-round hangup" onClick={onHangup} aria-label={labels.hangup}>
          {labels.hangup}
        </button>
        {snapshot.fallbackAvailable && snapshot.phase === "error" && (
          <button type="button" className="call-round fallback" onClick={onFallback} aria-label={labels.fallback}>
            {labels.fallback}
          </button>
        )}
      </div>
    </section>
  );
}
