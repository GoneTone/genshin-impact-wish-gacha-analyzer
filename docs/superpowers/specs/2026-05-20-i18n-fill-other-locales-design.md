# 補完 ja / zh_Hans / es / fr / pt / th / vi 翻譯：設計

- 日期：2026-05-20
- 分支：flutter-rewrite（直接 push，不開 PR）
- 狀態：設計已確認（使用者於 2026-05-20「ok」），待寫實作計畫

## 目標

依 template `lib/l10n/app_zh.arb`（208 個翻譯 key）補齊以下七個語系檔的缺漏 key：

| 語系 | 現有 key | 缺漏 | localeTranslator 動作 |
|---|---|---|---|
| ja | 195 | 13（皆為 `shareImage*`） | 已含 Claude Code（**不動**） |
| zh_Hans | 195 | 13（皆為 `shareImage*`） | 空（**不動**，使用者明確指示） |
| es | 37 | 171 | 尾端附加 `, <a href=...>Claude Code (Opus 4.7)</a>` |
| fr | 28 | 180 | 原本空字串 → 設為 `<a href=...>Claude Code (Opus 4.7)</a>` |
| pt | 22 | 186 | 沿用 `&` 連接，新項以 `, ` 附加 Claude Code |
| th | 37 | 171 | 尾端附加 Claude Code |
| vi | 13 | 195 | 原本空字串 → 設為 Claude Code 單獨一項 |

`en`（208，完整）與 `zh`（template）不動。`zh` 的 localeTranslator 依使用者指示不動。

合計補缺：929 個翻譯項。

## 已確認決策

1. **只補缺，不改既有譯文**：保留社群既有譯者風格，即使品質有瑕疵（如 pt 既有翻譯有明顯問題）也不動，避免 scope creep 與覆寫他人貢獻。
2. **不開 PR**：直接 push 到 `flutter-rewrite`，每語系一個 commit（共 7 個）。本質為機械翻譯補缺，無架構/邏輯變動。
3. **不確定的官方術語跳過**：若查不到某語系對某遊戲專有詞的官方原神譯文，該 key 整筆**不寫入**（保留為缺）。最後彙整 Skip List 回報使用者。**不**用英文/原文 fallback。
4. **localeTranslator** 規則依上表，繁中（zh）與簡中（zh_Hans）不動。
5. **placeholder 與 ICU plural 格式照搬**：`{n}`、`{star}` 等變數名、ICU `plural`/`select` 結構與 template 完全一致。既有 es/fr/pt 已用 ICU `plural` 形式的 key（如 `relativeSecondsAgo`），新增項若有 count 也比照辦理。

## 在地化要求

非逐字轉換，須符合各語言 UI 慣用語：

- **ja**：補 13 個 `shareImage*`，沿用既有檔案風格（敬語、半形括號、片假名 UI 詞）。
- **zh_Hans**：補 13 個 `shareImage*`，使用中國大陸慣用語（軟體→软件、資料→数据、帳號→账号、復原→撤销、專案→项目）。
- **es** / **fr** / **pt**：歐洲西文/法文/葡文。注意 fr 的 `Voeux`（OE 連字）與既有檔案一致；pt 接受既有 BR/PT 不分（既有譯者命名為 `Português` 未分區）。
- **th**：泰文 UI 慣用語，數字與單位之間空格依既有檔案風格。
- **vi**：越南文，動詞名詞慣用「nhân vật」「vũ khí」（既有檔案已採用）。

## 官方術語表（glossary）擴充

既有 `docs/superpowers/i18n-glossary-2026-05-17.md` 已鎖定 en/ja/zh_Hans 三語的原神術語。本次需**延伸**該檔，新增 es/fr/pt/th/vi 五欄。重點查證對象：

- `gachaType*`：角色活動祈願 / 武器活動祈願 / 集錄祈願 / 常駐祈願 / 新手祈願 / 活動頌願 / 常駐頌願
- `pity`（保底）、`rarity`（稀有度）、星級寫法
- `navSectionGacha`、`navSectionOdes`
- 「祈願」、「頌願」、「卡池」核心名詞

