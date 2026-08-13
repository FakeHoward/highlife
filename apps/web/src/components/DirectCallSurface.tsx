import { useEffect, useRef, useState } from "react";
import type { DirectCallSnapshot } from "../matrix/directCall";
import { DIRECT_CALL_MIC_BLOCKED } from "../matrix/directCallErrors";

interface Props {
  snapshot: DirectCallSnapshot;
  onAccept: () => void;
  onReject: () => void;
  onHangup: () => void;
  onToggleMicrophone: () => void;
  labels: DirectCallLabels;
}

export interface DirectCallLabels {
  dialog: string;
  connected: string;
  incoming: string;
  failed: string;
  connecting: string;
  unknownPeer: string;
  answer: string;
  decline: string;
  mute: string;
  unmute: string;
  hangup: string;
  micBlocked: string;
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

export function DirectCallSurface({
  snapshot,
  onAccept,
  onReject,
  onHangup,
  onToggleMicrophone,
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

  if (snapshot.phase === "idle" || snapshot.phase === "ended") return null;

  const incoming = snapshot.direction === "incoming" && snapshot.phase === "ringing";
  const failed = snapshot.phase === "error";
  const status = failed
    ? snapshot.error === DIRECT_CALL_MIC_BLOCKED
      ? labels.micBlocked
      : snapshot.error || labels.failed
    : snapshot.phase === "connected"
      ? elapsed || labels.connected
      : snapshot.phase === "ringing"
        ? labels.incoming
        : labels.connecting;

  return (
    <section className={`call-stage${failed ? " is-error" : ""}`} role="dialog" aria-label={labels.dialog}>
      <audio ref={remoteAudio} autoPlay />
      <div className="call-stage-mark" aria-hidden="true">☎</div>
      <div className="call-stage-copy">
        <strong>{snapshot.peerName || snapshot.peerUserId || labels.unknownPeer}</strong>
        <span>{status}</span>
      </div>
      <div className="call-stage-actions">
        {incoming ? (
          <>
            <button type="button" className="call-round answer" onClick={onAccept} aria-label={labels.answer}>
              {labels.answer}
            </button>
            <button type="button" className="call-round hangup" onClick={onReject} aria-label={labels.decline}>
              {labels.decline}
            </button>
          </>
        ) : failed ? (
          <button type="button" className="call-round hangup" onClick={onHangup} aria-label={labels.hangup}>
            {labels.hangup}
          </button>
        ) : (
          <>
            <button
              type="button"
              className={`call-round mute${snapshot.microphoneMuted ? " is-on" : ""}`}
              onClick={onToggleMicrophone}
              aria-label={snapshot.microphoneMuted ? labels.unmute : labels.mute}
            >
              {snapshot.microphoneMuted ? labels.unmute : labels.mute}
            </button>
            <button type="button" className="call-round hangup" onClick={onHangup} aria-label={labels.hangup}>
              {labels.hangup}
            </button>
          </>
        )}
      </div>
    </section>
  );
}
