# README 介紹區塊改寫 Design

## 背景

Flutter+Rust 重寫後，取得卡池歷史 URL 的機制從「讀 Web Cache 檔案」改為「啟動本機 MITM proxy 攔截 webview 對 `*.hoyoverse.com/getGachaLog` 的請求」。三份 README（`README.md`、`README_EN.md`、`README_ZH-CN.md`）的「介紹四段」仍在描述舊流程，需要同步更新。

「下載軟體」段提到防毒軟體誤報，新流程因為包含產生／安裝本機根憑證、設置系統代理，誤報機率比舊流程高，也需要補充說明來源。

## 目標

- 將三份 README 的「介紹四段」改寫為符合新流程的描述。
- 保留原作者口語、第一人稱的語氣（不重組、不轉成正式文體）。
- 新增「使用方式」段，明確指引「按更新 → 開卡池歷史」的順序。
- 「下載軟體」段補充防毒誤報的技術原因（MITM proxy + 本機根憑證）。

## 非目標

- 不重組整份 README 結構。
- 不調整「功能與待做事項」、「截圖」、「開發」等段落。
- 不在介紹中暴露低層細節（如 `127.0.0.1:18080`、`hudsucker`、`rcgen` 等）。

## 範圍

需要改動的檔案與段落：

| 檔案 | 改動段落 |
|---|---|
| `README.md`（zh-TW）| 介紹四段、新增「使用方式」段、「下載軟體」段補述 |
| `README_EN.md` | 介紹四段、新增 “How to Use” 段、Download 段補述 |
| `README_ZH-CN.md` | 介紹四段、新增「使用方式」段、「下载软件」段补述 |

「使用方式」段插入位置：放在「下載軟體」段之後（先讓使用者下載、再講怎麼用）。

## 設計決策

### 1. 改寫方向：最小改寫、保留原結構

維持原本「介紹 → 原理 → 首次/更新流程 → 不封號」四段對齊。只代換失準的事實（Web Cache → MITM 攔截）、補上順序提示（按更新後再開卡池歷史頁面），不調整段落順序、不轉換人稱。

### 2. 憑證透明度：介紹中明說、下載段詳述

「原理」段一行帶過「會在本機啟動代理伺服器、安裝本機產生的根憑證」；「下載軟體」段詳述「為什麼可能被防毒軟體誤報」，明確說明「只攔 `*.hoyoverse.com/getGachaLog`、憑證只留在使用者電腦」。

### 3. 「不封號」段：保留口語、補技術邊界

保留原作者「請放心」、「不要怪罪我們」這類親切語氣，但把「不會竄改任何遊戲檔案和數據」擴寫為「不會讀取或竄改任何遊戲檔案、記憶體與遊戲傳輸的資料，只會在 webview 開啟卡池歷史頁面時攔下那一條請求網址」。

### 4. 移除已不存在的描述

舊版說「如果版本更新了會自動重新加載資料」──新版程式碼（`lib/state/wish_repository.dart`）裡沒有這個邏輯，必須移除。

## 三語版本最終文案

### 繁體中文（README.md）

**介紹段（保留原樣）：**
> 我開發了一套用來分析祈願卡池歷史記錄的軟體，一開啟各種數據清清楚楚，不用再手動計算啦！

**原理段：**
> 本軟體原理是按下「更新資料」後會在本機啟動一個只跑在您電腦上的代理伺服器，並自動安裝一張本機產生的根憑證，藉此攔截原神 webview 對 miHoYo 卡池歷史 API 的請求，所以要在按下更新後再到遊戲內開啟卡池歷史記錄才能攔到，取得網址後拆解參數，參數會用於 miHoYo 原神相關的 API。

**首次/更新流程段：**
> 第一次按下「更新資料」會加載您完整的卡池歷史，這可能需要一些時間，完成後會將資料存放在您的電腦內，這樣下次開啟軟體就不用再花時間等待資料加載。之後想取得新資料按一下「更新資料」即可，軟體會記住先前攔到的網址，能用就直接用、不用每次重新攔截；如果認證過期，軟體會請您再到遊戲開一次卡池歷史頁面以重新取得網址。

**不封號段：**
> 請放心：本軟體不會讀取或竄改任何遊戲檔案、記憶體與遊戲傳輸的資料，只會在 webview 開啟卡池歷史頁面時攔下那一條請求網址，所以不會有被封鎖帳號的風險。如果有被封號，請思考您是不是其他原因被封鎖，不要怪罪我們。

**新增「使用方式」段（放在「下載軟體」段之後）：**
> ## 使用方式
>
> 1. 啟動原神，先別開啟卡池歷史頁面。
> 2. 開啟本軟體並按下「更新資料」，軟體會在背景啟動本機代理伺服器並等候攔截。
> 3. 切回遊戲，到「祈願 → 歷史記錄」開啟卡池歷史頁面。
> 4. 軟體攔到網址後會自動關閉代理、還原系統代理設定並開始抓取資料；之後想再更新只要重複步驟 2，網址未過期就會直接套用。

**「下載軟體」段補述：**
> 軟體在安裝或執行時有可能會被防毒軟體阻擋。原因是本軟體會自行產生並安裝一張本機根憑證、並在按下更新時短暫設置系統代理以攔截原神 webview 的卡池歷史請求──這類行為與惡意程式相似，但本軟體只攔截 `*.hoyoverse.com/getGachaLog` 這一條 API，且憑證只留在您的電腦。如果無法正常執行，請嘗試關閉防毒軟體後再執行看看，本軟體保證無毒。

