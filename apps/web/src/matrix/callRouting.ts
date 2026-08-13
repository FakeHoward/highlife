export type OutgoingCallMode = "matrixrtc" | "direct" | "blocked";

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
