import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/aiomatrix/polls.dart';
import 'package:highlife_client/domain/timeline_models.dart';
import 'package:highlife_client/services/call_uri.dart';

void main() {
  test('buildPollStartContent matches aiomatrix lean shape', () {
    final content = buildPollStartContent(
      question: 'Lunch?',
      answers: const ['Pizza', 'Sushi'],
    );
    expect(content['msgtype'], 'm.text');
    expect(content['body'], 'Lunch?');
    expect(content[pollLeanContentKey], isA<Map>());
    final start = content[pollStartUnstable] as Map;
    expect(start['max_selections'], 1);
    expect((start['answers'] as List), hasLength(2));
  });

  test('buildTimelineItems aggregates poll votes and ends', () {
    final items = buildTimelineItems(
      [
        RawRoomEvent(
          eventId: '\$poll',
          type: pollStartUnstable,
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 6, 12),
          content: buildPollStartContent(
            question: 'Lunch?',
            answers: const ['Pizza', 'Sushi'],
          ),
        ),
        RawRoomEvent(
          eventId: '\$vote1',
          type: pollResponseUnstable,
          senderId: '@bob:example.org',
          timestamp: DateTime.utc(2026, 8, 6, 12, 1),
          content: buildPollResponseContent(
            pollEventId: '\$poll',
            answerIds: const ['answer0'],
          ),
        ),
        RawRoomEvent(
          eventId: '\$vote2',
          type: pollResponseUnstable,
          senderId: '@carol:example.org',
          timestamp: DateTime.utc(2026, 8, 6, 12, 2),
          content: buildPollResponseContent(
            pollEventId: '\$poll',
            answerIds: const ['answer1'],
          ),
        ),
        RawRoomEvent(
          eventId: '\$end',
          type: pollEndUnstable,
          senderId: '@alice:example.org',
          timestamp: DateTime.utc(2026, 8, 6, 12, 3),
          content: buildPollEndContent('\$poll'),
        ),
      ],
      ownUserId: '@bob:example.org',
    );

    expect(items, hasLength(1));
    final poll = items.single as PollTimelineItem;
    expect(poll.question, 'Lunch?');
    expect(poll.ended, isTrue);
    expect(poll.totalVoters, 2);
    expect(poll.counts['answer0'], 1);
    expect(poll.counts['answer1'], 1);
    expect(poll.mySelections, {'answer0'});
  });

  test('hasActiveCallMemberStates detects memberships', () {
    expect(hasActiveCallMemberStates(const []), isFalse);
    expect(
      hasActiveCallMemberStates([
        {
          'memberships': [
            {'device_id': 'DEV', 'membership': 'join'},
          ],
        },
      ]),
      isTrue,
    );
  });
}