### English (README_EN.md)

**Intro paragraph (unchanged):**
> I have developed a utility for analyzing gacha history, where all data and numbers are well-organized in a convenient manner.

**How it works:**
> When you press *Update*, the utility starts a local proxy server (running only on your computer) and automatically installs a locally generated root certificate, so it can intercept Genshin Impact's webview request to the miHoYo wish history API. You therefore need to open the wish history page in the game *after* pressing *Update*, so the request can be captured. The captured URL is parsed and the resulting parameters are used to call miHoYo's API.

**First load / update flow:**
> The first time you press *Update*, the utility loads your full gacha history, which may take a while. The data is then stored locally so you don't have to wait again on the next launch. To pull new records, just press *Update*: the utility remembers the previously captured URL and reuses it as long as it's still valid, so you don't have to repeat the capture every time. If the captured URL has expired, the utility will ask you to open the wish history page in the game again to re-capture.

**Not banned:**
> Rest assured: this utility does not read or modify any game file, game memory, or in-game network traffic. It only intercepts the wish history page request that the in-game webview itself makes, so there is no risk of being banned for using it. If you have been banned, it was likely for a different reason. Please do not blame us, thanks.

**New “How to Use” section (placed after Download Software):**
> ## How to Use
>
> 1. Launch Genshin Impact (don't open the wish history page yet).
> 2. Open this utility and press *Update*. The utility will start a local proxy server in the background and wait for the request.
> 3. Switch back to the game and open *Wish → History* to view the wish history page.
> 4. Once captured, the utility automatically shuts down the proxy, restores your system proxy settings, and starts fetching your data. To update again later, just repeat step 2 — the captured URL will be reused if still valid.

**Download Software paragraph:**
> The software may trigger anti-virus software during installation and execution. This is because it generates and installs a local root certificate, and briefly configures a system proxy when you press *Update* to intercept the in-game webview's wish history request — behavior that resembles malware. However, the utility only intercepts the single `*.hoyoverse.com/getGachaLog` endpoint, and the certificate stays on your computer. If the software doesn't function correctly, please try disabling any anti-virus software you have installed. We guarantee this software is safe and virus-free.

### 简体中文 (README_ZH-CN.md)

**介绍段（保留原样）：**
> 我开发了一套用来分析祈愿卡池历史记录的软件，一开启各种数据清清楚楚，不用再手动计算啦！

**原理段：**
> 本软件原理是按下「更新资料」后会在本机启动一个只跑在您电脑上的代理服务器，并自动安装一张本机生成的根证书，藉此拦截原神 webview 对 miHoYo 卡池历史 API 的请求，所以要在按下更新后再到游戏内开启卡池历史记录才能拦到，取得网址后拆解参数，参数会用于 miHoYo 原神相关的 API。

**首次/更新流程段：**
> 第一次按下「更新资料」会加载您完整的卡池历史，这可能需要一些时间，完成后会将资料存放在您的电脑内，这样下次开启软件就不用再花时间等待资料加载。之后想取得新资料按一下「更新资料」即可，软件会记住先前拦到的网址，能用就直接用、不用每次重新拦截；如果认证过期，软件会请您再到游戏开一次卡池历史页面以重新取得网址。

**不封号段：**
> 请放心：本软件不会读取或窜改任何游戏文件、内存与游戏传输的数据，只会在 webview 开启卡池历史页面时拦下那一条请求网址，所以不会有被封锁帐号的风险。如果有被封号，请思考您是不是其他原因被封锁，不要怪罪我们。

**新增「使用方式」段（放在「下载软件」段之后）：**
> ## 使用方式
>
> 1. 启动原神，先别开启卡池历史页面。
> 2. 开启本软件并按下「更新资料」，软件会在后台启动本机代理服务器并等候拦截。
> 3. 切回游戏，到「祈愿 → 历史记录」开启卡池历史页面。
> 4. 软件拦到网址后会自动关闭代理、还原系统代理设定并开始抓取资料；之后想再更新只要重复步骤 2，网址未过期就会直接套用。

**「下载软件」段补述：**
> 软件在安装或运行时有可能会被防毒软件阻挡。原因是本软件会自行生成并安装一张本机根证书、并在按下更新时短暂设置系统代理以拦截原神 webview 的卡池历史请求——这类行为与恶意程序相似，但本软件只拦截 `*.hoyoverse.com/getGachaLog` 这一条 API，且证书只留在您的电脑。如果无法正常运行，请尝试关闭防毒软件后再运行看看，本软件保证无毒。

## 驗收條件

- 三份 README 的介紹四段已替換為新文案，事實與 `lib/state/wish_repository.dart`、`rust/src/api/capture.rs`、`rust/src/mitm.rs` 一致。
- 三份 README 都新增「使用方式 / How to Use」段，位置在「下載軟體 / Download Software」段之後。
- 三份 README 的「下載軟體 / Download Software」段已補上防毒誤報的技術原因。
- 三份 README 沒有殘留「Web Cache」、「自動重新加載」等舊流程描述。
- 其他段落（語言切換、Crowdin badge、文章連結、功能列表、截圖、開發）未被動到。
