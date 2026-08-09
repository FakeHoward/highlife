import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/update_checker.dart';

void main() {
  group('ClientReleaseInfo', () {
    test('parses latest.json including sha256', () {
      final info = ClientReleaseInfo.fromJson({
        'version': '0.2.0',
        'build': 2,
        'notes': 'Parity release',
        'assets': {
          'android': 'https://example.com/a.apk',
          'windows': 'https://example.com/w.zip',
        },
        'sha256': {
          'android':
              '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        },
      });
      expect(info.version, '0.2.0');
      expect(info.build, 2);
      expect(info.notes, 'Parity release');
      expect(info.assets['android'], contains('.apk'));
      expect(info.sha256['android'], startsWith('0123'));
    });
  });

  group('release URL trust', () {
    test('requires HTTPS and matching or allowlisted host', () {
      const meta = 'https://testhighlife.strangled.net/client/latest.json';
      expect(
        isTrustedReleaseAssetUrl(
          'https://testhighlife.strangled.net/client/highlife.apk',
          latestJsonUrl: meta,
        ),
        isTrue,
      );
      expect(
        isTrustedReleaseAssetUrl(
          'https://github.com/acme/highlife/releases/download/v1/a.apk',
          latestJsonUrl: meta,
        ),
        isTrue,
      );
      expect(
        isTrustedReleaseAssetUrl(
          'http://testhighlife.strangled.net/client/highlife.apk',
          latestJsonUrl: meta,
        ),
        isFalse,
      );
      expect(
        isTrustedReleaseAssetUrl(
          'https://evil.example/a.apk',
          latestJsonUrl: meta,
        ),
        isFalse,
      );
      expect(isHttpsUri(Uri.parse(meta)), isTrue);
      expect(isHttpsUri(Uri.parse('http://example.com/x')), isFalse);
    });
  });

  group('integrity', () {
    test('verifies sha256 and rejects mismatch', () {
      final bytes = utf8.encode('highlife');
      final expected = sha256.convert(bytes).toString();
      expect(verifyAssetSha256(bytes, expected), isTrue);
      expect(
        verifyAssetSha256(
          bytes,
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        ),
        isFalse,
      );
      expect(isSha256Hex('abc'), isFalse);
    });

    test('integrityGateError fails closed when native hash missing', () {
      final info = ClientReleaseInfo.fromJson({
        'version': '9.0.0',
        'build': 99,
        'assets': {
          'android': 'https://github.com/acme/r/releases/download/v9/a.apk',
          'web': 'https://github.com/acme/r/releases/download/v9/w.zip',
        },
      });
      // On the VM test target (linux/windows/mac), native platforms require hash.
      if (platformRequiresIntegrityHash()) {
        expect(integrityGateError(info), contains('Missing sha256'));
      }
      final withHash = ClientReleaseInfo.fromJson({
        'version': '9.0.0',
        'build': 99,
        'assets': {
          'android': 'https://github.com/acme/r/releases/download/v9/a.apk',
          'windows': 'https://github.com/acme/r/releases/download/v9/w.zip',
          'linux': 'https://github.com/acme/r/releases/download/v9/l.zip',
        },
        'sha256': {
          'android':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'windows':
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'linux':
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        },
      });
      expect(integrityGateError(withHash), isNull);
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
