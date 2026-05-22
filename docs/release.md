# Release SOP

如何發 Genshin Impact Wish Gacha Analyzer 新版本（Windows installer）。

## 前置條件

- `master` 已是要發版的 commit
- Tag 名遵循 semver：`vX.Y.Z` 或 `vX.Y.Z-rc.N`
- 你有 repo 的 release 建立權限

## 步驟

1. **觸發 release workflow**
   - GitHub repo → Actions → `release-windows` → **"Run workflow"**
   - **tag**：`vX.Y.Z`（必須符合 semver；不要帶 `+build` 部分；prerelease 寫 `vX.Y.Z-rc.N`）
   - **prerelease**：要發 prerelease 才勾選
   - 點 **"Run workflow"**（CI 固定以 `master` 為發版基準）

2. **等 CI 跑完**
   - 觸發 workflow：`release-windows`
   - Actions 頁面看 run 結果（run name = release tag）

3. **確認 installer 已附上**
   - CI 成功後會自動建立一個 **草稿** release（標題 = tag），到該草稿頁面確認
   - Assets 區應該有 `Genshin_Impact_Wish_Gacha_Analyzer-Setup-X.Y.Z.exe`
   - Release notes = 自動產生的 What's Changed ＋ 固定附帶的翻譯邀請／防毒說明（維護於 `.github/release-footer.md`），Publish 前可自行編輯
   - Workflow run 的 step summary 會顯示 SHA-256 / size / release commit

4. **Publish**
   - 草稿頁面點 **"Publish release"**
   - GitHub 把 tag 打在 master 當下 tip（含 CI push 的 pubspec bump commit）

## 失敗排查

| 症狀 | 處理 |
|---|---|
| Workflow fail：tag 名不符 | 用正確 tag 重新 Run workflow（若已建草稿先刪草稿） |
| Workflow fail：build / ISCC 失敗 | 看 step log；修代碼 push 到 master 後重新 Run workflow |
| Workflow 成功但 release 沒 exe | 從 workflow run 下載 artifact (`windows-installer-X.Y.Z+N`)，手動拖到草稿 |

## 注意事項

- **每次發版 CI 會自動 push 一個 pubspec bump commit 到 master**，commit author 顯示為 `github-actions[bot]`。
- **發版前不要手動改 pubspec version**——讓 CI 改，避免雙方衝突。
- **草稿不會建立 tag**：草稿狀態下 GitHub 不建 git tag，刪草稿即可重來；只有按 Publish 才會把 tag 打在草稿釘住的 commit 上。
- **發版固定以 master 為基準**：workflow 寫死 `ref: master` 並把 pubspec bump push 回 master，無法從其他 branch 發版；發版前確認 master tip 就是要發的 commit。
- **升 Flutter 版本走 PR 改 `.fvmrc`**：CI 與本地會同步切換。
