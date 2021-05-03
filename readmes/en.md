# 原神祈願卡池分析 Genshin Impact Wish Gacha Analyzer

[![翻譯狀態](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/svg-badge.svg)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

我開發了一套用來分析祈願卡池歷史紀錄的軟體，一開啟各種數據清清楚楚，不用再手動計算啦！

本軟體原理是讀取原神遊戲 Log 檔案取得卡池歷史紀錄頁面網址，所以要先在遊戲內開啟過卡池歷史紀錄才能讀取到，取得網址後拆解參數，參數會用於 miHoYo 原神相關的 API。

第一次開啟時會加載您的卡池歷史資料，這可能需要一些時間，完成後會將資料存放在您的電腦內，這樣下次開啟軟體時就不用再花時間等待資料加載了，但要取得新資料要按下更新資料才會更新，如果版本更新了會自動重新加載資料。

請放心：本軟體不會竄改任何遊戲檔案和數據，所以不會有被封鎖帳號的風險。如果有被封號，請思考您是不是其他原因被封鎖，不要怪罪我們。

巴哈姆特文：<https://forum.gamer.com.tw/C.php?bsn=36730&snA=11990&tnum=4>

## 多國語言

請協助我們將軟體翻譯成各國語言！

[![翻譯狀態](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/open-graph.png)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

## 下載軟體

軟體在安裝或執行時有可能會被防毒軟體阻擋。如果無法正常執行，請嘗試關閉防毒軟體後再執行看看，本軟體保證無毒。

[https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases](https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases)

## 功能和待做事項

- [x] Support International Server
- [ ] Support CN Server
- [x] Total wish counts
- [x] 5-star average draw statistics
- [x] Pity progress bar and remaining pulls statistics
- [x] Drop rate and number of wish statistics according to rarity
- [x] Drop rate and number of Characters and Weapons wish statistics
- [x] Wish drop rarity pie chart
- [x] Characters and Weapons drops pie chart
- [x] Wish history (official API data) form (Customizable sorting and search)
- [x] Export wish records to Excel
- [x] Load the official API according to the player's language to obtain relative language data
- [x] Genshin Impact character image preview
- [x] Software version update notification
- [x] Multi-lingual ([Help us translate](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/))
- [ ] Multi-account record switch
- [ ] Share records and analysis results online
- [ ] Dark mode
- [X] Web daily check-in
- [X] Teyvat Interactive Map

## 截圖

![綜合數據圖表](/images/1.png)
![角色活動祈願 - 數據圖表](/images/2.png)
![中獎率](/images/3.png)
![表格 1](/images/4.png)
![表格 2](/images/5.png)
![每日簽到](/images/6.png)
![提瓦特互動地圖](/images/7.png)

## 開發

### 安裝依賴套件

```bash
npm install
```

### 編譯並執行 (開發)

```bash
npm run electron:serve
```

### 編譯並最小化 (生產)

#### ia32 和 x64

```bash
npm run electron:build:win
```

#### ia32

```bash
npm run electron:build:win32
```

#### x64

```bash
npm run electron:build:win64
```
