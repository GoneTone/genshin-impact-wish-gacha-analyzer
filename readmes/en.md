# 原神祈願卡池分析 Genshin Impact Wish Gacha Analyzer

[![translation status](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/svg-badge.svg)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

I developed a set of software to analyze the historical records of the Genshin Impact Gatcha. NO MORE GUARANTEE COUNTING! Everything will be all set once you open your gacha history.

The principle of this software is to read the original game Log file to obtain the Gacha history page URL. So you need to open the Gacha history in the game before you can load it. After obtaining the URL, the software will disassemble the parameters, the parameters will be used in the API related to miHoYo.

Your Gacha history data will be loaded when you open it for the first time. This may take a while. After completion, the data will be stored in your computer, in that case you don’t have to spend time waiting for the data to load next time you open the software. However, if you want to obtain new information, you need to click Update Information. Once the software version is updated, the information will be reloaded automatically.

DISCLAIMER : this software will not tamper with any game files and data, there is no risk of getting BANNED. We do not take responsibility whether you have been BANNED for other reasons if happened.

Original post from Bahamut forum 巴哈姆特文：<https://forum.gamer.com.tw/C.php?bsn=36730&snA=11990&tnum=4>

## multi-lingual

Please help us translate the software into various languages!

[![Translation status](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/open-graph.png)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

## Download software

The software may be blocked by anti-virus software during installation or execution. If the software fails to execute, please try closing the anti-virus software and rerun. The software is guaranteed to be virus-free.

[https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases](https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases)

## Features and to-dos

- [x] Support International Server
- [ ] Support CN Server
- [x] Total pull counts
- [x] 5-star average draw statistics
- [x] Guaranteed progress bar and remaining pulls statistics
- [x] Pull rate and number of Rank gacha statistics
- [x] Pull rate and number of Characters and Weapons gacha statistics
- [x] Number of Rank gacha pie chart
- [x] Number of Characters and Weapons gacha pie chart
- [x] Gacha history (official API data) form (Customizable sorting and search)
- [x] Export gacha records to Excel
- [x] Load the official API according to the player's language to obtain relative language data
- [x] Genshin Impact character image review
- [x] Software version update notification
- [x] multi-lingual ([Help us translate](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/))
- [ ] Multi-account record switch
- [ ] Share records and analysis results online
- [ ] Dark mode
- [X] Web daily check-in
- [X] Teyvat Interactive Map

## Screenshots

![Comprehensive data chart](/images/1.png)
![Character Gacha Data Chart](/images/2.png)
![Pull rate](/images/3.png)
![Chart 1](/images/4.png)
![Chart 2](/images/5.png)
![Daily login](/images/6.png)
![Teyvat interactive map](/images/7.png)

## Development

### 安裝依賴套件

```bash
npm install
```

### 編譯並執行 (開發)

```bash
npm run electron:serve
```

### 編譯並最小化 (生產)

#### ia32 & x64

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
