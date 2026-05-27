# 既有註解清理 + 規則改寫

日期：2026-05-20
分支：`flutter-rewrite`

## 動機

`CLAUDE.md` / `AGENTS.md` 在 2026-05-20 commit `4bb0d3d` 加入了「不要隨意加註解 — 預設不寫註解，只在 WHY 不顯而易見時加」的條目。但既有程式碼（commit `128f035` Flutter rewrite init 起累積）裡有大量規則制定前的註解：

- 約 698 處 `//` + 419 處 `///`（lib/，含 generated）
- 約 264 處 `//`（test/）
- 40 個檔案開頭有 `// lib/foo/bar.dart` 形式的路徑 banner

實作層註解品質參差：有些是真正的段落導引/invariant（要留），有些是純粹重述名稱、檔頭路徑 banner、測試樣板 `// arrange/act/assert`（要刪）。同時，使用者明確要求 dartdoc 例外：「方法應該有 dartdoc，讓閱讀者立刻知道方法在做什麼」— 這在現行規則中沒寫，需要補進規則本身。

這支 spec 的工作分三部分：(1) 改寫規則；(2) 依新規則清理既有註解；(3) 啟用 `public_member_api_docs` lint 鎖住「以後新增 public 宣告漏 dartdoc」這道入口（private 仍靠人工保證）。

## 規則改寫（CLAUDE.md / AGENTS.md）

兩檔同步替換現行「不要隨意加註解」單條為兩條並列的條目：

> **註解節制使用**：預設不寫實作層註解；寫了就要對讀者有資訊增益。可寫的情境：
> - **WHY 不顯而易見**：隱藏限制、微妙 invariant、特殊 bug 的 workaround、會讓讀者意外的行為。
> - **結構/段落導引**：複雜函式內標出段落意圖，讓讀者一眼看懂在做什麼（例：`// 計算每個 visible entry 是否為月份分組首 row`）。短到名稱已自明的小函式不需要。
>
> 反例（不要寫）：
> - 重述名稱毫無新增資訊（壞例：`// 取得 user id` 對應 `String getUserId()`）
> - **檔頭路徑 banner**（如 `// lib/foo/bar.dart`）
> - 被註解掉的舊程式碼（直接刪）
>
> 判準：拿掉這條註解，讀者是否需要多花時間理解？需要 → 留；不需要 → 刪。
>
> **方法應該有 dartdoc**：所有宣告（top-level function、class、constructor、method、field、typedef、enum；含 private `_xxx`）寫一行 `///` dartdoc 說明其作用，讓讀者不必讀實作就知道在做什麼。Flutter override（`build()`、`createState()`、`dispose()`、`initState()`、`didChangeDependencies()` 等簽名已自明的）不寫。

兩條同時存在不衝突 — 第一條規範實作層 `//` 註解，第二條規範宣告層 `///` dartdoc。

放置位置維持原條目位置（CLAUDE.md / AGENTS.md 第 9 行附近），保留條目間順序與其他規則不動。

## 清理範圍

**處理**
- `lib/` 手寫 Dart 檔
- `test/` 全部

**排除**
- `lib/generated/`（assets codegen）
- `lib/src/rust/`（flutter_rust_bridge codegen）
- `lib/l10n/generated/`（intl codegen）
- 其他 codegen 產出（下次 regen 會覆寫）

**不在範圍內**（避免 scope creep）
- 不重構任何邏輯
- 不改檔名 / 搬位置
- 不調 import 順序
- 不開除 `public_member_api_docs` 以外的新 lint 規則（不開 `package_api_docs`、`comment_references` 等；之後另案再評估）
- 不修 `pubspec.yaml`

## 判斷準則

### 保留（不動或最小修飾）

通用判準：拿掉這條註解後，讀者是否需要多花時間理解程式碼？需要 → 留。

1. **既有 dartdoc 已說明 WHAT 的**：哪怕一行 — 留著。
2. **真正的 WHY 註解**：invariant、race condition、跨檔對齊、workaround、會讓讀者意外的行為。
   參考範例（這些必須留）：
   - `lib/services/log_service.dart:49-52` — broadcast listener 不能拋例外
   - `lib/services/log_service.dart:87-88` — 時間戳用 UTC 對齊分檔基準
   - `lib/services/log_service.dart:111-114` — 用 `r.time.toUtc()` 取年月日避免 rollover race
   - `lib/services/log_service.dart:133-136` — sink 取走立即新開避免 `StreamSink is bound to a stream`
   - `lib/widgets/rarity_pie.dart:10-11` — `_kRingRadius=75 + _kCenterRadius=40 = 230px` 對齊 ChartCard 244px slot
   - `lib/widgets/share/share_card.dart:148-149` — `firstWhere` 為何不需 `orElse`（gacha_types.dart 靜態保證）
