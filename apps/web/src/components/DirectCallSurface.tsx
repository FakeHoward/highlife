import { useEffect, useRef } from "react";
import type { DirectCallSnapshot } from "../matrix/directCall";

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

  useEffect(() => {
    const element = remoteAudio.current;
    if (!element) return;
    element.srcObject = snapshot.remoteStream;
    if (snapshot.remoteStream) void element.play().catch(() => undefined);
    return () => {
      element.srcObject = null;
    };
  }, [snapshot.remoteStream]);

  if (!snapshot.call && snapshot.phase !== "error") return null;

  const incoming = snapshot.direction === "incoming" && snapshot.phase === "ringing";
  const status =
    snapshot.phase === "connected"
      ? labels.connected
      : snapshot.phase === "ringing"
        ? labels.incoming
        : snapshot.phase === "error"
          ? labels.failed
          : labels.connecting;

  return (
    <section className="direct-call" role="dialog" aria-label={labels.dialog}>
      <audio ref={remoteAudio} autoPlay />
      <div className="direct-call-copy">
        <strong>{snapshot.peerName || snapshot.peerUserId || labels.unknownPeer}</strong>
        <span>{status}</span>
      </div>
      <div className="direct-call-actions">
        {incoming ? (
          <>
            <button type="button" className="button call-answer" onClick={onAccept} aria-label={labels.answer}>
              {labels.answer}
            </button>
            <button type="button" className="button danger" onClick={onReject} aria-label={labels.decline}>
              {labels.decline}
            </button>
          </>
        ) : (
          <>
            <button type="button" className="button" onClick={onToggleMicrophone} aria-label={snapshot.microphoneMuted ? labels.unmute : labels.mute}>
              {snapshot.microphoneMuted ? labels.unmute : labels.mute}
            </button>
            <button type="button" className="button danger" onClick={onHangup} aria-label={labels.hangup}>
              {labels.hangup}
            </button>
          </>
        )}
      </div>
    </section>
  );
}
