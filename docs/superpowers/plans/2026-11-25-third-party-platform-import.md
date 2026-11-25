# 第三方平台祈願記錄匯入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 先修好第二個角色活動祈願（400），再改寫卡池記錄合併規則並新增 UIGF（JSON v2.0～v4.x）與 paimon.moe（Excel）的第三方匯入。

**Architecture:** 合併改成「卡池 key＋同一秒」整組比對的共用純函式（`lib/services/record_merge.dart`），匯入備份、雲端同步、抓官方資料、第三方匯入全走它。第三方平台比照鳴潮的 Adapter：每個 `PlatformImporter` 把檔案轉成 `AccountsBundle`，接回設定頁既有的匯入下游。沒有官方 `id` 的記錄用首位 `0` 的替代 `id`，不改存檔格式。

**Tech Stack:** Flutter／Dart（`fvm`）、Riverpod、`http`、新增 `excel` 套件讀 xlsx。

**Spec:** `docs/superpowers/specs/2026-11-25-third-party-platform-import-design.md`

## Global Constraints

- 分支：`feat/third-party-import`（從 `feat/android` 開出）；不 push。
- 所有 Flutter／Dart 指令用 `fvm`；commit 前依序 `fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。
- commit 用 PowerShell（GPG 簽章），訊息英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；不 `--no-verify`。
- 所有宣告（含 private）要有一行 `///` dartdoc；實作註解只寫 WHY；註解與 dartdoc 用繁中全形標點。
- log 一律英文，`Logger('wish.import.platform')`（匯入）、`Logger('wish.merge')`（合併）；UID 經 `sanitizeUid`；例外用 `warning('...', e, st)`。
- 新 dialog 一律 `AppDialog`；進行中不可關閉的視窗 `showCloseButton: false`＋`PopScope(canPop: false)`；`InkWell` 顯式 `mouseCursor: SystemMouseCursors.click`。
- l10n：先寫 `app_zh.arb`，再補其餘 30 個 ARB（全部都有實體翻譯）；結尾省略號用半形 `...`；改完 `fvm flutter gen-l10n`。卡池名稱照 `docs/術語表.md` 與官方 `itemTypeNameMap`。
- 合併規則五個性質（spec〈五〉）必須成立：官方記錄不刪不改（`lang` 回填與 301→400 修正除外）、冪等、順序無關、每「卡池＋秒」不相加、只有官方記錄時與舊行為逐筆相同。
- 替代 `id` 格式：`"0" + yyyyMMddHHmmss + 兩碼同秒序號 + "00"`，共 19 碼。官方 `id`：`^[1-9]\d{18}$`。
- 整份拒絕、不跳過：未知卡池類型、UIGF 主版本 > 4、補名稱的字典抓不到或查無、星級查不到、必要欄位缺失或格式錯、同秒超過 99 筆。
- 重疊提醒門檻：N ≥ 10 且 M ≤ N ÷ 10。
- UID 驗證：`^\d{9,10}$`。
- 測試 fixture 一律自製、匿名；不得把使用者真實檔案（含 UID `8000…`）放進 repo。
- UI 改動要同時顧電腦與手機（直向、橫向），並有版面測試；共用邏輯（`lib/state`、`lib/services`）兩個平台都不可改變既有行為。

## Review Focus

1. **語言轉換後重新匯入同一份 paimon 檔**：本機替代記錄名稱已被轉成中文，重新匯入的是英文；同 `id` 必須只留一筆（Task 2 測試 `same substitute id with different names stays one record`）。
2. **paimon `Time` 儲存格是 Excel 日期數值而非文字**：要轉回同一秒的 `yyyy-MM-dd HH:mm:ss`，不可因時區偏移（Task 5 測試 `time as excel date cell`）。
3. **最新一筆是替代記錄時抓官方資料**：停止點要用最新官方 `id`，抓完同秒替代記錄被取代、其他保留（Task 3 測試 `substitute newer than newest official is replaced by fetched official`）。
4. **舊版 App 讀含替代記錄的備份／雲端資料**：`schema_version` 2 要被版本 1 的讀取端拒絕（Task 4 測試 `reader with max 1 rejects bundle containing substitute records`）。
5. **UIGF v4 同一 UID 同時在 `hk4e` 與 `hk4e_ugc`**：合成一個帳號，祈願與頌願都在（Task 6 測試 `same uid in hk4e and hk4e_ugc becomes one account`）。

