/// MSC3381 / aiomatrix poll wire helpers (stable + unstable namespaces).
library;

const pollStartUnstable = 'org.matrix.msc3381.poll.start';
const pollStartStable = 'm.poll.start';
const pollResponseUnstable = 'org.matrix.msc3381.poll.response';
const pollResponseStable = 'm.poll.response';
const pollEndUnstable = 'org.matrix.msc3381.poll.end';
const pollEndStable = 'm.poll.end';
const pollLeanContentKey = 'dev.aiomatrix.poll';
const pollTextKey = 'org.matrix.msc1767.text';

const pollStartEventTypes = {pollStartUnstable, pollStartStable};
const pollResponseEventTypes = {pollResponseUnstable, pollResponseStable};
const pollEndEventTypes = {pollEndUnstable, pollEndStable};

class PollAnswerOption {
  const PollAnswerOption({required this.id, required this.text});

  final String id;
  final String text;
}

class PollStartData {
  const PollStartData({
    required this.question,
    required this.answers,
    this.maxSelections = 1,
    this.disclosed = true,
  });

  final String question;
  final List<PollAnswerOption> answers;
  final int maxSelections;
  final bool disclosed;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _extensibleText(Object? value) {
  final map = _asMap(value);
  if (map == null) return value is String ? value : null;
  final text = map[pollTextKey] ?? map['body'] ?? map['text'];
  return text is String ? text : null;
}

/// Extract structured start block from poll.start event content.
PollStartData? parsePollStartContent(Map<String, dynamic> content) {
  final block = _asMap(content[pollStartUnstable]) ??
      _asMap(content[pollStartStable]);
  if (block == null) return null;

  final question = _extensibleText(block['question'])?.trim() ?? '';
  if (question.isEmpty) return null;

  final rawAnswers = block['answers'];
  if (rawAnswers is! List || rawAnswers.isEmpty) return null;
  final answers = <PollAnswerOption>[];
  for (var i = 0; i < rawAnswers.length; i++) {
    final item = _asMap(rawAnswers[i]);
    if (item == null) continue;
    final id = (item['id'] as String?)?.trim();
    final text = _extensibleText(item)?.trim() ?? '';
    if (id == null || id.isEmpty || text.isEmpty) continue;
    answers.add(PollAnswerOption(id: id, text: text));
  }
  if (answers.isEmpty) return null;

  final max = block['max_selections'];
  final maxSelections = max is int
      ? max.clamp(1, answers.length)
      : (max is num ? max.toInt().clamp(1, answers.length) : 1);

  final kind = block['kind']?.toString() ?? '';
  final disclosed = !kind.contains('undisclosed');

  return PollStartData(
    question: question,
    answers: answers,
    maxSelections: maxSelections,
    disclosed: disclosed,
  );
}

bool isPollStartType(String type) => pollStartEventTypes.contains(type);
bool isPollResponseType(String type) => pollResponseEventTypes.contains(type);
bool isPollEndType(String type) => pollEndEventTypes.contains(type);

String? pollRelationEventId(Map<String, dynamic> content) {
  final relates = _asMap(content['m.relates_to']);
  if (relates == null) return null;
  if (relates['rel_type'] != 'm.reference') return null;
  return relates['event_id'] as String?;
}

List<String> parsePollResponseAnswers(Map<String, dynamic> content) {
  final unstable = _asMap(content[pollResponseUnstable]);
  if (unstable != null) {
    final answers = unstable['answers'];
    if (answers is List) {
      return answers.whereType<String>().toList();
    }
  }
  final stable = _asMap(content[pollResponseStable]);
  if (stable != null) {
    final answers = stable['answers'];
    if (answers is List) {
      return answers.whereType<String>().toList();
    }
  }
  final selections = content['m.selections'];
  if (selections is List) {
    return selections.whereType<String>().toList();
  }
  return const [];
}

/// Build aiomatrix-compatible poll.start content (unstable type preferred).
Map<String, dynamic> buildPollStartContent({
  required String question,
  required List<String> answers,
  int maxSelections = 1,
  bool leanBody = true,
}) {
  final q = question.trim();
  if (q.isEmpty) {
    throw ArgumentError('poll question must be non-empty');
  }
  final cleaned = answers.map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
  if (cleaned.isEmpty) {
    throw ArgumentError('poll requires at least one answer');
  }
  final structured = cleaned.asMap().entries.map((e) {
    return {
      'id': 'answer${e.key}',
      pollTextKey: e.value,
    };
  }).toList();
  final start = {
    'question': {pollTextKey: q},
    'kind': 'org.matrix.msc3381.poll.disclosed',
    'max_selections': maxSelections.clamp(1, cleaned.length),
    'answers': structured,
  };
  final body = leanBody
      ? q
      : '$q\n${cleaned.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}';
  return {
    pollStartUnstable: start,
    pollStartStable: start,
    'body': body,
    'msgtype': 'm.text',
    if (leanBody)
      pollLeanContentKey: {
        'version': 1,
        'lean': true,
        'question': q,
      },
  };
}

Map<String, dynamic> buildPollResponseContent({
  required String pollEventId,
  required List<String> answerIds,
}) {
  final response = {'answers': answerIds};
  return {
    'm.relates_to': {
      'rel_type': 'm.reference',
      'event_id': pollEventId,
    },
    pollResponseUnstable: response,
    pollResponseStable: response,
  };
}

Map<String, dynamic> buildPollEndContent(String pollEventId) {
  const end = <String, dynamic>{};
  return {
    'm.relates_to': {
      'rel_type': 'm.reference',
      'event_id': pollEventId,
    },
    pollEndUnstable: end,
    pollEndStable: end,
    'body': 'Poll ended',
    'msgtype': 'm.text',
  };
}

class PollVoteTally {
  const PollVoteTally({
    required this.counts,
    required this.mySelections,
    required this.totalVoters,
  });

  final Map<String, int> counts;
  final Set<String> mySelections;
  final int totalVoters;
}

/// Latest response per sender wins; empty answers spoil the vote.
PollVoteTally tallyPollVotes({
  required Iterable<({String senderId, DateTime timestamp, List<String> answers})>
      responses,
  required Set<String> validAnswerIds,
  required int maxSelections,
  String? ownUserId,
}) {
  final bySender = <String, ({DateTime timestamp, List<String> answers})>{};
  for (final response in responses) {
    final previous = bySender[response.senderId];
    if (previous != null && !response.timestamp.isAfter(previous.timestamp)) {
      continue;
    }
    bySender[response.senderId] = (
      timestamp: response.timestamp,
      answers: response.answers,
    );
  }

  final counts = {for (final id in validAnswerIds) id: 0};
  var voters = 0;
  var my = <String>{};

  for (final entry in bySender.entries) {
    final truncated = entry.value.answers
        .where(validAnswerIds.contains)
        .take(maxSelections)
        .toSet()
        .toList();
    if (truncated.isEmpty) continue;
    // Spoiled if any unknown id was present before filter and nothing valid left —
    // already filtered. If original had unknown ids, MSC says spoil entirely:
    final original = entry.value.answers;
    if (original.any((id) => !validAnswerIds.contains(id))) continue;
    voters += 1;
    for (final id in truncated) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (ownUserId != null && entry.key == ownUserId) {
      my = truncated.toSet();
    }
  }

  return PollVoteTally(
    counts: counts,
    mySelections: my,
    totalVoters: voters,
  );
}
