# 卡池歷史資料語言轉換設計

## 背景與問題

`GachaRecord.name`／`itemType` 是「抓取或匯入當下的遊戲語言」原始字串，依 `record.lang` 而定。使用者若曾切換遊戲語言再同步、或匯入了不同語言的卡池記錄，同一份存檔就會**混語言**：部分物品是中文、部分英文、部分日文。

目標：在設定頁新增**獨立於應用程式介面語言**的「資料語言」設定，設定後讓卡池歷史資料統一成單一語言；轉換所需的各語言名稱透過 HoYoWiki 取得並**本地持久化快取**，切換語言再切回不需重抓。

本設計**忠實對齊姐妹專案**（鳴潮版 `wuthering-waves-convene-gacha-analyzer` PR #32，SHA `2a38f76`）的決策骨架（D1～D11），僅在「資料來源」（HoYoWiki ≠ encore.moe）與「genshin 資料模型」強制處改寫，**不擅自增減功能**。差異一律於下方對照表明列。

## 目標 / 非目標

### 目標

- 設定頁新增「資料語言」區塊：下拉（15 種 HoYoLab Wiki 語言＋「未設定（不轉換）」）＋「立即轉換資料語言」按鈕。
- 設定後，**更新資料／匯入資料**自動把該帳號資料轉換成設定語言。
- 轉換改寫存檔內的物品**名稱**與該筆 `lang`；類型維持語言無關（既有 `menu_id` 機制）、詳情自動跟上。
- 各語言名冊以 HoYoWiki `get_entry_page_list` 取得，持久化為 `lang_catalog/<lang>.json`，重複切換語言重用不重抓。
- 失敗一律吞例外、回原資料，**絕不中斷更新／匯入、絕不毀資料**。

### 非目標

- **頌願（odes，gachaType `2000`／`1000`）不在轉換範圍**：現行頌願被排除於 HoYoWiki 拓圖之外，其物品保持原狀（genshin 特有，姐妹專案無此分類）。
- 轉換範圍為**所有非頌願祈願**（`GachaCategory.gacha`＝`301`／`302`／`500`／`200`／`100`，即角色／武器／綜合／常駐／新手，物品皆落在 HoYoWiki menu_id 2／4），與既有 `hoyoWikiTargetGachaTypes` 一致。判準用 `convertibleGachaTypes`（由 `gachaTypes` 依 category 衍生，DRY）。
- 不重構既有 `HoYoWikiIndex`（search／entry_page／icon／詳情）子系統；新 catalog 子系統與其**並存**，不合併。
- 不做應用程式介面語言（App locale）的任何更動。

## 與姐妹專案的對齊對照（D1～D11）

| ID | 姐妹專案 | 本專案對齊狀況 |
|----|---------|--------------|
| **D1** 突變存檔 | 改寫 JSON 的 `name`／`languageCode`（／回查補 `resourceId`） | ✅ 改寫 `GachaRecord.name`／`lang`。genshin record **無 id 欄位**，故不存在「補 id」。 |
| **D2** 設定三態 | `dataLanguage`(`String?`)＋`dataLanguageSeeded`(bool)；pref key 不存在／`"none"`／語言碼 | ✅ 完全比照（見「設定與播種」）。 |
| **D3** 自動播種 | 僅 `!seeded` 時，bootstrap 取最新帳號語言、首次更新／匯入取該次語言；該語言須是選項之一才播種標記 | ✅ 完全比照。 |
| **D4** 改設定不動既有 | 改下拉只記目標語言，不自動轉既有 | ✅ 完全比照。 |
| **D5** 語言目錄快取 | `lang_catalog/<lang>.json`（`resourceId → {name, kind}`），缺才補抓；無時間過期，但**未命中自動刷新**（PR #33） | ✅ 改用 HoYoWiki：`<lang>.json`（`hoyowiki_id → {name, kind=menu_id}`）；同樣無時間過期 + 未命中自動刷新（見「未命中自動刷新」）。 |
| **D6** 目錄來源 | 擴充 `EncoreCatalog.nameByKindId`，複用 `fetchCatalog` | ✅ 改用 HoYoWiki `get_entry_page_list`（menu_id 2／4 分頁），新 `LangCatalogFetcher`。 |
| **D7** 名稱回查補 id | 合成負值 id／查無者用「原名＋原語言」目錄 `idByName` 回查真實 id 再轉 | ✅ **此即 genshin 的主路徑**：record 本無 id，永遠走 `srcCatalog.idByName[name] → id → targetCatalog.byId[id].name`。無「補 id 寫回」一說（record 無 id 欄位）。 |
| **D8** 類型跟 UI 語言 | 不動 `resourceType`，顯示走 `itemTypeKeyLabel(kind, l)` | ✅ 不動 `itemType`，顯示走既有 `itemTypeKeyLabel`。**需 index 橋接**（下述）以維持轉換後類型判定正確。 |
| **D9** 詳情跟資料語言 | 改 `languageCode` 後詳情／圖片自動以新語言補抓 | ✅ 改 `lang` 後，既有 `pageByLang[lang]` + lazy 抓取自動跟上。 |
| **D10** 更新／匯入後置轉換 | `update()`／importer 完成後若已設定則轉換再落地 | ✅ 完全比照。 |
| **D11** 失敗不毀資料 | 補抓失敗→優雅中止、回原資料、流程仍回報成功 | ✅ 完全比照。 |

