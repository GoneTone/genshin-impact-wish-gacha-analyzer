import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/ads/native_ad.dart';

/// 記錄呼叫與 dispose 次數的假原生廣告載入器。
class _FakeLoader {
  /// 建立假載入器；[result] 決定回傳廣告、null 或丟例外。
  _FakeLoader({this.result = _Result.ad});

  /// 模擬的載入結果。
  final _Result result;

  /// 被呼叫的次數。
  int calls = 0;

  /// 假廣告被 dispose 的次數。
  int disposes = 0;

  /// 非 null 時載入等它完成才回傳，用來模擬尚未載完。
  Completer<void>? gate;

  /// 依 [result] 回傳假廣告、null 或丟例外。
  Future<LoadedNative?> call(
    NativeAdPlacement placement,
    Brightness brightness,
  ) async {
    calls++;
    final pending = gate;
    if (pending != null) await pending.future;
    switch (result) {
      case _Result.ad:
        return (view: const SizedBox(), dispose: () => disposes++);
      case _Result.none:
        return null;
      case _Result.error:
        throw Exception('platform');
    }
  }
}

/// [_FakeLoader] 的載入結果種類。
enum _Result {
  /// 回傳假廣告。
  ad,

  /// 回傳 null（載入失敗）。
  none,

  /// 丟出平台例外。
  error,
}

/// 測試用的廣告位 key。
const NativeAdKey _key = (
  placement: NativeAdPlacement.overviewGacha,
  scope: 'overview',
  brightness: Brightness.dark,
);

