# GitHub Release Notes 連結 GitHub 化顯示

## 背景與問題

App 內的「更新內容」（`ReleaseNotesContent`，由 `NewVersionDialog` 與 `CurrentReleaseDialog` 共用）直接把 GitHub Releases API 回傳的 `body`（原始 Markdown）丟給 `markdown_widget` 渲染。GitHub 自家網頁會把 release notes 裡的裸網址自動轉成精簡顯示（PR 連結變 `#70`、compare 連結變 `v1.0.0...v1.1.0`、`@提及` 變使用者連結），但 `markdown_widget` 不會，於是 App 內顯示的是又長又雜的完整網址，閱讀體驗與 GitHub 不一致。

實際 release body 範例：

```text
* feat(hoyowiki): item icons … by @GoneTone in https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/pull/70
* chore(deps): bump … by @dependabot[bot] in https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/pull/75

**Full Changelog**: https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/compare/v1.0.0...v1.1.0
```

## 目標

在 App 內渲染 release notes 前，把本專案的 GitHub 連結改寫成與 GitHub 網頁一致的精簡顯示樣式。

| 來源 | 轉成 |
|---|---|
| `https://github.com/{owner}/{repo}/pull/70` | `[#70](url)` |
| `https://github.com/{owner}/{repo}/issues/123` | `[#123](url)` |
| `https://github.com/{owner}/{repo}/compare/v1.0.0...v1.1.0` | `[v1.0.0...v1.1.0](url)` |
| `https://github.com/{owner}/{repo}/commit/{40 碼 sha}` | `[{前 7 碼}](url)` |
| `@GoneTone` | `[@GoneTone](https://github.com/GoneTone)` |
| `@dependabot[bot]` | `[@dependabot[bot]](https://github.com/apps/dependabot)` |

`{owner}` / `{repo}` 取自 `AppRepo`（`GoneTone` / `genshin-impact-wish-gacha-analyzer`）。

## 非目標（YAGNI）

- **跨 repo 連結**：GitHub 會顯示成 `owner/repo#70`，但本專案 release notes 由自家 PR 自動產生，不會出現跨 repo 連結，故不處理。
- **非 GitHub 網址**：prose 裡的社群文章、Crowdin 等網址維持原樣，不在轉換範圍。
- **改動 `AppRelease.body` 來源資料**：轉換屬呈現層，model 仍忠實反映 API 原始內容。

## 架構

採「渲染前純函式轉換」：

- **新檔 `lib/utils/github_release_linkify.dart`**：匯出純函式 `linkifyGithubReferences(String body) → String`。無副作用、不依賴 Flutter，對齊 `lib/utils/` 既有慣例（`format_bytes.dart`、`uid_display.dart` 等）。
- **接點 `lib/widgets/dialogs/release_notes_content.dart`**：`MarkdownBlock(data: ...)` 改為 `data: linkifyGithubReferences(release.body)`。`NewVersionDialog` 與 `CurrentReleaseDialog` 共用此 widget，兩處自動生效。

資料流：`AppRelease.body`（原始）→ `linkifyGithubReferences`（呈現層轉換）→ `MarkdownBlock` 渲染。`AppRelease.body` 本身不變。

## 轉換邏輯細節

`linkifyGithubReferences` 依序套用數個 `RegExp` 替換。repo 前綴由 `AppRepo.githubUrl` 組成，host 中的 `.` 在 regex 內需跳脫（`github\.com`）。

1. **PR**：`{repoPrefix}/pull/(\d+)` → `[#$1]($0)`（`$0` 為整段匹配到的網址）。
2. **Issue**：`{repoPrefix}/issues/(\d+)` → `[#$1]($0)`。
3. **Compare**：`{repoPrefix}/compare/([^\s)]+)` → `[$1]($0)`（label 為捕捉到的比較區間，例 `v1.0.0...v1.1.0`；以空白或 `)` 為界）。
4. **Commit**：`{repoPrefix}/commit/([0-9a-fA-F]{7,40})` → `[{$1 前 7 碼}]($0)`。
5. **@提及**（全域，不限 repo，最後套用）：
   - pattern 形如 `@(username)(\[bot\])?`，username 採 GitHub 規則：`[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?`。
   - 帶 `[bot]` 後綴 → `[@{name}[bot]](https://github.com/apps/{name})`；否則 → `[@{name}](https://github.com/{name})`。
   - 以 negative lookbehind 擋掉 email／路徑樣式：`@` 前若緊鄰 `[A-Za-z0-9._%+@/-]` 則不視為提及。

**防重複包裝**：所有「網址型」替換（PR/Issue/compare/commit）在匹配網址前加 negative lookbehind `(?<![(<])`，避免改寫已是 `[文字](url)` 或 `<url>` 形式的網址，防止產生 `[[..](..)](..)`。

**套用順序**：先網址型（1～4，彼此 path 不重疊、順序不敏感），@提及（5）最後，避免互相干擾。

## 錯誤處理

純字串轉換，無 I/O、無外部呼叫，不引入新的錯誤分支。`body` 為空字串時各 regex 無匹配、原樣回傳（`ReleaseNotesContent` 既有的 `release.body.isNotEmpty` 判斷仍在轉換前先擋空 body，行為不變）。本變更不需新增 logger。

## 測試

新增 `test/utils/github_release_linkify_test.dart`，涵蓋：

- PR 連結 → `#70`
- Issue 連結 → `#123`
- compare 連結 → `v1.0.0...v1.1.0`
- commit 連結（40 碼）→ 前 7 碼短 SHA
- `@GoneTone` → 使用者連結
- `@dependabot[bot]` → app 連結，保留 `[bot]` 顯示
- 非 GitHub 網址（如社群文章、Crowdin）維持原樣
- 已是 `[文字](url)` / `<url>` 的 GitHub 網址不再被包一層
- email 樣式（`foo@bar.com`）不被誤判為提及
- 同一行多個可轉換目標皆正確轉換（取自真實 release body 片段）

## 驗收條件

- `dart format lib/ test/`、`flutter analyze`（`No issues found!`）、`flutter test`（`All tests passed!`）全綠。
- 新增的單元測試全部通過。