### genshin 資料模型強制的差異（非擅自增減）

1. **無 `resourceId` 欄位**：故無 `backfilledId` 統計；結果框只顯示「轉換 N 筆／無法轉換 M 筆」兩個數字（姐妹專案顯示三個）。
2. **頌願排除、範圍為非頌願祈願（`GachaCategory.gacha`＝301／302／500／200／100）**：genshin 特有。
3. **index 橋接**：見下「轉換引擎」與「index 橋接」段——純為維持既有 D8／D9 行為的內部接線，非新使用者功能。
4. **未命中刷新的「強訊號」不同**：姐妹專案用「正值 `resourceId` 在目標目錄查無」判定目錄過期；genshin record 無 id，改用等價判準——「候選的原語言與目標語言**都是 15 選項之一**、卻在快取目錄解析不出名稱」。「語言是選項之一」這道守衛對應姐妹的 `resourceId > 0`，避免外部短碼資料白白觸發刷新。

## 架構與元件

### 1. 資料語言定義（新檔 `lib/services/data_language.dart`）

比照姐妹專案形狀，換成 15 種 HoYoLab Wiki 語言、代碼用 MiHoYo 標準 locale（與 `record.lang`／`X-Rpc-Language` 同一套）：

```dart
/// 單一可選資料語言：HoYoWiki 對齊的 [code] 與母語顯示 [label]。
typedef DataLanguageOption = ({String code, String label});

/// 可選資料語言清單（顯示順序固定），代碼對齊 HoYoLab Wiki，與 App UI 語言獨立。
const List<DataLanguageOption> kDataLanguageOptions = [
  (code: 'zh-tw', label: '繁體中文'),
  (code: 'zh-cn', label: '简体中文'),
  (code: 'en-us', label: 'English'),
  (code: 'ja-jp', label: '日本語'),
  (code: 'ko-kr', label: '한국어'),
  (code: 'es-es', label: 'Español'),
  (code: 'fr-fr', label: 'Français'),
  (code: 'ru-ru', label: 'Русский'),
  (code: 'th-th', label: 'ภาษาไทย'),
  (code: 'vi-vn', label: 'Tiếng Việt'),
  (code: 'de-de', label: 'Deutsch'),
  (code: 'id-id', label: 'Bahasa Indonesia'),
  (code: 'pt-pt', label: 'Português'),
  (code: 'tr-tr', label: 'Türkçe'),
  (code: 'it-it', label: 'Italiano'),
];

/// 可選資料語言代碼集合（供 seeding 判定語言是否在選項內）。
final Set<String> kDataLanguageCodes = {for (final o in kDataLanguageOptions) o.code};

/// [code] 是否為可選資料語言（用於自動播種：落在選項外則維持未設定）。
bool isSupportedDataLanguage(String code) => kDataLanguageCodes.contains(code);
```

> 確切 15 語言代碼以 HoYoLab Wiki Genshin 語言切換器為準；`label` 為母語名、不進 ARB、不隨 UI 語言。順序於 plan 階段定稿。

### 2. 設定與播種（三態，`AppSettings`／`SettingsStorage`／`SettingsNotifier`）

完全比照姐妹專案三態編碼：

- `AppSettings` 新增 `String? dataLanguage` + `bool dataLanguageSeeded`；`copyWith` 加 `dataLanguage`／`clearDataLanguage`／`dataLanguageSeeded`。
- `SettingsStorage` pref key `pref.dataLanguage`：

