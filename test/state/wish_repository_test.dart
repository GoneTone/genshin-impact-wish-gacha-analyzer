import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeCapture implements WishCapture {
  _FakeCapture(this._url);
  final String? _url;

  @override
  CaptureSession start() => CaptureSession(
        result: Future.value(_url),
        cancel: () async {},
      );
}

class _CountingCapture implements WishCapture {
  _CountingCapture(this._inner, this._onCall);
  final WishCapture _inner;
  final void Function() _onCall;

  @override
  CaptureSession start() {
    _onCall();
    return _inner.start();
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('repo_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('bootstrap load 空目錄 → state 為空', () async {
    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(WishStorage(tempDir)),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        httpClientProvider.overrideWithValue(MockClient((_) async {
          throw 'unreachable';
        })),
      ],
    );
    addTearDown(container.dispose);

    // 觸發 build
    final initial = container.read(wishRepositoryProvider);
    expect(initial.activeUid, isNull);
    expect(initial.byUid, isEmpty);

    // 等 bootstrap fire-and-forget 完成
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final after = container.read(wishRepositoryProvider);
    expect(after.activeUid, isNull);
  });

  test('bootstrap load 有 2 個 UID 檔 → activeUid = 較新者', () async {
    final storage = WishStorage(tempDir);
    await storage.save(BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ));
    await storage.save(BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 5, 9), // 較新
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ));

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        httpClientProvider
            .overrideWithValue(MockClient((_) async => http.Response('{}', 200))),
      ],
    );
    addTearDown(container.dispose);

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(wishRepositoryProvider);
    expect(state.knownUids.toSet(), {'A', 'B'});
    expect(state.activeUid, 'B');
  });

  test('AuthExpired 連續 2 次 → UpdateFailed with exact message', () async {
    final storage = WishStorage(tempDir);
    // 先 seed 一個 cached URL，讓 update 直接走 fetch path（跳過 MITM 階段）
    await storage.save(BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ));
    await storage.saveCapturedUrl('A', 'https://example.com/getGachaLog?authkey=expired');

    var fetcherCalls = 0;
    final mock = MockClient((req) async {
      fetcherCalls++;
      // 永遠回 -101 認證失效
      return http.Response(
        '{"retcode":-101,"message":"authkey timeout","data":null}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    var captureCalls = 0;
    final fakeCapture = _FakeCapture('https://example.com/getGachaLog?authkey=alsoexpired');

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWith((ref) {
          // 計數 capture 被呼叫幾次
          return _CountingCapture(fakeCapture, () => captureCalls++);
        }),
        httpClientProvider.overrideWithValue(mock),
      ],
    );
    addTearDown(container.dispose);

    // 等 bootstrap 完成
    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(wishRepositoryProvider).activeUid, 'A');

    // 觸發 update
    await container.read(wishRepositoryProvider.notifier).update();

    final progress = container.read(wishRepositoryProvider).progress;
    expect(progress, isA<UpdateFailed>());
    expect((progress as UpdateFailed).message, '認證持續失效，請重新登入遊戲');
    // capture 應該被叫 1 次（fallback MITM）；cached URL 第一次直接用，沒 MITM
    expect(captureCalls, 1);
    // fetcher 至少被叫過（兩次嘗試都打 mock）
    expect(fetcherCalls, greaterThan(0));
  });

  test('clearProgress 把 progress 重設為 null', () async {
    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(WishStorage(tempDir)),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        httpClientProvider
            .overrideWithValue(MockClient((_) async => http.Response('{}', 200))),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(wishRepositoryProvider.notifier);
    notifier.debugSetProgress(const UpdateFailed('test'));
    expect(container.read(wishRepositoryProvider).progress, isA<UpdateFailed>());

    notifier.clearProgress();
    expect(container.read(wishRepositoryProvider).progress, isNull);
  });
}
