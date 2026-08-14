import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/services/auth_errors.dart';
import 'package:matrix/matrix.dart';

class _WrappedInitError implements Exception {
  _WrappedInitError(this.originalException);
  final Object originalException;
  @override
  String toString() => originalException.toString();
}

void main() {
  group('normalizeHomeserverInput', () {
    test('adds https and strips trailing slash', () {
      expect(
        normalizeHomeserverInput('testhighlife.strangled.net/'),
        'https://testhighlife.strangled.net',
      );
    });

    test('extracts server from MXID-shaped input', () {
      expect(
        normalizeHomeserverInput('@viewer:testhighlife.strangled.net'),
        'https://testhighlife.strangled.net',
      );
    });

    test('keeps localhost on http', () {
      expect(normalizeHomeserverInput('localhost:8008'), 'http://localhost:8008');
    });
  });

  group('loginTokenFromRedirect', () {
    test('extracts loginToken from query and fragment', () {
      expect(
        loginTokenFromRedirect(
          Uri.parse('highlife://login?loginToken=abc'),
        ),
        'abc',
      );
      expect(
        loginTokenFromRedirect(
          Uri.parse('https://example.org/#loginToken=xyz'),
        ),
        'xyz',
      );
      expect(
        loginTokenFromRedirect(Uri.parse('highlife://login')),
        isNull,
      );
    });
  });

  group('localpartOf', () {
    test('strips MXID to localpart', () {
      expect(localpartOf('@viewer:testhighlife.strangled.net'), 'viewer');
      expect(localpartOf('viewer'), 'viewer');
    });
  });

  group('mapAuthError', () {
    test('passes through auth keys', () {
      expect(mapAuthError(AuthErrorKeys.forbidden), AuthErrorKeys.forbidden);
    });

    test('maps transport failures to network', () {
      expect(
        mapAuthError(Exception('SocketException: Failed host lookup')),
        AuthErrorKeys.network,
      );
    });

    test('does not treat generic ClientException as network', () {
      expect(
        mapAuthError(Exception('ClientException: Bad state')),
        AuthErrorKeys.loginFailed,
      );
    });

    test('unwraps nested originalException to MatrixException', () {
      final matrix = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Invalid password',
      });
      expect(mapAuthError(_WrappedInitError(matrix)), AuthErrorKeys.forbidden);
    });
  });
}
