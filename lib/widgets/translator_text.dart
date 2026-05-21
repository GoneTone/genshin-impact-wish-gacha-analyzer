import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

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
      Logger(
        'ui.link',
      ).warning('TranslatorText: dropping invalid href "$href"');
      segments.add(TextSegment(label));
    }
    cursor = match.end;
  }

  if (cursor < raw.length) {
    segments.add(TextSegment(raw.substring(cursor)));
  }

  return segments;
}

/// [parseTranslatorMarkup] 拆出的文字或連結段落基底類型。
sealed class TranslatorSegment {
  /// 建立 [TranslatorSegment]。
  const TranslatorSegment();
}

/// 純文字段落。
class TextSegment extends TranslatorSegment {
  /// 建立 [TextSegment]。
  const TextSegment(this.text);

  /// 段落文字內容。
  final String text;
}

/// 可點擊連結段落。
class LinkSegment extends TranslatorSegment {
  /// 建立 [LinkSegment]。
  const LinkSegment(this.text, this.uri);

  /// 顯示文字。
  final String text;

  /// 連結目標 URI。
  final Uri uri;
}

/// 把帶有 `<a href>` 標籤的字串顯示為可點擊文字。
class TranslatorText extends StatefulWidget {
  /// 建立 [TranslatorText]。
  const TranslatorText({super.key, required this.raw, this.style});

  /// 含 `<a href>` 標籤的原始字串。
  final String raw;

  /// 套用於全段文字的基礎樣式（可選）。
  final TextStyle? style;

  @override
  State<TranslatorText> createState() => _TranslatorTextState();
}

/// [TranslatorText] 的 State：解析 segment 並管理連結 [TapGestureRecognizer] 生命週期。
class _TranslatorTextState extends State<TranslatorText> {
  /// 當前 [widget.raw] 解析出的段落列表。
  late List<TranslatorSegment> _segments;

  /// 各 [LinkSegment] 對應的手勢辨識器，與 [_segments] 的連結型段落一一對應。
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

  /// 重新解析 [widget.raw] 並為 [LinkSegment] 建立手勢辨識器。
  void _rebuild() {
    _segments = parseTranslatorMarkup(widget.raw);
    for (final seg in _segments) {
      if (seg is LinkSegment) {
        _recognizers.add(
          TapGestureRecognizer()..onTap = () => openExternalUrl(seg.uri),
        );
      }
    }
  }

  /// 釋放所有 [TapGestureRecognizer] 並清空列表。
  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final linkColor = Theme.of(context).colorScheme.primary;

    var linkIndex = 0;
    return Text.rich(
      TextSpan(
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
                mouseCursor: SystemMouseCursors.click,
                recognizer: _recognizers[linkIndex++],
              ),
        ],
      ),
    );
  }
}
