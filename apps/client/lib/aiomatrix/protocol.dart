/// Wire protocol shared with the Node aiomatrix bot framework.
library;

import 'dart:convert';

import 'markdown.dart';

const keyboardContentKey = 'dev.aiomatrix.keyboard';
const callbackEventType = 'dev.aiomatrix.callback';
const callbackAnswerEventType = 'dev.aiomatrix.callback_answer';
const toastEventType = 'dev.aiomatrix.toast';
const progressEventType = 'dev.aiomatrix.progress';
const hostCapabilitiesStateEventType = 'dev.aiomatrix.host';
const miniAppContentKey = 'dev.aiomatrix.mini_app';
const miniAppDataMsgType = 'dev.aiomatrix.mini_app_data';
const miniAppDataKey = 'dev.aiomatrix.mini_app_data';
const commandsStateEventType = 'dev.aiomatrix.commands';
const callbackFallbackCommand = 'cb';
const miniAppMsgtypeStudnovsu = 'ru.studnovsu.mini_app';
const hostCapabilitiesSchemaVersion = 1;

/// Aware-host handshake content for `dev.aiomatrix.host` room state.
Map<String, Object?> buildHostCapabilitiesContent() => {
      'version': hostCapabilitiesSchemaVersion,
      'client_profile': 'aware',
      'features': const [
        'keyboard',
        'callback_answer',
        'toast',
        'progress',
        'poll_ui',
        'mini_app',
      ],
      'keyboard': true,
      'callback_answer': true,
      'toast': true,
      'progress': true,
      'poll_ui': true,
      'mini_app': true,
    };

enum ButtonKind { callback, url, miniApp, command }

class InlineButton {
  const InlineButton({
    required this.kind,
    required this.text,
    this.data,
    this.token,
    this.url,
    this.command,
    this.startParam,
    this.style,
  });

  final ButtonKind kind;
  final String text;
  final String? data;
  final String? token;
  final String? url;
  final String? command;
  final String? startParam;
  final String? style;

  factory InlineButton.fromJson(Map<String, dynamic> json) {
    final kindRaw = json['kind'] as String? ?? 'callback';
    final kind = switch (kindRaw) {
      'url' => ButtonKind.url,
      'mini_app' => ButtonKind.miniApp,
      'command' => ButtonKind.command,
      _ => ButtonKind.callback,
    };
    return InlineButton(
      kind: kind,
      text: (json['text'] as String?)?.trim() ?? '',
      data: json['data'] as String?,
      token: json['token'] as String?,
      url: json['url'] as String?,
      command: json['command'] as String?,
      startParam: json['startParam'] as String?,
      style: json['style'] as String?,
    );
  }
}

class KeyboardContent {
  const KeyboardContent({required this.inline, this.fallbackCommand});

  final List<List<InlineButton>> inline;
  final String? fallbackCommand;

  static KeyboardContent? tryParse(Map<String, dynamic>? content) {
    if (content == null) return null;
    final raw = content[keyboardContentKey];
    if (raw is! Map) return null;
    final rows = raw['inline'];
    if (rows is! List) return null;
    final inline = <List<InlineButton>>[];
    for (final row in rows) {
      if (row is! List) continue;
      final buttons = <InlineButton>[];
      for (final item in row) {
        if (item is! Map) continue;
        final btn = InlineButton.fromJson(Map<String, dynamic>.from(item));
        if (btn.text.isEmpty) continue;
        buttons.add(btn);
      }
      if (buttons.isNotEmpty) inline.add(buttons);
    }
    if (inline.isEmpty) return null;
    return KeyboardContent(
      inline: inline,
      fallbackCommand: raw['fallback_command'] as String? ?? callbackFallbackCommand,
    );
  }

  /// Drop MiniApp buttons when a dedicated MiniApp card is already shown.
  KeyboardContent withoutMiniAppButtons() {
    final filtered = inline
        .map((row) => row.where((b) => b.kind != ButtonKind.miniApp).toList())
        .where((row) => row.isNotEmpty)
        .toList();
    if (filtered.isEmpty) {
      return KeyboardContent(inline: const [], fallbackCommand: fallbackCommand);
    }
    return KeyboardContent(inline: filtered, fallbackCommand: fallbackCommand);
  }
}

class MiniAppCard {
  const MiniAppCard({
    required this.url,
    this.title,
    this.description,
    this.buttonText,
    this.appId,
    this.botId,
    this.startParam,
    this.display,
  });

