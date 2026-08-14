const highLifeUrlScheme = 'highlife';

const highLifeLinuxApplicationId = 'app.highlife.highlife_client';

/// HKCU classes for an unpackaged Windows build (`reg add`).
List<List<String>> windowsProtocolRegCommands({
  required String scheme,
  required String executable,
}) {
  final classes = r'Software\Classes\' + scheme;
  return [
    ['add', classes, '/ve', '/d', 'URL:$scheme Protocol', '/f'],
    ['add', classes, '/v', 'URL Protocol', '/d', '', '/f'],
    [
      'add',
      '$classes\\shell\\open\\command',
      '/ve',
      '/d',
      '"$executable" "%1"',
      '/f',
    ],
  ];
}

/// .desktop body so xdg-open can return `highlife://` to this binary.
String linuxDesktopEntry({
  required String name,
  required String executable,
  required String applicationId,
  required String scheme,
}) {
  return '''
[Desktop Entry]
Name=$name
Exec="$executable" %u
Type=Application
StartupWMClass=$applicationId
MimeType=x-scheme-handler/$scheme;
NoDisplay=true
''';
}
