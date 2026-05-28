import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart'
    show httpClientProvider;
import 'package:genshin_impact_wish_gacha_analyzer/state/current_release.dart';

Map<String, dynamic> _releaseJson(String tag, String published) => {
  'tag_name': tag,
  'name': tag,
  'body': '## body for $tag',
  'prerelease': false,
  'draft': false,
  'html_url': 'https://github.com/o/r/releases/tag/$tag',
  'published_at': published,
};

ProviderContainer _container(http.Client client) {
  // Riverpod 3 預設對失敗 provider 做指數退避自動重試（最長 6.4s × N 次），
  // 會把錯誤測試的 await .future 卡到 30s test timeout；測試容器一律
  // 關掉 retry，讓錯誤立刻反映到 AsyncValue 上。
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [httpClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('首次 watch → 打一次 API，state 變 AsyncData', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(_releaseJson('v1.1.0', '2026-05-27T00:00:00Z')),
        200,
      ),
    );
    final container = _container(client);

    final release = await container.read(
      currentReleaseProvider('1.1.0').future,
    );

    expect(release.tagName, 'v1.1.0');
    final state = container.read(currentReleaseProvider('1.1.0'));
    expect(state.hasValue, isTrue);
    expect(state.value?.tagName, 'v1.1.0');
  });

  test('重複 read 同一 version → 不重打 API（FutureProvider.family cache）', () async {
    var callCount = 0;
    final client = MockClient((_) async {
      callCount++;
      return http.Response(
        jsonEncode(_releaseJson('v1.1.0', '2026-05-27T00:00:00Z')),
        200,
      );
    });
    final container = _container(client);

    await container.read(currentReleaseProvider('1.1.0').future);
    await container.read(currentReleaseProvider('1.1.0').future);
    await container.read(currentReleaseProvider('1.1.0').future);

    expect(callCount, 1);
  });

  test('不同 version key → 各自打一次 API', () async {
    final calledFor = <String>[];
    final client = MockClient((req) async {
      calledFor.add(req.url.path);
      final tag = req.url.path.split('/').last;
      return http.Response(
        jsonEncode(_releaseJson(tag, '2026-05-27T00:00:00Z')),
        200,
      );
    });
    final container = _container(client);

    await container.read(currentReleaseProvider('1.0.0').future);
    await container.read(currentReleaseProvider('1.1.0').future);

    expect(calledFor.where((p) => p.endsWith('v1.0.0')).length, 1);
    expect(calledFor.where((p) => p.endsWith('v1.1.0')).length, 1);
  });

  test('ref.invalidate → 重新 fetch', () async {
    var callCount = 0;
    final client = MockClient((_) async {
      callCount++;
      return http.Response(
        jsonEncode(_releaseJson('v1.1.0', '2026-05-27T00:00:00Z')),
        200,
      );
    });
    final container = _container(client);

    await container.read(currentReleaseProvider('1.1.0').future);
    expect(callCount, 1);

    container.invalidate(currentReleaseProvider('1.1.0'));
    await container.read(currentReleaseProvider('1.1.0').future);
    expect(callCount, 2);
  });

  test('service 拋 ReleaseCheckNotFound → state 變 AsyncError', () async {
    final client = MockClient((_) async => http.Response('Not Found', 404));
    final container = _container(client);

    try {
      await container.read(currentReleaseProvider('1.1.0').future);
      fail('expected throw');
    } on ReleaseCheckNotFound catch (e) {
      expect(e.tag, 'v1.1.0');
    }
    final state = container.read(currentReleaseProvider('1.1.0'));
    expect(state.hasError, isTrue);
    expect(state.error, isA<ReleaseCheckNotFound>());
  });

  test('service 拋 ReleaseCheckServer → state 變 AsyncError', () async {
    final client = MockClient((_) async => http.Response('boom', 503));
    final container = _container(client);

    try {
      await container.read(currentReleaseProvider('1.1.0').future);
      fail('expected throw');
    } on ReleaseCheckServer catch (e) {
      expect(e.status, 503);
    }
    expect(
      container.read(currentReleaseProvider('1.1.0')).error,
      isA<ReleaseCheckServer>(),
    );
  });
}
