# 頌願抓取時補寫 `lang` 設計

## 背景與問題

頌願走的 API 是 `getBeyondGachaLog`，回應的 list 元素**不含 `lang` 欄位**（與一般祈願的 `getGachaLog` schema 不一致）。因此 `GachaRecord.fromApiJson`（`lib/models/gacha_record.dart:60`）目前把頌願 record 的 `lang` 填成空字串 `''`，並一路寫進本地存檔 json。

但擷取到的祈願 URL **本身帶 `lang` query 參數**（如 `lang=zh-tw`／`en`／`ja`），且每次組請求都帶著它。也就是說「這筆是用哪個語言抓的」這個資訊其實拿得到，只是沒被寫進 record。URL 的 `lang` 值與一般祈願 API 回傳的 `lang` 同格式同語意。

目標：**抓取頌願並寫入 json 時，把 `lang` 補成 URL 的 `lang`，而非空值。** 既有已存檔、`lang` 為空的頌願記錄也一併回填。

## 範圍與非目標

- **單純補 `lang`**：不新增任何抓取 HoYoWiki 的邏輯，不改動 HoYoWiki 管線。
- 不處理「匯入外部 json」路徑（那是另一條資料來源，與 API 再抓取無關）。

### 下游零副作用（無需額外守衛）

補 `lang` 後，頌願物品**不會**因此被 HoYoWiki 抓取，既有程式已在兩層擋掉：

1. **批次抓取**：更新後與 force-refetch 都走 `_fetchHoYoWiki`。它在 `gacha_repository.dart:782/788` 用 `hoyoWikiTargetGachaTypes = {'301','302','500','200','100'}` 過濾，頌願的 gachaType（`'2000'`／`'1000'`）在 `lang.isEmpty` 判斷之前就先被 `continue` 掉。
2. **on-demand 詳情**：`gacha_item_detail_dialog.dart:22/28` 的 `_odesGachaTypes = {'2000','1000'}` 讓頌願物品「永遠不可點」，dialog 不開、不觸發抓取。

其他用到 `record.lang` 的地方：

- `five_star_collection.dart:60`、`gacha_item_detail_dialog.dart:28`：兩者都在 lookup 之前以 gachaType 硬排除頌願，補 `lang` **行為零變化**。
- `item_type_kind.dart:15` 的 `itemTypeKeyOf`：**未**排除頌願，會經 `gacha_row`／`gacha_stats` 對頌願 record 呼叫。補 `lang` 前查 `'::name'`（空 lang）結構上保證 `null → fallback`；補 `lang` 後查 `'<lang>::name'`，**不再結構保證 null**，僅當某一般祈願物品同名同語言已被 HoYoWiki 索引時才命中，此時頌願 `itemTypeKey` 會從原始字串翻成 `kind:character`／`kind:weapon`。頌願裝扮名不與角色／武器撞名，實務影響趨近於零；且此為純本地 lookup，**不觸發任何抓取**。

故本設計**不需要任何「擋 HoYoWiki」守衛**（`itemTypeKeyOf` 的 nuance 僅為衍生標籤，且不涉及任何 I/O）。

## 資料來源與流向

頌願 record 的 `lang` 唯一可靠來源 ＝ 擷取 URL 的 `lang` query 參數。流向分兩條：

- **新抓的記錄**：在解析 API 回應時，以 URL 的 `lang` 作為 fallback 寫入 → record 一出生即帶正確 `lang`。
- **既有存檔記錄**：在合併（merge）回傳前，把 `lang` 為空者回填成 URL 的 `lang`。

兩條都只在 `lang` 為空時才套用 fallback／回填，因此一般祈願（API 已帶非空 `lang`）完全不受影響。

## 改動點

### 1. `lib/services/gacha_url.dart`

新增 getter，讓 fetcher 不必自己摸內部 `_uri`：

```dart
/// 擷取 URL 的 `lang` query 參數；缺漏時為空字串。
String get lang => _uri.queryParameters['lang'] ?? '';
```

### 2. `lib/models/gacha_record.dart`

- `fromApiJson` 新增具名參數 `String fallbackLang = ''`。`lang` 邏輯改為：API 有非空 `lang` 時用 API 的（一般祈願不受影響）；否則用 `fallbackLang`（頌願）。

  ```dart
  factory GachaRecord.fromApiJson(
    Map<String, dynamic> json, {
    required String gachaType,
    String fallbackLang = '',
  }) {
    final apiLang = json['lang'] as String?;
    return GachaRecord(
      // ……其餘欄位不變……
      lang: (apiLang == null || apiLang.isEmpty) ? fallbackLang : apiLang,
    );
  }
  ```

- 新增 `copyWith`，供回填產生新 record（YAGNI：當前只需改 `lang`）：

  ```dart
  /// 複製本 record，可覆寫 [lang]（其餘欄位沿用原值）。
  GachaRecord copyWith({String? lang}) => GachaRecord(
    id: id,
    uid: uid,
    gachaType: gachaType,
    name: name,
    itemType: itemType,
    rankType: rankType,
    time: time,
    lang: lang ?? this.lang,
  );
  ```

### 3. `lib/services/gacha_fetcher.dart`

- `fetchPage`：對稱既有的 `queryGachaType`，加抽 `queryLang`，並傳入 `fromApiJson` 作 fallback：

  ```dart
  final queryLang = url.queryParameters['lang'] ?? '';
  // ……
  GachaRecord.fromApiJson(
    e as Map<String, dynamic>,
    gachaType: queryGachaType,
    fallbackLang: queryLang,
  )
  ```

- `fetchBannerWithMerge`：回傳前回填 `existing` 中 `lang` 為空者。`url.lang` 為空（URL 缺 `lang` 參數）時整段跳過，避免把空值蓋空值。回填數 `> 0` 時記一行 log：

  ```dart
  final urlLang = url.lang;
  final List<GachaRecord> normalizedExisting;
  if (urlLang.isEmpty) {
    normalizedExisting = existing;
  } else {
    var backfilled = 0;
    normalizedExisting = existing.map((r) {
      if (r.lang.isEmpty) {
        backfilled++;
        return r.copyWith(lang: urlLang);
      }
      return r;
    }).toList(growable: false);
    if (backfilled > 0) {
      _log.info(
        'banner=$gachaType backfilled lang for $backfilled records to "$urlLang"',
      );
    }
  }
  return [...fresh, ...normalizedExisting];
  ```

> 一般祈願的 existing record 必有非空 `lang`，`r.lang.isEmpty` 為 false → 不變動；故此回填在實務上只作用於頌願。採通用的 `isEmpty` 判斷而非按 endpoint 特判，較精準也較簡潔。

## 測試

- **`test/models/gacha_record_test.dart`**
  - `fromApiJson` 頌願形態（`item_name`、無 `lang`）＋ `fallbackLang` → `lang` 為 fallback 值。
  - `fromApiJson` 一般祈願形態（API 帶 `lang`）＋ `fallbackLang` → API 的 `lang` 優先，fallback 被忽略。
  - `copyWith(lang: ...)` 只改 `lang`，其餘欄位不變。
- **`test/services/gacha_fetcher_test.dart`**
  - 新抓的頌願 fresh record 帶 URL 的 `lang`。
  - `fetchBannerWithMerge` 把 existing 中空 `lang` 的記錄回填成 URL 的 `lang`。
  - URL 無 `lang` 參數時不丟例外，existing 原樣保留。

## 驗收

- `dart format lib/ test/`、`flutter analyze`（`No issues found!`）、`flutter test`（`All tests passed!`）全綠。