| key 狀態 | `dataLanguage` | `seeded` | 語義 |
|---|---|---|---|
| key 不存在 | `null` | `false` | **未初始化** → 可被自動播種 |
| key = `"none"` | `null` | `true` | **明確未設定／停用轉換** → 不轉換、**不再播種** |
| key = `"<code>"` | `code` | `true` | **指定語言** → 轉換 |

- `load`：`dataLanguage = (raw == null || raw == 'none') ? null : raw`；`dataLanguageSeeded = raw != null`。
- `save`：`!seeded → remove(key)`；`seeded → setString(key, dataLanguage ?? 'none')`。
- `setDataLanguage(String? code)`：使用者操作，一律 `seeded=true`；`code == null` = 明確選「不轉換」，停止自動播種。
- `seedDataLanguageIfUnset(String code)`：僅當 `!seeded` 且 `isSupportedDataLanguage(code)` 才播種並標記；否則 no-op（留待之後有效語言）。
- Provider `dataLanguageProvider = Provider<String?>((ref) => ref.watch(settingsProvider.select((s) => s.dataLanguage)))`。

### 3. 語言目錄子系統（新檔，對應姐妹 D5／D6／G）

並存於既有 `HoYoWikiIndex` 之外，專供名稱轉換。

**模型 `LangCatalog`**（記憶體）：
- `byId: Map<String, ({String name, int kind})>`（`kind` = menu_id 2／4）。
- `idByName: Map<String, String>`，由 `byId` 反推；**同名對到不同 id 者剔除**（ambiguous 不放入，避免誤判）。

**`LangCatalogFetcher`**（新檔 `lib/services/lang_catalog_fetcher.dart`）：
- `fetchCatalog(lang, {client})`：對 `menu_id` 為 2 或 4 各自分頁 POST `get_entry_page_list`：
  - URL `https://sg-act-public-api.hoyolab.com/hoyowiki/genshin/wapi/get_entry_page_list`
  - headers：`Referer: https://wiki.hoyolab.com/`、`X-Rpc-Language: <lang>`、`X-Rpc-Wiki_app: genshin`
  - body：`{"filters":[],"menu_id":"<2|4>","page_num":N,"page_size":50,"use_es":true}`
  - 逐頁累積 `data.list[]` 的 `entry_page_id → name`，標記 `kind = menu_id`，直到回傳空頁。
  - `retcode != 0` throw `ApiErrorException`（沿用既有例外）。
- 沿用既有 `HoYoWikiFetcher` 的並行度／timeout 慣例。

**`LangCatalogStorage`**（新檔 `lib/services/lang_catalog_storage.dart`）：
- 路徑：applicationSupport 下 `lang_catalog/<lang>.json`（與 `hoyowiki_index.json`／圖片快取同一資料根；確切 baseDir provider 於 plan 階段接既有 hoyowiki 快取目錄）。
- 格式：`{ "lang", "fetched_at"(ISO8601 UTC), "items": { "<id>": { "name", "kind" } } }`。
- 原子寫入（`.tmp` + rename）。`load` 解析失敗 → log warning、回 `null`（視為缺檔重抓）。

**`LangCatalogService`**（新檔 `lib/services/lang_catalog_service.dart`）：
- `_memo: Map<String, LangCatalog>`，**無時間過期（disk 為真相）**；但提供 `forceRefresh` 供「未命中刷新」（見轉換引擎）。
- `ensure(lang, {client, bool forceRefresh = false})`：
  - `forceRefresh == false` → 三層 memo → `storage.load` → 缺則 `fetcher.fetchCatalog` → `storage.save` → 存 memo 回傳。
  - `forceRefresh == true` → **略過 memo／本地、強制重抓並覆寫**（disk + memo）。
  - **網路失敗直接 throw**，由呼叫端決定吞例外。
- log `wish.langconvert.catalog`（來源 disk/remote、筆數）。

**Provider**（新檔 `lib/state/lang_catalog.dart`）：`langCatalogServiceProvider`。

### 4. 轉換引擎（新檔 `lib/services/gacha_language_converter.dart`，對應姐妹 B）

```dart
/// 轉換結果計數（genshin 無 resourceId，故無 backfilledId）。
class LangConvertResult {
  final int total;       // 在範圍內且 lang != target 的候選筆數
  final int converted;   // 成功轉換筆數
  final int unresolved;  // 無法轉換、保持原狀筆數
  LangConvertResult operator +(LangConvertResult o) => ...; // 多帳號聚合
}
```

介面（per 帳號 `BannerStorage`）：

