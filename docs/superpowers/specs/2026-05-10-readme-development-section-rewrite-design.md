# README 開發區塊改寫 — 設計文件

- 日期：2026-05-10
- 分支：`flutter-rewrite`
- 影響檔案：`README.md`、`README_EN.md`、`README_ZH-CN.md`

---

## 1. 背景與動機

三份 README 的「開發 / Development / 开发」區塊仍停留在舊的 Electron + npm 流程：

```bash
npm install
npm run electron:serve
npm run electron:build:win / win32 / win64
```

但專案已經完成 Flutter 重寫（`flutter-rewrite` 分支）：

- 主程式：Flutter (Dart SDK `^3.11.5`)
- 原生擴充：Rust crate `genshin_capture_core` 透過 `flutter_rust_bridge` 2.12.0 橋接
- 平台目錄只有 `windows/`，Cargo.toml 內 `cfg(windows)` 依賴包含 `windows`、`hudsucker`（HTTPS 代理）、`rcgen`、`rustls`
- 既有 `npm` / `electron:*` 指令在 Flutter repo 完全跑不起來

任何想對 `flutter-rewrite` 分支貢獻或自行編譯的開發者，現在依 README 操作只會得到錯誤。

## 2. 目標

讓使用者讀完開發區塊就能：

1. 知道目前只支援 Windows
2. 裝齊必要工具
3. 取得原始碼、安裝依賴
4. 跑 dev、編譯 release、跑測試
5. 在修改 Rust API 後正確重新產生橋接程式碼

不在範圍內：

- macOS / Linux / Arm64 支援說明（未驗證、且 Cargo.toml 目前未確認 arm64 可編）
- Visual Studio workload 細節（交給 `flutter doctor` 提示）
- 專案結構、l10n 工作流程、代理 CA 安裝（屬「詳細版」內容，本次採中等版）

## 3. 採用方向

中等版詳細度：保留所有必要章節但每節極簡。三份 README 同步更新，章節結構相同、內容語言對應翻譯。

## 4. 章節結構（繁中為基準）

```
## 開發
  ### 前置需求
  ### 取得原始碼並安裝依賴
  ### 開發模式執行
  ### Rust ↔ Dart 橋接程式碼產生
  ### 編譯生產版
  ### 執行測試
```

## 5. 各章節最終內容（繁中）

### 前置需求

- 目前僅支援 Windows
- [Flutter SDK](https://flutter.dev/docs/get-started/install)（最新穩定版）
- [Rust toolchain](https://rustup.rs/)（stable）
- 執行 `flutter doctor`，依提示補齊缺少的工具

### 取得原始碼並安裝依賴

```bash
git clone https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer.git
cd genshin-impact-wish-gacha-analyzer
flutter pub get
cargo build --manifest-path rust/Cargo.toml
```

### 開發模式執行

```bash
flutter run -d windows
```

### Rust ↔ Dart 橋接程式碼產生

修改 `rust/src/api/` 內的 Rust 函式後，重新產生橋接程式碼。第一次使用前先安裝 codegen 工具：

```bash
cargo install flutter_rust_bridge_codegen
```

之後每次修改 API 都執行：

```bash
flutter_rust_bridge_codegen generate
```

產生的檔案位於 `lib/src/rust/`。

### 編譯生產版

```bash
flutter build windows --release
```

輸出：`build\windows\x64\runner\Release\`

### 執行測試

```bash
flutter test
cargo test --manifest-path rust/Cargo.toml
```

## 6. 多語言對應

三份 README 採用相同章節結構與相同指令，僅章節標題與描述文字翻譯。

| 繁中 (`README.md`) | 簡中 (`README_ZH-CN.md`) | 英文 (`README_EN.md`) |
| --- | --- | --- |
| 開發 | 开发 | Development |
| 前置需求 | 前置需求 | Prerequisites |
| 目前僅支援 Windows | 目前仅支持 Windows | Windows only for now |
| Flutter SDK（最新穩定版） | Flutter SDK（最新稳定版） | Flutter SDK (latest stable) |
| Rust toolchain（stable） | Rust toolchain（stable） | Rust toolchain (stable) |
| 執行 `flutter doctor`，依提示補齊缺少的工具 | 运行 `flutter doctor`，依提示补齐缺少的工具 | Run `flutter doctor` and install anything it flags as missing |
| 取得原始碼並安裝依賴 | 取得源代码并安装依赖 | Clone and install dependencies |
| 開發模式執行 | 开发模式运行 | Run in development mode |
| Rust ↔ Dart 橋接程式碼產生 | Rust ↔ Dart 桥接代码生成 | Rust ↔ Dart bridge code generation |
| 修改 `rust/src/api/` 內的 Rust 函式後，重新產生橋接程式碼。第一次使用前先安裝 codegen 工具： | 修改 `rust/src/api/` 内的 Rust 函数后，重新生成桥接代码。第一次使用前先安装 codegen 工具： | After changing Rust functions in `rust/src/api/`, regenerate the bridge code. Install the codegen tool on first use: |
| 之後每次修改 API 都執行： | 之后每次修改 API 都运行： | Then run this whenever the API changes: |
| 產生的檔案位於 `lib/src/rust/`。 | 生成的文件位于 `lib/src/rust/`。 | Generated files live in `lib/src/rust/`. |
| 編譯生產版 | 编译生产版 | Build for release |
| 輸出： | 输出： | Output: |
| 執行測試 | 运行测试 | Run tests |

所有指令與路徑（`git clone`、`flutter pub get`、`cargo build --manifest-path rust/Cargo.toml`、`flutter run -d windows`、`cargo install flutter_rust_bridge_codegen`、`flutter_rust_bridge_codegen generate`、`flutter build windows --release`、`build\windows\x64\runner\Release\`、`flutter test`、`cargo test --manifest-path rust/Cargo.toml`）三份共用，原樣不譯。

## 7. 取代範圍

每份 README 中以「## 開發 / ## Development / ## 开发」為起點到檔案結尾的整段全部替換為新版內容。`README.md` 與 `README_ZH-CN.md` 的 `## 開發` / `## 开发` 區塊（含 ### 子章節）自第 65 行起替換；`README_EN.md` 自第 67 行 `## Development` 起替換。其餘章節（簡介、多國語言、下載、功能清單、截圖）不動。

## 8. 風險與後續

- **codegen 版本**：`cargo install flutter_rust_bridge_codegen` 不指定版本，會抓最新版。`pubspec.yaml` 鎖在 `flutter_rust_bridge: ^2.12.0`、`Cargo.toml` 鎖在 `flutter_rust_bridge = "=2.12.0"`，若未來 codegen 主版本跳號可能與 runtime 不相容。本次先不在 README 內鎖版本，待真的踩到再補。
- **Arm64**：Flutter 官方支援 windows-arm64，但本專案 Rust 依賴未驗證可在 arm64 編。本次刻意不提，避免誤導。
- **未來新增平台**：若日後加 macOS / Linux 支援，需要再開新 spec 補對應章節。
