# 手動更新物品詳細資料 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在設定頁新增一顆非破壞性的「更新物品資料」按鈕，重抓所有物品的 HoYoWiki metadata（強制重抓已解析條目的 entry 階段），保留既有快取圖、新 gallery 圖維持 lazy。

**Architecture:** 重用既有 `_fetchHoYoWiki` 三階段管線，加一個 `forceEntryRefetch` 開關讓 entry 階段強制重抓已解析條目；外層包一個不呼叫 `resetAll()` 的 `refreshAllHoYoWikiMetadata()`；設定頁新增獨立「物品資料」區與輕量確認 dialog。詳情頁零改動（既有 lazy backfill 已涵蓋）。

**Tech Stack:** Flutter、Riverpod（`NotifierProvider`）、`http`/`MockClient`、flutter gen-l10n（ARB）、flutter_test。

## Global Constraints

- 指令一律優先透過 `fvm` 執行（`fvm flutter analyze` / `fvm flutter test` / `fvm flutter gen-l10n` / `fvm dart format lib/ test/`）；找不到 `fvm` 才退回 `flutter` / `dart`。
- 提交前依序通過：`fvm dart format lib/ test/`、`fvm flutter analyze`（須 `No issues found!`）、`fvm flutter test`（須 `All tests passed!`）。不得用 `--no-verify`。
- 不要 `git push`（功能分支 `feat/manual-refresh-item-metadata` 已建立，所有 commit 落在此分支）。
- 所有新宣告（method、field、class）寫一行 `///` dartdoc；Flutter override 不寫。
- 關鍵節點埋 `Logger` log，命名對齊既有樹（`gacha.hoyowiki.*`）；敏感資料經 `sanitizeUrl`/`sanitizeUid`。
- 註解節制：只在 WHY 不顯而易見或段落導引時寫。
- CJK 文案（含 ARB、dartdoc、註解）用全形標點；commit message 用英文半形、conventional commits；省略號一律半形 `...`（ARB 內既有用全形 `…`，新字串沿用既有檔案慣例以保持一致——見 Task 3 說明）。
- i18n 從 `app_zh.arb`（template）起手；只在已有實體翻譯的 ARB 補字串，空殼 ARB 留給 Crowdin pipeline。
- Dialog 一律用既有 `showConfirmDialog`，不手寫 `AlertDialog`。
- 嚴禁重複造輪子：重用 `_fetchHoYoWiki`、`showConfirmDialog`、`SectionCard`、`app_shell` 既有進度 listener。

---

### Task 1: `_fetchHoYoWiki` 加 `forceEntryRefetch` 開關

**Files:**
- Modify: `lib/state/gacha_repository.dart`（`_fetchHoYoWiki` 簽名與 entryTodo 建構；`debugRunHoYoWikiOnly` 加參數）
- Test: `test/state/gacha_repository_hoyowiki_test.dart`

**Interfaces:**
- Produces:
  - `Future<int> _fetchHoYoWiki(http.Client client, {bool forceEntryRefetch = false})`
  - `Future<void> debugRunHoYoWikiOnly({bool forceEntryRefetch = false})`（測試 hook，`@visibleForTesting`）

**背景：** 目前 `_fetchHoYoWiki`（`lib/state/gacha_repository.dart:979`）的 entryTodo 由 `needRefetchEntry` 判定——entry 已存在且該 lang page 已抓就跳過。force 模式要讓**所有已解析的 (id, lang)** 都進 entry worklist。search 階段不需改（newly-searched id 的 entry 為 null，`needRefetchEntry` 本就回 true）。

- [ ] **Step 1: 寫失敗測試**

在 `test/state/gacha_repository_hoyowiki_test.dart` 的 `main()` 內、最後一個 top-level `test(...)`（cancel 那筆，約 1072 行的 `});` 之後、`main` 收尾的 `}` 之前）插入。此測試用可變的 gallery 長度模擬「HoYoWiki 後來新增了一張 gallery 圖」，驗證 force 模式會重抓已存在的 entry 並更新 gallery：

