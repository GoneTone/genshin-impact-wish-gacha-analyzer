import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_cache_usage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hoyowiki_cache_usage_');
    container = ProviderContainer(
      overrides: [hoyowikiCacheDirProvider.overrideWithValue(tempDir)],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<void> touch(String name, int size) async {
    final f = File('${tempDir.path}/$name');
    await f.writeAsBytes(List<int>.filled(size, 0));
  }

  test('空目錄 → 0 / 0', () async {
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 0);
    expect(usage.galleryBytes, 0);
    expect(usage.totalBytes, 0);
  });

  test('只 icon', () async {
    await touch('abc_icon.png', 1234);
    await touch('def_icon.jpg', 4321);
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 1234 + 4321);
    expect(usage.galleryBytes, 0);
  });

  test('只 gallery', () async {
    await touch('abc_gallery_aaaaaaaaaaaa.png', 5000);
    await touch('def_gallery_bbbbbbbbbbbb.jpg', 6000);
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 0);
    expect(usage.galleryBytes, 5000 + 6000);
  });

  test('混合 + 其他檔案被忽略', () async {
    await touch('abc_icon.png', 100);
    await touch('abc_gallery_xxxxxxxxxxxx.webp', 200);
    await touch('hoyowiki_index.json', 999); // index JSON 不算
    await touch('readme.txt', 50); // 其他檔不算
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 100);
    expect(usage.galleryBytes, 200);
    expect(usage.totalBytes, 300);
  });

  test('cache 目錄不存在 → 0 / 0(不拋例外)', () async {
    await tempDir.delete(recursive: true);
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 0);
    expect(usage.galleryBytes, 0);
  });
}
