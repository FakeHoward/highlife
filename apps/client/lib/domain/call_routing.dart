/// Where an outgoing call from the room chrome should go.
enum OutgoingCallKind { nativeDirect, matrixRtc }

/// Prefer MatrixRTC whenever a focus exists so web / Element X can join.
/// Native 1:1 is only for DMs when MatrixRTC is unavailable.
OutgoingCallKind outgoingCallKind({
  required bool isDirectChat,
  bool matrixRtcAvailable = false,
}) {
  if (matrixRtcAvailable) return OutgoingCallKind.matrixRtc;
  return isDirectChat
      ? OutgoingCallKind.nativeDirect
      : OutgoingCallKind.matrixRtc;
}

const kQuickReactions = [
  '👍',
  '❤️',
  '😂',
  '🎉',
  '👀',
  '🔥',
  '😢',
  '🙏',
];
