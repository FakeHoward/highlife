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

  /// Set when WASM/native crypto init failed; UI should surface this prominently.
  final String? error;
}

/// Load vodozemac WASM from `web/pkg/` when present.
///
/// On failure the app still boots with [NativeImplementations.dummy], but
/// [CryptoInitResult.available] is false and [CryptoInitResult.error] explains why.
///
/// Build artifacts with `scripts/build_vodozemac_wasm.sh` (or the Client CI web job).
Future<CryptoInitResult> initializeCryptoImplementations() async {
  try {
    await vodozemac
        .init(wasmPath: './pkg/')
        .timeout(const Duration(seconds: 20));
    return CryptoInitResult(
      implementations: NativeImplementationsWebWorker(
        Uri.parse('assets/packages/matrix/assets/web_worker.dart.js'),
      ),
      available: true,
    );
  } catch (error, stack) {
    final message =
        'E2EE unavailable: vodozemac WASM init failed ($error). '
        'Build web/pkg with scripts/build_vodozemac_wasm.sh or the Client CI web job.';
    debugPrint('$message\n$stack');
    return CryptoInitResult(
      implementations: NativeImplementations.dummy,
      available: false,
      error: message,
    );
  }
}
