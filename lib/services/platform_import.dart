import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/paimon_moe_importer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/uigf_importer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/record_merge.dart';

/// Logger 實例（第三方平台匯入）。
final _log = Logger('wish.import.platform');

/// 補齊匯入記錄缺少的名稱與星級（例如 UIGF 選填欄位不存在時），需要網路的部分
/// 由實作負責，方便測試時注入假資料。
abstract interface class ItemResolver {
  /// 依 [itemId] 回傳名稱與該名稱的語言（App 語言代碼，如 `zh-tw`；目標語言由
  /// 實作決定）；查無丟 [ItemResolveException]。
  Future<({String name, String lang})> nameFor(String itemId);

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

/// UIGF 檔的主版本號比支援的（v4）新時拋出。
class UigfVersionTooNewException implements Exception {
  /// 建立 [UigfVersionTooNewException]。
  const UigfVersionTooNewException(this.version);

  /// 檔案宣告的版本字串（如 `v5.0`）。
  final String version;

  @override
  String toString() => 'UigfVersionTooNewException($version)';
}

/// 匯入檔含有不認得的卡池類型（或 paimon.moe 分頁）時拋出；整份拒絕。
class UnknownGachaTypeException implements Exception {
  /// 建立 [UnknownGachaTypeException]。
  const UnknownGachaTypeException(this.types);

  /// 檔案中所有不認得的卡池類型（或分頁名）。
  final Set<String> types;

  @override
  String toString() => 'UnknownGachaTypeException($types)';
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

  /// 平台清單列前置的平台圖示（asset 路徑）。
  String get iconAsset;

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
const List<PlatformImporter> kPlatformImporters = [
  UigfImporter(),
  PaimonMoeImporter(),
];

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

/// 第三方匯入在使用者按下「匯入」時呼叫：檔案沒有可靠匯出時間的帳號，把「最後更新」
/// 從解析當下改成 [at]；取自檔案匯出時間的帳號維持不變。
///
/// 依賴 importer 的約定：[AccountsBundle.exportedAt] 是解析當下，沒有匯出時間的帳號
/// `lastUpdated` 也放同一個值，匯出時間則一定早於它，所以「不早於 exportedAt」就是
/// 沒有匯出時間。
AccountsBundle stampLastUpdated(AccountsBundle bundle, DateTime at) =>
    AccountsBundle(
      exportedAt: bundle.exportedAt,
      appVersion: bundle.appVersion,
      lastActiveUid: bundle.lastActiveUid,
      accounts: [
        for (final a in bundle.accounts)
          a.data.lastUpdated.isBefore(bundle.exportedAt)
              ? a
              : ExportedAccount(
                  data: a.data.copyWith(lastUpdated: at),
                  alias: a.alias,
                  aliasUpdatedAt: a.aliasUpdatedAt,
                ),
      ],
    );

/// UID 格式檢查：9～10 位數字。
final _uidPattern = RegExp(r'^\d{9,10}$');

/// [uid] 是否符合原神 UID 格式（9～10 位數字）。
bool isValidUid(String uid) => _uidPattern.hasMatch(uid);

/// 匯入檔時間字串格式 `yyyy-MM-dd HH:mm:ss`。
final _importTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$',
);

/// 把 `yyyy-MM-dd HH:mm:ss` 的 [text] 原樣解析為本地 [DateTime]，不做時區換算；
/// 格式不符或日期不存在（如 13 月、25 時）回 null。
DateTime? parseImportTime(String text) {
  final m = _importTimePattern.firstMatch(text);
  if (m == null) return null;
  final [y, mo, d, h, mi, s] = [
    for (var g = 1; g <= 6; g++) int.parse(m.group(g)!),
  ];
  // DateTime 會把 13 月、25 時之類的值進位成合法日期，要擋下來；用 UTC 檢查，
  // 本地時間落在日光節約跳過的那一小時時才不會被誤判。
  final t = DateTime.utc(y, mo, d, h, mi, s);
  final valid =
      t.year == y &&
      t.month == mo &&
      t.day == d &&
      t.hour == h &&
      t.minute == mi &&
      t.second == s;
  return valid ? DateTime(y, mo, d, h, mi, s) : null;
}

/// 對 [records]（來源順序）呼叫 [assignSubstituteIds]；同一卡池、同一秒的替代記錄
/// 超過 100 筆（序號用完）時記 log 並丟 [FormatException]。[platform] 寫進 log。
List<GachaRecord> assignSubstituteIdsOrReject(
  String platform,
  List<GachaRecord> records,
) {
  try {
    return assignSubstituteIds(records);
  } on ArgumentError catch (e, st) {
    final perSecond = <(String, DateTime), int>{};
    for (final r in records) {
      if (isOfficialId(r.id)) continue;
      perSecond.update(
        (bannerKeyFor(r.gachaType), r.time),
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    final (banner, time) = perSecond.entries
        .firstWhere((e) => e.value > 100)
        .key;
    _log.warning(
      '$platform import: more than 100 substitute records in one second '
      'banner=$banner time=$time',
      e,
      st,
    );
    throw FormatException('Banner $banner has more than 100 records at $time');
  }
}
