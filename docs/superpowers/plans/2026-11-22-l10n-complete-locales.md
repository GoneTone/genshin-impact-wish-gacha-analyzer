# 多國語言補齊與術語表（子專案 11）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 31 種語言全部有完整翻譯，遊戲用語照官方；同時移植鳴潮第 49 節的複數、不支援語言改回英文、挪威文、由右往左、長字串溢出、Android 原生字串與 Crowdin 設定。

**Architecture:** 先定術語表與繁中原文，再改語言解析程式，接著補既有語言、平行翻譯 22 種空殼語言，最後補 Android 原生字串、RTL 與溢出修正。每一段都以鳴潮對應 commit 為範本（`git -C ../wuthering-waves-convene-gacha-analyzer show <commit>`），實際位置以原神程式為準。

**Tech Stack:** Flutter gen-l10n（ARB、ICU plural）、Riverpod、Android `res/values-*/strings.xml`、Crowdin `crowdin.yml`。

**Spec:** `docs/superpowers/specs/2026-11-22-l10n-complete-locales-design.md`

## Global Constraints

- 原文是 `lib/l10n/app_zh.arb`（`@` 說明當語境），`app_en.arb` 當參考。所有 Flutter／Dart 指令用 `fvm`。
- 術語表既有 9 欄（zh_Hant、zh_Hans、en、ja、es、fr、pt、th、vi）內容不改，只新增欄位與段落。
- 遊戲有出的語言（App 有 ARB 的）：`zh`、`zh_Hans`、`en`、`ja`、`ko`、`de`、`fr`、`es`、`pt`／`pt_BR`（照官方 `pt-pt`）、`ru`、`th`、`vi`、`it`、`tr`。遊戲用語逐字照官方。
- 遊戲沒出的語言：`af`、`ar`、`ca`、`cs`、`da`、`el`、`fi`、`he`、`hu`、`nl`、`no`、`pl`、`ro`、`sr`、`sv`、`uk`。卡池名稱與短名、側欄祈願／頌願區塊標題、物品類型、句子裡提到的遊戲選單與頁面用英文官方名稱；App 自己的敘述與標籤照常翻譯；需要詞尾變化時改寫句子，不把詞尾黏在英文名稱後面。
- 翻譯者欄位 `localeTranslator`：`zh`、`zh_Hans` 空白；其他語言固定 `<a href="https://claude.com/claude-code">Claude Code</a>`。`@@locale` 不帶地區碼以外的寫法照現有檔（例如 `pt_BR`）。
- 省略號一律半形 `...`（含 CJK）。中日文與英數字之間空一格。CJK 文字用全形標點。
- 複數：只有單複數兩類且 `one` 不含 0 的語言用 `=1{}`（en、de、es、pt、pt_BR、it、ca、nl、af、da、sv、no、fi、el、hu）；法文用 `one{}`（0 和 1 都算單數）；`ru`、`uk`、`sr`、`pl`、`cs`、`ro`、`ar`、`he` 照 CLDR 用 `one`／`two`／`few`／`many`，不可改成 `=1`；`zh`、`zh_Hans`、`ja`、`ko`、`th`、`vi`、`tr` 沒有單複數之分，不用 plural。型別是 `String` 的佔位符不能用 plural。標籤寫法（「紀錄：3」）與單複數同形的字不用改。
- Android 原生字串資料夾：希伯來文 `values-iw`、挪威文 `values-nb`、巴西葡文 `values-pt-rBR`、葡萄牙文 `values-pt`、繁中 `values-zh-rTW`、簡中 `values-zh-rCN`、英文 `values/`；單、雙引號加反斜線跳脫。
- 送給系統的挪威文代碼是 `nb`；從系統讀回時 `nb`、`nn`、`no` 都對到 App 的 `no`。
- Windows 版面與行為不得改變（RTL 修正只影響由右往左的語言）。
- log 訊息一律英文；commit message 英文 conventional commits，結尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；commit 用 PowerShell 執行（GPG 簽章）。
- 每個 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。

