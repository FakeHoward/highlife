import 'package:matrix/matrix.dart';

import 'call_uri.dart';

const String defaultLivekitJwtUrl =
    'https://rtc.testhighlife.strangled.net/livekit/jwt';

class LivekitFocus {
  const LivekitFocus({
    required this.serviceUrl,
    this.alias,
  });

  final String serviceUrl;
  final String? alias;
}

LivekitFocus? discoverLivekitFocus(
  Map<String, dynamic>? wellKnown, {
  String fallbackUrl = defaultLivekitJwtUrl,
}) {
  final foci = wellKnown?['org.matrix.msc4143.rtc_foci'];
  if (foci is List) {
    for (final item in foci) {
      if (item is! Map) continue;
      final focus = Map<String, dynamic>.from(item);
      if (focus['type'] != 'livekit') continue;
      final url = '${focus['livekit_service_url'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      final alias = focus['livekit_alias'];
      return LivekitFocus(
        serviceUrl: url.replaceAll(RegExp(r'/$'), ''),
        alias: alias is String && alias.isNotEmpty ? alias : null,
      );
    }
  }
  final fallback = fallbackUrl.trim().replaceAll(RegExp(r'/$'), '');
  if (fallback.isEmpty) return null;
  return LivekitFocus(serviceUrl: fallback);
}

String jwtRequestUrl(String serviceUrl, String endpoint) {
  return '${serviceUrl.replaceAll(RegExp(r'/$'), '')}/$endpoint';
}

Map<String, dynamic> legacyJwtRequestBody({
  required String roomId,
  required String deviceId,
  required Map<String, dynamic> openIdToken,
}) {
  return {
    'room': roomId,
    'device_id': deviceId,
    'openid_token': openIdToken,
  };
}

({String url, String jwt}) parseSfuConfig(Map<String, dynamic> payload) {
  final url = payload['url'];
  final jwt = payload['jwt'];
  if (url is! String || jwt is! String) {
    throw const FormatException('LiveKit JWT response is missing url or jwt');
  }
  return (url: url, jwt: jwt);
}

Map<String, dynamic> msc3401MembershipContent({
  required String deviceId,
  required String livekitServiceUrl,
  required String livekitAlias,
  DateTime? now,
}) {
  final expires = (now ?? DateTime.now())
      .add(const Duration(hours: 1))
      .millisecondsSinceEpoch;
  return {
    'memberships': [
      {
        'application': 'm.call',
        'call_id': '',
        'device_id': deviceId,
        'expires_ts': expires,
        'scope': 'm.room',
        'foci_preferred': [
          {
            'type': 'livekit',
            'livekit_service_url': livekitServiceUrl,
            'livekit_alias': livekitAlias,
          },
        ],
        'focus_active': {
          'type': 'livekit',
          'focus_selection': 'oldest_membership',
        },
      },
    ],
  };
}

String msc3401StateKey(String userId, String deviceId) => '_${userId}_$deviceId';

LivekitFocus? livekitFocusFromCallMemberContent(Map<String, dynamic> content) {
  for (final key in const ['foci_preferred', 'foci_active', 'foci']) {
    final list = content[key];
    if (list is! List) continue;
    for (final item in list) {
      if (item is! Map) continue;
      final focus = Map<String, dynamic>.from(item);
      if (focus['type'] != 'livekit') continue;
      final url = '${focus['livekit_service_url'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      final alias = focus['livekit_alias'];
      return LivekitFocus(
        serviceUrl: url.replaceAll(RegExp(r'/$'), ''),
        alias: alias is String && alias.isNotEmpty ? alias : null,
      );
    }
  }
  final memberships = content['memberships'];
  if (memberships is List) {
    for (final raw in memberships) {
      if (raw is! Map) continue;
      final nested =
          livekitFocusFromCallMemberContent(Map<String, dynamic>.from(raw));
      if (nested != null) return nested;
    }
  }
  return null;
}

LivekitFocus? remoteLivekitFocus(Room room, String selfUserId) {
  final states = room.states[callMemberStateEventType];
  if (states == null) return null;
  for (final entry in states.entries) {
        final sender = userIdFromCallMemberStateKey(
          entry.key,
          entry.value.senderId,
        );
    if (sender == selfUserId) continue;
    final focus = livekitFocusFromCallMemberContent(
      Map<String, dynamic>.from(entry.value.content),
    );
    if (focus != null) return focus;
  }
  return null;
}
