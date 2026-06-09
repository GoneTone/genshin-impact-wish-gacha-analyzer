# 匯入時判別檔案是否由本軟體匯出設計

## 背景與目標

姐妹專案 [wuthering-waves-convene-gacha-analyzer](https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer)（鳴潮 Convene 抽卡分析器，同作者、同架構）與本專案（原神）使用**完全相同的匯出 JSON 形狀**：`AccountsBundle.toJson` 兩邊都寫 `schema_version`／`exported_at`／`app_version`／`last_active_uid`／`accounts`，且**都沒有任何 app／game 識別欄位**。因此目前匯入端無法分辨一個備份檔到底來自哪個遊戲——鳴潮的備份檔丟進原神 App 會被當成合法檔嘗試匯入。

兩個事實讓現況更糟：

- `app_version` 只是版本號（如 `1.0.0`），不識別 App。
- `currentSchemaVersion` 鳴潮是 `2`、本專案是 `1`。鳴潮 schema-2 檔目前會撞上版本檢查、顯示**錯誤訊息「請更新 App」**（其實是別款遊戲的檔）；而舊的鳴潮 schema-1 檔則完全擋不掉。

關鍵可靠依據：**祈願代碼空間不重疊**。本專案 `gachaTypes` 的代碼集合為 `{301, 302, 500, 200, 100, 2000, 1000}`；鳴潮用 `cardPoolType` `{1,2,3,4,5,6,8,9,10,11}`。在匯出 JSON 中，代碼是 `accounts[i].banners` map 的 key。

本設計用**兩者並用（hybrid）**的方式在匯入時判別「是否由本軟體匯出」，並在偵測到外來檔時以正確訊息拒絕。

**成功條件**

- 匯入鳴潮備份檔（含現有舊檔與未來檔、任何 schema 版本）一律被拒，並顯示「非本軟體匯出」的在地化訊息，而非誤導的「請更新 App」。
- 較新版**原神**檔仍正確顯示「請更新 App」（不被身分判別誤殺）。
- 本軟體自己的既有舊備份（無識別欄位、含原神代碼）仍可正常匯入。
- 無 `app` 欄位的舊檔若混入非原神 banner，只要含至少一個原神代碼即接受該檔，並只匯入可辨識的原神 banner、跳過未知 banner（不因未知記錄結構而整檔解析失敗）。
- 新匯出的檔帶有明確的 app 識別欄位；加欄位不破壞舊版 App 讀取既有檔。
- `fvm flutter analyze` 全綠、`fvm flutter test` 全綠。

## 決策摘要

| 面向 | 決策 |
|------|------|
| 判別機制 | 兩者並用：顯式識別碼（新檔權威）+ 內容嗅探（舊檔 fallback） |
| 識別碼欄位 | `app`，值為套件名字串 `genshin_impact_wish_gacha_analyzer` |
| schema_version | **不** bump（`app` 為純加法欄位，舊版 App 忽略未知欄位即可） |
| 內容判據 | `accounts[*].banners` 的 key 是否屬於 `gachaTypes` 代碼集合（重用單一真實來源，不另建表） |
| 判別時機 | 在 `importAccounts` 內、`AccountsBundle.fromJson` **之前**（在版本檢查之前，確保訊息正確） |
| 舊檔判別嚴格度 | **lenient + 過濾**：只要有任一原神代碼即接受該檔，但濾掉非原神 banner（整條跳過、不解析其記錄）；完全沒有原神代碼才整檔拒絕 |
| 偵測動作 | 純外來檔（顯式 `app` 不符，或舊檔無任何原神代碼）→ 硬性拒絕並顯示在地化原因；混合舊檔 → 接受並只匯入可辨識的原神 banner |
| 信任邊界 | 顯式 `app` **相符**的檔完整信任、不過濾（避免誤刪較新版本本軟體尚未認得的代碼，那情況交由 schema_version 機制） |
| 新例外 | `ForeignBundleException`（此備份非本軟體匯出） |
| 新 ARB key | `importReasonForeignApp`，9 個已翻語系（譯文經 workflow 翻譯＋校驗） |

## 設計

### 1. 識別碼常數與匯出（`lib/models/accounts_bundle.dart`、`lib/services/accounts_export.dart`）

在 `accounts_bundle.dart` 新增 top-level 常數（附 dartdoc）：

```dart
/// 本軟體的匯出識別字串，寫入備份檔的 `app` 欄位供匯入端辨識來源。
/// 值對齊 pubspec 套件名；姐妹專案（鳴潮）為 `wuthering_waves_convene_gacha_analyzer`，天生相異。
const String accountsBundleAppId = 'genshin_impact_wish_gacha_analyzer';
```