3. **dartdoc 的前置條件 / 後置條件 / API 契約**：例 `lib/widgets/cards/timeline_vertical.dart:50-52` 的 `fillHeight: true` 前置條件。
4. **結構/段落導引型行內 `//`**：在較長函式內標出段落意圖，讓讀者一眼看懂這段在做什麼。
   參考範例（這些留）：
   - `lib/widgets/cards/timeline_vertical.dart:205` — `// 計算每個 visible entry 是否為月份分組首 row`
   - `lib/widgets/cards/timeline_vertical.dart:223 / 233 / 324` — `// 背景軸線` / `// 前景:Column of rows` / `// 月份左欄(固定寬度…)`
   - `lib/widgets/share/share_card.dart:390 / 411 / 416 / 454` — `// 頂部：三張 App StatCard 橫排…` / `// 下方：左欄雙圓餅 + 右欄時間軸…` / `// index 0 = 左欄…` / `// index 1 = 右欄…`
   - `lib/widgets/cards/timeline_vertical.dart:88 / 93` — `// length + firstTime 同時不同 → 視為不同資料集，reset` / `// 同資料集（或局部變動）→ 只做 clamp`
   判準：拿掉後讀者需要逐行讀程式碼才能定位段落意圖 → 留。
5. **連續多行的視覺隱喻說明**：例 `lib/widgets/cards/timeline_vertical.dart:14-17` 的「上→下 = 新→舊」 — 留，這是讀者理解該檔的鑰匙。

### 移除

通用判準：拿掉這條註解後，讀者是否需要多花時間理解程式碼？不需要 → 刪。

1. **檔頭路徑 banner**（40 檔，例 `// lib/widgets/rarity_pie.dart`）。
   - 若 banner 內混了有價值的 WHY/HOW（例 `lib/services/share_image_renderer.dart:1-5` 解釋為何用獨立 RenderView），把那段挪到對應 class/方法 dartdoc，再移除整段 banner。
2. **純粹重述名稱的行內 `//`**：對下一行內容毫無新增資訊。
   - 壞例：`// 設定 controller` 對應 `_controller = ...`
   - 壞例：`// 回傳 uid` 對應 `return uid;`
   - 反例（這些留，見「保留 #4」）：標出段落意圖、決策分支、視覺結構的 `//`
3. **重述名稱意義的 dartdoc**：對欄位/getter/簡單方法重述名稱、無新增資訊。
   - 壞例：對 `final String uid;` 寫 `/// uid。`
   - 壞例：對 `bool get isEmpty => …` 寫 `/// 是否為空`
4. **語意空泛的測試樣板註解**：`// arrange` / `// act` / `// assert`、`// given...` / `// when...` / `// then...`、`// === xxx ===` 等純樣板無針對性內容的。測試裡若有「為何這樣排測試」的 WHY 註解則屬「保留 #2」。
5. **被註解掉的舊程式碼**：直接刪。

### 補齊

1. **所有宣告缺 dartdoc 的**：補一行 WHAT，使讀者不必讀實作。
   - 涵蓋：top-level function、class、constructor、method、field、typedef、enum
   - 涵蓋 private `_xxx`
   - 例外：Flutter override（`build`、`createState`、`dispose`、`initState`、`didChangeDependencies`、`reassemble`、`debugFillProperties`、`==`、`hashCode`、`toString` 等 framework / Object 標準 override，簽名已自明）
2. **補齊內容原則**：
   - 一行為主（少數確實需要兩行的允許，例如有非顯然的參數含意）
   - 描述「做什麼」而非「怎麼做」
   - 不重述名稱（壞例：`/// 取得 user id` 對應 `String getUserId()`）
   - 與既有 dartdoc 風格一致：繁體中文（台灣）、無句末標點不強制

### Borderline 處理規則

- 一段註解半 WHAT 半 WHY → 兩段都過判準。若 WHAT 部分屬「結構/段落導引」一樣留；只刪純粹重述名稱、毫無資訊的句子。
- 一行行內 `//` 既不是純重述名稱、也說不上明顯的段落導引 → **保留**（保守原則；判準偏向「拿掉後是否更難讀」這側）。
- 不確定是否為 invariant → **保留**。
- dartdoc 描述了 invariant + 簡述 WHAT → 整段留。
- 若刪一段 `//` 會讓周圍程式碼看起來突兀（例：移除「// 頂部：…」後緊接的 `Column(children: [...])` 失去結構提示）→ 留。

## 執行流程

### Commit 0：規則更新

先做這個。後續所有清理都依新規則。

- 改 `CLAUDE.md`：替換現行「不要隨意加註解」單條為兩條
- 改 `AGENTS.md`：同步
- `dart format` 不適用（純 markdown）；`flutter analyze` / `flutter test` 跑一輪確保沒副作用
- commit message: `docs(rules): split comment rule; require dartdoc on declarations`

### Commit 1~7：分批清理

每批一個 commit。順序：

