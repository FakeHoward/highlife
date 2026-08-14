import 'package:flutter/foundation.dart';

/// webview_flutter hosts Android, iOS, and macOS. Windows/Linux fall back
/// to the system browser until a desktop WebView plugin is wired.
bool get embeddedWebViewAvailable {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}
