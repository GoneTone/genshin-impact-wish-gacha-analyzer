// test/services/app_release_checker_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';

http.Response _ok(List<Map<String, dynamic>> body) =>
    http.Response(jsonEncode(body), 200);

Map<String, dynamic> _release({
  required String tag,
  required String published,
  bool prerelease = false,
  bool draft = false,
  String name = '',
  String body = '',
  String htmlUrl = 'https://example.com',
}) => {
  'tag_name': tag,
  'name': name,
  'body': body,
  'prerelease': prerelease,
  'draft': draft,
  'html_url': htmlUrl,
  'published_at': published,
};

void main() {
  group('fetchNewerReleases — happy path', () {
    test('回傳新到舊的、比 currentVersion 新的 release', () async {
      final client = MockClient(
        (req) async => _ok([
          _release(tag: 'v1.2.0', published: '2026-05-13T00:00:00Z'),
          _release(tag: 'v1.1.0', published: '2026-05-10T00:00:00Z'),
          _release(tag: 'v1.0.0', published: '2026-05-01T00:00:00Z'),
        ]),
      );
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result.map((r) => r.tagName), ['v1.2.0', 'v1.1.0']);
      expect(result[0].version, '1.2.0');
      expect(result[0].publishedAt, DateTime.utc(2026, 5, 13));
    });
  });

  group('fetchNewerReleases — filtering', () {
    test('過濾 prerelease 與 draft', () async {
      final client = MockClient(
        (_) async => _ok([
          _release(tag: 'v1.2.0', published: '2026-05-13T00:00:00Z'),
          _release(
            tag: 'v1.3.0',
            published: '2026-05-14T00:00:00Z',
            prerelease: true,
          ),
          _release(
            tag: 'v1.4.0',
            published: '2026-05-15T00:00:00Z',
            draft: true,
          ),
        ]),
      );
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result.map((r) => r.tagName), ['v1.2.0']);
    });

    test('tag 格式錯（"weird-tag"）→ 該筆跳過，其他正常', () async {
      final client = MockClient(
        (_) async => _ok([
          _release(tag: 'v1.2.0', published: '2026-05-13T00:00:00Z'),
          _release(tag: 'weird-tag', published: '2026-05-14T00:00:00Z'),
        ]),
      );
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result.map((r) => r.tagName), ['v1.2.0']);
    });

    test('current = 最新 → 回空 list', () async {
      final client = MockClient(
        (_) async =>
            _ok([_release(tag: 'v1.0.0', published: '2026-05-13T00:00:00Z')]),
      );
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result, isEmpty);
    });

    test('tag 無 "v" 前綴也可被 parse', () async {
      final client = MockClient(
        (_) async =>
            _ok([_release(tag: '1.2.0', published: '2026-05-13T00:00:00Z')]),
      );
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result.map((r) => r.tagName), ['1.2.0']);
      expect(result[0].version, '1.2.0');
    });
  });

  group('fetchNewerReleases — errors', () {
    test('200 但 body 非 JSON list → ReleaseCheckFormat', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'oops': 1}), 200),
      );
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });

    test('200 但 body 不是 JSON → ReleaseCheckFormat', () async {
      final client = MockClient((_) async => http.Response('<html/>', 200));
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });

    test('503 → ReleaseCheckServer(503)', () async {
      final client = MockClient((_) async => http.Response('boom', 503));
      try {
        await fetchNewerReleases(currentVersion: '1.0.0', client: client);
        fail('expected throw');
      } on ReleaseCheckServer catch (e) {
        expect(e.status, 503);
      }
    });

    test('403 + x-ratelimit-remaining: 0 → ReleaseCheckRateLimited', () async {
      final client = MockClient(
        (_) async => http.Response(
          'forbidden',
          403,
          headers: const {'x-ratelimit-remaining': '0'},
        ),
      );
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckRateLimited>()),
      );
    });

    test('403 但 ratelimit 還有 → ReleaseCheckServer(403)', () async {
      final client = MockClient(
        (_) async => http.Response(
          'forbidden',
          403,
          headers: const {'x-ratelimit-remaining': '42'},
        ),
      );
      try {
        await fetchNewerReleases(currentVersion: '1.0.0', client: client);
        fail('expected throw');
      } on ReleaseCheckServer catch (e) {
        expect(e.status, 403);
      }
    });

    test('SocketException → ReleaseCheckNetwork', () async {
      final client = MockClient((_) async {
        throw const SocketException('offline');
      });
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckNetwork>()),
      );
    });

    test('http.ClientException → ReleaseCheckNetwork', () async {
      final client = MockClient((_) async {
        throw http.ClientException('connection reset');
      });
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckNetwork>()),
      );
    });

    test(
      'TimeoutException 觸發 → ReleaseCheckTimeout',
      () async {
        final client = MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 15));
          return http.Response('[]', 200);
        });
        expect(
          () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
          throwsA(isA<ReleaseCheckTimeout>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test('currentVersion 無法 parse → ReleaseCheckFormat', () async {
      final client = MockClient((_) async => _ok([]));
      expect(
        () =>
            fetchNewerReleases(currentVersion: 'not-a-version', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });
  });
}
