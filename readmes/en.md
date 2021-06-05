# 原神祈願卡池分析 Genshin Impact Wish Gacha Analyzer

[![Translation status](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/svg-badge.svg)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

I developed a software to analyze the historical records of the Genshin Impact Wish. NO MORE GUARANTEE COUNTING! Everything will be all set once you opened your wish history.

The principle of this software is to read the original game Log file to obtain the wish history page URL. So you need to open the wish history in the game before you can load it. After obtaining the URL, the software will disassemble the parameters, the parameters will be used in the API related to miHoYo.

Your wish history data will be loaded when you open it for the first time. This may take a while. After the completion, the data will be stored in your computer, therefore you don’t have to spend time waiting for the data to load next time you open the software. However, if you want to obtain new information, you need to click Update Information. Once the software version is updated, the information will be reloaded automatically.

DISCLAIMER : this software will NOT tamper with any game files and data, there is NO RISK of getting BANNED. We do not take responsibility whether you have been BANNED for other reasons if happened.

Original post from Bahamut forum 巴哈姆特文：<https://forum.gamer.com.tw/C.php?bsn=36730&snA=11990&tnum=4>

## Multi-lingual

Please help us translate the software into various languages!

[![Translation status](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/open-graph.png)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

## Download software

The software may be blocked by anti-virus software during installation or execution. If the software fails to execute, please try disabling the anti-virus software and rerun. The software is guaranteed to be virus-free.

[https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases](https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases)

## Features And To-dos

- [x] 支援國際服
- [ ] 支援中國服
- [x] 總抽數統計
- [x] 中5星平均抽數統計
- [x] 保底進度條及剩餘抽數統計
- [x] 級別中獎率和中獎數統計
- [x] 角色武器中獎率和中獎數統計
- [x] 級別中獎數圓餅圖
- [x] 角色武器中獎數圓餅圖
- [x] 歷史紀錄 (官方 API 資料) 表單 (可自訂排序及搜尋)
- [x] 將抽卡紀錄導出 Excel
- [x] 依據玩家語言讀取官方 API 取得相對語言資料
- [x] 原神角色圖像查看
- [x] 版本更新通知
- [x] 多國語言 ([協助翻譯](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/))
- [ ] 多帳號紀錄切換
- [ ] 紀錄和分析結果分享至線上
- [ ] 黑暗模式主題
- [X] 網頁簽到頁面
- [X] 提瓦特互動地圖
- [ ] 資料更新不覆蓋舊資料
- [ ] 資料備份導出導入 (手動)

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
