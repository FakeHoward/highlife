import 'dart:convert';

import '../hl_kit.dart';
import '../platform/embedded_webview.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'element_call_widget_host.dart';

export 'element_call_widget_host.dart'
    show WidgetSendEventFn, WidgetUploadFn, WidgetDownloadFn;

/// Native (IO) WebView embed for Element Call + Widget API bridge.
class CallWebView extends StatefulWidget {
  const CallWebView({
    super.key,
    required this.uri,
    required this.widgetId,
    required this.roomId,
    required this.onWidgetMessage,
    required this.onUnsupported,
    this.sendEvent,
    this.uploadContent,
    this.downloadContent,
    this.onReady,
  });

  final Uri uri;
  final String widgetId;
  final String roomId;
  final ValueChanged<String> onWidgetMessage;
  final VoidCallback onUnsupported;
  final WidgetSendEventFn? sendEvent;
  final WidgetUploadFn? uploadContent;
  final WidgetDownloadFn? downloadContent;
  final VoidCallback? onReady;

  static bool get supported => embeddedWebViewAvailable;

  @override
  State<CallWebView> createState() => _CallWebViewIoState();
}

class _CallWebViewIoState extends State<CallWebView> {
  WebViewController? _controller;
  ElementCallWidgetHost? _host;
  var _failed = false;

  String get _allowedOrigin => widget.uri.origin;

  @override
  void initState() {
    super.initState();
    _init();
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final requested = Uri.tryParse(request.url);
    if (requested == null) return NavigationDecision.prevent;
    try {
      if (requested.origin == _allowedOrigin) {
        return NavigationDecision.navigate;
      }
    } catch (_) {
      // Non-http(s) URLs have no origin; block them.
    }
    return NavigationDecision.prevent;
  }

  Future<void> _init() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'HighLifeBridge',
        onMessageReceived: (message) {
          widget.onWidgetMessage(message.message);
          final host = _host;
          if (host != null) {
            host.handleRaw(message.message);
          }
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageFinished: (_) => _injectBridge(controller),
        ),
      );
      await controller.loadRequest(widget.uri);
      if (!mounted) return;
      _host = ElementCallWidgetHost(
        widgetId: widget.widgetId,
        roomId: widget.roomId,
        controller: controller,
        targetOrigin: _allowedOrigin,
        sendEvent: widget.sendEvent,
        uploadContent: widget.uploadContent,
        downloadContent: widget.downloadContent,
        onCapabilityChange: widget.onReady,
      );
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onUnsupported();
    }
  }

  Future<void> _injectBridge(WebViewController controller) async {
    final allowedOrigin = jsonEncode(_allowedOrigin);
    await controller.runJavaScript('''
(function() {
  if (window.__highlifeBridge) return;
  window.__highlifeBridge = true;
  var allowedOrigin = $allowedOrigin;
  window.addEventListener('message', function(event) {
    try {
      if (event.origin !== allowedOrigin) return;
      var data = event.data;
      var payload = (typeof data === 'string') ? data : JSON.stringify(data);
      HighLifeBridge.postMessage(payload);
    } catch (e) {}
  });
})();
''');
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
