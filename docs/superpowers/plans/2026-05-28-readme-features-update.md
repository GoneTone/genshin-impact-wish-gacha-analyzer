# README Features 區塊更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在三份 README(繁中、简中、英文)的「功能與特色 / Features」清單各新增同一組 3 個 bullet:5★ / 4★ 平均出貨抽數、HoYoWiki 整合、介面 UID 遮罩。

**Architecture:** 純文字 insert,3 檔 × 3 bullet = 9 處 Edit。所有插入都落在既有「功能與特色 / Features」bullet 清單內,不動其他區塊。改完統整成一個 commit。

**Tech Stack:** Markdown only。無程式碼、無單元測試;驗收以 `git diff` 視覺檢查為主。

**標點規則:** 繁/簡中文新 bullet 必須用**全形標點**(`(` `)` `:` `;` `,` 等),與既有 README 慣例一致。英文新 bullet 用半形標點。

**Spec:** `docs/superpowers/specs/2026-05-28-readme-features-update-design.md`

---

### Task 1: 更新 `README.md`(繁體中文)

**Files:**
- Modify: `README.md`(三處插入,line 47 / 52 / 56 附近)

- [ ] **Step 1: 確認當前內容**

讀取 `README.md` line 39–60 區段(「功能與特色」清單),確認以下三行存在且字串完全一致:
- line 47: `- 5★ 與 4★ 雙保底進度條,並顯示距離保底剩餘抽數`(其中「,」為全形)
- line 52: `- 歷史記錄表格:多欄排序、模糊搜尋、稀有度與物品類型篩選、分頁`(其中「:」為全形)
- line 56: `- 多國語言([協助翻譯](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))`(其中「(」「)」為全形)

若有任一行不符,先停下回報——表示 README 已被別人改過,需重新比對 spec。

- [ ] **Step 2: 插入「平均出貨抽數」bullet(位置 1)**

Edit `README.md`:
- old_string:
  ```
  - 5★ 與 4★ 雙保底進度條,並顯示距離保底剩餘抽數
  ```
- new_string:
  ```
  - 5★ 與 4★ 雙保底進度條,並顯示距離保底剩餘抽數
  - 5★ / 4★ 平均出貨抽數統計(各卡池與整體)
  ```

注意新 bullet 內的「(」「)」必須是全形(`U+FF08` `U+FF09`)。

- [ ] **Step 3: 插入「HoYoWiki 整合」bullet(位置 2)**

Edit `README.md`:
- old_string:
  ```
  - 歷史記錄表格:多欄排序、模糊搜尋、稀有度與物品類型篩選、分頁
  ```
- new_string:
  ```
  - 歷史記錄表格:多欄排序、模糊搜尋、稀有度與物品類型篩選、分頁
  - 自動補上角色 / 武器的圖示與資料(來源:HoYoWiki):表格與時間軸都附圖示;點擊物品可查看官方插圖、描述與標籤,並一鍵跳轉 HoYoWiki
  ```

注意新 bullet 內全部全形標點:`(` `)` 兩處、`:` 兩處(「來源」後與「HoYoWiki)」後)、`;` 一處、`,` 一處。半形空格 + 半形 `/` 維持(對齊既有 bullet 慣例)。

- [ ] **Step 4: 插入「介面 UID 遮罩」bullet(位置 3)**

Edit `README.md`:
- old_string:
  ```
  - 多國語言([協助翻譯](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))
  ```
- new_string:
  ```
  - 多國語言([協助翻譯](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))
  - 可在設定開啟介面 UID 遮罩(只顯示前三碼),保護隱私
  ```

注意新 bullet 內「(」「)」「,」皆為全形。

- [ ] **Step 5: 視覺驗證 diff**

執行:
```powershell
git diff README.md
```

預期輸出:**剛好 3 個新增行**,內容如上述三個 new_string 的新增 bullet,沒有刪除行、沒有其他修改。若 diff 不只 3 行新增,回頭檢查 Step 2–4 的 old/new string。

