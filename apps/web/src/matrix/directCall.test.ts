import { describe, expect, it, vi } from "vitest";

vi.mock("matrix-js-sdk", () => ({
  CallEvent: { State: "state", Hangup: "hangup", Error: "error", FeedsChanged: "feeds_changed" },
}));
vi.mock("matrix-js-sdk/lib/webrtc/call", () => ({
  CallErrorCode: { UserHangup: "user_hangup" },
  CallState: {
    Fledgling: "fledgling",
    Ringing: "ringing",
    Connected: "connected",
    Ended: "ended",
  },
}));
vi.mock("matrix-js-sdk/lib/webrtc/callEventHandler", () => ({
  CallEventHandlerEvent: { Incoming: "Call.incoming" },
}));

import { CallEvent } from "matrix-js-sdk";
import {
  CallErrorCode,
  CallState,
} from "matrix-js-sdk/lib/webrtc/call";
import { CallEventHandlerEvent } from "matrix-js-sdk/lib/webrtc/callEventHandler";
import { DirectCallController, type DirectMatrixCall } from "./directCall";

class FakeCall {
  roomId = "!room:example.org";
  state = CallState.Fledgling;
  microphoneMuted = false;
  placed = false;
  answered = false;
  rejected = false;
  hungUp = false;
  hangupReason: CallErrorCode | null = null;
  suppressHangupEvent: boolean | null = null;
  cameraMuted = true;
  video = false;
  remoteFeeds: Array<{ stream: MediaStream }> = [];
  localFeeds: Array<{ stream: MediaStream }> = [];
  private listeners = new Map<string, Set<(...args: unknown[]) => void>>();

  on(event: string, listener: (...args: unknown[]) => void) {
    const handlers = this.listeners.get(event) ?? new Set();
    handlers.add(listener);
    this.listeners.set(event, handlers);
    return this;
  }

  off(event: string, listener: (...args: unknown[]) => void) {
    this.listeners.get(event)?.delete(listener);
    return this;
  }

  emit(event: string, ...args: unknown[]) {
    for (const listener of this.listeners.get(event) ?? []) listener(...args);
  }

  async placeVoiceCall() {
    this.placed = true;
  }

  async placeVideoCall() {
    this.placed = true;
    this.video = true;
  }

  isLocalVideoMuted() {
    return this.cameraMuted ?? true;
  }

  async setLocalVideoMuted(muted: boolean) {
    this.cameraMuted = muted;
    return muted;
  }

  async answer() {
    this.answered = true;
  }

  reject() {
    this.rejected = true;
  }

  hangup(reason: CallErrorCode, suppressEvent: boolean) {
    this.hungUp = true;
    this.hangupReason = reason;
    this.suppressHangupEvent = suppressEvent;
    this.state = CallState.Ended;
    this.emit(CallEvent.State, CallState.Ended);
  }

  isMicrophoneMuted() {
    return this.microphoneMuted;
  }

  async setMicrophoneMuted(muted: boolean) {
    this.microphoneMuted = muted;
    return muted;
  }

  getOpponentMember() {
    return { name: "Ada", userId: "@ada:example.org" };
  }

  getRemoteFeeds() {
    return this.remoteFeeds;
  }

  getLocalFeeds() {
    return this.localFeeds;
  }
}

class FakeClient {
  incoming?: (call: DirectMatrixCall) => void;
  call = new FakeCall();

  on(event: string, listener: (call: DirectMatrixCall) => void) {
    if (event === CallEventHandlerEvent.Incoming) this.incoming = listener;
    return this;
  }

  off() {
    this.incoming = undefined;
    return this;
  }

  createCall() {
    return this.call as unknown as DirectMatrixCall;
  }
}

