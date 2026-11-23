import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/play_update.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

http.Response _ok(List<Map<String, dynamic>> body) =>
    http.Response(jsonEncode(body), 200);

Map<String, dynamic> _release(String tag, String published) => {
  'tag_name': tag,
  'name': '',
  'body': '',
  'prerelease': false,
  'draft': false,
  'html_url': 'https://example.com/$tag',
  'published_at': published,
};

ProviderContainer _container({
  required String currentVersion,
  required http.Client client,
  Map<String, Object> prefs = const {},
}) {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
  final container = ProviderContainer(
    overrides: [
      appVersionProvider.overrideWithValue(currentVersion),
      httpClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 測試用 [PlayUpdateGateway]：回傳固定 [info]，[error] 非 null 時改拋出。
class _FakePlayGateway implements PlayUpdateGateway {
  /// 建立 [_FakePlayGateway]。
  _FakePlayGateway({this.info, this.error});

  /// check() 回傳的資訊。
  final PlayUpdateInfo? info;

  /// check() 要拋出的例外。
  final Object? error;

  @override
  Future<PlayUpdateInfo> check() async {
    if (error != null) throw error!;
    return info!;
  }

  /// downloadFlexible() 被呼叫的次數。
  int downloads = 0;

  @override
  Future<PlayDownloadResult> downloadFlexible() async {
    downloads++;
    return PlayDownloadResult.downloaded;
  }

  @override
  Future<void> completeFlexible() async {}
}

/// 非 Android 時不該被碰到的 [PlayUpdateGateway]：任何呼叫都記數並讓測試失敗。
class _ForbiddenPlayGateway implements PlayUpdateGateway {
  /// 任一方法被呼叫的次數；Android 分支的 catch 會吞掉 fail()，所以另外記數。
  int calls = 0;

  /// 記一次呼叫並讓測試失敗。
  Never _forbidden(String method) {
    calls++;
    fail('PlayUpdateGateway.$method must not be called on non-Android');
  }

  @override
  Future<PlayUpdateInfo> check() async => _forbidden('check');

  @override
  Future<PlayDownloadResult> downloadFlexible() async =>
      _forbidden('downloadFlexible');

  @override
  Future<void> completeFlexible() async => _forbidden('completeFlexible');
}

/// 建立 Android 情境的 container：Play 回報 [gateway]，GitHub 走 [client]。
ProviderContainer _androidContainer({
  required PlayUpdateGateway gateway,
  required http.Client client,
  Map<String, Object> prefs = const {},
}) {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
  final container = ProviderContainer(
    overrides: [
      appVersionProvider.overrideWithValue('1.8.0'),
      httpClientProvider.overrideWithValue(client),
      isAndroidProvider.overrideWithValue(true),
      playUpdateGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Play 回報有 v1.9.0 可更新。
const _playV190 = PlayUpdateInfo(
  updateAvailability: UpdateAvailability.updateAvailable,
  availableVersionCode: 1090099,
  flexibleAllowed: true,
);

/// 重新開啟 App 時，Play 回報開發者觸發的 v1.9.0 更新處於 [status]。
PlayUpdateInfo _inProgress(InstallStatus status) => PlayUpdateInfo(
  updateAvailability: UpdateAvailability.developerTriggeredUpdateInProgress,
  availableVersionCode: 1090099,
  flexibleAllowed: false,
  installStatus: status,
);

/// GitHub 有 v1.10.0、v1.9.0、v1.8.2 三個 release。
MockClient _githubThree() => MockClient(
  (_) async => _ok([
    _release('v1.10.0', '2026-06-03T00:00:00Z'),
    _release('v1.9.0', '2026-06-02T00:00:00Z'),
    _release('v1.8.2', '2026-06-01T00:00:00Z'),
  ]),
);

void main() {
  test('初始 state = ReleaseIdle', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => _ok([])),
    );
    expect(container.read(appReleaseProvider), isA<ReleaseIdle>());
  });

  test('check(manual: true) 有新版 → ReleaseAvailable', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient(
        (_) async => _ok([_release('v1.2.0', '2026-05-13T00:00:00Z')]),
      ),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);

    final state = container.read(appReleaseProvider);
    expect(state, isA<ReleaseAvailable>());
    expect((state as ReleaseAvailable).releases.first.tagName, 'v1.2.0');
  });

  test('check(manual: false) 有新版 → ReleaseAvailable', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient(
        (_) async => _ok([_release('v1.2.0', '2026-05-13T00:00:00Z')]),
      ),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: false);

    expect(container.read(appReleaseProvider), isA<ReleaseAvailable>());
  });

  test(
    'check(manual: false) 且最新 tag == skippedReleaseTag → 維持 ReleaseIdle',
    () async {
      final container = _container(
        currentVersion: '1.0.0',
        client: MockClient(
          (_) async => _ok([_release('v1.2.0', '2026-05-13T00:00:00Z')]),
        ),
        prefs: const {'pref.skippedReleaseTag': 'v1.2.0'},
      );
      await container.read(settingsProvider.notifier).waitForLoad();

      await container.read(appReleaseProvider.notifier).check(manual: false);

      expect(container.read(appReleaseProvider), isA<ReleaseIdle>());
    },
  );

  test('check(manual: true) 無視 skippedReleaseTag → ReleaseAvailable', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient(
        (_) async => _ok([_release('v1.2.0', '2026-05-13T00:00:00Z')]),
      ),
      prefs: const {'pref.skippedReleaseTag': 'v1.2.0'},
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);

    expect(container.read(appReleaseProvider), isA<ReleaseAvailable>());
  });

  test('check(manual: true) — 空 list → ReleaseUpToDate', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => _ok([])),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);

    expect(container.read(appReleaseProvider), isA<ReleaseUpToDate>());
  });

  test(
    'check(manual: false) — 空 list → 維持 ReleaseIdle (auto path 靜默)',
    () async {
      final container = _container(
        currentVersion: '1.0.0',
        client: MockClient((_) async => _ok([])),
      );
      await container.read(settingsProvider.notifier).waitForLoad();

      await container.read(appReleaseProvider.notifier).check(manual: false);

      expect(container.read(appReleaseProvider), isA<ReleaseIdle>());
    },
  );

  test('check(manual: true) error → ReleaseCheckFailed (含 token)', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => http.Response('boom', 503)),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);

    final state = container.read(appReleaseProvider);
    expect(state, isA<ReleaseCheckFailed>());
    expect((state as ReleaseCheckFailed).reason, 'server:503');
  });

  test('check(manual: false) error → 維持 ReleaseIdle，靜默', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => http.Response('boom', 503)),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: false);

    expect(container.read(appReleaseProvider), isA<ReleaseIdle>());
  });

  test('skipVersion 寫入 settings.skippedReleaseTag', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => _ok([])),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).skipVersion('v1.5.0');

    expect(container.read(settingsProvider).skippedReleaseTag, 'v1.5.0');
  });

  test('error token: network', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async {
        throw http.ClientException('offline');
      }),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);
    final state = container.read(appReleaseProvider);
    expect((state as ReleaseCheckFailed).reason, 'network');
  });

  test('error token: rateLimited', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient(
        (_) async => http.Response(
          'forbidden',
          403,
          headers: const {'x-ratelimit-remaining': '0'},
        ),
      ),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);
    final state = container.read(appReleaseProvider);
    expect((state as ReleaseCheckFailed).reason, 'rateLimited');
  });

  test('check 在 ReleaseChecking 期間 re-entrant 呼叫不會重複觸發', () async {
    var callCount = 0;
    final client = MockClient((_) async {
      callCount++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _ok([]);
    });
    final container = _container(currentVersion: '1.0.0', client: client);
    await container.read(settingsProvider.notifier).waitForLoad();

    final notifier = container.read(appReleaseProvider.notifier);
    // 並行呼叫兩次：第二次應在第一次完成前被擋下
    final f1 = notifier.check(manual: true);
    final f2 = notifier.check(manual: true);
    await Future.wait([f1, f2]);

    expect(callCount, 1);
    expect(container.read(appReleaseProvider), isA<ReleaseUpToDate>());
  });

  test(
    'non-Android never touches the Play gateway and keeps GitHub results',
    () async {
      final gateway = _ForbiddenPlayGateway();
      var githubCalls = 0;
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          appVersionProvider.overrideWithValue('1.8.0'),
          httpClientProvider.overrideWithValue(
            MockClient((_) async {
              githubCalls++;
              return _ok([
                _release('v1.10.0', '2026-06-03T00:00:00Z'),
                _release('v1.9.0', '2026-06-02T00:00:00Z'),
              ]);
            }),
          ),
          isAndroidProvider.overrideWithValue(false),
          playUpdateGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).waitForLoad();
      final notifier = container.read(appReleaseProvider.notifier);

      for (final manual in [false, true]) {
        await notifier.check(manual: manual);
        final state = container.read(appReleaseProvider) as ReleaseAvailable;
        expect(state.playTag, isNull);
        expect(state.releases.map((r) => r.tagName), ['v1.10.0', 'v1.9.0']);
      }
      expect(githubCalls, 2);
      expect(gateway.calls, 0);
    },
  );

  group('android (Play)', () {
    test(
      'play update + github notes → available with notes up to the play version',
      () async {
        final container = _androidContainer(
          gateway: _FakePlayGateway(info: _playV190),
          client: _githubThree(),
        );
        await container.read(settingsProvider.notifier).waitForLoad();

        await container.read(appReleaseProvider.notifier).check(manual: true);

        final state = container.read(appReleaseProvider) as ReleaseAvailable;
        expect(state.playTag, 'v1.9.0');
        expect(state.releases.map((r) => r.tagName), ['v1.9.0', 'v1.8.2']);
      },
    );

    test('play update + github failure → available without notes', () async {
      final container = _androidContainer(
        gateway: _FakePlayGateway(info: _playV190),
        client: MockClient((_) async => http.Response('', 500)),
      );
      await container.read(settingsProvider.notifier).waitForLoad();

      await container.read(appReleaseProvider.notifier).check(manual: false);

      final state = container.read(appReleaseProvider) as ReleaseAvailable;
      expect(state.releases, isEmpty);
      expect(state.playTag, 'v1.9.0');
    });

    test('play reports no update but github has one → no prompt', () async {
      const none = PlayUpdateInfo(
        updateAvailability: UpdateAvailability.updateNotAvailable,
        availableVersionCode: null,
        flexibleAllowed: false,
      );
      final container = _androidContainer(
        gateway: _FakePlayGateway(info: none),
        client: _githubThree(),
      );
      await container.read(settingsProvider.notifier).waitForLoad();
      final notifier = container.read(appReleaseProvider.notifier);

      await notifier.check(manual: true);
      expect(container.read(appReleaseProvider), isA<ReleaseUpToDate>());

      await notifier.check(manual: false);
      expect(container.read(appReleaseProvider), isA<ReleaseIdle>());
    });

    test('non-play install: silent on auto, failure on manual', () async {
      final container = _androidContainer(
        gateway: _FakePlayGateway(
          error: PlatformException(code: 'TASK_FAILURE'),
        ),
        client: _githubThree(),
      );
      await container.read(settingsProvider.notifier).waitForLoad();
      final warnings = <LogRecord>[];
      final sub = Logger.root.onRecord.listen((r) {
        if (r.level == Level.WARNING) warnings.add(r);
      });
      addTearDown(sub.cancel);
      final notifier = container.read(appReleaseProvider.notifier);

      await notifier.check(manual: false);
      expect(container.read(appReleaseProvider), isA<ReleaseIdle>());

      await notifier.check(manual: true);
      expect(
        (container.read(appReleaseProvider) as ReleaseCheckFailed).reason,
        'play',
      );
      expect(
        warnings.where(
          (r) =>
              r.message == 'play update check failed' &&
              r.error is PlatformException,
        ),
        hasLength(2),
      );
    });

    test('flexible update not allowed is still prompted', () async {
      const immediateOnly = PlayUpdateInfo(
        updateAvailability: UpdateAvailability.updateAvailable,
        availableVersionCode: 1090099,
        flexibleAllowed: false,
      );
      final container = _androidContainer(
        gateway: _FakePlayGateway(info: immediateOnly),
        client: _githubThree(),
      );
      await container.read(settingsProvider.notifier).waitForLoad();

      await container.read(appReleaseProvider.notifier).check(manual: false);

      final state = container.read(appReleaseProvider) as ReleaseAvailable;
      expect(state.playTag, 'v1.9.0');
    });

    test('skipped play version is not prompted on auto check', () async {
      final container = _androidContainer(
        gateway: _FakePlayGateway(info: _playV190),
        // GitHub 失敗 → releases 為空，只有比對 Play 換算的 tag 才能略過
        client: MockClient((_) async => http.Response('', 500)),
        prefs: {'pref.skippedReleaseTag': 'v1.9.0'},
      );
      await container.read(settingsProvider.notifier).waitForLoad();
      final notifier = container.read(appReleaseProvider.notifier);

      await notifier.check(manual: false);
      expect(container.read(appReleaseProvider), isA<ReleaseIdle>());

      await notifier.check(manual: true);
      expect(container.read(appReleaseProvider), isA<ReleaseAvailable>());
    });

    test('undecodable play version code → no prompt', () async {
      const bad = PlayUpdateInfo(
        updateAvailability: UpdateAvailability.updateAvailable,
        availableVersionCode: 17,
        flexibleAllowed: true,
      );
      final container = _androidContainer(
        gateway: _FakePlayGateway(info: bad),
        client: _githubThree(),
      );
      await container.read(settingsProvider.notifier).waitForLoad();
      final warnings = <String>[];
      final sub = Logger.root.onRecord.listen((r) {
        if (r.level == Level.WARNING) warnings.add(r.message);
      });
      addTearDown(sub.cancel);
      final notifier = container.read(appReleaseProvider.notifier);

      await notifier.check(manual: true);
      expect(container.read(appReleaseProvider), isA<ReleaseUpToDate>());

      await notifier.check(manual: false);
      expect(container.read(appReleaseProvider), isA<ReleaseIdle>());

      expect(
        warnings.where((m) => m.contains('has no tag mapping')),
        hasLength(2),
      );
    });

    test(
      'developer-triggered update in progress is not "up to date"',
      () async {
        final container = _androidContainer(
          gateway: _FakePlayGateway(info: _inProgress(InstallStatus.canceled)),
          client: _githubThree(),
        );
        await container.read(settingsProvider.notifier).waitForLoad();

        await container.read(appReleaseProvider.notifier).check(manual: true);

        expect(container.read(appReleaseProvider), isA<ReleaseAvailable>());
      },
    );

    test(
      'github throws a non-ReleaseCheckError → still prompts without notes',
      () async {
        final container = _androidContainer(
          gateway: _FakePlayGateway(info: _playV190),
          client: MockClient(
            (_) async => throw const HandshakeException('bad cert'),
          ),
        );
        await container.read(settingsProvider.notifier).waitForLoad();

        await container.read(appReleaseProvider.notifier).check(manual: false);

        final state = container.read(appReleaseProvider) as ReleaseAvailable;
        expect(state.releases, isEmpty);
        expect(state.playTag, 'v1.9.0');
      },
    );
  });
}
