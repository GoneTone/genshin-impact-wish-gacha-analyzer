# release-windows workflow 觸發重設 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `release-windows` workflow 從跑不起來的 `release: types: [created]`（草稿不觸發）改為 `workflow_dispatch` 手動觸發，並讓 CI 自行建立附好 installer 的草稿、釘住 build 的 commit SHA，保留「公開前人工檢查」關卡。

**Architecture:** 觸發改 `workflow_dispatch`（輸入 `tag` + `prerelease`）；tag 來源由 release context 換成 `inputs.tag`；checkout/push 寫死 `master`；新增「擷取 release commit SHA」step；用冪等的 `gh release create --draft ... --target $SHA` / `gh release upload --clobber` 取代原僅上傳的 step；同步重寫 `docs/release.md` SOP。

**Tech Stack:** GitHub Actions（`workflow_dispatch`）、PowerShell（pwsh step）、GitHub CLI（`gh release`）。

---

## 背景與限制

- 只改兩個檔：`.github/workflows/release-windows.yml`、`docs/release.md`。**無 Dart 變更**，故 `dart format` / `flutter analyze` / `flutter test` 三道 gate 對本變更內容 trivially 通過（仍可依 CLAUDE.md 於 commit 前跑一次確認沒誤動）。
- `actionlint` 本機未安裝；YAML 驗證以**結構走讀**為主，`actionlint` 列為選用。
- `gh` 2.87.0 可用。
- 真正 end-to-end 只能在下次發版時實跑一次 `workflow_dispatch` 驗證（CI 無法本地模擬 signing/build）。
- CI 訊息一律英文（沿用既有慣例）。
- 計畫檔與 spec 位於 `docs/superpowers/`（本地不進版控），**不要 `git add` 計畫/spec 本身**。

## File Structure

| 檔案 | 責任 | 動作 |
|---|---|---|
| `.github/workflows/release-windows.yml` | Windows installer 發版 workflow | 改觸發、tag 來源、checkout 目標、新增 SHA step、改建草稿 step、改 step summary |
| `docs/release.md` | 發版 SOP 文件 | 重寫步驟 1/3、失敗表 |

---

### Task 1: 改觸發區塊（trigger / run-name / concurrency / 移除 job if）

**Files:**
- Modify: `.github/workflows/release-windows.yml:1-17`

- [ ] **Step 1: 替換檔頭觸發與 concurrency 區塊**

把目前的 1–13 行：

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
```

改為：

```yaml
name: release-windows
run-name: release ${{ inputs.tag }}

on:
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag (vX.Y.Z or vX.Y.Z-rc.N)'
        required: true
        type: string
      prerelease:
        description: 'Mark as pre-release'
        type: boolean
        default: false

permissions:
  contents: write

concurrency:
  group: release-${{ inputs.tag }}
  cancel-in-progress: false
```

- [ ] **Step 2: 移除 job 上的草稿條件**

把：

```yaml
  build-windows:
    if: github.event.release.draft == true
    runs-on: windows-latest
```

改為：

```yaml
  build-windows:
    runs-on: windows-latest
```

- [ ] **Step 3: 走讀驗證**

人工確認：`on:` 只剩 `workflow_dispatch`、兩個 input 縮排正確（`inputs:` → 各 input → 屬性）、job 不再有 `if:`、`concurrency.group` 用 `inputs.tag`。若有裝 `actionlint` 則跑 `actionlint .github/workflows/release-windows.yml` 預期無 error。

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release-windows.yml
git commit -m "ci(release): switch release-windows trigger to workflow_dispatch"
```

---

### Task 2: tag 來源、checkout/push 目標改 master，擷取 release commit SHA

**Files:**
- Modify: `.github/workflows/release-windows.yml`（checkout step 的 `ref`、Parse tag step 的 `$tag`、Commit pubspec bump step 的 push 目標；並在其後新增一個 step）

- [ ] **Step 1: checkout 改用 master**

把 checkout step 的 `with:`：

```yaml
        with:
          ref: ${{ github.event.release.target_commitish }}
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}
```

改為：

```yaml
        with:
          ref: master
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Parse tag 取用 input**

把 `Parse tag & rewrite pubspec` step 內的：

```pwsh
          $tag = "${{ github.event.release.tag_name }}"