```dart
  test('forceEntryRefetch=true：已解析的 entry 仍重抓並更新 gallery', () async {
    var entryCallCount = 0;
    var galleryListLen = 1;
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': 'Hu Tao',
                  'entry_page_id': '111',
                  'menu': {
                    'sub_menus': [
                      {'id': 2},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        entryCallCount++;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {
                'icon_url': 'https://x/icon.png',
                'modules': [
                  {
                    'components': [
                      {
                        'component_id': 'gallery_character',
                        'data': jsonEncode({
                          'pic': '',
                          'list': [
                            for (var i = 0; i < galleryListLen; i++)
                              {
                                'id': 'g$i',
                                'key': 'k$i',
                                'img': 'https://x/g$i.png',
                                'imgDesc': '',
                              },
                          ],
                        }),
                      },
                    ],
                  },
                ],
              },
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    // 第一次增量抓取：entry 抓 1 次，gallery 1 張
    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1);
    expect(
      container.read(hoyowikiIndexProvider).lookupEntry('111')!
          .pageByLang['en-us']!.gallery!.list.length,
      1,
    );

    // HoYoWiki 端新增一張 gallery 圖
    galleryListLen = 2;

    // 非 force：已抓過 → 不重抓，gallery 仍是舊的 1 張
    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1, reason: '非 force 模式不重抓已解析 entry');

    // force：強制重抓 entry → gallery 更新為 2 張
    await notifier.debugRunHoYoWikiOnly(forceEntryRefetch: true);
    expect(entryCallCount, 2, reason: 'force 模式重抓已解析 entry');
    expect(
      container.read(hoyowikiIndexProvider).lookupEntry('111')!
          .pageByLang['en-us']!.gallery!.list.length,
      2,
      reason: 'force 重抓後 mergeEntry 覆蓋 gallery，新圖出現',
    );

    // gallery 大圖不應被 eager 下載（維持 lazy）
    final galleryFiles = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'111_gallery_').hasMatch(f.path))
        .toList();
    expect(galleryFiles, isEmpty, reason: 'gallery 維持 lazy，不在更新流程下載');
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/state/gacha_repository_hoyowiki_test.dart --plain-name "forceEntryRefetch"`
Expected: 編譯失敗或 FAIL —— `debugRunHoYoWikiOnly` 尚無具名參數 `forceEntryRefetch`。

- [ ] **Step 3: 實作 `_fetchHoYoWiki` 簽名與 entryTodo 強制納入**

在 `lib/state/gacha_repository.dart` 修改 `_fetchHoYoWiki` 簽名（約 979 行）：

```dart
  Future<int> _fetchHoYoWiki(
    http.Client client, {
    bool forceEntryRefetch = false,
  }) async {
```

把初始 entryTodo 建構（約 1023-1036 行）的判定改為「force 時無條件納入」：

```dart
    final entryTodo = <({String id, String lang})>{};
    for (final lang in allLangs) {
      for (final name in namesByLang[lang] ?? const <String>{}) {
        final id = index.lookupId(name: name, lang: lang);
        if (id == null) continue;
        if (forceEntryRefetch ||
            needRefetchEntry(
              index.lookupEntry(id),
              index.lookupMenuId(id),
              lang,
            )) {
          entryTodo.add((id: id, lang: lang));
        }
      }
    }
```

更新 `_fetchHoYoWiki` 的 dartdoc，在流程說明補一句：「`forceEntryRefetch` 為 true 時，entry 階段強制納入所有已解析的 (id, lang)，用於設定頁手動更新物品資料。」

- [ ] **Step 4: 實作 `debugRunHoYoWikiOnly` 透傳參數**

修改 `debugRunHoYoWikiOnly`（約 1204 行）：

```dart
  /// 測試用：略過 banner fetch 直接跑 hoyowiki 階段（用既有 state.byUid）。
  @visibleForTesting
  Future<void> debugRunHoYoWikiOnly({bool forceEntryRefetch = false}) async {
    _cancelTriggered = false;
    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    try {
      await _fetchHoYoWiki(cancellable.client, forceEntryRefetch: forceEntryRefetch);
    } finally {
      cancellable.client.close();
    }
  }
```

- [ ] **Step 5: 跑測試確認通過**

Run: `fvm flutter test test/state/gacha_repository_hoyowiki_test.dart`
Expected: PASS（新測試與既有 11 筆全綠）。

- [ ] **Step 6: Commit**

```bash
fvm dart format lib/ test/
git add lib/state/gacha_repository.dart test/state/gacha_repository_hoyowiki_test.dart
git commit -m "feat(hoyowiki): add forceEntryRefetch flag to metadata fetch pipeline"
```