---

### Task 1: 第二個角色活動祈願（400）

**Files:**
- Modify: `lib/models/gacha_record.dart`（`copyWith` 增加 `id`、`gachaType`）
- Modify: `lib/services/gacha_fetcher.dart:105-130`（`fetchPage`）
- Modify: `lib/data/gacha_types.dart`（`gachaTypeFor`、新增 `bannerKeyFor`）
- Modify: `lib/widgets/banner_colors.dart:75`（`colorFor`）
- Modify: `lib/widgets/cards/timeline_horizontal.dart:53-56`（`bannerDistributionEntries`）
- Modify: `lib/models/banner_storage.dart`（`_mergeRecordsById` 的 301→400 修正）
- Modify: `lib/l10n/app_*.arb`（31 個）、`docs/術語表.md`
- Test: `test/services/gacha_fetcher_test.dart`、`test/data/gacha_types_test.dart`（不存在則建立）、`test/models/banner_storage_test.dart`、`test/widgets/cards/timeline_horizontal_test.dart`（沿用既有檔名，沒有則建立）

**Interfaces:**
- Produces: `String bannerKeyFor(String gachaType)`（`'400'` → `'301'`，其餘原樣）；`GachaRecord.copyWith({String? id, String? gachaType, String? name, String? lang})`；ARB key `gachaTypeCharacter2`。

**Ruling（不照 spec 字面）：** spec〈十八〉寫「`gachaTypes` 加入 `400`」，但 `gachaTypes` 會驅動側欄、抓取迴圈與 UID 探測，加進去會多出一個卡池頁並多抓一次。改成 `gachaTypeFor('400')` 回傳一個**不在 `gachaTypes` 清單裡**的常數 `GachaType(gachaType: '400', nameKey: 'gachaTypeCharacter2', category: GachaCategory.gacha, pities: 與 301 相同)`，`resolveName` 加上 `'gachaTypeCharacter2'`。

- [ ] **Step 1: 寫失敗測試**

```dart
// gacha_fetcher_test.dart
test('wish page keeps api gacha_type 400', () async {
  // 假 client 對 getGachaLog?gacha_type=301 回一筆 gacha_type '400'、一筆 '301'
  expect(page.records.map((r) => r.gachaType), ['400', '301']);
});
test('odes page still overrides with queried 1000/2000', () async {
  // getBeyondGachaLog?gacha_type=2000 回 op_gacha_type '20021'
  expect(page.records.single.gachaType, '2000');
});
// gacha_types_test.dart
test('400 resolves to character event wish-2 with character pity', () {
  expect(gachaTypeFor('400').nameKey, 'gachaTypeCharacter2');
  expect(pityThresholdFor('400', 5), 90);
  expect(pityThresholdFor('400', 4), 10);
  expect(gachaTypes.any((t) => t.gachaType == '400'), isFalse);
  expect(bannerKeyFor('400'), '301');
  expect(bannerKeyFor('302'), '302');
});
// banner_storage_test.dart
test('incoming 400 corrects local 301 with same id', () {
  final merged = local301.mergeWith(incoming400SameId);
  expect(merged.banners['301']!.single.gachaType, '400');
});
test('local 400 is not downgraded by incoming 301', () { ... expect('400'); });
// timeline_horizontal_test.dart
test('400 entries count toward character event legend', () {
  // entries: 2 筆 '301'、1 筆 '400'
  expect(rows.firstWhere((e) => e.name == l.gachaTypeCharacter).count, 3);
  expect(rows.length, gachaTypes.length);
});
```

另加 `colorFor('400') == colorFor('301')` 的斷言。

- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/services/gacha_fetcher_test.dart test/data/gacha_types_test.dart test/models/banner_storage_test.dart test/widgets/cards/timeline_horizontal_test.dart`，預期新測試 FAIL。
- [ ] **Step 3: 實作**
  - `fetchPage`：由 `url.path` 是否以 `GachaEndpoint.odes.pathSegment` 結尾判斷頌願；祈願傳 `e['gacha_type'] as String? ?? queryGachaType`，頌願維持傳 `queryGachaType`。`fromApiJson` 簽章不變。
  - `_mergeRecordsById`：同 `id` 時，本機 `gachaType == '301'` 且傳入 `'400'` → `copyWith(gachaType: '400')`（可與既有 `lang` 回填同時發生）。
  - `bannerDistributionEntries`：計數 key 改用 `bannerKeyFor(e.gachaType)`。
  - `colorFor`：`'301' || '400' => character`。
  - ARB：新增 `gachaTypeCharacter2`，`app_zh.arb` 為「角色活動祈願-2」；其他語言取官方 `itemTypeNameMap` 的 `400`（取得方式見 `docs/術語表.md`〈官方來源鍵名〉；已收錄的 ko／de／ru／it／tr 用表上的值，pt 為 `Oração de Evento de Personagem - 2`；遊戲沒出的語言依術語表規則用英文 `Character Event Wish-2`）。把 400 這列補進術語表主表。`fvm flutter gen-l10n`。
- [ ] **Step 4: 跑測試確認通過**（同 Step 2 指令，全部 PASS），再跑 `fvm flutter test` 全套。
- [ ] **Step 5: 時間軸顏色與名稱給使用者看**：電腦版與手機各截一張含 400 記錄的時間軸，回報給使用者確認顏色（spec〈十八〉：顏色要使用者看過再定）；使用者要求改色就改 `colorFor` 並更新測試。
- [ ] **Step 6: Commit** — `fix(gacha): keep character event wish-2 (400) records and label them`

---

### Task 2: 合併規則（record_merge）

**Files:**
- Create: `lib/services/record_merge.dart`
- Modify: `lib/models/banner_storage.dart`（`mergeWith` 改呼叫 `mergeBannerRecords`；移除 `_mergeRecordsById`，其 `lang` 回填與 301→400 修正搬進新函式；dartdoc「依 id 降序」改寫）
- Modify: `lib/state/gacha_repository.dart:1787-1797`（`_seedLangFromData` 改用 `compareRecordsNewestFirst`）、`:1511-1513`（`_runImport` 的 added／duplicate 不得為負，各自 clamp 到 0）
- Test: `test/services/record_merge_test.dart`、`test/models/banner_storage_test.dart`

**Interfaces:**
- Consumes: `bannerKeyFor`、`GachaRecord.copyWith(id:, gachaType:)`（Task 1）
- Produces:
  - `bool isOfficialId(String id)`（`^[1-9]\d{18}$`）
  - `bool isSubstituteId(String id)`（`id.startsWith('0')`）
  - `String substituteId(DateTime time, int seq)`（seq > 99 丟 `ArgumentError`）
  - `List<GachaRecord> assignSubstituteIds(List<GachaRecord> recordsInSourceOrder)`：對 `id` 非官方格式者依「`bannerKeyFor(gachaType)`＋`time`」在來源順序中的出現序號產生替代 `id`；官方 `id` 原樣保留。
  - `int compareRecordsNewestFirst(GachaRecord a, GachaRecord b)`（`time` 新→舊，同 `time` 依 `id` 大→小）
  - `List<GachaRecord> mergeBannerRecords(List<GachaRecord> local, List<GachaRecord> incoming)`：spec〈五〉規則 1～3，回傳依 `compareRecordsNewestFirst` 排序。

規則 2 筆數相同時的 tie-break：兩組各自依 `id` 排序後，以 `'${r.lang}\u0000${r.name}\u0000${r.itemType}\u0000${r.rankType}'` 用 `\u0001` 串起來比較，取字串較小者。

- [ ] **Step 1: 寫失敗測試**（`record_merge_test.dart`，fixture 用自製 helper 產生官方／替代記錄）

```dart
test('substituteId format', () {
  expect(substituteId(DateTime(2025, 12, 1, 4, 6, 48), 3), '0202512010406480300');
  expect(substituteId(DateTime(2025, 12, 1, 4, 6, 48), 3).length, 19);
  expect(() => substituteId(DateTime(2025), 100), throwsArgumentError);
});
test('official-only merge equals old id-union order', () { ... });           // 性質 5
test('official at a second replaces substitute group', () { ... });          // 規則 1
test('substitute-only second takes larger group, never sum', () { ... });   // 規則 2、性質 4
test('equal-size substitute groups pick the same group regardless of order', () {
  expect(ids(mergeBannerRecords(a, b)), ids(mergeBannerRecords(b, a)));
});
test('merge is idempotent', () { expect(m(m(x, y), y), m(x, y)); });
test('all orders of three sources give the same result', () { ... });      // 6 種排列
test('local official records are never removed', () { ... });
test('gap filled by substitutes, surrounding official kept', () { ... });
test('ten-pull with repeated 3-star stays ten', () { ... });
test('same substitute id with different names stays one record', () { ... }); // Review Focus 1
test('assignSubstituteIds numbers per banner key and second', () {
  // 同秒三筆 301、同秒一筆 400（同 key 301）→ 序號 00..03；不同秒重新從 00
});
```

`banner_storage_test.dart`：`mergeWith` 對替代＋官方混合資料符合上述行為；`lastUpdated` 規則不變。

- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/services/record_merge_test.dart test/models/banner_storage_test.dart`
- [ ] **Step 3: 實作** `record_merge.dart` 與上列修改。合併時記 `Logger('wish.merge')`：每卡池「官方取代替代」組數、「兩邊皆替代取較多」組數；同秒兩邊官方與替代筆數不一致時 `warning`。
- [ ] **Step 4: 跑測試確認通過**，再跑 `fvm flutter test` 全套（雲端同步、匯入既有測試須續綠）。
- [ ] **Step 5: Commit** — `feat(merge): merge records per banner and second so substitutes never duplicate`

