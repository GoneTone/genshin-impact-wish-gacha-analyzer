import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';

/// 把目前狀態打包成 [AccountsBundle] 並序列化成 pretty-printed JSON 字串。
///
/// 帳號順序套用 [mergeUidOrder]，與設定頁顯示順序一致。
String exportAccounts({
  required Map<String, BannerStorage> byUid,
  required List<String> uidOrder,
  required Map<String, String> uidAliases,
  required Map<String, DateTime> uidAliasUpdatedAt,
  required String? lastActiveUid,
  required String appVersion,
  required DateTime now,
}) {
  final ordered = mergeUidOrder(
    knownUids: byUid.keys,
    customOrder: uidOrder,
    lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
  );

  final accounts = [
    for (final uid in ordered)
      ExportedAccount(
        data: byUid[uid]!,
        alias: uidAliases[uid],
        aliasUpdatedAt: uidAliasUpdatedAt[uid],
      ),
  ];

  final bundle = AccountsBundle(
    exportedAt: now.toUtc(),
    appVersion: appVersion,
    lastActiveUid: lastActiveUid,
    accounts: accounts,
  );

  return const JsonEncoder.withIndent('  ').convert(bundle.toJson());
}

/// 在背景 isolate 跑 [exportAccounts]，回傳 JSON 字串（雲端同步用）。
///
/// 數 MB 的 jsonEncode 在主 isolate 會卡住畫面；有記錄檔的帳號只傳路徑、由背景
/// isolate 自己讀檔（把全部記錄當訊息傳過去，複製本身在主 isolate 就要十幾 ms）。
/// 每條寫入路徑都是先存檔才更新 state，所以檔案內容與記憶體一致；
/// 還沒有檔案的帳號（記憶體中剛建立、或測試直接塞的資料）才傳物件。
Future<String> exportAccountsInBackground({
  required Map<String, BannerStorage> byUid,
  required File Function(String uid) recordsFileOf,
  required List<String> uidOrder,
  required Map<String, String> uidAliases,
  required Map<String, DateTime> uidAliasUpdatedAt,
  required String? lastActiveUid,
  required String appVersion,
  required DateTime now,
}) => _exportInBackground(
  byUid: byUid,
  recordsFileOf: recordsFileOf,
  uidOrder: uidOrder,
  uidAliases: uidAliases,
  uidAliasUpdatedAt: uidAliasUpdatedAt,
  lastActiveUid: lastActiveUid,
  appVersion: appVersion,
  now: now,
  finish: _asIs,
);

/// 同 [exportAccountsInBackground]，但在背景直接編成 UTF-8 位元組（匯出檔案用）。
Future<Uint8List> exportAccountsBytesInBackground({
  required Map<String, BannerStorage> byUid,
  required File Function(String uid) recordsFileOf,
  required List<String> uidOrder,
  required Map<String, String> uidAliases,
  required Map<String, DateTime> uidAliasUpdatedAt,
  required String? lastActiveUid,
  required String appVersion,
  required DateTime now,
}) => _exportInBackground(
  byUid: byUid,
  recordsFileOf: recordsFileOf,
  uidOrder: uidOrder,
  uidAliases: uidAliases,
  uidAliasUpdatedAt: uidAliasUpdatedAt,
  lastActiveUid: lastActiveUid,
  appVersion: appVersion,
  now: now,
  finish: _asUtf8,
);

/// 原樣回傳 JSON 字串。
String _asIs(String json) => json;

/// 把 JSON 字串編成 UTF-8 位元組。
Uint8List _asUtf8(String json) => utf8.encode(json);

/// 兩個公開入口的共用實作；寫成 top-level 讓送進 isolate 的閉包只抓參數。
Future<T> _exportInBackground<T>({
  required Map<String, BannerStorage> byUid,
  required File Function(String uid) recordsFileOf,
  required List<String> uidOrder,
  required Map<String, String> uidAliases,
  required Map<String, DateTime> uidAliasUpdatedAt,
  required String? lastActiveUid,
  required String appVersion,
  required DateTime now,
  required T Function(String json) finish,
}) {
  final filePaths = <String, String>{};
  final inMemory = <String, BannerStorage>{};
  for (final MapEntry(:key, :value) in byUid.entries) {
    final file = recordsFileOf(key);
    if (file.existsSync()) {
      filePaths[key] = file.path;
    } else {
      inMemory[key] = value;
    }
  }
  return Isolate.run(() {
    final loaded = <String, BannerStorage>{
      for (final MapEntry(:key, :value) in filePaths.entries)
        key: readRecordsFileSync(value),
      ...inMemory,
    };
    return finish(
      exportAccounts(
        byUid: loaded,
        uidOrder: uidOrder,
        uidAliases: uidAliases,
        uidAliasUpdatedAt: uidAliasUpdatedAt,
        lastActiveUid: lastActiveUid,
        appVersion: appVersion,
        now: now,
      ),
    );
  });
}
