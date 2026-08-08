import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/aiomatrix/markdown.dart';

void main() {
  test('markdownToPlain strips markers like the web client', () {
    expect(
      markdownToPlain('**FormSpace** — try `/start`'),
      'FormSpace — try /start',
    );
    expect(markdownToPlain('say *hi* now'), 'say hi now');
    expect(markdownToPlain('[docs](https://example.com/x)'), 'docs');
  });

  test('markdownToSpans renders bold, italic, code and paragraphs', () {
    final spans = markdownToSpans('**FormSpace** — try `/start`\n\nnext');
    final flat = _flatten(spans);
    expect(flat, contains('FormSpace'));
    expect(flat, contains('/start'));
    expect(flat, contains('next'));
    expect(flat, contains('\n\n'));

    final bold = _findStyle(spans, (s) => s?.fontWeight == FontWeight.w700);
    expect(bold, isNotNull);

    final code = _findStyle(spans, (s) => s?.fontFamily == 'monospace');
    expect(code, isNotNull);

    final italicSpans = markdownToSpans('say *hi* now');
    final italic = _findStyle(
      italicSpans,
      (s) => s?.fontStyle == FontStyle.italic,
    );
    expect(italic, isNotNull);
  });

  test('markdownToSpans builds tappable https links', () {
    String? opened;
    final spans = markdownToSpans(
      'see [docs](https://example.com/x)',
      onLinkTap: (url) => opened = url,
    );
    final link = _findWidget(spans);
    expect(link, isNotNull);
    (link as GestureDetector).onTap?.call();
    expect(opened, 'https://example.com/x');
  });
}

String _flatten(List<InlineSpan> spans) {
  final buf = StringBuffer();
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null) buf.write(span.text);
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    } else if (span is WidgetSpan) {
      final child = span.child;
      if (child is GestureDetector) {
        final text = child.child;
        if (text is Text) buf.write(text.data);
      }
    }
  }

  for (final span in spans) {
    walk(span);
  }
  return buf.toString();
}

TextStyle? _findStyle(
  List<InlineSpan> spans,
  bool Function(TextStyle?) match,
) {
  TextStyle? found;
  void walk(InlineSpan span) {
    if (found != null) return;
    if (span is TextSpan) {
      if (match(span.style)) {
        found = span.style;
        return;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  for (final span in spans) {
    walk(span);
  }
  return found;
}

Widget? _findWidget(List<InlineSpan> spans) {
  Widget? found;
  void walk(InlineSpan span) {
    if (found != null) return;
    if (span is WidgetSpan) {
      found = span.child;
      return;
    }
    if (span is TextSpan) {
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  for (final span in spans) {
    walk(span);
  }
  return found;
}
