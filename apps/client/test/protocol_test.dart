import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/aiomatrix/protocol.dart';

void main() {
  test('parses shared contracts keyboard fixture', () {
    final fixture = File('../../contracts/fixtures/dev.aiomatrix.keyboard.json');
    expect(fixture.existsSync(), isTrue);
    final parsed = KeyboardContent.tryParse({
      keyboardContentKey: jsonDecode(fixture.readAsStringSync()),
    });
    expect(parsed, isNotNull);
    expect(parsed!.inline, hasLength(2));
    expect(parsed.inline.first.first.kind, ButtonKind.callback);
    expect(parsed.inline.last.last.kind, ButtonKind.command);
    expect(parsed.fallbackCommand, 'cb');
  });

  test('parses keyboard and ignores malformed buttons', () {
    final kb = KeyboardContent.tryParse({
      keyboardContentKey: {
        'version': 1,
        'inline': [
          [
            {'kind': 'callback', 'text': 'Yes', 'data': 'vote:yes', 'token': 't1'},
            {'kind': 'url', 'text': 'Docs', 'url': 'https://example.org'},
            {'kind': 'callback', 'text': '  '},
          ],
        ],
      },
    });
    expect(kb, isNotNull);
    expect(kb!.inline.first.first.kind, ButtonKind.callback);
    expect(kb.inline.first, hasLength(2));
  });

  test('filters commands by name and aliases', () {
    final cmds = [
      const AdvertisedCommand(name: 'start', description: 'hi'),
      const AdvertisedCommand(name: 'suggest', aliases: ['offer']),
    ];
    expect(filterSuggestions(cmds, '/s').map((c) => c.name), ['start', 'suggest']);
    expect(filterSuggestions(cmds, '!of').single.name, 'suggest');
    expect(filterSuggestions(cmds, 'hello'), isEmpty);
  });

  test('completes a command while preserving its prefix', () {
    const command = AdvertisedCommand(name: 'start', args: '<topic>');
    expect(completeCommand(command, typed: '!st'), '!start ');
  });

  test('allows secure MiniApps and local development only', () {
    expect(isSafeHttpUrl('https://example.org/app', requireHttps: true), isTrue);
    expect(isSafeHttpUrl('http://localhost:3000/app', requireHttps: true), isTrue);
    expect(isSafeHttpUrl('http://example.org/app', requireHttps: true), isFalse);
    expect(isSafeHttpUrl('javascript:alert(1)'), isFalse);
  });

  test('humanizes MiniApp publish JSON and room previews', () {
    final raw = jsonEncode({
      'action': 'publish',
      'kind': 'rsvp',
      'title': 'Event RSVP',
      'description': 'Built with FormSpace on your Matrix homeserver.',
      'fields': [
        {
          'id': 'f1',
          'type': 'single',
          'label': 'Attendance',
          'required': true,
        },
      ],
      'policy': 'public',
      'anonymous': false,
      'oneResponse': true,
      'deadlineMs': null,
    });
    expect(humanizeStructuredPayload(raw), 'Published RSVP: Event RSVP');
    expect(
      formatMessagePreview({
        'msgtype': miniAppDataMsgType,
        'body': raw,
        miniAppDataKey: {'version': 1, 'data': raw},
      }),
      'Published RSVP: Event RSVP',
    );
    expect(
      buildMiniAppDataContent(data: raw)['body'],
      'Published RSVP: Event RSVP',
    );
    expect(
      formatMessagePreview({
        'body': '**FormSpace** welcome\n\n1. Survey → !cb aaa.bbb.ccc',
        keyboardContentKey: {'inline': []},
      }),
      'FormSpace welcome',
    );
  });

  test('aware host capabilities content matches aiomatrix handshake', () {
    final content = buildHostCapabilitiesContent();
    expect(content['version'], hostCapabilitiesSchemaVersion);
    expect(content['client_profile'], 'aware');
    expect(content['callback_answer'], isTrue);
    expect(content['toast'], isTrue);
    expect(content['progress'], isTrue);
    expect(content['mini_app'], isTrue);
    expect(content['features'], contains('keyboard'));
    expect(content['features'], contains('callback_answer'));
    expect(hostCapabilitiesStateEventType, 'dev.aiomatrix.host');
    expect(callbackAnswerEventType, 'dev.aiomatrix.callback_answer');
    expect(toastEventType, 'dev.aiomatrix.toast');
    expect(progressEventType, 'dev.aiomatrix.progress');
  });
}
