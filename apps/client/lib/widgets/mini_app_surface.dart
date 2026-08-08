import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../aiomatrix/protocol.dart';
import '../l10n/messages.dart';
import '../services/session.dart';
import '../theme.dart';
import 'hl_button.dart';
import 'mini_app_webview.dart';

/// In-app MiniApp surface mirroring React `MiniAppSurface` postMessage protocol.
class MiniAppSurface extends StatefulWidget {
  const MiniAppSurface({
    super.key,
    required this.card,
    required this.room,
    required this.messageId,
    required this.session,
    required this.strings,
  });

  final MiniAppCard card;
  final Room room;
  final String messageId;
  final HighLifeSession session;
  final AppStrings strings;

  static Future<void> open(
    BuildContext context, {
    required MiniAppCard card,
    required Room room,
    required String messageId,
    required HighLifeSession session,
    required AppStrings strings,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: card.title ?? strings.miniApp,
      pageBuilder: (context, animation, secondaryAnimation) {
        return MiniAppSurface(
          card: card,
          room: room,
          messageId: messageId,
          session: session,
          strings: strings,
        );
      },
    );
  }

  @override
  State<MiniAppSurface> createState() => _MiniAppSurfaceState();
}

class _MiniAppSurfaceState extends State<MiniAppSurface> {
  late final Uri _uri = Uri.parse(widget.card.url);
  var _useExternalOnly = !MiniAppWebView.supported;
  String? _error;

  Map<String, dynamic> get _initPayload {
    final initData = extractMiniAppInitData(widget.card.url);
    return {
      'platform': 'matrix',
      'colorScheme':
          Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light',
      if (initData != null) 'initData': initData,
      'matrix': {
        'roomId': widget.room.id,
        'botId': widget.card.botId,
        'startParam': widget.card.startParam,
      },
    };
  }

  Future<void> _openExternal() async {
    final launched = await launchUrl(
      _uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      setState(() => _error = widget.strings.couldNotOpenMiniApp);
    }
  }

  Future<void> _onBridgeMessage(Map<String, dynamic> data) async {
    final type = data['type']?.toString();
    if (type == 'close') {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (type == 'sendData') {
      final payload = data['payload'];
      final raw = payload is Map ? payload['data'] : null;
      if (raw is! String) return;
      try {
        await widget.session.sendMiniAppData(
          widget.room,
          raw,
          appId: widget.card.appId,
          messageId: widget.messageId,
        );
        if (mounted) Navigator.of(context).maybePop();
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final title = widget.card.title ?? s.miniApp;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          tooltip: s.done,
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
          if (_error != null)
            Material(
              color: Theme.of(context).extension<HighLifeTokens>()?.dangerSoft ??
                  Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color:
                        Theme.of(context).extension<HighLifeTokens>()?.danger ??
                            Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _useExternalOnly
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.miniAppEmbedUnsupported,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          HlButton.primary(
                            onPressed: _openExternal,
                            label: Text(s.openExternally),
                          ),
                        ],
                      ),
                    ),
                  )
                : MiniAppWebView(
                    uri: _uri,
                    initPayload: _initPayload,
                    onBridgeMessage: _onBridgeMessage,
                    onUnsupported: () {
                      if (!mounted) return;
                      setState(() => _useExternalOnly = true);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