`AccountsBundle.toJson` 加寫 `app` 欄位（置於 `schema_version` 後）：

```dart
  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'app': accountsBundleAppId,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'last_active_uid': lastActiveUid,
    'accounts': accounts.map((a) => a.toJson()).toList(growable: false),
  };
```

`AccountsBundle.fromJson` **不需**讀 `app`（身分判別在 service 層讀 raw 完成）；既有 `fromJson` 本就忽略未知欄位，無須改動。`exportAccounts` 不需改（透過 `toJson` 自動帶上）。

> schema_version 維持 `1`：`app` 是純加法欄位，舊版本 App 讀新檔時忽略它即可，不觸發版本不相容。

### 2. 身分判別與 `ForeignBundleException`（`lib/services/accounts_import.dart`）

新增例外型別（附 dartdoc 與 `toString()`，對齊 [UnsupportedSchemaVersionException] 既有風格）：

```dart
/// 匯入檔不是由本軟體匯出（app 識別碼不符，或舊檔卡池代碼非原神已知集合）時拋出。
class ForeignBundleException implements Exception {
  /// 建立 [ForeignBundleException]。
  const ForeignBundleException();

  @override
  String toString() => 'ForeignBundleException';
}
```

`importAccounts` 在確認 raw 是 `Map` 之後、呼叫 `AccountsBundle.fromJson` 之前，依 `app` 欄位走兩條路：

```dart
  final app = raw['app'];
  final Map<String, dynamic> prepared;
  if (app is String) {
    if (app != accountsBundleAppId) {
      _log.warning('import failed: foreign bundle (app=$app)');
      throw const ForeignBundleException();
    }
    prepared = raw; // 本軟體自己的檔，完整信任、不過濾
  } else {
    prepared = _screenLegacyBundle(raw); // 無 app 的舊檔：判別 + 過濾未知 banner
  }
  // 既有版本／結構檢查（沿用目前的 try/catch）
  try {
    return AccountsBundle.fromJson(prepared);
  } on UnsupportedSchemaVersionException catch (e) { ... }
    on FormatException catch (e) { ... }
    catch (e, st) { ... }
```

> 信任邊界：顯式 `app` **相符**的檔不過濾。若未來版本新增了本版本還不認得的代碼，過濾會誤刪資料；那情況本就由 `AccountsBundle.fromJson` 的 schema_version 檢查（→ `UnsupportedSchemaVersionException`「請更新 App」）把關。

無 `app` 欄位的舊檔交由下列 helper 判別並過濾（附 dartdoc）：

```dart
/// 處理無 `app` 欄位的舊備份：依卡池代碼判別是否為本軟體（原神）檔，並濾掉非原神 banner。
///
/// 蒐集 `accounts[*].banners` 的 key 與 [gachaTypes] 已知集合比對：
/// - 確有卡池資料、但無一是原神代碼 → 丟 [ForeignBundleException]（純外來，如鳴潮檔）。
/// - 否則回傳濾除未知 banner 後的 raw：未知代碼的 banner 整條跳過（不解析其記錄），
///   濾空的帳號一併移除，只保留可辨識的原神 banner。
/// - 讀不出任何卡池資料（空檔／結構模糊）→ 原樣交回，由 [AccountsBundle.fromJson] 後續處理。
Map<String, dynamic> _screenLegacyBundle(Map<String, dynamic> raw) { ... }
```

`_screenLegacyBundle` 邏輯：

1. `final known = {for (final t in gachaTypes) t.gachaType};`（已知集合 `{301,302,500,200,100,2000,1000}`）。
2. `raw['accounts']` 非 `List` → 原樣回傳（結構錯誤交 `fromJson` 報）。
3. 逐一帳號：`entry` 或 `entry['banners']` 非 `Map` → 原樣保留該 entry（交 `fromJson` 處理）；否則逐一 banner key，只保留 `known.contains(key)` 的；同時記錄「是否見過任何代碼」`sawAnyCode` 與「是否保留了任何原神 banner」`keptAnyKnown`。
4. 帳號濾後 banners 非空 → 以濾後 banners 重建該 entry 加入；濾空（原本就有 banner 但全非原神）→ 丟棄該帳號。
5. `sawAnyCode && !keptAnyKnown` → 丟 `ForeignBundleException`（純外來）。
6. 否則回傳 `{...raw, 'accounts': 濾後清單}`。

