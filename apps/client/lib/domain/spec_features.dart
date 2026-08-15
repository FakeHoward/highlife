/// Wire helpers for Element-parity MSCs. Keep this file free of Flutter widgets.
library;

const msc4139PromptsKey = 'org.matrix.msc4139.prompts';
const msc4139UsedPromptKey = 'org.matrix.msc4139.used_prompt';
const msc4139ReplyType = 'org.matrix.msc4139.conversation.reply';
const msc4332CommandsState = 'org.matrix.msc4332.commands';
const msc4310Decline = 'm.rtc.decline';
const msc4310DeclineUnstable = 'org.matrix.msc4310.rtc.decline';
const msc2545PackState = 'im.ponies.room_emotes';
const msc2545UserEmotes = 'im.ponies.user_emotes';
const stickerEventType = 'm.sticker';
const msc3266SummaryPath = '/_matrix/client/v1/room_summary';
const msc3266SummaryUnstablePath =
    '/_matrix/client/unstable/im.nheko.summary/summary';
const simplifiedSlidingSyncPath =
    '/_matrix/client/unstable/org.matrix.simplified_msc3575/sync';
const msc3575SlidingSyncPath = '/_matrix/client/unstable/org.matrix.msc3575/sync';
const msc4039Upload = 'org.matrix.msc4039.upload_file';
const msc4039Download = 'org.matrix.msc4039.download_file';

class IntentionalMentions {
  const IntentionalMentions({required this.userIds, this.room = false});

  final List<String> userIds;
  final bool room;

  Map<String, Object?> toJson() => {
        'user_ids': userIds,
        if (room) 'room': true,
      };
}

IntentionalMentions intentionalMentions(String body, Iterable<String> memberIds) {
  final ids = <String>{
    for (final id in memberIds)
      if (id.isNotEmpty && body.contains(id)) id,
  };
  final room = RegExp(r'(^|\s)@room\b', caseSensitive: false).hasMatch(body);
  return IntentionalMentions(userIds: ids.toList(), room: room);
}

Map<String, Object?> attachMentions(
  Map<String, Object?> content,
  String body,
  Iterable<String> memberIds,
) {
  return {...content, 'm.mentions': intentionalMentions(body, memberIds).toJson()};
}

Map<String, Object?> threadRelation(
  String rootId, {
  String? replyToId,
  bool? fallback,
}) {
  final reply = replyToId ?? rootId;
  return {
    'rel_type': 'm.thread',
    'event_id': rootId,
    'is_falling_back': fallback ?? reply == rootId,
    'm.in_reply_to': {'event_id': reply},
  };
}

String? threadRootId(Map<String, dynamic> content) {
  final rel = content['m.relates_to'];
  if (rel is! Map) return null;
  if (rel['rel_type'] != 'm.thread') return null;
  final id = rel['event_id'];
  return id is String ? id : null;
}

bool isThreadFallback(Map<String, dynamic> content) {
  final rel = content['m.relates_to'];
  return rel is Map && rel['is_falling_back'] == true;
}

bool belongsOnMainTimeline(Map<String, dynamic> content) {
  final root = threadRootId(content);
  if (root == null) return true;
  return isThreadFallback(content);
}

class GeoPoint {
  const GeoPoint({
    required this.lat,
    required this.lon,
    required this.geoUri,
    this.description,
  });

  final double lat;
  final double lon;
  final String geoUri;
  final String? description;
}

GeoPoint? parseGeoUri(String value) {
  final match = RegExp(r'^geo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:;|$)', caseSensitive: false)
      .firstMatch(value.trim());
  if (match == null) return null;
  final lat = double.tryParse(match.group(1)!);
  final lon = double.tryParse(match.group(2)!);
  if (lat == null || lon == null) return null;
  return GeoPoint(lat: lat, lon: lon, geoUri: value.trim());
}

Map<String, Object?> locationContent(double lat, double lon, {String? description}) {
  final geoUri = 'geo:$lat,$lon';
  final body = (description?.trim().isNotEmpty ?? false) ? description!.trim() : geoUri;
  return {
    'msgtype': 'm.location',
    'body': body,
    'geo_uri': geoUri,
    'org.matrix.msc3488.location': {
      'uri': geoUri,
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
    },
    'org.matrix.msc3488.ts': DateTime.now().millisecondsSinceEpoch,
    'org.matrix.msc1767.text': body,
  };
}

GeoPoint? parseLocationContent(Map<String, dynamic> content) {
  final nested = content['org.matrix.msc3488.location'];
  final uri = nested is Map ? nested['uri'] : content['geo_uri'];
  if (uri is! String) return null;
  final parsed = parseGeoUri(uri);
  if (parsed == null) return null;
  final description = nested is Map ? nested['description'] : content['body'];
  return GeoPoint(
    lat: parsed.lat,
    lon: parsed.lon,
    geoUri: uri,
    description: description is String ? description : parsed.description,
  );
}