describe("DirectCallController", () => {
  it("places an outgoing Matrix voice call and exposes its peer", async () => {
    const client = new FakeClient();
    const controller = new DirectCallController(client);

    await controller.start("!room:example.org");

    expect(client.call.placed).toBe(true);
    expect(controller.snapshot.direction).toBe("outgoing");
    expect(controller.snapshot.peerName).toBe("Ada");
  });

  it("announces incoming calls and accepts them only after user action", async () => {
    const client = new FakeClient();
    const controller = new DirectCallController(client);
    client.incoming?.(client.call as unknown as DirectMatrixCall);

    expect(controller.snapshot.direction).toBe("incoming");
    expect(controller.snapshot.phase).toBe("ringing");
    expect(client.call.answered).toBe(false);

    await controller.accept();
    expect(client.call.answered).toBe(true);
  });

  it("ends and clears calls when the SDK reports an ended state", () => {
    const client = new FakeClient();
    const controller = new DirectCallController(client);
    client.incoming?.(client.call as unknown as DirectMatrixCall);

    client.call.state = CallState.Ended;
    client.call.emit(CallEvent.State, CallState.Ended, CallState.Ringing, client.call);

    expect(controller.snapshot.phase).toBe("ended");
    expect(controller.snapshot.call).toBeNull();
  });

  it("toggles microphone state through the Matrix call", async () => {
    const client = new FakeClient();
    const controller = new DirectCallController(client);
    client.incoming?.(client.call as unknown as DirectMatrixCall);

    await controller.toggleMicrophone();

    expect(client.call.microphoneMuted).toBe(true);
    expect(controller.snapshot.microphoneMuted).toBe(true);
  });

  it("hangs up with the matrix-js-sdk 42.1 signature and releases streams", () => {
    const client = new FakeClient();
    const controller = new DirectCallController(client);
    const remoteStream = {} as MediaStream;
    client.call.remoteFeeds = [{ stream: remoteStream }];
    client.incoming?.(client.call as unknown as DirectMatrixCall);

    expect(controller.snapshot.remoteStream).toBe(remoteStream);
    controller.hangup();

    expect(client.call.hangupReason).toBe(CallErrorCode.UserHangup);
    expect(client.call.suppressHangupEvent).toBe(false);
    expect(controller.snapshot.call).toBeNull();
    expect(controller.snapshot.remoteStream).toBeNull();
    expect(controller.snapshot.localStream).toBeNull();
  });

  it("keeps a visible error when getUserMedia fails and the SDK ends the call", async () => {
    const client = new FakeClient();
    const controller = new DirectCallController(client);
    const denied = Object.assign(new Error("Permission denied by system"), { name: "NotAllowedError" });
    client.call.placeVoiceCall = async () => {
      client.call.emit(CallEvent.Error, denied);
      client.call.hangup(CallErrorCode.UserHangup, false);
      throw denied;
    };

    await expect(controller.start("!room:example.org")).rejects.toThrow(/Permission denied/);
    expect(controller.snapshot.phase).toBe("error");
    expect(controller.snapshot.call).toBeNull();
    expect(controller.snapshot.error).toBe("mic_blocked");
  });

  it("keeps the mic-blocked error when the SDK ends the call without rejecting placeVoiceCall", async () => {
    const client = new FakeClient();
    const controller = new DirectCallController(client);
    const denied = Object.assign(new Error("Permission denied by system"), { name: "NotAllowedError" });
    client.call.placeVoiceCall = async () => {
      client.call.emit(CallEvent.Error, denied);
      client.call.hangup(CallErrorCode.UserHangup, false);
    };

    await controller.start("!room:example.org");
    expect(controller.snapshot.phase).toBe("error");
    expect(controller.snapshot.error).toBe("mic_blocked");
  });

  it("unsubscribes and terminates an active call when disposed", () => {
    const client = new FakeClient();
    const controller = new DirectCallController(client);
    client.incoming?.(client.call as unknown as DirectMatrixCall);

    controller.dispose();

    expect(client.incoming).toBeUndefined();
    expect(client.call.hungUp).toBe(true);
    expect(controller.snapshot.call).toBeNull();
  });
});
