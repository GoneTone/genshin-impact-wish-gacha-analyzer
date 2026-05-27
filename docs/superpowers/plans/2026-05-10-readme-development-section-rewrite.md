# README 開發區塊改寫 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將三份 README（繁中、英文、簡中）的「開發 / Development / 开发」區塊從舊 Electron+npm 內容替換為 Flutter + flutter_rust_bridge 工作流程。

**Architecture:** 每份 README 視為獨立替換目標。從各檔案 `## 開發` / `## Development` / `## 开发` 標題到檔案結尾整段替換。最後做一次跨檔案一致性驗證，確保舊 npm/electron 字串完全清除、新 flutter/cargo 指令在三份都存在。

**Tech Stack:** Markdown 純文字編輯。驗證使用 ripgrep（透過 Grep 工具）。

---

## File Structure

| 檔案 | 動作 | 替換範圍 |
| --- | --- | --- |
| `README.md` | 修改 | 第 65 行 `## 開發` 至檔尾 |
| `README_EN.md` | 修改 | 第 67 行 `## Development` 至檔尾 |
| `README_ZH-CN.md` | 修改 | 第 65 行 `## 开发` 至檔尾 |

每個任務各自獨立，可單獨 commit。第 4 個任務做跨檔案驗證。

---

### Task 1: 替換 `README.md`（繁體中文）

**Files:**
- Modify: `README.md` (從第 65 行 `## 開發` 至檔尾，共 34 行)

- [ ] **Step 1: 讀取檔案末段確認當前內容**

Run: 讀取 `README.md` 第 65 行至檔尾。
Expected: 看到舊的 `## 開發` → `### 安裝依賴套件` → `npm install` → 一直到 `npm run electron:build:win64` 區塊（共 34 行，最後一行是 ` ``` `）。

- [ ] **Step 2: 用 Edit 工具替換整段**

`old_string`（從 `## 開發` 到檔尾原樣 34 行）：

````
## 開發

### 安裝依賴套件

```bash
npm install
```

### 編譯並執行 (開發)

```bash
npm run electron:serve
```

### 編譯並最小化 (生產)

#### ia32 和 x64

```bash
npm run electron:build:win
```

#### ia32

```bash
npm run electron:build:win32
```

#### x64

```bash
npm run electron:build:win64
```
````

`new_string`：

````
## 開發

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
````

- [ ] **Step 3: 驗證舊內容已清除**

使用 Grep 工具：
- pattern: `electron:|npm install|npm run`
- path: `README.md`
- output_mode: `content`

Expected: 無結果（exit code 1 / 0 matches）。

- [ ] **Step 4: 驗證新內容已加入**

使用 Grep 工具：
- pattern: `flutter pub get|flutter run -d windows|flutter_rust_bridge_codegen|flutter build windows --release`
- path: `README.md`
- output_mode: `count`

Expected: 共 4 個 match（每條指令各 1 次）。

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(readme): rewrite development section for Flutter+Rust (zh-TW)"
```

---

### Task 2: 替換 `README_EN.md`（English）

**Files:**
- Modify: `README_EN.md` (從第 67 行 `## Development` 至檔尾，共 33 行)

- [ ] **Step 1: 讀取檔案末段確認當前內容**

Run: 讀取 `README_EN.md` 第 67 行至檔尾。
Expected: 看到舊的 `## Development` → `### Install Packages` → `npm install` → 一直到 `npm run electron:build:win64` 區塊。

- [ ] **Step 2: 用 Edit 工具替換整段**

`old_string`（從 `## Development` 到檔尾原樣）：

````
## Development

### Install Packages

```bash
npm install
```

### Compile and Run (For Development Use)

```bash
npm run electron:serve
```

### Compile and Minify (For Production Use)

#### ia32 and x64

```bash
npm run electron:build:win
```

#### ia32

```bash
npm run electron:build:win32
```

#### x64

```bash
npm run electron:build:win64
```
````

`new_string`：

````
## Development

### Prerequisites

