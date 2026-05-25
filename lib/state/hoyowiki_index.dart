import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:synchronized/synchronized.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

/// HoYoWiki index 儲存層，main.dart 用 `overrideWithValue` 注入。
final hoyowikiIndexStorageProvider = Provider<HoYoWikiIndexStorage>((ref) {
  throw UnimplementedError(
    'hoyowikiIndexStorageProvider must be overridden in main()',
  );
});

/// HoYoWiki 圖檔快取目錄，main.dart 用 `overrideWithValue` 注入。
final hoyowikiCacheDirProvider = Provider<Directory>((ref) {
  throw UnimplementedError(
    'hoyowikiCacheDirProvider must be overridden in main()',
  );
});

/// HoYoWiki API fetcher；預設值即可，無需 override。
final hoyowikiFetcherProvider = Provider<HoYoWikiFetcher>(
  (ref) => HoYoWikiFetcher(),
);

/// 當前載入的 [HoYoWikiIndex]；透過 [HoYoWikiIndexNotifier] 變更。
final hoyowikiIndexProvider =
    NotifierProvider<HoYoWikiIndexNotifier, HoYoWikiIndex>(
      HoYoWikiIndexNotifier.new,
    );

/// 包裝 [HoYoWikiIndexStorage] 的 Riverpod Notifier；mutation 後同步 persist。
class HoYoWikiIndexNotifier extends Notifier<HoYoWikiIndex> {
  static final _log = Logger('gacha.hoyowiki.notifier');

  Completer<void>? _loadCompleter;

  /// 保護 setSearch / setEntry 的 read-modify-write，避免並發 worker 互相覆蓋。
  final _lock = Lock();

  @override
  HoYoWikiIndex build() {
    _loadCompleter = Completer<void>();
    unawaited(_load());
    return const HoYoWikiIndex.empty();
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

  /// 寫入一筆 search 對應（含 [menuId]）並 persist。
  Future<void> setSearch({
    required String name,
    required String lang,
    required String id,
    required int menuId,
  }) async {
    await _lock.synchronized(() async {
      final newSearch = Map<String, String>.from(state.searchMap)
        ..['$lang::$name'] = id;
      final newMenuIds = Map<String, int>.from(state.menuIds)..[id] = menuId;
      final next = HoYoWikiIndex(
        searchMap: newSearch,
        entries: state.entries,
        menuIds: newMenuIds,
      );
      await _saveAndEmit(next);
    });
  }

  /// 寫入一筆 entry 並 persist。
  Future<void> setEntry({
    required String id,
    required HoYoWikiEntry entry,
  }) async {
    await _lock.synchronized(() async {
      final newEntries = Map<String, HoYoWikiEntry>.from(state.entries)
        ..[id] = entry;
      final next = HoYoWikiIndex(
        searchMap: state.searchMap,
        entries: newEntries,
        menuIds: state.menuIds,
      );
      await _saveAndEmit(next);
    });
  }

  /// 在 cache 檔案下載完成後呼叫；state 內容不變但 identity 換新，
  /// 觸發 watch hoyowikiIndexProvider 的 widget 重新 build 以挑到新檔。
  void bumpCacheRevision() {
    state = HoYoWikiIndex(
      searchMap: state.searchMap,
      entries: state.entries,
      menuIds: state.menuIds,
    );
  }

  /// 強制重抓圖片用：清空整個 index 與 cache 目錄。
  /// 呼叫後 state 為 [HoYoWikiIndex.empty]；磁碟側 index 檔已隨 cache
  /// 目錄一併被 [HoYoWikiIndexStorage.wipeCacheDirectory] 刪除（下次
  /// `load()` 因檔案不存在會回空 index）。失敗（權限不足等）直接拋給
  /// 呼叫方 emit `UpdateFailed`。
  Future<void> resetAll() async {
    final storage = ref.read(hoyowikiIndexStorageProvider);
    await storage.clearAll();
    await storage.wipeCacheDirectory();
    if (!ref.mounted) return;
    state = const HoYoWikiIndex.empty();
    _log.info('resetAll: index+cache wiped');
  }

  /// 內部 helper：寫檔 + emit。
  Future<void> _saveAndEmit(HoYoWikiIndex next) async {
    final storage = ref.read(hoyowikiIndexStorageProvider);
    await storage.save(next);
    if (!ref.mounted) return;
    state = next;
  }
}