查證來源優先序：
1. HoYoverse 官方各語系網站（hoyoverse.com）：公告、官方介紹頁
2. 官方遊戲內截圖（玩家社群貼文）
3. Fandom Wiki 各語版（次要參考）

**頌願（Odes）**：HoYoverse 在 en/ja/zh_Hans 之外的語系尚無官方分類名公開，**很可能在多數語系需跳過**`gachaTypeOdes*` 與 `navSectionOdes`、`navOdesEvent`、`navOdesStandard`、`pageOverviewOdesSection`、`emptyNoOdesRecords` 等與「頌願」直接相關的 key。

glossary 擴充寫入新檔 `docs/superpowers/i18n-glossary-2026-05-20-other-locales.md`（既有 `2026-05-17` 那份保持不變，只覆 en/ja/zh_Hans），不進版控。

## 檔案編輯規格

對每個目標語系檔：

- **不動既有 key**（保留 value 與順序）。
- **新增 key** 插入位置：以 template `app_zh.arb` 的相對順序為基準，盡量靠近相鄰既有 key（如新增 `actionCancel` 緊接 `actionUpdate`）。容許輕微順序差異——閱讀友善優先，gen-l10n 不依賴順序。
- 新增 placeholder metadata：若 template 中該 key 有 `@key` 區塊（如 `@progressFetchingBanner`），locale 檔可加可不加（locale 檔的 metadata 不影響 gen-l10n，只影響可讀性）。**統一不加**，以最小變更為原則。
- UTF-8、2-space 縮排、合法 JSON、結尾無 trailing comma。
- `localeTranslator` 修改依上表規則執行。

## 逐檔流程

按缺漏量由少到多依序處理（先小後大、容易發現問題時及時調整流程）：

1. `app_ja.arb`（補 13 個 `shareImage*`，最簡單）
2. `app_zh_Hans.arb`（補 13 個 `shareImage*`）
3. `app_es.arb`（補 171 個 + localeTranslator）
4. `app_th.arb`（補 171 個 + localeTranslator）
5. `app_fr.arb`（補 180 個 + localeTranslator）
6. `app_pt.arb`（補 186 個 + localeTranslator）
7. `app_vi.arb`（補 195 個 + localeTranslator）

每個檔案處理完即執行驗證並 commit。

## 驗證（每個 commit 前）

依 CLAUDE.md 強制三項：

1. `dart format lib/ test/` — 須無變動或自動格式化
2. `flutter analyze` — 必須 `No issues found!`
3. `flutter test` — 必須 `All tests passed!`

額外人工檢查：

- placeholder 名稱集合與 template 一致（避免 `{count}` 誤寫成 `{n}` 等）
- `{star}`、`{n}` 等動態變數的數量與 template 對齊
- 跳過的 key 不寫入（不要寫成空字串）

## Commit 規格

每語系一個 commit，訊息英文（與既有 i18n 相關 commit 對齊，例如 `chore(i18n): refine Japanese wording for pity & rate-limit`）：

- `chore(i18n): complete Japanese share-image strings`
- `chore(i18n): complete Simplified Chinese share-image strings`
- `chore(i18n): fill Spanish translations from Traditional Chinese template`
- `chore(i18n): fill Thai translations from Traditional Chinese template`
- `chore(i18n): fill French translations from Traditional Chinese template`
- `chore(i18n): fill Portuguese translations from Traditional Chinese template`
- `chore(i18n): fill Vietnamese translations from Traditional Chinese template`

含 Claude Code 共著者標記。

## 不做（YAGNI）

- 不改既有譯文（即使品質有瑕疵）
- 不動 `en` 與 `zh`、`zh_Hans` 的 localeTranslator
- 不重排 key 順序、不重寫整檔
- 不在 locale 檔補 `@key` metadata（template 已有，locale 檔的不影響 gen-l10n）
- 不為跳過的 key 寫 fallback 英文/原文
- 不為這次翻譯新增測試（既有測試已涵蓋 arb 一致性）

## 報告（任務結束時提供使用者）

- 各語系實際補完數量
- Skip List：跳過的 key、語系、原因
- glossary 路徑（本地，未進版控）
- 7 個 commit 的 SHA 列表
