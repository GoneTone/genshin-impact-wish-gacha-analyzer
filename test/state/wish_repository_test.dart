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
