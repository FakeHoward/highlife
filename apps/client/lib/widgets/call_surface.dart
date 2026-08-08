import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/messages.dart';
import '../services/session.dart';
import 'call_webview.dart';
import 'hl_button.dart';

/// In-app Element Call surface with WebView embed and external fallback.
class CallSurface extends StatefulWidget {
  const CallSurface({
    super.key,
    required this.callUri,
    required this.room,
    required this.session,
    required this.strings,
  });

  final Uri callUri;
  final Room room;
  final HighLifeSession session;
  final AppStrings strings;

  static Future<void> open(
    BuildContext context, {
    required Uri callUri,
    required Room room,
    required HighLifeSession session,
    required AppStrings strings,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: strings.callTitle,
      pageBuilder: (context, animation, secondaryAnimation) {
        return CallSurface(
          callUri: callUri,
          room: room,
          session: session,
          strings: strings,
        );
      },
    );
  }

  @override
  State<CallSurface> createState() => _CallSurfaceState();
}

class _CallSurfaceState extends State<CallSurface> {
  String? _bridgeNote;
  var _useExternalOnly = !CallWebView.supported;

  String get _widgetId => 'highlife_call_${widget.room.id}';

  Future<void> _openExternal() async {
    final launched = await launchUrl(
      widget.callUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      setState(() => _bridgeNote = widget.strings.couldNotOpenCall);
    }
  }

  void _onWidgetMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['api'] == 'fromWidget') {
        final action = decoded['action']?.toString();
        if (action == 'content_loaded' || action == 'capabilities') {
          setState(() => _bridgeNote = widget.strings.widgetReady);
        }
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _sendEvent({
    required String type,
    required Map<String, dynamic> content,
    String? stateKey,
    String? roomId,
  }) {
    return widget.session.sendWidgetRoomEvent(
      roomId: roomId ?? widget.room.id,
      type: type,
      content: content,
      stateKey: stateKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.callTitle),
        leading: IconButton(
          tooltip: s.leaveCall,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close),
        ),
        actions: [
          HlButton.text(
            onPressed: _openExternal,
            label: Text(s.openExternally),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_bridgeNote != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_bridgeNote!),
              ),
            ),
          Expanded(
            child: _useExternalOnly
                ? _Fallback(
                    message: s.embedUnsupported,
                    openLabel: s.openExternally,
                    onOpen: _openExternal,
                  )
                : CallWebView(
                    uri: widget.callUri,
                    widgetId: _widgetId,
                    roomId: widget.room.id,
                    sendEvent: _sendEvent,
                    onWidgetMessage: _onWidgetMessage,
                    onReady: () {
                      if (mounted) {
                        setState(() => _bridgeNote = s.widgetReady);
                      }
                    },
                    onUnsupported: () {
                      if (mounted) setState(() => _useExternalOnly = true);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.message,
    required this.openLabel,
    required this.onOpen,
  });

  final String message;
  final String openLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.call_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            HlButton.primary(onPressed: onOpen, label: Text(openLabel)),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              Text(
                'Web build',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
