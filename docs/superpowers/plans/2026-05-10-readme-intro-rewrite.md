# README Intro Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the intro section of all three README files (zh-TW, en, zh-CN) to reflect the Flutter+Rust rewrite (MITM proxy capture instead of Web Cache reading), add a new "How to Use / 使用方式 / 使用方式" section, and expand the "Download Software" anti-virus warning with the technical reason.

**Architecture:** Pure documentation edit. Three README files share the same structure; each file gets the same set of edits in the same locations. Tasks are split per file so they can be executed independently and reviewed individually.

**Tech Stack:** Markdown (CommonMark, GitHub-rendered).

**Spec:** `docs/superpowers/specs/2026-05-10-readme-intro-rewrite-design.md`

---

## File Structure

| File | Lines changed | Why |
|---|---|---|
| `README.md` (zh-TW) | L7-13 (intro 4 段), L27 (下載段補述), insert new section after L29 | 主語言版本 |
| `README_EN.md` | L7-15 (intro 5→4 paragraphs), L29 (Download warning), insert new section after L31 | English mirror |
| `README_ZH-CN.md` | L7-13 (介绍四段), L27 (下载段补述), insert new section after L29 | 简中 mirror |

Note: README_EN.md's intro is currently 5 paragraphs (L7, L9, L11, L13, L15). The rewrite collapses L9 + L11 ("It works by reading…" + "Variables retrieved…") into one "How it works" paragraph, matching the zh-TW/zh-CN structure of 4 paragraphs.

The new "使用方式 / How to Use" section is inserted **after** the "下載軟體 / Download Software" section (after the GitHub releases link, before "## 功能和待做事項 / ## Functions & To-do List").

---

### Task 1: Rewrite README.md (繁體中文)

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the four intro paragraphs (L7-13)**

Use the Edit tool with `old_string`:

```
我開發了一套用來分析祈願卡池歷史記錄的軟體，一開啟各種數據清清楚楚，不用再手動計算啦！

本軟體原理是讀取原神遊戲 Web Cache 檔案取得卡池歷史記錄頁面網址，所以要先在遊戲內開啟過卡池歷史記錄才能讀取到，取得網址後拆解參數，參數會用於 miHoYo 原神相關的 API。

第一次開啟時會加載您的卡池歷史資料，這可能需要一些時間，完成後會將資料存放在您的電腦內，這樣下次開啟軟體時就不用再花時間等待資料加載了，但要取得新資料要按下更新資料才會更新，如果版本更新了會自動重新加載資料。

請放心：本軟體不會竄改任何遊戲檔案和數據，所以不會有被封鎖帳號的風險。如果有被封號，請思考您是不是其他原因被封鎖，不要怪罪我們。
```

`new_string`:

```
我開發了一套用來分析祈願卡池歷史記錄的軟體，一開啟各種數據清清楚楚，不用再手動計算啦！

本軟體原理是按下「更新資料」後會在本機啟動一個只跑在您電腦上的代理伺服器，並自動安裝一張本機產生的根憑證，藉此攔截原神 webview 對 miHoYo 卡池歷史 API 的請求，所以要在按下更新後再到遊戲內開啟卡池歷史記錄才能攔到，取得網址後拆解參數，參數會用於 miHoYo 原神相關的 API。

第一次按下「更新資料」會加載您完整的卡池歷史，這可能需要一些時間，完成後會將資料存放在您的電腦內，這樣下次開啟軟體就不用再花時間等待資料加載。之後想取得新資料按一下「更新資料」即可，軟體會記住先前攔到的網址，能用就直接用、不用每次重新攔截；如果認證過期，軟體會請您再到遊戲開一次卡池歷史頁面以重新取得網址。

請放心：本軟體不會讀取或竄改任何遊戲檔案、記憶體與遊戲傳輸的資料，只會在 webview 開啟卡池歷史頁面時攔下那一條請求網址，所以不會有被封鎖帳號的風險。如果有被封號，請思考您是不是其他原因被封鎖，不要怪罪我們。
```

- [ ] **Step 2: Expand the Download Software anti-virus paragraph**

Use the Edit tool with `old_string`:

