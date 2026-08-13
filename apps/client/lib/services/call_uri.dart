import 'package:flutter/foundation.dart';

/// Builds a trusted Element Call widget URL, or null when misconfigured.
Uri? buildElementCallUri({
  required String elementCallUrl,
  required String roomId,
  String? userId,
  String? deviceId,
  String? homeserverUrl,
  String? parentUrl,
  bool allowInsecureLocalhost = kDebugMode,
}) {
  final trimmed = elementCallUrl.trim();
  if (trimmed.isEmpty || roomId.trim().isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  final host = uri.host;
  final local = host == 'localhost' || host == '127.0.0.1';
  final secure = uri.isScheme('https') || (allowInsecureLocalhost && local);
  if (!secure) return null;

  // Native embeds have no browser origin; prefer explicit parent, else the
  // Element Call origin on IO / page origin on Flutter web.
  final resolvedParent = (parentUrl != null && parentUrl.trim().isNotEmpty)
      ? parentUrl.trim()
      : (kIsWeb && Uri.base.hasScheme && Uri.base.host.isNotEmpty
          ? Uri.base.origin
          : uri.origin);

  return uri.replace(
    queryParameters: {
      'widgetId': 'highlife_call_$roomId',
      'parentUrl': resolvedParent,
      'roomId': roomId,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      if (homeserverUrl != null && homeserverUrl.isNotEmpty)
        'baseUrl': homeserverUrl,
    },
  );
}

const callMemberStateEventType = 'org.matrix.msc3401.call.member';

/// Active MatrixRTC session via non-expired MSC3401 call.member memberships.
///
/// Do not treat leftover `m.call` / `devices` keys alone as an active call —
/// Element Call often leaves those after everyone hangs up.
bool hasActiveCallMemberStates(
  Iterable<Map<String, dynamic>> memberContents, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final nowMs = clock.millisecondsSinceEpoch;
  for (final content in memberContents) {
    if (content.isEmpty) continue;
    if (_slotMembershipActive(content, nowMs)) return true;
    final memberships = content['memberships'];
    if (memberships is! List || memberships.isEmpty) continue;
    for (final raw in memberships) {
      if (raw is! Map) continue;
      if (_slotMembershipActive(Map<String, dynamic>.from(raw), nowMs)) {
        return true;
      }
    }
  }
  return false;
}

bool _slotMembershipActive(Map<String, dynamic> membership, int nowMs) {
  final expires = membership['expires_ts'] ?? membership['expires'];
  if (expires is num && expires.toInt() > 0 && expires.toInt() <= nowMs) {
    return false;
  }
  final kind = '${membership['membership'] ?? ''}'.toLowerCase();
  if (kind == 'leave' || kind == 'hangup') return false;
  final application = membership['application'];
  if (application is String && application.isNotEmpty) return true;
  final deviceId = membership['device_id'];
  if (deviceId is String && deviceId.isNotEmpty) {
    return kind.isEmpty ||
        kind == 'join' ||
        kind == 'call' ||
        kind == 'connected';
  }
  return false;
}

String userIdFromCallMemberStateKey(String stateKey, String sender) {
  final match = RegExp(r'(@[^:]+:[^_]+)').firstMatch(stateKey);
  return match?.group(1) ?? sender;
}