void main() {
  group('NativeAdPlacement.template', () {
    test('列表位用小型模板，其他用中型', () {
      expect(NativeAdPlacement.bannerList.template, TemplateType.small);
      expect(NativeAdPlacement.bannerMid.template, TemplateType.medium);
      expect(NativeAdPlacement.overviewGacha.template, TemplateType.medium);
      expect(NativeAdPlacement.overviewOdes.template, TemplateType.medium);
    });
  });

  group('nativeTemplateStyleFor', () {
    for (final (brightness, tokens, theme) in [
      (Brightness.dark, GachaTokens.dark, buildDarkTheme()),
      (Brightness.light, GachaTokens.light, buildLightTheme()),
    ]) {
      test('套用 $brightness 的色票', () {
        final style = nativeTemplateStyleFor(TemplateType.medium, brightness);
        expect(style.templateType, TemplateType.medium);
        expect(style.mainBackgroundColor, tokens.surfaceCard);
        expect(style.cornerRadius, AppRadius.md);

        final cta = style.callToActionTextStyle!;
        expect(cta.backgroundColor, tokens.accentPrimary);
        expect(cta.textColor, theme.colorScheme.onPrimary);
        expect(cta.style, NativeTemplateFontStyle.bold);
        expect(cta.size, 14);

        final primary = style.primaryTextStyle!;
        expect(primary.textColor, tokens.textPrimary);
        expect(primary.backgroundColor, tokens.surfaceCard);
        expect(primary.style, NativeTemplateFontStyle.bold);
        expect(primary.size, 14);

        final secondary = style.secondaryTextStyle!;
        expect(secondary.textColor, tokens.textSecondary);
        expect(secondary.backgroundColor, tokens.surfaceCard);
        expect(secondary.style, NativeTemplateFontStyle.normal);
        expect(secondary.size, 12);

        final tertiary = style.tertiaryTextStyle!;
        expect(tertiary.textColor, tokens.textMuted);
        expect(tertiary.backgroundColor, tokens.surfaceCard);
        expect(tertiary.style, NativeTemplateFontStyle.normal);
        expect(tertiary.size, 12);
      });
    }
  });

  group('NativeAdBlock', () {
    const viewKey = Key('fake-native');

    /// 在 [width] 寬的父層中呈現 [placement] 的 [NativeAdBlock]。
    Future<void> pump(
      WidgetTester tester,
      double width,
      NativeAdPlacement placement,
    ) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NativeAdBlock(
                    key: const Key('block'),
                    ad: (
                      view: const SizedBox.expand(key: viewKey),
                      dispose: () {},
                    ),
                    placement: placement,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    /// 包住假廣告的外框。
    Finder frame() => find
        .ancestor(of: find.byKey(viewKey), matching: find.byType(Container))
        .first;

    testWidgets('可用寬度 319 不顯示', (tester) async {
      await pump(tester, 319, NativeAdPlacement.bannerList);
      expect(find.byKey(viewKey), findsNothing);
      expect(tester.getSize(find.byKey(const Key('block'))).height, 0);
    });

    testWidgets('可用寬度 320 顯示小型', (tester) async {
      await pump(tester, 320, NativeAdPlacement.bannerList);
      expect(find.byKey(viewKey), findsOneWidget);
      expect(tester.getSize(frame()), const Size(320, kNativeSmallHeight));
      // 外框的邊線不能吃掉內容寬度，否則模板會小於官方最小寬度 320。
      expect(
        tester.getSize(find.byKey(viewKey)),
        const Size(320, kNativeSmallHeight),
      );
      // 列表中的小型廣告是列表外框裡的一列，不自帶邊框。
      expect(tester.widget<Container>(frame()).foregroundDecoration, isNull);
      final decoration =
          tester.widget<Container>(frame()).decoration! as BoxDecoration;
      expect(decoration.color, GachaTokens.dark.surfaceCard);
    });

    testWidgets('寬螢幕上限 400 並置中，中型高度', (tester) async {
      await pump(tester, 600, NativeAdPlacement.overviewGacha);
      expect(
        tester.widget<Container>(frame()).foregroundDecoration,
        isA<BoxDecoration>(),
      );
      expect(
        kNativeMediumHeight,
        greaterThanOrEqualTo(350),
        reason: '官方中型模板版面固定 350dp 高',
      );
      expect(tester.getSize(frame()), const Size(400, kNativeMediumHeight));
      expect(
        tester.getSize(find.byKey(viewKey)),
        const Size(400, kNativeMediumHeight),
      );
      expect(tester.getCenter(frame()).dx, 300);
      expect(
        tester.getSize(find.byKey(const Key('block'))).height,
        kNativeMediumHeight,
      );
    });
  });

  group('nativeAdProvider', () {
    /// 以 [loader] 取代正式載入器的 container，測試結束自動釋放。
    ProviderContainer containerWith(_FakeLoader loader) {
      final container = ProviderContainer(
        overrides: [nativeAdLoaderProvider.overrideWithValue(loader.call)],
      );
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('同一個 key 只載入一次', (tester) async {
      final loader = _FakeLoader();
      final container = containerWith(loader);
      container.listen(nativeAdProvider(_key), (_, _) {});
      expect(await container.read(nativeAdProvider(_key).future), isNotNull);
      expect(await container.read(nativeAdProvider(_key).future), isNotNull);
      expect(loader.calls, 1);
    });

    testWidgets('provider 釋放後等下一幀才釋放廣告', (tester) async {
      final loader = _FakeLoader();
      final container = containerWith(loader);
      container.listen(nativeAdProvider(_key), (_, _) {});
      await container.read(nativeAdProvider(_key).future);
      container.dispose();
      // 舊的 AdWidget 這一幀可能還在畫面上，提早釋放會變成紅色錯誤框。
      expect(loader.disposes, 0);
      await tester.pump();
      expect(loader.disposes, 1);
    });

    testWidgets('provider 釋放後才載入完成的廣告立刻釋放', (tester) async {
      final loader = _FakeLoader()..gate = Completer<void>();
      final container = containerWith(loader);
      container.listen(nativeAdProvider(_key), (_, _) {});
      container.dispose();
      loader.gate!.complete();
      await tester.idle();
      expect(loader.disposes, 1);
      await tester.pump();
      expect(loader.disposes, 1);
    });

    testWidgets('載入失敗時為 null', (tester) async {
      final loader = _FakeLoader(result: _Result.none);
      final container = containerWith(loader);
      container.listen(nativeAdProvider(_key), (_, _) {});
      expect(await container.read(nativeAdProvider(_key).future), isNull);
    });

    testWidgets('載入器丟例外時為 null 且不重試', (tester) async {
      final loader = _FakeLoader(result: _Result.error);
      final container = containerWith(loader);
      container.listen(nativeAdProvider(_key), (_, _) {});
      expect(await container.read(nativeAdProvider(_key).future), isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(loader.calls, 1);
    });
  });
}
