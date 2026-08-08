import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/l10n/messages.dart';

void main() {
  group('AppStrings locale lookup', () {
    test('returns English by default', () {
      final en = AppStrings(AppLocale.en);

      expect(en.signIn, 'Sign in');
      expect(en.settings, 'Settings');
      expect(en.inviteMember, 'Invite member');
      expect(en.searchConversations, 'Search conversations');
      expect(en.startCall, 'Start call');
      expect(en.encryptionAvailable, 'Encryption available');
    });

    test('returns Russian translations for the same keys', () {
      final ru = AppStrings(AppLocale.ru);

      expect(ru.signIn, 'Войти');
      expect(ru.settings, 'Настройки');
      expect(ru.inviteMember, 'Пригласить участника');
      expect(ru.searchConversations, 'Поиск бесед');
      expect(ru.startCall, 'Начать звонок');
      expect(ru.encryptionAvailable, 'Шифрование доступно');
    });

    test('interpolates reply target and maps callback status keys', () {
      final en = AppStrings(AppLocale.en);
      final ru = AppStrings(AppLocale.ru);

      expect(en.replyingTo('@alice:example.org'), 'Replying to @alice:example.org');
      expect(ru.replyingTo('@alice:example.org'), 'Ответ @alice:example.org');
      expect(en.callbackFeedback('sending'), 'Sending…');
      expect(ru.callbackFeedback('sent'), 'Отправлено');
      expect(ru.callbackFeedback('failed'), 'Ошибка');
    });

    test('AppLocale.fromCode falls back to English', () {
      expect(AppLocale.fromCode('ru'), AppLocale.ru);
      expect(AppLocale.fromCode('en'), AppLocale.en);
      expect(AppLocale.fromCode(null), AppLocale.en);
      expect(AppLocale.fromCode('de'), AppLocale.en);
    });
  });
}
