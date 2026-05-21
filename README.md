# 原神祈願卡池分析 Genshin Impact Wish Gacha Analyzer

繁體中文 | [简体中文](README_ZH-HANS.md) | [English](README_EN.md)

[![Crowdin](https://badges.crowdin.net/genshin-impact-wish-gacha-analyzer/localized.svg)](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer)

我開發了一套用來分析祈願卡池歷史記錄的軟體，一開啟各種數據清清楚楚，不用再手動計算啦！

本軟體原理是按下「更新資料」後會在本機啟動一個只跑在您電腦上的代理伺服器，並自動安裝一張本機產生的根憑證，藉此攔截原神 WebView 對 miHoYo 卡池歷史 API 的請求，所以要在按下更新後再到遊戲內開啟卡池歷史記錄才能攔到，取得網址後拆解參數，參數會用於 miHoYo 原神相關的 API。

第一次按下「更新資料」會加載您完整的卡池歷史，這可能需要一些時間，完成後會將資料存放在您的電腦內，這樣下次開啟軟體就不用再花時間等待資料加載。之後想取得新資料按一下「更新資料」即可，軟體會記住先前攔到的網址，能用就直接用、不用每次重新攔截；如果網址過期，軟體會請您再到遊戲開一次卡池歷史頁面以重新取得網址。

請放心：本軟體不會讀取或竄改任何遊戲檔案、記憶體與遊戲傳輸的資料，只會在 WebView 開啟卡池歷史頁面時攔下那一條請求網址，所以不會有被封鎖帳號的風險。如果有被封號，請思考您是不是其他原因被封鎖，不要怪罪我們。

文章：
- 巴哈姆特：<https://forum.gamer.com.tw/C.php?bsn=36730&snA=11990&tnum=4>
- HoYoLAB：<https://www.hoyolab.com/genshin/article/552176>

## 多國語言

請協助我們將軟體翻譯成各國語言！

<https://crowdin.com/project/genshin-impact-wish-gacha-analyzer>

## 下載軟體

軟體在安裝或執行時有可能會被防毒軟體阻擋。原因是本軟體會自行產生並安裝一張本機根憑證、並在按下更新時短暫設定系統代理以攔截原神 WebView 的卡池歷史請求──這類行為與惡意程式相似，但本軟體只攔截 `*.hoyoverse.com/getGachaLog` 這一條 API，且憑證只留在您的電腦。如果無法正常執行，請嘗試關閉防毒軟體後再執行看看，本軟體保證無毒。

<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## 使用方式

1. 啟動原神，先別開啟卡池歷史頁面。
2. 開啟本軟體並按下「更新資料」，軟體會在背景啟動本機代理伺服器並等候攔截。
3. 切回遊戲，到「祈願 → 歷史記錄」開啟卡池歷史頁面。
4. 軟體攔到網址後會自動關閉代理、還原系統代理設定並開始抓取資料；之後想再更新只要重複步驟 2，網址未過期就會直接套用。

## 功能與特色

- 自動攔截原神 WebView 對 miHoYo 卡池歷史 API（透過本機代理伺服器與自簽根憑證），不需手動貼網址
- 支援國際服 (暫不支援中國服)
- 涵蓋 7 種卡池：角色活動祈願、武器活動祈願、集錄祈願、常駐祈願、新手祈願、活動頌願、常駐頌願
- 多帳號 (UID) 管理：自訂別名、拖曳排序、一鍵切換
- 自動合併新舊資料，不覆蓋過去記錄，不會因為官方歷史記錄過時而消失
- 總抽數及 5★ / 4★ / 3★ / 2★ 件數與占比統計
- 5★ 與 4★ 雙保底進度條，並顯示距離保底剩餘抽數
- 各卡池 5★ 時間軸
- 各卡池最高稀有度件數比較長條圖
- 稀有度分布圓餅圖
- 類型分布圓餅圖
- 歷史記錄表格：多欄排序、模糊搜尋、稀有度與物品類型篩選、分頁
- 帳號資料匯出 / 匯入 JSON
- 深色 / 淺色主題切換
- 多國語言（[協助翻譯](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer)）
- 啟動時自動檢查新版本，也可在設定頁手動觸發
- 所有資料留在本機，不上傳

## 截圖

![綜合數據頁](docs/images/zh-Hant/1.png)
![角色活動祈願頁](docs/images/zh-Hant/2.png)
![活動頌願頁](docs/images/zh-Hant/3.png)
![設定頁](docs/images/zh-Hant/4.png)
![分享圖生成設定](docs/images/zh-Hant/5.png)
![分享圖](docs/images/zh-Hant/6.png)

## 開發

### 前置需求

- 目前僅支援 Windows
- [Flutter SDK](https://docs.flutter.dev/install)（最新穩定版）
- [Rust toolchain](https://rustup.rs/)（stable）
- 執行 `flutter doctor`，依提示補齊缺少的工具

### 取得原始碼並安裝依賴

```bash
git clone https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer.git
cd genshin-impact-wish-gacha-analyzer
flutter pub get
cargo build --manifest-path rust/Cargo.toml
```

### 開發模式執行

```bash
flutter run -d windows
```

### Rust ↔ Dart 橋接程式碼產生

修改 `rust/src/api/` 內的 Rust 函式後，重新產生橋接程式碼。第一次使用前先安裝 codegen 工具：

```bash
cargo install flutter_rust_bridge_codegen
```

之後每次修改 API 都執行：

```bash
flutter_rust_bridge_codegen generate
```

產生的檔案位於 `lib/src/rust/`。

### 編譯生產版

```bash
flutter build windows --release
```

輸出：`build\windows\x64\runner\Release\`

### 執行測試

```bash
flutter test
cargo test --manifest-path rust/Cargo.toml
```
