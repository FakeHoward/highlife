/// Pure membership helpers (no Matrix SDK dependency) for unit tests and UI.
library;

const membershipInvite = 'invite';
const membershipJoin = 'join';
const membershipLeave = 'leave';

/// Returns items whose membership equals [membership].
List<T> filterByMembership<T>(
  Iterable<T> items,
  String Function(T item) membershipOf,
  String membership,
) {
  return items
      .where((item) => membershipOf(item) == membership)
      .toList(growable: false);
}

/// Rooms (or room-like entries) with invite membership.
List<T> filterInviteRooms<T>(
  Iterable<T> items,
  String Function(T item) membershipOf,
) =>
    filterByMembership(items, membershipOf, membershipInvite);

/// Joined rooms only (excludes invites / left).
List<T> filterJoinedRooms<T>(
  Iterable<T> items,
  String Function(T item) membershipOf,
) =>
    filterByMembership(items, membershipOf, membershipJoin);

/// Split into invites then joined (each group keeps input order).
({List<T> invites, List<T> joined}) partitionInvitesAndJoined<T>(
  Iterable<T> items,
  String Function(T item) membershipOf,
) {
  final invites = <T>[];
  final joined = <T>[];
  for (final item in items) {
    final membership = membershipOf(item);
    if (membership == membershipInvite) {
      invites.add(item);
    } else if (membership == membershipJoin) {
      joined.add(item);
    }
  }
  return (invites: invites, joined: joined);
}
