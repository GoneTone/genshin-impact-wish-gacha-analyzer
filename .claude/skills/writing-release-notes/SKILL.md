---
name: writing-release-notes
description: Use when drafting GitHub release notes or changelog content for this project (Genshin Impact Wish Gacha Analyzer). Triggers when the user asks to write release content for a new version, summarize a tag-to-tag diff (e.g. "v1.0.0...v1.1.0"), or produce "更新內容 / 版本說明 / release note". Produces bilingual (zh-Hant on top, en on bottom) Discord-style prose for headline features with a short bullet list for minor items — NOT a corporate-style changelog with one section header per category.
---

# Writing Release Notes (this project)

## 風格摘要

**雙語輸出**：繁體中文在上、英文在下，內容對齊（同樣的 hero 段落數、同樣的 bullet 數、同樣的 emoji 位置）。兩個 H2 直接相鄰，**不加 `---` 水平線**。

每一語言內部：單一 `## 此版本重點` / `## What's New` 標題開場，前段用 1–3 段**散文**敘述主打功能，最後接一段「除此之外，我們還做了：」/「On top of that, we also did:」+ 條列次要項。整體語氣像 Discord 公告，不是 SaaS changelog。

## 為什麼這樣寫

- **重點功能用散文**：可以一邊介紹一邊埋槽點、把使用情境帶出來，讀者比較記得住
- **次要項用 bullet**：本來就不需要鋪陳，硬寫散文反而拖
- **不切 H2/H3 per feature**：分節會讓 release note 看起來像產品手冊，喪失「聊天感」

## 結構（必照）

整份輸出順序（兩個 H2 直接相鄰，**不加 `---`**）：

```
## 此版本重點
（繁中 hero 散文）
（繁中 bullet 區）

## What's New
（英文 hero 散文）
（英文 bullet 區）
```

每一語言內部：

1. **ONE H2**：繁中用 `## 此版本重點`、英文用 `## What's New`（不要再切子標題；散文段落自帶轉場）
2. **Hero 散文**（1–3 段，每段一個主題群）
   - 開頭 hook：rhetorical 問題、callback 舊體驗、痛點吐槽——讓讀者一秒進入情境
   - 一段內可以串多個相關功能（例：隱私 UID 遮罩 + 移除使用者資料 → 同段「隱私 / 資料清理」）
   - 第二人稱直接對讀者：繁中「你的 / 點下去 / 終於不用」；英文 "your / click / no more"
   - emoji 偶爾用，每段 1–2 個，挑自然停頓處（句末或破折號前後）；**中英文 emoji 位置要對齊**
3. **過場句 + bullet 區**
   - 繁中過場：「除此之外，我們還做了：」
   - 英文過場："On top of that, we also did:"
   - 每條：`主題：細節（可加調皮註解）` / `Topic: detail (with a cheeky aside if it fits)`
   - **中英文 bullet 條數與順序要一一對應**

## 取得素材

```bash
git log <prev-tag>..HEAD --oneline                                    # 看所有 commit
git log <prev-tag>..HEAD --merges --pretty=format:"%h %s"             # PR 標題（高層脈絡）
git diff <prev-tag>..HEAD -- README.md README_EN.md                   # 確認對外講法
git diff <prev-tag>..HEAD --stat | tail -30                           # 大致變動規模
```

從 PR 標題挑 2–3 個 hero，其餘進 bullet。**Crowdin / Dependabot / 機械 refactor 永遠進 bullet 區或省略。**

## Gold Standard：v1.1.0（使用者親自校稿後的版本）

