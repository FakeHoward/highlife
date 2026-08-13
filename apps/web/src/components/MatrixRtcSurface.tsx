import { useEffect, useRef, useState } from "react";
import type { MatrixRtcSnapshot } from "../matrix/matrixRtc";

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
}

interface Props {
  snapshot: MatrixRtcSnapshot;
  onHangup: () => void;
  onToggleMicrophone: () => void;
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
  onFallback,
  labels,
}: Props) {
  const remoteAudio = useRef<HTMLAudioElement>(null);
  const elapsed = useCallElapsed(snapshot.phase === "connected");

  useEffect(() => {
    const element = remoteAudio.current;
    if (!element) return;
    element.srcObject = snapshot.remoteStream;
    if (snapshot.remoteStream) void element.play().catch(() => undefined);
    return () => {
      element.srcObject = null;
    };
  }, [snapshot.remoteStream]);

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
      <div className="call-stage-mark" aria-hidden="true">☎</div>
      <div className="call-stage-copy">
        <strong>{labels.participants.replace("{count}", String(snapshot.participantCount))}</strong>
        <span>{status}</span>
      </div>
      <div className="call-stage-actions">
        {snapshot.phase !== "error" && (
          <button
            type="button"
            className={`call-round mute${snapshot.microphoneMuted ? " is-on" : ""}`}
            onClick={onToggleMicrophone}
            aria-label={snapshot.microphoneMuted ? labels.unmute : labels.mute}
          >
            {snapshot.microphoneMuted ? labels.unmute : labels.mute}
          </button>
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
