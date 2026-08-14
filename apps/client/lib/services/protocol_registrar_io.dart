import 'dart:io';

import '../domain/protocol_registration.dart';

Future<void> registerHighLifeProtocol() async {
  try {
    if (Platform.isWindows) {
      await _registerWindows();
    } else if (Platform.isLinux) {
      await _registerLinux();
    }
  } catch (_) {
    // Protocol registration is best-effort; SSO can still paste a token.
  }
}

Future<void> _registerWindows() async {
  final exe = Platform.resolvedExecutable;
  for (final args in windowsProtocolRegCommands(
    scheme: highLifeUrlScheme,
    executable: exe,
  )) {
    await Process.run('reg', args, runInShell: true);
  }
}

Future<void> _registerLinux() async {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return;
  final dir = Directory('$home/.local/share/applications');
  await dir.create(recursive: true);
  final desktop = File('${dir.path}/$highLifeLinuxApplicationId.desktop');
  await desktop.writeAsString(
    linuxDesktopEntry(
      name: 'HighLife',
      executable: Platform.resolvedExecutable,
      applicationId: highLifeLinuxApplicationId,
      scheme: highLifeUrlScheme,
    ),
  );
  await Process.run('xdg-mime', [
    'default',
    '$highLifeLinuxApplicationId.desktop',
    'x-scheme-handler/$highLifeUrlScheme',
  ]);
  await Process.run('update-desktop-database', [dir.path]);
}