  final String url;
  final String? title;
  final String? description;
  final String? buttonText;
  final String? appId;
  final String? botId;
  final String? startParam;
  final String? display;

  static MiniAppCard? tryParse(Map<String, dynamic>? content) {
    if (content == null) return null;
    final raw = content[miniAppContentKey];
    if (raw is Map) {
      final url = raw['url'] as String?;
      if (url != null && url.isNotEmpty) {
        return MiniAppCard(
          url: url,
          title: raw['title'] as String?,
          description: raw['description'] as String?,
          buttonText: raw['button_text'] as String?,
          appId: raw['app_id'] as String?,
          botId: raw['bot_id'] as String?,
          startParam: raw['start_param'] as String?,
          display: raw['display'] as String?,
        );
      }
    }
    if (content['msgtype'] == miniAppMsgtypeStudnovsu) {
      final url = content['url'] as String?;
      if (url != null && url.isNotEmpty) {
        return MiniAppCard(
          url: url,
          title: content['title'] as String?,
          botId: content['bot_id'] as String?,
        );
      }
    }
    return null;
  }
}

class AdvertisedCommand {
  const AdvertisedCommand({
    required this.name,
    this.aliases = const [],
    this.description,
    this.args,
    this.category,
  });

  final String name;
  final List<String> aliases;
  final String? description;
  final String? args;
  final String? category;

  factory AdvertisedCommand.fromJson(Map<String, dynamic> json) {
    return AdvertisedCommand(
      name: json['name'] as String? ?? '',
      aliases: (json['aliases'] as List?)?.cast<String>() ?? const [],
      description: json['description'] as String?,
      args: json['args'] as String?,
      category: json['category'] as String?,
    );
  }
}

class CommandsState {
  const CommandsState({
    required this.commands,
    this.prefixes = const ['/', '!'],
    required this.botId,
  });

  final List<AdvertisedCommand> commands;
  final List<String> prefixes;
  final String botId;

  static CommandsState? tryParse(Map<String, dynamic>? content, String stateKey) {
    if (content == null) return null;
    final raw = content['commands'];
    if (raw is! List) return null;
    final commands = <AdvertisedCommand>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final cmd = AdvertisedCommand.fromJson(Map<String, dynamic>.from(item));
      if (cmd.name.isNotEmpty) commands.add(cmd);
    }
    if (commands.isEmpty) return null;
    final prefixes = (content['prefixes'] as List?)?.cast<String>() ?? const ['/', '!'];
    return CommandsState(commands: commands, prefixes: prefixes, botId: stateKey);
  }
}

Map<String, dynamic> buildCallbackContent(InlineButton button, String messageId) {
  if (button.token != null && button.token!.isNotEmpty) {
    return {'token': button.token, 'message_id': messageId};
  }
  return {'data': button.data ?? '', 'message_id': messageId};
}

/// Pull signed MiniApp initData from a launch URL fragment when present.
String? extractMiniAppInitData(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasFragment) return null;
  final params = Uri.splitQueryString(uri.fragment);
  return params['matrixWebAppData'] ?? params['tgWebAppData'];
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'rsvp':
      return 'RSVP';
    case 'survey':
      return 'survey';
    case 'join':
      return 'join request';
    case 'onboard':
      return 'onboarding';
    default:
      return kind;
  }
}

String _choiceLabel(String choice) {
  switch (choice) {
    case 'going':
      return 'Going';
    case 'maybe':
      return 'Maybe';
    case 'no':
      return "Can't make it";
    default:
      return choice;
  }
}

/// Humanize MiniApp `sendData` JSON for timeline / room-list display.
String? humanizeStructuredPayload(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final action = decoded['action']?.toString() ?? '';
    if (action.isEmpty) return null;
    final title = (decoded['title']?.toString() ?? '').trim();
    final kind = decoded['kind']?.toString() ?? '';
    final choice = decoded['choice']?.toString() ?? '';
    switch (action) {
      case 'publish':
        final label = _kindLabel(kind);
        return title.isEmpty
            ? 'Published ${label.isEmpty ? 'form' : label}'
            : 'Published ${label.isEmpty ? 'form' : label}: $title';
      case 'save_draft':
        return title.isEmpty ? 'Saved form draft' : 'Saved draft: $title';
      case 'submit':
        return 'Submitted a form response';
      case 'rsvp':
        return choice.isEmpty ? 'RSVP response' : 'RSVP: ${_choiceLabel(choice)}';
      default:
        return 'MiniApp · $action';
    }
  } catch (_) {
    return null;
  }
}

