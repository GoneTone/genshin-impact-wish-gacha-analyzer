# 隱私權政策 Privacy Policy

適用於「祈願卡池分析 for 原神」（套件名稱 `tw.reh.genshin.gacha`）的 Android 版與 Windows 版。

最後更新：2026-11-22

[繁體中文](#繁體中文) | [English](#english)

## 繁體中文

本 App 是玩家自製的非官方工具，與 HoYoverse 無關。開發者沒有架設任何伺服器，也不會收到你的任何資料。

### 存在你裝置上的資料

- 卡池記錄（祈願記錄）、帳號 UID 與你設定的別名。
- 查詢祈願記錄用的網址（含遊戲核發的 authkey；從遊戲取得或你手動輸入），每個 UID 保存最近一次的網址，供下次更新使用。
- App 設定與執行記錄（log）。
- HoYoWiki 的物品資料與圖片快取。
- Android 版：你在 Google 廣告同意視窗的選擇、無線偵錯的配對金鑰（加密保存）。

以上資料存在你的裝置上，在 App 內刪除帳號會一併刪除該帳號的卡池記錄與保存的網址。

- **Android 版**：解除安裝 App 會刪除裝置上的資料。Android 的系統備份可能會把 App 資料（卡池記錄、設定）備份到你自己的 Google 帳號，是否備份由你裝置上的備份設定決定；重新安裝或換新裝置時，系統可能會還原這份備份。加密保存的憑證（例如無線偵錯的配對金鑰）不會備份，還原後需要重新配對。
- **Windows 版**：資料存在 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer`。解除安裝時會詢問是否一併刪除，預設保留；保留的話可以之後自行刪除這個資料夾。解除安裝時一定會嘗試移除本機產生的根憑證（Windows 會跳出一次確認視窗，按「是」才會刪除）並刪除它的私密金鑰資料夾 `%APPDATA%\genshin_impact_wish_gacha_analyzer\ca`，不受上述「是否刪除資料」的選擇影響。

### 會連線的對象

- **HoYoverse 官方伺服器**：用上述網址取得你的祈願記錄。這和你在遊戲內開啟「祈願記錄」頁面時送出的請求相同。
- **HoYoLAB Wiki（HoYoWiki）**：下載角色與武器的名稱、圖示與圖片。只傳送物品名稱或物品 ID 與語言，不包含你的帳號資料。
- **GitHub**：檢查有沒有新版本、取得更新說明。
- **Google AdMob**（只限 Android 版）：在部分頁面的內容之間顯示原生廣告，見下方「廣告」。
- **Google 雲端硬碟**（只在你自己開啟雲端同步時）：把卡池記錄與帳號別名寫入你自己的 Google 雲端硬碟中、只有本 App 能存取的隱藏資料夾（appDataFolder）。查詢祈願記錄用的網址不會上傳。App 只會取得你的 Google 帳號 email 用來顯示「已連結哪個帳號」，以及存取這個資料夾的權限。你可以隨時在設定頁中斷連結，並到 Google 帳號的安全性設定移除授權。

### Android 版取得祈願記錄網址的方式

Android 不允許 App 直接讀取其他 App 的資料。本 App 會在你按下「更新資料」後，透過系統內建的「無線偵錯」（或你授權的 root）讀取手機的系統記錄（logcat），等你在遊戲內開啟「祈願記錄」頁面時，從中找出祈願記錄網址。你也可以改為手動貼上網址。

- 只從更新開始的時間點往後讀，只留下第一筆符合祈願記錄網址的那一行，其餘系統記錄不保存也不上傳；暫存這一行的檔案在取得網址或取消後立即刪除。
- 用完立刻中斷連線；無線偵錯若是本 App 打開的（或剛完成配對），會一併關閉，你原本就開著的會維持開啟。沒有權限關閉時，App 會提醒你自行關閉。
- `WRITE_SECURE_SETTINGS` 權限只用來開關無線偵錯，讓你不用每次手動設定。你可以隨時在設定頁「讀取遊戲記錄」解除配對，同時收回這個權限並刪除配對金鑰。

### 廣告（只限 Android 版）

Android 版會在部分有內容的頁面中，於內容之間穿插 Google AdMob 原生廣告。Windows 版沒有廣告。

- 依 Google 公布的說明，Google Mobile Ads SDK 會自動收集並傳送以下資料給 Google，用於廣告、分析與防止詐騙：裝置的 IP 位址（可能用來推估大致位置）、與廣告的互動（例如 App 啟動、點擊、影片觀看）、效能診斷資訊，以及 Android 廣告 ID、應用程式集 ID 等裝置識別碼。所有資料在傳輸時都經過 TLS 加密。
- 這些資料由 Google 收集與處理，開發者收不到個人資料。詳見 [Google 如何使用合作夥伴網站或應用程式的資訊](https://policies.google.com/technologies/partner-sites)。
- 歐洲經濟區、英國與瑞士的使用者，第一次開啟 App 時會看到 Google 的同意視窗，之後可以在設定頁的「廣告隱私權選項」變更選擇；美國部分州的使用者可以在設定頁的「廣告隱私權選項」選擇退出個人化廣告。拒絕個人化廣告時，仍會顯示非個人化廣告。
- 你可以在 Android 系統設定重設或刪除廣告 ID。
- 廣告內容分級上限為「青少年（T）」。

### Windows 版取得祈願記錄網址的方式

按下「更新資料」後，App 會同時用兩種方式等你在遊戲內開啟「祈願記錄」頁面，先取得網址的那一種為準；你也可以改為手動貼上網址。

- **讀取遊戲的網頁快取**：找出遊戲資料夾（依序參考你在設定指定的資料夾、遊戲的 `output_log.txt`、Windows 登錄檔中的安裝路徑與常見安裝路徑），再讀取遊戲資料夾內 `GenshinImpact_Data\webCaches` 的網頁快取，找出新出現的祈願記錄網址。
- **本機攔截**：在你的電腦上啟動一個只聽本機（`127.0.0.1`）的攔截程式，暫時把目前使用者的系統代理設定指向它，並在目前使用者的根憑證存放區安裝一張在本機產生的根憑證（第一次安裝時 Windows 會跳出一次確認視窗）。攔截期間經過系統代理的網路流量會由這個本機程式轉送；它只讀取遊戲對 HoYoverse 祈願記錄 API 送出的那一條請求來取得網址，其餘流量不記錄、不修改，原樣轉送。攔截期間經過系統代理的 HTTPS 連線會在你的電腦上先解密、再重新加密後轉送；解密後的內容不會被儲存或上傳。

- 除了上述 `output_log.txt` 與網頁快取之外不讀取其他遊戲檔案，不修改任何遊戲檔案，也不讀取遊戲記憶體。
- 攔截只在更新期間進行，取得網址或取消後立即停止並還原原本的系統代理設定；若 App 意外結束而留下代理設定，下次啟動時會自動清除。

### 不會做的事

- 除了 Android 版的廣告（見上方「廣告」），沒有其他分析或追蹤工具；開發者不會販售你的資料。
- 執行記錄（log）只保留最近 7 天，寫入前會遮蔽網址中的 authkey 等參數與電腦的使用者名稱；只有在你自己匯出或分享時才會離開裝置。

### 刪除你的資料

「祈願卡池分析 for 原神」（Wish Analyzer for Genshin）的開發者沒有伺服器，不保存你的任何資料；你的資料只在你的裝置與你自己的 Google 雲端硬碟裡，可以照以下步驟自行刪除：

1. **刪除單一帳號的資料**：在 App 的「設定」→「帳號管理」，點該 UID 右邊的 ⋮ →「移除」，輸入 UID 確認後按「刪除」。有開雲端同步的話，勾選「同時從雲端同步資料移除此帳號」會在下次同步時一併刪除雲端硬碟中這個帳號的資料。
2. **刪除裝置上的所有資料**：解除安裝 App（Windows 版解除安裝時選擇一併刪除資料）。也可以在「設定」→「資料管理」按「清除所有資料」刪除所有帳號的卡池記錄、在「設定」→「Logs 偵錯」按「清除所有 logs」刪除執行記錄、在「設定」→「圖片快取」按「清除詳情圖快取」刪除物品詳情圖片。
3. **刪除雲端硬碟上的所有同步資料**：在電腦上開啟 Google 雲端硬碟網頁版 →「設定」→「管理應用程式」，找到本 App →「選項」→「刪除隱藏的應用程式資料」。之後可以到 Google 帳號的「安全性」→「第三方應用程式和服務」移除本 App 的存取權。
4. **廣告資料（只限 Android 版）**：AdMob 收集的資料由 Google 依其隱私權政策處理與保留，開發者無法刪除；你可以在 Android 系統設定重設或刪除廣告 ID。

以上步驟會刪除對應資料，開發者沒有另外保留任何副本。Android 系統備份到你 Google 帳號中的副本，由你在 Google 帳號中自行管理。

### 兒童

本 App 不以兒童為對象。

### 聯絡方式

https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/issues

## English

This app is an unofficial fan-made tool and is not affiliated with HoYoverse. The developer runs no server and receives none of your data.

### Data stored on your device

- Wish history (banner records), account UIDs and the aliases you set.
- The URL used to query your wish history (it contains the authkey issued by the game; taken from the game or a URL you enter). The most recent URL is kept for each UID for the next update.
- App settings and logs.
- HoYoWiki item data and the image cache.
- Android: your choices in Google's ad consent form, and the wireless debugging pairing key (stored encrypted).

This data is stored on your device. Deleting an account in the app removes that account's records and its saved URL.

- **Android**: uninstalling the app removes the data on the device. Android's system backup may back up the app data (wish history, settings) to your own Google account, depending on your device's backup setting, and may restore it when you reinstall or set up a new device. Encrypted credentials (such as the wireless debugging pairing key) are not backed up; after a restore you need to pair again.
- **Windows**: the data is stored in `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer`. The uninstaller asks whether to delete it and keeps it by default; you can delete that folder yourself later. Uninstalling always tries to remove the locally generated root certificate (Windows asks you to confirm once; it is deleted only if you choose Yes) and deletes its private key folder `%APPDATA%\genshin_impact_wish_gacha_analyzer\ca`, whatever you choose about the data.

### Services the app connects to

- **HoYoverse official servers**: to fetch your wish history with the URL above. This is the same request the game sends when you open the Wish History page.
- **HoYoLAB Wiki (HoYoWiki)**: to download character and weapon names, icons and images. Only item names or item IDs and the language are sent, never your account data.
- **GitHub**: to check for new versions and fetch release notes.
- **Google AdMob** (Android only): to show native ads between the content of some pages; see "Ads" below.
- **Google Drive** (only if you turn on cloud sync yourself): the app writes your wish history and account aliases to a hidden folder in your own Google Drive that only this app can access (appDataFolder). The wish history URL is never uploaded. The app only gets your Google account email, to show which account is linked, and access to that folder. You can unlink at any time in Settings and remove the access in your Google Account security settings.

### How the Android version gets the wish history URL

Android doesn't let apps read other apps' data. After you tap "Update", the app reads the phone's system log (logcat) through Android's built-in Wireless debugging (or root, if you grant it) and waits for you to open the Wish History page in the game to find the wish history URL. You can also paste the URL manually instead.

- It reads only from the moment the update starts and keeps only the first line that matches the wish history URL; no other system log content is kept or uploaded. The temporary file holding that line is deleted as soon as the URL is found or you cancel.
- It disconnects right away when done and turns wireless debugging off again if the app turned it on (or you just paired); if you already had it on, it stays on. If the app has no permission to turn it off, it reminds you to turn it off yourself.
- The `WRITE_SECURE_SETTINGS` permission is used only to turn wireless debugging on and off, so you don't have to set it up each time. You can remove the pairing at any time under "Game Log Access" in Settings, which also revokes this permission and deletes the pairing key.

### Ads (Android only)

The Android version shows Google AdMob native ads between the content of some pages that have content. The Windows version has no ads.

- According to Google's disclosure, the Google Mobile Ads SDK automatically collects and sends the following data to Google for advertising, analytics and fraud prevention: the device's IP address (which may be used to estimate its general location), interactions with ads (such as app launches, taps and video views), performance diagnostics, and device identifiers such as the Android advertising ID and app set ID. All of it is encrypted in transit with TLS.
- This data is collected and processed by Google; the developer does not receive personal data. See [How Google uses information from sites or apps that use our services](https://policies.google.com/technologies/partner-sites).
- Users in the European Economic Area, the UK and Switzerland see Google's consent form the first time they open the app, and can change their choice later under "Ad privacy options" in Settings. Users in some US states can opt out of personalized ads under "Ad privacy options" in Settings. If you decline personalized ads, non-personalized ads are still shown.
- You can reset or delete your advertising ID in Android's system settings.
- Ad content is limited to the "Teen (T)" rating.

### How the Windows version gets the wish history URL

When you click "Update", the app waits in two ways at once for you to open the Wish History page in the game, and uses whichever gets the URL first. You can also paste the URL manually instead.

- **Reading the game's web cache**: the app finds the game folder (checking, in order, the folder you set in Settings, the game's `output_log.txt`, the install paths in the Windows registry and common install paths), then reads the web cache under `GenshinImpact_Data\webCaches` in the game folder to find a newly added wish history URL.
- **Local interception**: the app starts an interception helper on your computer that listens only locally (`127.0.0.1`), temporarily points the current user's system proxy setting at it, and installs a root certificate generated on your computer into the current user's root certificate store (Windows asks you to confirm once, the first time). During interception, network traffic that goes through the system proxy is relayed by this local helper; it reads only the one request the game sends to the HoYoverse wish history API to get the URL, and all other traffic is relayed untouched, without being recorded or modified. During interception, HTTPS connections that go through the system proxy are decrypted on your computer and re-encrypted before being forwarded; the decrypted content is never saved or uploaded.

- Apart from that `output_log.txt` and the web cache it reads no game files, it never modifies game files or reads game memory.
- Interception runs only during an update; it stops and restores your original system proxy setting as soon as the URL is found or you cancel. If the app exits unexpectedly and leaves the proxy setting behind, it is cleared automatically the next time the app starts.

### What the app does not do

- Apart from the ads in the Android version (see "Ads" above), no analytics or tracking tools; the developer never sells your data.
- Logs are kept for the last 7 days only, with the authkey and similar URL parameters and your computer's user name masked before they are written; they leave your device only when you export or share them yourself.

### Deleting your data

The developer of Wish Analyzer for Genshin (祈願卡池分析 for 原神) runs no server and keeps none of your data. Your data is only on your device and in your own Google Drive, and you can delete it yourself:

1. **Delete one account's data**: in the app, go to Settings → Account management, tap ⋮ next to the UID → Remove, type the UID to confirm and tap Delete. If cloud sync is on, checking "Also remove this account from cloud sync data" also deletes that account's data from your Google Drive at the next sync.
2. **Delete all data on the device**: uninstall the app (on Windows, choose to delete the data when uninstalling). You can also use Settings → Data management → Clear all data to delete every account's records, Settings → Debug logs → Clear all logs to delete the logs, and Settings → Image cache → Clear detail images to delete the item detail images.
3. **Delete all synced data in Google Drive**: open Google Drive on the web on a computer → Settings → Manage apps, find this app → Options → Delete hidden app data. You can then remove the app's access under Security → Third-party apps & services in your Google Account.
4. **Ad data (Android only)**: data collected by AdMob is processed and retained by Google under its own privacy policy; the developer cannot delete it. You can reset or delete your advertising ID in Android's system settings.

These steps delete the data; the developer keeps no other copy. Copies backed up to your Google account by Android's system backup are managed by you in your Google account.

### Children

This app is not directed at children.

### Contact

https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/issues
