# GitHub Release Auto-Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 當使用者在 GitHub UI 建立 release 草稿時，CI 自動產出 Windows installer 並附加到同一個草稿。

**Architecture:** 單一 GitHub Actions workflow（`windows-latest` runner），由 `release: created` event 觸發，job 層 `if` 過濾僅處理草稿。**所有 build 邏輯直接呼叫既有 `scripts/build_installer/build_release.ps1`，YAML 不重抄 flutter / ISCC 步驟**。CI 在 build 前把 tag 解析的版號寫入 `pubspec.yaml` 並以 `github-actions[bot]` 身份 push 回 master，確保 installer 內部版號永遠對齊 release tag。

**Tech Stack:** GitHub Actions、PowerShell 7、Flutter 3.41.9（`subosito/flutter-action@v2` + `.fvmrc`）、Rust（`dtolnay/rust-toolchain@stable`）、Inno Setup 6（chocolatey）、`gh` CLI。

**Spec reference:** `docs/superpowers/specs/2026-05-20-github-release-auto-build-design.md`

---

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `.fvmrc` | Create | 鎖 Flutter SDK 版本，本地 fvm 與 CI 共用 |
| `scripts/build_installer/build_release.ps1` | Modify | (1) ISCC 偵測加 PATH fallback；(2) 加 signing if-block 預留掛點 |
| `.github/workflows/release-windows.yml` | Create | 主 CI workflow |
| `docs/release.md` | Create | 發版操作 SOP（給使用者看） |

**不動的檔案**：`installer.iss`、`ChineseTraditional.isl`、`ChineseSimplified.isl`、`pubspec.yaml`（CI 會在 runtime 動態改寫）、任何 `lib/` / `test/` / `windows/` 下的檔案。

---

## Branching 假設

本 plan 假設執行者在 `flutter-rewrite` branch 上開新 feature branch（例如 `feat/ci-release-windows`），完成後 PR merge 回 `flutter-rewrite`。L3 真實 release 測試需等 `flutter-rewrite` 合入 master 後才能進行（GitHub `release` event 只 fire default branch 的 workflow）。

---

## Pre-flight Checks

- [ ] **Step 0.1: 確認工作分支與工作樹乾淨**

Run:
```bash
git status
git branch --show-current
```
Expected: working tree clean；branch 為 `flutter-rewrite` 或新 feature branch。

若要開新 feature branch：
```bash
git checkout -b feat/ci-release-windows
```

- [ ] **Step 0.2: 確認本地工具可用**

Run:
```bash
flutter --version
ISCC.exe /?
```
Expected:
- Flutter 3.41.9（stable）
- ISCC 顯示 usage（Inno Setup 6.3+）

若 ISCC 不在 PATH，從 https://jrsoftware.org/isdl.php 安裝 Inno Setup 6 後重開 shell 再試。

- [ ] **Step 0.3: 確認 baseline build 可跑（無任何本 plan 的改動）**

Run: `.\scripts\build_installer\build_release.ps1`
Expected: 成功，產出 `build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-1.0.0.exe`。

若失敗：先修，**plan 假設既有 build 鏈本身是綠的**。

---

### Task 1: 新建 `.fvmrc` 鎖 Flutter 版本

**Files:**
- Create: `.fvmrc`

- [ ] **Step 1.1: 建立 `.fvmrc`**

Create file `.fvmrc` with exact content:
```json
{
  "flutter": "3.41.9"
}
```

- [ ] **Step 1.2: 驗證內容**

Run: `Get-Content .fvmrc -Raw`
Expected: 印出上方 JSON 內容。

- [ ] **Step 1.3: （選用）若本地裝有 fvm，驗證能解析**

Run: `fvm use 2>$null`
Expected: 若 fvm 存在，會輸出 "Now using flutter 3.41.9"；若 fvm 不存在，命令會失敗——略過。

- [ ] **Step 1.4: Commit**

```bash
git add .fvmrc
git commit -m "chore(ci): pin Flutter SDK 3.41.9 via .fvmrc"
```

---

### Task 2: `build_release.ps1` 加 ISCC PATH fallback

**Files:**
- Modify: `scripts/build_installer/build_release.ps1` (function `Find-ISCC`)

- [ ] **Step 2.1: 在 `Find-ISCC` 內加 PATH 查找**

Open `scripts/build_installer/build_release.ps1`。找到既有 `Find-ISCC` 函式（約 line 35-62）。在 `$FallbackPaths` 迴圈之後、`return $null` 之前插入：