## Review Focus

1. 系統語言是 App 完全不支援的語言（例如印尼文 `id`）：應顯示英文，不能掉到字母排序第一個的南非語。→ Task 3 測試。
2. 系統語言是書面挪威語 `nb-NO`（Android、Windows 的實際回報）：應顯示挪威文。→ Task 3 測試。
3. 俄文、烏克蘭文數量為 21、阿拉伯文數量為 2：要走 CLDR 的 `one`／`two` 類別，不能被 `=1` 漏掉。→ Task 4 與 Task 5 的 `plural_forms_test`。
4. 法文、義大利文 `strings.xml` 裡的撇號（`l'appareil`）沒跳脫會讓 release 建置失敗。→ Task 6 測試掃描未跳脫的引號。
5. 阿拉伯文介面下「5 / 80」與遮罩 UID 不能被雙向演算法倒過來。→ Task 7 `rtl_layout_test`。

---

### Task 1: 術語表新增 ko、de、ru、it、tr 與頌願的官方用語

**Files:**
- Modify: `docs/術語表.md`

**Interfaces:**
- Produces: 術語表新段落「其他語言的官方用語」，Task 4、Task 5 的翻譯以它為唯一依據。

- [ ] **Step 1: 取得祈願官方用語**：把 `https://gs.hoyoverse.com/genshin/event/e20190909gacha-v3/index.html` 與它載入的 `bundle_*.js` 下載到 scratchpad 的新空資料夾，只當資料讀、不執行。從 bundle 取出 15 種語言（`zh-cn`、`zh-tw`、`en-us`、`ja-jp`、`ko-kr`、`de-de`、`fr-fr`、`es-es`、`pt-pt`、`ru-ru`、`th-th`、`vi-vn`、`id-id`、`it-it`、`tr-tr`）的卡池名稱（`key:"100"/"200"/"301"/"302"/"500"` 對應新手、常駐、角色活動、武器活動、集錄）與頁面文字（祈願歷史紀錄、類型、名稱、祈願類型、時間、角色、武器）。拿 `en-us` 對照鍵名確認每個值的意思。
- [ ] **Step 2: 取得頌願官方用語**：在頌願頁 `https://gs.hoyoverse.com/genshin/event/e20250716gacha/index.html` 的 bundle／vendors 裡找 mi18n 專案名稱，組出 `https://webstatic-sea.hoyoverse.com/admin/mi18n/...` 語系檔網址，取 `beyond_gacha_type_1000`、`beyond_gacha_type_2000` 等鍵在上述語言的值。**找不到時停下來請使用者**在遊戲裡重新打開頌願紀錄頁，用 App 擷取到的網址在瀏覽器開啟，從開發者工具的網路請求取得語系檔（使用者 2026-11-22 已同意）。不要自動操作遊戲。
- [ ] **Step 3: 核對既有 9 欄**：只比對、不改。若官方值和既有欄位不同，記在回報裡交給控制者判斷，不動表格。
- [ ] **Step 4: 寫入術語表**：照鳴潮 `docs/術語表.md` 的格式加一段「## 其他語言的官方用語」：開頭一段說明來源網址與擷取日期（2026-11-22）、遊戲沒出的語言用英文官方名稱的規則（照 Global Constraints 的那條寫）、`pt_BR` 與 `pt` 都跟官方 `pt-pt`；表格欄位 `en | ko | de | ru | it | tr`，列出卡池名稱（含 2 個頌願）、祈願、頌願、祈願歷史紀錄、類型、名稱、祈願類型、時間、角色、武器。Android 系統用語（「無線偵錯」「使用配對碼配對裝置」）另列一張表，涵蓋全部 31 種語言，值沿用 `app_en.arb` 等既有語言引導頁的寫法與各語言 Android 官方譯名。
- [ ] **Step 5: Commit**

```powershell
git add docs/術語表.md
git commit -m "docs(glossary): add official game terms for ko, de, ru, it and tr"
```

