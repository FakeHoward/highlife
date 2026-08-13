import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/messenger_extras.dart';

void main() {
  group('messenger extras', () {
    test('toggles pinned ids', () {
      expect(togglePinnedIds(['\$a'], '\$b'), ['\$a', '\$b']);
      expect(togglePinnedIds(['\$a', '\$b'], '\$a'), ['\$b']);
    });

    test('finds the first unread event', () {
      expect(firstUnreadEventId(['\$a', '\$b'], null), '\$a');
      expect(firstUnreadEventId(['\$a', '\$b'], '\$a'), '\$b');
      expect(firstUnreadEventId(['\$a', '\$b'], '\$b'), isNull);
    });

    test('quotes forwarded body', () {
      expect(formatForwardedBody('Ada', 'hello'), 'Ada:\nhello');
    });
  });
}