---

### Task 3: 抓官方資料改用共用合併

**Files:**
- Modify: `lib/services/gacha_fetcher.dart:149-236`（`fetchBannerWithMerge`）
- Modify: `lib/state/gacha_repository.dart:955-957`（`newCount` 為負時以 0 計入 `totalNew`）
- Test: `test/services/gacha_fetcher_test.dart`

**Interfaces:**
- Consumes: `isOfficialId`、`mergeBannerRecords`（Task 2）

- [ ] **Step 1: 寫失敗測試**

```dart
test('stop point skips substitute records', () async {
  // existing：最新一筆是替代記錄（比最新官方新），API 回到最新官方 id 前的記錄
  // 預期：抓取繼續到最新官方 id 才停（驗證送出的 end_id 序列）
});
test('substitute newer than newest official is replaced by fetched official', () async {
  // 同秒官方回來 → 替代消失；不同秒的替代保留
});
test('existing with only substitutes fetches to api end', () async { ... });
test('official-only existing behaves exactly as before', () async { ... }); // 既有測試保持
test('empty-lang backfill unchanged for odes', () async { ... });           // 既有測試保持
```

- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/services/gacha_fetcher_test.dart`
- [ ] **Step 3: 實作**：`existingMaxId` 取 `existing` 中第一筆 `isOfficialId` 的 `id`，沒有則 `'0'`；回傳值改為 `mergeBannerRecords(normalizedExisting, fresh)`（`lang` 回填邏輯維持在合併前）。
- [ ] **Step 4: 跑測試確認通過**，再跑 `fvm flutter test test/state/` 與全套。
- [ ] **Step 5: Commit** — `fix(fetch): stop at the newest official record and merge with substitutes`

---

### Task 4: `schema_version` 依內容計算

**Files:**
- Modify: `lib/models/accounts_bundle.dart:70-110`
- Test: `test/models/accounts_bundle_test.dart`

**Interfaces:**
- Consumes: `isSubstituteId`（Task 2）
- Produces: `static const int maxReadableSchemaVersion = 2;`（取代讀取端用的 `currentSchemaVersion`）；`int get schemaVersion`（含替代記錄 → 2，否則 1）。dartdoc 寫明 spec〈八〉的規則與每個版本的意義。

- [ ] **Step 1: 寫失敗測試**

```dart
test('bundle without substitute records writes version 1', () { expect(b.toJson()['schema_version'], 1); });
test('bundle with a substitute record writes version 2', () { ... 2 });
test('reader accepts 1 and 2, rejects 3', () { ... throwsA(isA<UnsupportedSchemaVersionException>()) });
test('reader with max 1 rejects bundle containing substitute records', () {
  // 以 version 2 的 JSON 模擬舊版讀取端的判斷：2 > 1 即拒絕（Review Focus 4）
});
```

- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/models/accounts_bundle_test.dart`
- [ ] **Step 3: 實作**；全專案 grep `currentSchemaVersion` 改用新名稱。
- [ ] **Step 4: 跑測試確認通過**，再跑 `test/services/accounts_*`、`test/state/cloud_sync_test.dart`、`test/state/gacha_repository_cloud_import_test.dart`。
- [ ] **Step 5: Commit** — `feat(import): write schema version 2 only when substitute records exist`

