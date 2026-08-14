import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/deep_links.dart';

void main() {
  test('extracts SSO token from highlife login URLs', () {
    final link = parseHighLifeDeepLink(
      Uri.parse('highlife://login?loginToken=abc'),
    );
    expect(link?.loginToken, 'abc');
    expect(link?.roomId, isNull);
  });

  test('extracts room ids from push deep links', () {
    final link = parseHighLifeDeepLink(
      Uri.parse('highlife://room?id=!chat:example.org'),
    );
    expect(link?.roomId, '!chat:example.org');
  });

  test('ignores unrelated URLs', () {
    expect(
      parseHighLifeDeepLink(Uri.parse('https://example.org/app')),
      isNull,
    );
  });
}
