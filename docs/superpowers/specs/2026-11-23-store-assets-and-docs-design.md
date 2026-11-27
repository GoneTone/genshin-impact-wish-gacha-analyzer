# 子專案 13：授權頁、README 與主題圖片（設計）

狀態：實作完成；截圖於 2026-11-24 補上

## 目的

Android 移植的最後一個子專案。比照鳴潮移植筆記第 55、56 節（授權頁、README），以及鳴潮的 `tool/generate_feature_graphic.py`，補齊上架與公開說明需要的部分。

全部在 `feat/android` 上做，這個子專案完成後**還不開 PR**：內部測試版用這個分支在本機建置；發布後，同一個分支補上截圖，再開 PR。

## 範圍

### 這次做

1. **授權頁**：貢獻者頁「專案授權」區塊下方加一顆「開放原始碼授權」按鈕（`contributorsOpenSourceLicenses`，31 種語言，翻譯照鳴潮），按下去開 Flutter 內建的 `showLicensePage`。
   - 傳 `useRootNavigator: true`。
   - 版本用 `appVersionProvider`。
   - 圖示自己包 `Padding`。
   - 實作逐字對照鳴潮。
2. **README 文字（四種語言：`README.md`、`README_EN.md`、`README_JA-JP.md`、`README_ZH-HANS.md`）**：照鳴潮筆記第 56 節「一定要改的」和「容易漏掉的寫法」改。
   - 用詞照該語言 ARB 的官方用語。
   - 功能列表要對照現在的畫面逐條檢查。
   - Android 段落這次先不放圖。
3. **主題圖片**：移植 `tool/generate_feature_graphic.py`，輸出 `docs/images/play-store/feature-graphic-<語言>.png`，共四張（1024×500）。
   - 版面、字型、配色與檔名語言碼（`en`、`zh-TW`、`ja`、`zh-CN`）照鳴潮。
   - 文字和商店標題（`private/play-store/listing.md`）一致：

     | 語言 | 名稱 | for | 標語 |
     |---|---|---|---|
     | en | Wish Analyzer | for Genshin | Wish stats · Pity tracking · 5★ timeline |
     | zh-TW | 祈願卡池分析 | for 原神 | 祈願記錄統計・保底進度・5★ 時間軸 |
     | ja | 祈願分析 | for 原神 | 祈願履歴の統計・天井の進捗・★5 タイムライン |
     | zh-CN | 祈愿卡池分析 | for 原神 | 祈愿记录统计・保底进度・5★ 时间轴 |

   - 網址列：`github.com/GoneTone/genshin-impact-wish-gacha-analyzer`。

### 內部測試發布後再做（同一個分支、開 PR 前）

- 移植 `tool/capture_store_screenshots.py`，拍商店截圖：四種語言 × 四種裝置（手機、7 吋、10 吋、Chromebook）。用哪個帳號的資料，到時候再決定。
- README 的 Android 段落放手機和 10 吋截圖。
- Windows 截圖搬到 `docs/images/<語言>/windows/`，順序和商店截圖一致，並補拍「等待開啟記錄頁」。

### 商店頁上線後再做

- README「下載軟體」段的下載徽章與商標聲明、Release 頁尾的下載段。
- 標題上方的主題圖片原本也排在這裡，2026-11-24 改為提前加上（比照鳴潮；圖片不依賴商店頁上線）。
- `docs/release.md` 的徽章／`{{INSTALLER_URL}}` 那句改回鳴潮原文。

### 不做

- **Android 原生套件和 Rust crate 的授權**：照鳴潮第 55 節，不加 `oss-licenses-plugin`。
- **WinDivert 授權**：原神沒有用 WinDivert。
- **MSVC `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`**：鳴潮加它是因為 `flutter_inappwebview_windows`，原神沒有這個外掛。第一次 CI 發版出現 STL1011 錯誤再補。
- **Crowdin**：`crowdin.yml` 已經有 `strings.xml` 那組設定。既有翻譯要在合併後用 CLI 補匯入，屆時和本機改過的卡池名一起處理。

## 驗收

- 授權頁：
  - 有 widget 測試，確認按鈕存在，按下後打開 `LicensePage`。
  - Windows 和 Android 都要看過畫面，確認授權頁蓋住整個畫面。
  - `fvm flutter analyze`、`fvm flutter test` 全綠。