```

改為：

```pwsh
          $tag = "${{ inputs.tag }}"
```

（同 step 其餘 regex 驗證、`buildNumber`、`pubspecVersion`、寫入 `GITHUB_ENV` 的邏輯**完全不動**。）

- [ ] **Step 3: Commit pubspec bump 推回 master**

把 `Commit pubspec bump` step 內的：

```pwsh
          git push origin HEAD:${{ github.event.release.target_commitish }}
```

改為：

```pwsh
          git push origin HEAD:master
```

- [ ] **Step 4: 新增「擷取 release commit SHA」step**

在 `Commit pubspec bump` step 之後、`Build Windows installer` step（`# === D. Build`）之前，插入：

```yaml
      - name: Capture release commit SHA
        shell: pwsh
        run: |
          $sha = (git rev-parse HEAD).Trim()
          "RELEASE_SHA=$sha" | Out-File $env:GITHUB_ENV -Append
          Write-Host "Release commit SHA: $sha"
```

> 此 step **無 `if:` 條件**，確保 `VERSION_CHANGED == 'false'`（pubspec 未變動、無新 commit）時 `RELEASE_SHA` 仍取到當下 master tip，避免後續 `--target` 為空。

- [ ] **Step 5: 走讀驗證**

人工確認：檔內已無任何 `github.event.release` 參照（可搜尋 `github.event.release` 應為 0 筆）；新 step 縮排與相鄰 step 對齊；`RELEASE_SHA` 寫入 `GITHUB_ENV` 語法與檔內其他 `Out-File $env:GITHUB_ENV -Append` 一致。

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release-windows.yml
git commit -m "ci(release): source tag from input, pin release to built commit SHA"
```

---

### Task 3: 冪等建草稿（取代原「Upload installer to release draft」）

**Files:**
- Modify: `.github/workflows/release-windows.yml`（`# === F. Upload to release draft` 區塊，原 114–121 行附近）

- [ ] **Step 1: 替換上傳 step 為「建草稿或更新資產」**

把：

```yaml
      # === F. Upload to release draft ===============================
      - name: Upload installer to release draft
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          $tag = "${{ github.event.release.tag_name }}"
          # 上傳檔名與 build 產物完全一致,不改名
          gh release upload "$tag" "${{ env.INSTALLER_PATH }}" --clobber
```

改為：

```yaml
      # === F. Create or update release draft ========================
      - name: Create or update release draft
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          $tag = "${{ inputs.tag }}"
          # 重跑情境:草稿已存在則只覆蓋上傳資產;否則建新草稿並釘在 build 的 commit
          gh release view "$tag" 2>$null
          if ($LASTEXITCODE -eq 0) {
            Write-Host "Draft '$tag' already exists; re-uploading installer with --clobber"
            gh release upload "$tag" "$env:INSTALLER_PATH" --clobber
          } else {
            Write-Host "Creating draft release '$tag' targeting $env:RELEASE_SHA"
            $createArgs = @("$tag", "$env:INSTALLER_PATH", "--draft", "--title", "$tag", "--generate-notes", "--target", "$env:RELEASE_SHA")
            if ("${{ inputs.prerelease }}" -eq "true") { $createArgs += "--prerelease" }
            gh release create @createArgs
          }
```

> `gh release view "$tag" 2>$null` 找不到 release 時會以非 0 退出，故用 `$LASTEXITCODE` 分流。`--generate-notes` 提供自動 changelog 底稿，Publish 前可手動編輯。

- [ ] **Step 2: 走讀驗證**

人工確認：`$env:INSTALLER_PATH` 在此前的 `Locate installer` step 已寫入 `GITHUB_ENV`、`$env:RELEASE_SHA` 在 Task 2 新 step 已寫入；`prerelease` 條件用字串比較 `"${{ inputs.prerelease }}" -eq "true"`；splatting `@createArgs` 語法正確。

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-windows.yml
git commit -m "ci(release): create draft release in CI idempotently with installer"
```

---

### Task 4: Step summary 改 tag 來源並標示草稿待發布

**Files:**
- Modify: `.github/workflows/release-windows.yml`（`# === H. Step summary` 區塊，原 134–149 行附近）