- Windows only for now
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (latest stable)
- [Rust toolchain](https://rustup.rs/) (stable)
- Run `flutter doctor` and install anything it flags as missing

### Clone and install dependencies

```bash
git clone https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer.git
cd genshin-impact-wish-gacha-analyzer
flutter pub get
cargo build --manifest-path rust/Cargo.toml
```

### Run in development mode

```bash
flutter run -d windows
```

### Rust ↔ Dart bridge code generation

After changing Rust functions in `rust/src/api/`, regenerate the bridge code. Install the codegen tool on first use:

```bash
cargo install flutter_rust_bridge_codegen
```

Then run this whenever the API changes:

```bash
flutter_rust_bridge_codegen generate
```

Generated files live in `lib/src/rust/`.

### Build for release

```bash
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\`

### Run tests

```bash
flutter test
cargo test --manifest-path rust/Cargo.toml
```
````

- [ ] **Step 3: 驗證舊內容已清除**

使用 Grep 工具：
- pattern: `electron:|npm install|npm run`
- path: `README_EN.md`
- output_mode: `content`

Expected: 無結果。

- [ ] **Step 4: 驗證新內容已加入**

使用 Grep 工具：
- pattern: `flutter pub get|flutter run -d windows|flutter_rust_bridge_codegen|flutter build windows --release`
- path: `README_EN.md`
- output_mode: `count`

Expected: 共 4 個 match。

- [ ] **Step 5: Commit**

```bash
git add README_EN.md
git commit -m "docs(readme): rewrite development section for Flutter+Rust (en)"
```

---

### Task 3: 替換 `README_ZH-CN.md`（简体中文）

**Files:**
- Modify: `README_ZH-CN.md` (從第 65 行 `## 开发` 至檔尾，共 34 行)

- [ ] **Step 1: 讀取檔案末段確認當前內容**

Run: 讀取 `README_ZH-CN.md` 第 65 行至檔尾。
Expected: 看到舊的 `## 开发` → `### 安装依赖套件` → `npm install` → 一直到 `npm run electron:build:win64` 區塊。

- [ ] **Step 2: 用 Edit 工具替換整段**

`old_string`（從 `## 开发` 到檔尾原樣）：

````
## 开发

### 安装依赖套件

```bash
npm install
```

### 编译并运行 (开发)

```bash
npm run electron:serve
```

### 编译并最小化 (生产)

#### ia32 和 x64

```bash
npm run electron:build:win
```

#### ia32

```bash
npm run electron:build:win32
```

#### x64

```bash
npm run electron:build:win64
```
````

`new_string`：

````
## 开发

### 前置需求

- 目前仅支持 Windows
- [Flutter SDK](https://flutter.dev/docs/get-started/install)（最新稳定版）
- [Rust toolchain](https://rustup.rs/)（stable）
- 运行 `flutter doctor`，依提示补齐缺少的工具

### 取得源代码并安装依赖

```bash
git clone https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer.git
cd genshin-impact-wish-gacha-analyzer
flutter pub get
cargo build --manifest-path rust/Cargo.toml
```

### 开发模式运行

```bash
flutter run -d windows
```

### Rust ↔ Dart 桥接代码生成

修改 `rust/src/api/` 内的 Rust 函数后，重新生成桥接代码。第一次使用前先安装 codegen 工具：

```bash
cargo install flutter_rust_bridge_codegen
```

之后每次修改 API 都运行：

```bash
flutter_rust_bridge_codegen generate
```

生成的文件位于 `lib/src/rust/`。

### 编译生产版

```bash
flutter build windows --release
```

输出：`build\windows\x64\runner\Release\`

### 运行测试

```bash
flutter test
cargo test --manifest-path rust/Cargo.toml
```
````

- [ ] **Step 3: 驗證舊內容已清除**

使用 Grep 工具：
- pattern: `electron:|npm install|npm run`
- path: `README_ZH-CN.md`
- output_mode: `content`

Expected: 無結果。

- [ ] **Step 4: 驗證新內容已加入**

使用 Grep 工具：
- pattern: `flutter pub get|flutter run -d windows|flutter_rust_bridge_codegen|flutter build windows --release`
- path: `README_ZH-CN.md`
- output_mode: `count`

Expected: 共 4 個 match。

- [ ] **Step 5: Commit**

```bash
git add README_ZH-CN.md
git commit -m "docs(readme): rewrite development section for Flutter+Rust (zh-CN)"
```

---

### Task 4: 跨檔案一致性最終驗證

**Files:**
- 讀取：三份 README

- [ ] **Step 1: 確認三份 README 都不再含 npm/electron 字串**

使用 Grep 工具：
- pattern: `electron:|npm install|npm run`
- glob: `README*.md`
- output_mode: `count`

Expected: 無結果（三份檔案都 0 match）。

- [ ] **Step 2: 確認三份 README 都含完整新指令**

使用 Grep 工具：
- pattern: `flutter pub get`
- glob: `README*.md`
- output_mode: `files_with_matches`

Expected: `README.md`、`README_EN.md`、`README_ZH-CN.md` 三個檔案皆出現。

再執行：
- pattern: `flutter_rust_bridge_codegen generate`
- glob: `README*.md`
- output_mode: `files_with_matches`

Expected: 同上三個檔案皆出現。

再執行：
- pattern: `cargo test --manifest-path rust/Cargo.toml`
- glob: `README*.md`
- output_mode: `files_with_matches`

Expected: 同上三個檔案皆出現。

- [ ] **Step 3: 確認章節結構在三份檔案完全對齊**

使用 Grep 工具：
- pattern: `^### `
- path: `README.md`
- output_mode: `content`
- `-n`: true

Expected 6 個 `###` 標題：前置需求 / 取得原始碼並安裝依賴 / 開發模式執行 / Rust ↔ Dart 橋接程式碼產生 / 編譯生產版 / 執行測試。

對 `README_EN.md` 重複，Expected 6 個英文標題：Prerequisites / Clone and install dependencies / Run in development mode / Rust ↔ Dart bridge code generation / Build for release / Run tests。

對 `README_ZH-CN.md` 重複，Expected 6 個簡中標題：前置需求 / 取得源代码并安装依赖 / 开发模式运行 / Rust ↔ Dart 桥接代码生成 / 编译生产版 / 运行测试。

- [ ] **Step 4: 確認 git 狀態乾淨**

```bash
git status
```

Expected: `nothing to commit, working tree clean`，前面三個 commit 都在 log。

```bash
git log --oneline -3
```

Expected: 三筆新 commit 訊息分別是 `docs(readme): rewrite development section for Flutter+Rust (zh-CN)`、`(en)`、`(zh-TW)`。

- [ ] **Step 5: 不需要額外 commit**

第 4 個任務只是驗證，沒有檔案修改。如果驗證失敗，回到對應 Task 1/2/3 修正並另外 commit；通過則任務完成。
