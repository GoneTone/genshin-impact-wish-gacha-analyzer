import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

final _log = Logger('gacha.hoyowiki.preload');

/// 提供分享圖 sync pipeline 用的預解碼 icon [ui.Image] map（key = hoyowiki_id）。
class PreloadedHoyoWikiImages extends InheritedWidget {
  /// 建立 [PreloadedHoyoWikiImages]。
  const PreloadedHoyoWikiImages({
    super.key,
    required this.images,
    required super.child,
  });

  /// hoyowiki_id → 預解碼的 [ui.Image]（已 owned；render 結束需 dispose）。
  final Map<String, ui.Image> images;

  /// 從祖先 [PreloadedHoyoWikiImages] 取得；不存在回 null。
  static PreloadedHoyoWikiImages? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreloadedHoyoWikiImages>();

  @override
  bool updateShouldNotify(PreloadedHoyoWikiImages oldWidget) =>
      !identical(images, oldWidget.images);
}

/// 預解碼 [records] 對應的 hoyowiki icon cache 檔成 [ui.Image] map。
///
/// 缺 cache 或 lookup miss 的 record 直接跳過（分享圖內走 placeholder）。
/// 回傳的 map 須由 caller 在 render 結束後呼叫 [disposePreloadedHoyoWikiImages]
/// 釋放 native 資源。
Future<Map<String, ui.Image>> preloadHoyoWikiImages({
  required HoyoWikiIndex index,
  required Directory cacheDir,
  required Iterable<GachaRecord> records,
}) async {
  final out = <String, ui.Image>{};
  final seenIds = <String>{};

  for (final r in records) {
    if (r.gachaType == '2000' || r.gachaType == '1000') continue;
    final id = index.lookupId(name: r.name, lang: r.lang);
    if (id == null || !seenIds.add(id)) continue;
    final entry = index.lookupEntry(id);
    final url = entry?.iconUrl;
    if (entry == null || url == null || url.isEmpty) continue;
    final file = hoyowikiCacheFile(
      baseDir: cacheDir,
      id: id,
      kind: HoyoWikiImageKind.icon,
      url: url,
    );
    if (!file.existsSync()) continue;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      out[id] = frame.image;
    } catch (e, st) {
      _log.warning('preload decode failed id=$id', e, st);
    }
  }
  return out;
}

/// dispose 由 [preloadHoyoWikiImages] 產出的所有 [ui.Image]。
void disposePreloadedHoyoWikiImages(Map<String, ui.Image> images) {
  for (final img in images.values) {
    img.dispose();
  }
}