---

### Task 2: 更新 `README_ZH-HANS.md`(简体中文)

**Files:**
- Modify: `README_ZH-HANS.md`(三處插入,line 47 / 52 / 56 附近)

- [ ] **Step 1: 確認當前內容**

讀取 `README_ZH-HANS.md` line 39–60 區段,確認以下三行存在:
- line 47: `- 5★ 与 4★ 双保底进度条,并显示距离保底的剩余抽数`(「,」全形)
- line 52: `- 历史记录表格:多列排序、模糊搜索、稀有度与物品类型筛选、分页`(「:」全形)
- line 56: `- 多国语言([协助翻译](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))`(「(」「)」全形)

- [ ] **Step 2: 插入「平均出货抽数」bullet(位置 1)**

Edit `README_ZH-HANS.md`:
- old_string:
  ```
  - 5★ 与 4★ 双保底进度条,并显示距离保底的剩余抽数
  ```
- new_string:
  ```
  - 5★ 与 4★ 双保底进度条,并显示距离保底的剩余抽数
  - 5★ / 4★ 平均出货抽数统计(各卡池与整体)
  ```

- [ ] **Step 3: 插入「HoYoWiki 整合」bullet(位置 2)**

Edit `README_ZH-HANS.md`:
- old_string:
  ```
  - 历史记录表格:多列排序、模糊搜索、稀有度与物品类型筛选、分页
  ```
- new_string:
  ```
  - 历史记录表格:多列排序、模糊搜索、稀有度与物品类型筛选、分页
  - 自动补上角色 / 武器的图标与资料(来源:HoYoWiki):表格与时间轴都附图标;点击物品可查看官方插画、描述与标签,并一键跳转 HoYoWiki
  ```

注意:简中用「图标」(对应繁中「圖示」)、「插画」(对应繁中「插圖」)、「标签」(对应繁中「標籤」)。所有 `(` `)` `:` `;` `,` 均为全形。

- [ ] **Step 4: 插入「界面 UID 遮罩」bullet(位置 3)**

Edit `README_ZH-HANS.md`:
- old_string:
  ```
  - 多国语言([协助翻译](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))
  ```
- new_string:
  ```
  - 多国语言([协助翻译](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))
  - 可在设置开启界面 UID 遮罩(只显示前三码),保护隐私
  ```

注意:简中用「设置」(对应繁中「設定」)、「界面」(对应繁中「介面」)、「码」(对应繁中「碼」)。

- [ ] **Step 5: 視覺驗證 diff**

執行:
```powershell
git diff README_ZH-HANS.md
```

預期輸出:剛好 3 個新增行。

---

### Task 3: 更新 `README_EN.md`(English)

**Files:**
- Modify: `README_EN.md`(三處插入,line 47 / 52 / 56 附近)

- [ ] **Step 1: 確認當前內容**

讀取 `README_EN.md` line 39–60 區段,確認以下三行存在:
- line 47: `- Dual pity progress (5★ and 4★) showing remaining pulls until pity`
- line 52: `- Wish history table: multi-column sort, fuzzy search, rarity and item-type filters, pagination`
- line 56: `- Multi-language ([help us translate](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))`

英文版全程半形標點。

- [ ] **Step 2: 插入 “Average pulls” bullet(Position 1)**

Edit `README_EN.md`:
- old_string:
  ```
  - Dual pity progress (5★ and 4★) showing remaining pulls until pity
  ```
- new_string:
  ```
  - Dual pity progress (5★ and 4★) showing remaining pulls until pity
  - Average pulls per 5★ / 4★ hit (per-banner and overall)
  ```

- [ ] **Step 3: 插入 “HoYoWiki integration” bullet(Position 2)**

Edit `README_EN.md`:
- old_string:
  ```
  - Wish history table: multi-column sort, fuzzy search, rarity and item-type filters, pagination
  ```
