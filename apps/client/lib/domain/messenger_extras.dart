List<String> togglePinnedIds(List<String> current, String eventId) {
  if (current.contains(eventId)) {
    return current.where((id) => id != eventId).toList();
  }
  return [...current, eventId];
}

String? firstUnreadEventId(List<String> eventIds, String? readUpTo) {
  if (eventIds.isEmpty) return null;
  if (readUpTo == null || readUpTo.isEmpty) return eventIds.first;
  final index = eventIds.indexOf(readUpTo);
  if (index < 0) return eventIds.first;
  if (index + 1 >= eventIds.length) return null;
  return eventIds[index + 1];
}

String formatForwardedBody(String senderName, String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return senderName;
  return '$senderName:\n$trimmed';
}

String formatForwardedMedia(String senderName, String kind) {
  final label = kind.trim().isEmpty ? 'attachment' : kind.trim();
  return '$senderName:\n[$label]';
}

String composerDraftKey(String roomId) => 'hl.draft.$roomId';

String mediaKindLabel(String messageType) {
  return switch (messageType) {
    'm.image' => 'image',
    'm.video' => 'video',
    'm.audio' => 'audio',
    'm.file' => 'file',
    _ => 'attachment',
  };
}

Map<String, dynamic> voiceNoteExtraContent({required int durationMs}) {
  return {
    'msgtype': 'm.audio',
    'info': {'duration': durationMs, 'mimetype': 'audio/mp4'},
    'org.matrix.msc3245.voice': <String, dynamic>{},
    'org.matrix.msc1767.audio': {'duration': durationMs},
  };
}
