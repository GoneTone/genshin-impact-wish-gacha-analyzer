# `wish` → `gacha` 中立化重構設計

日期：2026-05-18
分支：`flutter-rewrite`

## 背景與目標

本專案後續會複製修改成適用於其他遊戲，`wish`（祈願）是原神專有名詞。本次將程式碼內 `wish` 相關命名中立化為 `gacha`，讓未來 clone 成其他遊戲時不會有原神相關名稱殘留。

盤點結論：專案內真正屬於「我們可控且該中立化」的命名只有 `wish`。其餘原神色彩字串分屬三類，**不在本次範圍**：

- 外部 API 契約字面（改了會壞）：`authkey` / `authkey_ver` / `sign_type` / `game_biz`、`hoyoverse.com` / `hoyolab.com` / `mihoyo`、`getGachaLog` / `getBeyondGachaLog`、gacha_type 代碼 `100/200/301/302/400/500`。
- 已中立的通用抽卡術語：`pity`、`banner`、`gachaType*`。
- 使用者選擇保留：Dart package 名 `genshin_impact_wish_gacha_analyzer`。

## 決策紀錄

| 決策點 | 結論 |
|---|---|
| 既有使用者持久化資料（`wish_data` 夾、Rust CA 夾） | **只改新安裝，不遷移**。升級後舊資料讀不到，等同重新抓取 / 重新信任憑證 |
| i18n | **改 key 名**（含對應 `.dart` 引用 + 重產 generated）；**顯示文字值維持原神用語**（「祈願 / Wish」），clone 時各自改 arb 值 |
| 註解 | 英文 `wish`→`gacha`；繁中「祈願」→「卡池」，指「抽取動作」的句子改用語境正確中立詞求通順 |
| package 名 | 保留 `genshin_impact_wish_gacha_analyzer`（import 路徑不受影響） |
| `pity` / `banner` / `gachaType*` | 維持（通用抽卡術語，本身已中立） |

## 範圍

### 識別子（8 個 class + 全小寫）

`WishRecord`→`GachaRecord`、`WishRepository`→`GachaRepository`、`WishStorage`→`GachaStorage`、`WishFetcher`→`GachaFetcher`、`WishCapture`→`GachaCapture`、`WishStats`→`GachaStats`、`WishState`→`GachaState`、`RustWishCapture`→`RustGachaCapture`；所有變數 / 方法 / 參數 / 欄位 token 內 `wish`→`gacha`、`Wish`→`Gacha`。

### 檔案 git mv（17 個，保留歷史）

- `lib/models/wish_record.dart` → `gacha_record.dart`
- `lib/services/wish_{fetcher,filter,pity,row,stats,storage}.dart` → `gacha_*`
- `lib/state/wish_{capture,repository}.dart` → `gacha_*`
- `test/` 下對應 8 個測試檔同步 git mv

### Logger 名稱（4）

`wish.capture`→`gacha.capture`、`wish.fetcher`→`gacha.fetcher`、`wish.repo`→`gacha.repo`、`wish.storage`→`gacha.storage`。

### 路徑字串（1）

`lib/main.dart:86` `'${supportDir.path}/wish_data'` → `/gacha_data`。**不做資料遷移。**

### i18n key（3 個 × 4 個 arb 檔）

| 舊 key | 新 key |
|---|---|
| `navSectionWish` | `navSectionGacha` |
| `emptyNoWishRecords` | `emptyNoGachaRecords` |
| `pageOverviewWishSection` | `pageOverviewGachaSection` |

- 改名範圍：`app_en.arb`、`app_ja.arb`、`app_zh.arb`、`app_zh_Hans.arb`（這 3 key 僅存在於這 4 檔；純 `key:value`，無 `@meta`）。其餘 `es/fr/pt/th/vi` 無此 3 key（走 template `app_zh.arb` fallback），不需動。
- arb 採 **key 定向編輯**，不對 arb 跑整檔字串取代（保護顯示文字值）。
- 重新產生：`flutter gen-l10n`（`l10n.yaml`：arb-dir `lib/l10n`，template `app_zh.arb`，output `lib/l10n/generated/`）。
- 更新 `.dart` 引用 3 處：`lib/pages/app_shell.dart:258`（`l.navSectionWish`）、`lib/pages/overview_page.dart:144`（`l.pageOverviewWishSection`）、`:150`（`l.emptyNoWishRecords`）。

### 註解

英文 `wish`→`gacha`（機械替換）；繁中「祈願」→「卡池」，少數指「抽取動作」的句子（如「執行一次祈願」）改用語境正確中立詞（如「抽卡」）求通順。

## 硬性排除（絕不更動）

- i18n 顯示文字值：`"Genshin Wish Analyzer"`、`gachaType* "...Wish"`、`progressOpenGameHint`、`errorNoRecords`、`confirmClear*Body`、繁中「祈願」值等（因只改 key token + arb key 定向編輯，值天然安全）。
- 外部 API 字面：`authkey` / `authkey_ver` / `sign_type` / `game_biz`、`hoyoverse.com` / `hoyolab.com` / `mihoyo`、gacha_type 代碼。
- package 名 `genshin_impact_wish_gacha_analyzer`、`pity` / `banner` / `gachaType*`。
- `lib/src/rust/`（frb 產生碼，已確認無 `wish`）、`lib/l10n/generated/`（改用 `flutter gen-l10n` 重產，不手改）、`rust/`（無 `wish` 識別子）。

## 執行策略（做法 C：邊界感知識別子取代 + git mv + 編譯/測試安全網）

1. `git mv` 17 個檔案。
2. `.dart`（排除 `lib/l10n/generated/`）：token 級 `wish`→`gacha`、`Wish`→`Gacha` 均勻替換（i18n key 已一併改名，無需保護清單），修正 import 路徑。
3. arb：對 `app_{en,ja,zh,zh_Hans}.arb` 的 3 個 key 行做定向 key 改名（不動值），執行 `flutter gen-l10n` 重產 generated。
4. 註解：依規則逐處處理（英文機械換、繁中看語境）。

理由：範圍是有限且可枚舉的集合；對 rename 而言編譯器 + 測試是最強驗證。純 IDE rename 無法處理 Logger 字串字面與路徑字串，純 sed 邊界判斷風險高，故採混合。

## 驗證（CLAUDE.md 提交前檢查）

1. `dart format lib/ test/`
2. `flutter analyze` → 必須輸出 `No issues found!`
3. `flutter test` → 必須輸出 `All tests passed!`
4. 全庫 `grep -rn '[Ww]ish' lib/ test/`，殘留必須只落在白名單：i18n 顯示文字值、被排除的外部 API 字面、package 名 — 人工核對無遺漏。

## Commit 切分

單一 commit（rename + 內容改動同 commit，git 自動辨識 rename）：

```
refactor(naming): rename wish→gacha for game-agnostic reuse
```
