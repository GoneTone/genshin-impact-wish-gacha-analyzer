import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/ads.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/ads/native_ad.dart';

/// 原生廣告頁面測試的帳號。
const fakeNativeAdUid = '801000000';

/// 狀態固定為 [banners] 的 repository 替身，不做 bootstrap 與 I/O。
class FixedGachaRepository extends GachaRepository {
  /// 建立替身；[bootstrapping] 時維持啟動載入中。
  FixedGachaRepository(this.banners, {this.bootstrapping = false});

  /// 各卡池的記錄。
  final Map<String, List<GachaRecord>> banners;

  /// 是否維持啟動載入中。
  final bool bootstrapping;

  @override
  GachaState build() => _stateOf(banners);

  /// 以 [banners] 取代目前帳號的記錄（對頁面而言等同切到另一個帳號）。
  void setBanners(Map<String, List<GachaRecord>> banners) =>
      state = _stateOf(banners);

  /// 以 [banners] 組出狀態。
  GachaState _stateOf(Map<String, List<GachaRecord>> banners) => GachaState(
    activeUid: fakeNativeAdUid,
    byUid: {
      fakeNativeAdUid: BannerStorage(
        uid: fakeNativeAdUid,
        lastUpdated: DateTime.utc(2026, 5, 1),
        banners: banners,
      ),
    },
    isBootstrapping: bootstrapping,
  );
}

/// 永遠回傳空 index、不讀磁碟的 HoYoWiki index 替身，避免頁面測試出現載入失敗的警告。
class EmptyHoYoWikiIndex extends HoYoWikiIndexNotifier {
  @override
  HoYoWikiIndex build() => const HoYoWikiIndex.empty();
}

/// 不碰原生 SDK、可由測試切換「可請求廣告」的廣告控制器替身。
class FakeAdsController extends AdsController {
  /// 建立替身，[initial] 為初始的「可請求廣告」旗標。
  FakeAdsController(this.initial);

  /// 初始的「可請求廣告」旗標。
  final bool initial;

  @override
  AdsState build() => AdsState(canRequestAds: initial);

  /// 模擬同意流程／SDK 初始化完成後改變「可請求廣告」。
  set canRequestAds(bool value) => state = AdsState(canRequestAds: value);
}

/// 一則假原生廣告的載入記錄。
class FakeNativeAd {
  /// 建立記錄。
  FakeNativeAd(this.placement, this.brightness, this.key);

  /// 載入的位置。
  final NativeAdPlacement placement;

  /// 載入時的深淺色。
  final Brightness brightness;

  /// 假 view 的 key。
  final Key key;

  /// 是否已被 dispose。
  bool disposed = false;

  /// dispose 當下假 view 是否還掛在畫面上。
  bool disposedWhileMounted = false;

  /// 是否在某一幀的 post-frame 階段才 dispose（而非 provider 釋放當下）。
  bool disposedAfterFrame = false;
}

/// 記錄每次載入的假原生廣告載入器，以 `nativeAdLoaderProvider.overrideWithValue(loader.call)` 使用。
class FakeNativeAdLoader {
  /// 建立假載入器；[fail] 時一律回傳 null。
  FakeNativeAdLoader({this.fail = false});

  /// 是否模擬載入失敗。
  final bool fail;

  /// 每次載入的記錄。
  final loads = <FakeNativeAd>[];

  /// [placement] 被載入的次數。
  int calls(NativeAdPlacement placement) =>
      loads.where((a) => a.placement == placement).length;

  /// 回傳帶唯一 key（`native-<位置>-<序號>`）的假廣告，或在 [fail] 時回傳 null。
  Future<LoadedNative?> call(
    NativeAdPlacement placement,
    Brightness brightness,
  ) async {
    final ad = FakeNativeAd(
      placement,
      brightness,
      ValueKey('native-${placement.name}-${loads.length}'),
    );
    loads.add(ad);
    if (fail) return null;
    return (
      view: SizedBox(key: ad.key),
      dispose: () {
        ad.disposed = true;
        ad.disposedWhileMounted = find.byKey(ad.key).evaluate().isNotEmpty;
        ad.disposedAfterFrame =
            SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.postFrameCallbacks;
      },
    );
  }
}

/// 畫面上任何一則假原生廣告的 view。
final anyFakeNativeView = find.byWidgetPredicate(
  (w) => w.key is ValueKey<String> && '${w.key}'.contains('native-'),
);

/// 目前顯示的 [placement] 假 view；[skipOffstage] 為 false 時也找畫面外已建構的。
Finder fakeNativeViewOf(
  NativeAdPlacement placement, {
  bool skipOffstage = true,
}) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      '${w.key}'.contains('native-${placement.name}-'),
  skipOffstage: skipOffstage,
);