---

### Task 2: 新增 `refreshAllHoYoWikiMetadata()` 非破壞性入口

**Files:**
- Modify: `lib/state/gacha_repository.dart`（新增 logger field + public method）
- Test: `test/state/gacha_repository_hoyowiki_test.dart`

**Interfaces:**
- Consumes: `_fetchHoYoWiki(client, forceEntryRefetch: true)`（Task 1）
- Produces: `Future<void> refreshAllHoYoWikiMetadata()`（public，供設定頁呼叫）

- [ ] **Step 1: 寫失敗測試**

在 `test/state/gacha_repository_hoyowiki_test.dart` 接續 Task 1 的測試之後插入。驗證 `refreshAllHoYoWikiMetadata` 會重抓已解析 entry、保留既有 icon 快取檔、且結束 emit `UpdateCompleted`：

```dart
  test('refreshAllHoYoWikiMetadata：非破壞性重抓，保留 icon、emit UpdateCompleted', () async {
    var entryCallCount = 0;
    var imageDownloadCount = 0;
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': 'Hu Tao',
                  'entry_page_id': '111',
                  'menu': {
                    'sub_menus': [
                      {'id': 2},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        entryCallCount++;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {'icon_url': 'https://x/icon.png', 'header_img_url': ''},
            },
          }),
          200,
        );
      }
      imageDownloadCount++;
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    // 先增量抓一次：建立 index + icon 快取檔
    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1);
    expect(imageDownloadCount, 1, reason: '第一次下 icon');
    final iconFile = File('${tempDir.path}/111_icon.png');
    expect(iconFile.existsSync(), isTrue);

    // 非破壞性更新
    await notifier.refreshAllHoYoWikiMetadata();

    // entry 被強制重抓；icon 已在快取 → 不重下；icon 檔仍在（未被 wipe）
    expect(entryCallCount, 2, reason: 'force 重抓 entry');
    expect(imageDownloadCount, 1, reason: 'icon 已快取，缺才下 → 不重下');
    expect(iconFile.existsSync(), isTrue, reason: '非破壞性：既有快取保留');

    // 結束狀態為 UpdateCompleted
    expect(container.read(gachaRepositoryProvider).progress, isA<UpdateCompleted>());
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/state/gacha_repository_hoyowiki_test.dart --plain-name "refreshAllHoYoWikiMetadata"`
Expected: 編譯失敗 —— `refreshAllHoYoWikiMetadata` 未定義。

- [ ] **Step 3: 新增 logger field**

在 `lib/state/gacha_repository.dart` 既有 logger 宣告（111-117 行）之後新增：

```dart
  static final _refreshMetaLog = Logger('gacha.hoyowiki.refreshMetadata');
```

- [ ] **Step 4: 實作 `refreshAllHoYoWikiMetadata`**

緊接在 `forceRefetchAllHoYoWikiImages`（約 604 行的 `}` 之後）新增。骨架比照 `forceRefetchAllHoYoWikiImages`，但**不呼叫 `resetAll()`**、無 wipe 失敗路徑：

```dart
  /// 非破壞性更新所有物品的 HoYoWiki metadata（強制重抓已解析條目的 entry 階段）。
  ///
  /// 與 [forceRefetchAllHoYoWikiImages] 不同：**不** `resetAll()`，保留既有 index
  /// 與快取圖。重抓後 [HoYoWikiIndexNotifier.mergeEntry] 覆蓋各 lang page，新增的
  /// gallery 圖只更新 index、不在此下載（維持 lazy，由詳情頁開啟時補）；icon 僅在
  /// 本地缺檔時才下載。
  ///
  /// 流程：互斥檢查 → emit `Preparing` → `_fetchHoYoWiki(forceEntryRefetch: true)`
  /// → 依取消狀態 emit `UpdateCompleted` 或 `clearProgress`。
  Future<void> refreshAllHoYoWikiMetadata() async {
    if (state.progress != null) {
      _refreshMetaLog.info('skip: another progress in-flight');
      return;
    }
    if (_isUpdating) return;
    _isUpdating = true;
    _cancelTriggered = false;
    _refreshMetaLog.info('start, totalUids=${state.byUid.length}');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;
    state = state.copyWith(progress: const Preparing());

    try {
      var images = 0;
      try {
        images = await _fetchHoYoWiki(
          cancellable.client,
          forceEntryRefetch: true,
        );
      } catch (e, st) {
        _refreshMetaLog.warning('hoyowiki stage threw (ignored)', e, st);
      }
      if (!ref.mounted) return;

      if (_cancelTriggered) {
        _refreshMetaLog.warning('cancelled');
        state = state.copyWith(clearProgress: true);
        return;
      }

      _refreshMetaLog.info('done, images=$images');
      state = state.copyWith(
        progress: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: DateTime.now().toUtc(),
          hoYoWikiImagesDownloaded: images,
        ),
      );
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }
```