```powershell
    # PATH lookup（CI 環境 / chocolatey 安裝走這條）
    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
```

調整後 `Find-ISCC` 結尾應為：
```powershell
    foreach ($p in $FallbackPaths) {
        if (Test-Path $p) { return $p }
    }

    # PATH lookup（CI 環境 / chocolatey 安裝走這條）
    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    return $null
}
```

- [ ] **Step 2.2: 跑一遍 build 確認沒破**

Run: `.\scripts\build_installer\build_release.ps1`
Expected: 完成，產出 `build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-1.0.0.exe`。本地有註冊表項，會走原本路徑，PATH fallback 不會被觸發，但需確認沒語法錯。

- [ ] **Step 2.3: Commit**

```bash
git add scripts/build_installer/build_release.ps1
git commit -m "chore(build): add ISCC PATH lookup fallback for CI"
```

---

### Task 3: `build_release.ps1` 加 signing if-block 預留掛點

**Files:**
- Modify: `scripts/build_installer/build_release.ps1`（兩處插入）

- [ ] **Step 3.1: 在 flutter build 之後插入 app exe signing block**

找到 `build_release.ps1` 約 line 83：
```powershell
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build 失敗" }
```

緊接其後（在 `# --- 4. 編譯安裝檔 ----...` 註解之前）插入：

```powershell

# --- 3a. (Optional) Sign app exe before packaging --------------------------
if ($env:WINDOWS_SIGN_PFX_BASE64 -and $env:WINDOWS_SIGN_PASSWORD) {
    Write-Host ""
    Write-Host "==> Signing app exe (TODO: signtool)" -ForegroundColor Yellow
    # TODO(signing): 用 base64 還原 pfx,呼叫 signtool sign /f ... /p ... build\windows\x64\runner\Release\*.exe
}
else {
    Write-Host ""
    Write-Host "==> Skip app exe signing (no cert configured)" -ForegroundColor DarkGray
}
```

- [ ] **Step 3.2: 在 ISCC 編譯之後插入 installer signing block**

找到 `build_release.ps1` 約 line 94：
```powershell
& $ISCC "/DMyAppVersion=$Version" $IssPath
if ($LASTEXITCODE -ne 0) { throw "ISCC 編譯失敗" }
```

緊接其後（在 `# --- 5. 報告產物 ---...` 註解之前）插入：

```powershell

# --- 4a. (Optional) Sign installer after ISCC -----------------------------
if ($env:WINDOWS_SIGN_PFX_BASE64 -and $env:WINDOWS_SIGN_PASSWORD) {
    Write-Host ""
    Write-Host "==> Signing installer (TODO: signtool)" -ForegroundColor Yellow
    # TODO(signing): signtool sign /f ... /p ... <installer.exe>
}
else {
    Write-Host ""
    Write-Host "==> Skip installer signing (no cert configured)" -ForegroundColor DarkGray
}
```

- [ ] **Step 3.3: 跑一遍 build 確認兩個 block 都進入 else 分支**

Run: `.\scripts\build_installer\build_release.ps1`
Expected: 完成，log 中包含兩行 `==> Skip ... signing (no cert configured)`（暗灰色）。

- [ ] **Step 3.4: Commit**

```bash
git add scripts/build_installer/build_release.ps1
git commit -m "chore(build): add optional signing if-blocks (no-op without cert)"
```

---

### Task 4: 新建 `.github/workflows/release-windows.yml`

**Files:**
- Create: `.github/workflows/release-windows.yml`

- [ ] **Step 4.1: 建立 workflow 檔，內容如下**

Create `.github/workflows/release-windows.yml` with exact content:

