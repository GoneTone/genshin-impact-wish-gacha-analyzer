import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_link.dart';

void main() {
  testWidgets('渲染 Image 並套用指定 height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: 'test banner',
            height: 64,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.height, 64);
    expect(image.fit, BoxFit.contain);
  });
}