```dart
Future<({BannerStorage data, LangConvertResult result, List<IndexHint> hints})>
  convert(BannerStorage data, String targetLang);
```

**流程**：
1. `ensure(targetLang)` 取目標目錄。
2. 掃描蒐集需補的原語言集合：`convertibleGachaTypes.contains(gachaType)` 且 `lang != target` 且 `lang` 非空者的 `lang`；逐一 `ensure(srcLang)`（失敗向上拋，交呼叫端吞）。
3. **未命中自動刷新（有界，對應姐妹 PR #33）**：以快取目錄試解析候選（`convertibleGachaTypes.contains(gachaType)`、`lang != target`、且 `lang` 與 `target` **都是 15 選項之一**），若存在「`srcCatalog.idByName[name]` 查無，或解出的 id 不在 `targetCatalog`」者，視為目錄過期（遊戲新版新增物品的強訊號）→ **強制重抓目標＋相關來源目錄各一次**（`ensure(..., forceRefresh: true)`）後再續。單次刷新、有界；HoYoWiki 真未收錄者，下次轉換才再試。
4. **逐筆處理**，分支順序：
   - **範圍外**（`!convertibleGachaTypes.contains(gachaType)`，含頌願 2000／1000）→ 原樣保留、不計數。
   - **同語言**（`lang == target`）→ 原樣保留、不計數（避免摘要灌水）。
   - 否則 `total++`，走名稱回查：`id = srcCatalog(record.lang).idByName[record.name]`；
     - `id == null` → `unresolved++`，原樣保留。
     - `targetName = targetCatalog.byId[id]?.name`；`null` → `unresolved++`，原樣保留。
     - 皆命中 → `record.copyWith(name: targetName, lang: targetLang)`，`converted++`，並記一筆 `IndexHint(lang: target, name: targetName, id: id, kind: catalog.kind)` 供 index 橋接。
5. 結尾 `wish.langconvert` info log（脫敏 uid、target、`total/converted/unresolved`）。回傳新 `BannerStorage` + result + hints。

> `GachaRecord.copyWith` 需擴充支援 `name`（既有僅 `lang`，PR #86 加入）。

### 5. index 橋接（維持 D8／D9，genshin 強制）

轉換改了 `name`＋`lang` 但**不動 `itemType`**。既有 `itemTypeKeyOf(record, index)` 以 `index.lookupId(name, lang) → menuId` 判類型；若 index 不認得 `<target>::<targetName>`，會 fallback 到原始（舊語言）`itemType` 字串，**導致類型跨語言分裂復發**。

故轉換落地後，repository 把 `hints` 寫入既有 `HoYoWikiIndex`（透過 notifier）：`searchMap['<target>::<targetName>'] = id`、`menuIds[id] = kind`。如此 `itemTypeKeyOf` 與五星一覽、icon／詳情 lookup 在轉換後續用既有路徑即正確；詳情頁資料本身仍走既有 lazy 抓取（D9）。

> 此橋接純為保留既有行為，不新增使用者可見功能。catalog 的 `id`／`kind` 與 index 的 `hoyowiki_id`／`menu_id` 本為同一套，故可直接餵入。

### 6. Repository 串接（`lib/state/gacha_repository.dart`，對應姐妹 C／D10／D11）

共用私有 `_convertAccountToDataLanguage(BannerStorage data)`：讀 `dataLanguageProvider`，`null` 原樣回；否則 `converter.convert(...)`，整段 try/catch 吞例外、warning log、回原 `data`（D11）；成功則套用 `hints` 至 index。

四觸發點：

1. **bootstrap 播種**：帳號載入後，取所有 UID 中最新（`lastUpdated`／最近 record `time`）語言 → `seedDataLanguageIfUnset(seedLang)`。**只播種、不轉換**（D4）。
2. **update 後置轉換**：合併出 `newData` → `_convertAccountToDataLanguage` → `GachaStorage.save` → 更新 state → `seedDataLanguageIfUnset(url.lang)`（首次更新播種）→ 之後既有 `_fetchHoYoWiki`／icon 補抓。**先轉存、後播種、最後補圖**。
3. **import 後置轉換**：逐帳號 `mergeWith` → `_convertAccountToDataLanguage` → `save`；全部處理完、套偏好後，以最新語言播種。
4. **`unifyDataLanguage()`（「立即轉換」按鈕）**：讀 `dataLanguageProvider`，`null` 回零結果；**立刻 emit `ConvertingDataLanguage` 進度狀態**（點擊當下即彈進度 dialog，文案「正在轉換資料語言」——不可重用 `Preparing`，那是 MITM 擷取 URL 用語「正在準備資料來源」）；**逐帳號** `convert → save → 套 hints`，聚合 result，單帳號失敗吞例外 warning 續跑；全部完成刷新 state；最後主動清進度狀態。**不跑逐物品 `_fetchHoYoWiki` prewarm**（genshin 特有取捨：HoYoWiki 須逐物品抓 `entry_page`，prewarm 會讓每次轉換卡數十秒；而 icon 為 lang-agnostic、平常更新時已快取，詳情本就 lazy 載入，故 prewarm 對 genshin 幾無增益卻嚴重拖慢——與姐妹用 encore bulk catalog（名稱＋icon 一次到位）的快速 prewarm 本質不同）。