```yaml
name: release-windows
run-name: release ${{ github.event.release.tag_name }}

on:
  release:
    types: [created]

permissions:
  contents: write

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
      # === A. Checkout target branch ================================
      - name: Checkout target branch
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.release.target_commitish }}
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      # === B. Toolchain =============================================
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
        shell: pwsh
        run: choco install innosetup -y --no-progress

      - name: Verify ISCC on PATH
        shell: pwsh
        run: |
          $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
          if (-not $iscc) { throw "ISCC.exe not on PATH after chocolatey install" }
          Write-Host "ISCC: $($iscc.Source)"

      # === C. Version injection =====================================
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

      # === D. Build =================================================
      - name: Build Windows installer
        shell: pwsh
        run: .\scripts\build_installer\build_release.ps1

      - name: Locate installer
        shell: pwsh
        run: |
          $candidates = @(Get-ChildItem build\installer\*.exe -ErrorAction SilentlyContinue)
          if ($candidates.Count -eq 0) { throw "build\installer 內沒有 *.exe" }
          if ($candidates.Count -gt 1) {
            throw "build\installer 內有多個 *.exe,預期僅 1 個:`n$($candidates.FullName -join "`n")"
          }
          $exe = $candidates[0].FullName
          "INSTALLER_PATH=$exe" | Out-File $env:GITHUB_ENV -Append
          "INSTALLER_NAME=$($candidates[0].Name)" | Out-File $env:GITHUB_ENV -Append

      # === E. Sign (skip, structure 內嵌於 build_release.ps1) ==========

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

      # === H. Step summary ==========================================
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

- [ ] **Step 4.2: YAML 靜態檢查（若 actionlint 可用）**

Run: `actionlint .github/workflows/release-windows.yml`
Expected: 無 error。

若本地沒裝 actionlint：
- chocolatey: `choco install actionlint -y`
- 或從 https://github.com/rhysd/actionlint/releases 下載

若無法安裝 actionlint：略過此步，L2 測試會抓到 syntax issue。

- [ ] **Step 4.3: Commit**

```bash
git add .github/workflows/release-windows.yml
git commit -m "feat(ci): add release-windows workflow for draft auto-build"
```

---

### Task 5: 新建 `docs/release.md`

**Files:**
- Create: `docs/release.md`

- [ ] **Step 5.1: 建立 release SOP 文件**

Create `docs/release.md` with exact content:

````markdown
# Release SOP

如何發 Genshin Impact Wish Gacha Analyzer 新版本（Windows installer）。

## 前置條件

- `master` 已是要發版的 commit
- Tag 名遵循 semver：`vX.Y.Z` 或 `vX.Y.Z-rc.N`
- 你有 repo 的 release 建立權限

## 步驟

1. **建立 release 草稿**
   - GitHub repo → Releases → "Draft a new release"
   - **Tag name**：`vX.Y.Z`（必須符合 semver；不要帶 `+build` 部分；prerelease 寫 `vX.Y.Z-rc.N`）
   - **Target**：`master`
   - **☑ Set as a draft**（要發 prerelease 另外勾「Set as a pre-release」）
   - **Release notes**：自由填寫
   - 點 **"Save draft"**

2. **等 CI 跑完**
   - 觸發 workflow：`release-windows`
   - Actions 頁面看 run 結果（run name = release tag）

3. **確認 installer 已附上**
   - 回到該 release 草稿頁面
   - Assets 區應該有 `Genshin_Impact_Wish_Gacha_Analyzer-Setup-X.Y.Z.exe`
   - Workflow run 的 step summary 會顯示 SHA-256 / size

4. **Publish**
   - 草稿頁面點 **"Publish release"**
   - GitHub 把 tag 打在 master 當下 tip（含 CI push 的 pubspec bump commit）

## 失敗排查

| 症狀 | 處理 |
|---|---|
| Workflow fail：tag 名不符 | 刪草稿、改 tag 名重建 |
| Workflow fail：build / ISCC 失敗 | 看 step log；修代碼 push 到 master 後刪草稿重建 |
| Workflow 成功但 release 沒 exe | 從 workflow run 下載 artifact (`windows-installer-X.Y.Z+N`)，手動拖到草稿 |
| Pubspec push race（你在 CI 期間 push 了新 commit） | 刪草稿、本地 rebase、重建草稿 |

## 注意事項

- **每次發版 CI 會自動 push 一個 pubspec bump commit 到 master**，commit author 顯示為 `github-actions[bot]`。
- **發版前不要手動改 pubspec version**——讓 CI 改，避免雙方衝突。
- **Tag 不要重用**：刪了草稿不會刪 tag，但 GitHub 允許舊 tag 重綁 release。為避免混亂，刪草稿時順手刪 tag：`git push origin :refs/tags/vX.Y.Z`。
- **不要在 master 之外的 branch 發 release**：CI 會 push pubspec 到 release `target_commitish`，誤推到 dev branch 會把 dev branch 也 bump 版號。
- **升 Flutter 版本走 PR 改 `.fvmrc`**：CI 與本地會同步切換。
````

- [ ] **Step 5.2: Commit**

