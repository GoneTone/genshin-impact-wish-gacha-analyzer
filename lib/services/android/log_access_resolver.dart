import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/adb_shell_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/flutter_adb_session.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/genshin_game_package.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_method.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/root_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/shell_exec.dart';

export 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_method.dart';

/// 沒有自動讀取方式的原因。
enum LogAccessUnavailable {
  /// 無線偵錯尚未配對。
  notPaired,

  /// 沒有連上 Wi‑Fi（無線偵錯無法使用）。
  noWifi,

  /// 已配對但連不上無線偵錯（配對可能失效）。
  adbConnectFailed,

  /// 無線偵錯是關的，App 也沒有權限打開（手動開關模式）。
  wirelessDebuggingOff,

  /// 目前的 Wi‑Fi 還沒允許無線偵錯：系統擋下開啟並跳出詢問視窗，要等玩家按「允許」。
  networkNotAllowed,

  /// 這台裝置無法自動讀取。
  unsupported,

  /// 裝置上找不到國際服原神。
  gameNotInstalled,
}

/// [LogAccessResolver.resolve] 的結果。
sealed class LogAccessOutcome {
  /// 建立結果。
  const LogAccessOutcome();
}

/// 可以讀取系統記錄。
final class LogAccessReady extends LogAccessOutcome {
  /// 建立結果。
  LogAccessReady({
    required this.exec,
    required this.method,
    required this.release,
    this.game,
    Stream<bool>? healthChanges,
  }) : healthChanges = healthChanges ?? const Stream.empty();

  /// 在裝置上執行 shell 指令的函式（root 或無線偵錯）。
  final ShellExec exec;

  /// 「開啟原神」要開的套件名稱：裝了多個版本時取排序第一個；查詢失敗時為 null。
  final String? game;

  /// 使用的讀取方式。
  final LogAccessMethod method;

  /// 用完時呼叫：中斷連線並依規則關閉無線偵錯。
  ///
  /// 回傳 true 代表照規則應該關掉無線偵錯，但沒有權限關（手動開關模式），需要提示玩家自行關閉。
  final Future<bool> Function() release;

  /// 連線健康狀態變化（false＝中斷、true＝恢復）。
  final Stream<bool> healthChanges;
}

/// 沒有自動讀取方式。
final class LogAccessBlocked extends LogAccessOutcome {
  /// 建立結果。
  const LogAccessBlocked(
    this.reason, {
    this.rootDenied = false,
    this.enabledWireless = false,
    this.wirelessLeftOn = false,
  });

  /// 原因。
  final LogAccessUnavailable reason;

  /// 裝置有 `su` 但沒拿到 root 授權（被拒或沒按允許）；root 工具可能已記成永久拒絕而不再詢問。
  final bool rootDenied;

  /// 這次判斷曾由 App 打開無線偵錯（原本是關的），或照規則用完要關（剛配對完、玩家照引導打開）。
  /// 之後若由系統打開（例如玩家在詢問視窗按允許），重試時不能當成玩家原本就開著而在用完後留著。
  final bool enabledWireless;

  /// 照規則該關掉無線偵錯，但沒有權限關而留著開；更新完成時要提示玩家自行關閉。
  final bool wirelessLeftOn;
}

/// 本 App 的套件名稱（授權 `WRITE_SECURE_SETTINGS` 用）。
const _appPackage = 'tw.reh.genshin.gacha';

/// 授權自己開關無線偵錯的指令。
const grantWriteSecureSettingsCommand =
    'pm grant $_appPackage android.permission.WRITE_SECURE_SETTINGS';

/// 收回 [grantWriteSecureSettingsCommand] 的指令。
const revokeWriteSecureSettingsCommand =
    'pm revoke $_appPackage android.permission.WRITE_SECURE_SETTINGS';

/// 透過 shell 關閉無線偵錯（解除配對收回權限後，App 自己已經不能關，交給 shell 做；會中斷目前連線）。
const disableAdbWifiCommand = 'settings put global adb_wifi_enabled 0';

/// 依 root → 無線偵錯（Android 11 以上）的順序決定怎麼讀系統記錄。
class LogAccessResolver {
  /// 建立 resolver；[makeConnector] 讀出配對金鑰並回傳連線函式。
  LogAccessResolver({
    required this.platform,
    required this.root,
    required this.keyStore,
    required this.makeConnector,
    this.discoverAttempts = 5,
    this.discoverRetryDelay = const Duration(seconds: 1),
    this.enableSettleDelay = const Duration(milliseconds: 500),
    this.connectRetryDelay = const Duration(milliseconds: 1500),
    this.connectRetryAttempts = 3,
  });

  /// 系統功能。
  final LogAccessPlatform platform;

