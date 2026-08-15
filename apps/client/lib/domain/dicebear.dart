/// DiceBear fallback avatars. Seed is a hash of the Matrix id, not the raw MXID.
const _host = 'https://api.dicebear.com';
const _version = '9.x';
const _style = 'notionists-neutral';

const _backgrounds = <String>[
  '168acd',
  '2a9d8f',
  '457b9d',
  '6d597a',
  'c44536',
  '577590',
];

/// FNV-1a 32-bit, stable across web and Flutter.
String dicebearSeed(String identity) {
  var hash = 2166136261;
  final normalized = identity.trim().toLowerCase();
  for (final unit in normalized.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String dicebearBackground(String identity) {
  final seed = dicebearSeed(identity);
  final nibble = int.parse(seed.substring(seed.length - 1), radix: 16);
  return _backgrounds[nibble % _backgrounds.length];
}

String dicebearAvatarUrl(String identity, {int size = 128}) {
  final seed = dicebearSeed(identity);
  final params = {
    'seed': seed,
    'size': '$size',
    'backgroundColor': dicebearBackground(identity),
  };
  final query = params.entries
      .map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}')
      .join('&');
  return '$_host/$_version/$_style/png?$query';
}