> 容錯：讀取 raw 巢狀結構每層都以型別檢查保護，非預期型別就原樣保留交 `fromJson`；讀不出任何代碼（空檔）時不判外來、原樣交回。過濾在解析記錄**之前**完成，故未知 banner 內若是別款遊戲的記錄結構也不會觸發解析錯誤。

最終 `importAccounts` 的檢查順序：

1. `jsonDecode` 失敗 → `FormatException('Invalid JSON')`〔既有〕
2. 非 Map → `FormatException('Top-level value must be an object')`〔既有〕
3. **身分判別**〔新增，在版本檢查之前〕：顯式 `app` 不符 → `ForeignBundleException`；無 `app` 的舊檔經 `_screenLegacyBundle` →（純外來）`ForeignBundleException`／（其餘）濾後 raw。
4. `AccountsBundle.fromJson(prepared)` → `UnsupportedSchemaVersionException`（版本過新）／`FormatException`（結構）〔既有〕

`gachaTypes` 來自 `lib/data/gacha_types.dart`（`accounts_import.dart` 需 import 之）。`gachaTypes` 為 const list，取 `.gachaType` 不會觸發 `resolveName`（不需 `AppLocalizations`），純 Dart 單測可直接使用。

### 3. UI（`lib/pages/settings_page.dart`）

`importAccounts` 的 try/catch 加 `on ForeignBundleException` 一臂（與既有 `on UnsupportedSchemaVersionException`／`on FormatException` 並列，順序不拘——三型別互斥）：

```dart
    } on ForeignBundleException {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(l.settingsImportFailed(l.importReasonForeignApp)),
        ),
      );
      return;
    }
```

英文細節已於 `importAccounts` 內 `_log.warning`，UI 不重複 log。

### 4. i18n（ARB）

新增 1 個 key `importReasonForeignApp`，比照既有 reason key（無 placeholder、無 `@` 區塊），加進 9 個已翻語系（`zh`／`en`／`fr`／`es`／`ja`／`vi`／`th`／`zh_Hans`／`pt_BR`），空殼語系留給 Crowdin。

繁中（`app_zh.arb`，來源）初稿：

```json
  "importReasonForeignApp": "此檔案不是由本軟體匯出的備份（可能來自其他遊戲的版本）",
```

其餘 8 語系譯文於實作前透過翻譯＋對抗式校驗 workflow 產出，沿用各檔既有語氣與用詞。寫入後跑 `fvm flutter gen-l10n`（產物 `lib/l10n/generated/` 未進版控、不 commit）。

### 5. 測試

- `test/services/accounts_import_test.dart`：以 `importAccounts` 為入口驗證可觀察行為——
  - **顯式 `app` 不符**（如 `wuthering_waves_convene_gacha_analyzer`）→ 丟 `ForeignBundleException`。
  - **顯式 `app` 相符** → 正常回傳，且不過濾（即使含本版本未知代碼也保留）。
  - **無 `app` + 純原神代碼**（`301`/`302`…）→ 正常回傳，banner 全數保留。
  - **無 `app` + 純鳴潮代碼**（`1`/`2`/`7`）→ 丟 `ForeignBundleException`。
  - **無 `app` + 混合**（`301` + `1`）→ 正常回傳，且回傳的 bundle **只含 `301` banner、不含 `1`**（驗證未知 banner 被濾掉）；若某帳號只剩未知代碼則該帳號被移除。
  - **無 `app` + 空 `accounts`／無 banners** → 不判外來，正常回傳（空 bundle）。
  - **順序驗證**：純外來檔（無 `app`、純鳴潮代碼）即使 `schema_version: 999` 也應丟 `ForeignBundleException`（而非 `UnsupportedSchemaVersionException`）。
- `test/models/accounts_bundle_test.dart`：`toJson` 輸出含 `'app': accountsBundleAppId`；既有 round-trip 測試仍綠（`fromJson` 忽略 `app`）。
- `settings_page` 的型別→l10n 映射比照既有 reason key 不寫 widget test（純呈現映射，理由同前一支 spec）。

## 範圍外

- **姐妹專案（鳴潮 repo）加上對應 `app` 欄位**——那是另一個 repo，本次不做；列為建議後續，雙向就能對稱互拒。
- 不調整既有 `UnsupportedSchemaVersionException`／其餘 reason key（前一支 spec 已處理）。
- 不偵測「同為原神但更舊／更新格式」以外的細粒度差異——交由既有 schema_version 機制。
