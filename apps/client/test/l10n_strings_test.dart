import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/l10n/messages.dart';

void main() {
  group('AppStrings', () {
    test('defaults to English values', () {
      final s = AppStrings(AppLocale.en);
      expect(s.signIn, 'Sign in');
      expect(s.settings, 'Settings');
      expect(s.startCall, 'Start call');
      expect(s.syncError, 'Offline or sync error');
    });

    test('returns Russian values for ru locale', () {
      final s = AppStrings(AppLocale.ru);
      expect(s.signIn, 'Войти');
      expect(s.settings, 'Настройки');
      expect(s.invites, 'Приглашения');
      expect(s.retry, 'Повторить');
      expect(s.roomAliasLabel, 'Основной адрес');
      expect(s.changeAvatar, 'Изменить аватар');
    });

    test('exposes avatar and alias actions in English', () {
      final s = AppStrings(AppLocale.en);
      expect(s.roomAliasLabel, 'Canonical address');
      expect(s.changeAvatar, 'Change avatar');
      expect(s.optionalRoomAlias, 'Address (optional)');
      expect(s.callAnswer, 'Answer');
      expect(s.callHangup, 'Hang up');
      expect(s.callFallback, 'Use Element Call');
      expect(s.pinMessage, 'Pin');
      expect(s.muteNotifications, 'Mute notifications');
    });

    test('every key exists in both EN and RU', () {
      for (final key in AppStrings.keys) {
        expect(AppStrings.hasKeyInBoth(key), isTrue, reason: key);
      }
    });

    test('formats placeholders', () {
      final s = AppStrings(AppLocale.en);
      expect(s.replyingTo('@alice:example.org'), 'Replying to @alice:example.org');
      expect(s.typingUsers('Alice'), 'Alice typing…');
      expect(s.syncErrorDetail('timeout'), 'Sync error: timeout');
    });

    test('AppLocale.fromCode normalizes prefixes', () {
      expect(AppLocale.fromCode(null), AppLocale.en);
      expect(AppLocale.fromCode('en'), AppLocale.en);
      expect(AppLocale.fromCode('ru_RU'), AppLocale.ru);
      expect(AppLocale.fromCode('unknown'), AppLocale.en);
    });

    test('callbackFeedback maps status keys', () {
      final s = AppStrings(AppLocale.en);
      expect(s.callbackFeedback('sending'), s.sending);
      expect(s.callbackFeedback('sent'), s.sent);
      expect(s.callbackFeedback('failed'), s.failed);
    });
  });
}
