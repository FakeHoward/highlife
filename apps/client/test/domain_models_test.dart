import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/timeline_models.dart';

void main() {
  group('groupTimelineItems', () {
    test('starts a new group when the sender changes', () {
      final items = [
        TimelineItem(
          eventId: 'one',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 10),
          body: 'One',
        ),
        TimelineItem(
          eventId: 'two',
          senderId: '@bob:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 10, 1),
          body: 'Two',
        ),
      ];

      final groups = groupTimelineItems(items);

      expect(groups, hasLength(2));
      expect(groups.first.items.single.eventId, 'one');
      expect(groups.last.items.single.eventId, 'two');
    });

    test('keeps nearby messages from one sender together', () {
      final items = [
        TimelineItem(
          eventId: 'one',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 10),
          body: 'One',
        ),
        TimelineItem(
          eventId: 'two',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 10, 4),
          body: 'Two',
        ),
      ];

      final groups = groupTimelineItems(items);

      expect(groups, hasLength(1));
      expect(groups.single.items.map((item) => item.eventId), ['one', 'two']);
    });

    test('starts a new group across a day boundary', () {
      final items = [
        TimelineItem(
          eventId: 'one',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 4, 23, 59),
          body: 'One',
        ),
        TimelineItem(
          eventId: 'two',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5),
          body: 'Two',
        ),
      ];

      expect(groupTimelineItems(items), hasLength(2));
    });
  });

  test('classifies supported rich message types without discarding body', () {
    expect(
      TimelineItem.fromContent(
        eventId: 'image',
        senderId: '@alice:example.org',
        timestamp: DateTime.utc(2026),
        content: const {
          'msgtype': 'm.image',
          'body': 'photo.jpg',
          'url': 'mxc://example.org/media',
        },
      ),
      isA<MediaTimelineItem>()
          .having((item) => item.kind, 'kind', TimelineItemKind.image)
          .having((item) => item.body, 'body', 'photo.jpg'),
    );
    expect(
      TimelineItem.fromContent(
        eventId: 'voice',
        senderId: '@alice:example.org',
        timestamp: DateTime.utc(2026),
        content: const {
          'msgtype': 'm.audio',
          'body': 'Voice message',
          'url': 'mxc://example.org/voice',
          'org.matrix.msc3245.voice': <String, dynamic>{},
          'org.matrix.msc1767.audio': {'duration': 2400},
        },
      ),
      isA<MediaTimelineItem>()
          .having((item) => item.isVoice, 'isVoice', isTrue)
          .having((item) => item.durationMs, 'durationMs', 2400),
    );
  });

  group('buildTimelineItems', () {
    test('keeps room state changes as dedicated system timeline items', () {
      final items = buildTimelineItems([
        RawRoomEvent(
          eventId: 'name-change',
          type: 'm.room.name',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 9),
          content: const {'name': 'Product'},
        ),
      ]);

      expect(items.single.kind, TimelineItemKind.system);
      expect(items.single.body, 'Product');
    });

    test('applies edits, hides replace events, and aggregates reactions', () {
      final items = buildTimelineItems([
        RawRoomEvent(
          eventId: 'msg',
          type: 'm.room.message',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 10),
          content: const {
            'msgtype': 'm.text',
            'body': 'draft',
          },
        ),
        RawRoomEvent(
          eventId: 'edit',
          type: 'm.room.message',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 10, 1),
          content: const {
            'msgtype': 'm.text',
            'body': '* final',
            'm.new_content': {
              'msgtype': 'm.text',
              'body': 'final',
            },
            'm.relates_to': {
              'rel_type': 'm.replace',
              'event_id': 'msg',
            },
          },
        ),
        RawRoomEvent(
          eventId: 'react',
          type: 'm.reaction',
          senderId: '@bob:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 10, 2),
          content: const {
            'm.relates_to': {
              'rel_type': 'm.annotation',
              'event_id': 'msg',
              'key': '👍',
            },
          },
        ),
      ]);

      expect(items, hasLength(1));
      expect(items.single.body, 'final');
      expect(items.single.edited, isTrue);
      expect(items.single.reactions, hasLength(1));
      expect(items.single.reactions.single.key, '👍');
      expect(items.single.reactions.single.count, 1);
      expect(items.single.reactions.single.reactedByMe, isFalse);
    });

    test('marks own reactions with reactedByMe', () {
      final items = buildTimelineItems(
        [
          RawRoomEvent(
            eventId: 'msg',
            type: 'm.room.message',
            senderId: '@alice:example.org',
            timestamp: DateTime.utc(2026, 8, 5, 10),
            content: const {'msgtype': 'm.text', 'body': 'hi'},
          ),
          RawRoomEvent(
            eventId: 'react',
            type: 'm.reaction',
            senderId: '@me:example.org',
            timestamp: DateTime.utc(2026, 8, 5, 10, 2),
            content: const {
              'm.relates_to': {
                'rel_type': 'm.annotation',
                'event_id': 'msg',
                'key': '❤️',
              },
            },
          ),
        ],
        ownUserId: '@me:example.org',
      );
      expect(items.single.reactions.single.reactedByMe, isTrue);
      expect(items.single.reactions.single.ownEventId, 'react');
    });

    test('keeps undecrypted events on the timeline', () {
      final items = buildTimelineItems([
        RawRoomEvent(
          eventId: 'cipher',
          type: 'm.room.encrypted',
          senderId: '@bob:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 11),
          content: const {
            'algorithm': 'm.megolm.v1.aes-sha2',
            'ciphertext': '…',
          },
        ),
      ]);

      expect(items, hasLength(1));
      expect(items.single.kind, TimelineItemKind.notice);
      expect(items.single.eventId, 'cipher');
    });

    test('keeps reply targets from m.in_reply_to', () {
      final items = buildTimelineItems([
        RawRoomEvent(
          eventId: 'reply',
          type: 'm.room.message',
          senderId: '@bob:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 11),
          content: const {
            'msgtype': 'm.text',
            'body': '> quote\n\nanswer',
            'm.relates_to': {
              'm.in_reply_to': {'event_id': 'root'},
            },
          },
        ),
      ]);

      expect(items.single.replyToEventId, 'root');
    });

    test('hides in-thread replies and keeps fallbacks on the main timeline', () {
      final items = buildTimelineItems([
        RawRoomEvent(
          eventId: 'root',
          type: 'm.room.message',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 10),
          content: const {'msgtype': 'm.text', 'body': 'root'},
        ),
        RawRoomEvent(
          eventId: 'thread-reply',
          type: 'm.room.message',
          senderId: '@bob:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 11),
          content: const {
            'msgtype': 'm.text',
            'body': 'answer from another client',
            'm.relates_to': {
              'rel_type': 'm.thread',
              'event_id': 'root',
              'm.in_reply_to': {'event_id': 'root'},
            },
          },
        ),
        RawRoomEvent(
          eventId: 'fallback',
          type: 'm.room.message',
          senderId: '@carol:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 12),
          content: const {
            'msgtype': 'm.text',
            'body': 'fallback preview',
            'm.relates_to': {
              'rel_type': 'm.thread',
              'event_id': 'root',
              'is_falling_back': true,
              'm.in_reply_to': {'event_id': 'root'},
            },
          },
        ),
      ]);

      expect(items.map((item) => item.eventId), ['root', 'fallback']);
      expect(items.first.threadReplyCount, 2);
      expect(items.last.threadRootId, 'root');
    });

    test('keeps thread replies when building a thread panel', () {
      final items = buildTimelineItems(
        [
          RawRoomEvent(
            eventId: 'root',
            type: 'm.room.message',
            senderId: '@alice:example.org',
            timestamp: DateTime.utc(2026, 8, 5, 10),
            content: const {'msgtype': 'm.text', 'body': 'root'},
          ),
          RawRoomEvent(
            eventId: 'thread-reply',
            type: 'm.room.message',
            senderId: '@bob:example.org',
            timestamp: DateTime.utc(2026, 8, 5, 11),
            content: const {
              'msgtype': 'm.text',
              'body': 'in thread',
              'm.relates_to': {
                'rel_type': 'm.thread',
                'event_id': 'root',
                'm.in_reply_to': {'event_id': 'root'},
              },
            },
          ),
        ],
        forThreadRootId: 'root',
      );
      expect(items.map((item) => item.eventId), ['root', 'thread-reply']);
    });

    test('classifies stickers and location fields', () {
      final items = buildTimelineItems([
        RawRoomEvent(
          eventId: 'sticker',
          type: 'm.sticker',
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 13),
          content: const {
            'body': 'wave',
            'url': 'mxc://example.org/sticker',
            'info': {'mimetype': 'image/png'},
          },
        ),
        RawRoomEvent(
          eventId: 'place',
          type: 'm.room.message',
          senderId: '@bob:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 14),
          content: const {
            'msgtype': 'm.location',
            'body': 'Red Square',
            'geo_uri': 'geo:55.75,37.62',
          },
        ),
        RawRoomEvent(
          eventId: 'prompt-reply',
          type: 'org.matrix.msc4139.conversation.reply',
          senderId: '@carol:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 15),
          content: const {
            'msgtype': 'm.text',
            'body': '1d6',
          },
        ),
        RawRoomEvent(
          eventId: 'decline',
          type: 'm.rtc.decline',
          senderId: '@dave:example.org',
          timestamp: DateTime.utc(2026, 8, 5, 16),
          content: const {},
        ),
      ]);

      expect(items[0].kind, TimelineItemKind.sticker);
      expect(items[0], isA<MediaTimelineItem>());
      expect(items[1].kind, TimelineItemKind.location);
      expect(items[1].latitude, 55.75);
      expect(items[1].longitude, 37.62);
      expect(items[1].geoUri, 'geo:55.75,37.62');
      expect(items[2].kind, TimelineItemKind.text);
      expect(items[2].body, '1d6');
      expect(items[3].kind, TimelineItemKind.system);
    });
  });
}
