import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// UMP 同意資訊更新失敗時丟出的例外，帶 UMP 錯誤碼與訊息。
class AdsConsentException implements Exception {
  /// 建立例外，[code] 為 UMP 錯誤碼，[message] 為錯誤訊息。
  AdsConsentException(this.code, this.message);

  /// UMP 錯誤碼。
  final String code;

  /// UMP 錯誤訊息。
  final String message;

  @override
  String toString() => 'AdsConsentException(code=$code, message=$message)';
}

/// UMP 同意流程與 MobileAds SDK 的薄包裝，把 callback 轉成 [Future]；建構時不碰外掛，只有呼叫方法才會。
class AdsPlatform {
  /// 建立包裝。
  AdsPlatform();

  /// 向 UMP 更新同意資訊，失敗時丟 [AdsConsentException]。
  Future<void> requestConsentUpdate() {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      completer.complete,
      (error) => completer.completeError(
        AdsConsentException('${error.errorCode}', error.message),
      ),
    );
    return completer.future;
  }

  /// 需要時載入並顯示同意表單，表單錯誤時丟 [AdsConsentException]。
  Future<void> loadAndShowConsentFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(
          AdsConsentException('${error.errorCode}', error.message),
        );
      }
    });
    return completer.future;
  }

  /// 依目前同意狀態回傳是否可以請求廣告。
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  /// 是否必須提供隱私權選項入口（GDPR 等地區為 true）。
  Future<bool> isPrivacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  /// 顯示隱私權選項表單，表單錯誤時丟 [AdsConsentException]。
  Future<void> showPrivacyOptionsForm() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(
          AdsConsentException('${error.errorCode}', error.message),
        );
      }
    });
    return completer.future;
  }

  /// 初始化 MobileAds SDK，並限制廣告內容分級為 T（青少年）。
  Future<void> initializeSdk() async {
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(maxAdContentRating: MaxAdContentRating.t),
    );
  }
}
