import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:matrix/matrix.dart';

class CryptoInitResult {
  const CryptoInitResult({
    required this.implementations,
    required this.available,
    this.error,
  });

  final NativeImplementations implementations;
  final bool available;

  /// Set when native crypto init failed; UI should surface this prominently.
  final String? error;
}

/// Load Rust vodozemac; keep dummy so the UI can still start when init fails.
Future<CryptoInitResult> initializeCryptoImplementations() async {
  try {
    await vodozemac.init().timeout(const Duration(seconds: 20));
    return CryptoInitResult(
      implementations: NativeImplementationsIsolate(
        compute,
        vodozemacInit: () => vodozemac.init(),
      ),
      available: true,
    );
  } catch (error, stack) {
    final message =
        'E2EE unavailable: vodozemac init failed ($error). '
        'Encrypted rooms will not decrypt on this device.';
    debugPrint('$message\n$stack');
    return CryptoInitResult(
      implementations: NativeImplementations.dummy,
      available: false,
      error: message,
    );
  }
}
