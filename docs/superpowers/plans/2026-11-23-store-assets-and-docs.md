# 子專案 13：授權頁、README 與主題圖片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 補上開放原始碼授權頁、四種語言 README 的 Android 說明，以及 Play 商店主題圖片。

**Architecture:** 三個獨立任務，都是把鳴潮（`E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`）已經做過的改動搬過來，只換術語。授權頁照鳴潮 `7898319`；主題圖片照鳴潮 `tool/generate_feature_graphic.py`；README 照鳴潮 `c5171d6`、`897d15c`，以及鳴潮 `docs/Android移植筆記.md` 第 56 節。

**Tech Stack:** Flutter（FVM）、Riverpod、gen-l10n；Python 3（Pillow 12、numpy 2，已安裝）。

**Spec:** `docs/superpowers/specs/2026-11-23-store-assets-and-docs-design.md`

## Global Constraints

- 分支 `feat/android`，不 push、不開 PR。
- commit 用 PowerShell（GPG 簽章），英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 提交前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。
- CJK 文字用全形標點；省略號一律半形 `...`。
- 所有宣告都要有一行 `///` dartdoc；Python 函式寫 docstring（照鳴潮）。
- 偏離鳴潮的寫法前要先停下來回報，不要自己改寫。
- 不放截圖、不加下載徽章、不在 README 頂端放主題圖片（spec 把這些排到之後）。

## Review Focus

- 授權頁開在巢狀 Navigator 裡時沒有蓋住整個畫面：Task 1 用 `useRootNavigator: true`，並在 Windows 和 Android 上看過畫面。
- 測試環境沒有 override `appVersionProvider` 時會丟 `UnimplementedError`：Task 1 的測試要 override，並斷言授權頁顯示該版本字串。
- 主題圖片的日文、簡中標語缺字（豆腐字）或超出右邊界：Task 2 產生後要用眼睛看四張圖。
- README 只改了繁中，其他三種語言漏改：Task 3 四個檔案的段落結構要一致。
- README 寫了原神 Android 版沒有的讀取方式或功能：Task 3 每一條都要對照原神的程式與 ARB，不能照抄鳴潮。

---

### Task 1: 開放原始碼授權頁

**Files:**
- Modify: `lib/pages/contributors_page.dart`（「專案授權」`SectionCard`，約第 80～86 行）
- Modify: `lib/l10n/app_*.arb`（31 個檔案）
- Test: `test/pages/contributors_page_test.dart`

**Interfaces:**
- Consumes: `appVersionProvider`（`lib/app_info.dart`）、`l.appName`、`assets/icons/app_icon.png`、`AppSpacing.m`、`AppRadius.md`。
- Produces: `l.contributorsOpenSourceLicenses`；私有 widget `_ThirdPartyLicensesButton`。

- [ ] **Step 1：寫會失敗的測試**

在 `contributors_page_test.dart` 加：

```dart
testWidgets('專案授權下方有「開放原始碼授權」按鈕，按下開啟授權頁並顯示版本', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [appVersionProvider.overrideWithValue('9.8.7')],
    child: /* 與 _wrap 相同的 MaterialApp */,
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('開放原始碼授權'));
  await tester.pumpAndSettle();
  expect(find.byType(LicensePage), findsOneWidget);
  expect(find.text('9.8.7'), findsOneWidget);
});
```

`_wrap` 可以加一個 `overrides` 參數來共用，不要複製整段。按鈕若在畫面外，先 `ensureVisible`。

- [ ] **Step 2：執行測試，確認失敗**

Run: `fvm flutter test test/pages/contributors_page_test.dart`
Expected: FAIL（找不到「開放原始碼授權」）

- [ ] **Step 3：加 ARB 字串**

- 31 個 ARB 都加 `contributorsOpenSourceLicenses`，放在 `contributorsProjectLicense` 的下一行。
- 值逐字複製鳴潮同名檔案的同一個 key（例如繁中「開放原始碼授權」、英文「Open source licenses」）。
- 鳴潮沒有 `@contributorsOpenSourceLicenses` 說明，這裡也不加。
- 加完執行 `fvm flutter gen-l10n`。

- [ ] **Step 4：實作按鈕**

逐字照鳴潮 `git show 7898319 -- lib/pages/contributors_page.dart`，只把 import 的套件名稱換成 `genshin_impact_wish_gacha_analyzer`：
- `SectionCard` 的 child 改成 `Column`：`TranslatorText` 加上 `SizedBox(height: AppSpacing.m)`，再接 `_ThirdPartyLicensesButton`。
- 按鈕用 `OutlinedButton.icon`：
  - 圖示：`Icons.integration_instructions_outlined`，size 18。
  - 按下呼叫 `showLicensePage`：
    - `applicationName: l.appName`
    - `applicationVersion: ref.read(appVersionProvider)`
    - `applicationIcon`：`Padding(vertical: AppSpacing.m)` 包 `ClipRRect(AppRadius.md)`，裡面是 64×64 的 `app_icon.png`。
    - `useRootNavigator: true`

- [ ] **Step 5：執行測試，確認通過**

Run: `fvm flutter test test/pages/contributors_page_test.dart`
Expected: PASS

- [ ] **Step 6：完整檢查並提交**

執行 Global Constraints 的三項檢查，然後提交：

```
feat(contributors): add an open source licenses page

Add an "Open source licenses" button under the project license section
of the contributors page. It opens Flutter's built-in license page full
screen with the app name, a rounded app icon and the current version.
The label is translated into all 31 locales.

Rust crates and Android native dependencies are not added, same as the
Wuthering Waves analyzer: the oss-licenses Gradle plugin breaks CMake
configure tasks under AGP 9.
```