### Task 2: 鳴潮後續文案修正在原神的適用性

**Files:**
- Modify: `lib/l10n/app_zh.arb` 與既有 8 個有翻譯的 ARB（只在適用時）
- Modify: `docs/superpowers/specs/2026-11-22-l10n-complete-locales-design.md`（附錄）

**Interfaces:**
- Produces: 定稿的繁中原文，Task 4、Task 5 以它翻譯。

- [ ] **Step 1: 逐一判斷** 鳴潮 `337ce7d`、`6b0978e`、`307a45e`、`08bb4ab`、`8dbb5e9`、`a53f4f0`：看 `git show` 的繁中改動，在原神 `app_zh.arb` 找對應字串。原神已是修正後的說法、或功能不存在 → 不適用；仍是舊說法 → 適用，照鳴潮的方向改繁中原文與既有 8 種語言（zh_Hans、en、ja、es、fr、pt_BR、th、vi），用語換成原神的（喚取→祈願）。`a53f4f0` 若原神該 key 只缺在空殼語言，留給 Task 5。
- [ ] **Step 2: 附錄記錄**：在 spec 附錄加「鳴潮後續文案修正」小節，每個 commit 一行：適用／不適用與理由。
- [ ] **Step 3: 驗證**：`fvm flutter gen-l10n`、analyze、test 全綠（有測試寫死舊字串就照新字串改）。
- [ ] **Step 4: Commit**：`fix(l10n): carry over the later wording fixes from the sister project`（全部不適用時只提交附錄，訊息用 `docs(spec): note which later wording fixes apply`）。

### Task 3: 不支援語言改回英文與挪威文對應

**Files:**
- Modify: `lib/state/localization_metadata.dart`（`localeListResolution`）
- Modify: `lib/services/android/app_prefs_platform.dart`（`systemLocaleTagOf`、`languagePreferenceOfSystemTag`）
- Test: `test/l10n/locale_metadata_test.dart`、`test/services/android/app_prefs_platform_test.dart`

**Interfaces:**
- Produces: `localeListResolution(List<Locale>?, Iterable<Locale>) -> Locale?` 在清單為空或整份對不上時回 `Locale('en')`（`en` 在支援清單中時）；`nb`／`nn` 視同 `no`。`systemLocaleTagOf(LocaleLanguage('no')) == 'nb'`。

範本：鳴潮 `cde6409`（解析）與 `0069630`（挪威文，程式與測試部分；`locales_config.xml`、`crowdin.yml` 留給 Task 5、Task 6）。

- [ ] **Step 1: 寫失敗測試**（`locale_metadata_test.dart`）：
  - `localeListResolution([Locale('id')], supported)` 回 `Locale('en')`，其中 `supported` 是以 `af` 開頭、含 `en` 的清單。
  - `localeListResolution([], supported)` 與 `localeListResolution(null, supported)` 回 `Locale('en')`。
  - `localeListResolution([Locale('nb','NO')], supportedWithNo)` 與 `[Locale('nn')]` 都回 `Locale('no')`。
  - 既有 `zh-Hant`、`zh-TW`、`zh-CN` 案例維持不變。
- [ ] **Step 2: 寫失敗測試**（`app_prefs_platform_test.dart`）：`systemLocaleTagOf(const LocaleLanguage('no')) == 'nb'`；`languagePreferenceOfSystemTag('nb', released)` 與 `('no', released)` 都回 `LocaleLanguage('no')`（`released` 含 `Locale('no')`）。
- [ ] **Step 3: 確認失敗**：`fvm flutter test test/l10n/locale_metadata_test.dart test/services/android/app_prefs_platform_test.dart` → FAIL。
- [ ] **Step 4: 實作**：照鳴潮兩個 commit 的寫法改；dartdoc 同步更新映射說明。
- [ ] **Step 5: 確認通過** 同上指令 → PASS；再跑全部測試。
- [ ] **Step 6: Commit**：`fix(l10n): fall back to English and match Norwegian Bokmal to Norwegian`。

