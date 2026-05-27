# 清理未使用的翻譯 key — 設計

日期：2026-05-19
分支：flutter-rewrite

## 目標

一次性移除專案 i18n 中未被使用的翻譯 key，使模板與所有語言 arb 的 key 集合一致、每個 key 在 `lib/` 都有實際存取。不留下任何腳本或工具（YAGNI）。

## 背景

- 模板檔：`lib/l10n/app_zh.arb`（約 389 key）
- 9 個語言 arb：`app_zh, app_zh_Hans, app_en, app_es, app_fr, app_ja, app_pt, app_th, app_vi`
- 產生目錄：`lib/l10n/generated/`
- 存取方式單純：`AppLocalizations.of(context)!.keyName` 或 `final l = AppLocalizations.of(context)!; l.keyName`
- 已確認：無動態字串組 key、無 extension helper、無反射查找 → 靜態掃描偵測可靠
- 偵測誤差方向天然安全：generated getter 名 = key 名，若 `lib/` 有同名 `.xxx` 會被當「有用」保留，不會誤刪在用的 key

## 範圍決策（已與使用者確認）

- 產出形式：**一次性清掉**，不留腳本 / CI 檢查
- 「被使用」判定範圍：**只看 `lib/`**（`test/` 引用不算數）
- 同時清「**孤兒 key**」：只出現在某些語言 arb、模板裡沒有的 key

## 方案

採方案 A：grep 偵測 + 逐行移除，保留原檔排版使 diff 最小。
（方案 B 重新序列化 JSON 會整檔重排，diff 爆炸；方案 C 引入套件＝過度工程，皆不採用。）

## 設計

### 1. 偵測階段

- 解析 `lib/l10n/app_zh.arb`，取出所有非 metadata 頂層 key（排除 `@@locale`、`@@x-*`、`@key` 描述區塊）。
- 對每個 key 用 ripgrep 在 `lib/**/*.dart` 搜 `\.<key>\b`，**排除** `lib/l10n/`。零命中 → 「未使用」。
  - getter 與帶 placeholder 的 method 呼叫皆被 `\.<key>\b` 涵蓋。
- 掃 9 個 arb，key 不存在於模板者 → 「孤兒」。
- 特別保護驗證：明確確認 `localeNativeName`、`localeTranslator`、`localeTranslatorLabel` 在 `lib/` 有 `.xxx` 存取；若意外落入未使用清單，需人工複核才刪。

### 2. 移除階段

- 對 9 個 arb 逐檔按行刪除：
  - 未使用 key 的 `"key": "..."` 行（多行字串一併處理）
  - 對應 `"@key": { ... }` metadata 區塊（可能跨多行）
  - 所有孤兒 key（同上）
- 保留原縮排、key 順序、尾隨逗號正確性；不重排、不整檔重新序列化。

### 3. 重新產生 + 收尾

- 跑 `flutter gen-l10n`（或 `flutter pub get` 觸發）重新產生 `lib/l10n/generated/`。
- 修測試：`test/` 引用到已刪 key 而編譯失敗者，連同移除 / 改寫。
- 品質閘（依 CLAUDE.md，全綠才算完成）：
  1. `dart format lib/ test/`
  2. `flutter analyze` → `No issues found!`
  3. `flutter test` → `All tests passed!`

### 4. 風險與緩解

| 風險 | 緩解 |
|---|---|
| 同名 `.key` 在非 l10n 程式碼出現，導致該刪沒刪 | 可接受（保守、留垃圾不誤刪），不額外處理 |
| 多行 arb 值 / metadata 刪不乾淨造成 JSON 壞掉 | 刪除後立即 `flutter gen-l10n` + `flutter analyze` 驗證 arb 合法 |
| `localeNativeName` 等動態走訪型 key 被誤列 | 偵測後人工複核這幾個特別 key 才刪 |
| 孤兒 key 行含特殊跳脫字元 | 按行精準比對刪除，不用寬鬆正則 |

### 5. 成功標準

- 模板與 9 個 arb 的 key 集合一致，且每個 key 在 `lib/` 都有實際存取。
- generated code 同步更新。
- 三項品質閘全綠。
- diff 僅含「刪除行」+ generated 變更，無格式雜訊。