  /// root shell。
  final RootShell root;

  /// 配對金鑰保存。
  final AdbKeyStore keyStore;

  /// 讀出金鑰後產生無線偵錯連線函式。
  final Future<AdbConnector> Function() makeConnector;

  /// NSD 找不到連接埠時最多嘗試幾次（剛打開無線偵錯時服務要一點時間才會出現）。
  final int discoverAttempts;

  /// NSD 重試間隔。
  final Duration discoverRetryDelay;

  /// 打開無線偵錯後等多久再讀回開關（系統擋下時會立刻改回關閉）。
  final Duration enableSettleDelay;

  /// 連不上時等多久再重新找連接埠（無線偵錯剛關又開時，NSD 會先回報上一輪的連接埠）。
  final Duration connectRetryDelay;

  /// 連不上時保持無線偵錯開著、重新找連接埠再連的最多次數。
  final int connectRetryAttempts;

  /// 本 resolver 的 logger。
  static final _log = Logger('capture.android');

  /// 決定讀取方式；[preferred] 先試，[forceDisableAfterUse] 為 true 時用完一律關閉無線偵錯（剛配對完時）。
  ///
  /// [abort] 完成時（玩家取消或手動送出）結束 root 授權等待，之後的方式都不再嘗試。
  /// 讀取方式之前先找原神：沒裝就不跳 root 授權或打開無線偵錯；查詢失敗不能當成沒裝，照常判斷。
  Future<LogAccessOutcome> resolve({
    LogAccessMethod? preferred,
    bool forceDisableAfterUse = false,
    Future<void>? abort,
  }) async {
    final sw = Stopwatch()..start();
    var finished = false;
    var aborted = false;
    unawaited(
      abort?.then((_) async {
        if (finished) return;
        aborted = true;
        _log.info('log access resolve aborted ms=${sw.elapsedMilliseconds}');
        // 關掉 su 會讓還在等授權的 verify 立刻失敗，root 工具的詢問視窗也跟著結束。
        await root.close();
      }),
    );
    try {
      final games = await platform.installedGamePackages();
      if (games == null) {
        _log.warning('game detection failed, resolving without a game');
      } else {
        _log.info('games installed=${games.join(',')}');
        if (games.isEmpty) {
          return const LogAccessBlocked(LogAccessUnavailable.gameNotInstalled);
        }
      }
      return await _resolve(
        game: games == null ? null : sortGenshinPackages(games).first,
        preferred: preferred,
        forceDisableAfterUse: forceDisableAfterUse,
        isAborted: () => aborted,
        sw: sw,
      );
    } finally {
      finished = true;
    }
  }

  /// [resolve] 的實際流程；[isAborted] 為 true 後不再嘗試下一種方式。
  Future<LogAccessOutcome> _resolve({
    required String? game,
    required LogAccessMethod? preferred,
    required bool forceDisableAfterUse,
    required bool Function() isAborted,
    required Stopwatch sw,
  }) async {
    final order = {
      ?preferred,
      LogAccessMethod.root,
      LogAccessMethod.wirelessDebugging,
    };
    LogAccessBlocked? blocked;
    var rootDenied = false;
    for (final method in order) {
      if (isAborted()) break;
      final outcome = switch (method) {
        LogAccessMethod.root => await _tryRoot(
          game,
          onDenied: () => rootDenied = true,
        ),
        LogAccessMethod.wirelessDebugging => await _tryWireless(
          game,
          forceDisableAfterUse,
          isAborted,
        ),
      };
      if (outcome is LogAccessReady) {
        _log.info(
          'log access ready method=${method.name} game=$game '
          'ms=${sw.elapsedMilliseconds}',
        );
        return outcome;
      }
      if (outcome is LogAccessBlocked) blocked ??= outcome;
    }
    final result = LogAccessBlocked(
      blocked?.reason ?? LogAccessUnavailable.unsupported,
      rootDenied: rootDenied,
      enabledWireless: blocked?.enabledWireless ?? false,
      wirelessLeftOn: blocked?.wirelessLeftOn ?? false,
    );
    _log.info(
      'log access blocked reason=${result.reason.name} rootDenied=$rootDenied '
      'ms=${sw.elapsedMilliseconds}',
    );
    return result;
  }

  /// root：有 `su` 且授權成功才可用；否則回 null 讓下一種方式接手。有 `su` 卻沒拿到授權時呼叫 [onDenied]。
  Future<LogAccessOutcome?> _tryRoot(
    String? game, {
    required void Function() onDenied,
  }) async {
    if (!await root.isSuPresent()) return null;
    if (!await root.verify()) {
      onDenied();
      return null;
    }
    return LogAccessReady(
      exec: root.exec,
      method: LogAccessMethod.root,
      game: game,
      healthChanges: root.healthChanges,
      release: () async {
        await root.close();
        return false;
      },
    );
  }

