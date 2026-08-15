import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/spec_features.dart';

void main() {
  test('intentional mentions collect mxids and @room', () {
    final mentions = intentionalMentions('hey @alice:example.org and @room', [
      '@alice:example.org',
      '@bob:example.org',
    ]);
    expect(mentions.userIds, ['@alice:example.org']);
    expect(mentions.room, isTrue);
  });

  test('thread replies stay off the main timeline unless fallback', () {
    expect(
      belongsOnMainTimeline({
        'm.relates_to': {
          'rel_type': 'm.thread',
          'event_id': 'root',
          'is_falling_back': false,
        },
      }),
      isFalse,
    );
    expect(
      belongsOnMainTimeline({
        'm.relates_to': {
          'rel_type': 'm.thread',
          'event_id': 'root',
          'is_falling_back': true,
        },
      }),
      isTrue,
    );
    expect(threadRelation('root')['is_falling_back'], isTrue);
    expect(
      threadRelation('root', replyToId: 'root', fallback: false)['is_falling_back'],
      isFalse,
    );
  });

  test('location content round-trips MSC3488', () {
    final content = locationContent(55.75, 37.62, description: 'Red Square');
    expect(content['msgtype'], 'm.location');
    final parsed = parseLocationContent(Map<String, dynamic>.from(content));
    expect(parsed?.lat, 55.75);
    expect(parsed?.description, 'Red Square');
  });

  test('image pack parser ignores non-mxc urls', () {
    final items = parseImagePack({
      'images': {
        'wave': {'url': 'mxc://example.org/abc', 'body': 'wave'},
        'skip': {'url': 'https://evil.example/x.png'},
      },
    });
    expect(items, hasLength(1));
    expect(stickerContent(items.single)['url'], 'mxc://example.org/abc');
  });

  test('MSC4139 prompts parse preset buttons', () {
    final parsed = parseMsc4139Prompts({
      msc4139PromptsKey: {
        'prompts': [
          {
            'type': 'preset',
            'id': '1d6',
            'label': {
              'm.text': [
                {'body': '1d6'},
              ],
            },
          },
        ],
      },
    });
    expect(parsed?.prompts.single.id, '1d6');
    expect(conversationReplyContent(promptId: '1d6', label: '1d6', rootEventId: r'$w')['body'], '1d6');
  });

  test('sliding sync flags and subscription path', () {
    expect(slidingSyncSupported({'org.matrix.simplified_msc3575': true}), isTrue);
    expect(threadSubscriptionPath('!r:ex', r'$t'), contains('msc4306'));
    expect(parseRoomSummary({'name': 'Lobby'}, '!x:ex').name, 'Lobby');
    expect(matrixApiAction(threadSubscriptionPath('!r:ex', r'$t')), startsWith('/client/'));
    expect(
      parseSlidingSyncRoomOrder({
        'lists': {
          'all': {
            'ops': [
              {
                'op': 'SYNC',
                'room_ids': ['!a:ex', '!b:ex'],
              },
            ],
          },
        },
      }),
      ['!a:ex', '!b:ex'],
    );
    expect(parseProfileAbout({profileAboutKey: 'hello from HighLife'}), 'hello from HighLife');
    expect(firstHttpUrl('see https://example.org/a, then text'), 'https://example.org/a');
    expect(
      parseUrlPreview({'og:title': 'Example'}, 'https://example.org')?.title,
      'Example',
    );
  });

  test('MSC4332 commands parse nested and top-level command lists', () {
    final nested = parseCommandsState({
      msc4332CommandsState: {
        'commands': [
          {'name': 'roll', 'aliases': ['r'], 'description': 'dice'},
        ],
      },
    });
    expect(nested.single.name, 'roll');
    expect(nested.single.aliases, ['r']);
    final top = parseCommandsState({
      'commands': [
        {'name': 'help'},
      ],
    });
    expect(top.single.name, 'help');
  });

  test('login QR payload stays a local matrix: URI', () {
    expect(
      matrixLoginQrPayload(
        homeserver: 'https://matrix.example.org',
        deviceId: 'DEVICE',
        userId: '@alice:example.org',
      ),
      startsWith('matrix://login?'),
    );
  });
}
