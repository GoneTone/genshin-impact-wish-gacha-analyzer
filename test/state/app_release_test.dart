// test/state/app_release_test.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
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
}