  /// 收集本機無線偵錯的連接埠；剛打開無線偵錯時 NSD 還找不到，所以重試幾次。
  Future<List<int>> discoverConnectPorts() async {
    for (var i = 0; i < discoverAttempts; i++) {
      final ports = await platform.discoverAdbConnectPorts();
      if (ports.isNotEmpty) return ports;
      await Future<void>.delayed(discoverRetryDelay);
    }
    return const [];
  }

  /// 無線偵錯：檢查配對與 Wi‑Fi、必要時打開無線偵錯、連線、補授權；Android 10 以下沒有此功能。
  ///
  /// 連不上時保持開著重新找連接埠再試；[isAborted] 為 true 後不再重試。
  Future<LogAccessOutcome?> _tryWireless(
    String? game,
    bool forceDisableAfterUse,
    bool Function() isAborted,
  ) async {
    if (await platform.sdkInt() < 30) return null;
    if (!await keyStore.hasKey()) {
      return const LogAccessBlocked(LogAccessUnavailable.notPaired);
    }
    if (!await platform.isWifiConnected()) {
      return const LogAccessBlocked(LogAccessUnavailable.noWifi);
    }
    final wasOn = await platform.isAdbWifiEnabled();
    if (!wasOn && !await platform.setAdbWifiEnabled(true)) {
      return const LogAccessBlocked(LogAccessUnavailable.wirelessDebuggingOff);
    }
    if (!wasOn) {
      await Future<void>.delayed(enableSettleDelay);
      if (!await platform.isAdbWifiEnabled()) {
        _log.info('wireless debugging not allowed on this network yet');
        return const LogAccessBlocked(
          LogAccessUnavailable.networkNotAllowed,
          enabledWireless: true,
        );
      }
    }
    final client = AdbShellClient(
      connect: await makeConnector(),
      rediscover: () async {
        if (!await platform.isAdbWifiEnabled()) {
          await platform.setAdbWifiEnabled(true);
        }
        return discoverConnectPorts();
      },
    );
    final tried = {...await discoverConnectPorts()};
    var connected = await client.connectAny(tried.toList());
    // 剛關又開時 adbd 換了連接埠但 NSD 還回報舊的；再切一次開關只會讓 NSD 一直落後一輪，所以保持開著等它跟上。
    for (
      var attempt = 1;
      !connected && !isAborted() && attempt <= connectRetryAttempts;
      attempt++
    ) {
      await Future<void>.delayed(connectRetryDelay);
      if (isAborted()) break;
      final ports = await discoverConnectPorts();
      _log.info('adb connect retry attempt=$attempt ports=$ports tried=$tried');
      final fresh = ports.where((p) => !tried.contains(p)).toList();
      if (fresh.isEmpty) continue;
      tried.addAll(fresh);
      connected = await client.connectAny(fresh);
    }
    if (!connected) {
      await client.close();
      final turnOff = !wasOn || forceDisableAfterUse;
      final leftOn = turnOff && !await platform.setAdbWifiEnabled(false);
      if (leftOn) {
        _log.info(
          'wireless debugging left on after connect failure: '
          'no permission to turn it off',
        );
      }
      return LogAccessBlocked(
        LogAccessUnavailable.adbConnectFailed,
        enabledWireless: turnOff,
        wirelessLeftOn: leftOn,
      );
    }
    if (!await platform.hasWriteSecureSettings()) {
      try {
        await client.exec(grantWriteSecureSettingsCommand);
        _log.info(
          'write secure settings granted=${await platform.hasWriteSecureSettings()}',
        );
      } on AdbShellException catch (e) {
        _log.warning('write secure settings grant failed: ${e.message}');
      }
    }
    return LogAccessReady(
      exec: client.exec,
      method: LogAccessMethod.wirelessDebugging,
      game: game,
      healthChanges: client.healthChanges,
      release: () async {
        await client.close();
        if (wasOn && !forceDisableAfterUse) return false;
        if (await platform.setAdbWifiEnabled(false)) return false;
        _log.info('wireless debugging left on: no permission to turn it off');
        return true;
      },
    );
  }
}

/// 提供 [LogAccessResolver]，測試可 override。
final logAccessResolverProvider = Provider<LogAccessResolver>((ref) {
  final keyStore = ref.watch(adbKeyStoreProvider);
  return LogAccessResolver(
    platform: ref.watch(logAccessPlatformProvider),
    root: RootShell(),
    keyStore: keyStore,
    makeConnector: () async {
      final crypto = await keyStore.load();
      return (port) async =>
          crypto == null ? null : connectFlutterAdb(crypto, port);
    },
  );
});