- README：四種語言的段落結構一致，沒有留下只適用電腦版的句子（照第 56 節逐條核對）。
- 主題圖片：四張都是 1024×500、RGB；文字沒有超出邊界，也沒有缺字（豆腐字）。

## 附錄：實作結果

### Commits

- 授權頁：`72d1a3b`。
- 主題圖片：`80de832`。
- README：`1f6f70c`、`9604cd7`、`ee25abb`、`eaa3e07`。

### 畫面確認

- Android（模擬器，x86_64 release 版）：授權頁蓋住整個畫面，圖示與版本都有顯示。
- Windows（debug 版，使用者授權模擬點擊）：授權頁蓋住整個視窗（含上方帳號列與下方「最後更新」），以左右分欄顯示，圖示與版本都有顯示。
- 主題圖片：四張都看過，沒有缺字，文字也沒有超出邊界。

### 和設計不同的地方

- **原神 Android 版的讀取方式只有兩種**：root 與無線偵錯（Android 11 以上），讀的是系統 log。
  - 鳴潮 README 的「直接讀取（Android 10 以下）」與「讀遊戲 log 檔」都沒有照搬。
- **「請放心」段的 Windows 子句改寫**：原本寫「不讀取遊戲檔案、只攔截那一條請求」，但 Windows 版其實會讀 `output_log.txt`（找遊戲資料夾）和網頁快取（找網址）。
  - 改成如實描述。
  - 照鳴潮的寫法，刪掉「不會讀取遊戲傳輸的資料」。
- **功能列表**：
  - 逐條對照程式後，保底進度條、時間軸、平均出貨抽數三條補上「常駐頌願為 4★ 與 3★」或「常駐頌願為 4★」。
  - 分享圖改成「複製或儲存，Android 另可系統分享」。
  - 「模糊搜尋」改成「關鍵字搜尋（依名稱）」。
- **原理段與使用方式沒有提網頁快取備援**：子專案 0 沒有把 README 列入範圍，這次的範圍也只有 Android。

### 截圖（2026-11-24）

- **資料**：使用者朋友的帳號（1752 抽），使用者 2026-11-24 指定。
  - 截圖時遮蔽 UID，並暫時拿掉帳號別名。
  - Android 模擬器只匯入這個帳號；Windows 拍完用備份把資料夾整個還原。
- **商店截圖**：移植 `tool/capture_store_screenshots.py`，四種語言 × 四種裝置各 8 張，放在 `docs/images/play-store/screenshots/<語言>/<裝置>/`。
  - 詳情打開最新的 5★ 角色薇斯納（Vesna、ヴェスナ、薇斯纳）。
  - App 語言用原神的 `zh-Hant`／`zh-Hans`；拍完改回開始前的設定（鳴潮寫死改回 `zh-TW`）。
  - 存檔失敗時重試：實際拍攝時遇過一次 `OSError: [Errno 22]`，推測是檔案被短暫鎖住。
  - 模擬器上用的是不帶 `ads_defines.json` 的 x86_64 release 版（只播測試廣告、沒有 AdMob 驗證器浮層），因為模擬器上原本那版是上傳金鑰簽的，換 debug 金鑰的版本要先解除安裝。
  - agent-device 開著時 `uiautomator dump` 不會輸出，腳本檔頭已註明。
- **README**：四種語言的截圖段分成 Windows、Android 手機、Android 平板三小節，Android 直接引用 `phone` 與 `tablet-10`。
- **Windows 截圖**：四種語言全部重拍，放在 `docs/images/<語言>/windows/1–9.png`，舊的 `docs/images/<語言>/1–8.png` 刪除。
  - 順序照鳴潮：綜合、角色、武器、頌願（活動）、物品詳情、分享圖設定、分享圖、等待畫面、設定。
  - 原神多一張頌願頁（使用者決定保留），所以是 9 張。
  - 等待畫面：存著的網址還有效時按更新不會進入等待，拍攝時暫時移開 `<UID>.url.json`。
- **和設計不同的地方**：
  - **Windows 截圖整組重拍**：設計原本只寫「搬到 `windows/`、補拍等待畫面」，但舊圖是 v1.4.0，圖示、資料量都和 Android 對不上，使用者 2026-11-24 同意整組重拍。
  - **雲端同步會把別名寫回來**：Windows 開著自動同步時，清掉的別名會被雲端的別名合併回來（合併規則是「本機沒有別名就用雲端的」），所以拍攝期間關掉自動同步，拍完由備份還原。
