import '../services/auth_errors.dart';
import 'auth_web_flow_stub.dart'
    if (dart.library.io) 'auth_web_flow_io.dart' as impl;
import '../hl_kit.dart';

export '../services/auth_errors.dart' show AuthBrowserOutcome, AuthBrowserResult;

/// Open MAS/SSO in an in-app WebView when the platform can host one.
Future<AuthBrowserResult> showAuthWebFlow({
  required BuildContext context,
  required Uri uri,
  required String title,
  required String doneLabel,
}) {
  return impl.showAuthWebFlow(
    context: context,
    uri: uri,
    title: title,
    doneLabel: doneLabel,
  );
}
