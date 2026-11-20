# 手機滑動流暢度（子專案 8）— 設計 spec

- 狀態：已核准（2026-11-20）
- 日期：2026-11-20
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第三節子專案 8；順序已調整為 8 → 9 → 12 → 10 → 11 → 7 → 13）
- 對應鳴潮版：`wuthering-waves-convene-gacha-analyzer` 的 `2026-11-07-mobile-scroll-smoothness-design.md`，commit `fe269e9`～`6ab24d1`（清單見第二節）；移植筆記第 41 節

---

## 一、目的

鳴潮版在 ROG Phone 9（165Hz）實測，綜合頁慣性滑動只有約 43% 的幀準時，根因是頁面結構，不是某個元件慢（移植筆記第 41 節）。原神版的頁面結構和鳴潮分家前相同，有同樣的三個問題：

1. 綜合頁、卡池頁（含頌願）外層是 `SingleChildScrollView` + `Column`（`overview_page.dart:122`、`banner_page.dart:135`），整頁一次建好，每捲一點整頁（含畫面外的區塊）都要重新繪製與更新語意樹。
2. 保底卡呼吸動畫在 `initState` 無條件 `repeat()`（`pity_card.dart:51`），只有「快保底」才用得到，但計時器一直跑，卡池頁靜止時也持續重畫（耗電）。
3. 橫向五星時間軸是 `SingleChildScrollView` + `Row`（`timeline_horizontal.dart:191`），所有欄位一次建好；五星一覽是整塊 `Wrap` 一次建好。

這個子專案照搬鳴潮的結構改動。**流暢度實測（profile 版、SurfaceFlinger 量慣性滑動準時率）不在這次做**，留到子專案 9 做完、UI 定案後（使用者 2026-11-20 決定，路線圖第三節）。

## 二、範圍

**移植的鳴潮 commit**（`git -C ../wuthering-waves-convene-gacha-analyzer show <commit>`）：

| commit | 內容 |
|---|---|
| `fe269e9` | 呼吸動畫只在快保底時跑（`pity_card.dart`） |
| `819f3f4` | 捲出畫面的有狀態區塊保持存活（`timeline_vertical.dart`、`search_filter_bar.dart`、`sortable_table.dart`） |
| `5907e54` | 橫向時間軸逐欄按需建構（`timeline_horizontal.dart`） |
| `7b33b11` | 綜合頁、卡池頁改成按需建構（`overview_page.dart`、`banner_page.dart`） |
| `70d206a` | `.gitattributes` 加 `*.sh text eol=lf` |
| `9d6be8c` | 電腦版整頁預先建好，捲軸滑塊不跳（`layout.dart` 的 `pageScrollCacheExtent()`） |
| `595ee0e` | 分享按鈕捲出畫面時仍維持忙碌狀態（`share_action_button.dart`） |
| `9317776` | 五星區塊出現時，卡池頁的搜尋與表格狀態不重置（`banner_page.dart`） |
| `e002813` | 時間軸圖示欄節點對齊軸線、拖曳游標只在欄位上（`timeline_horizontal.dart`） |
| `40a6a98` | 測試：呼吸動畫跑到一半開啟「減少動態」 |
| `0cb1fff` 與 `93e63b8` 的腳本部分 | `tool/measure_frame_pacing.sh`（以 `0cb1fff` 的版本為準） |
| `6ab24d1` | 五星一覽逐列建構（`five_star_overview.dart`、兩個頁面） |

**不移植**：`14be8a8`、`71a5f40`（spec／plan）、`93e63b8`／`96980f9` 的移植筆記內容（原神記在本 spec 附錄）。

**新增的前置重構（使用者 2026-11-20 同意）**：時間軸寫法對齊鳴潮，見 4.1。

## 三、目標／非目標／反目標

**目標**

- 手機與平板上，綜合頁、卡池頁、頌願頁只建構、繪製畫面上看得到的區塊；橫向時間軸只建構看得到的欄；五星一覽逐列建構。
- 保底卡靜止時不排程畫面；「快保底」時呼吸動畫照常；pity 資料更新而進入或離開「快保底」時動畫跟著啟停；開啟「減少動態」時停止。
- 外觀、互動在手機與電腦版都不變（唯一例外：4.1 的直向時間軸兩處對齊鳴潮）。

**非目標**

- 流暢度實測與達標（≥ 95%）：留到子專案 9 之後。
- 啟動流程、物品圖示解碼尺寸、`build()` 內的檔案存在檢查（鳴潮量過不是瓶頸）。
- 鎖定刷新率、關閉語意樹等迴避手段。
- 設定頁、貢獻者頁（鳴潮量過已達標，不改）。

**反目標**