- new_string:
  ```
  - Wish history table: multi-column sort, fuzzy search, rarity and item-type filters, pagination
  - Auto-fetched character / weapon icons and details (from HoYoWiki): shown in the history table and timelines; click an item to view official artwork, description, and tags — with a one-click jump to HoYoWiki
  ```

注意 `—`(em-dash,`U+2014`),與既有 bullet 行 41、58 用法一致。

- [ ] **Step 4: 插入 “UID masking” bullet(Position 3)**

Edit `README_EN.md`:
- old_string:
  ```
  - Multi-language ([help us translate](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))
  ```
- new_string:
  ```
  - Multi-language ([help us translate](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))
  - Optional UID masking in the UI (first 3 digits only) for added privacy
  ```

- [ ] **Step 5: 視覺驗證 diff**

執行:
```powershell
git diff README_EN.md
```

預期輸出:剛好 3 個新增行。

---

### Task 4: 整體驗證 + Commit

**Files:**
- 只 stage 三份 README,不動其他檔案

- [ ] **Step 1: 全局 diff 檢查**

執行:
```powershell
git diff --stat
```

預期輸出:**只有三份 README 出現在 stat,每份 +3 −0**,沒有其他檔案被改:
```
 README.md          | 3 +++
 README_EN.md       | 3 +++
 README_ZH-HANS.md  | 3 +++
 3 files changed, 9 insertions(+)
```

若有額外檔案被改到(例如誤觸 spec、誤觸 lib/),先 `git restore --` 還原,再回到對應 Task 重做。

- [ ] **Step 2: 對齊三檔的新 bullet 位置**

執行:
```powershell
git diff README.md README_EN.md README_ZH-HANS.md
```

肉眼確認:
1. 每份 README 的「平均出貨抽數」bullet 都緊接在雙保底進度條 bullet 之後
2. 每份的「HoYoWiki」bullet 都緊接在「歷史記錄表格」bullet 之後
3. 每份的「UID 遮罩」bullet 都緊接在「多國語言」bullet 之後

- [ ] **Step 3: 全形/半形標點抽檢**

執行 PowerShell 抽 codepoint(memory 提醒過全形標點靠肉眼會被陰):
```powershell
$line = (Get-Content README.md)[47..49]
$line | ForEach-Object { $_; ($_.ToCharArray() | ForEach-Object { '{0} U+{1:X4}' -f $_, [int][char]$_ }) -join ' ' }
```

預期:line 48(新插入「平均出貨抽數」bullet)的「(」「)」codepoint 顯示為 `U+FF08` / `U+FF09`(全形),若顯示 `U+0028` / `U+0029`(半形)就是錯的,回 Task 1 Step 2 修正。

對 `README_ZH-HANS.md` 重複同樣 codepoint 抽檢(同樣抽新插入的「平均出货抽数」bullet)。

- [ ] **Step 4: Commit**

執行(分別 `git add` 三檔以避免誤觸):
```powershell
git add README.md README_EN.md README_ZH-HANS.md
```

```powershell
git commit -m @'
docs(readme): add 3 new features to Features section

Add bullets for 5★/4★ average pulls per hit, HoYoWiki item icon
and detail integration, and the optional UI UID mask privacy
setting. Applied to all 3 README files (zh-Hant, zh-Hans, en).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

- [ ] **Step 5: 驗證 commit 已建立**

執行:
```powershell
git log -1 --stat
```

預期:最新 commit 有 3 files changed, 9 insertions(+)。

---

## 不做的事(YAGNI 提醒)

- 不重排既有 bullet 順序
- 不修「分享圖」既有 bullet 的 UID 遮罩描述(那是分享圖獨立行為,與本次新增的「介面 UID 遮罩」是不同功能)
- 不加 sub-heading
- 不動 README 其他區塊(介紹、下載、使用方式、截圖、開發等)
- 不執行 `dart format`、`flutter analyze`、`flutter test`(本次只動 README,與 Dart/Rust 無關)
- 不 `git push`
