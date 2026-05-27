import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

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
      final log = Logger('gacha.hoyowiki.usage');
      final dir = ref.watch(hoyowikiCacheDirProvider);
      if (!await dir.exists()) {
        log.fine('cache dir not exist → zero');
        return const HoYoWikiCacheUsage(iconBytes: 0, galleryBytes: 0);
      }
      var iconBytes = 0;
      var galleryBytes = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final base = p.basename(entity.path);
        final size = await entity.length();
        if (base.contains('_gallery_')) {
          galleryBytes += size;
        } else if (base.contains('_icon.')) {
          iconBytes += size;
        }
      }
      log.fine('scan done icon=$iconBytes gallery=$galleryBytes');
      return HoYoWikiCacheUsage(
        iconBytes: iconBytes,
        galleryBytes: galleryBytes,
      );
    });
