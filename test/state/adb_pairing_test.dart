import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/adb_shell_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/flutter_adb_session.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/root_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/adb_pairing.dart';

/// 可設定狀態的平台替身。
class _Platform extends LogAccessPlatform {
  bool dev = true;
  bool notifications = true;
  bool grantNotifications = true;
  bool serviceRunning = false;
  bool wss = false;
  int serviceStarts = 0;
  int wirelessOpens = 0;
  Future<({bool ok, String message})> Function(int, String)? handler;

  @override
  Future<bool> isDevelopmentSettingsEnabled() async => dev;
  @override
  Future<bool> areNotificationsEnabled() async => notifications;
  @override
  Future<bool> requestNotificationPermission() async =>
      notifications = grantNotifications;
  @override
  Future<bool> isPairingServiceRunning() async => serviceRunning;
  @override
  Future<void> startPairingService() async {
    serviceStarts++;
    serviceRunning = true;
  }

  @override
  Future<void> stopPairingService() async => serviceRunning = false;
  @override
  Future<void> openWirelessDebugging() async => wirelessOpens++;

  @override
  Future<bool> hasWriteSecureSettings() async => wss;
  bool adbWifiOn = true;
  final adbWifiWrites = <bool>[];

  @override
  Future<bool> isAdbWifiEnabled() async => adbWifiOn;
  @override
  Future<bool> setAdbWifiEnabled(bool enabled) async {
    if (!wss) return false;
    adbWifiWrites.add(enabled);
    adbWifiOn = enabled;
    return true;
  }

  @override
  Future<List<int>> discoverAdbConnectPorts() async => [5555];
  @override
  void setPairingCodeHandler(
    Future<({bool ok, String message})> Function(int port, String code)? h,
  ) => handler = h;
}

/// 配對與連線結果可設定的替身；執行 pm grant 時依 [grantWorks] 打開權限。
class _Ops extends AdbPairingOps {
  _Ops(this.platform) : super(AdbKeyStore());

  final _Platform platform;
  bool pairOk = true;
  bool grantWorks = true;
  bool reachable = true;
  bool pairThrows = false;

  /// `pm grant` 回傳的輸出。
  String grantOutput = '';
  final commands = <String>[];
  final pairs = <(int, String)>[];

  @override
  Future<bool> pair(int port, String code) async {
    pairs.add((port, code));
    if (pairThrows) throw StateError('key storage failed');
    return pairOk;
  }

  @override
  Future<AdbSession?> connect(int port) async =>
      reachable ? _Session(this) : null;
}

/// 回應 id 與 pm grant 的連線替身。
/// 金鑰是否存在可設定、記錄刪除的替身。
class _Keys extends AdbKeyStore {
  bool has = true;

  @override
  Future<bool> hasKey() async => has;
  @override
  Future<void> delete() async => has = false;
}

class _Session implements AdbSession {
  _Session(this.ops);

  final _Ops ops;

  @override
  Future<Uint8List> shell(String command) async {
    ops.commands.add(command);
    if (command == grantWriteSecureSettingsCommand && ops.grantWorks) {
      ops.platform.wss = true;
    }
    final out = switch (command) {
      'id' => 'uid=2000',
      grantWriteSecureSettingsCommand => ops.grantOutput,
      _ => '',
    };
    return Uint8List.fromList(utf8.encode(out));
  }

  @override
  Future<void> close() async {}
}

