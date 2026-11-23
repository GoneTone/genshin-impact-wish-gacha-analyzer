import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:logging/logging.dart';

/// Play 回報的更新資訊。
class PlayUpdateInfo {
  /// 建立 [PlayUpdateInfo]。
  const PlayUpdateInfo({
    required this.updateAvailability,
    required this.availableVersionCode,
    required this.flexibleAllowed,
    this.installStatus = InstallStatus.unknown,
  });

  /// Play 回報的更新可用性。
  final UpdateAvailability updateAvailability;

  /// Play 上新版的 versionCode；無新版時可能為 null。
  final int? availableVersionCode;

  /// 此次更新是否允許彈性（背景下載）更新。
  final bool flexibleAllowed;

  /// 更新的下載／安裝進度。
  final InstallStatus installStatus;

  /// 是否有 App 該處理的新版；之前已開始的更新（下載中或已下載完）也算。
  bool get available =>
      updateAvailability == UpdateAvailability.updateAvailable ||
      updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress;

  /// 更新是否已下載完、只差重新啟動安裝。
  bool get downloaded => installStatus == InstallStatus.downloaded;

  /// 更新是否正在排隊或下載中。
  bool get downloading =>
      installStatus == InstallStatus.pending ||
      installStatus == InstallStatus.downloading;
}

/// 彈性更新下載的結果。
enum PlayDownloadResult {
  /// 下載完成，可呼叫 [PlayUpdateGateway.completeFlexible] 安裝。
  downloaded,

  /// 使用者拒絕更新。
  denied,

  /// 下載或啟動更新失敗。
  failed,
}

/// in_app_update 的最小介面（測試替換用）。
abstract class PlayUpdateGateway {
  /// 查詢 Play 是否有新版；不是從 Play 安裝等狀況會拋例外。
  Future<PlayUpdateInfo> check();

  /// 開始彈性更新，下載完成才回傳；呼叫前須先在同一個 process 呼叫過 [check]。
  Future<PlayDownloadResult> downloadFlexible();

  /// 安裝已下載的更新（App 會重新啟動）。
  Future<void> completeFlexible();
}

/// 以 `in_app_update` 套件實作的 [PlayUpdateGateway]。
class InAppUpdatePlayGateway implements PlayUpdateGateway {
  /// 此類別的 logger。
  static final _log = Logger('release');

  @override
  Future<PlayUpdateInfo> check() async {
    final info = await InAppUpdate.checkForUpdate();
    return PlayUpdateInfo(
      updateAvailability: info.updateAvailability,
      availableVersionCode: info.availableVersionCode,
      flexibleAllowed: info.flexibleUpdateAllowed,
      installStatus: info.installStatus,
    );
  }

  @override
  Future<PlayDownloadResult> downloadFlexible() async {
    // 從通知列取消下載等狀況下 plugin 的 startFlexibleUpdate 永遠不回覆，
    // 所以同時看進度事件，先到先用。
    final fromStatus = Completer<PlayDownloadResult>();
    final sub = InAppUpdate.installUpdateListener.listen(
      (status) {
        final result = switch (status) {
          InstallStatus.downloaded => PlayDownloadResult.downloaded,
          // 使用者取消（同意對話框或通知列）屬於使用者的選擇，不提示改到 Play 更新。
          InstallStatus.canceled => PlayDownloadResult.denied,
          InstallStatus.failed => PlayDownloadResult.failed,
          _ => null,
        };
        if (result == null || fromStatus.isCompleted) return;
        _log.info(
          'play flexible update ended by install status=${status.name}',
        );
        fromStatus.complete(result);
      },
      // 事件串流出錯時仍以 startFlexibleUpdate 的回覆為準，不誤判成失敗。
      onError: (Object e, StackTrace st) =>
          _log.warning('play install status stream error', e, st),
    );
    try {
      return await Future.any([_startFlexible(), fromStatus.future]);
    } finally {
      await sub.cancel();
    }
  }

  /// 呼叫 plugin 開始彈性更新，並把回覆轉成 [PlayDownloadResult]。
  static Future<PlayDownloadResult> _startFlexible() async {
    try {
      return switch (await InAppUpdate.startFlexibleUpdate()) {
        AppUpdateResult.success => PlayDownloadResult.downloaded,
        AppUpdateResult.userDeniedUpdate => PlayDownloadResult.denied,
        AppUpdateResult.inAppUpdateFailed => PlayDownloadResult.failed,
      };
    } on PlatformException {
      return PlayDownloadResult.failed;
    }
  }

  @override
  Future<void> completeFlexible() => InAppUpdate.completeFlexibleUpdate();
}

/// [PlayUpdateGateway] 的 provider；測試 override 成 fake。
final playUpdateGatewayProvider = Provider<PlayUpdateGateway>(
  (ref) => InAppUpdatePlayGateway(),
);
