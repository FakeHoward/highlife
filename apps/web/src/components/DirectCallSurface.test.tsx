import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
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
};

describe("DirectCallSurface", () => {
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
