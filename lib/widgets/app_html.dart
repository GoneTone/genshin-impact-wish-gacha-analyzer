import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'package:genshin_impact_wish_gacha_analyzer/utils/html_linkify.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

/// 渲染 HTML 的共用元件：自動把純文字 `http(s)` 網址轉成可點連結（含內容既有的
/// `<a href>`），點擊以系統瀏覽器開啟。
///
/// 連結採全應用統一的靜態 primary 連結色（[linkBaseColor]）+ 底線，對齊既有行內
/// 連結風格；不做 per-link hover。呼叫端可透過 [style] 覆蓋 `body`／`p` 等標籤樣式
/// （疊在預設 `a` 樣式之後）。
class AppHtml extends StatelessWidget {
  /// 建立 [AppHtml]。[data] 為 HTML 字串；[style] 為額外的 flutter_html 標籤樣式。
  const AppHtml({super.key, required this.data, this.style = const {}});

  /// 要渲染的 HTML 內容。
  final String data;

  /// 額外的標籤樣式覆寫（疊在預設 `a` 樣式之後）。
  final Map<String, Style> style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Html(
      data: linkifyHtml(data),
      onLinkTap: (url, _, _) => unawaited(openExternalUrlString(url)),
      style: {
        'a': Style(
          color: linkBaseColor(theme),
          textDecoration: TextDecoration.underline,
        ),
        ...style,
      },
    );
  }
}
