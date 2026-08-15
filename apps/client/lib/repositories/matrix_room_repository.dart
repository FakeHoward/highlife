import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import '../domain/matrix_identity.dart';
import '../domain/spec_features.dart';

class MatrixRoomRepository {
  MatrixRoomRepository(this.client);

  final Client client;
  List<String> slidingRoomOrder = const [];

  /// All joined/invited rooms from the client, including spaces.
  List<Room> get rooms {
    final result = client.rooms.toList();
    final order = slidingRoomOrder;
    result.sort((a, b) {
      if (order.isNotEmpty) {
        final ia = order.indexOf(a.id);
        final ib = order.indexOf(b.id);
        if (ia >= 0 && ib >= 0 && ia != ib) return ia.compareTo(ib);
        if (ia >= 0 && ib < 0) return -1;
        if (ib >= 0 && ia < 0) return 1;
      }
      return b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime);
    });
    return result;
  }

  /// Matrix spaces only.
  List<Room> get spaces {
    final result = client.rooms.where((room) => room.isSpace).toList()
      ..sort(
        (a, b) =>
            b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
      );
    return result;
  }

  /// Child rooms known locally for [space] via `m.space.child` / [Room.spaceChildren].
  List<Room> roomsInSpace(Room space) {
    if (!space.isSpace) return const [];
    final out = <Room>[];
    for (final child in space.spaceChildren) {
      final roomId = child.roomId;
      if (roomId == null || roomId.isEmpty) continue;
      final room = client.getRoomById(roomId);
      if (room != null) out.add(room);
    }
    return out;
  }

  Future<String> createRoom(
    String name, {
    bool? enableEncryption,
    String? alias,
  }) async {
    final roomId = await client.createGroupChat(
      groupName: name.trim(),
      enableEncryption: enableEncryption,
    );
    final normalizedAlias = normalizeRoomReference(
      alias ?? '',
      homeserver: client.homeserver?.host,
    );
    if (normalizedAlias.isNotEmpty) {
      final room = client.getRoomById(roomId);
      if (room != null) await room.setCanonicalAlias(normalizedAlias);
    }
    return roomId;
  }

  /// Private Matrix space (sidebar folder).
  Future<String> createSpace(String name, {String? topic}) {
    final trimmedTopic = topic?.trim();
    return client.createSpace(
      name: name.trim(),
      topic: trimmedTopic == null || trimmedTopic.isEmpty ? null : trimmedTopic,
      visibility: Visibility.private,
    );
  }

  Future<void> addRoomToSpace(Room space, Room room) {
    return space.setSpaceChild(room.id);
  }

  Future<String> startDirectChat(
    String userId, {
    bool enableEncryption = true,
  }) {
    return client.startDirectChat(
      userId.trim(),
      enableEncryption: enableEncryption,
    );
  }

  Future<String> joinRoom(String roomIdOrAlias) {
    final id = normalizeRoomReference(
      roomIdOrAlias,
      homeserver: client.homeserver?.host,
    );
    final colon = id.lastIndexOf(':');
    final via =
        colon > 0 && colon < id.length - 1 ? <String>[id.substring(colon + 1)] : null;
    return client.joinRoom(id, via: via);
  }

  Future<String> knockRoom(String roomIdOrAlias, {String? reason}) {
    final id = normalizeRoomReference(
      roomIdOrAlias,
      homeserver: client.homeserver?.host,
    );
    final colon = id.lastIndexOf(':');
    final via =
        colon > 0 && colon < id.length - 1 ? <String>[id.substring(colon + 1)] : null;
    return client.knockRoom(id, via: via, reason: reason);
  }

  Future<void> invite(Room room, String userId) {
    return room.invite(userId.trim());
  }

  Future<void> leave(Room room) => room.leave();

  List<User> listKnocks(Room room) =>
      room.getParticipants([Membership.knock]);

  Future<void> approveKnock(Room room, String userId) =>
      room.invite(userId.trim());

  Future<void> denyKnock(Room room, String userId) =>
      room.kick(userId.trim());

  Future<SearchResults> searchMessages(String term, {String? roomId}) {
    return client.search(
      Categories(
        roomEvents: RoomEventsCriteria(
          searchTerm: term.trim(),
          filter: roomId == null ? null : SearchFilter(rooms: [roomId]),
        ),
      ),
    );
  }

  Future<Timeline> timeline(
    Room room, {
    required void Function() onUpdate,
  }) {
    return room.getTimeline(onUpdate: onUpdate);
  }

  Future<void> paginate(Timeline timeline, {int count = 30}) {
    return timeline.requestHistory(historyCount: count);
  }

  Future<void> markRead(Timeline timeline, {String? eventId}) {
    return timeline.setReadMarker(eventId: eventId, public: false);
  }

  Future<void> setTyping(Room room, bool typing) {
    return room.setTyping(typing, timeout: typing ? 8000 : null);
  }

  List<String> _memberIds(Room room) {
    return room
        .getParticipants([Membership.join])
        .map((user) => user.id)
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<void> subscribeToThread(Room room, String rootId) async {
    try {
      await client.request(
        RequestType.PUT,
        matrixApiAction(threadSubscriptionPath(room.id, rootId)),
        data: const {'automatic': false},
      );
    } catch (_) {}
  }

  Future<String?> sendText(
    Room room,
    String text, {
    Event? replyTo,
    Event? edit,
    String? threadRootId,
  }) async {
    final content = Map<String, dynamic>.from(
      attachMentions(
        {'msgtype': 'm.text', 'body': text},
        text,
        _memberIds(room),
      ),
    );
    if (threadRootId != null) {
      content['m.relates_to'] = Map<String, dynamic>.from(
        threadRelation(
          threadRootId,
          replyToId: replyTo?.eventId,
          fallback: false,
        ),
      );
    }
    final eventId = await room.sendEvent(
      content,
      inReplyTo: threadRootId == null ? replyTo : null,
      editEventId: edit?.eventId,
    );
    if (threadRootId != null) {
      await subscribeToThread(room, threadRootId);
    }
    return eventId;
  }

  Future<String?> sendEvent(
    Room room,
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    Event? replyTo,
    String? threadRootId,
    String? bodyForMentions,
  }) async {
    var payload = Map<String, dynamic>.from(content);
    final body = bodyForMentions ?? payload['body'] as String? ?? '';
    payload = Map<String, dynamic>.from(
      attachMentions(payload, body, _memberIds(room)),
    );
    if (threadRootId != null) {
      payload['m.relates_to'] = Map<String, dynamic>.from(
        threadRelation(
          threadRootId,
          replyToId: replyTo?.eventId,
          fallback: false,
        ),
      );
    }
    final eventId = await room.sendEvent(
      payload,
      type: type,
      inReplyTo: threadRootId == null ? replyTo : null,
    );
    if (threadRootId != null) {
      await subscribeToThread(room, threadRootId);
    }
    return eventId;
  }

  Future<String?> sendLocation(
    Room room,
    double lat,
    double lon, {
    String? description,
    String? threadRootId,
  }) {
    final content = locationContent(lat, lon, description: description);
    return sendEvent(
      room,
      Map<String, dynamic>.from(content),
      threadRootId: threadRootId,
      bodyForMentions: description ?? '',
    );
  }

  Future<String?> sendSticker(
    Room room,
    ImagePackItem item, {
    String? threadRootId,
  }) {
    return sendEvent(
      room,
      Map<String, dynamic>.from(stickerContent(item)),
      type: stickerEventType,
      threadRootId: threadRootId,
      bodyForMentions: item.body,
    );
  }

  Future<String?> sendConversationReply(
    Room room, {
    required String rootEventId,
    required String promptId,
    required String label,
  }) async {
    final eventId = await room.sendEvent(
      Map<String, dynamic>.from(
        conversationReplyContent(
          promptId: promptId,
          label: label,
          rootEventId: rootEventId,
        ),
      ),
      type: msc4139ReplyType,
    );
    await subscribeToThread(room, rootEventId);
    return eventId;
  }

  List<ImagePackItem> listImagePacks({Room? room}) {
    final out = <ImagePackItem>[];
    final seen = <String>{};
    void addFrom(Map<String, dynamic>? content) {
      if (content == null) return;
      for (final item in parseImagePack(content)) {
        if (!item.usage.contains('sticker')) continue;
        if (seen.add(item.url)) out.add(item);
      }
    }

    final account = client.accountData[msc2545UserEmotes];
    if (account != null) {
      addFrom(Map<String, dynamic>.from(account.content));
    }
    final rooms = room == null ? client.rooms : <Room>[room];
    for (final candidate in rooms) {
      final states = candidate.states[msc2545PackState];
      if (states == null) continue;
      for (final event in states.values) {
        addFrom(Map<String, dynamic>.from(event.content));
      }
    }
    return out;
  }

  Future<RoomSummary> fetchRoomSummary(String roomIdOrAlias) async {
    final id = normalizeRoomReference(
      roomIdOrAlias,
      homeserver: client.homeserver?.host,
    );
    final encoded = Uri.encodeComponent(id);
    try {
      final payload = await client.request(
        RequestType.GET,
        matrixApiAction('$msc3266SummaryPath/$encoded'),
      );
      return parseRoomSummary(Map<String, dynamic>.from(payload), id);
    } catch (_) {
      final payload = await client.request(
        RequestType.GET,
        matrixApiAction('$msc3266SummaryUnstablePath/$encoded'),
      );
      return parseRoomSummary(Map<String, dynamic>.from(payload), id);
    }
  }

  Future<void> sendRtcDecline(Room room, {String? notificationEventId}) async {
    final content = Map<String, dynamic>.from(
      rtcDeclineContent(notificationEventId: notificationEventId),
    );
    try {
      await room.sendEvent(content, type: msc4310Decline);
    } catch (_) {
      await room.sendEvent(content, type: msc4310DeclineUnstable);
    }
  }

  /// One-shot simplified sliding sync for room order. Classic `/sync` stays the
  /// live loop — do not start a second long-poll client.
  Future<void> probeSlidingSync() async {
    try {
      final versions = await client.getVersions();
      final unstable = versions.unstableFeatures;
      if (!slidingSyncSupported(
        unstable == null ? null : Map<String, dynamic>.from(unstable),
      )) {
        return;
      }
      try {
        final payload = await client.request(
          RequestType.POST,
          matrixApiAction(simplifiedSlidingSyncPath),
          data: defaultSlidingSyncRequest(),
        );
        slidingRoomOrder =
            parseSlidingSyncRoomOrder(Map<String, dynamic>.from(payload));
        return;
      } catch (_) {
        final payload = await client.request(
          RequestType.POST,
          matrixApiAction(msc3575SlidingSyncPath),
          data: defaultSlidingSyncRequest(),
        );
        slidingRoomOrder =
            parseSlidingSyncRoomOrder(Map<String, dynamic>.from(payload));
      }
    } catch (_) {
      // Homeserver or SDK without SSS — keep classic recency order.
    }
  }

  Future<String?> sendReaction(Room room, Event event, String key) {
    return room.sendReaction(event.eventId, key);
  }

  Future<String?> redact(Event event, {String? reason}) {
    return event.redactEvent(reason: reason);
  }

  Future<String?> upload(
    Room room, {
    required Uint8List bytes,
    required String fileName,
    Event? replyTo,
    Map<String, dynamic>? extraContent,
    String? threadRootId,
  }) {
    return room.sendFileEvent(
      MatrixFile(bytes: bytes, name: fileName),
      inReplyTo: threadRootId == null ? replyTo : null,
      extraContent: threadRootId == null
          ? extraContent
          : <String, dynamic>{
              ...?extraContent,
              'm.relates_to': Map<String, dynamic>.from(
                threadRelation(
                  threadRootId,
                  replyToId: replyTo?.eventId,
                  fallback: false,
                ),
              ),
            },
    );
  }

  Future<String?> forwardEvent(Room target, Event event) {
    return target.sendEvent(
      Map<String, dynamic>.from(event.content),
      type: event.type,
    );
  }
}
