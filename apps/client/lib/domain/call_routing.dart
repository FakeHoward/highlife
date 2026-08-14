/// Where an outgoing call from the room chrome should go.
enum OutgoingCallKind { nativeDirect, matrixRtc }

/// Direct chats use first-party Matrix 1:1 VoIP. Rooms and spaces use MatrixRTC.
OutgoingCallKind outgoingCallKind({required bool isDirectChat}) {
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
