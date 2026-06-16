import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_language.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 轉換結果計數（genshin 無 resourceId，故無 backfilledId）。可相加聚合多帳號。
class LangConvertResult {
  /// 建立 [LangConvertResult]。
  const LangConvertResult({
    this.total = 0,
    this.converted = 0,
    this.unresolved = 0,
  });

  /// 在範圍內且 lang != target 的候選筆數。
  final int total;

  /// 成功轉換筆數。
  final int converted;

  /// 無法轉換、保持原狀的筆數。
  final int unresolved;

  /// 逐項相加。
  LangConvertResult operator +(LangConvertResult o) => LangConvertResult(
    total: total + o.total,
    converted: converted + o.converted,
    unresolved: unresolved + o.unresolved,
  );
}

/// 轉換後要寫回 HoYoWikiIndex 的提示，維持類型判定與詳情／icon lookup。
class IndexHint {
  /// 建立 [IndexHint]。
  const IndexHint({
    required this.lang,
    required this.name,
    required this.id,
    required this.menuId,
  });

  /// 目標語言。
  final String lang;

  /// 目標語言的物品名。
  final String name;

  /// hoyowiki_id。
  final String id;

  /// menu_id（2／4）。
  final int menuId;
}

/// 把一份 [BannerStorage] 的非頌願紀錄名稱統一成目標語言。
///
/// 只改 `name`／`lang`，不動 `itemType`（類型顯示走 menu_id，見 spec D8）。
/// 轉不了的紀錄完全保持原狀。
class GachaLanguageConverter {
  /// 建立 [GachaLanguageConverter]；[ensureCatalog] 取得某語言名冊
  /// （生產接 `LangCatalogService.ensure`，測試注入 fake）。
  GachaLanguageConverter({required this.ensureCatalog});

  /// 取得某語言名冊；[forceRefresh] 為 true 時略過快取重抓。
  final Future<LangCatalog> Function(String lang, {bool forceRefresh})
  ensureCatalog;

  /// Logger 實例。
  static final _log = Logger('wish.langconvert');

  /// 轉換 [data] 為 [targetLang]，回傳新存檔、計數與 index 提示。
  Future<
    ({BannerStorage data, LangConvertResult result, List<IndexHint> hints})
  >
  convert(BannerStorage data, String targetLang) async {
    var targetCat = await ensureCatalog(targetLang);

    final srcLangs = <String>{};
    for (final entry in data.banners.entries) {
      if (!convertibleGachaTypes.contains(entry.key)) continue;
      for (final r in entry.value) {
        if (r.lang == targetLang || r.lang.isEmpty) continue;
        srcLangs.add(r.lang);
      }
    }
    final srcCats = <String, LangCatalog>{};
    for (final lang in srcLangs) {
      srcCats[lang] = await ensureCatalog(lang);
    }

    bool resolvable(GachaRecord r) {
      final id = srcCats[r.lang]?.idByName[r.name];
      return id != null && targetCat.byId.containsKey(id);
    }

    final staleDetected =
        isSupportedDataLanguage(targetLang) &&
        data.banners.entries.any(
          (e) =>
              convertibleGachaTypes.contains(e.key) &&
              e.value.any(
                (r) =>
                    r.lang != targetLang &&
                    r.lang.isNotEmpty &&
                    isSupportedDataLanguage(r.lang) &&
                    !resolvable(r),
              ),
        );
    if (staleDetected) {
      _log.info('stale catalog detected, refreshing target=$targetLang');
      targetCat = await ensureCatalog(targetLang, forceRefresh: true);
      for (final lang in srcLangs) {
        if (isSupportedDataLanguage(lang)) {
          srcCats[lang] = await ensureCatalog(lang, forceRefresh: true);
        }
      }
    }

    var result = const LangConvertResult();
    final hints = <IndexHint>[];
    final newBanners = <String, List<GachaRecord>>{};
    data.banners.forEach((key, list) {
      if (!convertibleGachaTypes.contains(key)) {
        newBanners[key] = list;
        return;
      }
      final out = <GachaRecord>[];
      for (final r in list) {
        if (r.lang == targetLang) {
          out.add(r);
          continue;
        }
        result = result + const LangConvertResult(total: 1);
        final id = r.lang.isEmpty ? null : srcCats[r.lang]?.idByName[r.name];
        final target = id == null ? null : targetCat.byId[id];
        if (id != null && target != null) {
          out.add(r.copyWith(name: target.name, lang: targetLang));
          hints.add(
            IndexHint(
              lang: targetLang,
              name: target.name,
              id: id,
              menuId: target.kind,
            ),
          );
          result = result + const LangConvertResult(converted: 1);
        } else {
          out.add(r);
          result = result + const LangConvertResult(unresolved: 1);
        }
      }
      newBanners[key] = out;
    });

    _log.info(
      'converted uid=${sanitizeUid(data.uid)} target=$targetLang '
      'total=${result.total} converted=${result.converted} '
      'unresolved=${result.unresolved}',
    );
    return (
      data: data.copyWith(banners: newBanners),
      result: result,
      hints: hints,
    );
  }
}
