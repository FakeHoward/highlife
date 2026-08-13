import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DirectCallSurface } from "./DirectCallSurface";

const labels = {
  dialog: "Voice call",
  connected: "Online",
  incoming: "Ringing",
  failed: "Failed",
  connecting: "Dialing",
  unknownPeer: "Matrix user",
  answer: "Pick up",
  decline: "Dismiss",
  mute: "Silence",
  unmute: "Restore audio",
  hangup: "End",
  micBlocked: "Microphone is blocked by the system.",
};

describe("DirectCallSurface", () => {
  afterEach(() => {
    cleanup();
  });

  it("requires an explicit choice for an incoming call", () => {
    const accept = vi.fn();
    const reject = vi.fn();
    render(
      <DirectCallSurface
        snapshot={{
          call: {} as never,
          roomId: "!room:example.org",
          direction: "incoming",
          phase: "ringing",
          peerName: "Ada",
          peerUserId: "@ada:example.org",
          microphoneMuted: false,
          remoteStream: null,
          localStream: null,
          error: null,
        }}
        onAccept={accept}
        onReject={reject}
        onHangup={vi.fn()}
        onToggleMicrophone={vi.fn()}
        labels={labels}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Pick up" }));
    fireEvent.click(screen.getByRole("button", { name: "Dismiss" }));

    expect(accept).toHaveBeenCalledOnce();
    expect(reject).toHaveBeenCalledOnce();
  });

  it("shows a dismissible overlay when media permission fails without an active call object", () => {
    const hangup = vi.fn();
    render(
      <DirectCallSurface
        snapshot={{
          call: null,
          roomId: "!room:example.org",
          direction: "outgoing",
          phase: "error",
          peerName: "Ada",
          peerUserId: "@ada:example.org",
          microphoneMuted: false,
          remoteStream: null,
          localStream: null,
          error: "mic_blocked",
        }}
        onAccept={vi.fn()}
        onReject={vi.fn()}
        onHangup={hangup}
        onToggleMicrophone={vi.fn()}
        labels={{ ...labels, micBlocked: "Microphone is blocked by the system." }}
      />,
    );

    expect(screen.getByText("Microphone is blocked by the system.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Silence" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "End" }));
    expect(hangup).toHaveBeenCalledOnce();
  });

  it("shows mute and hang-up controls once a call is active", () => {
    const toggleMicrophone = vi.fn();
    const hangup = vi.fn();
    render(
      <DirectCallSurface
        snapshot={{
          call: {} as never,
          roomId: "!room:example.org",
          direction: "outgoing",
          phase: "connected",
          peerName: "Ada",
          peerUserId: "@ada:example.org",
          microphoneMuted: false,
          remoteStream: null,
          localStream: null,
          error: null,
        }}
        onAccept={vi.fn()}
        onReject={vi.fn()}
        onHangup={hangup}
        onToggleMicrophone={toggleMicrophone}
        labels={labels}
      />,
    );

    expect(screen.getByText("Online")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Silence" }));
    fireEvent.click(screen.getByRole("button", { name: "End" }));

    expect(toggleMicrophone).toHaveBeenCalledOnce();
    expect(hangup).toHaveBeenCalledOnce();
  });
});
