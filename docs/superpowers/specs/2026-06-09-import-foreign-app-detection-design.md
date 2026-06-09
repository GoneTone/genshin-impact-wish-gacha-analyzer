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
| 偵測動作 | 硬性拒絕（外來遊戲資料無法有意義地匯入），顯示在地化原因 |
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

新增判別函式（top-level、可單測；附 dartdoc）：

```dart
/// 判斷 raw 備份 JSON 是否**不是**本軟體匯出的。
///
/// 先看顯式 `app` 欄位（新檔權威依據）；無 `app` 的舊檔退而檢查
/// `accounts[*].banners` 的卡池代碼是否屬於 [gachaTypes] 已知集合。
/// 蒐集到代碼但無一屬於原神 → 外來；其餘（含原神代碼、空檔、結構讀不出）→ 視為非外來，交後續流程。
bool isForeignBundle(Map<String, dynamic> raw) { ... }
```

判別邏輯：

1. `final app = raw['app'];` 若 `app is String` → 回傳 `app != accountsBundleAppId`。
2. 否則蒐集卡池代碼：`raw['accounts']` 若為 `List`，逐一取 `entry['banners']`（若為 `Map`）的 keys，聯集成 `Set<String>`。
3. 已知集合：`final known = {for (final t in gachaTypes) t.gachaType};`
4. 若蒐集到的代碼集合非空且 `codes.intersection(known).isEmpty` → 回傳 `true`（外來）；否則 `false`。

> 容錯：任何讀取 raw 巢狀結構的步驟以型別檢查保護（非預期型別就略過該層）；讀不出任何代碼時回傳 `false`，把判斷讓給既有的 `FormatException`／版本檢查流程。

`importAccounts` 在確認 raw 是 `Map` 之後、呼叫 `AccountsBundle.fromJson` 之前插入：

```dart
  if (isForeignBundle(raw)) {
    _log.warning('import failed: foreign bundle (not from this app)');
    throw const ForeignBundleException();
  }
```

最終 `importAccounts` 的檢查順序：

1. `jsonDecode` 失敗 → `FormatException('Invalid JSON')`〔既有〕
2. 非 Map → `FormatException('Top-level value must be an object')`〔既有〕
3. **`isForeignBundle` → `ForeignBundleException`**〔新增，在版本檢查之前〕
4. `AccountsBundle.fromJson` → `UnsupportedSchemaVersionException`（版本過新）／`FormatException`（結構）〔既有〕

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

- `test/services/accounts_import_test.dart`（或新測試檔）：`isForeignBundle` 單測——
  - `app` 符合 → false；`app` 不符（如 `wuthering_waves_convene_gacha_analyzer`）→ true。
  - 無 `app` + banners key 全為原神代碼（如 `301`/`302`）→ false。
  - 無 `app` + banners key 全為鳴潮代碼（如 `1`/`2`/`7`）→ true。
  - 無 `app` + 空 `accounts`／無 banners／結構模糊 → false。
  - `importAccounts`：外來 raw（含 `app` 不符、或鳴潮代碼）→ 丟 `ForeignBundleException`。
  - **順序驗證**：外來檔即使 `schema_version: 999` 也應丟 `ForeignBundleException`（而非 `UnsupportedSchemaVersionException`）。
- `test/models/accounts_bundle_test.dart`：`toJson` 輸出含 `'app': accountsBundleAppId`；既有 round-trip 測試仍綠（`fromJson` 忽略 `app`）。
- `settings_page` 的型別→l10n 映射比照既有 reason key 不寫 widget test（純呈現映射，理由同前一支 spec）。

## 範圍外

- **姐妹專案（鳴潮 repo）加上對應 `app` 欄位**——那是另一個 repo，本次不做；列為建議後續，雙向就能對稱互拒。
- 不調整既有 `UnsupportedSchemaVersionException`／其餘 reason key（前一支 spec 已處理）。
- 不偵測「同為原神但更舊／更新格式」以外的細粒度差異——交由既有 schema_version 機制。
