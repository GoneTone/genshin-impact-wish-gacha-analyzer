# 原神祈願卡池分析 Genshin Impact Wish Gacha Analyzer

[繁體中文](README.md) | [简体中文](README_ZH-CN.md) | English

[![Translation status](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/svg-badge.svg)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

I developed a utility to analyze the gacha history. All data and numbers are well-organized to free your hand without the dazzling calculations!

This software works by reading the logs in the game to get the wish history website. Therefore, you must start the game and open the wish history page at least once before running this utility to function correctly.

The variables in the website retrieved will be broken down and used in API related to Genshin Impact (from miHoYo).

The software loads your gacha history during the initial start -  this process may take a while. Then, the loaded data will store in the local to make it not take that much time in the next start. The retrieved data will not be updated until you update it manually. The data will also be automatically updated when there is a version update.

Disclaimer: This software does NOT tamper with any game file and data; thus, there is no risk of getting banned from using this software. If you got banned, please kindly consider if you had other factors that got you banned.  Please do not blame us, thanks.

The original post on Bahamut (巴哈姆特): <https://forum.gamer.com.tw/C.php?bsn=36730&snA=11990&tnum=4>

## Multiple Language

Please help us translate this software into a variety of languages!

[![Translation status](https://weblate.reh.tw/widgets/genshin-impact-wish-gacha-analyzer/-/open-graph.png)](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/)

## Download Software

The software may get blocked by the anti-virus software during the installation and execution process. If the software cannot function correctly, please try disabling the anti-virus and run again. We promise this software is safe, virus-free.

<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## Functions & To-do List

- [x] Support The International Server
- [ ] Support The CN Server
- [x] Total Wish Counter
- [x] Average Wishes per 5-star Drop Calculator
- [x] Pity Progress Bar and Remaining Wish Counter
- [x] Drop Rate By Rarity and Drop Counter
- [x] Characters/Weapons Drop Rate and Drop Counter
- [x] Rare Drops Pie-chart
- [x] Characters/Weapons Drops Pie-chart
- [x] Record History From The Official API(Allow Custom Ordering and Search)
- [x] Export the Record to Excel
- [x] Load The According Language Data Form The Official API by Local User's Language
- [x] View Character Image
- [x] Software Update Notification
- [x] Multi-language ([Help us traslate!](https://weblate.reh.tw/engage/genshin-impact-wish-gacha-analyzer/))
- [ ] Switching Between Multi-accounts' records
- [ ] Share The Record and Analyzed Result Online
- [ ] Dark mode
- [X] Daily Check-in Webpage
- [X] Teyvat Interactive Map
- [ ] Update Data Without Overwriting The Original Data
- [ ] Export and Import Data Back-ups (Manual)

## Screenshot 

![Overall Data Chart](docs/images/en/1.png)
![Character Event Wish-Data Chart](docs/images/en/2.png)
![Drop Rate](docs/images/en/3.png)
![Table 1](docs/images/en/4.png)
![Table 2](docs/images/en/5.png)
![Daily Check-in](docs/images/en/6.png)
![Teyvat Interactive Map](docs/images/en/7.png)

## Development

### Install Packages

```bash
npm install
```

### Compile and Run (For Development Use)

```bash
npm run electron:serve
```

### Compile and Minify (For Production Use)

#### ia32 and x64

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
