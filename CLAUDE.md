# 規則

- 回答使用**繁體中文 (台灣)**。
- **嚴禁重複造輪子**：動手撰寫任何工具方法前，務必先確認專案內有沒有現成可用的方法，有則直接使用，不要自己再寫一個類似的，如果在其他業務邏輯內有可以使用的程式碼，抽出來共用。
- **專案要好維護**：讓其他協助開發者可以清楚了解程式碼在做什麼，架構清楚，如有需要可以引入套件撰寫更加簡潔好維護的程式碼，不要自行造輪子。
- **風格體驗要一致**：應用程式的 UI/UX 要一致，避免混亂，任何設計都要考慮到 RWD 和元件內容是否會超出邊界等等的情況。
- **行動裝置與電腦都要顧到**：任何 UI/UX 改動都要同時檢查行動裝置（直向、橫向）與電腦版，不能因為調整其中一邊而讓另一邊跑版、溢出或行為改變。只改單一平台時，用 `isCompactLayout` 等既有判斷把分支隔開；完成前兩邊都要看過（實機／模擬器與 Windows 視窗），並有對應的版面測試鎖住。
- **共用邏輯改動兩個平台都要顧到**：`lib/state`、`lib/services` 裡沒有平台分支的程式碼（例如 `GachaUrlWatch`、`GachaRepository`、設定儲存、雲端同步、ARB 字串）是 Android 與電腦版共用的，修改時要確認另一個平台的流程不會因此改變。只想改單一平台時，用 `isAndroidProvider` 等既有判斷把分支隔開，並用另一個平台的測試鎖住原本的行為。完成前另一個平台也要驗證：至少跑相關測試，牽涉讀 log、抓資料等真實流程時要實際跑一次；改到 manifest、Kotlin 或 R8 相關的東西時，要用 release 版實跑。
- **Dialog 一律用 `AppDialog`**：新建 dialog 一律使用 `AppDialog`（`lib/widgets/dialogs/app_dialog.dart`），透過 `size: AppDialogSize.sm/md/lg/xl`（480 / 640 / 720 / 960）指定最大寬度。內部自動套寬高上限（width = `min(size.maxWidth, mq.width - 80)`，height = `min(720, mq.height - 120)`），低視窗下也不會被卡死。整體需要捲動時加 `scrollable: true`；內容已自帶捲動元件（`ListView` 等）維持預設 `false`。標題列右上角預設有 ✕（`showCloseButton: true`，點了等同取消、回傳 `null`，呼叫端要把 `null` 當取消處理）；**進行中、不能中途關閉的視窗（下載、同步、匯入、產生圖片等）要設 `showCloseButton: false`**，並搭配 `PopScope(canPop: false)`。**不要再自己手寫 `AlertDialog` + `ConstrainedBox` + `math.min(...)`**。
- **新功能要埋 log**：實作新功能或修改既有業務邏輯時，在關鍵節點（I/O、錯誤分支、外部 API、Rust bridge 互動等）加上適當等級的 `Logger('xxx').info/warning/severe(...)` 呼叫，內容要帶足夠 context（uid、banner、retcode、脫敏 URL 等）讓使用者匯出 log 後能直接定位問題，而不是 `"failed"` 這種沒有上下文的訊息。**log 訊息內容一律用英文**（與既有 log 慣例一致、方便搜尋、不受 locale 影響）：涵蓋 Dart `Logger`、Rust `tracing` 等所有會寫進 log 或 stderr 的訊息字串（`key=value` 診斷欄位同理）；**唯獨程式碼註解／dartdoc 不受此條影響，仍依「標點依語言慣例」用中文全形**。Logger 命名對齊既有樹（例如 `wish.*`、`app.*`、`rust.*`）。敏感資料一律經 `sanitizeUrl` / `sanitizeUid` 後再寫入。`LogService` 寫入前會對整行（訊息、例外物件、stack trace）統一套 `sanitizeLogMessage`，遮掉網址 authkey、家目錄使用者名稱與卡池記錄檔名裡的 uid，所以例外物件照常傳給 `Logger`（`warning('...', e, st)`）即可；訊息裡自己組的 uid 仍要經 `sanitizeUid`。
- **註解節制使用**：預設不寫實作層 `//` 註解；寫了就要對讀者有資訊增益。可寫的情境：(1) **WHY 不顯而易見**——隱藏限制、微妙 invariant、特殊 bug 的 workaround、會讓讀者意外的行為；(2) **結構/段落導引**——在較長的函式內標出段落意圖，讓讀者一眼看懂這段在做什麼。判準：拿掉註解後讀者是否需要多花時間理解？需要 → 留；不需要 → 刪。反例：純粹重述下一行名稱（壞例 `// 取得 user id` 對應 `String getUserId()`）、檔頭路徑 banner（如 `// lib/foo/bar.dart`）、被註解掉的舊程式碼（直接刪）。
- **標點依語言慣例**：CJK 語境（繁體中文 (台灣)、日文等）一律用全形標點 `，。！？；：（）「」『』、──`，涵蓋註解、dartdoc、UI 文字（ARB）、PR 描述、設計文件。英文／純程式碼語境維持半形 `. , ( ) ! ? : ;`。中英混排以**主語言**為準（中文句子內含英文短語，標點仍用全形）。
- **Commit message 與 PR 標題一律英文**：commit message（subject 與 body）與 PR 標題使用英文、半形標點，沿用 conventional commits 格式（`feat(...)`、`fix(...)`、`docs(...)` 等）。PR 描述、設計文件、程式碼註解／dartdoc、UI 文字（ARB）等不受此條影響，仍依上一條「標點依語言慣例」維持繁體中文全形。
- **方法應該有 dartdoc**：所有宣告（top-level function、class、constructor、method、field、typedef、enum；含 private `_xxx`）寫一行 `///` dartdoc 說明其作用，讓讀者不必讀實作就知道在做什麼。Flutter override（`build()`、`createState()`、`dispose()`、`initState()`、`didChangeDependencies()` 等簽名已自明的）不寫。
- **`rust_builder/` 勿手動改**：`rust_builder/` 是 flutter_rust_bridge 自動產生的 FFI plugin glue（含 `cargokit/`），只負責把 `rust/` 編進 Flutter 原生建置流程，本身沒有業務邏輯。要改 Rust 邏輯改 `rust/`（crate `genshin_capture_core`）；要改 Dart 綁定改 `flutter_rust_bridge.yaml` 後重跑 frb codegen。Rust 編譯由 cargokit 自動掛在 `flutter build` 的 CMake 流程上，**不需另外手動 `cargo build`**，但建置機需安裝 Rust toolchain（cargo）。
- **簡單改動免 spec**：純樣式微調（顏色、間距、icon 換掉、字串小改）、單檔 typo、單一 bug fix、純機械重構（重新命名、抽常數）、翻譯補字串等，可直接動手實作不必走 brainstorming → spec → plan 流程；若使用者下指令時已自帶設計判斷（明確的 what + why）也同樣免 spec。需要 spec 的判準：跨多檔影響架構、新增 widget／service／資料流、需要驗收條件超過「跑 analyze + test 全綠」的功能。把 spec 留給真正會影響後人維護的決策。
- **優先用 `fvm flutter` / `fvm dart`**：本專案以 FVM 釘住 Flutter 版本（見 `.fvmrc`），所有 Flutter／Dart 指令（`fvm flutter analyze`／`fvm flutter test`／`fvm flutter gen-l10n`／`fvm dart format` 等）一律優先透過 `fvm` 執行，確保用的是專案釘住的 SDK 版本；若環境找不到 `fvm`，再退回直接使用 `flutter`／`dart`。

## 提交前品質檢查

執行 `git commit` 前，依序執行以下指令並確認全部通過（指令一律優先透過 `fvm` 執行，找不到 `fvm` 才退回直接用 `flutter`／`dart`）：

1. **格式化**：`fvm dart format lib/ test/`（不要對 `.` 跑，會動到 `rust_builder/` 內 vendored 程式碼）
2. **靜態分析**：`fvm flutter analyze` — 必須輸出 `No issues found!`
3. **測試**：`fvm flutter test` — 必須輸出 `All tests passed!`

任何一項失敗就先修，不要用 `--no-verify` 跳過 hooks。

不要主動 git push。

## YAGNI 原則（You Ain't Gonna Need It）

只實作當前需要的功能，不要預先設計「未來可能用到」的東西。

| ❌ 不要          | ✅ 應該    |
|---------------|---------|
| 預先建立抽象層或介面    | 需要時再抽象  |
| 加入「以後可能用到」的參數 | 只加必要參數  |
| 過度設計可擴展架構     | 簡單直接的實作 |
| 預留未使用的設定選項    | 有需求再加   |
