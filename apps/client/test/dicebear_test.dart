import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/dicebear.dart';

void main() {
  test('keeps a stable hashed seed for the same Matrix id', () {
    expect(dicebearSeed('@alice:example.org'), dicebearSeed('@alice:example.org'));
    expect(dicebearSeed('@alice:example.org'), isNot(dicebearSeed('@bob:example.org')));
    expect(dicebearSeed('@alice:example.org'), dicebearSeed(' @ALICE:example.org '));
  });

  test('builds a DiceBear PNG URL without the raw MXID', () {
    expect(dicebearSeed('@alice:example.org'), 'f7d6ffc5');
    final url = dicebearAvatarUrl('@alice:example.org', size: 96);
    expect(url, contains('https://api.dicebear.com/9.x/notionists-neutral/png?'));
    expect(url, contains('size=96'));
    expect(url, contains('backgroundColor='));
    expect(url, isNot(contains('alice')));
    expect(url, contains('seed=${dicebearSeed('@alice:example.org')}'));
  });
}
