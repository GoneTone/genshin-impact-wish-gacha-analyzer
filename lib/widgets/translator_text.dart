import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 把 localeTranslator 字串拆成可渲染段落。
///
/// 只支援 `<a href="https://...">label</a>` 一種標籤；href 必須是
/// http / https 且能被 [Uri.tryParse] 解析。其他情境降為純文字。
@visibleForTesting
List<TranslatorSegment> parseTranslatorMarkup(String raw) {
  if (raw.isEmpty) return const [];

  final pattern = RegExp(r'<a\s+href="([^"]+)">([^<]+)</a>');
  final segments = <TranslatorSegment>[];
  var cursor = 0;

  for (final match in pattern.allMatches(raw)) {
    if (match.start > cursor) {
      segments.add(TextSegment(raw.substring(cursor, match.start)));
    }
    final href = match.group(1)!;
    final label = match.group(2)!;
    final uri = Uri.tryParse(href);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      segments.add(LinkSegment(label, uri));
    } else {
      debugPrint('TranslatorText: dropping invalid href "$href"');
      segments.add(TextSegment(label));
    }
    cursor = match.end;
  }

  if (cursor < raw.length) {
    segments.add(TextSegment(raw.substring(cursor)));
  }

  return segments;
}

sealed class TranslatorSegment {
  const TranslatorSegment();
}

class TextSegment extends TranslatorSegment {
  const TextSegment(this.text);
  final String text;
}

class LinkSegment extends TranslatorSegment {
  const LinkSegment(this.text, this.uri);
  final String text;
  final Uri uri;
}

/// 把帶有 `<a href>` 標籤的字串顯示為可點擊文字。
///
/// 僅用於設定頁 About 區塊的譯者署名。
class TranslatorText extends StatefulWidget {
  const TranslatorText({super.key, required this.raw, this.style});

  final String raw;
  final TextStyle? style;

  @override
  State<TranslatorText> createState() => _TranslatorTextState();
}

class _TranslatorTextState extends State<TranslatorText> {
  late List<TranslatorSegment> _segments;
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant TranslatorText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raw != widget.raw) {
      _disposeRecognizers();
      _rebuild();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _rebuild() {
    _segments = parseTranslatorMarkup(widget.raw);
    for (final seg in _segments) {
      if (seg is LinkSegment) {
        _recognizers.add(TapGestureRecognizer()..onTap = () => _open(seg.uri));
      }
    }
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri uri) async {
    if (!await canLaunchUrl(uri)) {
      debugPrint('TranslatorText: cannot launch $uri');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final linkColor = Theme.of(context).colorScheme.primary;

    var linkIndex = 0;
    return RichText(
      text: TextSpan(
        children: [
          for (final seg in _segments)
            if (seg is TextSegment)
              TextSpan(text: seg.text, style: baseStyle)
            else if (seg is LinkSegment)
              TextSpan(
                text: seg.text,
                style: baseStyle.copyWith(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                ),
                recognizer: _recognizers[linkIndex++],
              ),
        ],
      ),
    );
  }
}
