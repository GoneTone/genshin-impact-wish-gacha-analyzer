import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/ads/ads_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/ads.dart';

/// 記錄呼叫並可調整回傳值的假 [AdsPlatform]。
class _FakeAdsPlatform extends AdsPlatform {
  /// 建立假平台，[consentFails] 為 true 時 [requestConsentUpdate] 丟例外。
  _FakeAdsPlatform({
    this.consentFails = false,
    this.canRequest = false,
    this.optionsRequired = false,
  });

  /// 同意資訊更新是否失敗。
  final bool consentFails;

  /// [canRequestAds] 的回傳值。
  bool canRequest;

  /// [isPrivacyOptionsRequired] 的回傳值。
  bool optionsRequired;

  /// 非 null 時 [requestConsentUpdate] 會丟出它。
  Object? consentError;

  /// 非 null 時 [initializeSdk] 會丟出它。
  Object? initError;

  /// 非 null 時 [initializeSdk] 會等它完成。
  Completer<void>? initGate;

  /// 非 null 時 [showPrivacyOptionsForm] 會等它完成。
  Completer<void>? formGate;

  /// 非 null 時 [showPrivacyOptionsForm] 會丟出它。
  Object? formError;

  /// 非 null 時 [showPrivacyOptionsForm] 結束後把 [canRequest] 改成它。
  bool? canRequestAfterForm;

  /// [requestConsentUpdate] 的呼叫次數。
  int consentUpdates = 0;

  /// 非 null 時 [loadAndShowConsentFormIfRequired] 會丟出它。
  Object? loadFormError;

  /// [initializeSdk] 的呼叫次數。
  int initCalls = 0;

  /// [showPrivacyOptionsForm] 的呼叫次數。
  int formCalls = 0;

  @override
  Future<void> requestConsentUpdate() async {
    consentUpdates++;
    if (consentError != null) throw consentError!;
    if (consentFails) throw AdsConsentException('1', 'boom');
  }

  @override
  Future<void> loadAndShowConsentFormIfRequired() async {
    if (loadFormError != null) throw loadFormError!;
  }

  @override
  Future<bool> canRequestAds() async => canRequest;

  @override
  Future<bool> isPrivacyOptionsRequired() async => optionsRequired;

  @override
  Future<void> showPrivacyOptionsForm() async {
    formCalls++;
    await formGate?.future;
    if (formError != null) throw formError!;
    canRequest = canRequestAfterForm ?? canRequest;
  }

  @override
  Future<void> initializeSdk() async {
    initCalls++;
    await initGate?.future;
    if (initError != null) throw initError!;
  }
}