- [ ] **Step 5: 跑測試確認通過**

Run: `fvm flutter test test/state/gacha_repository_hoyowiki_test.dart`
Expected: PASS（全部綠）。

- [ ] **Step 6: Commit**

```bash
fvm dart format lib/ test/
git add lib/state/gacha_repository.dart test/state/gacha_repository_hoyowiki_test.dart
git commit -m "feat(hoyowiki): add non-destructive refreshAllHoYoWikiMetadata entry point"
```

---

### Task 3: 新增 i18n 字串（ARB）

**Files:**
- Modify: `lib/l10n/app_zh.arb`（template，必填）
- Modify: `lib/l10n/app_en.arb` 及其他**已含** `settingsRefetchHoyoWikiImagesTitle` 的 `app_*.arb`
- Generated: `lib/l10n/generated/*`（由 gen-l10n 產生，隨後一併提交）

**Interfaces:**
- Produces（供 Task 4 使用的 getter）：`l.settingsItemData`、`l.settingsRefreshItemDataDesc`、`l.settingsRefreshItemDataTitle`、`l.settingsRefreshItemDataEmpty`、`l.confirmRefreshItemDataTitle`、`l.confirmRefreshItemDataBody`、`l.confirmRefreshItemDataConfirm`

**說明：** template 為 `app_zh.arb`。其他 locale 若缺 key 會在執行期 fallback 到 template，故 gen-l10n 不會因非 template ARB 缺 key 而失敗。依專案慣例只在「已有實體翻譯」的 ARB 補字串——判準：該檔已含 `settingsRefetchHoyoWikiImagesTitle`（用 Grep 確認），有則補、空殼則跳過。省略號沿用本檔既有寫法（`app_zh.arb` 內既有 `計算中…` 用全形，新字串若含省略號比照同檔慣例；本批字串草案不含省略號）。

- [ ] **Step 1: 在 `app_zh.arb` 新增字串**

在 `lib/l10n/app_zh.arb` 的 `confirmRefetchHoyoWikiConfirm` 區塊（366-369 行）之後、`settingsImageCache`（371 行）之前插入：

```json
  "settingsItemData": "物品資料",
  "@settingsItemData": {
    "description": "Settings page section title for item data (HoYoWiki metadata) controls."
  },
  "settingsRefreshItemDataDesc": "從 HoYoWiki 重新抓取所有物品的最新詳細資料（描述、圖片清單等），保留已下載的圖片；新增的圖片會在你開啟該物品詳情時才下載。",
  "@settingsRefreshItemDataDesc": {
    "description": "Description under the 'refresh item data' button explaining the non-destructive metadata refresh."
  },
  "settingsRefreshItemDataTitle": "更新物品資料",
  "@settingsRefreshItemDataTitle": {
    "description": "Settings → Item data → button: re-fetch latest HoYoWiki item metadata without clearing cached images."
  },
  "settingsRefreshItemDataEmpty": "尚無卡池記錄，無法更新物品資料",
  "@settingsRefreshItemDataEmpty": {
    "description": "Tooltip shown when the refresh-item-data button is disabled because there are no gacha records on the device."
  },
  "confirmRefreshItemDataTitle": "更新物品資料？",
  "@confirmRefreshItemDataTitle": {
    "description": "Title of the AlertDialog confirming the non-destructive item metadata refresh."
  },
  "confirmRefreshItemDataBody": "將連線 HoYoWiki 重新抓取所有物品的詳細資料，依物品數量可能需要一段時間。已下載的圖片會保留，不會被清除。",
  "@confirmRefreshItemDataBody": {
    "description": "Body of the AlertDialog confirming the item metadata refresh; clarifies it is non-destructive."
  },
  "confirmRefreshItemDataConfirm": "開始更新",
  "@confirmRefreshItemDataConfirm": {
    "description": "Confirm button label in the refresh-item-data AlertDialog."
  },
```

