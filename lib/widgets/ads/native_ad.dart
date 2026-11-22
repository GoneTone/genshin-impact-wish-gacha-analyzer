import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/ads/ad_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 小型模板外框的固定高度（dp）。
const double kNativeSmallHeight = 100;

/// 中型模板外框的固定高度（dp）：官方中型模板版面固定 350dp，多留一點避免橫向時切到底部留白。
const double kNativeMediumHeight = 355;

/// 原生模板的最小寬度（dp）：可用寬度不足時不顯示廣告。
const double kNativeMinWidth = 320;

/// 原生廣告的顯示位置。
enum NativeAdPlacement {
  /// 卡池頁記錄列表中。
  bannerList,

  /// 卡池頁段落之間。
  bannerMid,

  /// 總覽頁祈願段與頌願段之間。
  overviewGacha,

  /// 總覽頁頌願段之後。
  overviewOdes;

  /// 此位置使用的模板：列表內用小型，其他用中型。
  TemplateType get template =>
      this == bannerList ? TemplateType.small : TemplateType.medium;
}

/// 載入好的原生廣告：可顯示的 [view] 與釋放原生廣告的 [dispose]。
typedef LoadedNative = ({Widget view, VoidCallback dispose});

/// 依位置與深淺色載入原生廣告；失敗回傳 null。
typedef NativeAdLoader =
    Future<LoadedNative?> Function(
      NativeAdPlacement placement,
      Brightness brightness,
    );

/// 一則原生廣告的識別：位置、所屬範圍（例如卡池）與深淺色。
typedef NativeAdKey = ({
  NativeAdPlacement placement,
  String scope,
  Brightness brightness,
});

/// 廣告相關 log。
final _log = Logger('ads');

/// 依 [brightness] 的 App 色票組出 [type] 模板的樣式。
NativeTemplateStyle nativeTemplateStyleFor(
  TemplateType type,
  Brightness brightness,
) {
  final dark = brightness == Brightness.dark;
  final tokens = dark ? GachaTokens.dark : GachaTokens.light;
  final scheme = (dark ? buildDarkTheme() : buildLightTheme()).colorScheme;
  return NativeTemplateStyle(
    templateType: type,
    mainBackgroundColor: tokens.surfaceCard,
    cornerRadius: AppRadius.md,
    callToActionTextStyle: NativeTemplateTextStyle(
      textColor: scheme.onPrimary,
      backgroundColor: tokens.accentPrimary,
      style: NativeTemplateFontStyle.bold,
      size: 14,
    ),
    primaryTextStyle: NativeTemplateTextStyle(
      textColor: tokens.textPrimary,
      backgroundColor: tokens.surfaceCard,
      style: NativeTemplateFontStyle.bold,
      size: 14,
    ),
    secondaryTextStyle: NativeTemplateTextStyle(
      textColor: tokens.textSecondary,
      backgroundColor: tokens.surfaceCard,
      style: NativeTemplateFontStyle.normal,
      size: 12,
    ),
    tertiaryTextStyle: NativeTemplateTextStyle(
      textColor: tokens.textMuted,
      backgroundColor: tokens.surfaceCard,
      style: NativeTemplateFontStyle.normal,
      size: 12,
    ),
  );
}

/// 正式的原生廣告載入器：以 AdMob 原生模板載入，測試以 override 換成假實作。
final nativeAdLoaderProvider = Provider<NativeAdLoader>(
  (ref) => (placement, brightness) async {
    final result = Completer<LoadedNative?>();
    final ad = NativeAd(
      adUnitId: admobNativeUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: nativeTemplateStyleFor(
        placement.template,
        brightness,
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (result.isCompleted) return;
          _log.info('native loaded placement=${placement.name}');
          result.complete((
            view: AdWidget(ad: ad as AdWithView),
            dispose: ad.dispose,
          ));
        },
        onAdFailedToLoad: (ad, error) {
          if (result.isCompleted) return;
          _log.warning(
            'native failed placement=${placement.name} '
            'code=${error.code} message=${error.message}',
          );
          ad.dispose();
          result.complete(null);
        },
      ),
    );
    try {
      await ad.load();
    } catch (_) {
      unawaited(ad.dispose());
      rethrow;
    }
    return result.future;
  },
);

/// 每個 [NativeAdKey] 最多載入一次的原生廣告；沒有人監聽時釋放，失敗為 null 且不重試。
final nativeAdProvider = FutureProvider.autoDispose
    .family<LoadedNative?, NativeAdKey>((ref, key) async {
      final load = ref.read(nativeAdLoaderProvider);
      final placement = key.placement.name;
      LoadedNative? shown;
      ref.onDispose(() {
        final ad = shown;
        if (ad == null) return;
        // 舊的 AdWidget 這一幀可能還在畫面上，先釋放會變成紅色錯誤框；
        // 畫面靜止時不會有下一幀，要主動排一幀，否則廣告一直不被釋放。
        WidgetsBinding.instance
          ..addPostFrameCallback((_) {
            ad.dispose();
            _log.info('native disposed placement=$placement');
          })
          ..ensureVisualUpdate();
      });
      LoadedNative? ad;
      try {
        ad = await load(key.placement, key.brightness);
      } catch (e, st) {
        // 例外若外洩，Riverpod 會自動重試；當成載入失敗。
        _log.severe('native load threw placement=$placement', e, st);
        return null;
      }
      if (!ref.mounted) {
        if (ad != null) {
          ad.dispose();
          _log.info('native disposed placement=$placement');
        }
        return null;
      }
      return shown = ad;
    });

/// 顯示一則已載入的原生廣告：寬度上限 400dp 並置中，可用寬度不足 320dp 時不顯示。
class NativeAdBlock extends StatelessWidget {
  /// 建立 [placement] 位置的 [ad] 外框。
  const NativeAdBlock({super.key, required this.ad, required this.placement});

  /// 要顯示的廣告。
  final LoadedNative ad;

  /// 廣告位置，決定外框高度。
  final NativeAdPlacement placement;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kNativeMinWidth) {
          return const SizedBox.shrink();
        }
        return Center(
          heightFactor: 1,
          child: Container(
            width: math.min(constraints.maxWidth, 400),
            height: placement.template == TemplateType.small
                ? kNativeSmallHeight
                : kNativeMediumHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: tokens.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            // 邊線畫在前景：放在 decoration 會內縮 1dp，模板就小於官方最小寬度 320。
            // 列表中的廣告是列表外框裡的一列，不再自帶邊框。
            foregroundDecoration: placement == NativeAdPlacement.bannerList
                ? null
                : BoxDecoration(
                    border: Border.all(color: tokens.borderSubtle),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
            child: ad.view,
          ),
        );
      },
    );
  }
}
