import {
  CallEvent,
  type MatrixCall,
} from "matrix-js-sdk";
import {
  CallErrorCode,
  CallState,
} from "matrix-js-sdk/lib/webrtc/call";
import { CallEventHandlerEvent } from "matrix-js-sdk/lib/webrtc/callEventHandler";
import { classifyDirectCallFailure } from "./directCallErrors";

export type DirectCallPhase = "idle" | "ringing" | "connecting" | "connected" | "ended" | "error";
export type DirectCallDirection = "incoming" | "outgoing" | null;
export { DIRECT_CALL_MIC_BLOCKED, classifyDirectCallFailure } from "./directCallErrors";

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
  cameraMuted?: boolean;
  video?: boolean;
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
  const withVideo = feeds.find((feed) => {
    const getVideoTracks = feed.stream.getVideoTracks;
    return typeof getVideoTracks === "function" && getVideoTracks.call(feed.stream).length > 0;
  });
  const withAudio = feeds.find((feed) => {
    const getAudioTracks = feed.stream.getAudioTracks;
    return typeof getAudioTracks === "function" && getAudioTracks.call(feed.stream).length > 0;
  });
  return (withVideo ?? withAudio ?? feeds[0])?.stream ?? null;
}

function streamHasVideo(stream: MediaStream | null): boolean {
  return Boolean(stream && typeof stream.getVideoTracks === "function" && stream.getVideoTracks().length > 0);
}

export class DirectCallController {
  private current: DirectCallSnapshot = EMPTY_SNAPSHOT;
  private retainError = false;
  private readonly listeners = new Set<() => void>();
  private readonly onIncoming = (call: DirectMatrixCall) => this.attach(call, "incoming");
  private readonly onCallState = (nextState: CallState): void => {
    if (nextState === CallState.Ended) {
      this.detachCurrent();
      if (this.retainError || this.current.phase === "error") {
        this.publish({ ...this.terminalSnapshot("error"), error: this.current.error });
        return;
      }
      this.publish(this.terminalSnapshot("ended"));
      return;
    }
    this.refresh({ phase: phaseForState(nextState) });
  };
  private readonly onFeedsChanged = (): void => this.refresh();
  private readonly onCallError = (reason: unknown): void => {
    this.retainError = true;
    this.refresh({ phase: "error", error: classifyDirectCallFailure(reason) });
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

  async start(roomId: string, options?: { video?: boolean }): Promise<void> {
    if (this.current.call) throw new Error("Another call is already active");
    const call = this.client.createCall(roomId);
    if (!call) throw new Error("This browser cannot start WebRTC calls");
    this.attach(call, "outgoing", Boolean(options?.video));
    try {
      if (options?.video && typeof call.placeVideoCall === "function") {
        await call.placeVideoCall();
      } else {
        await call.placeVoiceCall();
      }
    } catch (reason) {
      this.failCurrent(call, reason);
      throw reason;
    }
  }

  async accept(options?: { video?: boolean }): Promise<void> {
    const call = this.requiredCall();
    const video = Boolean(options?.video ?? this.current.video);
    await call.answer(true, video);
    this.refresh({ phase: "connecting", video });
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

  async toggleCamera(): Promise<void> {
    const call = this.requiredCall();
    const muted = typeof call.isLocalVideoMuted === "function" ? !call.isLocalVideoMuted() : true;
    if (typeof call.setLocalVideoMuted === "function") {
      await call.setLocalVideoMuted(muted);
    }
    this.refresh({ cameraMuted: muted, video: true });
  }

  clearEnded(): void {
    if (this.current.phase === "ended" || this.current.phase === "error") {
      this.retainError = false;
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

  private failCurrent(call: DirectMatrixCall, reason: unknown): void {
    this.retainError = true;
    this.detachCurrent();
    try {
      call.hangup(CallErrorCode.UserHangup, false);
    } catch {
      // The SDK may already have terminated the call after getUserMediaFailed.
    }
    this.publish({
      ...this.terminalSnapshot("error"),
      error: classifyDirectCallFailure(reason),
    });
  }

  private attach(call: DirectMatrixCall, direction: Exclude<DirectCallDirection, null>, video = false): void {
    if (this.current.call && this.current.call !== call) {
      if (direction === "incoming") call.reject();
      return;
    }
    this.retainError = false;
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
      cameraMuted: typeof call.isLocalVideoMuted === "function" ? call.isLocalVideoMuted() : !video,
      video,
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
            cameraMuted: typeof call.isLocalVideoMuted === "function" ? call.isLocalVideoMuted() : this.current.cameraMuted,
            video: this.current.video || streamHasVideo(preferredStream(call.getRemoteFeeds())) || streamHasVideo(preferredStream(call.getLocalFeeds())),
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
