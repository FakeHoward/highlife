/// Stub for web / non-IO platforms — UnifiedPush is Android-only here.
class UnifiedPushService {
  UnifiedPushService({required this.onEndpoint, this.onMessage});

  final Future<void> Function(String endpoint) onEndpoint;
  final Future<void> Function(Object? payload)? onMessage;

  Future<void> start() async {}

  void dispose() {}
}
