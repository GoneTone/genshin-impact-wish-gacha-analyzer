# 補齊 zh_Hans / en / ja 三語翻譯：設計

- 日期：2026-05-17
- 分支：flutter-rewrite
- 狀態：設計已確認，待寫實作計畫

## 目標

依 template `lib/l10n/app_zh.arb`（259 個翻譯 key，基準、不得修改）完整重建三個
語系檔，每檔 259 key 全數補齊，結構逐行鏡像 template：

- `lib/l10n/app_zh_Hans.arb`（現 205 key，缺 ~54，結尾結構壞掉、key 散亂）
- `lib/l10n/app_en.arb`（現 232 key，缺 ~27，有人工翻譯與譯者掛名）
- `lib/l10n/app_ja.arb`（現 35 key，缺 ~224，嚴重缺漏、有譯者掛名）

翻譯需在地化（非逐字轉換），遊戲專有名詞一律使用 HoYoverse 官方 in-game 譯名。

## 已確認決策

1. **產出方式**：完整重建、逐行鏡像 `app_zh.arb` 結構。不做最小補缺。
2. **@-metadata**：locale 檔保留 `@`-metadata 區塊鏡像 template（內容照抄；Flutter
   gen-l10n 實際只從 template `app_zh.arb` 讀 placeholder metadata，locale 檔的
   為結構對齊用，不影響功能）。
3. **值來源優先序**（每 key 逐一決定）：
   1. 該檔現有且正確的人工翻譯 → 沿用（保留 en / ja 既有譯文與譯者掛名）。
   2. 現有檔無此 key → 依 `app_zh.arb` 原文本地化新譯。
   3. 所有套用／新譯的遊戲專有名詞 → 以鎖定的官方術語表回頭校正一遍（含既有
      譯文也要校）。
4. **不沿用舊版 master 翻譯**：不做 `master:src/locales/*.json` 中文值橋接 mining。
   舊譯僅當非強制參考。
5. **術語表全查證**：glossary 所有詞條（不只不確定者）上網查 HoYoverse 官方
   譯名後鎖定，再開始填值。查不到可靠官方來源者標「暫譯，待確認」，不默默亂填。

## 在地化要求

非逐字轉換，須符合各語言 UI 慣用語：

- **zh_Hans**：中國大陸慣用語。例：軟體→软件、網路→网络、資料→数据、
  帳號→账号、復原→撤销、專案→项目（含校正現有檔 `contributorsProjectLicense`
  「专案许可证」→「项目许可证」、`contributorsProjectLeader`「专案负责人」等）。
- **ja**：日文 UI 慣用語與助詞；數字／`{placeholder}` 與單位間距符合日文排版。
- **en**：自然英文 UI 文案，sentence case，與既有風格一致。

`localeTranslator`：en / ja 保留現有掛名；zh_Hans 維持空字串（無掛名 →
不顯示譯者列，符合 `@localeTranslator` 說明）。

## 官方術語表（glossary）

填值前先建立並鎖定。下表為初判，**全部詞條**以實際查到的官方 in-game 譯名為準：

| 繁中原文 | EN | JA | zh_Hans |
|---|---|---|---|
| 祈願 | Wish | 祈願 | 祈愿 |
| 角色活動祈願 | Character Event Wish | キャラクターイベント祈願 | 角色活动祈愿 |
| 武器活動祈願 | Weapon Event Wish | 武器イベント祈願 | 武器活动祈愿 |
| 集錄祈願 | Chronicled Wish | 集録祈願 | 集录祈愿 |
| 常駐祈願 | Standard Wish | 通常祈願 | 常驻祈愿 |
| 新手祈願 | Novice Wishes | 初心者向け祈願 | 新手祈愿 |
| 頌願（活動／常駐） | 待查證 | 待查證 | 颂愿 |
| 保底 | 待查證（社群慣用 Pity） | 天井 | 保底 |
| 稀有度 | Rarity | レアリティ | 稀有度 |
| UID | UID | UID | UID |

- 查證方式：WebSearch / WebFetch，優先官方來源（HoYoLAB、官方公告、官方
  wiki）。`頌願` 為較新玩法（本 app 才有），EN/JA 官方名重點查。
- glossary 鎖定後寫入實作計畫，所有相關 key 引用同一譯名，跨語言一致。
- 非遊戲詞（export/import、保底相關 UI 句等）走一般本地化，不進 glossary。

## 檔案結構規格

逐行鏡像 `app_zh.arb`：

- `@@locale` = `zh_Hans` / `en` / `ja`。
- `localeNativeName` = 简体中文 / English / 日本語；`localeTranslator` 依上述。
- 之後 259 個 key 依 `app_zh.arb` **完全相同的順序**排列，保留相同分組空行與
  相同 `@`-metadata 區塊（內容照抄 template）。
- UTF-8、2-space 縮排、合法 JSON、結尾無 trailing comma。

## 逐檔流程

1. 建 glossary（查證 → 鎖定）。
2. 對每檔（zh_Hans → en → ja）：逐 key 依值來源優先序填值，套 glossary。
3. 三檔各自輸出為完整鏡像結構檔。

## 驗證

提交前依 CLAUDE.md 順序，全通過才算完成：

1. `dart format lib/ test/`
2. `flutter analyze` → 必須 `No issues found!`
3. `flutter test` → 必須 `All tests passed!`
4. 一次性比對腳本（不進版控）：
   - 三檔 key 集合 == `app_zh.arb` key 集合（無多無缺）。
   - 每個值的 `{placeholder}` 名稱集合與 `app_zh.arb` 對應 key 一致。
   - ICU `plural`/`select` 結構與 `app_zh.arb` 一致。
   - 零差異才算過。

## 不做（YAGNI）

- 不做 master 舊譯 value-bridge mining。
- 不寫可重用多語系遷移框架（單次任務）。
- 不修改 `app_zh.arb` 及其他語系檔（fr / es / pt / th / vi）。
- 不調整 l10n.yaml 或產碼設定。

## 版控

spec 與一次性驗證腳本沿用 `docs/superpowers` gitignored 慣例，不進版控。
僅 `lib/l10n/app_zh_Hans.arb` / `app_en.arb` / `app_ja.arb` 三檔為交付物。
