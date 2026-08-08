import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Registers an HTTP Matrix pusher when a push gateway is configured.
///
/// Compile-time:
/// - `HIGHLIFE_PUSH_GATEWAY_URL` — Sygnal/ntfy-compatible gateway URL
/// - `HIGHLIFE_PUSH_APP_ID` — defaults to `app.highlife.android`
///
/// Call [registerHttpPusher] only with a real UnifiedPush/FCM endpoint.
/// Do not pass `deviceID` as a fake pushkey — without an OS token, skip
/// registration until [UnifiedPushService] (or FCM) provides one.
class PushService {
  PushService(this._client);

  final Client _client;

  static const gatewayUrl = String.fromEnvironment(
    'HIGHLIFE_PUSH_GATEWAY_URL',
    defaultValue: '',
  );

  static const appId = String.fromEnvironment(
    'HIGHLIFE_PUSH_APP_ID',
    defaultValue: 'app.highlife.android',
  );

  bool get isConfigured => gatewayUrl.trim().isNotEmpty;

  /// Register (or refresh) an HTTP pusher. [pushkey] is typically an FCM/UnifiedPush token.
  Future<void> registerHttpPusher({
    required String pushkey,
    String? deviceDisplayName,
  }) async {
    final gateway = gatewayUrl.trim();
    final key = pushkey.trim();
    if (gateway.isEmpty || key.isEmpty) return;

    final display = deviceDisplayName ?? _defaultDeviceName();
    final clipped =
        display.length <= 64 ? display : display.substring(0, 64);

    final data = <String, Object?>{
      'pushkey': key,
      'kind': 'http',
      'app_id': appId,
      'app_display_name': 'HighLife',
      'device_display_name': clipped,
      'lang': 'en',
      'data': {
        'url': gateway.replaceAll(RegExp(r'/+$'), ''),
        'format': 'event_id_only',
      },
      'append': false,
    };

    await _client.request(
      RequestType.POST,
      '/client/v3/pushers/set',
      data: data,
    );
  }

  String _defaultDeviceName() {
    if (kIsWeb) return 'HighLife Web';
    try {
      return 'HighLife ${Platform.operatingSystem}';
    } catch (_) {
      return 'HighLife';
    }
  }
}