- [ ] **Step 2: 在 `app_en.arb` 新增對應英文字串**

在 `lib/l10n/app_en.arb` 對應位置（`confirmRefetchHoyoWikiConfirm` 之後）插入。英文無 `@` metadata 區塊（template 已帶 description），只需 key-value：

```json
  "settingsItemData": "Item Data",
  "settingsRefreshItemDataDesc": "Re-fetch the latest item details (descriptions, image lists, etc.) from HoYoWiki, keeping already-downloaded images. New images are downloaded when you open the item's details.",
  "settingsRefreshItemDataTitle": "Update Item Data",
  "settingsRefreshItemDataEmpty": "No gacha records yet — nothing to update",
  "confirmRefreshItemDataTitle": "Update item data?",
  "confirmRefreshItemDataBody": "This will contact HoYoWiki to re-fetch every item's details, which may take a while depending on how many items you have. Already-downloaded images are kept and will not be cleared.",
  "confirmRefreshItemDataConfirm": "Start update",
```

> 若 `app_en.arb` 既有條目帶 `@` metadata，則比照同檔慣例補上；以實際檔案格式為準。

- [ ] **Step 3: 補其他已翻譯的 ARB**

Run（找出已翻譯的 locale 檔）：`grep -l "settingsRefetchHoyoWikiImagesTitle" lib/l10n/app_*.arb`
對結果中**除 `app_zh.arb`/`app_en.arb` 外**的每個檔，比照 Step 2 形式新增上述 7 個 key，文案以繁中（Step 1）為基準翻成該語言；未出現在清單的 ARB（空殼）不動。

- [ ] **Step 4: 重新產生 localizations**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 新增上述 getter。

- [ ] **Step 5: analyze 驗證 getter 可用**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/
git commit -m "feat(l10n): add item data refresh strings"
```

---

### Task 4: 設定頁新增「物品資料」區與按鈕

**Files:**
- Modify: `lib/pages/settings_page.dart`（新增 `SectionCard` 與 `_ItemDataSection`）
- Test: `test/pages/settings_item_data_section_test.dart`（新建）

**Interfaces:**
- Consumes: `refreshAllHoYoWikiMetadata()`（Task 2）、Task 3 的 `l.*` getter、既有 `showConfirmDialog`、`SectionCard`
- Produces: 無下游

**說明：** 新「物品資料」`SectionCard` 插在「圖片快取」（現約 110-114 行）之前。`_ItemDataSection` 為 `ConsumerWidget`，disable 條件比照 `_refetchAll`（`!hasData || progress != null`），確認用 `showConfirmDialog(isDanger: false)`，觸發用 `unawaited(...)`，進度 dialog 由 `app_shell` 既有 listener 自動彈出。

- [ ] **Step 1: 寫失敗 widget 測試**

新建 `test/pages/settings_item_data_section_test.dart`。先讀 `test/pages/` 既有測試（若有）對齊 harness 寫法；本測試自包含、用 `ProviderContainer` override 一個 spy 來驗證按鈕點擊→確認→呼叫。若 `_ItemDataSection` 為 private 無法直接 import，改以較輕的「getter 存在 + repository 方法可被呼叫」測試，或將測試聚焦在 `_ItemDataSection` 透過 `UncontrolledProviderScope` 掛載。實作如下（用一個可記錄呼叫的假 repository notifier 不易，故改驗證 UI 層級行為）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('物品資料區字串已生成且可取用', (tester) async {
    late AppLocalizations l;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) {
              l = AppLocalizations.of(context)!;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(l.settingsItemData, '物品資料');
    expect(l.settingsRefreshItemDataTitle, '更新物品資料');
    expect(l.confirmRefreshItemDataConfirm, '開始更新');
  });
}
```

