import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'call_uri.dart';

/// Element Call / matrix-js-sdk MatrixRTC to-device media key event.
const callEncryptionKeysEventType = 'io.element.call.encryption_keys';

/// LiveKit frame keys are 128-bit; Element Call imports them as HKDF material.
const callEncryptionKeyBytes = 16;

class CallPeer {
  const CallPeer({required this.userId, required this.deviceId});

  final String userId;
  final String deviceId;

  String get rtcBackendIdentity => '$userId:$deviceId';
}

class CallEncryptionKey {
  const CallEncryptionKey({
    required this.senderUserId,
    required this.deviceId,
    required this.memberId,
    required this.key,
    required this.index,
  });

  final String senderUserId;
  final String deviceId;
  final String memberId;
  final Uint8List key;
  final int index;

  String get rtcBackendIdentity => '$senderUserId:$deviceId';
}

String rtcBackendIdentity(String userId, String deviceId) => '$userId:$deviceId';

Uint8List generateCallEncryptionKey([Random? random]) {
  final rng = random ?? Random.secure();
  return Uint8List.fromList(
    List<int>.generate(callEncryptionKeyBytes, (_) => rng.nextInt(256)),
  );
}

Map<String, dynamic> callEncryptionToDeviceContent({
  required String roomId,
  required String deviceId,
  required String memberId,
  required Uint8List key,
  required int index,
  int? sentTs,
}) {
  return {
    'keys': {
      'index': index,
      'key': base64Encode(key),
    },
    'room_id': roomId,
    'member': {
      'claimed_device_id': deviceId,
      'id': memberId,
    },
    'session': {
      'call_id': '',
      'application': 'm.call',
      'scope': 'm.room',
    },
    'sent_ts': sentTs ?? DateTime.now().millisecondsSinceEpoch,
  };
}

CallEncryptionKey? parseCallEncryptionToDevice({
  required String sender,
  required String roomId,
  required Map<String, dynamic> content,
}) {
  if (content['room_id'] != roomId) return null;
  final keys = content['keys'];
  if (keys is! Map) return null;
  final encoded = keys['key'];
  final index = keys['index'];
  if (encoded is! String || index is! num) return null;
  final member = content['member'];
  if (member is! Map) return null;
  final deviceId = member['claimed_device_id'];
  if (deviceId is! String || deviceId.isEmpty) return null;
  final memberId = member['id'] is String && (member['id'] as String).isNotEmpty
      ? member['id'] as String
      : '$sender:$deviceId';
  try {
    return CallEncryptionKey(
      senderUserId: sender,
      deviceId: deviceId,
      memberId: memberId,
      key: Uint8List.fromList(base64Decode(encoded)),
      index: index.toInt(),
    );
  } on FormatException {
    return null;
  }
}

List<CallPeer> callPeersFromMemberContent({
  required String sender,
  required String stateKey,
  required Map<String, dynamic> content,
}) {
  final userId = userIdFromCallMemberStateKey(stateKey, sender);
  final seen = <String>{};
  final peers = <CallPeer>[];
  void add(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return;
    final key = '$userId:$deviceId';
    if (!seen.add(key)) return;
    peers.add(CallPeer(userId: userId, deviceId: deviceId));
  }

  final top = content['device_id'];
  if (top is String) add(top);
  final memberships = content['memberships'];
  if (memberships is List) {
    for (final raw in memberships) {
      if (raw is! Map) continue;
      final deviceId = raw['device_id'];
      if (deviceId is String) add(deviceId);
    }
  }
  return peers;
}

Map<String, Map<String, Map<String, dynamic>>> toDeviceMessages({
  required Iterable<CallPeer> peers,
  required String selfUserId,
  required String selfDeviceId,
  required Map<String, dynamic> content,
}) {
  final messages = <String, Map<String, Map<String, dynamic>>>{};
  for (final peer in peers) {
    if (peer.userId == selfUserId && peer.deviceId == selfDeviceId) continue;
    messages.putIfAbsent(peer.userId, () => <String, Map<String, dynamic>>{});
    messages[peer.userId]![peer.deviceId] = content;
  }
  return messages;
}