```
軟體在安裝或執行時有可能會被防毒軟體阻擋。如果無法正常執行，請嘗試關閉防毒軟體後再執行看看，本軟體保證無毒。
```

`new_string`:

```
軟體在安裝或執行時有可能會被防毒軟體阻擋。原因是本軟體會自行產生並安裝一張本機根憑證、並在按下更新時短暫設置系統代理以攔截原神 webview 的卡池歷史請求──這類行為與惡意程式相似，但本軟體只攔截 `*.hoyoverse.com/getGachaLog` 這一條 API，且憑證只留在您的電腦。如果無法正常執行，請嘗試關閉防毒軟體後再執行看看，本軟體保證無毒。
```

- [ ] **Step 3: Insert the new 「使用方式」 section after the Download Software section**

Use the Edit tool with `old_string`:

```
<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## 功能和待做事項
```

`new_string`:

```
<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## 使用方式

1. 啟動原神，先別開啟卡池歷史頁面。
2. 開啟本軟體並按下「更新資料」，軟體會在背景啟動本機代理伺服器並等候攔截。
3. 切回遊戲，到「祈願 → 歷史記錄」開啟卡池歷史頁面。
4. 軟體攔到網址後會自動關閉代理、還原系統代理設定並開始抓取資料；之後想再更新只要重複步驟 2，網址未過期就會直接套用。

## 功能和待做事項
```

- [ ] **Step 4: Verify the file contains no leftover stale terms**

Run:

```bash
grep -n "Web Cache\|自動重新加載\|不會竄改任何遊戲檔案和數據" README.md
```

Expected: no output (exit code 1).

Run:

```bash
grep -c "## 使用方式" README.md
```

Expected: `1`

---

### Task 2: Rewrite README_EN.md (English)

**Files:**
- Modify: `README_EN.md`

- [ ] **Step 1: Replace the five intro paragraphs (L7-15) with four paragraphs**

Use the Edit tool with `old_string`:

```
I have developed a utility for analyzing gacha history, where all data and numbers are well-organized in a convenient manner.

It works by reading game web cache file to obtain the wish history website url. Thus, you must start the game and open the wish history page at least once before running this utility.

Variables retrieved from the website will be analyzed and used in an API related to Genshin Impact (from miHoYo).
 
This program loads your gacha history during initial startup, which may take a while. The resulting data will be stored locally to ensure it not take that much time in the next start, after which it will not be updated until you update it manually. The data will also be automatically updated when there is a version update.
 
This program does not tamper with any game resources; thus, there is no risk of being banned for using this software. If you have been banned, it was likely for a different reason. Please do not blame us, thanks.
```

`new_string`:

```
I have developed a utility for analyzing gacha history, where all data and numbers are well-organized in a convenient manner.

When you press *Update*, the utility starts a local proxy server (running only on your computer) and automatically installs a locally generated root certificate, so it can intercept Genshin Impact's webview request to the miHoYo wish history API. You therefore need to open the wish history page in the game *after* pressing *Update*, so the request can be captured. The captured URL is parsed and the resulting parameters are used to call miHoYo's API.

The first time you press *Update*, the utility loads your full gacha history, which may take a while. The data is then stored locally so you don't have to wait again on the next launch. To pull new records, just press *Update*: the utility remembers the previously captured URL and reuses it as long as it's still valid, so you don't have to repeat the capture every time. If the captured URL has expired, the utility will ask you to open the wish history page in the game again to re-capture.

Rest assured: this utility does not read or modify any game file, game memory, or in-game network traffic. It only intercepts the wish history page request that the in-game webview itself makes, so there is no risk of being banned for using it. If you have been banned, it was likely for a different reason. Please do not blame us, thanks.
```

Note: the original lines L12, L14 contain a trailing space (the blank lines between paragraphs). The replacement collapses 5 paragraphs → 4 paragraphs and uses standard blank lines (no trailing space). This is intentional: the trailing-space artifact came from the original 5-paragraph layout and isn't worth preserving.

- [ ] **Step 2: Expand the Download Software anti-virus paragraph**

Use the Edit tool with `old_string`:

