import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/push_copy.dart';

void main() {
  test('uses explicit body text', () {
    expect(pushNotificationBody({'body': '  Hello  '}), 'Hello');
  });

  test('falls back to unread counts', () {
    expect(
      pushNotificationBody({
        'counts': {'unread': 3},
      }),
      '3 unread messages',
    );
  });

  test('reads room id from event_id_only payloads', () {
    expect(
      roomIdFromPush({'room_id': '!chat:example.org'}),
      '!chat:example.org',
    );
    expect(roomIdFromPush({'body': 'x'}), isNull);
  });

  test('decodes JSON push bytes and raw text', () {
    expect(
      decodePushBytes(utf8.encode('{"room_id":"!chat:example.org"}')),
      {'room_id': '!chat:example.org'},
    );
    expect(decodePushBytes(utf8.encode('hello')), 'hello');
    expect(decodePushBytes(const []), isNull);
  });
}
