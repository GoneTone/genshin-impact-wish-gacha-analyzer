# CI Workflow:format + analyze + test 設計

**日期**:2026-05-21
**狀態**:已通過 brainstorming,待 writing-plans

## 目標

新增一個 GitHub Actions workflow,在 PR 與 master push 時自動跑專案品質三關(`dart format` / `flutter analyze` / `flutter test`),取代目前完全沒有 CI 把關的狀態。

## 背景與限制

- 專案已從 Vue3+Electron 全面重寫為 Flutter + Rust(crate `genshin_capture_core`),目前僅 Windows 桌面。
- 既有唯一 workflow 是 `release-windows.yml`(release created 時建置 Windows 安裝檔),沒有任何驗證 PR / push 的 CI。
- 品質三關定義於 `CLAUDE.md`:`dart format lib/ test/` → `flutter analyze`(需 `No issues found!`)→ `flutter test`(需 `All tests passed!`)。
- 已確認 **測試不需 Rust**:`test/` 下無任何檔案 import `src/rust`,且無 `integration_test/`,70 個測試檔皆為純 Dart / widget 測試,不載入 native lib。`flutter analyze` 分析的 `lib/src/rust/` 是已 commit 的綁定 Dart 檔,亦不需 Rust。
- ~~已知 flaky:`log_service` / `app_release_checker` 在**平行**測試會偶發失敗~~ → 已從根因修復(見下節「flaky 根因修復」)。
- Flutter 版本鎖於 `.fvmrc`(目前 3.41.9),release workflow 已用 `subosito/flutter-action@v2` 讀此檔。

## 決策(經使用者確認)

| 項目 | 決定 |
|------|------|
| Runner | `ubuntu-latest`(analyze/test 純 Dart 不需 Rust,Linux runner 最省最快) |
| 觸發 | `push` 到 master + `pull_request` 到 master |
| job 結構 | 方案 A:單一 job,步驟串行(pub get → format → analyze → test) |
| flaky 對策 | 從根因修復(見下節),`flutter test` 預設平行即安全,不需 `--concurrency=1` |
| 範圍 | 完整品質三關:format + analyze + test |
| workflow 名稱 | `ci` |
| 並行控制 | `concurrency` 以 `github.ref` 分組,`cancel-in-progress: true`(master 也套用) |

## 設計

新增檔案 `.github/workflows/ci.yml`:

```yaml
name: ci

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version-file: .fvmrc
          channel: stable
          cache: true

      - run: flutter pub get

      - name: Check formatting
        run: dart format --output=none --set-exit-if-changed lib/ test/

      - name: Analyze
        run: flutter analyze

      - name: Test
        run: flutter test
```

### 設計要點

- **不裝 Rust toolchain**:測試與分析皆不需 native lib(見背景),省掉 `dtolnay/rust-toolchain` + cargokit 編譯的大量時間。
- **format 範圍 `lib/ test/`**:對齊 CLAUDE.md,不碰 `rust_builder/` 內 vendored 程式碼;`--set-exit-if-changed` 使格式不一致回非零退出。
- **`flutter test` 預設平行**:不加 `--concurrency=1`。flaky 根因已修(見下節),預設並行即安全。
- **沿用 release workflow 慣例**:同 `subosito/flutter-action@v2` + `flutter-version-file: .fvmrc` + `cache: true`,Flutter 版本與 release 鎖一致。
- **最小權限**:`contents: read`。
- **訊息英文**:對齊既有 CI 訊息慣例(本 workflow 僅標準 step,自訂訊息極少)。

### 錯誤行為

任一步驟非零退出即整個 job 失敗。format 不一致 → `set-exit-if-changed` 回非零;analyze 有 issue → 非零;test 失敗 → 非零。串行步驟讓紅燈明確對應到是哪一關。

## flaky 根因修復(本次一併完成)

經 systematic-debugging 調查,唯一可證實的平行 flaky 根因是 `test/services/app_release_checker_test.dart` 的 `'TimeoutException 觸發 → ReleaseCheckTimeout'` 測試:

- 它讓 `MockClient` 真實 `await Future.delayed(Duration(seconds: 15))`,藉此觸發 production `app_release_checker.dart` 的 `.timeout(Duration(seconds: 10))`。實跑 ~10 真實秒(已計時),test-level 上限僅 `Timeout(Duration(seconds: 20))`,只有 10s 餘裕。
- CI 共享 runner CPU 變動大,真實 timer 漂移即可能撞 20s test deadline → 假紅燈。這是「測試依賴真實掛鐘時間」反模式,且為全測試集唯一這樣寫的測試(其餘 `Future.delayed` 皆為 50ms 等級的 settle 用途)。
- `log_service` 無可重現 flaky(隔離 5/5、全套 concurrency=16 壓測 6/6,皆綠且瞬間),不修改。

**修法**:該測試改用 `package:fake_async` 的虛擬時間驅動(`async.elapse(Duration(seconds: 11))` 讓 10s timeout 在虛擬時間觸發),確定性、瞬間完成、免於 CPU 競爭。新增 `fake_async: ^1.3.3` 為直接 dev_dependency。

**異動檔案**:`pubspec.yaml`、`pubspec.lock`、`test/services/app_release_checker_test.dart`。

**驗證**:`dart format` 0 changed;`flutter analyze` No issues found!;單檔 16s→6s、timeout 測試 `00:10`→`00:00`;全套預設並行 ×3 全綠(534 測試)。

## 範圍外(YAGNI)

- 不修改 `log_service`(無可重現 flaky)。
- 不加 Windows / matrix runner(目前測試無平台相依)。
- 不加 build / 產物上傳(release workflow 已負責建置)。
- 不加 coverage 上傳、不接第三方報告服務。

## 驗證方式

- workflow 推上後,觀察一次 PR 觸發的 run 三步驟皆綠。
- 本機已驗證:`flutter analyze` → No issues found!;`flutter test` → All tests passed!(534 測試)。
