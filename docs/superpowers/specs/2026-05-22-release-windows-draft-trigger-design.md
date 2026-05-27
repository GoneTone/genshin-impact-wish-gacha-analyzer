# release-windows workflow 觸發重設 — Design

日期：2026-05-22

## 問題

`docs/release.md` 的發版 SOP（UI 建草稿 → 等 CI 自動 build 並把 installer 附到草稿 → 人工檢查 → 手動 Publish）**從機制上跑不起來**：

- `.github/workflows/release-windows.yml` 觸發條件為 `on: release: types: [created]`，job 又加 `if: github.event.release.draft == true`。
- 但 GitHub Actions 官方明定：**草稿 release 的 `created` / `edited` / `deleted` 活動類型一律不觸發 workflow**（來源：GitHub Actions「Events that trigger workflows」release 段）。

因此只要 release 還是草稿，這個 workflow 永遠不會被觸發——這就是「儲存草稿後沒執行」的根因。`release` 事件唯一會發的時機是草稿轉成已發布（`published` / `released` / `prereleased`），但那時已不是草稿，牴觸「公開前先人工檢查」這條紅線。

GitHub Actions 內**不存在**任何 `types:` 組合能在「草稿狀態」下觸發。唯一旁門（webhook → 外部 endpoint → `repository_dispatch`）需長期維運外部服務，對本專案是過度設計，不採用。

## 決策

- **紅線**：保留「公開前的人工檢查關卡」——CI 必須在 release 尚未公開時就 build 好 installer 並附上草稿，公開動作由人手動按。
- **方向**：改用 `workflow_dispatch` 手動觸發。手感最接近現狀（最後一樣得到附好 installer 的草稿、人工檢查、手動 Publish），只是觸發鈕從 release 頁「Save draft」換成 Actions 頁「Run workflow」。版號注入、草稿不建 tag、Publish 才打 tag 等既有機制全數保留。
- **順手修 race**：納入「釘 SHA」改動，消滅既有 race。

## 設計

### 1. 觸發與輸入

```yaml
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
```

- `run-name` → `release ${{ inputs.tag }}`。
- 移除 job 上的 `if: github.event.release.draft == true`（已無 release context）。
- `concurrency.group` → `release-${{ inputs.tag }}`，`cancel-in-progress: false` 不變。

### 2. Steps 調整（其餘維持原樣）

- **tag 來源**：所有 `github.event.release.tag_name` → `inputs.tag`；semver regex 驗證不變。
- **checkout / push 目標**：原 `github.event.release.target_commitish` → 寫死 `master`（強制 SOP「只在 master 發版」，更安全）。
- **prerelease**：原本靠 UI 勾選帶進草稿；改由 `inputs.prerelease` 控制（建草稿時加 `--prerelease`）。
- **建草稿（取代原「Upload installer to release draft」step）**：CI 自行建草稿，設計成**冪等**以支援失敗後重跑：

  ```pwsh
  gh release view "$tag" 2>$null
  if ($LASTEXITCODE -eq 0) {
    # 草稿已存在(重跑情境):只覆蓋上傳資產
    gh release upload "$tag" "$env:INSTALLER_PATH" --clobber
  } else {
    $createArgs = @("$tag", "$env:INSTALLER_PATH", "--draft", "--title", "$tag", "--generate-notes", "--target", "$env:RELEASE_SHA")
    if ("${{ inputs.prerelease }}" -eq "true") { $createArgs += "--prerelease" }
    gh release create @createArgs
  }
  ```

  `--generate-notes` 提供自動 changelog 底稿，Publish 前可編輯（取代原「在 UI 表單先手寫 notes」）。

### 3. 釘 SHA 消滅既有 race

`docs/release.md` 失敗表的「Pubspec push race」根因：草稿 `target_commitish` 存 branch 名 `master`，Publish 時才解析成當下 tip，若 CI 期間有新 commit 就錯位。

修法：bump commit push 完當場 `git rev-parse HEAD` 取確切 SHA，寫入 `RELEASE_SHA` 環境變數，建草稿時用 `--target $env:RELEASE_SHA` 釘在剛 build 的 commit。Publish 時 tag 一定落在被 build 的那顆 commit → 該 race 消除。

> 注意：`VERSION_CHANGED == 'false'`（pubspec 未變動、未產生新 commit）時，`RELEASE_SHA` 應取當下 checkout 的 master tip（即 `git rev-parse HEAD`），仍要設定，避免 `--target` 為空。

### 4. 文件同步（`docs/release.md`）

- 步驟 1：「UI 建草稿」→「Actions → `release-windows` → Run workflow，輸入 tag、勾選是否 prerelease」。
- 步驟 3：「回草稿頁確認 installer」改為「到 CI 自動建好的草稿頁確認 installer 已附上」。
- 步驟 4 Publish：不變。
- 失敗排查表：移除「Pubspec push race」列（已修）；「重建草稿」相關改為「Run workflow 重跑」；tag 清理註記沿用（草稿仍不建 tag）。

### 5. 驗證

- YAML：`actionlint`（若可用）或人工 syntax 走讀。
- PowerShell 片段：邏輯走讀（冪等分支、prerelease 條件、SHA 取值）。
- end-to-end：CI 無法本地完整模擬 signing/build，需下次發版時實際跑一次 `workflow_dispatch` 驗證。
- CI 訊息一律英文（沿用既有慣例）。

## 範圍外（YAGNI）

- 不加 target branch 輸入（SOP 規定只在 master 發版，寫死即可）。
- 不自架 webhook relay 還原「草稿儲存觸發」UX。
- 不改 build / signing / artifact 上傳邏輯。
