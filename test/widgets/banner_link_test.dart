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

  testWidgets('指定 cacheHeight 為 height × devicePixelRatio', (tester) async {
    // 用一個明確的 dpr 確保斷言可預期；MediaQuery 預設 dpr=1.0。
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2.0),
          child: const Scaffold(
            body: BannerLink(
              assetPath: 'assets/banners/gonetone_banner.png',
              url: 'https://example.test',
              semanticLabel: 'test banner',
              height: 64,
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    // height=64, dpr=2.0 → cacheHeight=128
    expect(image, isA<Image>());
    expect(
      (image.image as ResizeImage).height,
      128,
      reason: 'cacheHeight 應為 height(64) × devicePixelRatio(2.0) = 128',
    );
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

    final mouseRegions = tester.widgetList<MouseRegion>(
      find.descendant(
        of: find.byType(BannerLink),
        matching: find.byType(MouseRegion),
      ),
    );
    expect(
      mouseRegions.any((r) => r.cursor == SystemMouseCursors.click),
      isTrue,
    );
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

  testWidgets('Tooltip 使用 semanticLabel 作為 message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: '旋風之音 GoneTone',
            height: 64,
          ),
        ),
      ),
    );

    expect(find.byTooltip('旋風之音 GoneTone'), findsOneWidget);
  });

  testWidgets('提供 Semantics button label 給螢幕閱讀器', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: '旋風之音 GoneTone',
            height: 64,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('旋風之音 GoneTone'), findsAtLeastNWidgets(1));

    handle.dispose();
  });

  testWidgets('BannerLink 內的 GestureDetector 有連上 onTap', (tester) async {
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

    final detector = tester.widget<GestureDetector>(
      find
          .descendant(
            of: find.byType(BannerLink),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(detector.onTap, isNotNull);
    expect(detector.behavior, HitTestBehavior.opaque);
  });

  testWidgets('點擊 BannerLink 不會丟例外', (tester) async {
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

    await tester.tap(find.byType(BannerLink), warnIfMissed: false);
    await tester.pumpAndSettle();
  });
}