### Task 4: 既有 9 種語言補齊、照官方用語與複數

**Files:**
- Modify: `lib/l10n/app_zh_Hans.arb`、`app_en.arb`、`app_ja.arb`、`app_es.arb`、`app_fr.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`
- Create: `test/l10n/plural_forms_test.dart`
- Create（不進版控）：`<SDD 工作區>/check_arb.py`

**Interfaces:**
- Produces: `check_arb.py <arb 路徑>...`：對每個檔檢查 (1) key 集合與 `app_zh.arb` 相同；(2) 每個字串的 `{佔位符}` 名稱集合與 ICU 參數名稱和範本一致（plural 的分支內容可不同）；(3) `localeTranslator` 照 Global Constraints；(4) `@@locale` 和檔名一致；(5) 遊戲沒出的語言不含 CJK 字元（`[぀-ヿ一-鿿]`）。全部通過印 `OK <檔名>`，否則列出問題並以非 0 結束。Task 5 沿用。

範本：鳴潮 `4a23e4c`（英文複數、核心語言缺漏）、`46ae22d`（數量為 1 的詞形）、`a11352c`／`56ec259`（照官方用語）。

- [ ] **Step 1: 寫檢查腳本** 到 SDD 工作區，對 9 個檔執行，記下目前問題（預期 `app_zh_Hans.arb` 缺 1 個 key）。
- [ ] **Step 2: 寫失敗測試** `plural_forms_test.dart`：用 `lookupAppLocalizations(Locale(...))` 取實例，抽查數量相關字串（例如抽數、相對時間「N 天前」、匯入確認的帳號數與紀錄數），斷言 `en` 在 1 時是單數（不含 `1 pulls`、`1 days`、`1 accounts`）、2 時是複數；`fr` 在 1 時是單數。挑原神實際有 `int`／`num` 佔位符的 key，key 名稱照 `app_zh.arb`。
- [ ] **Step 3: 確認失敗**：`fvm flutter test test/l10n/plural_forms_test.dart` → FAIL。
- [ ] **Step 4: 修正 8 個檔**：補 `app_zh_Hans.arb` 缺的 key；卡池名稱、祈願／頌願、頁面與欄位用語逐字對照 `docs/術語表.md`；數字後面接的字會因 1 而變的字串改成 ICU plural（規則見 Global Constraints；標籤寫法「紀錄：3」、單複數同形不改）。
- [ ] **Step 5: 驗證**：`check_arb.py` 對 9 個檔全 `OK`；`fvm flutter gen-l10n`；`plural_forms_test` PASS；全部測試 PASS（寫死舊英文字串的測試照新字串改）。
- [ ] **Step 6: Commit**：`fix(l10n): pluralise counts and use the official game terms in the core locales`。

### Task 5: 翻譯 22 種空殼語言

**Files:**
- Modify: `lib/l10n/app_{af,ar,ca,cs,da,de,el,fi,he,hu,it,ko,nl,no,pl,pt,ro,ru,sr,sv,tr,uk}.arb`
- Modify: `android/app/src/main/res/xml/locales_config.xml`
- Modify: `test/l10n/plural_forms_test.dart`

**Interfaces:**
- Consumes: Task 1 術語表、Task 2 定稿原文、Task 4 `check_arb.py`。
- Produces: 31 種語言全部「已釋出」（`releasedLocalesProvider` 回傳 31 個）。

**執行方式（控制者裁定）**：這個任務由控制者平行派出翻譯子代理，每個只寫自己負責的 ARB、不 commit；全部回來後由一個整合子代理（或控制者）跑檢查、更新 `locales_config.xml` 與測試、提交。分組：`de/nl/af`、`da/sv/no`、`fi/hu/el`、`ru/uk/sr`、`pl/cs/ro`、`it/ca/pt`、`ar/he`、`ko/tr`。派工指示用中文寫，要求子代理用中文回報。