- 捲出畫面再捲回來時遺失狀態：紀錄表頁碼、搜尋框文字、篩選狀態、時間軸的橫向捲動位置。
- 版面在任何寬度下跑掉（電腦三欄、中寬、手機），或 RWD 斷點行為改變。
- 電腦版捲軸滑塊隨捲動改變大小或跳動。
- 無障礙退步：語意內容只改成按需產生，不刪除。
- 原神特有的部分被改掉：綜合頁的「祈願／頌願」兩段、HoYoWiki 圖片索引、`gachaType` 等原神命名、GIF 物品圖。

## 四、做法

### 4.1 前置重構：時間軸寫法對齊鳴潮（新增，外觀不變）

**為什麼**：兩邊時間軸外觀一樣，但寫法分岔。鳴潮 6/2 從原神分出時，把節點圓抽成共用的 `lib/widgets/cards/timeline_node.dart`（`TimelineNode`）；原神沒抽，直向時間軸自己有 `_Node`（`timeline_vertical.dart:590`），橫向又另外畫一份。6/19 兩邊各自做了「歐非色」「年／月分隔」「提示只顯示名稱」，功能一樣但程式各寫各的，所以 `timeline_horizontal.dart` 差約 230 行、`timeline_vertical.dart` 差約 165 行。不先對齊，`5907e54`、`e002813` 只能重寫。

**做什麼**：

- 新增 `lib/widgets/cards/timeline_node.dart`，以鳴潮 `fe269e9~1` 的版本為底（換套件名），橫向與直向時間軸都改用它，刪掉各自的節點實作。
- `timeline_horizontal.dart`、`timeline_vertical.dart` 的結構（常數、私有 widget 的拆法、月份／年份分隔的寫法）改成和鳴潮 `fe269e9~1` 相同，**畫出來的結果不變**。
- 原神特有的保留：`gachaType`（鳴潮是 `key`）、HoYoWiki 物品圖示（`GachaItemIcon` 一類）、原神的字串 key、歐非色計算用的稀有度參數。
- 鳴潮時間軸用到、原神還沒有的共用小工具一併帶進來（**我的判斷**，依 CLAUDE.md「不重複造輪子」）：
  - `kTabularFigures`（鳴潮 `lib/theme/tokens.dart`）：原神 `lib` 裡 14 處 `const [FontFeature.tabularFigures()]` 全部換成它，和鳴潮一致（鳴潮只剩定義那一處）。輸出完全相同。
  - `formatShortMonthDay`（鳴潮 `lib/utils/relative_time.dart`）：取代時間軸各自的 `_formatShortDate`。
  - 這兩項做成時間軸重構之前的獨立 commit（`refactor: ...`）。
- 驗收：既有的 `timeline_horizontal_test.dart`、`timeline_vertical_test.dart` 不改斷言就要通過；另加 golden 或尺寸／位置斷言，鎖住重構前後節點、月份標籤、分隔線的位置不變（**我的判斷**：純重構最怕「看起來差不多」，要有數字鎖住）。
- 做成獨立 commit（`refactor(timeline): ...`），放在所有移植 commit 之前。

**直向時間軸的兩處外觀差異照鳴潮改（使用者 2026-11-20 選 A）**：比對時發現兩邊直向時間軸不是完全一樣。

| | 原神原本 | 鳴潮（採用） |
|---|---|---|
| 歐非圖例上方間距 | `AppSpacing.s`（8） | `AppSpacing.m`（12） |
| 沒有任何節點（只有「現在」）時 | 仍顯示圖例 | 不顯示（`withLegend: widget.showLuckLegend && entries.isNotEmpty`） |

這兩處是唯一允許的外觀改動，做成獨立 commit（`style(timeline): ...`），放在不改外觀的結構重構**之後**，讓結構重構的位置斷言先在原外觀上通過。分享圖兩邊都傳 `showLuckLegend: true`，不受影響（有五星時照常顯示圖例）。

**判準**：結構重構與上面的 `style` commit 都完成後，`timeline_horizontal.dart`、`timeline_vertical.dart`、`timeline_node.dart` 和鳴潮 `fe269e9~1` 換掉套件名後比對，剩下的差異只能是上面列的原神特有部分。差異清單寫進實作報告。

### 4.2 移植鳴潮的改動

照第二節的順序移植，每個 commit 帶來的改動套到原神現有結構上（和子專案 3、4 相同做法：移植改動，不是整檔換成鳴潮版）。

- **頁面按需建構（`7b33b11`、`9d6be8c`、`9317776`、`6ab24d1`）**：`overview_page.dart`、`banner_page.dart` 外層照鳴潮改成 `CustomScrollView` + `SliverPadding` + `SliverMainAxisGroup` + `SliverList.list`（鳴潮從 `7b33b11` 起就是這個寫法，沒用過 `ListView`），同樣的 padding 與子區塊。`scrollCacheExtent: pageScrollCacheExtent()`：Windows／macOS／Linux 回 `ScrollCacheExtent.pixels(100000)`（整頁預先建好），手機與平板回 null（按需建構）。兩邊 `.fvmrc` 都是 Flutter 3.47.5，`ScrollCacheExtent` 可用。
  - **原神的綜合頁有「祈願」「頌願」兩段**（`_OverviewSection`），各自有統計、圖表、時間軸，兩段都要按需建構。**五星一覽只有祈願段有**（頌願段不傳 `fiveStarItems`），逐列建構只用在祈願段。
  - 頌願頁共用 `BannerPage`，跟著卡池頁一起改。
