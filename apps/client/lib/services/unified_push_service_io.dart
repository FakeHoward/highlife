import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:unifiedpush/unifiedpush.dart';

/// Registers UnifiedPush on Android and forwards the endpoint as a Matrix pushkey.
///
/// Skips iOS, web, and desktop. Requires a UnifiedPush distributor on device.
/// HTTP pusher registration is gated by [PushService.isConfigured]
/// (`HIGHLIFE_PUSH_GATEWAY_URL`).
class UnifiedPushService {
  UnifiedPushService({required this.onEndpoint});

  final Future<void> Function(String endpoint) onEndpoint;

  static const _instance = 'highlife';
  var _started = false;

  Future<void> start() async {
    if (_started) return;
    if (kIsWeb) return;
    // Ignore iOS entirely per release scope; desktop has no UP distributor path.
    if (!Platform.isAndroid) return;
    _started = true;

    try {
      await UnifiedPush.initialize(
        onNewEndpoint: (endpoint, instance) {
          if (instance != _instance && instance.isNotEmpty) return;
          final url = endpoint.url.trim();
          if (url.isEmpty) return;
          // ignore: discarded_futures
          onEndpoint(url);
        },
        onRegistrationFailed: (_, __) {},
        onUnregistered: (_) {},
        onMessage: (_, __) {
          // Matrix push gateway delivers via HTTP; no local decrypt path here.
        },
      );

      final ok = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
      if (ok) {
        await UnifiedPush.register(instance: _instance);
        return;
      }

      final distributors = await UnifiedPush.getDistributors();
      if (distributors.isEmpty) return;
      await UnifiedPush.saveDistributor(distributors.first);
      await UnifiedPush.register(instance: _instance);
    } catch (e, st) {
      debugPrint('UnifiedPush start failed: $e\n$st');
      // Push remains optional — do not register a fake deviceID pushkey.
    }
  }

  void dispose() {
    _started = false;
  }
}