```bash
git add docs/release.md
git commit -m "docs: add release SOP"
```

---

### Task 6: L1 — 本地完整 sanity build + pre-commit 品質檢查

- [ ] **Step 6.1: 清乾淨 build 目錄**

```powershell
Remove-Item build\installer -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 6.2: 跑完整 build script**

Run: `.\scripts\build_installer\build_release.ps1`
Expected: 成功，產出 `build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-1.0.0.exe`。log 中包含兩個 `==> Skip ... signing (no cert configured)`。

- [ ] **Step 6.3: 跑 CLAUDE.md 規定的提交前品質檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected:
- `dart format`：clean（本 plan 沒改 dart 檔，預期無變化）
- `flutter analyze`：`No issues found!`
- `flutter test`：`All tests passed!`（若 flake 在 `log_service` 或 `app_release_checker`，re-run 即可——見 [[project_flaky_parallel_test_suite]]）

無新 commit（前面每個 task 已個別 commit；此 task 是驗證 gate）。

---

### Task 7: L2 — 在 PR 上加暫時 `workflow_dispatch` 跑驗證

> ⚠️ 本 task 的修改是**暫時**的，Task 8 會 revert。先 push 一個 separate commit 方便 revert。

**Files:**
- Modify: `.github/workflows/release-windows.yml`（暫時加 trigger）

- [ ] **Step 7.1: Push branch 到 origin**

```bash
git push -u origin feat/ci-release-windows
```
（branch 名以實際為準）

- [ ] **Step 7.2: 開 PR**

```bash
gh pr create --base flutter-rewrite --fill --draft
```

- [ ] **Step 7.3: 修改 workflow 加 workflow_dispatch trigger + 4 處 fallback**

修改 `.github/workflows/release-windows.yml`：

**(a) 替換 `on:` 區塊**

從：
```yaml
on:
  release:
    types: [created]
```
改為：
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
        default: 'feat/ci-release-windows'
```

**(b) 替換 job 層 `if`**

從：
```yaml
    if: github.event.release.draft == true
```
改為：
```yaml
    if: github.event_name == 'workflow_dispatch' || github.event.release.draft == true
```

**(c) 替換 checkout `ref`**

從：
```yaml
          ref: ${{ github.event.release.target_commitish }}
```
改為：
```yaml
          ref: ${{ github.event.release.target_commitish || inputs.target_branch }}
```

**(d) 替換 tag 解析中的 `$tag`**

於「Parse tag & rewrite pubspec」step 內，把：
```powershell
$tag = "${{ github.event.release.tag_name }}"
```
改為：
```powershell
$tag = "${{ github.event.release.tag_name || inputs.tag }}"
```

**(e) 替換 git push 目標**

於「Commit pubspec bump」step 內，把：
```yaml
git push origin HEAD:${{ github.event.release.target_commitish }}
```
改為：
```yaml
git push origin HEAD:${{ github.event.release.target_commitish || inputs.target_branch }}
```

**(f) Upload step 改為僅 release event 才跑**

於「Upload installer to release draft」step 加 `if`：
```yaml
      - name: Upload installer to release draft
        if: github.event_name == 'release'
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          $tag = "${{ github.event.release.tag_name }}"
          gh release upload "$tag" "${{ env.INSTALLER_PATH }}" --clobber
```

理由：workflow_dispatch 跑時沒有真實 release，跳過上傳；artifact step (G) 還是會跑，從 artifact 取 exe 驗證。

- [ ] **Step 7.4: Commit L2 改動為獨立 commit**

```bash
git add .github/workflows/release-windows.yml
git commit -m "ci(temp): add workflow_dispatch for L2 testing — REVERT before merge"
git push
```

- [ ] **Step 7.5: 在 GitHub UI 手動觸發 workflow**

操作：
1. GitHub repo → Actions tab → 左側選 `release-windows`
2. 右上「Run workflow」下拉
3. **Use workflow from**：選你的 PR branch
4. **inputs**：
   - `tag`：`v0.0.0-dryrun`
   - `target_branch`：你的 PR branch 名
5. 點 **Run workflow**

- [ ] **Step 7.6: 觀察並驗證**

