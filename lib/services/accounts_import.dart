import 'dart:convert';

import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';

/// Logger 實例（帳號匯入/匯出）。
final _log = Logger('accounts.io');

/// 匯入檔不是由本軟體匯出（`app` 識別碼不符，或舊檔卡池代碼非原神已知集合）時拋出。
class ForeignBundleException implements Exception {
  /// 建立 [ForeignBundleException]。
  const ForeignBundleException();

  @override
  String toString() => 'ForeignBundleException';
}

/// 把 JSON 文字解析回 [AccountsBundle]。
/// 版本號過新時拋出 [UnsupportedSchemaVersionException]；
/// 非本軟體產生的備份時拋出 [ForeignBundleException]；
/// 其餘結構／型別不符時統一拋出 [FormatException]，給 UI 顯示用。
AccountsBundle importAccounts(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (e) {
    _log.warning('import failed: invalid JSON ($e)');
    throw const FormatException('Invalid JSON');
  }
  if (raw is! Map<String, dynamic>) {
    _log.warning('import failed: top-level not an object');
    throw const FormatException('Top-level value must be an object');
  }

  final app = raw['app'];
  final Map<String, dynamic> prepared;
  if (app is String) {
    if (app != accountsBundleAppId) {
      _log.warning('import failed: foreign bundle (app=$app)');
      throw const ForeignBundleException();
    }
    prepared = raw; // 本軟體自己的檔，完整信任、不過濾
  } else {
    prepared = _screenLegacyBundle(raw);
  }

  try {
    return AccountsBundle.fromJson(prepared);
  } on UnsupportedSchemaVersionException catch (e) {
    _log.warning('import failed: unsupported schema version ${e.version}');
    rethrow;
  } on FormatException catch (e) {
    _log.warning('import failed: ${e.message}');
    rethrow;
  } catch (e, st) {
    _log.warning('import failed: parse error', e, st);
    throw FormatException('Failed to parse: $e');
  }
}

/// 處理無 `app` 欄位的舊備份：依卡池代碼判別是否為本軟體（原神）檔，並濾掉非原神 banner。
///
/// 蒐集 `accounts[*].banners` 的 key 與 [gachaTypes] 已知集合比對：確有卡池資料但無一是
/// 原神代碼 → 丟 [ForeignBundleException]（純外來，如鳴潮檔）；否則回傳濾除未知 banner 後的
/// raw（未知代碼的 banner 整條跳過、不解析其記錄，濾空的帳號一併移除），只留可辨識的原神 banner。
/// 讀不出任何卡池資料（空檔／結構模糊）→ 原樣交回，由 [AccountsBundle.fromJson] 後續處理。
Map<String, dynamic> _screenLegacyBundle(Map<String, dynamic> raw) {
  final known = {for (final t in gachaTypes) t.gachaType};
  final accountsRaw = raw['accounts'];
  if (accountsRaw is! List) return raw;

  var sawAnyCode = false;
  var keptAnyKnown = false;
  final filteredAccounts = <dynamic>[];
  for (final entry in accountsRaw) {
    if (entry is! Map<String, dynamic>) {
      filteredAccounts.add(entry);
      continue;
    }
    final bannersRaw = entry['banners'];
    if (bannersRaw is! Map<String, dynamic>) {
      filteredAccounts.add(entry);
      continue;
    }
    final keptBanners = <String, dynamic>{};
    for (final code in bannersRaw.keys) {
      sawAnyCode = true;
      if (known.contains(code)) {
        keptBanners[code] = bannersRaw[code];
        keptAnyKnown = true;
      }
    }
    if (keptBanners.isNotEmpty) {
      filteredAccounts.add({...entry, 'banners': keptBanners});
    }
  }

  if (sawAnyCode && !keptAnyKnown) {
    _log.warning('import failed: foreign bundle (no Genshin pools)');
    throw const ForeignBundleException();
  }
  return {...raw, 'accounts': filteredAccounts};
}