```
The software may trigger anti-virus software during installation and execution. If the software doesn't function correctly, please try disabling any anti-virus software you have installed. We guarantee this software is safe and virus-free.
```

`new_string`:

```
The software may trigger anti-virus software during installation and execution. This is because it generates and installs a local root certificate, and briefly configures a system proxy when you press *Update* to intercept the in-game webview's wish history request — behavior that resembles malware. However, the utility only intercepts the single `*.hoyoverse.com/getGachaLog` endpoint, and the certificate stays on your computer. If the software doesn't function correctly, please try disabling any anti-virus software you have installed. We guarantee this software is safe and virus-free.
```

- [ ] **Step 3: Insert the new "How to Use" section after Download Software**

Use the Edit tool with `old_string`:

```
<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## Functions & To-do List
```

`new_string`:

```
<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## How to Use

1. Launch Genshin Impact (don't open the wish history page yet).
2. Open this utility and press *Update*. The utility will start a local proxy server in the background and wait for the request.
3. Switch back to the game and open *Wish → History* to view the wish history page.
4. Once captured, the utility automatically shuts down the proxy, restores your system proxy settings, and starts fetching your data. To update again later, just repeat step 2 — the captured URL will be reused if still valid.

## Functions & To-do List
```

- [ ] **Step 4: Verify the file contains no leftover stale terms**

Run:

```bash
grep -n "web cache\|automatically updated when there is a version update\|does not tamper with any game resources" README_EN.md
```

Expected: no output.

Run:

```bash
grep -c "## How to Use" README_EN.md
```

Expected: `1`

---

### Task 3: Rewrite README_ZH-CN.md (简体中文)

**Files:**
- Modify: `README_ZH-CN.md`

- [ ] **Step 1: Replace the four intro paragraphs (L7-13)**

Use the Edit tool with `old_string`:

```
我开发了一套用来分析祈愿卡池历史记录的软件，一开启各种数据清清楚楚，不用再手动计算啦！

本软件原理是读取原神游戏 Web Cache 文件取得卡池历史记录页面网址，所以要先在游戏内开启过卡池历史记录才能读取到，取得网址后拆解参数，参数会用于 miHoYo 原神相关的 API。

第一次开启时会加载您的卡池历史资料，这可能需要一些时间，完成后会将资料存放在您的电脑内，这样下次开启软件时就不用再花时间等待资料加载了，但要取得新资料要按下更新资料才会更新，如果版本更新了会自动重新加载资料。

请放心：本软件不会窜改任何游戏文件和数据，所以不会有被封锁帐号的风险。如果有被封号，请思考您是不是其他原因被封锁，不要怪罪我们。
```

`new_string`:

```
我开发了一套用来分析祈愿卡池历史记录的软件，一开启各种数据清清楚楚，不用再手动计算啦！

本软件原理是按下「更新资料」后会在本机启动一个只跑在您电脑上的代理服务器，并自动安装一张本机生成的根证书，藉此拦截原神 webview 对 miHoYo 卡池历史 API 的请求，所以要在按下更新后再到游戏内开启卡池历史记录才能拦到，取得网址后拆解参数，参数会用于 miHoYo 原神相关的 API。

第一次按下「更新资料」会加载您完整的卡池历史，这可能需要一些时间，完成后会将资料存放在您的电脑内，这样下次开启软件就不用再花时间等待资料加载。之后想取得新资料按一下「更新资料」即可，软件会记住先前拦到的网址，能用就直接用、不用每次重新拦截；如果认证过期，软件会请您再到游戏开一次卡池历史页面以重新取得网址。

请放心：本软件不会读取或窜改任何游戏文件、内存与游戏传输的数据，只会在 webview 开启卡池历史页面时拦下那一条请求网址，所以不会有被封锁帐号的风险。如果有被封号，请思考您是不是其他原因被封锁，不要怪罪我们。
```

- [ ] **Step 2: Expand the 下载软件 anti-virus paragraph**

Use the Edit tool with `old_string`:

```
软件在安装或运行时有可能会被防毒软件阻挡。如果无法正常运行，请尝试关闭防毒软件后再运行看看，本软件保证无毒。
```

`new_string`:

