import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(LogAccessPlatform.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  /// 讓 Kotlin 端以 [handler] 回應。
  void respond(Object? Function(MethodCall call) handler) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('discoverAdbConnectPorts maps the port list', () async {
    respond((_) => [37155, 44091]);
    expect(await LogAccessPlatform().discoverAdbConnectPorts(), [37155, 44091]);
    expect(calls.single.method, 'discoverAdbConnectPorts');
  });

  test('discoverAdbConnectPorts tolerates platform errors', () async {
    respond((_) => throw PlatformException(code: 'nsd'));
    expect(await LogAccessPlatform().discoverAdbConnectPorts(), isEmpty);
  });

  test('setAdbWifiEnabled passes the flag and maps the result', () async {
    respond((_) => true);
    expect(await LogAccessPlatform().setAdbWifiEnabled(true), isTrue);
    expect(calls.single.arguments, {'enabled': true});
  });

  test('setAdbWifiEnabled is false on platform error', () async {
    respond((_) => throw PlatformException(code: 'security'));
    expect(await LogAccessPlatform().setAdbWifiEnabled(true), isFalse);
  });

  test('installedGamePackages filters, sorts and sends the prefix', () async {
    respond(
      (_) => [
        'com.miHoYo.GenshinImpact.zz',
        'com.miHoYo.Yuanshen',
        'com.miHoYo.GenshinImpact',
      ],
    );
    expect(await LogAccessPlatform().installedGamePackages(), [
      'com.miHoYo.GenshinImpact',
      'com.miHoYo.GenshinImpact.zz',
    ]);
    expect(calls.single.method, 'installedGames');
    expect(
      (calls.single.arguments as Map)['prefix'],
      'com.miHoYo.GenshinImpact',
    );
  });

  test('installedGamePackages is null on error, not empty', () async {
    // 空清單代表「沒裝」，查詢失敗不能被當成沒裝。
    respond((_) => throw PlatformException(code: 'pm'));
    expect(await LogAccessPlatform().installedGamePackages(), isNull);
  });

  test('launchGame passes the package', () async {
    respond((_) => true);
    expect(
      await LogAccessPlatform().launchGame('com.miHoYo.GenshinImpact'),
      isTrue,
    );
    expect(calls.single.arguments, {'package': 'com.miHoYo.GenshinImpact'});
  });

  test('missing plugin returns conservative defaults', () async {
    final p = LogAccessPlatform();
    expect(await p.isWifiConnected(), isFalse);
    expect(await p.hasWriteSecureSettings(), isFalse);
    expect(await p.sdkInt(), 0);
    expect(await p.discoverAdbConnectPorts(), isEmpty);
    await p.openWirelessDebugging();
    expect(await p.isDevelopmentSettingsEnabled(), isFalse);
  });

  test('development settings follow AOSP: any non-zero value is on', () async {
    final p = LogAccessPlatform();
    for (final (raw, on) in [
      ('1', true),
      ('2', true),
      ('0', false),
      (null, false),
    ]) {
      respond((_) => raw);
      expect(await p.isDevelopmentSettingsEnabled(), on, reason: '$raw');
      expect(calls.single.method, 'developmentSettingsEnabledRaw');
    }
  });
}
