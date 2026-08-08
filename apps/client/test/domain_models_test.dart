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
  });

  group('buildTimelineItems', () {
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
  });
}
