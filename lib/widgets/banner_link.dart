import 'package:flutter/material.dart';

class BannerLink extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Image.asset(assetPath, height: height, fit: BoxFit.contain);
  }
}