```markdown
## 此版本重點

還記得以前打開歷史記錄表格，滿滿一片只有名字嗎？這次更新後你的「刻晴」終於不只是兩個字——HoYoWiki 整合正式登場，表格、時間軸、分享圖通通長出角色與武器的臉。手癢點下去還有官方立繪、圖庫、描述跟標籤，滑鼠滾輪縮放、雙擊放大、ESC 關掉，一秒切換到 HoYoWiki 看更多，整個分析器瞬間從 Excel 升級成圖鑑 📖

實況主跟截圖黨福音來了：介面 UID 遮罩 🕶️。設定點一下，UID 就只剩前三碼，再也不怕直播時被認親。如果哪天想換電腦重灌，解除安裝程式會貼心問你「要不要連同抽卡記錄、設定、快取一起清掉？」🧹 終於不用自己去翻 AppData 手動刪資料夾了

除此之外，我們還做了：
- 稀有度配色重整：5★ 提亮、新增 1★ 自己的顏色
- 設定頁新增「圖片快取」區塊：看用量、一鍵清圖庫
- 圖片懶載入，不打開詳情就不下載（你的硬碟感謝你）
- 兩輪 Crowdin 翻譯更新：泰 / 越 / 葡（巴） / 烏 / 韓 / 日 / 西 / 法 等
- GitHub Actions Dependabot 上線自動追依賴
- 新增一篇社群介紹文 → 原神資訊站 Genshin Impact Info (https://genshininfo.reh.tw/archives/97)

## What's New

Remember opening the history table and seeing nothing but a wall of names? After this update, your "Keqing" is finally more than two characters of text — HoYoWiki integration is officially here, and your tables, timelines, and share images all grew character and weapon portraits. Click any item and you get the official artwork, gallery, description, and tags; mouse-wheel zoom, double-tap to scale, ESC to close, and a one-click jump to HoYoWiki for more. The analyzer just leveled up from Excel to a full illustrated compendium 📖

Good news for streamers and screenshot folks: UI UID masking 🕶️. One toggle in Settings and your UID is clipped to just the first three digits — no more worrying about being identified mid-stream. And if you ever swap machines or reinstall, the uninstaller now politely asks "want to clear your gacha records, settings, and cache while we're at it?" 🧹 No more digging through AppData by hand.

On top of that, we also did:
- Refreshed rarity colors: brighter 5★ tones, and 1★ finally has its own color
- New "Image Cache" section in Settings: see usage, clear the gallery with one click
- Lazy-loaded gallery: nothing downloads until you open the details (your disk thanks you)
- Two rounds of Crowdin translation updates: Thai / Vietnamese / pt-BR / Ukrainian / Korean / Japanese / Spanish / French, and more
- GitHub Actions Dependabot is now tracking dependencies automatically
- New community write-up → 原神資訊站 Genshin Impact Info (https://genshininfo.reh.tw/archives/97)
```

**注意這份範例做對的事**：
- 中英文 hero 段落數相同（兩段）、bullet 條數相同（六條）、emoji 位置對齊（📖 / 🕶️ / 🧹）
- 開場 hook：「還記得以前⋯⋯滿滿一片只有名字嗎？」/ "Remember opening the history table⋯"
- 把多個 HoYoWiki 子功能（圖示、詳情、縮放、外連）壓在同一段內
- 把「隱私遮罩」和「解除安裝詢問」綁在同段——情境上相關（資料管理 / 安心感）
- 沒有 `## 主打 / ## 體驗 / ## 底層` 之類分節
- 沒有預設塞「完整 diff」連結或防毒 disclaimer——讓使用者自己決定
- 兩個 H2 直接相鄰，**沒有** `---` 分隔線
- 第三方站名「原神資訊站 Genshin Impact Info」用「原文 英譯」雙語並列，中英版本字串相同（不要在英文版只留 "Genshin Info Site"）

## 重點群組範例

當有多個小功能時，看怎麼把它們合進同一段：

| 主題群 | 包含的功能 |
|--------|-----------|
| 視覺化升級 | HoYoWiki 表格圖示、物品詳情 dialog、圖庫縮放 |
| 隱私 / 資料清理 | UID 遮罩、解除安裝詢問刪資料 |
| 底層變快 | 平行 worker pool、自動補資料 |
| 純功能新增 | 平均出貨抽數統計（通常單獨一段就好） |

