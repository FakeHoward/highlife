import { useEffect, useRef } from "react";
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

export function MatrixRtcSurface({
  snapshot,
  onHangup,
  onToggleMicrophone,
  onFallback,
  labels,
}: Props) {
  const remoteAudio = useRef<HTMLAudioElement>(null);

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
      ? labels.connected
      : snapshot.phase === "error"
        ? labels.failed
        : labels.connecting;

  return (
    <section className="direct-call" role="dialog" aria-label={labels.dialog}>
      <audio ref={remoteAudio} autoPlay />
      <div className="direct-call-copy">
        <strong>{labels.participants.replace("{count}", String(snapshot.participantCount))}</strong>
        <span>{status}</span>
      </div>
      <div className="direct-call-actions">
        {snapshot.phase !== "error" && (
          <button
            type="button"
            className="button"
            onClick={onToggleMicrophone}
            aria-label={snapshot.microphoneMuted ? labels.unmute : labels.mute}
          >
            {snapshot.microphoneMuted ? labels.unmute : labels.mute}
          </button>
        )}
        <button type="button" className="button danger" onClick={onHangup} aria-label={labels.hangup}>
          {labels.hangup}
        </button>
        {snapshot.fallbackAvailable && snapshot.phase === "error" && (
          <button type="button" className="button" onClick={onFallback} aria-label={labels.fallback}>
            {labels.fallback}
          </button>
        )}
      </div>
    </section>
  );
}
