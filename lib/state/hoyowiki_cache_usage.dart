import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

/// Logger 實例（gacha.hoyowiki.usage 命名空間，對齊既有 gacha.hoyowiki.* 樹）。
final _log = Logger('gacha.hoyowiki.usage');

/// HoYoWiki 圖片快取用量分項。
@immutable
class HoYoWikiCacheUsage {
  /// 建立 [HoYoWikiCacheUsage]。
  const HoYoWikiCacheUsage({
    required this.iconBytes,
    required this.galleryBytes,
  });

  /// 物品 icon 圖檔總大小（bytes）。
  final int iconBytes;

  /// 物品 gallery 圖檔總大小（bytes）。
  final int galleryBytes;

  /// icon + gallery 總和。
  int get totalBytes => iconBytes + galleryBytes;
}

/// 掃描 [hoyowikiCacheDirProvider] 目錄，分項計算 icon 與 gallery 圖檔總大小。
///
/// `autoDispose` → 離開設定頁自動釋放，下次進設定頁重新計算。
/// 失敗（權限等）讓 `FutureProvider` 自然進 `AsyncError` 狀態。
final hoyowikiCacheUsageProvider =
    FutureProvider.autoDispose<HoYoWikiCacheUsage>((ref) async {
      final dir = ref.read(hoyowikiCacheDirProvider);
      if (!await dir.exists()) {
        _log.fine('cache dir not exist → zero');
        return const HoYoWikiCacheUsage(iconBytes: 0, galleryBytes: 0);
      }
      var iconBytes = 0;
      var galleryBytes = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final path = entity.path;
        final size = await entity.length();
        if (path.contains('_gallery_')) {
          galleryBytes += size;
        } else if (path.contains('_icon.')) {
          iconBytes += size;
        }
      }
      _log.fine('scan done icon=$iconBytes gallery=$galleryBytes');
      return HoYoWikiCacheUsage(
        iconBytes: iconBytes,
        galleryBytes: galleryBytes,
      );
    });
