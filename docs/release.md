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
