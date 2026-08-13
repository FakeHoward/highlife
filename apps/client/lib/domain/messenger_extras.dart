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
