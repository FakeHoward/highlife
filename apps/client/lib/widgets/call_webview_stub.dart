import 'package:flutter/widgets.dart';

import 'element_call_widget_host.dart';

export 'element_call_widget_host.dart'
    show WidgetSendEventFn, WidgetUploadFn, WidgetDownloadFn;

/// Fallback when neither dart:io nor dart:html is available.
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

  static const supported = false;

  @override
  State<CallWebView> createState() => _CallWebViewStubState();
}

class _CallWebViewStubState extends State<CallWebView> {
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
