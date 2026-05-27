# 舊版翻譯挖掘：master 語系 → Flutter ARB 對照報告

- 日期：2026-05-16
- 分支：flutter-rewrite
- 狀態：設計已確認，待寫實作計畫

## 目標

舊版 `master`（Vue 網頁版）在 `src/locales/*.json` 有多語人工翻譯。新版 Flutter
以 ARB 重寫，多數語言的 `lib/l10n/app_*.arb` 嚴重缺漏。本任務挖掘舊版翻譯，
產出**一份對照報告**供人工審閱，決定哪些可套用至新版 ARB。

**本任務不修改任何 `lib/l10n/*.arb`。** 輸出僅為報告。

## 背景現況

舊版 key 為點號式（`ui.text.table.name`），新版為駝峰式（`tableName`），
兩邊 key 完全不對應，功能集亦不同（舊版有 Excel 匯出、網頁簽到、互動地圖）。
唯一可靠橋樑：**舊 `zh_TW.json` 的值 == 新 `app_zh.arb` 的值**（中文原文比對）。

`lib/l10n/app_zh.arb`（259 keys）為基準，**不得修改**。

新版 ARB 完整度：`app_en` 232、`app_zh_Hans` 205、`app_es`/`app_th` 40、
`app_ja` 35、`app_fr` 31、`app_pt` 24、`app_vi` 14（基準 259）。

舊版各語言完整度（以 zh_TW 為基準）：

| 舊檔 | 完整度 | 對應新版 |
|---|---|---|
| es_ES | 完整 | es |
| th_TH | 完整 | th |
| ja_JP | ~95% | ja |
| zh_CN | 完整 | zh_Hans |
| fr_FR | ~64% | fr |
| pt_BR | ~38% | pt |
| vi_VN | ~12% | vi |
| de_DE / ko_KR / ru_RU / pt_PT | 空 | 無價值，排除 |

## 已確認決策

1. **產出形式**：先出對照報告（不自動套用 ARB）。
2. **比對嚴格度**：分兩階標記 — byte 完全一致＝高信心；正規化後一致＝中信心。
   不做語義相近（如「級別」↔「稀有度」）。
3. **語言範圍**：全部 7 種（es / th / ja / zh_Hans / fr / pt / vi）。

## 設計

### 比對引擎

1. 解析 `lib/l10n/app_zh.arb` → `{newKey: 中文值}`，排除 `@@locale`、
   所有 `@`-前綴 metadata key、`localeNativeName`、`localeTranslator`。
2. `git show master:src/locales/zh_TW.json` → `{oldKey: 中文值}`，
   建「中文值 → oldKey 清單」反向索引（值重複保留多個 oldKey）。
3. 每個 newKey 以其中文值查舊 zh_TW：
   - byte 完全一致 → **高信心**
   - 正規化後一致 → **中信心**
   - 查無 → 不列入報告（無噪音）
4. 正規化規則（僅用於分階，不改寫翻譯本身）：
   - 去首尾空白
   - 全形/半形標點統一（冒號、引號、括號、驚嘆號等）
   - 所有 `{xxx}` placeholder 位置化為 `{}`
   - **不**統一 `5★`↔`5星`、全/半形數字等語義層差異
5. 對每個命中 `(newKey ↔ oldKey)`，自 7 個舊語言檔
   （es_ES / th_TH / ja_JP / zh_CN / fr_FR / pt_BR / vi_VN）
   取非空翻譯；缺失或空字串則該語言不列該候選。

### 旗標

- 🟢 高信心 / 🟡 中信心
- ⚠️ placeholder 名稱不同（舊 `{gacha_name}` vs 新 `{name}`）→ 套用須改名
- ⚠️ ICU 結構不同（新 `{count, plural, ...}` vs 舊平鋪）→ 不可直接套，需手改結構
- 📝 新版已有值 → 可能覆蓋，預設不建議動
- ⬜ 新版空缺 → 填補缺口，最高套用價值
- 🔀 撞中文：同句中文對應多個 oldKey → 列出全部 oldKey，提醒語境差異需挑選

### 報告結構

`docs/superpowers/i18n-migration/translation-candidates.md`，UTF-8。

依語言分組，順序：es → th → ja → zh_Hans → fr → pt → vi。
每組內排序：空缺且高信心 → 空缺中信心 → 已有值（參考/覆蓋候選）。

每列欄位：

```
| 新 key | 中文原文 | 舊翻譯候選 | 新版現值 | 信心 | 舊 oldKey 路徑 | 旗標 |
```

每組組末統計：可填補數 / 高信心數 / 需手改 placeholder 數 / 需手改 ICU 數。

### 執行與產出

- 腳本：`docs/superpowers/i18n-migration/extract_candidates.py`，
  僅標準庫（`json`、`subprocess`）。
- 舊檔一律經 `git show master:src/locales/<x>.json` 讀取，
  不 checkout、不動工作區。
- 終端印出每語言摘要統計，細節寫入 .md。
- 腳本與報告皆**不進版控**（沿用 `docs/superpowers` gitignored 慣例）。

### 邊界情況

- 舊語言檔某 key 缺失或空字串 → 該語言不列該候選。
- 舊 zh_TW 查無對應中文 → newKey 完全不出現於報告。
- `app_zh.arb` 的 `@`-meta / `@@locale` / `localeNativeName` /
  `localeTranslator` → 全數排除。
- 同中文多 oldKey → 全列出並標 🔀。

## 不做（YAGNI）

- 不寫可重用的多語系遷移框架（master 為死分支，單次任務）。
- 不自動寫入 ARB。
- 不做語義相近模糊比對。
- 不處理 de/ko/ru/pt_PT（舊版為空）。
