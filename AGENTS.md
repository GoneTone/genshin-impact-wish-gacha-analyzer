# 規則

- 回答使用**繁體中文 (台灣)**。
- **嚴禁重複造輪子**：動手撰寫任何工具方法前，務必先確認專案內有沒有現成可用的方法，有則直接使用，不要自己再寫一個類似的，如果在其他業務邏輯內有可以使用的程式碼，抽出來共用。
- **專案要好維護**：讓其他協助開發者可以清楚了解程式碼在做什麼，架構清楚，如有需要可以引入套件撰寫更加簡潔好維護的程式碼，不要自行造輪子。
- **風格體驗要一致**：應用程式的 UI/UX 要一致，避免混亂，任何設計都要考慮到 RWD 和元件內容是否會超出邊界等等的情況。
- **Dialog 一律用 `AppDialog`**：新建 dialog 一律使用 `AppDialog`（`lib/widgets/dialogs/app_dialog.dart`），透過 `size: AppDialogSize.sm/md/lg`（480 / 640 / 720）指定最大寬度。內部自動套寬高上限（width = `min(size.maxWidth, mq.width - 80)`，height = `min(720, mq.height - 120)`），低視窗下也不會被卡死。整體需要捲動時加 `scrollable: true`；內容已自帶捲動元件（`ListView` 等）維持預設 `false`。**不要再自己手寫 `AlertDialog` + `ConstrainedBox` + `math.min(...)`**。
- **新功能要埋 log**：實作新功能或修改既有業務邏輯時，在關鍵節點（I/O、錯誤分支、外部 API、Rust bridge 互動等）加上適當等級的 `Logger('xxx').info/warning/severe(...)` 呼叫，內容要帶足夠 context（uid、banner、retcode、脫敏 URL 等）讓使用者匯出 log 後能直接定位問題，而不是「失敗了」這種沒有上下文的訊息。Logger 命名對齊既有樹（例如 `wish.*`、`app.*`、`rust.*`）。敏感資料一律經 `sanitizeUrl` / `sanitizeUid` 後再寫入。
- **註解節制使用**：預設不寫實作層 `//` 註解；寫了就要對讀者有資訊增益。可寫的情境：(1) **WHY 不顯而易見**——隱藏限制、微妙 invariant、特殊 bug 的 workaround、會讓讀者意外的行為；(2) **結構/段落導引**——在較長的函式內標出段落意圖，讓讀者一眼看懂這段在做什麼。判準：拿掉註解後讀者是否需要多花時間理解？需要 → 留；不需要 → 刪。反例：純粹重述下一行名稱（壞例 `// 取得 user id` 對應 `String getUserId()`）、檔頭路徑 banner（如 `// lib/foo/bar.dart`）、被註解掉的舊程式碼（直接刪）。
- **方法應該有 dartdoc**：所有宣告（top-level function、class、constructor、method、field、typedef、enum；含 private `_xxx`）寫一行 `///` dartdoc 說明其作用，讓讀者不必讀實作就知道在做什麼。Flutter override（`build()`、`createState()`、`dispose()`、`initState()`、`didChangeDependencies()` 等簽名已自明的）不寫。

## 提交前品質檢查

執行 `git commit` 前，依序執行以下指令並確認全部通過：

1. **格式化**：`dart format lib/ test/`（不要對 `.` 跑，會動到 `rust_builder/` 內 vendored 程式碼）
2. **靜態分析**：`flutter analyze` — 必須輸出 `No issues found!`
3. **測試**：`flutter test` — 必須輸出 `All tests passed!`

任何一項失敗就先修，不要用 `--no-verify` 跳過 hooks。

## YAGNI 原則（You Ain't Gonna Need It）

只實作當前需要的功能，不要預先設計「未來可能用到」的東西。

| ❌ 不要          | ✅ 應該    |
|---------------|---------|
| 預先建立抽象層或介面    | 需要時再抽象  |
| 加入「以後可能用到」的參數 | 只加必要參數  |
| 過度設計可擴展架構     | 簡單直接的實作 |
| 預留未使用的設定選項    | 有需求再加   |
