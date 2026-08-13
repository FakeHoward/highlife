import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MatrixRtcSurface } from "./MatrixRtcSurface";

const labels = {
  dialog: "Group call",
  connecting: "Joining",
  connected: "In call",
  failed: "LiveKit failed",
  mute: "Mute",
  unmute: "Unmute",
  hangup: "Leave",
  fallback: "Use Element Call",
  participants: "{count} in call",
};

describe("MatrixRtcSurface", () => {
  afterEach(() => {
    cleanup();
  });

  it("offers Element Call only after LiveKit/MatrixRTC fails", () => {
    const fallback = vi.fn();
    render(
      <MatrixRtcSurface
        snapshot={{
          roomId: "!room:example.org",
          phase: "error",
          participantCount: 0,
          microphoneMuted: false,
          remoteStream: null,
          error: "jwt down",
          fallbackAvailable: true,
        }}
        onHangup={vi.fn()}
        onToggleMicrophone={vi.fn()}
        onFallback={fallback}
        labels={labels}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Use Element Call" }));
    expect(fallback).toHaveBeenCalledOnce();
  });

  it("keeps mute and leave controls while LiveKit is connected", () => {
    const hangup = vi.fn();
    render(
      <MatrixRtcSurface
        snapshot={{
          roomId: "!room:example.org",
          phase: "connected",
          participantCount: 3,
          microphoneMuted: false,
          remoteStream: null,
          error: null,
          fallbackAvailable: true,
        }}
        onHangup={hangup}
        onToggleMicrophone={vi.fn()}
        onFallback={vi.fn()}
        labels={labels}
      />,
    );

    expect(screen.getByText("3 in call")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Use Element Call" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Leave" }));
    expect(hangup).toHaveBeenCalledOnce();
  });
});
