import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

/// 可點擊的超連結 widget，以 primary 色繪製底線文字並在 hover 時加深。
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
    final baseColor = theme.colorScheme.primary;
    final hoverColor =
        Color.lerp(baseColor, theme.colorScheme.onSurface, 0.15) ?? baseColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: _hovering ? hoverColor : baseColor,
            decoration: TextDecoration.underline,
          ),
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