### 7. 設定頁 UI（`lib/pages/settings_page.dart`，對應姐妹 F）

新 `SectionCard`（標題「資料語言」`settingsDataLanguage`，icon `Icons.translate`），內含 `_DataLanguageSection`：

- **說明文字** `settingsDataLanguageDesc`：「統一卡池歷史資料的物品名稱語言，獨立於應用程式介面語言。設定後更新或匯入資料會自動轉換成此語言。」
- **下拉** `DropdownButtonFormField<String?>`，`initialValue: current`：
  - 第一項 `value: null` → `settingsDataLanguageUnset`「未設定（不轉換）」。
  - 其後 15 項來自 `kDataLanguageOptions`（母語名）。
  - `onChanged` → `notifier.setDataLanguage(v)`（`_busy` 時禁用）。
- **「立即轉換資料語言」按鈕** `OutlinedButton.icon`：
  - `current == null || _busy` 時禁用。
  - icon：閒置 `Icons.sync`，忙碌 16×16 `CircularProgressIndicator`；label：閒置 `settingsDataLanguageUnify`、忙碌 `settingsDataLanguageUnifying`「轉換中...」。
  - InkWell／按鈕顯式 `mouseCursor: SystemMouseCursors.click`。
- **進度／結果 UI 生命週期**（對應姐妹 D）：
  - 進度：按下立刻 emit `ConvertingDataLanguage` → 既有進度 dialog 即時彈出（涵蓋「轉換＋catalog 抓取」期間）；因 unify 無 `UpdateCompleted` 終止狀態，結尾**主動清進度**關閉，避免卡死。切回已快取語言時轉換為純本地 remap，dialog 一閃即逝。
  - 結果 `AppDialog size: sm`：成功 `settingsDataLanguageUnifyDone(converted, unresolved)`「已轉換 {converted} 筆，{unresolved} 筆無法轉換。」；失敗 `settingsDataLanguageUnifyFailed`「轉換失敗，資料未變更。請檢查網路後重試。」
  - 期間 `_busy=true` 禁用下拉與按鈕。

所有 dialog 一律 `AppDialog`（遵 CLAUDE.md）。

### 8. i18n / Logging

- 新 ARB key：`settingsDataLanguage`、`...Desc`、`...Unset`、`...Unify`、`...Unifying`、`...UnifyDone(converted, unresolved)`、`...UnifyFailed`。從 `app_zh.arb` 起手，只加進已有實體翻譯的 ARB，省略號半形（`轉換中...`）。語言母語名走常數不進 ARB。
- Logger：`wish.langconvert`（轉換 summary）、`wish.langconvert.catalog`（目錄存取）；脫敏 uid。

## 資料流

- 下拉選語言 → `setDataLanguage` → 持久化（**不動既有資料**，D4）。
- 「立即轉換」→ `unifyDataLanguage` → emit `ConvertingDataLanguage` → 逐帳號 `convert`（catalog 驅動）→ `save` → 套 hints → 刷新 → 清進度 → 結果框（無逐物品 prewarm）。
- update／import → 合併 → `_convertAccountToDataLanguage` → `save` → `seedIfUnset` → 補圖。
- bootstrap → `seedIfUnset`（最新語言）。
- 切回先前抓過的語言 → `lang_catalog/<lang>.json` 已存 → 零網路（滿足「切回來不用再抓」）。

## 失敗處理（D11）

