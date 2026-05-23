import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

/// HoyoWiki index 儲存層，main.dart 用 `overrideWithValue` 注入。
final hoyowikiIndexStorageProvider = Provider<HoyoWikiIndexStorage>((ref) {
  throw UnimplementedError(
    'hoyowikiIndexStorageProvider must be overridden in main()',
  );
});

/// HoyoWiki 圖檔快取目錄，main.dart 用 `overrideWithValue` 注入。
final hoyowikiCacheDirProvider = Provider<Directory>((ref) {
  throw UnimplementedError(
    'hoyowikiCacheDirProvider must be overridden in main()',
  );
});

/// HoyoWiki API fetcher；預設值即可，無需 override。
final hoyowikiFetcherProvider = Provider<HoyoWikiFetcher>(
  (ref) => HoyoWikiFetcher(),
);

/// 當前載入的 [HoyoWikiIndex]；透過 [HoyoWikiIndexNotifier] 變更。
final hoyowikiIndexProvider =
    NotifierProvider<HoyoWikiIndexNotifier, HoyoWikiIndex>(
      HoyoWikiIndexNotifier.new,
    );

/// 包裝 [HoyoWikiIndexStorage] 的 Riverpod Notifier；mutation 後同步 persist。
class HoyoWikiIndexNotifier extends Notifier<HoyoWikiIndex> {
  static final _log = Logger('wish.hoyowiki.notifier');

  Completer<void>? _loadCompleter;

  @override
  HoyoWikiIndex build() {
    _loadCompleter = Completer<void>();
    unawaited(_load());
    return const HoyoWikiIndex.empty();
  }

  /// 從 storage 載入並 emit 給 state。
  Future<void> _load() async {
    try {
      final storage = ref.read(hoyowikiIndexStorageProvider);
      final loaded = await storage.load();
      if (!ref.mounted) return;
      state = loaded;
    } catch (e, st) {
      _log.warning('load failed', e, st);
    } finally {
      _loadCompleter?.complete();
    }
  }

  /// 等待初始 load 結束。
  Future<void> waitForLoad() => _loadCompleter?.future ?? Future.value();

  /// 寫入一筆 search 對應並 persist。
  Future<void> setSearch({
    required String name,
    required String lang,
    required String id,
  }) async {
    final newSearch = Map<String, String>.from(state.searchMap)
      ..['$lang::$name'] = id;
    final next = HoyoWikiIndex(searchMap: newSearch, entries: state.entries);
    await _saveAndEmit(next);
  }

  /// 寫入一筆 entry 並 persist。
  Future<void> setEntry({
    required String id,
    required HoyoWikiEntry entry,
  }) async {
    final newEntries = Map<String, HoyoWikiEntry>.from(state.entries)
      ..[id] = entry;
    final next = HoyoWikiIndex(searchMap: state.searchMap, entries: newEntries);
    await _saveAndEmit(next);
  }

  /// 在 cache 檔案下載完成後呼叫；state 內容不變但 identity 換新，
  /// 觸發 watch hoyowikiIndexProvider 的 widget 重新 build 以挑到新檔。
  void bumpCacheRevision() {
    state = HoyoWikiIndex(searchMap: state.searchMap, entries: state.entries);
  }

  /// 內部 helper：寫檔 + emit。
  Future<void> _saveAndEmit(HoyoWikiIndex next) async {
    final storage = ref.read(hoyowikiIndexStorageProvider);
    await storage.save(next);
    if (!ref.mounted) return;
    state = next;
  }
}
