# GitHub Release 草稿自動 build & 附加 installer

- **建立日期**：2026-05-20
- **狀態**：Design 已定稿，待轉 implementation plan
- **適用分支**：`flutter-rewrite`（合併入 `master` 後正式啟用）
- **目標**：在 GitHub UI 建立 release 草稿時，CI 自動產出 Windows installer 並附加到「同一個草稿」，使用者只需按 Publish。

---

## 1. 背景

### 1.1 專案現況
- Flutter + Rust bridge 桌面應用，目前正從 Electron 版重寫到 Flutter（branch `flutter-rewrite`）。
- Windows 打包鏈完整：`scripts\build_installer\build_release.ps1` → 讀 `pubspec.yaml` version → `flutter build windows --release` → ISCC 編譯 `installer.iss` → 產出 `build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-<ver>.exe`。
- `installer.iss` 內含舊 Electron 版自動卸載邏輯（AppId 固定 GUID，不得變更）。
- `.github/` 目前只有 `FUNDING.yml` 和 `dependabot.yml`，**沒有任何 workflow**。
- `pubspec.yaml` 版本仍是預設 `1.0.0+1`，尚未啟動正式版號管理。

### 1.2 動機
- 目前發版要手動：本地跑 build script → 把 exe 拖到 GitHub release 頁面。
- 想自動化：建草稿 → 走開 → 回來按 Publish。

---

## 2. 核心設計決定

| 決定點 | 採用 | 否決選項 | 理由 |
|---|---|---|---|
| **Trigger** | `on: release` → `types: [created]`，內部 `if: github.event.release.draft == true` | (B) push tag 自建草稿；(C) workflow_dispatch | 最貼近使用者字面需求；release notes 可在 UI 寫好 |
| **版本 SoT** | Tag 驅動，CI 改寫 pubspec 並 push 回 master | pubspec 驅動 / 雙邊各管各 | 一個動作（建草稿）完成所有事 |
| **Pubspec push 時機** | Build 之前 push | Build 成功才 push | installer 內部版號永遠對齊 tag；失敗時 pubspec 已 bump 為可接受代價 |
| **Signing** | 預留 if-block + secrets 命名，這版完全 skip | 現在就接 | 還沒拿到憑證 |
| **目標平台** | Windows-only | macOS / Linux 同步 | 目前 `installer.iss` 只支援 Windows，YAGNI |
| **Job 結構** | 單 job、單平台、無 matrix | reusable workflow / matrix | 只有一個產物 |
| **Flutter 版本管理** | 新建 `.fvmrc`，`subosito/flutter-action@v2` 用 `flutter-version-file: .fvmrc` | 寫死於 workflow yaml | 本地 fvm 跟 CI 共用同一個檔，避免版本漂移 |
| **Inno Setup 安裝** | chocolatey (`choco install innosetup`) | winget / 手動下載 | windows-latest runner 上 chocolatey 比 winget 穩 |
| **Commit 身份** | `github-actions[bot]` | 使用者本人 email | CI 自動 commit 跟人為 commit 在歷史上分得開 |
| **Build number** | `${{ github.run_number }}` | run_attempt / release id | 單調遞增、跨 run 不重複 |
| **Installer 上傳檔名** | 與 `build_release.ps1` / `installer.iss` 產出的檔名**完全一致**（CI glob 出檔案，不重組路徑、不改名） | workflow 端重組檔名 / 加 tag 後綴 | 避免「pubspec version `1.2.3+47` vs installer.iss 用 `1.2.3`」這類字串不一致造成找不到檔；單一 source of truth = 實際產物 |

---

## 3. 整體流程

```
使用者在 GitHub UI 建草稿 release
  ├─ Tag name      : v1.2.3
  ├─ Target branch : master
  ├─ ☑ Set as draft
  └─ 寫 release notes
        │
        ▼  GitHub 觸發 release.created event
┌────────────────────────────────────────────────────────────┐
│ workflow: .github/workflows/release-windows.yml            │
│ runs-on: windows-latest                                    │
│ if: github.event.release.draft == true                     │
│                                                            │
│  A. Guard      檢查 draft + tag 格式                       │
│  B. 環境準備   checkout target_commitish / Flutter / Rust  │
│                / Inno Setup                                │
│  C. 版本注入   解析 tag → 改 pubspec → commit + push       │
│  D. Build      呼叫 build_release.ps1                      │
│  E. Sign       (skip,留 if-block)                         │
│  F. Upload     gh release upload --clobber                 │
│  G. Artifact   upload-artifact (30 天,debug 用)            │
│  H. Summary    寫 GITHUB_STEP_SUMMARY                      │
└────────────────────────────────────────────────────────────┘
        │
        ▼
草稿 release 帶著 exe,等使用者按「Publish」
```

