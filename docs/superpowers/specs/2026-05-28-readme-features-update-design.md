# README 功能與特色區塊更新 Design

## 背景

三份 README(`README.md` 繁體中文、`README_ZH-HANS.md` 简体中文、`README_EN.md` English)的「功能與特色 / Features」清單最後一次大改是 commit `79a5df0`(`docs(readme): rewrite Features section against actual implementation`),之後僅 `dcdfc79` 補了「分享圖」一項。

自上次大改以來,應用程式新增了多項使用者可感知的功能,目前清單已落後實作。需要把幾個明顯遺漏的功能補進去。

## 目標

- 在三份 README 的「功能與特色 / Features」清單分別新增 3 個 bullet。
- 三份內容對齊:每個語系的清單都新增同一組 3 項,順序與插入位置一致。
- 三項分別覆蓋:
    1. 5★ / 4★ 平均出貨抽數統計
    2. HoYoWiki 整合(物品圖示、詳情 dialog、跳轉外部連結)
    3. 設定可開啟介面 UID 遮罩(Privacy)

## 非目標

- 不重新排列原有清單既有項目。
- 不加 sub-heading / 分群。
- 不重寫已存在的「分享圖」UID 遮罩描述(概念相關但行為不同,各自獨立)。
- 不動「介紹」、「多國語言」、「下載軟體」、「使用方式」、「截圖」、「開發」等其他區塊。
- 不補 B 組(匯出/匯入全部帳號、多帳號管理別名等)與 C 組(視窗位置記憶、檔案總管開啟、新版本 markdown changelog 等)的細節。

## 範圍

| 檔案 | 改動 |
|---|---|
| `README.md`(繁體中文) | 「功能與特色」新增 3 項 |
| `README_ZH-HANS.md`(简体中文) | 「功能与特色」新增 3 項 |
| `README_EN.md`(English) | “Features” 新增 3 項 |

## 設計決策

### 1. 採「插在主題相鄰處」而非「統一附加到清單尾端」

3 個新項目各自插入到最相關的既有項目旁,讓讀者掃讀時的脈絡較順。差距是 diff 會動 3 個位置,而不是 1 個段落,但 3 份 README 都對齊得到。

### 2. 文案維持「單行 bullet、不開二級結構」

既有清單就是平鋪 bullet 清單(18 項),新增 3 項一樣以單行 bullet 寫,不加 sub-heading,避免破壞既有結構。

### 3. 「平均出貨抽數」用詞與既有「保底」並存

既有清單已有「5★ 與 4★ 雙保底進度條,並顯示距離保底剩餘抽數」,新增「平均出貨抽數」屬於另一個維度(歷史平均 vs 當前 pity),兩者並存不衝突,文字以「平均出貨抽數」描述,讀者一看就知道是統計值而非保底進度。

### 4. 「HoYoWiki 整合」用一條 bullet 涵蓋多項子功能

底層實作很多(icon 下載、entry 抓取、gallery 圖片、ZoomableImageOverlay、外部連結等),但對使用者來說就是「物品有圖、點下去看詳情、可跳轉 HoYoWiki」這一個體驗。用一條 bullet 描述就夠,避免清單膨脹。

### 5. 「介面 UID 遮罩」與既有「分享圖 UID 遮罩」明確區隔

既有 bullet 描述的是**生成分享圖時**的 UID 遮罩選項(只影響輸出圖片);新增 bullet 描述的是**全應用程式介面**的 UID 遮罩設定(影響所有頁面顯示)。文案以「介面」二字明確劃界,讀者不會混淆。

## 三語版本最終文案

### 繁體中文(`README.md`)

新增 3 個 bullet,分別插入位置:

**位置 1:** 接在「5★ 與 4★ 雙保底進度條,並顯示距離保底剩餘抽數」**之後**
```
- 5★ / 4★ 平均出貨抽數統計(各卡池與整體)
```

**位置 2:** 接在「歷史記錄表格:多欄排序、模糊搜尋、稀有度與物品類型篩選、分頁」**之後**
```
- 自動補上角色 / 武器的圖示與資料(來源:HoYoWiki):表格與時間軸都附圖示;點擊物品可查看官方插圖、描述與標籤,並一鍵跳轉 HoYoWiki
```

**位置 3:** 接在「多國語言([協助翻譯](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))」**之後**、「啟動時自動檢查新版本,也可在設定頁手動觸發」**之前**
```
- 可在設定開啟介面 UID 遮罩(只顯示前三碼),保護隱私
```

### 简体中文(`README_ZH-HANS.md`)

**位置 1:** 接在「5★ 与 4★ 双保底进度条,并显示距离保底的剩余抽数」**之後**
```
- 5★ / 4★ 平均出货抽数统计(各卡池与整体)
```

**位置 2:** 接在「历史记录表格:多列排序、模糊搜索、稀有度与物品类型筛选、分页」**之後**
```
- 自动补上角色 / 武器的图标与资料(来源:HoYoWiki):表格与时间轴都附图标;点击物品可查看官方插画、描述与标签,并一键跳转 HoYoWiki
```

**位置 3:** 接在「多国语言([协助翻译](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))」**之後**、「启动时自动检查新版本,也可在设置页手动触发」**之前**
```
- 可在设置开启界面 UID 遮罩(只显示前三码),保护隐私
```

### English(`README_EN.md`)

**Position 1:** After “Dual pity progress (5★ and 4★) showing remaining pulls until pity”
```
- Average pulls per 5★ / 4★ hit (per-banner and overall)
```

**Position 2:** After “Wish history table: multi-column sort, fuzzy search, rarity and item-type filters, pagination”
```
- Auto-fetched character / weapon icons and details (from HoYoWiki): shown in the history table and timelines; click an item to view official artwork, description, and tags — with a one-click jump to HoYoWiki
```

**Position 3:** After “Multi-language ([help us translate](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))”, before “Automatic update check on launch, with a manual trigger in Settings”
```
- Optional UID masking in the UI (first 3 digits only) for added privacy
```

## 標點規則

- 繁體中文 / 简体中文版:全形標點(`,`、`。`、`:`、`(`、`)`、`「」`、`、`),英文與半形保留給程式碼識別字、URL、`5★ / 4★`、檔名等場合。
- 英文版:半形標點。

## 驗收條件

- 三份 README 的「功能與特色 / Features」區塊各自比動工前**多 3 個 bullet**,內容如上文「三語版本最終文案」所列。
- 插入位置如上文標示。
- 三份 README 互相對齊:同一個概念在同一個相對位置。
- `git diff` 顯示**只動到三份 README 的 Features 清單**,沒有其他區塊或檔案被改到。
- 標點符合「繁/簡用全形、英文用半形」規則。
