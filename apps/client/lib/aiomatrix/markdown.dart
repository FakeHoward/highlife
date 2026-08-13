import '../hl_kit.dart';
import 'package:url_launcher/url_launcher.dart';

/// Strip a small Markdown subset down to plain text (room-list previews).
String markdownToPlain(String source) {
  if (source.isEmpty) return '';
  return source
      .replaceAllMapped(RegExp(r'`([^`\n]+)`'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\*\*([^*\n]+)\*\*'), (m) => m[1]!)
      .replaceAllMapped(
        RegExp(r'(^|[\s(])\*([^*\n]+)\*(?=[\s).,!?:;]|$)'),
        (m) => '${m[1]}${m[2]}',
      )
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .trim();
}

final _code = RegExp(r'`([^`\n]+)`');
final _bold = RegExp(r'\*\*([^*\n]+)\*\*');
final _italic = RegExp(r'(^|[\s(])\*([^*\n]+)\*(?=[\s).,!?:;]|$)');
final _link = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');

/// Lightweight Markdown → [InlineSpan] for chat bodies (parity with web).
/// Supports: `code`, **bold**, *italic*, [label](url), paragraphs / line breaks.
List<InlineSpan> markdownToSpans(
  String source, {
  TextStyle? style,
  Color? linkColor,
  void Function(String url)? onLinkTap,
}) {
  if (source.isEmpty) return [TextSpan(text: '', style: style)];

  final blocks = source.split(RegExp(r'\n{2,}'));
  final spans = <InlineSpan>[];
  for (var b = 0; b < blocks.length; b++) {
    if (b > 0) spans.add(TextSpan(text: '\n\n', style: style));
    final lines = blocks[b].split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(TextSpan(text: '\n', style: style));
      spans.addAll(
        _parseInline(
          lines[i],
          style: style,
          linkColor: linkColor,
          onLinkTap: onLinkTap,
        ),
      );
    }
  }
  return spans;
}

List<InlineSpan> _parseInline(
  String text, {
  TextStyle? style,
  Color? linkColor,
  void Function(String url)? onLinkTap,
}) {
  if (text.isEmpty) return [TextSpan(text: '', style: style)];

  final spans = <InlineSpan>[];
  var cursor = 0;
  while (cursor < text.length) {
    final rest = text.substring(cursor);
    Match? earliest;
    var kind = '';
    var earliestAbs = text.length;

    void consider(String k, Match? m) {
      if (m == null) return;
      final abs = cursor + m.start;
      if (abs < earliestAbs) {
        earliestAbs = abs;
        earliest = m;
        kind = k;
      }
    }

    consider('code', _code.firstMatch(rest));
    consider('bold', _bold.firstMatch(rest));
    consider('link', _link.firstMatch(rest));
    consider('italic', _italic.firstMatch(rest));

    final match = earliest;
    if (match == null) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
      break;
    }

    final absStart = cursor + match.start;
    final absEnd = cursor + match.end;
    if (absStart > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, absStart), style: style));
    }

    switch (kind) {
      case 'code':
        spans.add(
          TextSpan(
            text: match.group(1),
            style: (style ?? const TextStyle()).copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0x14000000),
            ),
          ),
        );
      case 'bold':
        spans.addAll(
          _parseInline(
            match.group(1)!,
            style: (style ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w700,
            ),
            linkColor: linkColor,
            onLinkTap: onLinkTap,
          ),
        );
      case 'link':
        final label = match.group(1)!;
        final url = match.group(2)!;
        if (_isSafeHttpsUrl(url) && onLinkTap != null) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => onLinkTap(url),
                child: Text(
                  label,
                  style: (style ?? const TextStyle()).copyWith(
                    color: linkColor ?? const Color(0xFF1263D6),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          );
        } else {
          spans.add(TextSpan(text: label, style: style));
        }
      case 'italic':
        final lead = match.group(1) ?? '';
        if (lead.isNotEmpty) {
          spans.add(TextSpan(text: lead, style: style));
        }
        spans.addAll(
          _parseInline(
            match.group(2)!,
            style: (style ?? const TextStyle()).copyWith(
              fontStyle: FontStyle.italic,
            ),
            linkColor: linkColor,
            onLinkTap: onLinkTap,
          ),
        );
      default:
        spans.add(TextSpan(text: text.substring(cursor, absEnd), style: style));
    }
    cursor = absEnd;
  }
  return spans;
}

bool _isSafeHttpsUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'https' &&
      !(uri.scheme == 'http' &&
          (uri.host == 'localhost' || uri.host == '127.0.0.1'))) {
    return false;
  }
  return uri.host.isNotEmpty;
}

/// Selectable markdown body for chat bubbles.
class MarkdownMessage extends StatelessWidget {
  const MarkdownMessage({
    super.key,
    required this.source,
    this.style,
    this.selectable = true,
  });

  final String source;
  final TextStyle? style;
  final bool selectable;

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final span = TextSpan(
      style: base,
      children: markdownToSpans(
        source,
        style: base,
        linkColor: Theme.of(context).colorScheme.primary,
        onLinkTap: _openLink,
      ),
    );
    if (selectable) {
      return SelectableText.rich(span);
    }
    return Text.rich(span);
  }
}
