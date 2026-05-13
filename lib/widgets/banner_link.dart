import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.semanticLabel,
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: AnimatedOpacity(
            opacity: _hovering ? 0.85 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Image.asset(
              widget.assetPath,
              height: widget.height,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
