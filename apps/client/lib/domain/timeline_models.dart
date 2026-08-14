import '../aiomatrix/polls.dart';
import '../aiomatrix/protocol.dart';

enum TimelineItemKind {
  text,
  notice,
  emote,
  image,
  video,
  audio,
  file,
  location,
  poll,
  system,
}

/// Lightweight event shape so timeline logic can be tested without a live Matrix client.
class RawRoomEvent {
  const RawRoomEvent({
    required this.eventId,
    required this.type,
    required this.senderId,
    required this.timestamp,
    required this.content,
    this.redacted = false,
  });

  final String eventId;
  final String type;
  final String senderId;
  final DateTime timestamp;
  final Map<String, dynamic> content;
  final bool redacted;
}

class ReactionSummary {
  const ReactionSummary({
    required this.key,
    required this.count,
    this.reactedByMe = false,
    this.ownEventId,
  });

  final String key;
  final int count;
  final bool reactedByMe;
  final String? ownEventId;
}

class TimelineItem {
  const TimelineItem({
    required this.eventId,
    required this.senderId,
    required this.timestamp,
    required this.body,
    this.kind = TimelineItemKind.text,
    this.replyToEventId,
    this.edited = false,
    this.reactions = const [],
  });

  final String eventId;
  final String senderId;
  final DateTime timestamp;
  final String body;
  final TimelineItemKind kind;
  final String? replyToEventId;
  final bool edited;
  final List<ReactionSummary> reactions;

  factory TimelineItem.fromContent({
    required String eventId,
    required String senderId,
    required DateTime timestamp,
    required Map<String, dynamic> content,
    bool edited = false,
    List<ReactionSummary> reactions = const [],
  }) {
    final msgtype = content['msgtype'] as String? ?? 'm.text';
    final kind = switch (msgtype) {
      'm.notice' => TimelineItemKind.notice,
      'm.emote' => TimelineItemKind.emote,
      'm.image' => TimelineItemKind.image,
      'm.video' => TimelineItemKind.video,
      'm.audio' => TimelineItemKind.audio,
      'm.file' => TimelineItemKind.file,
      'm.location' => TimelineItemKind.location,
      _ => TimelineItemKind.text,
    };
    final relatesTo = content['m.relates_to'];
    final relation = relatesTo is Map
        ? Map<String, dynamic>.from(relatesTo)
        : const <String, dynamic>{};
    final reply = relation['m.in_reply_to'];
    final replyMap =
        reply is Map ? Map<String, dynamic>.from(reply) : const <String, dynamic>{};
    final item = TimelineItem(
      eventId: eventId,
      senderId: senderId,
      timestamp: timestamp,
      body: resolveDisplayBody(content),
      kind: kind,
      replyToEventId: replyMap['event_id'] as String?,
      edited: edited,
      reactions: reactions,
    );
    if (kind == TimelineItemKind.text ||
        kind == TimelineItemKind.notice ||
        kind == TimelineItemKind.emote) {
      return item;
    }
    // Matrix media URLs are mxc:// — ignore https MiniApp / link fallbacks.
    final url = content['url'] as String?;
    final mxc = url != null && url.startsWith('mxc://') ? url : null;
    final info = _asMap(content['info']);
    final audioMeta = _asMap(content['org.matrix.msc1767.audio']);
    int? durationMs;
    final infoDuration = info['duration'];
    if (infoDuration is num) {
      durationMs = infoDuration >= 1000
          ? infoDuration.round()
          : (infoDuration * 1000).round();
    }
    final metaDuration = audioMeta['duration'];
    if (metaDuration is num) durationMs = metaDuration.round();
    return MediaTimelineItem.from(
      item,
      mxc,
      isVoice: content['org.matrix.msc3245.voice'] != null,
      durationMs: durationMs,
    );
  }
}

class MediaTimelineItem extends TimelineItem {
  const MediaTimelineItem({
    required super.eventId,
    required super.senderId,
    required super.timestamp,
    required super.body,
    required super.kind,
    this.mxcUrl,
    this.isVoice = false,
    this.durationMs,
    super.replyToEventId,
    super.edited,
    super.reactions,
  });

