import 'package:flutter/widgets.dart';

/// Fallback when an in-app MiniApp WebView is unavailable.
class MiniAppWebView extends StatefulWidget {
  const MiniAppWebView({
    super.key,
    required this.uri,
    required this.onBridgeMessage,
    required this.onUnsupported,
    this.initPayload,
  });

  final Uri uri;
  final ValueChanged<Map<String, dynamic>> onBridgeMessage;
  final VoidCallback onUnsupported;
  final Map<String, dynamic>? initPayload;

  static const supported = false;

  @override
  State<MiniAppWebView> createState() => _MiniAppWebViewStubState();
}

class _MiniAppWebViewStubState extends State<MiniAppWebView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onUnsupported();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
