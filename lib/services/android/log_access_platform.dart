import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/genshin_game_package.dart';

/// Android 讀取系統記錄所需的系統功能（Kotlin `LogAccessChannel`）的 Dart 包裝。
///
/// 所有方法遇到平台錯誤或非 Android（沒有 plugin）都記 warning 並回保守值，不往外丟。
class LogAccessPlatform {
  /// 與 Kotlin 端約定的 channel 名稱。
  static const channelName = 'tw.reh.genshin.gacha/log_access';

  /// 平台 channel。
  static const _channel = MethodChannel(channelName);

  /// 本包裝的 logger。
  static final _log = Logger('capture.android');

  /// 呼叫 [method]，失敗時記 warning 並回 [fallback]。
  Future<T> _call<T>(String method, T fallback, [Object? args]) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method, args);
      return result is T ? result : fallback;
    } on PlatformException catch (e) {
      _log.warning('$method failed code=${e.code} message=${e.message}');
    } on MissingPluginException {
      _log.warning('$method unavailable: no platform implementation');
    }
    return fallback;
  }

  /// `Build.VERSION.SDK_INT`；取不到時回 0。
  Future<int> sdkInt() => _call('sdkInt', 0);

  /// 目前的網路是否為 Wi‑Fi。
  Future<bool> isWifiConnected() => _call('isWifiConnected', false);

  /// 開發人員選項是否已開啟。
  Future<bool> isDevelopmentSettingsEnabled() =>
      _call('isDevelopmentSettingsEnabled', false);

  /// 無線偵錯（`adb_wifi_enabled`）目前是否開啟。
  Future<bool> isAdbWifiEnabled() => _call('isAdbWifiEnabled', false);

  /// 開關無線偵錯；沒有 `WRITE_SECURE_SETTINGS` 時回 false。
  Future<bool> setAdbWifiEnabled(bool enabled) =>
      _call('setAdbWifiEnabled', false, {'enabled': enabled});

  /// 本 App 是否已被授予 `WRITE_SECURE_SETTINGS`。
  Future<bool> hasWriteSecureSettings() =>
      _call('hasWriteSecureSettings', false);

  /// 用 NSD 收集本機無線偵錯的連線埠（可能含已關閉的舊埠）。
  Future<List<int>> discoverAdbConnectPorts() async {
    final ports = await _call<List<Object?>>(
      'discoverAdbConnectPorts',
      const [],
    );
    return [for (final p in ports) p as int];
  }

  /// 開啟系統的「無線偵錯」頁（不支援時退回開發人員選項）。
  Future<void> openWirelessDebugging() =>
      _call<Object?>('openWirelessDebugging', null);

  /// 開啟開發人員選項。
  Future<void> openDeveloperOptions() =>
      _call<Object?>('openDeveloperOptions', null);

  /// 開啟「關於」頁面（連點版本號碼開啟開發人員選項用）。
  Future<void> openDeviceInfoSettings() =>
      _call<Object?>('openDeviceInfoSettings', null);

  /// 開啟本 App 的通知設定。
  Future<void> openAppNotificationSettings() =>
      _call<Object?>('openAppNotificationSettings', null);

  /// 本 App 的通知是否允許顯示。
  Future<bool> areNotificationsEnabled() =>
      _call('areNotificationsEnabled', false);

  /// 請求通知權限（Android 13 以上），回傳最終是否允許。
  Future<bool> requestNotificationPermission() =>
      _call('requestNotificationPermission', false);

  /// 裝置上安裝的國際服原神套件（已排序）；查詢失敗時回 null，與「沒有安裝」區分。
  Future<List<String>?> installedGamePackages() async {
    final found = await _call<List<Object?>?>('installedGames', null, {
      'prefix': genshinPackagePrefix,
      'known': knownGenshinPackages,
    });
    return found == null
        ? null
        : sortGenshinPackages(found.whereType<String>());
  }

  /// 開啟 [package] 版本的原神；沒有安裝時回 false。
  Future<bool> launchGame(String package) =>
      _call('launchGame', false, {'package': package});
}

/// 提供 [LogAccessPlatform]，測試可 override。
final logAccessPlatformProvider = Provider<LogAccessPlatform>(
  (ref) => LogAccessPlatform(),
);
