import 'dart:convert';

import '../hl_kit.dart';
import '../platform/embedded_webview.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Native WebView for aiomatrix MiniApps with postMessage bridge.
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

  static bool get supported => embeddedWebViewAvailable;

  @override
  State<MiniAppWebView> createState() => _MiniAppWebViewIoState();
}

class _MiniAppWebViewIoState extends State<MiniAppWebView> {
  WebViewController? _controller;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!MiniAppWebView.supported) {
      widget.onUnsupported();
      return;
    }
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'HighLifeMiniApp',
        onMessageReceived: (message) {
          _handleRaw(controller, message.message);
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectBridge(controller),
        ),
      );
      await controller.loadRequest(widget.uri);
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onUnsupported();
    }
  }

  Future<void> _injectBridge(WebViewController controller) async {
    await controller.runJavaScript('''
(function() {
  if (window.__highlifeMiniAppBridge) return;
  window.__highlifeMiniAppBridge = true;
  window.addEventListener('message', function(event) {
    try {
      var data = event.data;
      var payload = (typeof data === 'string') ? data : JSON.stringify(data);
      HighLifeMiniApp.postMessage(payload);
    } catch (e) {}
  });
})();
''');
    await _postInit(controller);
  }

  Future<void> _postInit(WebViewController controller) async {
    final payload = widget.initPayload;
    if (payload == null) return;
    final message = jsonEncode({
      'source': 'aiomatrix-miniapp',
      'type': 'init',
      'payload': payload,
    });
    final origin = jsonEncode(widget.uri.origin);
    await controller.runJavaScript(
      'window.postMessage($message, $origin);',
    );
  }

  void _handleRaw(WebViewController controller, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final type = data['type']?.toString();
      if (type == 'bridgeReady' || type == 'requestInit') {
        _postInit(controller);
        return;
      }
      widget.onBridgeMessage(data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.expand();
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: controller);
  }
}
