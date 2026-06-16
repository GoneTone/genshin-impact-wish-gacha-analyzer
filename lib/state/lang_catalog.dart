import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

/// 名冊儲存層：放在 HoYoWiki 快取目錄下的 `lang_catalog/`。
final langCatalogStorageProvider = Provider<LangCatalogStorage>((ref) {
  final dir = ref.read(hoyowikiCacheDirProvider);
  return LangCatalogStorage(Directory('${dir.path}/lang_catalog'));
});

/// 名冊抓取器。
final langCatalogFetcherProvider = Provider<LangCatalogFetcher>(
  (ref) => LangCatalogFetcher(),
);

/// 名冊解析器（單例，memo 跨更新／轉換沿用）。
final langCatalogServiceProvider = Provider<LangCatalogService>((ref) {
  return LangCatalogService(
    storage: ref.read(langCatalogStorageProvider),
    fetcher: ref.read(langCatalogFetcherProvider),
    clientFactory: () => http.Client(),
  );
});