畫面確認（Windows 視窗與 Android 模擬器）由主控在任務審查後進行，實作者不用做。

---

### Task 2: Play 商店主題圖片

**Files:**
- Create: `tool/generate_feature_graphic.py`
- Create: `docs/images/play-store/feature-graphic-{en,zh-TW,ja,zh-CN}.png`

**Interfaces:**
- Consumes: `docs/images/play-store/icon-512.png`（已存在）。

- [ ] **Step 1：複製鳴潮的腳本**

把鳴潮的 `tool/generate_feature_graphic.py` 複製過來，只改下面這些地方，其餘逐字保留（包括版面常數、配色、字型、docstring 結構）：
- docstring 裡的「for 遊戲名」說明和用法不用改。
- `VARIANTS` 改成：

```python
VARIANTS = {
    'en': ('Wish Analyzer', 'for Genshin', 'Wish stats · Pity tracking · 5★ timeline', 'segoeuib.ttf', 'msjhbd.ttc'),
    'zh-TW': ('祈願卡池分析', 'for 原神', '祈願記錄統計・保底進度・5★ 時間軸', 'msjhbd.ttc', 'msjhbd.ttc'),
    'ja': ('祈願分析', 'for 原神', '祈願履歴の統計・天井の進捗・★5 タイムライン', 'YuGothB.ttc', 'YuGothB.ttc'),
    'zh-CN': ('祈愿卡池分析', 'for 原神', '祈愿记录统计・保底进度・5★ 时间轴', 'msyhbd.ttc', 'msyhbd.ttc'),
}
```

- `REPO = 'github.com/GoneTone/genshin-impact-wish-gacha-analyzer'`

- [ ] **Step 2：產生圖片**

Run: `python tool/generate_feature_graphic.py`
Expected：印出四行 `wrote docs/images/play-store/feature-graphic-<語言>.png  1024x500`；腳本內的 `assert` 會確認尺寸是 1024×500、模式是 RGB。

- [ ] **Step 3：檢查畫面**

用 Read 工具打開四張 PNG 逐一看過，要符合：
- 沒有豆腐字。
- 網址和標語都沒有超出右邊界。
- 「for 原神」是金色。

有問題先停下來回報，不要自己改版面常數。

- [ ] **Step 4：提交**

```
feat(play): add a store feature graphic generator and the four graphics
```

---

### Task 3: README 補上 Android 版

**Files:**
- Modify: `README.md`、`README_EN.md`、`README_JA-JP.md`、`README_ZH-HANS.md`

**參考**：
- 鳴潮 `git show c5171d6 897d15c -- README*.md`：照這兩個 commit 的段落結構和寫法改。
- 鳴潮 `docs/Android移植筆記.md` 第 56 節：其中「一定要改的」和「容易漏掉的寫法」每一條都要做到。
- 「上架後補上的」不做。

- [ ] **Step 1：盤點原神 Android 版的實際行為**

改 README 之前，先從原神的程式與 `lib/l10n/app_zh.arb` 確認以下事實，記在報告裡。README 只能寫確認過的事：
- Android 讀取 log 的方式有哪幾種，以及用完後怎麼收尾（例如中斷連線、把無線偵錯關回去）。
  - 相關程式：`android/app/src/main/kotlin/tw/reh/genshin/gacha/` 的 `LogAccessChannel`、`AdbPairingService`。
- 各語言 ARB 對這些功能的官方用語。
- 分享圖現在的實際行為。
- 雲端同步、更新檢查在 Android 上的行為：
  - Play 版透過 Play 商店更新。
  - 更新檢查的程式：`lib/state/app_release.dart`。

- [ ] **Step 2：改繁中 `README.md`**

照鳴潮 `c5171d6`、`897d15c` 與第 56 節改：
- 開頭介紹寫出支援的平台。
- 原理段拆成 Windows 和 Android。
- 「請放心」段改寫。
- 「使用方式」分成 Windows、Android 兩小節。
- 功能列表：
  - 加上「支援 Windows 與 Android」和「Android 版有原生廣告、Windows 版沒有」。
  - 其他每一條都對照現在的畫面檢查。
- 用詞改成「多台裝置」「裝置內」「取得」。
- 「前置需求」「開發模式執行」「編譯生產版」補上 Android：
  - APK／AAB 的輸出位置。
  - 沒有 `android/key.properties` 時用 debug 金鑰簽署。
  - 已經有的「廣告 ID（選用，Android）」段保留。
- 「截圖」段這次不動。

- [ ] **Step 3：改其他三種語言**

把繁中的改動同步到另外三個 README：
- 段落結構要和繁中一致。
- 用詞照該語言 ARB 的官方用語。
- 英文和日文是半形與全形標點的差別，照各語言慣例。

- [ ] **Step 4：檢查**

Run: `git diff --stat`
Expected：只有四個 README 有改動，且四個檔案增減的行數相近。

另外搜尋四個檔案，確認沒有留下只適用電腦版的句子，例如「多台電腦」「電腦內」「目前僅支援 Windows」，以及各語言的對應寫法。

- [ ] **Step 5：提交**

```
docs: describe the Android version in the READMEs
```

---

### 收尾（主控）

- spec 加一節附錄「實作結果」，記下：
  - 各任務的 commit。
  - 畫面確認的結果。
  - 和 spec 不同的地方。
- 狀態改成「實作完成，截圖待內部測試發布後補上」。