```
软件在安装或运行时有可能会被防毒软件阻挡。原因是本软件会自行生成并安装一张本机根证书、并在按下更新时短暂设置系统代理以拦截原神 webview 的卡池历史请求——这类行为与恶意程序相似，但本软件只拦截 `*.hoyoverse.com/getGachaLog` 这一条 API，且证书只留在您的电脑。如果无法正常运行，请尝试关闭防毒软件后再运行看看，本软件保证无毒。
```

- [ ] **Step 3: Insert the new 「使用方式」 section after 下载软件**

Use the Edit tool with `old_string`:

```
<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## 功能和待做事项
```

`new_string`:

```
<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## 使用方式

1. 启动原神，先别开启卡池历史页面。
2. 开启本软件并按下「更新资料」，软件会在后台启动本机代理服务器并等候拦截。
3. 切回游戏，到「祈愿 → 历史记录」开启卡池历史页面。
4. 软件拦到网址后会自动关闭代理、还原系统代理设定并开始抓取资料；之后想再更新只要重复步骤 2，网址未过期就会直接套用。

## 功能和待做事项
```

- [ ] **Step 4: Verify the file contains no leftover stale terms**

Run:

```bash
grep -n "Web Cache\|自动重新加载\|不会窜改任何游戏文件和数据" README_ZH-CN.md
```

Expected: no output.

Run:

```bash
grep -c "## 使用方式" README_ZH-CN.md
```

Expected: `1`

---

### Task 4: Cross-file consistency check

**Files:**
- Read-only verification across `README.md`, `README_EN.md`, `README_ZH-CN.md`.

- [ ] **Step 1: Confirm the new section was added (each file gains exactly one H2)**

Run:

```bash
grep -c "^## " README.md README_EN.md README_ZH-CN.md
```

Each file originally has 5 H2 headings (多國語言/下載軟體/功能和待做事項/截圖/開發 and equivalents). After adding `## 使用方式 / ## How to Use`, the count should be `6` per file.

Expected output: each file reports `6`.

- [ ] **Step 2: Confirm the H2 ordering is identical across all three files**

Run:

```bash
grep "^## " README.md
grep "^## " README_EN.md
grep "^## " README_ZH-CN.md
```

Expected order in all three (translations differ but slot order is identical):
1. 多國語言 / Multiple Language / 多国语言
2. 下載軟體 / Download Software / 下载软件
3. 使用方式 / How to Use / 使用方式
4. 功能和待做事項 / Functions & To-do List / 功能和待做事项
5. 截圖 / Screenshot / 截图
6. 開發 / Development / 开发

If any file's order doesn't match, the new section was inserted in the wrong place — fix and re-verify.

- [ ] **Step 3: Confirm `*.hoyoverse.com/getGachaLog` appears once in each file (Download Software paragraph)**

Run:

```bash
grep -c "hoyoverse.com/getGachaLog" README.md README_EN.md README_ZH-CN.md
```

Expected: each file reports `1`.

---

### Task 5: Commit

**Files:**
- All three READMEs (modified).

- [ ] **Step 1: Review the diff one last time**

Run:

```bash
git diff --stat README.md README_EN.md README_ZH-CN.md
git diff README.md README_EN.md README_ZH-CN.md
```

Expected: only the intro section, the Download Software paragraph, and the new How-to-Use section show changes. Nothing else.

- [ ] **Step 2: Stage and commit**

Run:

```bash
git add README.md README_EN.md README_ZH-CN.md
git commit -m "$(cat <<'EOF'
docs(readme): rewrite intro for MITM capture flow + add How-to-Use section

Replace the Web Cache description with the new Flutter+Rust capture
flow (local proxy + locally generated root certificate intercepting
the in-game webview request to *.hoyoverse.com/getGachaLog). Add a
new "使用方式 / How to Use" section, and expand the anti-virus
warning under "Download Software" with the technical reason for
common false positives.

Spec: docs/superpowers/specs/2026-05-10-readme-intro-rewrite-design.md
EOF
)"
```

- [ ] **Step 3: Verify commit landed**

Run:

```bash
git log -1 --stat
```

Expected: one commit touching exactly `README.md`, `README_EN.md`, `README_ZH-CN.md`.
