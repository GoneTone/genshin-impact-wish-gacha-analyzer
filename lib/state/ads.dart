import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/ads/ads_platform.dart';

/// UMP／MobileAds 的平台包裝，測試以 override 換成假實作。
final adsPlatformProvider = Provider<AdsPlatform>((ref) => AdsPlatform());

/// 廣告狀態：是否可請求廣告、是否需提供隱私權選項入口。
class AdsState {
  /// 建立狀態，預設皆為 false。
  const AdsState({
    this.canRequestAds = false,
    this.privacyOptionsRequired = false,
  });

  /// 同意流程完成後是否可以請求廣告。
  final bool canRequestAds;

  /// 是否必須提供隱私權選項入口。
  final bool privacyOptionsRequired;
}

/// 負責同意流程與 SDK 初始化的控制器。
class AdsController extends Notifier<AdsState> {
  /// 廣告相關 log。
  static final _log = Logger('ads');

  /// [start] 是否已執行過。
  bool _started = false;

  /// MobileAds SDK 的初始化；同一個 session 只初始化一次，失敗時清空以便重試。
  Future<void>? _sdkInit;

  @override
  AdsState build() => const AdsState();

  /// 依序更新同意資訊、必要時顯示表單、初始化 SDK；只會執行一次。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final platform = ref.read(adsPlatformProvider);
    try {
      await platform.requestConsentUpdate();
      try {
        await platform.loadAndShowConsentFormIfRequired();
      } on AdsConsentException catch (e) {
        _log.warning('consent form error code=${e.code} message=${e.message}');
      }
    } on AdsConsentException catch (e) {
      // 更新失敗仍沿用上次同意結果（UMP 官方建議），所以不 return。
      _log.warning('consent update failed code=${e.code} message=${e.message}');
    } catch (e, st) {
      // 同樣沿用上次同意結果，交給 _enableIfAllowed 判斷。
      _log.severe('ads consent failed', e, st);
    }
    try {
      await _enableIfAllowed(platform);
    } catch (e, st) {
      // 非同意例外（如 PlatformException）不能變成未處理錯誤；狀態維持預設＝廣告關閉。
      _log.severe('ads start failed', e, st);
    }
  }

  /// 顯示隱私權選項表單，關閉後重讀兩個旗標；表單中才同意時補初始化 SDK。
  Future<void> showPrivacyOptions() async {
    final platform = ref.read(adsPlatformProvider);
    try {
      try {
        await platform.showPrivacyOptionsForm();
      } on AdsConsentException catch (e) {
        _log.warning(
          'privacy options form error code=${e.code} message=${e.message}',
        );
      }
      await _enableIfAllowed(platform);
    } catch (e, st) {
      // 呼叫端是設定頁的按鈕，平台例外不能往上丟。
      _log.severe('privacy options failed', e, st);
    }
  }

  /// 初始化 SDK 並讓併發呼叫共用同一次初始化；失敗時清空以便下次重試。
  Future<void> _initSdkOnce(AdsPlatform platform) {
    return _sdkInit ??= platform.initializeSdk().catchError((
      Object e,
      StackTrace st,
    ) {
      _sdkInit = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  /// 讀取同意結果寫入狀態；可請求廣告時先初始化 SDK，內容分級上限才會在載入前套用。
  Future<void> _enableIfAllowed(AdsPlatform platform) async {
    final canRequest = await platform.canRequestAds();
    if (canRequest) await _initSdkOnce(platform);
    final optionsRequired = await platform.isPrivacyOptionsRequired();
    if (!ref.mounted) return;
    state = AdsState(
      canRequestAds: canRequest,
      privacyOptionsRequired: optionsRequired,
    );
    _log.info(
      'ads consent resolved canRequestAds=$canRequest privacyOptionsRequired=$optionsRequired',
    );
  }
}

/// 廣告同意與初始化狀態。
final adsProvider = NotifierProvider<AdsController, AdsState>(
  AdsController.new,
);
