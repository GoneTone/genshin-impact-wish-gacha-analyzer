import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/adb_shell_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/flutter_adb_session.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

/// 無線偵錯設定流程的階段。
enum PairingPhase {
  /// 說明頁（事前揭露）。
  disclosure,

  /// 開發人員選項還沒開。
  needDevOptions,

  /// 通知權限還沒允許（配對碼要從通知輸入）。
  needNotifications,

  /// 可以前往無線偵錯開始配對。
  ready,

  /// 配對服務已啟動，等玩家在通知輸入配對碼。
  waitingCode,

  /// 正在配對與授權。
  pairing,

  /// 配對成功，但授權自己開關無線偵錯失敗（部分廠牌的安全性限制）。
  grantFailed,

  /// 設定完成（可以自動開關無線偵錯）。
  done,

  /// 設定完成，但每次更新要手動開啟無線偵錯（玩家略過授權）。
  doneManual,
}

/// 設定流程的狀態。
class AdbPairingState {
  /// 建立狀態。
  const AdbPairingState(
    this.phase, {
    this.notificationsDenied = false,
    this.devOptionsUndetected = false,
  });

  /// 目前階段。
  final PairingPhase phase;

  /// 玩家拒絕過通知權限（畫面改為引導到 App 通知設定）。
  final bool notificationsDenied;

  /// 玩家回到 App 後仍偵測不到開發人員選項（畫面改提示總開關可能被關掉）。
  final bool devOptionsUndetected;

  /// 複製並替換指定欄位。
  AdbPairingState copyWith({
    PairingPhase? phase,
    bool? notificationsDenied,
    bool? devOptionsUndetected,
  }) => AdbPairingState(
    phase ?? this.phase,
    notificationsDenied: notificationsDenied ?? this.notificationsDenied,
    devOptionsUndetected: devOptionsUndetected ?? this.devOptionsUndetected,
  );
}

/// 無線偵錯設定流程：說明頁 → 開發人員選項 → 通知權限 → 配對 → 授權。
class AdbPairingController extends Notifier<AdbPairingState> {
  /// 本流程的 logger。
  static final _log = Logger('capture.pairing');

  /// 系統功能（build 時取得，流程途中 provider 被回收也能安全使用）。
  late LogAccessPlatform _platform;

  /// 配對與連線操作。
  late AdbPairingOps _ops;

  /// 用來找連接埠的 resolver。
  late LogAccessResolver _resolver;

  /// 開始設定時無線偵錯是否本來就開著；是的話設定完的那次更新不關它（只關照引導才打開的）。
  bool wirelessWasOnAtStart = false;

  /// 是否已檢查過一次開發人員選項（之後再偵測不到才顯示總開關的提示）。
  bool _devOptionsChecked = false;

  /// 切換階段；玩家已離開設定頁（provider 已回收）時忽略。
  void _go(PairingPhase phase) {
    if (ref.mounted) state = state.copyWith(phase: phase);
  }

  @override
  AdbPairingState build() {
    final platform = ref.read(logAccessPlatformProvider);
    _platform = platform;
    _ops = ref.read(adbPairingOpsProvider);
    _resolver = ref.read(logAccessResolverProvider);
    platform.setPairingCodeHandler(handlePairingCode);
    ref.onDispose(() {
      platform.setPairingCodeHandler(null);
      unawaited(platform.stopPairingService());
    });
    return const AdbPairingState(PairingPhase.disclosure);
  }

  /// 玩家在說明頁按「開始設定」。
  Future<void> startSetup() async {
    wirelessWasOnAtStart = await _platform.isAdbWifiEnabled();
    _log.info('setup started wirelessWasOn=$wirelessWasOnAtStart');
    _go(PairingPhase.needDevOptions);
    await refresh();
  }

  /// 從設定頁「重試授權」進入：直接到授權步驟。
  Future<void> startAtGrant() async {
    wirelessWasOnAtStart = await _platform.isAdbWifiEnabled();
    _log.info('retry grant started wirelessWasOn=$wirelessWasOnAtStart');
    _go(PairingPhase.grantFailed);
  }

  /// 依目前系統狀態更新階段（頁面回到前景時呼叫）；配對服務停了（逾時）就重新啟動。
  Future<void> refresh() async {
    if (!ref.mounted) return;
    final phase = state.phase;
    if (phase
        case PairingPhase.disclosure ||
            PairingPhase.pairing ||
            PairingPhase.grantFailed ||
            PairingPhase.done ||
            PairingPhase.doneManual) {
      return;
    }
    if (!await _platform.isDevelopmentSettingsEnabled()) {
      // 第一次檢查在按「開始設定」時；之後回到 App 仍偵測不到，多半是入口還在但總開關被關掉
      // （例如 vivo 連點版本號碼只會說入口已顯示），才提示玩家去開總開關。
      final undetected = _devOptionsChecked;
      _devOptionsChecked = true;
      if (ref.mounted) {
        state = state.copyWith(
          phase: PairingPhase.needDevOptions,
          devOptionsUndetected: state.devOptionsUndetected || undetected,
        );
      }
      return;
    }
    if (!await _platform.areNotificationsEnabled()) {
      _go(PairingPhase.needNotifications);
      return;
    }
    if (phase == PairingPhase.waitingCode) {
      if (!await _platform.isPairingServiceRunning()) {
        _log.info('pairing service not running, restarting');
        await _platform.startPairingService();
      }
      return;
    }
    _go(PairingPhase.ready);
  }

