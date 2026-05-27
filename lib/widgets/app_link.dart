import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

/// 連結預設色（primary）。
///
/// 與 [linkHoverColor] 一起構成全應用程式統一的連結色系；想在不同連結元件
/// 之間維持一致的 hover 體驗時，請呼叫這兩個 helper，不要自行決定 hover 色。
Color linkBaseColor(ThemeData theme) => theme.colorScheme.primary;

/// 連結 hover 色：往 onSurface 走 40%，提供明顯的對比變化。
///
/// 幅度刻意比 Material 預設 hover state layer 大，因為連結沒有 ripple／背景
/// 等其他回饋，全靠文字色變化告訴使用者「滑鼠停在連結上」。
Color linkHoverColor(ThemeData theme) =>
    Color.lerp(theme.colorScheme.primary, theme.colorScheme.onSurface, 0.4) ??
    theme.colorScheme.primary;

/// 可點擊的超連結 widget，以 primary 色繪製文字並在 hover 時加深對比。
class AppLink extends StatefulWidget {
  /// 建立 [AppLink]。[url] 必須是可解析的 URI 字串，[child] 為顯示內容。
  const AppLink({super.key, required this.url, required this.child});

  /// 點擊後開啟的目標 URL。
  final String url;

  /// 連結內容。
  final Widget child;

  @override
  State<AppLink> createState() => _AppLinkState();
}

/// [AppLink] 的 State：管理 hover 視覺與外部連結點擊。
class _AppLinkState extends State<AppLink> {
  /// 是否處於 hover 狀態。
  bool _hovering = false;

  /// 解析並開啟 [widget.url]；URL 無效時記錄 warning。
  Future<void> _handleTap() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      Logger('ui.link').warning('AppLink: invalid url "${widget.url}"');
      return;
    }
    await openExternalUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _hovering ? linkHoverColor(theme) : linkBaseColor(theme);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: color),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 以系統瀏覽器開啟 [uri]；無法啟動時記錄 warning 並靜默返回。
Future<void> openExternalUrl(Uri uri) async {
  if (!await canLaunchUrl(uri)) {
    Logger('ui.link').warning('openExternalUrl: cannot launch $uri');
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