- [ ] **Step 1: 寫翻譯說明**（SDD 工作區 `translation-guide.md`，中文）：原文與參考檔、術語表路徑與遊戲有出／沒出兩類規則、複數規則、引號與空格規則、省略號、翻譯者欄位、`@` metadata 照 `app_en.arb` 的結構但說明不必翻、完成後自己跑 `check_arb.py`。
- [ ] **Step 2: 平行派出 8 個翻譯子代理**，每個回報各檔 `check_arb.py` 結果。
- [ ] **Step 3: 整合驗證**：22 個檔 `check_arb.py` 全 `OK`；`fvm flutter gen-l10n` 無警告。
- [ ] **Step 4: 擴充 `plural_forms_test`**：加 `ru` 在 1、2、5、21 時分別是 `one`、`few`、`many`、`one` 的詞形；`ar` 在 2 時用 `two` 的詞形；`de` 在 1 時單數。
- [ ] **Step 5: 更新 `locales_config.xml`**：跑 `fvm flutter test test/l10n/android_locales_config_test.dart`，照失敗訊息列出的 31 個標籤更新（挪威文是 `nb`，來自 Task 3）。
- [ ] **Step 6: 全部測試**：`fvm flutter test` → `All tests passed!`。此時 `phone_layout_pages_test` 仍只跑原本語言，溢出留給 Task 8。
- [ ] **Step 7: Commit**：`feat(l10n): translate the app into 22 more languages`。

### Task 6: Android 原生字串與 Crowdin

**Files:**
- Create: `android/app/src/main/res/values-<code>/strings.xml`（每種還沒有的語言）
- Modify: `test/l10n/android_locales_config_test.dart`
- Modify: `crowdin.yml`

範本：鳴潮 `d6bf944`、`0069630`（`crowdin.yml` 的 `"no": nb`）。

- [ ] **Step 1: 寫失敗測試**（照搬鳴潮擴充後的 `android_locales_config_test.dart`，路徑與套件名換成原神）：
  - `locales_config.xml` 每個標籤都有對應資料夾的 `strings.xml`（`zh-Hant`→`values-zh-rTW`、`zh-Hans`→`values-zh-rCN`、`en`→`values`、`he`→`values-iw`、`nb`→`values-nb`、`pt-BR`→`values-pt-rBR`、其他 `values-<code>`）。
  - 每個 `strings.xml` 的字串名稱集合與 `values/strings.xml` 相同。
  - 每個 `strings.xml` 不含未跳脫的 `'` 或 `"`（字串內容裡的引號前面必須是 `\`）。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/l10n/android_locales_config_test.dart` → FAIL（缺 22 個資料夾）。
- [ ] **Step 3: 建立字串檔**：`app_name` 用各語言 ARB 的 `appName`；其餘照 `values/strings.xml` 的 16 個字串翻譯，系統用語照術語表 Android 那張表。
- [ ] **Step 4: 更新 `crowdin.yml`**：照鳴潮加一組 `strings.xml`（原文 `values-zh-rTW/strings.xml`、輸出 `values-%two_letters_code%`、`languages_mapping` 對 zh-CN／pt-BR／he／`"no": nb`、`translation_replace` 把 `values-en/` 換成 `values/`）。
- [ ] **Step 5: 驗證**：測試 PASS；`fvm flutter build apk --release --dart-define-from-file=secrets/cloud_sync_defines.json --dart-define-from-file=secrets/ads_defines.json` 成功（確認 aapt2 接受所有字串檔）。
- [ ] **Step 6: Commit**：`feat(l10n): translate the Android launcher name and pairing notification`。

### Task 7: 由右往左版面

**Files:**
- Modify: 鳴潮 `f87c2a4` 改到的元件在原神的對應檔（`cloud_sync_section.dart`、`pity_card.dart`、`stat_card.dart`、`timeline_horizontal.dart`、`timeline_vertical.dart`、`pager.dart`、`sortable_table.dart`、`gacha_item_detail_dialog.dart`、`gallery_chip_bar.dart`、`zoomable_image_overlay.dart`、`distribution_legend.dart`、`scroll_affordance.dart`、`uid_indicator.dart`），以實際有寫死 left／right 的地方為準
- Create: `test/widgets/rtl_layout_test.dart`