## Common Mistakes

| ❌ 不要 | ✅ 應該 |
|--------|--------|
| 只輸出單一語言 | 永遠中英雙語，繁中在上、英文在下，兩個 H2 直接相鄰（不加 `---`） |
| 在中英之間加 `---` 水平線 | 兩個 H2 直接相鄰即可 |
| 中英文段落數 / bullet 條數不一致 | 一一對應，emoji 位置也對齊 |
| 英文版把中文站名翻成英譯（如「原神資訊站」→ "Genshin Info Site"）只留英譯 | 第三方站名 / 來源用「原文 英譯」雙語並列，中英版本字串相同（如「原神資訊站 Genshin Impact Info」） |
| 整篇都是 bullet | 主打用散文，次要才 bullet |
| `### HoYoWiki 整合` / `## 主打功能` 分節 | 散文段落自帶轉場，不切標題 |
| 「本次更新包含⋯」「主要新增功能：」開場 | hook 開場（問句、痛點、callback） |
| 列每一條 commit | 只挑使用者會在意的 |
| Emoji 灑滿每行 | 每段 1–2 個，挑自然停頓處 |
| ✨ 主打 / ⚡ 底層 / 🎨 體驗 三段式 | 一段散文走完所有重點 |
| 預設加「完整 diff」連結與防毒 disclaimer | 讓使用者自己決定要不要 |
| 第三人稱客套（「使用者可以⋯」） | 第二人稱直接對讀者（「你⋯」） |
| 把 Crowdin / Dependabot / refactor 拉到 hero | 永遠進 bullet 區 |
| 英文版逐字直譯成生硬中式英文 | 重寫成自然英文，保留同樣的調皮節奏與 hook |

## 語言與標點

**繁中區**
- 繁體中文 (台灣)
- 全形標點 ，。！？；：（）「」『』、
- 散文內可用破折號 `——` 作節奏停頓
- 程式碼 / identifier 維持半形

**英文區**
- 半形標點 . , ! ? ; : ( ) " "
- 散文內可用 em dash ` — ` 作節奏停頓（用空格包圍）
- 自然口語英文，不要把中文逐字直譯
- 雙引號用直引號 `"`，不要用花引號 `"` `"`（GitHub markdown 顯示一致性）

## 草稿流程

1. `git log <prev-tag>..HEAD --merges` 抓 PR 標題、`git log --oneline` 看細部
2. 挑 2–3 個 hero（**合併相關的**），其餘進 bullet
3. **先寫繁中版**：把「故事」用散文寫清楚，再雕 emoji 和段落節奏
4. **再寫英文版**：對齊段落結構、bullet 條數、emoji 位置；用自然英文重寫，不逐字直譯
5. 兩個 H2 直接相鄰，**不要加 `---`**
6. 給使用者過稿
7. 若使用者改稿後風格有調整 → **回來更新這個技能的 Gold Standard 段落**（中英都要更新），下次才不會走回頭路

## 紅旗自檢

寫完前自問：
- [ ] 中英文都寫了？繁中在上、英文在下？兩個 H2 直接相鄰（**沒有** `---`）？
- [ ] 中英文段落數、bullet 條數一致？emoji 位置對齊？
- [ ] 中文站名 / 來源在英文版有保留「原文 英譯」雙語並列，不是只翻成英文？
- [ ] 各語言內是不是只有一個 H2（`## 此版本重點` / `## What's New`）？沒有別的標題？
- [ ] 主打功能是不是散文？沒被我寫成 bullet？
- [ ] 有沒有第二人稱直接對讀者？
- [ ] 是不是不小心又灑了「✨ ⚡ 🎨」三段式分節？
- [ ] Crowdin / Dependabot / 機械 refactor 有沒有乖乖待在 bullet 區？
- [ ] 英文版讀起來是自然英文，不是中式直譯？
