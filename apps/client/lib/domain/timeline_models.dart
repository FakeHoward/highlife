import '../aiomatrix/polls.dart';
import '../aiomatrix/protocol.dart';
import 'spec_features.dart';

enum TimelineItemKind {
  text,
  notice,
  emote,
  image,
  video,
  audio,
  file,
  location,
  sticker,
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
    this.threadRootId,
    this.threadReplyCount,
    this.geoUri,
    this.latitude,
    this.longitude,
    this.rawContent,
  });

  final String eventId;
  final String senderId;
  final DateTime timestamp;
  final String body;
  final TimelineItemKind kind;
  final String? replyToEventId;
  final bool edited;
  final List<ReactionSummary> reactions;
  final String? threadRootId;
  final int? threadReplyCount;
  final String? geoUri;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic>? rawContent;

  factory TimelineItem.fromContent({
    required String eventId,
    required String senderId,
    required DateTime timestamp,
    required Map<String, dynamic> content,
    bool edited = false,
    List<ReactionSummary> reactions = const [],
    String? eventType,
    String? threadRootId,
    int? threadReplyCount,
  }) {
    final msgtype = content['msgtype'] as String? ?? 'm.text';
    var kind = switch (msgtype) {
      'm.notice' => TimelineItemKind.notice,
      'm.emote' => TimelineItemKind.emote,
      'm.image' => TimelineItemKind.image,
      'm.video' => TimelineItemKind.video,
      'm.audio' => TimelineItemKind.audio,
      'm.file' => TimelineItemKind.file,
      'm.location' => TimelineItemKind.location,
      'm.sticker' => TimelineItemKind.sticker,
      _ => TimelineItemKind.text,
    };
    if (eventType == stickerEventType) kind = TimelineItemKind.sticker;
    final relatesTo = content['m.relates_to'];
    final relation = relatesTo is Map
        ? Map<String, dynamic>.from(relatesTo)
        : const <String, dynamic>{};
    final reply = relation['m.in_reply_to'];
    final replyMap =
        reply is Map ? Map<String, dynamic>.from(reply) : const <String, dynamic>{};
    final location = parseLocationContent(content);
    final item = TimelineItem(
      eventId: eventId,
      senderId: senderId,
      timestamp: timestamp,
      body: resolveDisplayBody(content),
      kind: kind,
      replyToEventId: replyMap['event_id'] as String? ??
          (relation['rel_type'] == 'm.thread'
              ? relation['event_id'] as String?
              : null),
      edited: edited,
      reactions: reactions,
      threadRootId: threadRootId,
      threadReplyCount: threadReplyCount,
      geoUri: location?.geoUri,
      latitude: location?.lat,
      longitude: location?.lon,
      rawContent: content,
    );
    if (kind == TimelineItemKind.text ||
        kind == TimelineItemKind.notice ||
        kind == TimelineItemKind.emote ||
        kind == TimelineItemKind.location) {
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
    super.threadRootId,
    super.threadReplyCount,
    super.geoUri,
    super.latitude,
    super.longitude,
    super.rawContent,
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
      threadRootId: item.threadRootId,
      threadReplyCount: item.threadReplyCount,
      geoUri: item.geoUri,
      latitude: item.latitude,
      longitude: item.longitude,
      rawContent: item.rawContent,
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
    super.threadRootId,
    super.threadReplyCount,
    super.rawContent,
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
///
/// Pass [forThreadRootId] to build a thread panel (root + in-thread replies).
/// The main timeline hides in-thread replies unless `is_falling_back`.
List<TimelineItem> buildTimelineItems(
  Iterable<RawRoomEvent> events, {
  String? ownUserId,
  String? forThreadRootId,
}) {
  final edits = <String, Map<String, dynamic>>{};
  final reactions = <String, Map<String, _ReactionBucket>>{};
  final threadCounts = <String, int>{};

  for (final event in events) {
    if (event.redacted) continue;
    final relation = _asMap(event.content['m.relates_to']);
    final relatedId = relation['event_id'] as String?;
    final relType = relation['rel_type'] as String?;
    final root = threadRootId(event.content);
    if (root != null) {
      threadCounts[root] = (threadCounts[root] ?? 0) + 1;
    }

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

  bool includeEvent(RawRoomEvent event) {
    if (forThreadRootId != null) {
      final root = threadRootId(event.content);
      return event.eventId == forThreadRootId || root == forThreadRootId;
    }
    return belongsOnMainTimeline(event.content);
  }

  List<ReactionSummary> reactionListFor(String eventId) {
    final reactionMap = reactions[eventId] ?? const {};
    return reactionMap.entries
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
  }

  String? rootIdFor(RawRoomEvent event) {
    return threadRootId(event.content) ??
        (threadCounts.containsKey(event.eventId) ? event.eventId : null);
  }

  final items = <TimelineItem>[];
  for (final event in events) {
    if (event.redacted) continue;

    if (const {
      'm.room.name',
      'm.room.topic',
      'm.room.canonical_alias',
      'm.room.avatar',
      msc4310Decline,
      msc4310DeclineUnstable,
    }.contains(event.type)) {
      if (forThreadRootId != null) continue;
      final body = switch (event.type) {
        'm.room.name' => event.content['name'] as String? ?? '',
        'm.room.topic' => event.content['topic'] as String? ?? '',
        'm.room.canonical_alias' =>
          event.content['alias'] as String? ?? '',
        msc4310Decline || msc4310DeclineUnstable => 'decline',
        _ => '',
      };
      items.add(
        TimelineItem(
          eventId: event.eventId,
          senderId: event.senderId,
          timestamp: event.timestamp,
          body: body,
          kind: TimelineItemKind.system,
          rawContent: event.content,
        ),
      );
      continue;
    }

    if (isPollStartType(event.type)) {
      if (!includeEvent(event)) continue;
      final start = parsePollStartContent(event.content);
      if (start == null) continue;
      final validIds = start.answers.map((a) => a.id).toSet();
      final tally = tallyPollVotes(
        responses: pollResponses[event.eventId] ?? const [],
        validAnswerIds: validIds,
        maxSelections: start.maxSelections,
        ownUserId: ownUserId,
      );
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
          reactions: reactionListFor(event.eventId),
          threadRootId: rootIdFor(event),
          threadReplyCount: threadCounts[event.eventId],
          rawContent: event.content,
        ),
      );
      continue;
    }

    if (isPollResponseType(event.type) || isPollEndType(event.type)) {
      continue;
    }

    if (event.type == 'm.room.encrypted') {
      if (!includeEvent(event)) continue;
      items.add(
        TimelineItem(
          eventId: event.eventId,
          senderId: event.senderId,
          timestamp: event.timestamp,
          body: '',
          kind: TimelineItemKind.notice,
          reactions: reactionListFor(event.eventId),
          threadRootId: rootIdFor(event),
          threadReplyCount: threadCounts[event.eventId],
          rawContent: event.content,
        ),
      );
      continue;
    }

    final isMessage = event.type == 'm.room.message' ||
        event.type == stickerEventType ||
        event.type == msc4139ReplyType;
    if (!isMessage) continue;
    final relation = _asMap(event.content['m.relates_to']);
    if (relation['rel_type'] == 'm.replace') continue;
    if (!includeEvent(event)) continue;

    final editedContent = edits[event.eventId];
    final content = editedContent == null
        ? event.content
        : <String, dynamic>{...event.content, ...editedContent};

    items.add(
      TimelineItem.fromContent(
        eventId: event.eventId,
        senderId: event.senderId,
        timestamp: event.timestamp,
        content: content,
        edited: editedContent != null,
        reactions: reactionListFor(event.eventId),
        eventType: event.type,
        threadRootId: rootIdFor(event),
        threadReplyCount: threadCounts[event.eventId],
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