- [ ] **Step 1: 更新 step summary 內容**

把 `Write step summary` step 內 here-string：

```pwsh
          @"
          ## Release ${{ github.event.release.tag_name }}

          - **Pubspec version**: ${{ env.PUBSPEC_VERSION }}
          - **Installer**: ``${{ env.INSTALLER_NAME }}``
          - **Size**: $size MB
          - **SHA-256**: ``$sha``
          - **Uploaded to release**: ✓
          "@ | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
```

改為：

```pwsh
          @"
          ## Release ${{ inputs.tag }}

          - **Pubspec version**: ${{ env.PUBSPEC_VERSION }}
          - **Installer**: ``${{ env.INSTALLER_NAME }}``
          - **Size**: $size MB
          - **SHA-256**: ``$sha``
          - **Release commit**: ``${{ env.RELEASE_SHA }}``
          - **Draft created**: ✓ — review and Publish manually
          "@ | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
```

- [ ] **Step 2: 走讀驗證**

人工確認：here-string 結尾 `"@` 仍頂格、heading 用 `inputs.tag`、新增的 `RELEASE_SHA` 行 interpolation 正確。

- [ ] **Step 3: 全檔最終走讀**

通讀整份 `release-windows.yml`：搜尋 `github.event.release` 應 0 筆；`inputs.tag`、`inputs.prerelease`、`RELEASE_SHA`、`INSTALLER_PATH` 各參照前後一致。若有裝 `actionlint` 則跑一次預期無 error。

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release-windows.yml
git commit -m "ci(release): update step summary for draft workflow_dispatch flow"
```

---

### Task 5: 重寫 `docs/release.md` SOP

**Files:**
- Modify: `docs/release.md`（步驟區塊與失敗排查表）

- [ ] **Step 1: 重寫步驟 1（建 release 草稿 → 觸發 workflow）**

把目前的步驟 1：

```markdown
1. **建立 release 草稿**
   - GitHub repo → Releases → "Draft a new release"
   - **Tag name**：`vX.Y.Z`（必須符合 semver；不要帶 `+build` 部分；prerelease 寫 `vX.Y.Z-rc.N`）
   - **Target**：`master`
   - **☑ Set as a draft**（要發 prerelease 另外勾「Set as a pre-release」）
   - **Release notes**：自由填寫
   - 點 **"Save draft"**
```

改為：

```markdown
1. **觸發 release workflow**
   - GitHub repo → Actions → `release-windows` → **"Run workflow"**
   - **tag**：`vX.Y.Z`（必須符合 semver；不要帶 `+build` 部分；prerelease 寫 `vX.Y.Z-rc.N`）
   - **prerelease**：要發 prerelease 才勾選
   - 點 **"Run workflow"**（CI 固定以 `master` 為發版基準）
```

- [ ] **Step 2: 重寫步驟 3（確認 installer）**

把目前的步驟 3：

```markdown
3. **確認 installer 已附上**
   - 回到該 release 草稿頁面
   - Assets 區應該有 `Genshin_Impact_Wish_Gacha_Analyzer-Setup-X.Y.Z.exe`
   - Workflow run 的 step summary 會顯示 SHA-256 / size
```

改為：

```markdown
3. **確認 installer 已附上**
   - CI 成功後會自動建立一個 **草稿** release（標題 = tag），到該草稿頁面確認
   - Assets 區應該有 `Genshin_Impact_Wish_Gacha_Analyzer-Setup-X.Y.Z.exe`
   - Release notes 由 CI 自動產生底稿，Publish 前可自行編輯
   - Workflow run 的 step summary 會顯示 SHA-256 / size / release commit