> 此測試先守住 Task 3 字串落地（Task 4 依賴）。`_ItemDataSection` 的點擊→`refreshAllHoYoWikiMetadata` 行為已由 Task 2 的 repository 測試覆蓋；UI 互動採人工驗收（驗收條件 4），避免為 private widget + 真實 HTTP 疊出脆弱測試（YAGNI）。

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/pages/settings_item_data_section_test.dart`
Expected: 若 Task 3 尚未合入此分支會 FAIL；本分支已含 Task 3，故此步應在 Step 1 之後直接驗證——若 getter 已存在則此測試在實作 UI 前就會 PASS（屬可接受，因為它守的是 Task 3 字串）。確認測試本身能編譯並執行。

- [ ] **Step 3: 新增 `_ItemDataSection` widget**

在 `lib/pages/settings_page.dart` 適當位置（建議緊鄰 `_ImageCacheSection` 之前）新增：

```dart
/// 物品資料區塊：提供「更新物品資料」按鈕，非破壞性重抓 HoYoWiki metadata。
class _ItemDataSection extends ConsumerWidget {
  /// 建立 [_ItemDataSection]。
  const _ItemDataSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final hasData = ref.watch(
      gachaRepositoryProvider.select((s) => s.byUid.isNotEmpty),
    );
    final progress = ref.watch(
      gachaRepositoryProvider.select((s) => s.progress),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.settingsRefreshItemDataDesc,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Tooltip(
          message: !hasData ? l.settingsRefreshItemDataEmpty : '',
          child: FilledButton.icon(
            onPressed: (!hasData || progress != null)
                ? null
                : () => _refreshItemData(context, ref),
            icon: const Icon(Icons.sync, size: 18),
            label: Text(l.settingsRefreshItemDataTitle),
          ),
        ),
      ],
    );
  }

  /// 顯示輕量確認 dialog，確認後呼叫 [GachaRepository.refreshAllHoYoWikiMetadata]。
  Future<void> _refreshItemData(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmDialog(
      context: ctx,
      title: l.confirmRefreshItemDataTitle,
      body: l.confirmRefreshItemDataBody,
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmRefreshItemDataConfirm,
      isDanger: false,
    );
    if (ok != true) return;
    // 後端流程獨立於 dialog lifecycle；UpdateProgressDialog 由 app_shell.dart
    // 既有 ref.listen 自動彈出。
    unawaited(
      ref.read(gachaRepositoryProvider.notifier).refreshAllHoYoWikiMetadata(),
    );
  }
}
```

> 確認 `lib/pages/settings_page.dart` 頂部已 import `dart:async`（`unawaited`）；`_ImageCacheSection` 既有 `unawaited` 用法表示應已 import，若無則補上。

- [ ] **Step 4: 掛上 `SectionCard`**

在 `build` 的 section 清單，「圖片快取」`SectionCard`（約 110 行）之前插入：

```dart
              SectionCard(
                title: l.settingsItemData,
                icon: Icons.dataset_outlined,
                child: const _ItemDataSection(),
              ),
              const SizedBox(height: AppSpacing.xl),
```

- [ ] **Step 5: 跑全套測試 + analyze**

Run: `fvm flutter analyze`
Expected: `No issues found!`

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
fvm dart format lib/ test/
git add lib/pages/settings_page.dart test/pages/settings_item_data_section_test.dart
git commit -m "feat(settings): add Item Data section with non-destructive refresh button"
```

---

### Task 5: 全套驗證與人工驗收

**Files:** 無（驗證任務）

- [ ] **Step 1: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 無檔案被改動（前面已格式化）或僅微調。

- [ ] **Step 2: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 人工驗收（驗收條件 3、4）**

1. 啟動 App → 設定頁出現獨立「物品資料」區與「更新物品資料」按鈕（非 danger 樣式）；無卡池記錄時 disable 並顯示 tooltip。
2. 對一個已有 gallery 的物品，於 HoYoWiki 新增圖後點「更新物品資料」→ 輕量確認 dialog → 確認後出現進度 dialog（搜尋→抓頁面→下載階段）。
3. 更新完成後開啟該物品詳情 → 可見新頁籤，缺的圖會 lazy 補下載；既有已下載的圖未被清除（「圖片快取」用量未歸零）。

- [ ] **Step 5:（如有殘留改動）Commit**

```bash
git add -A
git commit -m "chore: finalize manual item metadata refresh"
```

> 若前述任務已全部提交且無殘留，跳過此步。完成後不要 `git push`，依 finishing-a-development-branch 流程與使用者確認整合方式。

