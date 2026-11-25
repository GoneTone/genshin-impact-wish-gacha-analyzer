import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/paimon_moe_importer.dart';

/// 補齊匯入記錄缺少的名稱與星級（例如 UIGF 選填欄位不存在時），需要網路的部分
/// 由實作負責，方便測試時注入假資料。
abstract interface class ItemResolver {
  /// 依 [itemId] 回傳 [lang]（App 語言代碼，如 `zh-tw`）的名稱；查無丟
  /// [ItemResolveException]。
  Future<String> nameFor(String itemId, String lang);

  /// 依 [name] 與 [lang] 回傳 1～5 星；查無丟 [ItemResolveException]。
  Future<int> rankFor(String name, String lang);
}

/// [ItemResolver] 無法補齊某個物品時拋出。
class ItemResolveException implements Exception {
  /// 建立 [ItemResolveException]。
  const ItemResolveException(this.reason, this.item);

  /// 失敗原因（英文，寫進 log）。
  final String reason;

  /// 查不到的物品（`item_id` 或名稱）。
  final String item;

  @override
  String toString() => 'ItemResolveException($reason: $item)';
}

/// 第三方平台匯入器：把該平台的匯出檔轉成本軟體的 [AccountsBundle]，之後接回
/// 既有匯入下游（帳號挑選 → 確認 → 合併寫入＋補圖）。新增平台＝加一個實作類別
/// 並在 [kPlatformImporters] 註冊一行。
abstract interface class PlatformImporter {
  /// 穩定識別鍵（如 `'paimon_moe'`）。
  String get id;

  /// 平台顯示名（在地化）。
  String displayName(AppLocalizations l);

  /// 平台清單列的副標（在地化）；null 表示不顯示。
  String? subtitle(AppLocalizations l);

  /// 平台清單列的前置 icon。
  IconData get icon;

  /// 可接受的副檔名（如 `['xlsx']`）。
  List<String> get fileExtensions;

  /// 匯出檔沒有 UID、需要使用者指定帳號時為 true；此時 [parse] 產出的帳號 UID
  /// 為空字串，呼叫端選定後用 [assignTargetUid] 套上。
  bool get requiresTargetUid;

  /// 解析檔案內容為 [AccountsBundle]，每個卡池依 `compareRecordsNewestFirst`
  /// 由新到舊排序。
  ///
  /// 非此平台格式丟 `ForeignBundleException`；結構／欄位不符丟 [FormatException]。
  /// [resolver]：補齊缺少的名稱與星級，null 表示不補。
  Future<AccountsBundle> parse(Uint8List bytes, {ItemResolver? resolver});
}

/// 已支援的第三方平台清單。新增平台時在此追加。
const List<PlatformImporter> kPlatformImporters = [PaimonMoeImporter()];

/// 把 [bundle] 每個帳號的 UID 與每筆記錄的 `uid` 改成 [uid]，作用中 UID 也設為
/// [uid]（用於 [PlatformImporter.requiresTargetUid] 的平台）。
AccountsBundle assignTargetUid(AccountsBundle bundle, String uid) =>
    AccountsBundle(
      exportedAt: bundle.exportedAt,
      appVersion: bundle.appVersion,
      lastActiveUid: uid,
      accounts: [
        for (final a in bundle.accounts)
          ExportedAccount(
            data: BannerStorage(
              uid: uid,
              lastUpdated: a.data.lastUpdated,
              banners: a.data.banners.map(
                (key, records) => MapEntry(key, [
                  for (final r in records) r.copyWith(uid: uid),
                ]),
              ),
            ),
            alias: a.alias,
            aliasUpdatedAt: a.aliasUpdatedAt,
          ),
      ],
    );

/// UID 格式檢查：9～10 位數字。
final _uidPattern = RegExp(r'^\d{9,10}$');

/// [uid] 是否符合原神 UID 格式（9～10 位數字）。
bool isValidUid(String uid) => _uidPattern.hasMatch(uid);