void main() {
  late _Platform platform;
  late _Ops ops;
  late ProviderContainer c;

  setUp(() {
    platform = _Platform();
    ops = _Ops(platform);
    c = ProviderContainer(
      overrides: [
        logAccessPlatformProvider.overrideWithValue(platform),
        adbPairingOpsProvider.overrideWithValue(ops),
        logAccessResolverProvider.overrideWithValue(
          LogAccessResolver(
            platform: platform,
            root: RootShell(),
            keyStore: AdbKeyStore(),
            makeConnector: () async => ops.connect,
            discoverRetryDelay: Duration.zero,
          ),
        ),
      ],
    );
  });
  tearDown(() => c.dispose());

  // 頁面在畫面上時會一直監聽；測試同樣保持監聽，避免 autoDispose 在流程途中回收。
  setUp(() => c.listen(adbPairingProvider, (_, _) {}));

  AdbPairingController ctl() => c.read(adbPairingProvider.notifier);
  PairingPhase phase() => c.read(adbPairingProvider).phase;

  test('starts at the disclosure page', () {
    expect(phase(), PairingPhase.disclosure);
  });

  test('refresh walks dev options → notifications → ready', () async {
    platform
      ..dev = false
      ..notifications = false;
    await ctl().startSetup();
    expect(phase(), PairingPhase.needDevOptions);
    platform.dev = true;
    await ctl().refresh();
    expect(phase(), PairingPhase.needNotifications);
    platform.notifications = true;
    await ctl().refresh();
    expect(phase(), PairingPhase.ready);
  });

  test(
    'switch hint appears only after a re-check still finds dev options off',
    () async {
      platform.dev = false;
      await ctl().startSetup();
      expect(c.read(adbPairingProvider).devOptionsUndetected, isFalse);
      await ctl().refresh();
      expect(phase(), PairingPhase.needDevOptions);
      expect(c.read(adbPairingProvider).devOptionsUndetected, isTrue);
    },
  );

  test('denied notification permission is remembered for the UI', () async {
    platform
      ..notifications = false
      ..grantNotifications = false;
    await ctl().startSetup();
    await ctl().requestNotifications();
    expect(phase(), PairingPhase.needNotifications);
    expect(c.read(adbPairingProvider).notificationsDenied, isTrue);
  });

  test('service is not started until openWirelessDebugging', () async {
    await ctl().startSetup();
    expect(platform.serviceStarts, 0);
    await ctl().openWirelessDebugging();
    expect(platform.serviceStarts, 1);
    expect(platform.wirelessOpens, 1);
    expect(phase(), PairingPhase.waitingCode);
  });

  test('pairing code success with grant → done', () async {
    await ctl().startSetup();
    await ctl().openWirelessDebugging();
    final r = await platform.handler!(37155, '482913');
    expect(r.ok, isTrue);
    expect(ops.pairs.single, (37155, '482913'));
    expect(phase(), PairingPhase.done);
  });

  test('pairing code success but grant fails → grantFailed', () async {
    ops.grantWorks = false;
    await ctl().startSetup();
    await ctl().openWirelessDebugging();
    await platform.handler!(1, '111111');
    expect(phase(), PairingPhase.grantFailed);
  });

  test('logs the pm grant output on one line so rejections are diagnosable', () async {
    ops
      ..grantWorks = false
      ..grantOutput =
          "Exception occurred while executing 'grant':\n"
          'java.lang.SecurityException: grantRuntimePermission: Neither user 2000 '
          'nor current process has android.permission.GRANT_RUNTIME_PERMISSIONS.\n';
    final records = <LogRecord>[];
    final sub = Logger('capture.pairing').onRecord.listen(records.add);
    addTearDown(sub.cancel);
    await ctl().startSetup();
    await ctl().openWirelessDebugging();
    await platform.handler!(1, '111111');
    expect(
      records.map((r) => r.message),
      contains(
        "grant command output=\"Exception occurred while executing 'grant': "
        'java.lang.SecurityException: grantRuntimePermission: Neither user 2000 '
        'nor current process has android.permission.GRANT_RUNTIME_PERMISSIONS."',
      ),
    );
  });

  test('pmOutputForLog caps long output', () {
    final out = pmOutputForLog(utf8.encode('x' * 500));
    expect(out, '${'x' * 300}...');
  });

  test('wrong code returns ok=false without leaking the code', () async {
    ops.pairOk = false;
    await ctl().startSetup();
    await ctl().openWirelessDebugging();
    final r = await platform.handler!(1, '987654');
    expect(r.ok, isFalse);
    expect(r.message, isNot(contains('987654')));
    expect(phase(), PairingPhase.waitingCode);
  });

  test('pairing that throws goes back to waiting for a code', () async {
    ops.pairThrows = true;
    await ctl().startSetup();
    await ctl().openWirelessDebugging();
    final r = await platform.handler!(1, '222222');
    expect(r.ok, isFalse);
    expect(r.message, isNot(contains('222222')));
    expect(phase(), PairingPhase.waitingCode);
  });

  test('refresh restarts service when waiting and service stopped', () async {
    await ctl().startSetup();
    await ctl().openWirelessDebugging();
    platform.serviceRunning = false;
    await ctl().refresh();
    expect(platform.serviceStarts, 2);
    expect(phase(), PairingPhase.waitingCode);
  });

  test('retryGrant after enabling the option → done', () async {
    ops.grantWorks = false;
    await ctl().startSetup();
    await ctl().openWirelessDebugging();
    await platform.handler!(1, '111111');
    ops.grantWorks = true;
    await ctl().retryGrant();
    expect(phase(), PairingPhase.done);
  });

  test('skipGrant ends setup in manual toggle mode', () async {
    ops.grantWorks = false;
    await ctl().startSetup();
    await ctl().openWirelessDebugging();
    await platform.handler!(1, '111111');
    ctl().skipGrant();
    expect(phase(), PairingPhase.doneManual);
  });

  test('startAtGrant jumps straight to the grant step', () async {
    await ctl().startAtGrant();
    expect(phase(), PairingPhase.grantFailed);
  });

  test('records whether wireless debugging was on when setup starts', () async {
    platform.adbWifiOn = true;
    await ctl().startSetup();
    expect(ctl().wirelessWasOnAtStart, isTrue);
    platform.adbWifiOn = false;
    await ctl().startAtGrant();
    expect(ctl().wirelessWasOnAtStart, isFalse);
  });

  group('unpairWirelessDebugging', () {
    late _Keys keys;

    Future<bool> unpair() => unpairWirelessDebugging(
      platform: platform,
      ops: ops,
      resolver: c.read(logAccessResolverProvider),
      keyStore: keys,
    );

    setUp(() => keys = _Keys());

    test(
      'revokes, turns wireless debugging back off and deletes the key',
      () async {
        platform
          ..wss = true
          ..adbWifiOn = false;
        expect(await unpair(), isTrue);
        expect(ops.commands, contains(revokeWriteSecureSettingsCommand));
        expect(ops.commands.last, disableAdbWifiCommand);
        expect(keys.has, isFalse);
      },
    );

    test('keeps wireless debugging on if it already was', () async {
      platform
        ..wss = true
        ..adbWifiOn = true;
      await unpair();
      expect(ops.commands, isNot(contains(disableAdbWifiCommand)));
    });

    test('unreachable still deletes the key and reports it', () async {
      ops.reachable = false;
      expect(await unpair(), isFalse);
      expect(keys.has, isFalse);
    });

    test(
      'unreachable turns wireless debugging back off if it was off',
      () async {
        platform
          ..wss = true
          ..adbWifiOn = false;
        ops.reachable = false;
        expect(await unpair(), isFalse);
        expect(platform.adbWifiOn, isFalse);
      },
    );
  });
}