---

## Self-Review

**Spec coverage：**
- 設定頁手動更新入口 → Task 4（按鈕）+ Task 2（method）。
- 重抓範圍「全部已解析 entry + 重試未解析 search」→ Task 1（force entry）+ 既有 search 階段（未解析本就重試）。
- 非破壞性、保留已下載圖 → Task 2（不 `resetAll`）+ Task 1 download 階段只補缺 icon。
- 新圖 lazy、開詳情補下載 → 詳情頁零改動（spec 已論證），Task 1 測試驗證 gallery 不 eager 下載。
- icon「缺才下、URL 變不重下」→ 既有 download 階段 + id-key 快取，Task 2 測試驗證不重下。
- 獨立「物品資料」區 + 輕量確認 → Task 4。
- i18n → Task 3。
- 驗收條件（analyze/test 全綠、UI、實機）→ Task 5。

**Placeholder scan：** 無 TBD／TODO；每個 code step 含完整程式碼與 ARB JSON。

**Type consistency：** `_fetchHoYoWiki(client, {bool forceEntryRefetch})`、`debugRunHoYoWikiOnly({bool forceEntryRefetch})`、`refreshAllHoYoWikiMetadata()`、`_ItemDataSection`、`l.settingsItemData` 等命名跨 Task 一致。`UpdateCompleted` 具名參數（`totalNewRecords`/`failedBanners`/`updatedAt`/`hoYoWikiImagesDownloaded`）沿用 `forceRefetchAllHoYoWikiImages` 既有用法。

---

## 實作後演進（驗收階段追加）

> 本計畫的 Task 1-5 是原始範圍。實機驗收時依使用者回饋追加了下列任務；**最終出貨的完整設計以更新後的設計文件為準**（`docs/superpowers/specs/2026-06-18-manual-refresh-item-metadata-design.md`，已涵蓋以下全部）。此處僅記錄演進脈絡，方便對照 commit 歷史。

- **完成訊息語意化**：原計畫直接沿用 `UpdateCompleted`，但其內容是祈願記錄語意（「新增 N 筆紀錄」），對 metadata 刷新不適當。改為：`_fetchHoYoWiki` 回傳型別由 `Future<int>` 改為 record `({int imagesDownloaded, int itemsRefreshed, int staleLangItemsPruned})`；`UpdateCompleted` 新增 `hoyoWikiEntriesRefreshed`（int?，metadata 流程判別）與 `hoyoWikiStaleItemsPruned`（int）；`UpdateProgressDialog._Body` 的 `UpdateCompleted` 分支改三路，metadata 分支顯示「已更新 M 個物品的資料」+ 條件式「補下載 N 張」+ 條件式「已清理 K 個物品的殘留語言資料」。
- **殘留語言清理**：`_fetchHoYoWiki` 新增 `pruneStaleLangs` 旗標（`refreshAllHoYoWikiMetadata` 傳 true）；新增 `HoYoWikiIndexNotifier.pruneLanguages(Set<String> keepLangs) → Future<int>`，移除 index 中 `lang ∉ keepLangs` 的 `pageByLang`（保留 icon／searchMap／menuIds），空 keepLangs 與呼叫端 `allLangs.isNotEmpty` 雙重防呆，回傳清理到的相異物品數。
- **新增 i18n key**：`progressDoneItemDataSummary`、`progressDoneItemDataImagesSummary`、`progressDoneItemDataPrunedSummary`（皆帶 `{count}` int placeholder），補進 zh template + 9 個已翻譯語系。

**最終關鍵簽名（覆蓋上方原始 Task 描述）：**

```dart
// lib/state/gacha_repository.dart
Future<({int imagesDownloaded, int itemsRefreshed, int staleLangItemsPruned})>
    _fetchHoYoWiki(http.Client client, {bool forceEntryRefetch = false, bool pruneStaleLangs = false});

// lib/state/hoyowiki_index.dart
Future<int> pruneLanguages(Set<String> keepLangs); // 空集合回 0；回傳清理物品數

// lib/state/update_progress.dart — UpdateCompleted 新增
final int? hoyoWikiEntriesRefreshed; // 非 null = 更新物品資料流程；值為刷新物品數
final int hoyoWikiStaleItemsPruned;  // 預設 0；清理殘留語言的物品數
```
