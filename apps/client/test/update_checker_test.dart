import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/update_checker.dart';

void main() {
  group('ClientReleaseInfo', () {
    test('parses latest.json', () {
      final info = ClientReleaseInfo.fromJson({
        'version': '0.2.0',
        'build': 2,
        'notes': 'Parity release',
        'assets': {
          'android': 'https://example.com/a.apk',
          'windows': 'https://example.com/w.zip',
        },
      });
      expect(info.version, '0.2.0');
      expect(info.build, 2);
      expect(info.notes, 'Parity release');
      expect(info.assets['android'], contains('.apk'));
    });
  });

  group('isNewerRelease', () {
    test('detects newer version and build', () {
      expect(
        isNewerRelease(
          latestVersion: '0.2.0',
          latestBuild: 2,
          currentVersion: '0.1.0',
          currentBuild: 1,
        ),
        isTrue,
      );
      expect(
        isNewerRelease(
          latestVersion: '0.2.0',
          latestBuild: 3,
          currentVersion: '0.2.0',
          currentBuild: 2,
        ),
        isTrue,
      );
      expect(
        isNewerRelease(
          latestVersion: '0.2.0',
          latestBuild: 2,
          currentVersion: '0.2.0',
          currentBuild: 2,
        ),
        isFalse,
      );
    });
  });
}