Workflow run 應該：
- [ ] Checkout 成功（在 PR branch 上）
- [ ] Flutter / Rust / Inno Setup 三個 toolchain step 成功
- [ ] Verify ISCC on PATH 印出 `ISCC: C:\Program Files (x86)\Inno Setup 6\ISCC.exe`（或類似路徑）
- [ ] Parse tag step 成功，env 中有 `PUBSPEC_VERSION=0.0.0-dryrun+<n>`、`SEMVER=0.0.0-dryrun`
- [ ] Commit pubspec bump 成功（你的 PR branch 應該多了一個 `chore(release): bump version to v0.0.0-dryrun [skip ci]` commit）
- [ ] Build Windows installer 成功
- [ ] Locate installer 找到 1 個 exe
- [ ] **Upload to release draft** step 被 `if` 跳過（不應失敗）
- [ ] Upload artifact 成功
- [ ] Step summary 正確寫入

從 Run 頁面下載 artifact `windows-installer-0.0.0-dryrun+<n>`，解壓得到一個 exe。在 Windows VM 或本機跑這個 exe 確認可安裝、可啟動。

若 build 失敗：看 log → 修代碼 → push 到同 PR branch → 再 Run workflow。

---

### Task 8: 還原 L2 暫時改動

**Files:**
- Modify: `.github/workflows/release-windows.yml`（還原為 production 版本）

- [ ] **Step 8.1: Revert L2 commit**

```bash
# 找到 L2 commit hash
git log --oneline | Select-String "ci\(temp\)"

# Revert
git revert <L2 commit hash> --no-edit
```

- [ ] **Step 8.2: Revert CI push 的 pubspec bump commit**

L2 測試時 CI 在 PR branch 上推了一個 `chore(release): bump version to v0.0.0-dryrun` commit，pubspec 變成 `0.0.0-dryrun+<n>`。還原它：

```bash
git pull --rebase
git log --oneline | Select-String "bump version to v0.0.0-dryrun"
git revert <bump commit hash> --no-edit
```

- [ ] **Step 8.3: 驗證 workflow yaml 回到 production 狀態**

```bash
git diff HEAD~2..HEAD -- .github/workflows/release-windows.yml
```
Expected: 無 diff（兩個 revert 加起來把 L2 改動完全還原）。

Run: `Get-Content pubspec.yaml | Select-String "^version:"`
Expected: `version: 1.0.0+1`（pubspec 已還原）。

- [ ] **Step 8.4: Push revert commits**

```bash
git push
```

---

### Task 9: PR review + merge

- [ ] **Step 9.1: 把 PR 從 Draft 提到 Ready for review**

```bash
gh pr ready
```

- [ ] **Step 9.2: 自查 / peer review checklist**

PR diff 應該只剩下：
- [ ] `.fvmrc` 新建
- [ ] `scripts/build_installer/build_release.ps1` 修改（ISCC PATH fallback + signing if-blocks）
- [ ] `.github/workflows/release-windows.yml` 新建（**沒有 workflow_dispatch**、**`if` 是 `draft == true`**、**upload step 沒有額外的 `if`**）
- [ ] `docs/release.md` 新建
- [ ] `pubspec.yaml` 沒有變動

若以上有任何不符，回 Task 8 補修。

- [ ] **Step 9.3: Merge PR 到 `flutter-rewrite`**

```bash
gh pr merge --squash --delete-branch
```
（或依 repo 慣例選 merge / rebase）

- [ ] **Step 9.4: 在 `flutter-rewrite` 上拉最新**

```bash
git checkout flutter-rewrite
git pull
```

---

### Task 10: L3 — 真實 release dryrun（須 workflow 在 default branch 上）

> ⚠️ Prerequisite：workflow 必須在 GitHub repo 的 **default branch** 上，`release` event 才會 fire。
>
> - 若 default branch 仍是 `master` 且 `flutter-rewrite` 尚未合入 master：L3 須等到 merge 之後。
> - 若 default branch 已切到 `flutter-rewrite`：可立即進行。
>
> 假設前者：以下步驟在 `flutter-rewrite` 合入 master 之後執行。

- [ ] **Step 10.1: 在 GitHub UI 建立 test 草稿**

操作：
1. Releases → "Draft a new release"
2. **Choose a tag**：輸入 `v0.0.0-test.1`（如果系統說「Create new tag on publish」就選它）
3. **Target**：`master`
4. **Release title**：`L3 dryrun — delete after verify`
5. **Description**：`Testing release-windows workflow. Will be deleted.`
6. **☑ Set as a draft**
7. **☑ Set as a pre-release**（推薦，避免被誤認為正式版）
8. 點 **"Save draft"**