---

### Task 5: `PlatformImporter` 與 paimon.moe importer

**Files:**
- Modify: `pubspec.yaml`（`fvm flutter pub add excel`；確認授權與 Windows／Android 可用，記在 commit body）
- Create: `lib/services/platform_import.dart`
- Create: `lib/services/importers/paimon_moe_importer.dart`
- Test: `test/services/importers/paimon_moe_importer_test.dart`、`test/helpers/xlsx_fixture.dart`（用 `excel` 套件在測試中產生 xlsx bytes）

**Interfaces:**
- Consumes: `assignSubstituteIds`、`compareRecordsNewestFirst`、`bannerKeyFor`
- Produces（`platform_import.dart`）：

```dart
abstract interface class PlatformImporter {
  String get id;
  String displayName(AppLocalizations l);
  String? subtitle(AppLocalizations l);
  IconData get icon;
  List<String> get fileExtensions;
  bool get requiresTargetUid;
  Future<AccountsBundle> parse(Uint8List bytes, {ItemResolver? resolver});
}
AccountsBundle assignTargetUid(AccountsBundle bundle, String uid); // 套進 BannerStorage.uid 與每筆 record.uid
bool isValidUid(String uid); // ^\d{9,10}$
```

  `ItemResolver` 由 Task 7 定義；此 task 先在 `platform_import.dart` 宣告 `abstract interface class ItemResolver`（方法見 Task 7），paimon 不使用。`kPlatformImporters` 在 Task 6 完成後才註冊兩個 importer，本 task 先只放 `PaimonMoeImporter()`。
- `PaimonMoeImporter`：`id = 'paimon_moe'`、`fileExtensions = ['xlsx']`、`requiresTargetUid = true`、產出 1 個帳號、UID 為空字串、`lang = 'en-us'`、`itemType` 取 `Type` 原字串。

- [ ] **Step 1: 寫失敗測試**

```dart
test('maps sheets and Wish 2 to gacha types', () {
  // Character Event 兩列（Part '' / 'Wish 2'）、Weapon、Standard、Beginners'、Chronicled 各一列
  expect(types, ['301', '400', '302', '200', '100', '500']);
  expect(banner('301').length, 2); // 400 放在 key 301
});
test('same-second rows get sequential substitute ids in sheet order', () { ... '...00' '...01' });
test('records sorted newest first', () { ... });
test('time as excel date cell', () { /* 儲存格為日期值 2025-12-01 04:06:48 → 同字串 */ });
test('columns located by header name not position', () { ... });
test('Banner List sheet ignored', () { ... });
test('missing Information marker throws ForeignBundleException', () { ... });
test('missing required column throws FormatException', () { ... });
test('rank outside 1..5 throws FormatException', () { ... });
test('assignTargetUid sets uid on storage and every record', () { ... });
test('isValidUid', () { expect(isValidUid('812345678'), isTrue); expect(isValidUid('8123456'), isFalse); });
```

- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/services/importers/paimon_moe_importer_test.dart`
- [ ] **Step 3: 實作**；log：列數、各卡池筆數、時間範圍、拒絕原因（帶分頁名與列號）。
- [ ] **Step 4: 跑測試確認通過**，再跑全套與 `fvm flutter analyze`。
- [ ] **Step 5: Commit** — `feat(import): parse paimon.moe excel exports`

---

### Task 6: UIGF importer

**Files:**
- Create: `lib/services/importers/uigf_importer.dart`
- Modify: `lib/services/platform_import.dart`（`kPlatformImporters = [UigfImporter(), PaimonMoeImporter()]`）
- Test: `test/services/importers/uigf_importer_test.dart`、`test/fixtures/uigf/`（自製 v2.2、v3.0、v4.1、v4.2 含 `hk4e_ugc` 的 JSON，UID 用假值）

**Interfaces:**
- Consumes: `ItemResolver`（呼叫其方法補名稱／星級；`resolver` 為 null 而需要補時丟 `FormatException`）、`assignSubstituteIds`、`isOfficialId`
- Produces: `UigfImporter`：`id = 'uigf'`、`fileExtensions = ['json']`、`requiresTargetUid = false`；例外型別 `class UigfVersionTooNewException implements Exception { final String version; }`、`class UnknownGachaTypeException implements Exception { final Set<String> types; }`（放在 `platform_import.dart`，Task 9 對映錯誤訊息）。

依 spec〈二〉〈三〉：版本判斷（`info.version` → `info.uigf_version`）、v2／v3 `{info, list}`、v4 `hk4e[]` 多帳號、`hk4e_ugc`（`op_gacha_type` 對應回 `1000`／`2000`，對應表以實作當時 uigf.org 規範與官方 API 確認並寫進 dartdoc；`item_name`；頌願不設 `lang` 以外的轉換）、`gachaType` 保留 `400`、`lang` 取記錄 → 帳號、`time` 原樣、`id` 非官方格式改替代。

- [ ] **Step 1: 寫失敗測試**

```dart
test('v3.0 single account', () { ... });
test('v4.1 multiple accounts', () { ... });
test('v2.2 records carry uid and lang', () { ... });
test('400 kept and stored under key 301', () { ... });
test('ascending file order becomes newest first', () { ... });
test('invalid or missing id becomes substitute', () { ... startsWith('0') });
test('same uid in hk4e and hk4e_ugc becomes one account', () { ... }); // Review Focus 5
test('hk4e_ugc maps op_gacha_type to 1000/2000', () { ... });
test('minor version newer than known still parses', () { /* v4.9 */ });
test('major version 5 throws UigfVersionTooNewException', () { ... });
test('unknown gacha type throws UnknownGachaTypeException listing types', () { ... });
test('missing name asks resolver; resolver null throws FormatException', () { ... });
test('missing rank asks resolver', () { ... });
test('non-UIGF json throws ForeignBundleException', () { ... });
test('more than 99 records in one second throws FormatException', () { ... });
```

- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/services/importers/uigf_importer_test.dart`
- [ ] **Step 3: 實作**；log：UIGF 版本、帳號數、各卡池筆數、替代筆數、時間範圍、拒絕原因。
- [ ] **Step 4: 跑測試確認通過**，再跑全套。
- [ ] **Step 5: Commit** — `feat(import): parse UIGF json v2 through v4 including odes`

---

### Task 7: 補名稱與星級（`ItemResolver`）

**Files:**
- Create: `lib/services/importers/uigf_item_resolver.dart`
- Modify: `lib/services/platform_import.dart`（補完 `ItemResolver` 介面）
- Test: `test/services/importers/uigf_item_resolver_test.dart`（假 `http.Client`；HoYoWiki 回應用錄下來的真實 entry_page JSON 縮樣當 fixture）

**Interfaces:**
- Produces:

```dart
abstract interface class ItemResolver {
  /// 依 item_id 回傳 [lang]（App 語言代碼，如 zh-tw）的名稱；查無丟 ItemResolveException。
  Future<String> nameFor(String itemId, String lang);
  /// 依名稱與語言回傳 1～5 星；查無丟 ItemResolveException。
  Future<int> rankFor(String name, String lang);
}
class ItemResolveException implements Exception { final String reason; final String item; }
class UigfItemResolver implements ItemResolver {
  UigfItemResolver({required http.Client client, required HoYoWikiFetcher hoyowiki});
}
```

- 名稱：`https://api.uigf.org/dict/genshin/{code}.json`（名稱 → item_id，反轉後查）；App 語言對 UIGF 代碼：zh-tw→cht、zh-cn→chs、en-us→en、ja-jp→jp、ko-kr→kr、es-es→es、fr-fr→fr、ru-ru→ru、th-th→th、vi-vn→vi、de-de→de、id-id→id、pt-pt→pt；tr-tr、it-it 沒有字典，改用 en 並把回傳的 `lang` 設 en-us（由 UIGF importer 處理）。每個語言的字典一次匯入只抓一次。
- 星級：`hoyowiki.searchEntryId(name:, lang:)` → `fetchEntryPage(id:, lang:)` → 在 `page.tags` 找星級標籤。實作前先對一個角色、一個武器實際打一次 API，把 `filter_values` 的星級字串格式（各語言）記進 fixture 與 dartdoc；解析不出就丟 `ItemResolveException`。同名只查一次。
- UIGF importer 的目標語言：`dataLanguageProvider` 有值用它；沒有則用檔案帳號的 `lang`；再沒有用 `en-us`（Task 9 建 resolver 時傳入）。