```

- [ ] **Step 3: 更新失敗排查表（移除已修的 race 列、重跑改 Run workflow）**

把目前的失敗排查表：

```markdown
| 症狀 | 處理 |
|---|---|
| Workflow fail：tag 名不符 | 刪草稿、改 tag 名重建 |
| Workflow fail：build / ISCC 失敗 | 看 step log；修代碼 push 到 master 後刪草稿重建 |
| Workflow 成功但 release 沒 exe | 從 workflow run 下載 artifact (`windows-installer-X.Y.Z+N`)，手動拖到草稿 |
| Pubspec push race（你在 CI 期間 push 了新 commit） | 刪草稿、本地 rebase、重建草稿 |
```

改為：

```markdown
| 症狀 | 處理 |
|---|---|
| Workflow fail：tag 名不符 | 用正確 tag 重新 Run workflow（若已建草稿先刪草稿） |
| Workflow fail：build / ISCC 失敗 | 看 step log；修代碼 push 到 master 後重新 Run workflow |
| Workflow 成功但 release 沒 exe | 從 workflow run 下載 artifact (`windows-installer-X.Y.Z+N`)，手動拖到草稿 |
```

> 「Pubspec push race」列已隨「釘 SHA」修正移除：草稿 target 釘在 build 當下的 commit SHA，Publish 時 tag 必落在被 build 的 commit。

- [ ] **Step 4: 更新注意事項中的 race / 重建描述**

把注意事項中：

```markdown
- **Tag 不要重用**：刪了草稿不會刪 tag，但 GitHub 允許舊 tag 重綁 release。為避免混亂，刪草稿時順手刪 tag：`git push origin :refs/tags/vX.Y.Z`。
```

改為：

```markdown
- **草稿不會建立 tag**：草稿狀態下 GitHub 不建 git tag，刪草稿即可重來；只有按 Publish 才會把 tag 打在草稿釘住的 commit 上。
```

- [ ] **Step 5: 走讀驗證**

通讀 `docs/release.md`：確認全文不再出現「Save draft 觸發 CI」這類舊敘述、步驟順序連貫、失敗表與注意事項一致。

- [ ] **Step 6: Commit**

```bash
git add docs/release.md
git commit -m "docs(release): rewrite SOP for workflow_dispatch draft flow"
```

---

### Task 6: 最終整體驗證

**Files:**
- 無修改（驗證 only）

- [ ] **Step 1: 確認無 Dart 變更、品質 gate 不受影響**

```bash
git diff --name-only HEAD~5 HEAD
```
Expected: 只列出 `.github/workflows/release-windows.yml` 與 `docs/release.md`（無 `lib/` 或 `test/` 檔）。

- [ ] **Step 2: workflow 引用自洽最終檢查**

```bash
grep -n "github.event.release" .github/workflows/release-windows.yml
```
Expected: 無輸出（已全數移除）。

```bash
grep -n "inputs.tag\|inputs.prerelease\|RELEASE_SHA" .github/workflows/release-windows.yml
```
Expected: 列出 trigger、run-name、concurrency、Parse tag、Capture SHA、Create draft、step summary 等對應行。

- [ ] **Step 3: 標註 end-to-end 待驗**

提醒使用者：本變更的完整正確性需在**下次發版**實際以 `workflow_dispatch` 跑一次驗證（build / signing / 草稿建立 / 釘 SHA / Publish 後 tag 落點）。CI 無法本地模擬。

---

## Self-Review

**Spec coverage：**
- 觸發改 `workflow_dispatch` + inputs → Task 1 ✓
- tag 來源換 `inputs.tag`、checkout/push 寫死 master → Task 2 ✓
- prerelease 由 input 控制 → Task 3（建草稿條件）✓
- 冪等建草稿（view→upload/create）→ Task 3 ✓
- 釘 SHA 消 race（含 `VERSION_CHANGED=false` 邊界）→ Task 2 Step 4 ✓
- step summary 調整 → Task 4 ✓
- `docs/release.md` 重寫（步驟 1/3、失敗表）→ Task 5 ✓
- 驗證策略（actionlint 選用、grep 自洽、end-to-end 待發版）→ Task 6 ✓
- CI 訊息英文 → 新增 `Write-Host` 皆英文 ✓

**Placeholder scan：** 無 TBD/TODO；每個改動 step 皆含完整前後碼。

**Type/字串一致性：** `RELEASE_SHA`、`INSTALLER_PATH`、`INSTALLER_NAME`、`PUBSPEC_VERSION`、`inputs.tag`、`inputs.prerelease` 全檔命名前後一致；`gh release` 子命令（view/upload/create）與旗標拼寫一致。
