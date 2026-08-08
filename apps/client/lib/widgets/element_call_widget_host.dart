import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Matrix Widget API host bridge for Element Call (parity with web widgetHost.ts).
typedef WidgetSendEventFn = Future<Map<String, dynamic>> Function({
  required String type,
  required Map<String, dynamic> content,
  String? stateKey,
  String? roomId,
});

const _supportedApiVersions = [
  '0.0.1',
  '0.0.2',
  'org.matrix.msc2762',
  'org.matrix.msc2876',
  'org.matrix.msc2931',
  'org.matrix.msc2974',
];

const _defaultCapabilities = [
  'm.always_on_screen',
  'org.matrix.msc2762.timeline.*',
  'org.matrix.msc2762.send.event:m.room.message',
  'org.matrix.msc2762.receive.event:m.room.message',
  'org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member',
  'org.matrix.msc2762.receive.state_event:org.matrix.msc3401.call.member',
  'org.matrix.msc2762.send.event:org.matrix.msc4075.rtc.notification',
  'org.matrix.msc2762.receive.event:org.matrix.msc4075.rtc.notification',
  'org.matrix.msc2762.send.to_device',
  'org.matrix.msc2762.receive.to_device',
];

class ElementCallWidgetHost {
  ElementCallWidgetHost({
    required this.widgetId,
    required this.roomId,
    required this.controller,
    this.sendEvent,
    this.onCapabilityChange,
  });

  final String widgetId;
  final String roomId;
  final WebViewController controller;
  final WidgetSendEventFn? sendEvent;
  final VoidCallback? onCapabilityChange;

  final _approved = {..._defaultCapabilities};

  Future<void> handleRaw(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      if (message['api'] != 'fromWidget') return;
      final action = message['action']?.toString();
      final requestId = message['requestId'];
      if (action == null || requestId == null) return;
      final incomingWidgetId = message['widgetId']?.toString();
      if (incomingWidgetId != null &&
          incomingWidgetId.isNotEmpty &&
          incomingWidgetId != widgetId) {
        return;
      }
      await _handle(message, action);
    } catch (error, stack) {
      debugPrint('ElementCallWidgetHost: $error\n$stack');
    }
  }

  Future<void> _handle(Map<String, dynamic> request, String action) async {
    if (action == 'content_loaded') {
      await _reply(request, {});
      await _notifyCapabilities();
      return;
    }

    if (action == 'supported_api_versions') {
      await _reply(request, {'supported_versions': _supportedApiVersions});
      return;
    }

    if (action == 'capabilities' ||
        action == 'org.matrix.msc2974.request_capabilities') {
      final data = request['data'];
      final requested = data is Map && data['capabilities'] is List
          ? (data['capabilities'] as List).whereType<String>()
          : _defaultCapabilities;
      _approved.addAll(requested);
      await _reply(request, {'capabilities': _approved.toList()});
      await _notifyCapabilities();
      onCapabilityChange?.call();
      return;
    }

    if (action == 'set_always_on_screen') {
      await _reply(request, {'success': true});
      return;
    }

    if (action == 'get_openid') {
      await _reply(request, {'state': 'blocked'});
      return;
    }

    if (action == 'send_event') {
      final data = request['data'] is Map
          ? Map<String, dynamic>.from(request['data'] as Map)
          : <String, dynamic>{};
      final type = data['type']?.toString() ?? '';
      final content = data['content'] is Map
          ? Map<String, dynamic>.from(data['content'] as Map)
          : <String, dynamic>{};
      final stateKey = data['state_key'] as String?;
      final roomId = data['room_id'] as String? ?? this.roomId;
      final send = sendEvent;
      if (send == null || type.isEmpty) {
        await _reply(request, {
          'error': {
            'message': 'send_event is not available',
            'url': '',
            'http_status': 400,
          },
        });
        return;
      }
      try {
        final result = await send(
          type: type,
          content: content,
          stateKey: stateKey,
          roomId: roomId,
        );
        await _reply(request, {
          'room_id': roomId,
          'event_id': result['event_id'] ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
        });
      } catch (error) {
        await _reply(request, {
          'error': {
            'message': error.toString(),
            'url': '',
            'http_status': 500,
          },
        });
      }
      return;
    }

    if (action == 'send_to_device' ||
        action == 'update_immediate_device_list') {
      await _reply(request, {});
      return;
    }

    await _reply(request, {});
  }

  Future<void> _notifyCapabilities() async {
    final payload = jsonEncode({
      'api': 'toWidget',
      'requestId': 'highlife_caps_${DateTime.now().millisecondsSinceEpoch}',
      'widgetId': widgetId,
      'action': 'notify_capabilities',
      'data': {
        'approved': _approved.toList(),
        'requested': _approved.toList(),
      },
    });
    await controller.runJavaScript('window.postMessage($payload, "*");');
  }

  Future<void> _reply(
    Map<String, dynamic> request,
    Map<String, dynamic> response,
  ) async {
    final payload = jsonEncode({
      ...request,
      'api': 'toWidget',
      'response': response,
    });
    await controller.runJavaScript('window.postMessage($payload, "*");');
  }
}
