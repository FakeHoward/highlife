import {
  CallEvent,
  type MatrixCall,
} from "matrix-js-sdk";
import {
  CallErrorCode,
  CallState,
} from "matrix-js-sdk/lib/webrtc/call";
import { CallEventHandlerEvent } from "matrix-js-sdk/lib/webrtc/callEventHandler";

export type DirectCallPhase = "idle" | "ringing" | "connecting" | "connected" | "ended" | "error";
export type DirectCallDirection = "incoming" | "outgoing" | null;

export type DirectMatrixCall = MatrixCall;

export interface DirectCallClient {
  on(
    event: CallEventHandlerEvent.Incoming,
    listener: (call: DirectMatrixCall) => void,
  ): unknown;
  off(
    event: CallEventHandlerEvent.Incoming,
    listener: (call: DirectMatrixCall) => void,
  ): unknown;
  createCall(roomId: string): DirectMatrixCall | null;
}

export interface DirectCallSnapshot {
  call: DirectMatrixCall | null;
  roomId: string | null;
  direction: DirectCallDirection;
  phase: DirectCallPhase;
  peerName: string;
  peerUserId: string | null;
  microphoneMuted: boolean;
  remoteStream: MediaStream | null;
  localStream: MediaStream | null;
  error: string | null;
}

const EMPTY_SNAPSHOT: DirectCallSnapshot = {
  call: null,
  roomId: null,
  direction: null,
  phase: "idle",
  peerName: "",
  peerUserId: null,
  microphoneMuted: false,
  remoteStream: null,
  localStream: null,
  error: null,
};

function phaseForState(state: CallState): DirectCallPhase {
  if (state === CallState.Ringing) return "ringing";
  if (state === CallState.Connected) return "connected";
  if (state === CallState.Ended) return "ended";
  return "connecting";
}

function preferredStream(
  feeds: ReturnType<MatrixCall["getRemoteFeeds"]>,
): MediaStream | null {
  const withAudio = feeds.find((feed) => {
    const getAudioTracks = feed.stream.getAudioTracks;
    return typeof getAudioTracks === "function" && getAudioTracks.call(feed.stream).length > 0;
  });
  return (withAudio ?? feeds[0])?.stream ?? null;
}

export class DirectCallController {
  private current: DirectCallSnapshot = EMPTY_SNAPSHOT;
  private readonly listeners = new Set<() => void>();
  private readonly onIncoming = (call: DirectMatrixCall) => this.attach(call, "incoming");
  private readonly onCallState = (nextState: CallState): void => {
    if (nextState === CallState.Ended) {
      this.detachCurrent();
      this.publish(this.terminalSnapshot("ended"));
      return;
    }
    this.refresh({ phase: phaseForState(nextState) });
  };
  private readonly onFeedsChanged = (): void => this.refresh();
  private readonly onCallError = (reason: unknown): void => {
    const message =
      reason && typeof reason === "object" && "message" in reason
        ? String((reason as { message?: unknown }).message)
        : "Call failed";
    this.refresh({ phase: "error", error: message });
  };

  constructor(private readonly client: DirectCallClient) {
    client.on(CallEventHandlerEvent.Incoming, this.onIncoming);
  }

  get snapshot(): DirectCallSnapshot {
    return this.current;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async start(roomId: string): Promise<void> {
    if (this.current.call) throw new Error("Another call is already active");
    const call = this.client.createCall(roomId);
    if (!call) throw new Error("This browser cannot start WebRTC calls");
    this.attach(call, "outgoing");
    try {
      await call.placeVoiceCall();
    } catch (reason) {
      call.hangup(CallErrorCode.UserHangup, false);
      this.detachCurrent();
      const error =
        reason && typeof reason === "object" && "message" in reason
          ? String((reason as { message?: unknown }).message)
          : "Call failed";
      this.publish({ ...this.terminalSnapshot("error"), error });
      throw reason;
    }
  }

  async accept(): Promise<void> {
    const call = this.requiredCall();
    await call.answer(true, false);
    this.refresh({ phase: "connecting" });
  }

  reject(): void {
    const call = this.requiredCall();
    call.reject();
    this.detachCurrent();
    this.publish(this.terminalSnapshot("ended"));
  }

  hangup(): void {
    const call = this.requiredCall();
    call.hangup(CallErrorCode.UserHangup, false);
    this.detachCurrent();
    this.publish(this.terminalSnapshot("ended"));
  }

  async toggleMicrophone(): Promise<void> {
    const call = this.requiredCall();
    const muted = !call.isMicrophoneMuted();
    await call.setMicrophoneMuted(muted);
    this.refresh({ microphoneMuted: muted });
  }

  clearEnded(): void {
    if (this.current.phase === "ended" || this.current.phase === "error") {
      this.publish(EMPTY_SNAPSHOT);
    }
  }

  dispose(): void {
    this.client.off(CallEventHandlerEvent.Incoming, this.onIncoming);
    if (this.current.call && this.current.phase !== "ended") {
      this.current.call.hangup(CallErrorCode.UserHangup, false);
    }
    this.detachCurrent();
    this.current = this.terminalSnapshot("ended");
    this.listeners.clear();
  }

  private attach(call: DirectMatrixCall, direction: Exclude<DirectCallDirection, null>): void {
    if (this.current.call && this.current.call !== call) {
      if (direction === "incoming") call.reject();
      return;
    }
    this.detachCurrent();
    call.on(CallEvent.State, this.onCallState);
    call.on(CallEvent.FeedsChanged, this.onFeedsChanged);
    call.on(CallEvent.Error, this.onCallError);
    const member = call.getOpponentMember();
    this.publish({
      call,
      roomId: call.roomId,
      direction,
      phase: direction === "incoming" ? "ringing" : phaseForState(call.state),
      peerName: member?.name || member?.userId || "",
      peerUserId: member?.userId ?? null,
      microphoneMuted: call.isMicrophoneMuted(),
      remoteStream: preferredStream(call.getRemoteFeeds()),
      localStream: preferredStream(call.getLocalFeeds()),
      error: null,
    });
  }

  private refresh(overrides: Partial<DirectCallSnapshot> = {}): void {
    const call = this.current.call;
    this.publish({
      ...this.current,
      ...(call
        ? {
            microphoneMuted: call.isMicrophoneMuted(),
            remoteStream: preferredStream(call.getRemoteFeeds()),
            localStream: preferredStream(call.getLocalFeeds()),
          }
        : {}),
      ...overrides,
    });
  }

  private detachCurrent(): void {
    const call = this.current.call;
    if (!call) return;
    call.off(CallEvent.State, this.onCallState);
    call.off(CallEvent.FeedsChanged, this.onFeedsChanged);
    call.off(CallEvent.Error, this.onCallError);
  }

  private requiredCall(): DirectMatrixCall {
    if (!this.current.call) throw new Error("No active call");
    return this.current.call;
  }

  private terminalSnapshot(phase: "ended" | "error"): DirectCallSnapshot {
    return {
      ...this.current,
      call: null,
      phase,
      microphoneMuted: false,
      remoteStream: null,
      localStream: null,
    };
  }

  private publish(next: DirectCallSnapshot): void {
    this.current = next;
    for (const listener of this.listeners) listener();
  }
}
