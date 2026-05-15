import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

class BannerLink extends StatefulWidget {
  const BannerLink({
    super.key,
    required this.assetPath,
    required this.url,
    required this.semanticLabel,
    required this.height,
  });

  final String assetPath;
  final String url;
  final String semanticLabel;
  final double height;

  @override
  State<BannerLink> createState() => _BannerLinkState();
}

class _BannerLinkState extends State<BannerLink> {
  bool _hovering = false;

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
