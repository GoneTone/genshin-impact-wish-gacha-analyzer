import 'package:flutter/gestures.dart';
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

  testWidgets('hover 時 cursor 為 SystemMouseCursors.click', (tester) async {
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

    final region = tester.widget<MouseRegion>(
      find
          .descendant(
            of: find.byType(BannerLink),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(region.cursor, SystemMouseCursors.click);
  });

  testWidgets('hover 時 AnimatedOpacity 變為 0.85,離開後變回 1.0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: Center(
            child: BannerLink(
              assetPath: 'assets/banners/gonetone_banner.png',
              url: 'https://example.test',
              semanticLabel: 'test banner',
              height: 64,
            ),
          ),
        ),
      ),
    );

    double readOpacity() {
      final ao = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      return ao.opacity;
    }

    expect(readOpacity(), 1.0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.byType(BannerLink)));
    await tester.pump();
    expect(readOpacity(), 0.85);

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(readOpacity(), 1.0);
  });
}