String _stripKeyboardFallbackText(String body) {
  return body
      .replaceAll(RegExp(r'\n\n(?:\d+\.\s+.+(?:\n|$))+$', multiLine: true), '')
      .replaceAll(RegExp(r'\n\n(?:.*!cb\s+\S+(?:\n|$))+$', multiLine: true), '')
      .trimRight();
}

String _stripMiniAppUrlFallback(String body) {
  return body
      .replaceAll(RegExp(r'^[^\n]*:\s*https?:\/\/\S+\s*$', multiLine: true), '')
      .replaceAll(RegExp(r'https?:\/\/\S*matrixWebAppData=\S+'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String? _miniAppDataPayload(Map<String, dynamic> content) {
  final nested = content[miniAppDataKey];
  if (nested is Map && nested['data'] is String) {
    final data = nested['data'] as String;
    if (data.isNotEmpty) return data;
  }
  if (content['msgtype'] == miniAppDataMsgType && content['body'] is String) {
    return content['body'] as String;
  }
  return null;
}

/// Timeline body: humanize MiniApp data + strip wire fallbacks (keep Markdown).
String resolveDisplayBody(Map<String, dynamic> content) {
  final data = _miniAppDataPayload(content);
  if (data != null) {
    final human = humanizeStructuredPayload(data);
    if (human != null) return human;
    return data.trim().startsWith('{') ? 'MiniApp data' : data;
  }
  final body = content['body']?.toString() ?? '';
  final humanized = humanizeStructuredPayload(body);
  if (humanized != null) return humanized;
  final card = MiniAppCard.tryParse(content);
  if (card != null) {
    final parts = [card.title, card.description]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty);
    final joined = parts.join('\n\n');
    if (joined.isNotEmpty) return joined;
  }
  var text = body;
  if (content.containsKey(keyboardContentKey) ||
      content.containsKey('ru.studnovsu.inline_keyboard')) {
    text = _stripKeyboardFallbackText(text);
  }
  text = _stripMiniAppUrlFallback(text);
  text = text
      .replaceAll(RegExp(r'(?:^|\n).*!cb\s+\S+.*'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return text;
}

/// Single-line room-list preview.
String formatMessagePreview(Map<String, dynamic> content) {
  return markdownToPlain(resolveDisplayBody(content))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Map<String, dynamic> buildMiniAppDataContent({
  required String data,
  String? queryId,
  String? appId,
  String? messageId,
}) {
  return {
    'msgtype': miniAppDataMsgType,
    'body': humanizeStructuredPayload(data) ?? 'MiniApp data',
    miniAppDataKey: {
      'version': 1,
      'data': data,
      if (queryId != null) 'query_id': queryId,
      if (appId != null) 'app_id': appId,
      if (messageId != null) 'message_id': messageId,
    },
  };
}

List<AdvertisedCommand> filterSuggestions(
  List<AdvertisedCommand> commands,
  String typed,
) {
  final t = typed.trim();
  if (t.isEmpty || !(t.startsWith('/') || t.startsWith('!'))) {
    return const [];
  }
  final q = t.substring(1).toLowerCase();
  return commands
      .where(
        (c) =>
            c.name.toLowerCase().startsWith(q) ||
            c.aliases.any((a) => a.toLowerCase().startsWith(q)),
      )
      .take(8)
      .toList();
}

String completeCommand(AdvertisedCommand command, {required String typed}) {
  final prefix = typed.trimLeft().startsWith('!') ? '!' : '/';
  return '$prefix${command.name} ';
}

bool isSafeHttpUrl(String url, {bool requireHttps = false}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  if (!requireHttps) return true;
  return uri.host == 'localhost' ||
      uri.host == '127.0.0.1' ||
      uri.host == '[::1]';
}

bool isLikelyBotUserId(String userId) {
  final localpart = userId.startsWith('@')
      ? userId.substring(1).split(':').first
      : userId;
  final key = localpart.toLowerCase();
  return key == 'highlifebot' || key.endsWith('bot') || key.startsWith('bot');
}

bool roomNeedsHostHandshake({
  required Iterable<String> memberUserIds,
  bool hasCommandsState = false,
}) {
  if (hasCommandsState) return true;
  return memberUserIds.any(isLikelyBotUserId);
}
