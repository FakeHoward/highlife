import '../platform/embedded_webview.dart';
import '../hl_kit.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_errors.dart';

bool get _webviewSupported => embeddedWebViewAvailable;

Future<AuthBrowserResult> showAuthWebFlow({
  required BuildContext context,
  required Uri uri,
  required String title,
  required String doneLabel,
}) async {
  if (!_webviewSupported) {
    return const AuthBrowserResult(AuthBrowserOutcome.unsupported);
  }
  final result = await Navigator.of(context).push<AuthBrowserResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _AuthWebScreen(
        uri: uri,
        title: title,
        doneLabel: doneLabel,
      ),
    ),
  );
  return result ?? const AuthBrowserResult(AuthBrowserOutcome.cancelled);
}

class _AuthWebScreen extends StatefulWidget {
  const _AuthWebScreen({
    required this.uri,
    required this.title,
    required this.doneLabel,
  });

  final Uri uri;
  final String title;
  final String doneLabel;

  @override
  State<_AuthWebScreen> createState() => _AuthWebScreenState();
}

class _AuthWebScreenState extends State<_AuthWebScreen> {
  WebViewController? _controller;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;
            if (uri.scheme == 'highlife') {
              _completeIfToken(uri);
              return NavigationDecision.prevent;
            }
            if (_completeIfToken(uri)) return NavigationDecision.prevent;
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            final uri = Uri.tryParse(url);
            if (uri != null) _completeIfToken(uri);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url == null) return;
            final uri = Uri.tryParse(url);
            if (uri != null) _completeIfToken(uri);
          },
          onWebResourceError: (_) {
            if (!mounted || _controller != null) return;
            setState(() => _failed = true);
          },
        ),
      );
      await controller.loadRequest(widget.uri);
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  bool _completeIfToken(Uri uri) {
    final token = loginTokenFromRedirect(uri);
    if (token == null) return false;
    if (!mounted) return true;
    Navigator.pop(
      context,
      AuthBrowserResult(AuthBrowserOutcome.token, token),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          onPressed: () => Navigator.pop(
            context,
            const AuthBrowserResult(AuthBrowserOutcome.cancelled),
          ),
          icon: const Icon(Icons.close),
        ),
        actions: [
          IconButton(
            tooltip: widget.doneLabel,
            onPressed: () => Navigator.pop(
              context,
              const AuthBrowserResult(AuthBrowserOutcome.finished),
            ),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: _failed || controller == null
          ? Center(
              child: HlButton.primary(
                onPressed: () => Navigator.pop(
                  context,
                  const AuthBrowserResult(AuthBrowserOutcome.unsupported),
                ),
                label: Text(widget.doneLabel),
              ),
            )
          : WebViewWidget(controller: controller),
    );
  }
}
