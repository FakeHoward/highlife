export type OutgoingCallMode = "matrixrtc" | "direct" | "blocked";

/** MatrixRTC join uses `camera`; the chat chrome talks in `video`. */
export function matrixRtcCameraOptions(
  options?: { video?: boolean },
): { camera?: boolean } | undefined {
  if (!options) return undefined;
  return { camera: Boolean(options.video) };
}

export function outgoingCallMode(input: {
  isDirect: boolean;
  encrypted: boolean;
  cryptoReady: boolean;
  matrixRtcAvailable?: boolean;
}): OutgoingCallMode {
  const matrixRtcAvailable = input.matrixRtcAvailable !== false;
  if (matrixRtcAvailable) return "matrixrtc";
  if (input.isDirect) {
    if (input.encrypted && !input.cryptoReady) return "blocked";
    return "direct";
  }
  return "blocked";
}
