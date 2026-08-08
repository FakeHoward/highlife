import 'package:matrix/matrix.dart';

/// Normalize like web: trim, strip trailing `/`, MXID → server host, add scheme.
String normalizeHomeserverInput(String homeserver) {
  var hs = homeserver.trim().replaceFirst(RegExp(r'/+$'), '');
  if (hs.startsWith('@') && hs.contains(':')) {
    hs = hs.split(':').skip(1).join(':');
  }
  if (!hs.contains('://')) {
    hs = hs.startsWith('localhost') || hs.startsWith('127.')
        ? 'http://$hs'
        : 'https://$hs';
  }
  return hs.replaceFirst(RegExp(r'/+$'), '');
}

/// Localpart for password login (`@user:server` → `user`, else trimmed input).
String localpartOf(String userIdOrName) {
  final trimmed = userIdOrName.trim().replaceFirst(RegExp(r'^@'), '');
  if (trimmed.isEmpty) return '';
  return trimmed.split(':').first;
}

/// Stable auth error keys resolved in the UI via [AppStrings.authError].
abstract final class AuthErrorKeys {
  static const forbidden = 'auth.forbidden';
  static const userInUse = 'auth.userInUse';
  static const invalidUsername = 'auth.invalidUsername';
  static const weakPassword = 'auth.weakPassword';
  static const passwordLoginUnsupported = 'auth.passwordLoginUnsupported';
  static const uiaUnsupported = 'auth.uiaUnsupported';
  static const registerIncomplete = 'auth.registerIncomplete';
  static const usernameRequired = 'auth.usernameRequired';
  static const homeserverRequired = 'auth.homeserverRequired';
  static const userRequired = 'auth.userRequired';
  static const passwordRequired = 'auth.passwordRequired';
  static const passwordTooShort = 'auth.passwordTooShort';
  static const logoutFailed = 'auth.logoutFailed';
  static const loginFailed = 'auth.loginFailed';
  static const registerFailed = 'auth.registerFailed';
  static const network = 'auth.network';
}

Object _unwrapAuthError(Object error) {
  // ClientInitException is not always exported from package:matrix; unwrap by shape.
  try {
    final original = (error as dynamic).originalException;
    if (original is Object) return _unwrapAuthError(original);
  } catch (_) {}
  return error;
}

bool _looksLikeNetworkFailure(Object error) {
  if (error is MatrixException) return false;
  final text = error.toString().toLowerCase();
  // Prefer real transport failures; do not treat every ClientException as offline
  // (matrix wraps some API failures that way on mobile).
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('network is unreachable') ||
      text.contains('timed out') ||
      text.contains('timeout') ||
      text.contains('handshakeexception') ||
      text.contains('certificate');
}

String mapAuthError(Object error, {bool registering = false}) {
  if (error is String && error.startsWith('auth.')) return error;
  final unwrapped = _unwrapAuthError(error);
  if (unwrapped is String && unwrapped.startsWith('auth.')) return unwrapped;

  if (unwrapped is MatrixException) {
    switch (unwrapped.errcode) {
      case 'M_FORBIDDEN':
      case 'M_UNAUTHORIZED':
        return AuthErrorKeys.forbidden;
      case 'M_USER_IN_USE':
        return AuthErrorKeys.userInUse;
      case 'M_INVALID_USERNAME':
        return AuthErrorKeys.invalidUsername;
      case 'M_WEAK_PASSWORD':
        return AuthErrorKeys.weakPassword;
      default:
        break;
    }
    final message = unwrapped.errorMessage.toLowerCase();
    if (message.contains('user_in_use') || message.contains('already taken')) {
      return AuthErrorKeys.userInUse;
    }
    if (message.contains('forbidden') || message.contains('invalid password')) {
      return AuthErrorKeys.forbidden;
    }
  }

  if (_looksLikeNetworkFailure(unwrapped) || _looksLikeNetworkFailure(error)) {
    return AuthErrorKeys.network;
  }
  return registering ? AuthErrorKeys.registerFailed : AuthErrorKeys.loginFailed;
}

/// HighLife only auto-completes single-stage `m.login.dummy` UIA.
bool uiaAllowsDummy(MatrixException error) {
  final flows = error.authenticationFlows;
  if (flows == null || flows.isEmpty) return true;
  return flows.any(
    (flow) =>
        flow.stages.length == 1 && flow.stages.first == AuthenticationTypes.dummy,
  );
}