  final String? mxcUrl;
  final bool isVoice;
  final int? durationMs;

  factory MediaTimelineItem.from(
    TimelineItem item,
    String? mxcUrl, {
    bool isVoice = false,
    int? durationMs,
  }) {
    return MediaTimelineItem(
      eventId: item.eventId,
      senderId: item.senderId,
      timestamp: item.timestamp,
      body: item.body,
      kind: item.kind,
      mxcUrl: mxcUrl,
      isVoice: isVoice,
      durationMs: durationMs,
      replyToEventId: item.replyToEventId,
      edited: item.edited,
      reactions: item.reactions,
    );
  }
}

class PollTimelineItem extends TimelineItem {
  const PollTimelineItem({
    required super.eventId,
    required super.senderId,
    required super.timestamp,
    required this.question,
    required this.answers,
    required this.maxSelections,
    required this.ended,
    required this.counts,
    required this.mySelections,
    required this.totalVoters,
    this.disclosed = true,
    super.reactions,
  }) : super(body: question, kind: TimelineItemKind.poll);

  final String question;
  final List<PollAnswerOption> answers;
  final int maxSelections;
  final bool ended;
  final bool disclosed;
  final Map<String, int> counts;
  final Set<String> mySelections;
  final int totalVoters;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

class _ReactionBucket {
  _ReactionBucket();
  final Set<String> senders = <String>{};
  bool reactedByMe = false;
  String? ownEventId;