- [ ] **Step 1: 寫失敗測試**（以阿拉伯文 `Locale('ar')`，照鳴潮 `rtl_layout_test.dart` 的案例換成原神元件）：卡片彩色邊條在右側；進度條從右邊開始；垂直時間軸軸線與圓點在同一側；水平捲動區起點邊緣在右；比例數字（「5 / 80」）與遮罩 UID 的 `Text` 是 `TextDirection.ltr`；HoYoWiki 說明文字外層是 `Directionality(ltr)`。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/widgets/rtl_layout_test.dart` → FAIL。
- [ ] **Step 3: 修正**：`Border(left:)`→`BorderDirectional(start:)`、`Alignment.centerLeft`→`AlignmentDirectional.centerStart`（漸層 begin／end 同理）、`Positioned(left:)`→`PositionedDirectional(start:)`、`ScrollSide` 改 `start`／`end`、比例數字與 UID 固定 `TextDirection.ltr`、遊戲資料文字包 `Directionality(textDirection: TextDirection.ltr)`。
- [ ] **Step 4: 驗證**：RTL 測試 PASS；全部測試 PASS（由左往右的既有版面測試不變，證明 Windows 與其他語言不受影響）。
- [ ] **Step 5: Commit**：`fix(ui): mirror correctly in right-to-left languages`。

### Task 8: 長翻譯在手機不溢出

**Files:**
- Modify: `test/pages/phone_layout_pages_test.dart`
- Modify: 測試抓到溢出的元件（鳴潮 `7370042` 是 `distribution_legend.dart` 改用 `CompactLegendRow`、`contributors_page.dart` 改 `Wrap`、`settings_page.dart`）

- [ ] **Step 1: 改測試**：「1.3 倍字級不溢出」改成對 `AppLocalizations.supportedLocales` 每種語言都跑，頁面清單加上設定頁（照鳴潮 `7370042` 的寫法）。
- [ ] **Step 2: 執行**：`fvm flutter test test/pages/phone_layout_pages_test.dart`，記下失敗的語言與元件。
- [ ] **Step 3: 修正**：照鳴潮的修法處理（數值放不下時換行靠右用 `CompactLegendRow`、整列過寬用 `Wrap`）；只在手機版面生效的修正用既有的 `isCompactLayout` 分支，不改電腦版。
- [ ] **Step 4: 驗證**：版面測試 PASS；全部測試 PASS。
- [ ] **Step 5: Commit**：`fix(ui): keep long translations from overflowing on phones`。

### Task 9: 驗收與記錄

**Files:**
- Modify: `docs/superpowers/specs/2026-11-22-l10n-complete-locales-design.md`（附錄、狀態）

- [ ] **Step 1: 模擬器**（`wuwa_api37`，debug 版，透過 device 面板）：`adb shell cmd locale set-app-locales tw.reh.genshin.gacha --locales <code>` 依序切 `ar`（由右往左：卡片邊條、時間軸、比例數字、UID）、`de`（長字串）、`ko`（卡池名稱與術語表一致）、`nb`（顯示挪威文）、`id`（顯示英文）；看一種新語言的啟動器名稱與無線偵錯配對通知。debug 版的 AdMob 驗證器浮層先按 Dismiss。測完 `--locales ''` 還原。
- [ ] **Step 2: Windows**：先備份整個 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer`，把 `shared_preferences.json` 的 `flutter.pref.locale` 改成 `ar` 啟動看由右往左版面，驗完還原。需要實體輸入時先取得使用者同意。
- [ ] **Step 3: 附錄**：寫入自動化結果、模擬器與 Windows 結果、術語表每個新增詞的來源；狀態改為「已完成」。
- [ ] **Step 4: Commit**：`docs(spec): record sub-project 11 verification results`。