String openStreetMapUrl(double lat, double lon) =>
    'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon';

class ImagePackItem {
  const ImagePackItem({
    required this.shortcode,
    required this.url,
    required this.body,
    this.usage = const ['sticker'],
  });

  final String shortcode;
  final String url;
  final String body;
  final List<String> usage;
}

List<ImagePackItem> parseImagePack(Map<String, dynamic> content) {
  final images = content['images'];
  if (images is! Map) return const [];
  final out = <ImagePackItem>[];
  images.forEach((key, raw) {
    if (raw is! Map) return;
    final url = raw['url'];
    if (url is! String || !url.startsWith('mxc://')) return;
    final usage = (raw['usage'] as List?)?.whereType<String>().toList() ??
        const ['sticker', 'emoticon'];
    out.add(
      ImagePackItem(
        shortcode: key.toString(),
        url: url,
        body: raw['body'] as String? ?? key.toString(),
        usage: usage,
      ),
    );
  });
  return out;
}

Map<String, Object?> stickerContent(ImagePackItem item) => {
      'body': item.body,
      'url': item.url,
      'info': {'mimetype': 'image/png'},
    };

class Msc4139Prompt {
  const Msc4139Prompt({
    required this.id,
    required this.label,
    this.type = 'preset',
    this.validator,
  });

  final String id;
  final String label;
  final String type;
  final String? validator;
}

class Msc4139Prompts {
  const Msc4139Prompts({
    required this.prompts,
    this.intro,
    this.scope,
  });

  final List<Msc4139Prompt> prompts;
  final String? intro;
  final List<String>? scope;
}

String _promptLabel(Object? label) {
  if (label is String) return label;
  if (label is! Map) return '';
  final text = label['m.text'] ?? label['org.matrix.msc1767.text'];
  if (text is List && text.isNotEmpty && text.first is Map) {
    final body = (text.first as Map)['body'];
    if (body is String) return body;
  }
  if (text is String) return text;
  return '';
}

Msc4139Prompts? parseMsc4139Prompts(Map<String, dynamic> content) {
  final raw = content[msc4139PromptsKey] ?? content['m.prompts'];
  if (raw is! Map) return null;
  final promptsRaw = raw['prompts'];
  if (promptsRaw is! List) return null;
  final prompts = <Msc4139Prompt>[];
  for (final item in promptsRaw) {
    if (item is! Map) continue;
    final id = item['id'] as String? ?? '';
    if (id.isEmpty) continue;
    prompts.add(
      Msc4139Prompt(
        id: id,
        type: item['type'] == 'input' ? 'input' : 'preset',
        label: _promptLabel(item['label']).isEmpty ? id : _promptLabel(item['label']),
        validator: item['validator'] as String?,
      ),
    );
  }
  if (prompts.isEmpty) return null;
  final introBlock = raw['intro'];
  final intro = introBlock is Map ? _promptLabel(introBlock['content']) : introBlock as String?;
  final scope = (raw['scope'] as List?)?.whereType<String>().toList();
  return Msc4139Prompts(prompts: prompts, intro: intro, scope: scope);
}

Map<String, Object?> conversationReplyContent({
  required String promptId,
  required String label,
  required String rootEventId,
}) {
  return {
    msc4139UsedPromptKey: {'id': promptId},
    'org.matrix.msc1767.text': label,
    'body': label,
    'msgtype': 'm.text',
    'm.relates_to': threadRelation(rootEventId),
    'm.in_reply_to': {'event_id': rootEventId, 'rel_type': 'm.thread'},
  };
}

Map<String, Object?> rtcDeclineContent({String? notificationEventId}) => {
      if (notificationEventId != null)
        'm.relates_to': {
          'rel_type': 'm.reference',
          'event_id': notificationEventId,
        },
    };

String threadSubscriptionPath(String roomId, String rootId) =>
    '/_matrix/client/unstable/org.matrix.msc4306/rooms/${Uri.encodeComponent(roomId)}/thread/${Uri.encodeComponent(rootId)}/subscription';

const profileAboutKey = 'com.highlife.about';

String? parseProfileAbout(Map<String, dynamic> profile) {
  final value = profile[profileAboutKey];
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

final _httpUrl = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

String? firstHttpUrl(String body) {
  final match = _httpUrl.firstMatch(body);
  if (match == null) return null;
  return match.group(0)!.replaceFirst(RegExp(r'[),.;]+$'), '');
}

class UrlPreview {
  const UrlPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
  });

  final String url;
  final String? title;
  final String? description;
  final String? image;
}