  /// 請求通知權限；被拒絕時記下來，畫面改為引導到 App 通知設定。
  Future<void> requestNotifications() async {
    final granted = await _platform.requestNotificationPermission();
    _log.info('notification permission granted=$granted');
    if (!granted) {
      if (ref.mounted) state = state.copyWith(notificationsDenied: true);
      return;
    }
    await refresh();
  }

  /// 啟動配對服務並跳到「無線偵錯」頁；約 3 分鐘的上限從這裡開始算。
  Future<void> openWirelessDebugging() async {
    await _platform.startPairingService();
    await _platform.openWirelessDebugging();
    _go(PairingPhase.waitingCode);
  }

  /// 配對服務收到配對碼時呼叫：配對、連線並授權自己開關無線偵錯。回傳給通知顯示的結果（不含配對碼）。
  Future<({bool ok, String message})> handlePairingCode(
    int port,
    String code,
  ) async {
    _go(PairingPhase.pairing);
    bool ok;
    try {
      ok = await _ops.pair(port, code);
    } catch (e) {
      // 例如讀寫配對金鑰失敗；不回到等待配對碼，畫面會一直停在「配對中」。
      _log.warning('pairing threw error=${e.runtimeType}');
      ok = false;
    }
    _log.info('pairing ok=$ok');
    if (!ok) {
      _go(PairingPhase.waitingCode);
      return (ok: false, message: 'pairing failed');
    }
    await _grant();
    return (ok: true, message: '');
  }

  /// 授權失敗後，玩家開了安全性選項再試一次。
  Future<void> retryGrant() async {
    _go(PairingPhase.pairing);
    await _grant();
  }

  /// 玩家略過授權：之後每次更新手動開啟無線偵錯。
  void skipGrant() {
    _log.info('grant skipped, manual toggle mode');
    _go(PairingPhase.doneManual);
  }

  /// 連上無線偵錯並授權自己 `WRITE_SECURE_SETTINGS`，依結果進入完成或授權失敗。
  Future<void> _grant() async {
    final platform = _platform;
    if (await platform.hasWriteSecureSettings()) {
      _go(PairingPhase.done);
      return;
    }
    final client = AdbShellClient(connect: _ops.connect);
    try {
      final ports = await _resolver.discoverConnectPorts();
      if (await client.connectAny(ports)) {
        await client.exec(grantWriteSecureSettingsCommand);
      } else {
        _log.warning('grant: could not connect ports=${ports.length}');
      }
    } on AdbShellException catch (e) {
      _log.warning('grant command failed: ${e.message}');
    } finally {
      await client.close();
    }
    final granted = await platform.hasWriteSecureSettings();
    _log.info('write secure settings granted=$granted');
    _go(granted ? PairingPhase.done : PairingPhase.grantFailed);
  }
}

/// 無線偵錯設定流程；離開設定頁時自動 dispose（停止配對服務）。
final adbPairingProvider =
    NotifierProvider.autoDispose<AdbPairingController, AdbPairingState>(
      AdbPairingController.new,
    );

/// 解除配對：能連上無線偵錯時先收回自己的 `WRITE_SECURE_SETTINGS`，再刪除本機金鑰。
///
/// 回傳 true 代表有連上並收回權限；false 代表連不上（只刪了金鑰，需提示玩家到系統設定移除）。
/// 原本沒開無線偵錯時，最後也用 shell 把它關回去（收回權限後 App 自己就關不了）。
Future<bool> unpairWirelessDebugging({
  required LogAccessPlatform platform,
  required AdbPairingOps ops,
  required LogAccessResolver resolver,
  required AdbKeyStore keyStore,
}) async {
  final log = Logger('capture.pairing');
  final wasOn = await platform.isAdbWifiEnabled();
  if (!wasOn) await platform.setAdbWifiEnabled(true);
  final client = AdbShellClient(connect: ops.connect);
  var revoked = false;
  try {
    if (await client.connectAny(await resolver.discoverConnectPorts())) {
      await client.exec(revokeWriteSecureSettingsCommand);
      revoked = true;
      if (!wasOn) {
        try {
          await client.exec(disableAdbWifiCommand);
        } on AdbShellException {
          // 關閉無線偵錯會切斷這條連線，指令本身可能來不及回應。
        }
      }
    }
  } on AdbShellException catch (e) {
    log.warning('unpair revoke failed: ${e.message}');
  } finally {
    await client.close();
    // 沒收回權限時 App 還能自己關；連不上也不能把剛打開的無線偵錯留著。
    if (!wasOn && !revoked) await platform.setAdbWifiEnabled(false);
  }
  await keyStore.delete();
  log.info('unpaired revoked=$revoked');
  return revoked;
}

/// 解除配對（含清除記住的讀取方式）；Widget 測試可 override。
final unpairWirelessDebuggingProvider = Provider<Future<bool> Function()>(
  (ref) => () async {
    final revoked = await unpairWirelessDebugging(
      platform: ref.read(logAccessPlatformProvider),
      ops: ref.read(adbPairingOpsProvider),
      resolver: ref.read(logAccessResolverProvider),
      keyStore: ref.read(adbKeyStoreProvider),
    );
    await ref.read(settingsProvider.notifier).setLogAccessMethod(null);
    return revoked;
  },
);

/// 設定頁顯示用的無線偵錯配對狀態：是否有金鑰、App 能否自己開關無線偵錯。
final wirelessPairingStatusProvider =
    FutureProvider.autoDispose<({bool paired, bool canToggle})>((ref) async {
      final paired = await ref.read(adbKeyStoreProvider).hasKey();
      final canToggle = await ref
          .read(logAccessPlatformProvider)
          .hasWriteSecureSettings();
      return (paired: paired, canToggle: canToggle);
    });
