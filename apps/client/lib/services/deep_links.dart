import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'auth_errors.dart';

class DeepLink {
  const DeepLink({this.loginToken, this.roomId});

  final String? loginToken;
  final String? roomId;
}

DeepLink? parseHighLifeDeepLink(Uri uri) {
  final token = loginTokenFromRedirect(uri);
  final roomId = uri.queryParameters['room'] ??
      uri.queryParameters['id'] ??
      uri.queryParameters['room_id'];
  final room = roomId != null && roomId.startsWith('!') ? roomId : null;
  if (token == null && room == null) return null;
  return DeepLink(loginToken: token, roomId: room);
}

/// Listens for `highlife://` redirects (SSO token + room from push).
class DeepLinkListener {
  DeepLinkListener({required this.onLink});

  final void Function(DeepLink link) onLink;
  StreamSubscription<Uri>? _sub;
  String? _consumedInitial;

  Future<void> start() async {
    if (kIsWeb) return;
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null) {
        _consumedInitial = initial.toString();
        final parsed = parseHighLifeDeepLink(initial);
        if (parsed != null) onLink(parsed);
      }
    } catch (_) {}
    _sub = links.uriLinkStream.listen((uri) {
      if (uri.toString() == _consumedInitial) {
        _consumedInitial = null;
        return;
      }
      final parsed = parseHighLifeDeepLink(uri);
      if (parsed != null) onLink(parsed);
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
