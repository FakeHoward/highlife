import 'dart:convert';
import 'dart:typed_data';

/// Body shown for a Matrix `event_id_only` push when the payload has no text.
const kDefaultPushBody = 'New activity';

Object? decodePushBytes(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final text = utf8.decode(Uint8List.fromList(bytes), allowMalformed: true).trim();
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } catch (_) {
    return text;
  }
}

String pushNotificationBody(Object? payload) {
  if (payload is Map) {
    final body = payload['body'] ?? payload['content'];
    if (body is String && body.trim().isNotEmpty) return body.trim();
    final counts = payload['counts'];
    if (counts is Map && counts['unread'] is num) {
      final unread = (counts['unread'] as num).toInt();
      if (unread > 0) return unread == 1 ? '1 unread message' : '$unread unread messages';
    }
  }
  if (payload is String && payload.trim().isNotEmpty) return payload.trim();
  return kDefaultPushBody;
}

String? roomIdFromPush(Object? payload) {
  if (payload is! Map) return null;
  final roomId = payload['room_id'] ?? payload['roomId'];
  if (roomId is String && roomId.startsWith('!')) return roomId;
  return null;
}