---

## 4. 詳細實作規格

### 4.1 新建 / 修改檔案清單

| 檔案 | 狀態 | 用途 |
|---|---|---|
| `.github/workflows/release-windows.yml` | 新建 | 主 workflow |
| `.fvmrc` | 新建 | Flutter 版本鎖定（內容由實作者填入當下開發用的版本） |
| `scripts\build_installer\build_release.ps1` | 修改 | (1) ISCC 偵測加 PATH fallback；(2) 加 signing if-block 預留掛點 |
| `docs/release.md` | 新建 | Release 操作流程文件（給使用者看） |

**不動的檔案**：`installer.iss`、`ChineseTraditional.isl`、`ChineseSimplified.isl`、`pubspec.yaml`（CI 會改但不在本 spec 範圍內預先動）。

### 4.2 `.github/workflows/release-windows.yml` 骨架

```yaml
name: release-windows
run-name: release ${{ github.event.release.tag_name }}

on:
  release:
    types: [created]

permissions:
  contents: write  # push pubspec bump + upload release asset

concurrency:
  group: release-${{ github.event.release.id }}
  cancel-in-progress: false

jobs:
  build-windows:
    if: github.event.release.draft == true
    runs-on: windows-latest

    env:
      WINDOWS_SIGN_PFX_BASE64: ${{ secrets.WINDOWS_SIGN_PFX_BASE64 }}
      WINDOWS_SIGN_PASSWORD:   ${{ secrets.WINDOWS_SIGN_PASSWORD }}

    steps:
      # === A. Guard + Checkout =======================================
      - name: Checkout target branch
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.release.target_commitish }}
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      # === B. Toolchain ==============================================
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version-file: .fvmrc
          channel: stable
          cache: true

      - name: Setup Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Cache Rust
        uses: Swatinem/rust-cache@v2
        with:
          workspaces: rust_builder -> target

      - name: Install Inno Setup 6
        run: choco install innosetup -y --no-progress
        shell: pwsh

      - name: Verify ISCC on PATH
        run: |
          $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue)
          if (-not $iscc) { throw "ISCC.exe not on PATH after chocolatey install" }
          Write-Host "ISCC: $($iscc.Source)"
        shell: pwsh

      # === C. Version injection ======================================
      - name: Parse tag & rewrite pubspec
        shell: pwsh
        run: |
          $tag = "${{ github.event.release.tag_name }}"
          if ($tag -notmatch '^v(\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?)$') {
            throw "tag '$tag' does not match vX.Y.Z[-prerelease]"
          }
          $semver = $Matches[1]
          $buildNumber = ${{ github.run_number }}
          $pubspecVersion = "$semver+$buildNumber"

          $content = Get-Content pubspec.yaml -Raw -Encoding UTF8
          $updated = [regex]::Replace($content, '(?m)^version:\s*\S+\s*$', "version: $pubspecVersion", 1)

          if ($updated -eq $content) {
            "VERSION_CHANGED=false" | Out-File $env:GITHUB_ENV -Append
          } else {
            Set-Content pubspec.yaml -Value $updated -Encoding UTF8 -NoNewline
            "VERSION_CHANGED=true" | Out-File $env:GITHUB_ENV -Append
          }
          "PUBSPEC_VERSION=$pubspecVersion" | Out-File $env:GITHUB_ENV -Append
          "SEMVER=$semver" | Out-File $env:GITHUB_ENV -Append

      - name: Commit pubspec bump
        if: env.VERSION_CHANGED == 'true'
        shell: pwsh
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add pubspec.yaml
          git commit -m "chore(release): bump version to v${{ env.SEMVER }} [skip ci]"
          git push origin HEAD:${{ github.event.release.target_commitish }}

      # === D. Build ==================================================
      - name: Build Windows installer
        shell: pwsh
        run: .\scripts\build_installer\build_release.ps1

      - name: Locate installer
        shell: pwsh
        run: |
          $candidates = @(Get-ChildItem build\installer\*.exe -ErrorAction SilentlyContinue)
          if ($candidates.Count -eq 0) { throw "build\installer 內沒有 *.exe" }
          if ($candidates.Count -gt 1) { throw "build\installer 內有多個 *.exe,預期僅 1 個:`n$($candidates.FullName -join "`n")" }
          $exe = $candidates[0].FullName
          "INSTALLER_PATH=$exe" | Out-File $env:GITHUB_ENV -Append
          "INSTALLER_NAME=$($candidates[0].Name)" | Out-File $env:GITHUB_ENV -Append

      # === E. Sign (skip, structure only) ============================
      # build_release.ps1 內部自帶 if-block,有 secrets 才 sign。

      # === F. Upload to release draft ===============================
      - name: Upload installer to release draft
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          $tag = "${{ github.event.release.tag_name }}"
          # 上傳檔名與 build 產物完全一致,不改名
          gh release upload "$tag" "${{ env.INSTALLER_PATH }}" --clobber

      # === G. Workflow artifact (debug fallback) ====================
      - name: Upload installer as workflow artifact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: windows-installer-${{ env.PUBSPEC_VERSION }}
          path: build/installer/*.exe
          retention-days: 30
          if-no-files-found: warn

      # === H. Step summary ===========================================
      - name: Write step summary
        if: success()
        shell: pwsh
        run: |
          $exe = "${{ env.INSTALLER_PATH }}"
          $size = [math]::Round((Get-Item $exe).Length / 1MB, 2)
          $sha  = (Get-FileHash $exe -Algorithm SHA256).Hash
          @"
          ## Release ${{ github.event.release.tag_name }}

          - **Pubspec version**: ${{ env.PUBSPEC_VERSION }}
          - **Installer**: ``${{ env.INSTALLER_NAME }}``
          - **Size**: $size MB
          - **SHA-256**: ``$sha``
          - **Uploaded to release**: ✓
          "@ | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
```

### 4.3 `build_release.ps1` 調整

#### (1) ISCC 偵測加 PATH fallback

在 `Find-ISCC` 既有 fallback path 之後加：

```powershell
# PATH lookup（CI 環境 / chocolatey 安裝走這條）
$onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($onPath) { return $onPath.Source }
```

#### (2) Signing 預留掛點

在 `flutter build windows --release` **之後**、`ISCC` **之前**插入 app exe signing block；在 ISCC **之後**插入 installer signing block。**這版兩個 block 內都只放 TODO 註解 + log，不實際呼叫 signtool**：

```powershell
if ($env:WINDOWS_SIGN_PFX_BASE64 -and $env:WINDOWS_SIGN_PASSWORD) {
    Write-Host "==> Signing app exe (TODO: signtool)" -ForegroundColor Yellow
    # TODO(signing): 用 base64 還原 pfx,呼叫 signtool sign /f ... /p ... <exe>
} else {
    Write-Host "==> Skip app exe signing (no cert)" -ForegroundColor DarkGray
}
```

### 4.4 `.fvmrc` 內容

```json
{
  "flutter": "3.41.9"
}
```

對應使用者本地 Flutter stable 3.41.9（Dart 3.11.5，與 `pubspec.yaml` 的 `sdk: ^3.11.5` 一致）。**後續升 Flutter 走 PR 改 `.fvmrc` 一次更新本地與 CI**。

### 4.5 `docs/release.md` 內容

操作 SOP，至少包含：
1. 確認 master 已是想發版的狀態
2. GitHub Releases → Draft a new release
3. Tag name：`vX.Y.Z`（必須符合 semver；prerelease 寫 `vX.Y.Z-rc.N`）
4. Target：master
5. 寫 release notes，**勾選「Set as a draft」**
6. 點 "Save draft"
7. 到 Actions 頁面看 `release-windows` 跑完
8. 回到該 release 草稿，確認 exe 已附上
9. 點 "Publish release"
10. **失敗排查**：若 workflow fail，看 step log；artifact 內有 exe 可手動拖上去

---

## 5. 錯誤處理 / Recovery 矩陣

| 失敗點 | release 草稿 | pubspec 已 push? | 救援 |
|---|---|---|---|
| Tag 名不符 vX.Y.Z | 保留無 exe | 否 | 刪草稿、改 tag 名重建 |
| pubspec push race | 保留無 exe | 否 | 刪草稿、本地 rebase 後重建 |
| flutter build fail | 保留無 exe | **是** | 修代碼 push → 刪草稿重建（新 build_number） |
| ISCC fail | 保留無 exe | **是** | 同上 |
| gh release upload fail | 保留無 exe | **是** | 從 workflow artifact 下載 exe，UI 拖上去 |
| 事件 fire 兩次 | 保留 | idempotent（pubspec 已是該版會 skip commit） | `--clobber` 覆寫 asset |

---

## 6. 可觀測性

- **`run-name`**：用 release tag 命名 workflow run
- **`GITHUB_STEP_SUMMARY`**：成功時寫一份摘要（tag、version、size、SHA-256）
- **失敗通知**：暫不接外部，依賴 GitHub 預設 email
- **既有 `Write-Host`**：`build_release.ps1` 內的 log 全數會出現在 workflow log

---

## 7. 測試策略

| 層級 | 做法 | 抓什麼 |
|---|---|---|
| **L1** | 本地跑 `build_release.ps1` 確認既有腳本 + 兩處調整不破 | 既有腳本 / ISCC PATH fallback |
| **L2** | PR 上**暫時**加 `workflow_dispatch` trigger 跟 inputs（tag、target branch），手動跑驗證；merge 前移除 | 環境裝設、toolchain、ISCC compile、pubspec 改寫邏輯 |
| **L3** | 在同 repo 用 `v0.0.0-test.N` prerelease 草稿做真實演練；演練完刪 test tag + test commit | `release: created` 真實 payload、gh release upload、push pubspec 到 master |

**L2 暫時加的 workflow_dispatch 寫法**（merge 前必須移除）：

```yaml
on:
  release:
    types: [created]
  workflow_dispatch:
    inputs:
      tag:
        description: 'Tag name to simulate (e.g. v0.0.0-dryrun)'
        required: true
      target_branch:
        description: 'Target branch'
        required: true
        default: 'master'
```

對應 step 內讀取改用：`${{ github.event.release.tag_name || inputs.tag }}` 等的 fallback。

**注意**：job 層的 `if: github.event.release.draft == true` 在 workflow_dispatch 事件下會 evaluate 成 false（payload 沒有 `release` key），導致 L2 整個 job 被 skip。L2 期間 `if` 條件要改成：

```yaml
if: github.event_name == 'workflow_dispatch' || github.event.release.draft == true
```

**完成驗證後從 yaml 移除 `workflow_dispatch` block 並還原 `if` 條件**，避免 production workflow 帶測試入口。

---

## 8. YAGNI / 不採用清單

- ❌ macOS / Linux job
- ❌ matrix build
- ❌ reusable workflow
- ❌ rollback workflow（手動刪 tag + commit 即可）
- ❌ 自動 changelog / release notes 生成
- ❌ Discord / Slack 通知
- ❌ multi-channel（stable / beta）
- ❌ self-hosted runner
- ❌ build artifact cache（release 必須乾淨 build）

---

## 9. 已知風險 / 待觀察項

1. **`release: created` 對 draft 的觸發**：歷史上有報 flaky 紀錄，已加 `if: draft == true` 過濾並 `--clobber` 保 idempotent。L3 演練務必驗證。
2. **Pubspec push race**：使用者在 CI 期間 push 新 commit 會導致 push fail。Recovery 是手動重建草稿，預期罕見。
3. **`.fvmrc` 與本地 fvm 同步**：使用者沒裝 fvm 時，CI 仍能跑（`subosito/flutter-action` 讀檔即可）；但本地 build 若使用者裝的 Flutter 版本與 `.fvmrc` 不同，可能 build 出微差結果。建議文件內加註「升 Flutter 走 PR」。
4. **Branch protection**：使用者已確認 master 沒有阻擋 `GITHUB_TOKEN` push。將來若加 protection 必須加 Actions bot 例外。
5. **Signing 啟用時的範圍**：app exe vs installer 都簽 vs 只簽 installer，將來真的接憑證時要再做決定。