1. **資料/狀態層**（先做，影響面最小）
   - `lib/data/` + `lib/models/` + `lib/utils/` + `lib/theme/` + `lib/routing/` + `lib/state/`
   - `lib/app_info.dart` + `lib/main.dart`
   - commit: `chore(comments): clean lib data/state/theme per new comment rule`

2. **業務服務層**（註解密集、有真 invariant，最謹慎）
   - `lib/services/`（含 `log_service.dart`、`gacha_*`、`share_image_*` 等）
   - commit: `chore(comments): clean lib/services per new comment rule`

3. **基礎 widgets**（非 share、非 cards、非 dialogs）
   - `lib/widgets/` 根目錄與 `lib/widgets/data/`
   - commit: `chore(comments): clean lib/widgets base per new comment rule`

4. **卡片與對話框**
   - `lib/widgets/cards/` + `lib/widgets/dialogs/`
   - commit: `chore(comments): clean lib/widgets cards/dialogs per new comment rule`

5. **分享圖渲染樹**（註解最密集、彼此對齊靠 invariant）
   - `lib/widgets/share/` + `lib/services/share_image_*.dart`（若 2 未處理乾淨補上）+ `lib/services/overview_sections.dart`
   - commit: `chore(comments): clean lib share render tree per new comment rule`
   - 注意：此批若清掉跨檔對齊的 invariant 註解會破壞分享圖視覺，逐檔讀完整內容後再下判斷。

6. **頂層頁面**
   - `lib/pages/`
   - commit: `chore(comments): clean lib/pages per new comment rule`

7. **測試碼**
   - `test/` 全部
   - commit: `chore(comments): clean test per new comment rule`

### Commit 8：啟用 `public_member_api_docs` lint

清理全部完成、`flutter analyze` 已綠後才做（這之前開 lint 會大紅、commit 卡死）。

1. 改 `analysis_options.yaml`：在 root 加上 `linter.rules: [public_member_api_docs]`。
2. 新增 `test/analysis_options.yaml`：
   ```yaml
   include: ../analysis_options.yaml
   linter:
     rules:
       public_member_api_docs: false
   ```
   理由：test 檔常見 top-level helper / Mock / Fake / fixture 是 public，但名稱本身已足夠描述性（`_buildTestApp`、`FakeStorage` 等），enforce dartdoc 是雜訊大於資訊。Dart analyzer 支援巢狀 `analysis_options.yaml`，`test/` 目錄會自動採用此覆寫。
3. 跑 `flutter analyze` 必須 `No issues found!`。若有 public 漏 dartdoc 觸發 lint，回頭補（這代表 Commit 1~7 漏了 public 宣告）。
4. 跑 `flutter test` 一輪。
5. commit: `chore(lint): enable public_member_api_docs for lib/`

### 每批驗證流程

1. 逐檔讀完整內容 → 套判斷準則 → Edit
2. `dart format lib/ test/`
3. `flutter analyze` → 必須 `No issues found!`
4. `flutter test` → 必須 `All tests passed!`
5. 通過才 commit；失敗就修，**不用** `--no-verify`

### 意外處理

- **清掉某註解後 test 失敗** → 可能該註解標示了測試依賴的行為（例：跨檔 size 對齊）。**revert 該檔 + 把該註解升格成 dartdoc**，繼續其他檔。
- **`flutter analyze` 報新 lint**（Commit 1~7 期間）→ 不該發生（lint 在 Commit 8 才開）。若發生，回頭看 Edit 是否誤刪 `// ignore:`。
- **Commit 8 啟用 lint 後 analyze 紅** → 表示 Commit 1~7 期間漏了 public 宣告的 dartdoc。逐條按 lint 訊息補；補完成額外 fixup commit（`chore(comments): fixup missed public dartdocs`），不要把 Commit 8 跟補 fixup 合在一起。
- **flaky test**：依 memory `project_flaky_parallel_test_suite.md`，`log_service` / `app_release_checker` 平行偶 flake。test 失敗時先單檔重跑確認非 flaky 再判斷。
- **規則前 / 規則後混淆**：必先做 Commit 0；後續 Commit 1~7 一律以新規則為準。

## 預期產出

- 9 個 commit（規則 1 + 清理 7 + lint 啟用 1，若漏補可能多 fixup commit）
- `lib/` 檔頭路徑 banner 全清（40 檔）
- `lib/` + `test/` 純重述名稱的行內 `//` 移除；結構導引型 `//` 保留
- 所有宣告補上 dartdoc（含 private，除 Flutter override）
- 真正的 WHY 註解 100% 保留
- `analysis_options.yaml` 啟用 `public_member_api_docs`；`test/analysis_options.yaml` 覆寫關閉
- `flutter analyze` / `flutter test` 全綠

## 非目標

- 不導入 `public_member_api_docs` 以外的 lint
- 不重構 / 不搬檔 / 不改 logic
- 不處理 codegen 產物
- 不寫新工具腳本