  int get count => senders.length;
}

/// Normalize message / reaction / edit events into display items (oldest → newest).
List<TimelineItem> buildTimelineItems(
  Iterable<RawRoomEvent> events, {
  String? ownUserId,
}) {
  final edits = <String, Map<String, dynamic>>{};
  final reactions = <String, Map<String, _ReactionBucket>>{};

  for (final event in events) {
    if (event.redacted) continue;
    final relation = _asMap(event.content['m.relates_to']);
    final relatedId = relation['event_id'] as String?;
    final relType = relation['rel_type'] as String?;

    if (event.type == 'm.reaction' &&
        relType == 'm.annotation' &&
        relatedId != null) {
      final key = relation['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final bucket = reactions
          .putIfAbsent(relatedId, () => <String, _ReactionBucket>{})
          .putIfAbsent(key, _ReactionBucket.new);
      bucket.senders.add(event.senderId);
      if (ownUserId != null && event.senderId == ownUserId) {
        bucket.reactedByMe = true;
        bucket.ownEventId = event.eventId;
      }
      continue;
    }

    if (event.type == 'm.room.message' &&
        relType == 'm.replace' &&
        relatedId != null) {
      final newContent = _asMap(event.content['m.new_content']);
      if (newContent.isNotEmpty) {
        edits[relatedId] = newContent;
      }
    }
  }

  final pollResponses =
      <String, List<({String senderId, DateTime timestamp, List<String> answers})>>{};
  final endedPolls = <String>{};

  for (final event in events) {
    if (event.redacted) continue;
    if (isPollResponseType(event.type)) {
      final pollId = pollRelationEventId(event.content);
      if (pollId == null) continue;
      pollResponses.putIfAbsent(pollId, () => []).add((
        senderId: event.senderId,
        timestamp: event.timestamp,
        answers: parsePollResponseAnswers(event.content),
      ));
      continue;
    }
    if (isPollEndType(event.type)) {
      final pollId = pollRelationEventId(event.content);
      if (pollId != null) endedPolls.add(pollId);
    }
  }

  final items = <TimelineItem>[];
  for (final event in events) {
    if (event.redacted) continue;

    if (const {
      'm.room.name',
      'm.room.topic',
      'm.room.canonical_alias',
      'm.room.avatar',
    }.contains(event.type)) {
      final body = switch (event.type) {
        'm.room.name' => event.content['name'] as String? ?? '',
        'm.room.topic' => event.content['topic'] as String? ?? '',
        'm.room.canonical_alias' =>
          event.content['alias'] as String? ?? '',
        _ => '',
      };
      items.add(
        TimelineItem(
          eventId: event.eventId,
          senderId: event.senderId,
          timestamp: event.timestamp,
          body: body,
          kind: TimelineItemKind.system,
        ),
      );
      continue;
    }

    if (isPollStartType(event.type)) {
      final start = parsePollStartContent(event.content);
      if (start == null) continue;
      final validIds = start.answers.map((a) => a.id).toSet();
      final tally = tallyPollVotes(
        responses: pollResponses[event.eventId] ?? const [],
        validAnswerIds: validIds,
        maxSelections: start.maxSelections,
        ownUserId: ownUserId,
      );
      final reactionMap = reactions[event.eventId] ?? const {};
      final reactionList = reactionMap.entries
          .map(
            (entry) => ReactionSummary(
              key: entry.key,
              count: entry.value.count,
              reactedByMe: entry.value.reactedByMe,
              ownEventId: entry.value.ownEventId,
            ),
          )
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      items.add(
        PollTimelineItem(
          eventId: event.eventId,
          senderId: event.senderId,
          timestamp: event.timestamp,
          question: start.question,
          answers: start.answers,
          maxSelections: start.maxSelections,
          ended: endedPolls.contains(event.eventId),
          disclosed: start.disclosed,
          counts: tally.counts,
          mySelections: tally.mySelections,
          totalVoters: tally.totalVoters,
          reactions: reactionList,
        ),
      );
      continue;
    }

    if (isPollResponseType(event.type) || isPollEndType(event.type)) {
      continue;
    }

    if (event.type == 'm.room.encrypted') {
      final reactionMap = reactions[event.eventId] ?? const {};
      final reactionList = reactionMap.entries
          .map(
            (entry) => ReactionSummary(
              key: entry.key,
              count: entry.value.count,
              reactedByMe: entry.value.reactedByMe,
              ownEventId: entry.value.ownEventId,
            ),
          )
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      items.add(
        TimelineItem(
          eventId: event.eventId,
          senderId: event.senderId,
          timestamp: event.timestamp,
          body: '',
          kind: TimelineItemKind.notice,
          reactions: reactionList,
        ),
      );
      continue;
    }

    if (event.type != 'm.room.message') continue;
    final relation = _asMap(event.content['m.relates_to']);
    if (relation['rel_type'] == 'm.replace') continue;

    final editedContent = edits[event.eventId];
    final content = editedContent == null
        ? event.content
        : <String, dynamic>{...event.content, ...editedContent};
    final reactionMap = reactions[event.eventId] ?? const {};
    final reactionList = reactionMap.entries
        .map(
          (entry) => ReactionSummary(
            key: entry.key,
            count: entry.value.count,
            reactedByMe: entry.value.reactedByMe,
            ownEventId: entry.value.ownEventId,
          ),
        )
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    items.add(
      TimelineItem.fromContent(
        eventId: event.eventId,
        senderId: event.senderId,
        timestamp: event.timestamp,
        content: content,
        edited: editedContent != null,
        reactions: reactionList,
      ),
    );
  }

  items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return items;
}

class TimelineGroup {
  const TimelineGroup({required this.senderId, required this.items});

  final String senderId;
  final List<TimelineItem> items;
  DateTime get day => DateTime(
        items.first.timestamp.year,
        items.first.timestamp.month,
        items.first.timestamp.day,
      );
}

List<TimelineGroup> groupTimelineItems(
  Iterable<TimelineItem> items, {
  Duration maximumGap = const Duration(minutes: 5),
}) {
  final sorted = items.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final groups = <TimelineGroup>[];
  for (final item in sorted) {
    if (groups.isEmpty) {
      groups.add(TimelineGroup(senderId: item.senderId, items: [item]));
      continue;
    }
    final previousGroup = groups.last;
    final previous = previousGroup.items.last;
    final sameDay = previous.timestamp.year == item.timestamp.year &&
        previous.timestamp.month == item.timestamp.month &&
        previous.timestamp.day == item.timestamp.day;
    final close = item.timestamp.difference(previous.timestamp) <= maximumGap;
    if (previous.senderId == item.senderId && sameDay && close) {
      previousGroup.items.add(item);
    } else {
      groups.add(TimelineGroup(senderId: item.senderId, items: [item]));
    }
  }
  return groups;
}