/// 以 [fake] 建立容器。
ProviderContainer _container(_FakeAdsPlatform fake) {
  final c = ProviderContainer(
    overrides: [adsPlatformProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('start enables ads after consent', () async {
    final fake = _FakeAdsPlatform(canRequest: true);
    final c = _container(fake);
    await c.read(adsProvider.notifier).start();
    expect(c.read(adsProvider).canRequestAds, isTrue);
    expect(fake.initCalls, 1);
  });

  test('consent error leaves ads disabled', () async {
    final fake = _FakeAdsPlatform(consentFails: true);
    final c = _container(fake);
    await c.read(adsProvider.notifier).start();
    expect(c.read(adsProvider).canRequestAds, isFalse);
    expect(fake.initCalls, 0);
  });

  test('consent error still uses previous consent', () async {
    final fake = _FakeAdsPlatform(consentFails: true, canRequest: true);
    final c = _container(fake);
    await c.read(adsProvider.notifier).start();
    expect(c.read(adsProvider).canRequestAds, isTrue);
    expect(fake.initCalls, 1);
  });

  test('start runs once', () async {
    final fake = _FakeAdsPlatform();
    final c = _container(fake);
    await c.read(adsProvider.notifier).start();
    await c.read(adsProvider.notifier).start();
    expect(fake.consentUpdates, 1);
  });

  test('privacy options flag follows the platform', () async {
    final fake = _FakeAdsPlatform(optionsRequired: true);
    final c = _container(fake);
    await c.read(adsProvider.notifier).start();
    expect(c.read(adsProvider).privacyOptionsRequired, isTrue);
    fake.optionsRequired = false;
    await c.read(adsProvider.notifier).showPrivacyOptions();
    expect(c.read(adsProvider).privacyOptionsRequired, isFalse);
  });

  test(
    'unexpected platform error is contained and ads stay disabled',
    () async {
      final fake = _FakeAdsPlatform(canRequest: true)
        ..initError = StateError('plugin');
      final c = _container(fake);
      await c.read(adsProvider.notifier).start();
      expect(c.read(adsProvider).canRequestAds, isFalse);
    },
  );

  test('disposing while the privacy form is open does not throw', () async {
    final fake = _FakeAdsPlatform()..formGate = Completer<void>();
    final c = ProviderContainer(
      overrides: [adsPlatformProvider.overrideWithValue(fake)],
    );
    final pending = c.read(adsProvider.notifier).showPrivacyOptions();
    c.dispose();
    fake.formGate!.complete();
    await pending;
  });

  test('unexpected consent error still uses previous consent', () async {
    final fake = _FakeAdsPlatform(canRequest: true)
      ..consentError = StateError('plugin');
    final c = _container(fake);
    await c.read(adsProvider.notifier).start();
    expect(c.read(adsProvider).canRequestAds, isTrue);
    expect(fake.initCalls, 1);
  });

  test(
    'unexpected consent error without prior consent stays disabled',
    () async {
      final fake = _FakeAdsPlatform()..consentError = StateError('plugin');
      final c = _container(fake);
      await c.read(adsProvider.notifier).start();
      expect(c.read(adsProvider).canRequestAds, isFalse);
      expect(fake.initCalls, 0);
    },
  );

  for (final error in <Object>[
    AdsConsentException('2', 'form'),
    StateError('plugin'),
  ]) {
    test(
      'consent form ${error.runtimeType} follows the platform flag',
      () async {
        for (final canRequest in [true, false]) {
          final fake = _FakeAdsPlatform(canRequest: canRequest)
            ..loadFormError = error;
          final c = _container(fake);
          await c.read(adsProvider.notifier).start();
          expect(c.read(adsProvider).canRequestAds, canRequest);
        }
      },
    );
  }

  test('showPrivacyOptions shows the form once', () async {
    final fake = _FakeAdsPlatform();
    final c = _container(fake);
    await c.read(adsProvider.notifier).showPrivacyOptions();
    expect(fake.formCalls, 1);
  });

  test('concurrent start and privacy form initialize the SDK once', () async {
    final fake = _FakeAdsPlatform(canRequest: true)
      ..initGate = Completer<void>();
    final c = _container(fake);
    final ctrl = c.read(adsProvider.notifier);
    final both = Future.wait([ctrl.start(), ctrl.showPrivacyOptions()]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    fake.initGate!.complete();
    await both;
    expect(fake.initCalls, 1);
  });

  test('failed SDK init can be retried', () async {
    final fake = _FakeAdsPlatform(canRequest: true)
      ..initError = StateError('plugin');
    final c = _container(fake);
    final ctrl = c.read(adsProvider.notifier);
    await ctrl.start();
    fake.initError = null;
    await ctrl.showPrivacyOptions();
    expect(fake.initCalls, 2);
    expect(c.read(adsProvider).canRequestAds, isTrue);
  });

  test('consent given in the privacy form initializes the SDK', () async {
    // 啟動時表單失敗、之後才從設定頁同意：要補初始化，分級上限才會套用。
    final fake = _FakeAdsPlatform()..canRequestAfterForm = true;
    final c = _container(fake);
    await c.read(adsProvider.notifier).start();
    expect(fake.initCalls, 0);
    await c.read(adsProvider.notifier).showPrivacyOptions();
    expect(c.read(adsProvider).canRequestAds, isTrue);
    expect(fake.initCalls, 1);
  });

  test('privacy form does not initialize the SDK twice', () async {
    final fake = _FakeAdsPlatform(canRequest: true);
    final c = _container(fake);
    await c.read(adsProvider.notifier).start();
    await c.read(adsProvider.notifier).showPrivacyOptions();
    expect(fake.initCalls, 1);
  });

  test('unexpected privacy form error is contained', () async {
    final fake = _FakeAdsPlatform()..formError = StateError('plugin');
    final c = _container(fake);
    await c.read(adsProvider.notifier).showPrivacyOptions();
    expect(c.read(adsProvider).canRequestAds, isFalse);
  });
}
