import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/matrix_identity.dart';
import 'package:highlife_client/widgets/matrix_avatar.dart';

void main() {
  group('normalizeRoomReference', () {
    test('adds the alias marker and current server when omitted', () {
      expect(
        normalizeRoomReference('highlife', homeserver: 'matrix.example.org'),
        '#highlife:matrix.example.org',
      );
    });

    test('keeps complete room ids and aliases unchanged', () {
      expect(
        normalizeRoomReference('#team:example.org'),
        '#team:example.org',
      );
      expect(
        normalizeRoomReference('!opaque:example.org'),
        '!opaque:example.org',
      );
    });
  });

  test('avatar fallback color is stable and identity-specific', () {
    expect(
      deterministicAvatarColor('@alice:example.org'),
      deterministicAvatarColor('@alice:example.org'),
    );
    expect(
      deterministicAvatarColor('@alice:example.org'),
      isNot(deterministicAvatarColor('@bob:example.org')),
    );
  });
}
