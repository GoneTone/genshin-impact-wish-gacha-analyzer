# 原神祈願卡池分析 Genshin Impact Wish Gacha Analyzer

[![Translation status](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/svg-badge.svg)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

I developed a software to analyze the historical records of the Genshin Impact Wish. NO MORE GUARANTEE COUNTING! Everything will be all set once you opened your wish history.

The principle of this software is to read the original game Log file to obtain the wish history page URL. So you need to open the wish history in the game before you can load it. After obtaining the URL, the software will disassemble the parameters, the parameters will be used in the API related to miHoYo.

Your wish history data will be loaded when you open it for the first time. This may take a while. After the completion, the data will be stored in your computer, therefore you don’t have to spend time waiting for the data to load next time you open the software. However, if you want to obtain new information, you need to click Update Information. Once the software version is updated, the information will be reloaded automatically.

DISCLAIMER : this software will NOT tamper with any game files and data, there is NO RISK of getting BANNED. We do not take responsibility whether you have been BANNED for other reasons if happened.

Original post from Bahamut forum 巴哈姆特文：<https://forum.gamer.com.tw/C.php?bsn=36730&snA=11990&tnum=4>

## multi-lingual

Please help us translate the software into various languages!

[![Translation status](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/open-graph.png)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

## Download software

The software may be blocked by anti-virus software during installation or execution. If the software fails to execute, please try disabling the anti-virus software and rerun. The software is guaranteed to be virus-free.

[https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases](https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases)

## Features And To-dos

- [x] Support International Server
- [ ] Support CN Server
- [x] Total pull counts
- [x] 5-star average draw statistics
- [x] Guaranteed progress bar and remaining pulls statistics
- [x] Pull rate and number of wish statistics according to rarity
- [x] Pull rate and number of Characters and Weapons wish statistics
- [x] Wish drop rarity pie chart
- [x] Characters and Weapons drops pie chart
- [x] Wish history (official API data) form (Customizable sorting and search)
- [x] Export wish records to Excel
- [x] Load the official API according to the player's language to obtain relative language data
- [x] Genshin Impact character image preview
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
![Table 1](/images/4.png)
![Table 2](/images/5.png)
![Daily login](/images/6.png)
![Teyvat interactive map](/images/7.png)

## Development

### Installation package

```bash
npm install
```

### compile and run (for development use)

```bash
npm run electron:serve
```

### compile and minimize (for productive use)

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
