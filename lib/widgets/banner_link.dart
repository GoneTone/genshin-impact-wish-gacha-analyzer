import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

/// 可點擊的卡池 banner 圖片，hover 時降低透明度、點擊後以系統瀏覽器開啟 URL。
class BannerLink extends StatefulWidget {
  /// 建立 [BannerLink]。
  const BannerLink({
    super.key,
    required this.assetPath,
    required this.url,
    required this.semanticLabel,
    required this.height,
  });

  /// asset 路徑，對應 `Image.asset` 的 `assetPath` 參數。
  final String assetPath;

  /// 點擊後開啟的目標 URL。
  final String url;

  /// Tooltip 文字，同時作為 Semantics label。
  final String semanticLabel;

  /// 圖片高度（邏輯像素）。
  final double height;

  @override
  State<BannerLink> createState() => _BannerLinkState();
}

/// [BannerLink] 的 State：管理 hover 視覺。
class _BannerLinkState extends State<BannerLink> {
  /// 是否處於 hover 狀態。
  bool _hovering = false;

  /// 解析並開啟 [widget.url]；URL 無效時記錄 warning。
  Future<void> _handleTap() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      Logger('ui.link').warning('BannerLink: invalid url "${widget.url}"');
      return;
    }
    await openExternalUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Tooltip(
      message: widget.semanticLabel,
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: AnimatedOpacity(
              opacity: _hovering ? 0.85 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: Image.asset(
                widget.assetPath,
                height: widget.height,
                fit: BoxFit.contain,
                // 只設 cacheHeight，寬度按比例縮，避免 banner 變形。
                // 用 MediaQuery 的 dpr 而非寫死，正確支援高 DPI 螢幕。
                cacheHeight: (widget.height * dpr).round(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
