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

const _sendEventPrefix = 'org.matrix.msc2762.send.event:';
const _sendStateEventPrefix = 'org.matrix.msc2762.send.state_event:';
const _receiveEventPrefix = 'org.matrix.msc2762.receive.event:';
const _receiveStateEventPrefix = 'org.matrix.msc2762.receive.state_event:';

/// Event types Element Call may need beyond the static defaults.
bool _isAllowedCallEventType(String type) {
  if (type == 'm.room.message') return true;
  if (type == 'org.matrix.msc4075.rtc.notification') return true;
  if (type == 'org.matrix.rageshake.request') return true;
  if (type == 'org.matrix.msc3401.call' ||
      type == 'org.matrix.msc3401.call.member') {
    return true;
  }
  if (type.startsWith('m.call.')) return true;
  if (type.startsWith('org.matrix.msc3401.call')) return true;
  return false;
}

/// Whether a capability string may be granted to the Element Call widget.
@visibleForTesting
bool isGrantableWidgetCapability(String capability) {
  if (_defaultCapabilities.contains(capability)) return true;
  if (capability == 'm.always_on_screen') return true;
  if (capability.startsWith('org.matrix.msc2762.timeline')) return true;
  if (capability == 'org.matrix.msc2762.send.to_device' ||
      capability == 'org.matrix.msc2762.receive.to_device') {
    return true;
  }

  final String? eventType;
  if (capability.startsWith(_sendEventPrefix)) {
    eventType = capability.substring(_sendEventPrefix.length);
  } else if (capability.startsWith(_receiveEventPrefix)) {
    eventType = capability.substring(_receiveEventPrefix.length);
  } else if (capability.startsWith(_sendStateEventPrefix)) {
    eventType = capability.substring(_sendStateEventPrefix.length);
  } else if (capability.startsWith(_receiveStateEventPrefix)) {
    eventType = capability.substring(_receiveStateEventPrefix.length);
  } else {
    return false;
  }

  // Never grant unrestricted wildcards.
  if (eventType == '*' || eventType.isEmpty) return false;
  return _isAllowedCallEventType(eventType);
}

/// Whether [approved] includes a send capability covering [type].
@visibleForTesting
bool hasSendEventCapability(
  Set<String> approved,
  String type, {
  required bool isState,
}) {
  if (type.isEmpty) return false;
  final exact = isState
      ? '$_sendStateEventPrefix$type'
      : '$_sendEventPrefix$type';
  final wildcard =
      isState ? '${_sendStateEventPrefix}*' : '${_sendEventPrefix}*';
  return approved.contains(exact) || approved.contains(wildcard);
}

class ElementCallWidgetHost {
  ElementCallWidgetHost({
    required this.widgetId,
    required this.roomId,
    required this.controller,
    required this.targetOrigin,
    this.sendEvent,
    this.onCapabilityChange,
  });

  final String widgetId;
  final String roomId;
  final WebViewController controller;
  /// Origin of the embedded call widget URI; used for postMessage target.
  final String targetOrigin;
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
      for (final capability in requested) {
        if (isGrantableWidgetCapability(capability)) {
          _approved.add(capability);
        }
      }
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
      final isState = data.containsKey('state_key');
      // Always send into the call room; ignore widget-supplied room_id.
      final roomId = this.roomId;
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
      if (!hasSendEventCapability(_approved, type, isState: isState)) {
        await _reply(request, {
          'error': {
            'message': 'send_event capability not approved for $type',
            'url': '',
            'http_status': 403,
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
          'event_id': result['event_id'] ??
              'local_${DateTime.now().millisecondsSinceEpoch}',
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
    final origin = jsonEncode(targetOrigin);
    await controller.runJavaScript('window.postMessage($payload, $origin);');
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
    final origin = jsonEncode(targetOrigin);
    await controller.runJavaScript('window.postMessage($payload, $origin);');
  }
}