- **狀態保留（`819f3f4`、`9317776`、`595ee0e`）**：照鳴潮用 keep-alive（`AutomaticKeepAliveClientMixin`）讓 `SortableTable`、`SearchFilterBar`、`TimelineVertical` 捲出畫面後仍保留狀態；分享按鈕捲出畫面時忙碌狀態不重置。原神若還有其他會被回收且帶本地狀態的區塊（例如頌願段特有的元件），一併處理並在報告列出。
- **時間軸（`5907e54`、`e002813`）**：在 4.1 對齊後套用。橫向改成 `ListView.builder` 逐欄建構，「現在」欄、月份分隔線、左右漸層、箭頭、捲動指示、滑鼠拖曳維持現狀。`e002813` 的節點對齊修正：先在原神確認是否有同樣的錯位（鳴潮是圖示欄節點沒對齊軸線），有就套用；沒有也照搬程式，讓兩邊一致（**我的判斷**：對齊後的結構相同，錯位理應相同）。
- **呼吸動畫（`fe269e9`、`40a6a98`）**：只在 phase 為 `close` 且未要求減少動態時 `repeat()`，其他時候 `stop()`；`didUpdateWidget` 跟著 pity 資料啟停；減少動態設定變化時也要跟著停。呼吸動畫外層照鳴潮包一層 `RepaintBoundary`，動畫只重畫進度條本身。
- **量測腳本（`70d206a`、`0cb1fff`）**：搬 `tool/measure_frame_pacing.sh` 與 `.gitattributes` 規則，這次不執行，子專案 9 量測時用。腳本裡的套件名換成 `tw.reh.genshin.gacha`。

### 4.3 log

這些都是純畫面結構改動，沒有新的 I/O 或錯誤分支，不新增 log（和鳴潮相同）。

## 五、驗收

**自動測試**（`fvm dart format lib/ test/` 無改動、`fvm flutter analyze` 無問題、`fvm flutter test` 全過）

- 照搬鳴潮在這些 commit 新增的測試，改寫到原神的測試 helper 上；既有斷言不可刪減。至少涵蓋：
  - 非快保底時 `PityCard` 不排程畫面；快保底時動畫在跑；進出快保底會啟停；跑到一半開啟減少動態會停。
  - 紀錄表翻到第 N 頁、捲出再捲回，仍在第 N 頁；搜尋框文字、時間軸橫向位置同樣保留。
  - 手機寬度下，畫面外的區塊沒有被建構；電腦版整頁都建好。
  - 橫向時間軸只建構看得到的欄。
  - 五星區塊出現時，卡池頁的搜尋與表格狀態不重置。
  - 分享按鈕捲出再捲回，仍是忙碌狀態。
  - 五星一覽逐列建構。
- **原神特有**：綜合頁的頌願段同樣按需建構、狀態同樣保留；頌願頁（`BannerPage`）同上；頌願段沒有五星一覽，不出現多餘的空區塊。
- 4.1 的時間軸重構有位置／尺寸斷言鎖住外觀；直向時間軸另有測試鎖住「圖例上方 12px」與「沒有節點時不顯示圖例、有節點時顯示」。

**實機（debug 版即可，不量幀率）**

- 手機（ROG Phone，直向與橫向）：綜合頁、角色活動、武器活動、頌願頁上下捲動，外觀與改動前相同；翻頁、搜尋、時間軸橫捲後捲出再捲回，狀態都在；快保底的卡池呼吸動畫照常。
- Windows：同樣幾頁的外觀不變；捲動時右側捲軸滑塊大小固定、不跳。
- 測完依記憶「手機測完要真的還原」收尾。

**留到子專案 9 之後**：profile 版、`tool/measure_frame_pacing.sh` 實測慣性滑動準時率（目標 ≥ 95%）與靜止時出幀。

## 六、留給實作者決定

- 4.1 的 golden 測試或數值斷言，選一種可在 Windows 與 Linux CI 都穩定的做法。
- 原神特有區塊（頌願段）需不需要額外的 keep-alive，依實際有沒有本地狀態判斷，報告列出。

## 七、文件

- 本 spec 附錄 A：各鳴潮 commit 在原神的落點與偏離（實作後補）。附錄 B：驗收結果（驗收後補）。
- 不改 README（鳴潮這段也沒改）。
