import 'package:flutter/foundation.dart';

/// Google 官方公布的 Android 原生廣告測試單元 ID，只會出測試廣告。
const String kTestAdmobNativeUnitId = 'ca-app-pub-3940256099942544/2247696110';

/// 依建置模式決定原生廣告單元 ID：只有 release 且有注入值時才用注入值，否則一律用測試 ID。
String resolveNativeUnitId({required bool release, required String injected}) =>
    release && injected.isNotEmpty ? injected : kTestAdmobNativeUnitId;

/// 原生廣告單元 ID，建置時由 `--dart-define-from-file=secrets/ads_defines.json` 注入。
///
/// 不寫死在原始碼：專案開源，寫死的話任何人自行編譯都會用本專案的 AdMob 帳號播正式廣告，
/// 測試時的點擊會算成無效流量而有扣款或停權風險。未注入或非 release 時為官方測試 ID。
String get admobNativeUnitId => resolveNativeUnitId(
  release: kReleaseMode,
  injected: const String.fromEnvironment('ADMOB_NATIVE_UNIT_ID'),
);
