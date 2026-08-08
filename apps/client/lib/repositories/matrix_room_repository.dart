import 'dart:typed_data';

import 'package:matrix/matrix.dart';

class MatrixRoomRepository {
  const MatrixRoomRepository(this.client);

  final Client client;

  /// All joined/invited rooms from the client, including spaces.
  List<Room> get rooms {
    final result = client.rooms.toList()
      ..sort(
        (a, b) =>
            b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
      );
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

  Future<String> createRoom(String name, {bool? enableEncryption}) {
    return client.createGroupChat(
      groupName: name.trim(),
      enableEncryption: enableEncryption,
    );
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
    final id = roomIdOrAlias.trim();
    final colon = id.lastIndexOf(':');
    final via =
        colon > 0 && colon < id.length - 1 ? <String>[id.substring(colon + 1)] : null;
    return client.joinRoom(id, via: via);
  }

  Future<void> invite(Room room, String userId) {
    return room.invite(userId.trim());
  }

  Future<void> leave(Room room) => room.leave();

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
    return timeline.setReadMarker(eventId: eventId);
  }

  Future<void> setTyping(Room room, bool typing) {
    return room.setTyping(typing, timeout: typing ? 8000 : null);
  }

  Future<String?> sendText(
    Room room,
    String text, {
    Event? replyTo,
    Event? edit,
    String? threadRootEventId,
    String? threadLastEventId,
  }) {
    return room.sendTextEvent(
      text,
      inReplyTo: replyTo,
      editEventId: edit?.eventId,
      threadRootEventId: threadRootEventId,
      threadLastEventId: threadLastEventId,
    );
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
  }) {
    return room.sendFileEvent(
      MatrixFile(bytes: bytes, name: fileName),
      inReplyTo: replyTo,
    );
  }
}
