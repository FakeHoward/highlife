String normalizeRoomReference(String value, {String? homeserver}) {
  final input = value.trim();
  if (input.isEmpty || input.startsWith('!')) return input;
  if (input.startsWith('#') && input.contains(':')) return input;

  final alias = input.startsWith('#') ? input : '#$input';
  if (alias.contains(':')) return alias;

  final server = homeserver?.trim() ?? '';
  if (server.isEmpty) return alias;
  final host = Uri.tryParse(
        server.contains('://') ? server : 'https://$server',
      )?.host ??
      server;
  return host.isEmpty ? alias : '$alias:$host';
}

String? canonicalAliasFromState(
  Map<String, Map<String, dynamic>>? stateContent,
) {
  final content = stateContent?[''];
  final alias = content?['alias'];
  return alias is String && alias.trim().isNotEmpty ? alias.trim() : null;
}
