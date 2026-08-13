import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/matrix_rtc_e2ee.dart';

void main() {
  test('round-trips Element Call to-device media keys', () {
    final key = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final content = callEncryptionToDeviceContent(
      roomId: '!room:example.org',
      deviceId: 'DEVICE',
      memberId: '@me:example.org:DEVICE',
      key: key,
      index: 0,
      sentTs: 1,
    );
    expect(content['session'], {
      'call_id': '',
      'application': 'm.call',
      'scope': 'm.room',
    });
    final parsed = parseCallEncryptionToDevice(
      sender: '@me:example.org',
      roomId: '!room:example.org',
      content: content,
    );
    expect(parsed, isNotNull);
    expect(parsed!.index, 0);
    expect(parsed.deviceId, 'DEVICE');
    expect(parsed.rtcBackendIdentity, '@me:example.org:DEVICE');
    expect(parsed.key, key);
    expect((content['keys'] as Map)['key'], base64Encode(parsed.key));
  });

  test('ignores keys for a different room', () {
    expect(
      parseCallEncryptionToDevice(
        sender: '@ada:example.org',
        roomId: '!here:example.org',
        content: {
          'room_id': '!other:example.org',
          'keys': {'index': 0, 'key': base64Encode(Uint8List(16))},
          'member': {'claimed_device_id': 'EX'},
        },
      ),
      isNull,
    );
  });

  test('collects MSC3401 and slot-style call peers', () {
    final nested = callPeersFromMemberContent(
      sender: '@ada:example.org',
      stateKey: '_@ada:example.org_DEVICE',
      content: {
        'memberships': [
          {'application': 'm.call', 'device_id': 'DEVICE'},
        ],
      },
    );
    expect(nested.single.rtcBackendIdentity, '@ada:example.org:DEVICE');
    final slot = callPeersFromMemberContent(
      sender: '@ada:example.org',
      stateKey: '_@ada:example.org_EX',
      content: {
        'application': 'm.call',
        'device_id': 'EX',
      },
    );
    expect(slot.single.deviceId, 'EX');
  });

  test('omits self from to-device fan-out', () {
    final messages = toDeviceMessages(
      peers: const [
        CallPeer(userId: '@me:example.org', deviceId: 'MINE'),
        CallPeer(userId: '@ada:example.org', deviceId: 'EX'),
      ],
      selfUserId: '@me:example.org',
      selfDeviceId: 'MINE',
      content: const {'keys': true},
    );
    expect(messages.keys, ['@ada:example.org']);
    expect(messages['@ada:example.org']!['EX'], {'keys': true});
  });
}