- [ ] **Step 1: 寫失敗測試**：字典反轉查名、語言代碼對應、字典 HTTP 失敗丟 `ItemResolveException`、同語言只請求一次、HoYoWiki 星級解析（角色與武器 fixture 各一）、查無丟例外。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/services/importers/uigf_item_resolver_test.dart`
- [ ] **Step 3: 實作**；log：請求的字典語言、HTTP 狀態、查無的 item_id 或名稱。
- [ ] **Step 4: 跑測試確認通過**，再跑全套。
- [ ] **Step 5: Commit** — `feat(import): resolve missing UIGF names and ranks`

---

### Task 8: 重疊對不上的檢查

**Files:**
- Create: `lib/services/import_overlap_check.dart`
- Test: `test/services/import_overlap_check_test.dart`

**Interfaces:**
- Consumes: `isOfficialId`、`bannerKeyFor`
- Produces:

```dart
class OverlapMismatch {
  final String uid; final DateTime from; final DateTime to;
  final int groups;   // N
  final int matched;  // M
}
OverlapMismatch? checkImportOverlap({required BannerStorage local, required BannerStorage incoming});
```

  依 spec〈九〉：本機只取官方記錄的「卡池 key＋秒」；重疊期間＝兩邊時間範圍交集；N＝期間內傳入組數，M＝能對到同「卡池＋秒」且筆數相同的組數；`N >= 10 && M * 10 <= N` 才回傳，否則 null。

- [ ] **Step 1: 寫失敗測試**：選錯帳號（M＝0、N＝12）回傳；正確帳號回 null；N＝9 回 null；M＝1、N＝10 回傳（邊界）；M＝2、N＝19 回 null；本機沒有官方記錄回 null；時間範圍不相交回 null。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/services/import_overlap_check_test.dart`
- [ ] **Step 3: 實作**；log N、M、是否提醒（UID 經 `sanitizeUid`）。
- [ ] **Step 4: 跑測試確認通過**。
- [ ] **Step 5: Commit** — `feat(import): warn when imported records barely match local official ones`

---

### Task 9: 設定頁 UI 與字串

**Files:**
- Create: `lib/widgets/dialogs/platform_picker_dialog.dart`（逐字移植鳴潮同名檔，只換 import 路徑）
- Create: `lib/widgets/dialogs/import_target_account_dialog.dart`
- Modify: `lib/widgets/dialogs/confirm_dialog.dart:78`（`showConfirmDialog` 新增選用 `String? warning`）
- Modify: `lib/pages/settings_page.dart`（按鈕、`_runBundleImport` 抽出、`_importFromPlatform`）
- Modify: `lib/l10n/app_*.arb`（31 個）
- Test: `test/widgets/dialogs/platform_picker_dialog_test.dart`（移植鳴潮）、`test/widgets/dialogs/import_target_account_dialog_test.dart`、`test/widgets/dialogs/confirm_dialog_test.dart`（既有則加測）、`test/pages/settings_page_test.dart`（既有則加測）

**Interfaces:**
- Consumes: `kPlatformImporters`、`assignTargetUid`、`isValidUid`、`UigfItemResolver`、`checkImportOverlap`、各例外型別。
- Produces:

```dart
Future<PlatformImporter?> showPlatformPickerDialog({required BuildContext context});
/// 回傳選定的 UID；取消回 null。
Future<String?> showImportTargetAccountDialog({
  required BuildContext context,
  required List<AccountPickerEntry> accounts, // 本機帳號；空清單時只顯示輸入框
});
Future<bool?> showConfirmDialog({..., String? warning}); // 非 null 時內容下方顯示警告色區塊
```

