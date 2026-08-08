import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/room_filters.dart';

class _Room {
  const _Room(this.id, this.membership);
  final String id;
  final String membership;
}

void main() {
  group('room membership filters', () {
    const rooms = [
      _Room('a', membershipJoin),
      _Room('b', membershipInvite),
      _Room('c', membershipJoin),
      _Room('d', membershipLeave),
      _Room('e', membershipInvite),
    ];

    test('filterInviteRooms keeps invite membership only', () {
      final invites = filterInviteRooms(rooms, (room) => room.membership);
      expect(invites.map((room) => room.id), ['b', 'e']);
    });

    test('filterJoinedRooms keeps join membership only', () {
      final joined = filterJoinedRooms(rooms, (room) => room.membership);
      expect(joined.map((room) => room.id), ['a', 'c']);
    });

    test('partitionInvitesAndJoined preserves order in each bucket', () {
      final parts = partitionInvitesAndJoined(
        rooms,
        (room) => room.membership,
      );
      expect(parts.invites.map((room) => room.id), ['b', 'e']);
      expect(parts.joined.map((room) => room.id), ['a', 'c']);
    });
  });
}