UrlPreview? parseUrlPreview(Map<String, dynamic> payload, String fallbackUrl) {
  final title = payload['og:title'] as String?;
  final description = payload['og:description'] as String?;
  final image = payload['og:image'] as String?;
  final url = payload['og:url'] as String? ?? fallbackUrl;
  if ((title == null || title.isEmpty) &&
      (description == null || description.isEmpty) &&
      (image == null || image.isEmpty)) {
    return null;
  }
  return UrlPreview(
    url: url,
    title: title,
    description: description,
    image: image,
  );
}

bool slidingSyncSupported(Map<String, dynamic>? unstable) {
  if (unstable == null) return false;
  return unstable['org.matrix.simplified_msc3575'] == true ||
      unstable['org.matrix.msc4186'] == true ||
      unstable['org.matrix.msc3575'] == true;
}

class MscRoomSummary {
  const MscRoomSummary({
    required this.roomId,
    this.name,
    this.topic,
    this.avatarUrl,
    this.joinRule,
    this.numJoinedMembers,
  });

  final String roomId;
  final String? name;
  final String? topic;
  final String? avatarUrl;
  final String? joinRule;
  final int? numJoinedMembers;
}

MscRoomSummary parseRoomSummary(Map<String, dynamic> payload, String fallbackId) {
  return MscRoomSummary(
    roomId: payload['room_id'] as String? ?? fallbackId,
    name: payload['name'] as String?,
    topic: payload['topic'] as String?,
    avatarUrl: payload['avatar_url'] as String?,
    joinRule: payload['join_rule'] as String?,
    numJoinedMembers: switch (payload['num_joined_members']) {
      final int value => value,
      final num value => value.toInt(),
      _ => null,
    },
  );
}

bool isKnockJoinRule(String? joinRule) =>
    joinRule == 'knock' || joinRule == 'knock_restricted';

/// famedly `Client.request` prefixes `_matrix`, so strip it from spec paths.
String matrixApiAction(String path) {
  const prefix = '/_matrix';
  if (path.startsWith(prefix)) return path.substring(prefix.length);
  return path.startsWith('/') ? path : '/$path';
}

class SpecCommand {
  const SpecCommand({
    required this.name,
    this.aliases = const [],
    this.description,
    this.args = const [],
  });

  final String name;
  final List<String> aliases;
  final String? description;
  final List<String> args;
}

List<SpecCommand> parseCommandsState(Map<String, dynamic> content) {
  final nested = content[msc4332CommandsState];
  final source =
      nested is Map ? Map<String, dynamic>.from(nested) : content;
  final raw = source['commands'];
  if (raw is! List) return const [];
  final out = <SpecCommand>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final row = Map<String, dynamic>.from(item);
    final name = row['name'] as String? ?? '';
    if (name.isEmpty) continue;
    final aliases =
        (row['aliases'] as List?)?.whereType<String>().toList() ?? const [];
    var args = const <String>[];
    final rawArgs = row['args'];
    if (rawArgs is List) {
      args = rawArgs.whereType<String>().toList();
    } else if (rawArgs is String && rawArgs.isNotEmpty) {
      args = [rawArgs];
    }
    out.add(
      SpecCommand(
        name: name,
        aliases: aliases,
        description: row['description'] as String?,
        args: args,
      ),
    );
  }
  return out;
}

Map<String, Object?> defaultSlidingSyncRequest() => {
      'lists': {
        'all': {
          'ranges': [
            [0, 99],
          ],
          'sort': ['by_notification_level', 'by_recency'],
          'timeline_limit': 1,
        },
      },
    };

List<String> parseSlidingSyncRoomOrder(Map<String, dynamic> payload) {
  final lists = payload['lists'];
  if (lists is Map) {
    final all = lists['all'];
    if (all is Map) {
      final ops = all['ops'];
      if (ops is List) {
        final ids = <String>[];
        for (final op in ops) {
          if (op is! Map) continue;
          final roomIds = op['room_ids'];
          if (roomIds is List) {
            ids.addAll(roomIds.whereType<String>());
          }
        }
        if (ids.isNotEmpty) return ids;
      }
    }
  }
  final rooms = payload['rooms'];
  if (rooms is Map) {
    return rooms.keys.map((key) => key.toString()).toList();
  }
  return const [];
}

String matrixLoginQrPayload({
  required String homeserver,
  String? deviceId,
  String? userId,
}) {
  return Uri(
    scheme: 'matrix',
    host: 'login',
    queryParameters: {
      'hs_url': homeserver,
      if (deviceId != null && deviceId.isNotEmpty) 'device': deviceId,
      if (userId != null && userId.isNotEmpty) 'u': userId,
    },
  ).toString();
}
