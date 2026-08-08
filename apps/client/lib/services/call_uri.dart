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

/// Heuristic active MatrixRTC session via MSC3401 call.member state contents.
bool hasActiveCallMemberStates(
  Iterable<Map<String, dynamic>> memberContents,
) {
  for (final content in memberContents) {
    if (content.isEmpty) continue;
    final memberships = content['memberships'];
    if (memberships is List && memberships.isNotEmpty) return true;
    if (content.containsKey('devices') ||
        content.containsKey('m.devices') ||
        content.containsKey('m.call') ||
        content.containsKey('m.application')) {
      return true;
    }
  }
  return false;
}