- update／import 時 catalog 補抓網路失敗 → `_convertAccountToDataLanguage` 吞例外、warning、回未轉 `data`，流程仍正常存檔回報成功。
- unify 單帳號失敗 → 迴圈內 try/catch 吞例外 warning（`unify skip uid=...`），續跑其他帳號，該帳號保留原資料。
- unify 整體例外 → UI catch 顯示 `settingsDataLanguageUnifyFailed`。
- 補圖失敗 → 既有 icon／詳情抓取本即 best-effort，不影響已完成轉換。
- catalog 壞檔／缺檔 → `load` 回 `null` 重抓。
- 寫檔 → catalog 與記錄皆原子寫入。
- 「無法轉換」只計 `unresolved`，不視為錯誤、不中斷。

## 邊界

- **頌願（2000／1000）及範圍外** → 完全不動、不計數。
- **同語言** → 不動、不計數。
- **`lang` 為空**（早期頌願已由 PR #86 回填；一般祈願罕見）→ 無原語言目錄可查 → `unresolved`，保留原狀。
- **第三方匯入短碼／非選項語言**（如 `en`／`ja`）→ 兩種情形：(a) 該語言 catalog **抓取失敗**（HoYoWiki 拒絕該 lang）→ `ensure` 向上拋 → `_convertAccountToDataLanguage` 吞例外 → **整帳號轉換中止、全部保留原狀**（D11）；(b) catalog 抓得到但**名稱查無** → 該筆 `unresolved`，保留原狀。亦即「整帳號中止」與「單筆 unresolved」依失敗發生在 catalog 取得階段或逐筆解析階段而定。
- **同名歧義**（同名對多 id）→ `idByName` 剔除 → 該名 `unresolved`，保留原狀。
- **dedup**：轉換改 `name`／`lang` 不改 record `id`，既有以 API id 去重不受影響。
- **3★ 武器**：HoYoWiki menu 4 含 3★，可轉；個別未收錄者 `unresolved` 保留。
- **`itemType` 刻意不轉（D8）**：轉換只改 `name`／`lang`，故轉換過的 record 在**原始 JSON** 會出現「name=目標語言、item_type=原語言」的不一致。此為**刻意取捨**：PR #86 後類型顯示一律走 `menu_id → itemTypeKeyLabel(UI 語言)`，`item_type` 原始字串已是顯示用不到的殘留欄位（僅 menu_id 查無時當 fallback，而轉換過的 record 經 index 橋接 menu_id 必命中、不會 fallback），故畫面類型欄／圓餅／篩選**不受影響**；不一致僅存在於檢視／匯出原始 JSON 時，無使用者可見 bug。跟齊姐妹 D8、符合 YAGNI。

## 測試

- `data_language`：清單完整、代碼唯一、`isSupportedDataLanguage`。
- `settings_storage`／`settings`：三態序列化（不存在／`none`／碼）；`setDataLanguage(null)` 標 seeded 停播種；`seedDataLanguageIfUnset` 僅 `!seeded` 且屬選項才播種；改設定不動 records。
- `lang_catalog_storage`：存讀、`fetched_at`、壞檔回 null、原子寫。
- `lang_catalog_fetcher`：分頁累積、menu 2／4、空頁停止、retcode≠0 拋例外。
- `lang_catalog_service`：memo → disk → remote 三層；切回重用不重抓；`forceRefresh` 略過 memo／disk 強制重抓覆寫。
- `gacha_language_converter`：同語言略過不計；範圍外不動；名稱回查命中轉換；`idByName` 歧義剔除；目標查無→unresolved；原語言目錄抓取失敗向上拋；`hints` 正確；`LangConvertResult` 聚合。
- `gacha_language_converter` **未命中自動刷新（對應姐妹 PR #33）**：原/目標都是選項之一且快取目錄解析不出 → 觸發目標＋來源各一次 `forceRefresh` 後轉成功（stale-catalog 回歸測試）；外部短碼／非選項語言的 miss **不**觸發刷新；刷新後仍 miss → unresolved。
- `gacha_repository`：update／import 後置轉換（已設定才轉）；bootstrap／首次 update／import 播種；`unifyDataLanguage` 多帳號聚合與單帳號失敗吞例外續跑；進度即時彈出＋結尾清空；hints 寫入 index 後 `itemTypeKeyOf` 正確（D8 不回歸）。
- `GachaRecord.copyWith`：`name` 覆寫。
- `settings_page`：下拉含「未設定」＋15 語言、選擇呼叫 setter；按鈕觸發 unify 與結果框；`current==null` 禁用按鈕。

## 驗收

- `fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）全綠。
- 本機 Windows 實機驗證：設定資料語言、按「立即轉換資料語言」、進度框即時彈出並正常關閉、轉換筆數正確、混語言存檔統一、切換語言再切回不重抓。
