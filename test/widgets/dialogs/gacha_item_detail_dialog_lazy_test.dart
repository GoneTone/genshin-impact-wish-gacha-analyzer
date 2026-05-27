import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';

/// 假 fetcher：可注入「永遠成功」「永遠失敗」「第一次失敗第二次成功」三種模式。
class _FakeFetcher extends HoYoWikiFetcher {
  /// 建立 [_FakeFetcher]，以 [behaviorFor] 指定每個 URL 的回應行為。
  _FakeFetcher({required this.behaviorFor}) : super();

  /// url → 該 url 該如何回應。回 null = downloadImage 回 null；回 bytes = 成功。
  final Future<Uint8List?> Function(String url, int callCount) behaviorFor;

  /// 各 url 被呼叫的次數，key 為 url。
  final Map<String, int> _calls = {};

  @override
  Future<Uint8List?> downloadImage(String url, http.Client client) {
    final n = (_calls[url] = (_calls[url] ?? 0) + 1);
    return behaviorFor(url, n);
  }
}

/// 建立測試用 [GachaRecord]。
GachaRecord _rec({String name = 'X'}) => GachaRecord(
  id: '1',
  uid: '1',
  gachaType: '301',
  name: name,
  itemType: 'Character',
  rankType: 5,
  time: DateTime(2026, 5, 27),
  lang: 'en-us',
);

/// 在 [dir] 建立假 icon 檔（PNG magic bytes）。
Future<File> _touchIcon(Directory dir, String id) async {
  final f = File('${dir.path}/${id}_icon.png');
  await f.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);
  return f;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dialog_lazy_test_');
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  /// 建立並初始化 [ProviderContainer]，覆寫 fetcher。
  /// 必須在 [tester.runAsync] 內呼叫，因為 [waitForLoad] 涉及真實磁碟 I/O。
  Future<ProviderContainer> setupContainer(
    _FakeFetcher fetcher,
    Directory dir,
  ) async {
    final c = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(dir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(dir),
        hoyowikiFetcherProvider.overrideWithValue(fetcher),
      ],
    );
    await c.read(hoyowikiIndexProvider.notifier).waitForLoad();
    return c;
  }

  /// 在 index 中植入含 gallery 的 entry（id=x1，picUrl + list[0]）。
  Future<void> seedEntry(ProviderContainer c) async {
    final n = c.read(hoyowikiIndexProvider.notifier);
    await n.setSearch(name: 'X', lang: 'en-us', id: 'x1', menuId: 2);
    await n.mergeEntry(
      id: 'x1',
      lang: 'en-us',
      fetched: HoYoWikiEntryFetched(
        iconUrl: 'https://cdn/x1_icon.png',
        page: HoYoWikiPageData(
          gallery: const HoYoWikiGalleryData(
            picUrl: 'https://cdn/x1_pic.png',
            list: [
              HoYoWikiGalleryItem(
                id: 'g1',
                key: 'Idle',
                imgUrl: 'https://cdn/x1_g1.gif',
                imgDescHtml: '',
              ),
            ],
          ),
          desc: '',
          tags: [],
        ),
      ),
    );
  }

  /// pump dialog 並讓真實 async（disk write、fake fetcher）完成。
  /// 使用 runAsync + pump(duration) 而非 pumpAndSettle，因為 setState 呼叫
  /// 會持續觸發新 frame，導致 pumpAndSettle 無限循環。
  Future<void> pumpDialogAndSettle(
    WidgetTester tester,
    ProviderContainer c,
    GachaRecord r,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      showDialog<void>(
        context: nav.context,
        builder: (_) => GachaItemDetailDialog(record: r),
      ),
    );
    await tester.pump(); // dialog 顯示，build() 執行，addPostFrameCallback 排程
    await tester.pump(); // postFrameCallback 觸發，_fetchAndCache 開始（unawaited）
    // runAsync 讓 fake fetcher + file.writeAsBytes 在真實事件迴圈完成。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(); // setState(_GalleryReady) 重繪
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('initState 為每個 gallery URL 觸發 fetch', (tester) async {
    final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = await setupContainer(fetcher, tempDir);
      addTearDown(c.dispose);
      await seedEntry(c);
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialogAndSettle(tester, c, _rec());

    // 2 個 gallery URL（picUrl + list[0]）應各被打一次
    expect(fetcher._calls['https://cdn/x1_pic.png'], 1);
    expect(fetcher._calls['https://cdn/x1_g1.gif'], 1);
  });

  testWidgets('loading → ready：bytes 回來後寫入 cache 並顯示 Image.file', (
    tester,
  ) async {
    final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = await setupContainer(fetcher, tempDir);
      addTearDown(c.dispose);
      await seedEntry(c);
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialogAndSettle(tester, c, _rec());

    final dir = tempDir.listSync().whereType<File>().toList();
    expect(
      dir.any((f) => f.path.contains('_gallery_')),
      isTrue,
      reason: 'lazy fetch 後 gallery cache 檔應存在',
    );
  });

  testWidgets('downloadImage 回 null → UI 顯示重試按鈕', (tester) async {
    final fetcher = _FakeFetcher(behaviorFor: (url, n) async => null);
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = await setupContainer(fetcher, tempDir);
      addTearDown(c.dispose);
      await seedEntry(c);
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialogAndSettle(tester, c, _rec());

    expect(find.byIcon(Icons.refresh), findsWidgets);
  });

  testWidgets('重試：第一次 null 第二次成功', (tester) async {
    final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    final fetcher = _FakeFetcher(
      behaviorFor: (url, n) async => n == 1 ? null : fakeBytes,
    );
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = await setupContainer(fetcher, tempDir);
      addTearDown(c.dispose);
      await seedEntry(c);
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialogAndSettle(tester, c, _rec());
    expect(find.byIcon(Icons.refresh), findsWidgets);

    // 點重試按鈕（list[0] 的 Idle chip 是預設選中的第一個）
    await tester.tap(find.byIcon(Icons.refresh).first);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('dispose race：close dialog 期間 fetch 未完成，不拋例外', (tester) async {
    final completer = Completer<Uint8List?>();
    final fetcher = _FakeFetcher(behaviorFor: (url, n) => completer.future);
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = await setupContainer(fetcher, tempDir);
      addTearDown(c.dispose);
      await seedEntry(c);
      await _touchIcon(tempDir, 'x1');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      showDialog<void>(
        context: nav.context,
        builder: (_) => GachaItemDetailDialog(record: _rec()),
      ),
    );
    await tester.pump();
    await tester.pump();

    // dialog 還在 loading 狀態（completer 未完成），此時關閉 dialog
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // fetch 完成後不應拋例外（因為 !mounted 早退）
    await tester.runAsync(() async {
      completer.complete(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
