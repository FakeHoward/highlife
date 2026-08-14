import '../hl_kit.dart';
import '../services/auth_errors.dart';

Future<AuthBrowserResult> showAuthWebFlow({
  required BuildContext context,
  required Uri uri,
  required String title,
  required String doneLabel,
}) async {
  return const AuthBrowserResult(AuthBrowserOutcome.unsupported);
}
