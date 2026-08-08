/// Stub for web / non-IO platforms — UnifiedPush is Android-only here.
class UnifiedPushService {
  UnifiedPushService({required this.onEndpoint});

  final Future<void> Function(String endpoint) onEndpoint;

  Future<void> start() async {}

  void dispose() {}
}