UI 依 spec〈十一〉與已確認的畫面草稿（甲方案）：
- 設定頁「匯入資料」右邊加 `OutlinedButton.icon`（`Icons.cloud_sync_outlined`、`l.settingsImportOtherPlatform`），`progress != null` 時停用。
- 流程：選平台 → `pickFileBytes(extensions: platform.fileExtensions)` → `parse`（UIGF 需要補資料時，解析期間顯示不可關閉的進度對話框）→ `requiresTargetUid` 時開選帳號對話框並 `assignTargetUid` → 既有帳號挑選（`_runBundleImport`）→ 對每個選定帳號 `checkImportOverlap`，有結果就把每段警告文字串進 `warning`、確認鍵改「仍要匯入」 → `importAccountsAndFetchHoYoWiki`。
- 錯誤 snackbar：讀檔失敗 `importReasonUnreadable`、`ForeignBundleException` → `importReasonNotPlatformFile(platform)`、`FormatException` → `importReasonInvalidFormat`、`UigfVersionTooNewException` → `importReasonUigfVersionTooNew(version)`、`UnknownGachaTypeException` → `importReasonUnknownGachaType(types)`、`ItemResolveException` → `importReasonItemUnresolved(item)`。
- 選帳號對話框：`AppDialog`（`sm`）、`RadioGroup`／`RadioListTile` 列本機帳號（別名＋UID、本機筆數）＋「其他 UID」與 `TextField`；`isValidUid` 不成立時「繼續」停用；360 寬時 UID 與筆數改兩行。

ARB 新 key（`app_zh.arb` 值；鳴潮已有的三個 key 從鳴潮 31 個 ARB 逐字複製）：

| key | zh |
|---|---|
| `settingsImportOtherPlatform`（鳴潮） | 從其他平台匯入 |
| `platformPickerTitle`（鳴潮） | 選擇匯入來源平台 |
| `importReasonNotPlatformFile`（鳴潮） | 此檔案不是有效的 {platform} 匯出檔 |
| `platformUigf` | UIGF |
| `platformUigfSubtitle` | genshin-wish-export 等工具・JSON |
| `platformPaimonMoe` | paimon.moe |
| `platformPaimonMoeSubtitle` | paimon.moe・Excel |
| `importTargetAccountTitle` | 匯入到哪個帳號？ |
| `importTargetAccountBody` | paimon.moe 的匯出檔沒有 UID，請選擇這些記錄屬於哪個帳號。 |
| `importTargetAccountOtherUid` | 其他 UID |
| `importTargetAccountUidHint` | 輸入 UID |
| `importTargetAccountRecordCount` | 本機已有 {count} 筆記錄 |
| `importReasonUigfVersionTooNew` | 這個檔案的 UIGF 版本（{version}）較新，目前還不支援。請更新 App，或在原工具改用 v4 匯出 |
| `importReasonUnknownGachaType` | 檔案裡有不支援的卡池類型（{types}） |
| `importReasonItemUnresolved` | 無法補齊物品資料（{item}），請確認網路連線後再試 |
| `importOverlapWarning` | ⚠ {uid}：{from}～{to} 這段期間兩邊都有記錄，但 {groups} 次抽卡沒有一次對得上本機的官方記錄。可能選錯了帳號，或檔案的時區不同。 |
| `importOverlapWarningPartial` | ⚠ {uid}：{from}～{to} 這段期間兩邊都有記錄，但 {groups} 次抽卡只有 {matched} 次對得上本機的官方記錄。可能選錯了帳號，或檔案的時區不同。 |
| `confirmImportAnyway` | 仍要匯入 |
| `importResolvingItems` | 正在補齊物品資料... |

- [ ] **Step 1: 寫失敗測試**：平台清單兩列且點擊回傳 importer（移植鳴潮測試）；選帳號對話框——有帳號時預選第一個、選「其他 UID」輸入 7 碼時「繼續」停用、9 碼可用、沒有本機帳號只顯示輸入框、360×640 與 640×360 無 overflow；確認對話框 `warning` 非 null 時顯示警告文字、為 null 時與現在相同；設定頁按鈕在 `progress != null` 時停用。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/widgets/dialogs/ test/pages/settings_page_test.dart`
- [ ] **Step 3: 實作**（含 `fvm flutter gen-l10n`）。
- [ ] **Step 4: 跑測試確認通過**，再跑全套與 `fvm flutter analyze`。
- [ ] **Step 5: 實機驗證**（spec〈十六〉）：Windows 上把使用者提供的三個檔案（放在本機、不進 repo）以多種順序匯入，再抓一次官方資料，確認每個帳號 1155 筆且全為官方記錄；paimon 選錯帳號出現提醒。電腦視窗、手機直向與橫向各看一次所有新對話框（手機操作需使用者明講可以測）。
- [ ] **Step 6: Commit** — `feat(import): add third-party platform import for UIGF and paimon.moe`
