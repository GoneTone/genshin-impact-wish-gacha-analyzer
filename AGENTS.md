# 規則

- 回答使用**繁體中文 (台灣)**。
- **嚴禁重複造輪子**：動手撰寫任何工具方法前，務必先確認專案內有沒有現成可用的方法，有則直接使用，不要自己再寫一個類似的，如果在其他業務邏輯內有可以使用的程式碼，抽出來共用。
- **專案要好維護**：讓其他協助開發者可以清楚了解程式碼在做什麼，架構清楚，如有需要可以引入套件撰寫更加簡潔好維護的程式碼，不要自行造輪子。
- **風格體驗要一致**：應用程式的 UI/UX 要一致，避免混亂，任何設計都要考慮到 RWD 和元件內容是否會超出邊界等等的情況。
- **Dialog 高度上限**：`AlertDialog` 內容可能很長時，content 外面包一層 `ConstrainedBox(maxHeight: MediaQuery.of(context).size.height * 0.6)` 並讓內部自行滾動，避免吃滿整個視窗。
- **新功能要埋 log**：實作新功能或修改既有業務邏輯時，在關鍵節點（I/O、錯誤分支、外部 API、Rust bridge 互動等）加上適當等級的 `Logger('xxx').info/warning/severe(...)` 呼叫，內容要帶足夠 context（uid、banner、retcode、脫敏 URL 等）讓使用者匯出 log 後能直接定位問題，而不是「失敗了」這種沒有上下文的訊息。Logger 命名對齊既有樹（例如 `wish.*`、`app.*`、`rust.*`）。敏感資料一律經 `sanitizeUrl` / `sanitizeUid` 後再寫入。

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