- [ ] **Step 10.2: 觀察 workflow 自動觸發**

GitHub → Actions → 應該在數秒內看到新 run，run name 為 `release v0.0.0-test.1`。

若沒觸發：檢查 release 是否真為 draft；workflow 是否在 default branch 上；workflow 檔名與 `on: release` 設定。

- [ ] **Step 10.3: 驗證每個 step 成功**

點進該 run：
- [ ] Job `build-windows` 不被 skip（`if` 條件命中）
- [ ] Checkout step 用 `master` HEAD
- [ ] Toolchain 三步全綠
- [ ] Verify ISCC on PATH OK
- [ ] Parse tag：`tag=v0.0.0-test.1` → `SEMVER=0.0.0-test.1` → `PUBSPEC_VERSION=0.0.0-test.1+<n>`
- [ ] Commit pubspec bump 成功（master 上多了一個 bump commit）
- [ ] Build Windows installer 成功
- [ ] Locate installer 找到 exe
- [ ] Upload to release draft 成功（log 顯示 `gh release upload`）
- [ ] Upload artifact 成功
- [ ] Step summary 正確

- [ ] **Step 10.4: 驗證 release 草稿被附上 exe**

GitHub → Releases → 找到 `v0.0.0-test.1` 草稿：
- [ ] Assets 區有 `Genshin_Impact_Wish_Gacha_Analyzer-Setup-0.0.0-test.1.exe`
- [ ] 注意：檔名是 `0.0.0-test.1`（installer.iss 的 regex 切掉 `+build_number`），不含 `+<n>`。這是預期行為。

- [ ] **Step 10.5: 下載 exe 驗證可安裝可執行**

從 release 頁面下載該 exe：
- [ ] 可正常啟動安裝精靈
- [ ] 安裝到 `C:\Program Files\Genshin_Impact_Wish_Gacha_Analyzer`
- [ ] 桌面 / 開始選單捷徑建立
- [ ] 啟動 app，About / 設定 內顯示版本 `0.0.0-test.1`（或 `0.0.0-test.1+<n>`）

- [ ] **Step 10.6: 清理**

```bash
# 刪 draft release (gh CLI)
gh release delete v0.0.0-test.1 --yes

# 若 tag 已建（通常 publish 後才建,草稿不會建,但保險起見）
git fetch --tags
git tag -l "v0.0.0-test.1"
# 若有,刪除
git push origin :refs/tags/v0.0.0-test.1 2>$null
git tag -d v0.0.0-test.1 2>$null

# Revert CI 在 master 上 push 的 pubspec bump
git checkout master
git pull
git log --oneline -5
# 找到 "chore(release): bump version to v0.0.0-test.1 [skip ci]" commit
git revert <bump commit hash> --no-edit
git push
```

- [ ] **Step 10.7: 確認 master 乾淨**

```bash
git log --oneline -5
Get-Content pubspec.yaml | Select-String "^version:"
```
Expected: master 最新 commit 是 revert；`pubspec.yaml` 版本回到 `1.0.0+1`。

---

## Done Criteria

- [ ] `.fvmrc`、`build_release.ps1` 改動、`release-windows.yml`、`docs/release.md` 都已 commit 並 merge 到 default branch
- [ ] L1 本地 sanity build 通過
- [ ] L2 PR 上 workflow_dispatch 演練通過
- [ ] L2 暫時改動已 revert，PR diff 乾淨
- [ ] L3 真實 dryrun 完整跑過：草稿建立 → CI 自動 build → exe 附到草稿 → 下載 exe 可安裝可啟動
- [ ] L3 test 資產（draft、tag、bump commit）都已清理
- [ ] 首次正式發版可循 `docs/release.md` 操作

---

## 風險與注意（從 spec §9 帶過來，executor 須留意）

1. **`release: created` 對 draft 的觸發 flakiness**：L3 演練務必確認真實觸發成功。若 Task 10 Step 10.2 沒看到 workflow run，**先不要直接相信 spec**——查 release event 設定、查 Actions log、查 workflow file 是否在 default branch。
2. **Pubspec push race**：本 plan 沒處理 race；發生時手動 recover。
3. **Branch protection**：使用者已確認 master 沒擋 `GITHUB_TOKEN` push。若 L3 push 失敗報 protection 相關錯，停下來、加 Actions bot 例外、或回 plan author 修設計。
4. **Signing 啟用時的範圍**：兩個 if-block 是預留位，將來真要簽再回頭。
