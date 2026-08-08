import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/call_uri.dart';

void main() {
  test('builds Element Call widget params for a room', () {
    final uri = buildElementCallUri(
      elementCallUrl: 'https://call.testhighlife.strangled.net',
      roomId: '!room:example.org',
      userId: '@alice:example.org',
      deviceId: 'DEVICE',
      homeserverUrl: 'https://testhighlife.strangled.net',
    );

    expect(uri, isNotNull);
    expect(uri!.scheme, 'https');
    expect(uri.host, 'call.testhighlife.strangled.net');
    expect(uri.queryParameters['widgetId'], 'highlife_call_!room:example.org');
    expect(uri.queryParameters['roomId'], '!room:example.org');
    expect(uri.queryParameters['userId'], '@alice:example.org');
    expect(uri.queryParameters['deviceId'], 'DEVICE');
    expect(
      uri.queryParameters['baseUrl'],
      'https://testhighlife.strangled.net',
    );
    expect(
      uri.queryParameters['parentUrl'],
      'https://call.testhighlife.strangled.net',
    );
  });

  test('honors explicit parentUrl', () {
    final uri = buildElementCallUri(
      elementCallUrl: 'https://call.testhighlife.strangled.net',
      roomId: '!room:example.org',
      parentUrl: 'https://app.example',
    );
    expect(uri!.queryParameters['parentUrl'], 'https://app.example');
  });

  test('rejects insecure non-local call URLs', () {
    expect(
      buildElementCallUri(
        elementCallUrl: 'http://evil.example/call',
        roomId: '!room:example.org',
        allowInsecureLocalhost: false,
      ),
      isNull,
    );
  });
}
