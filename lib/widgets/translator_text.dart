import 'package:flutter/foundation.dart';

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
