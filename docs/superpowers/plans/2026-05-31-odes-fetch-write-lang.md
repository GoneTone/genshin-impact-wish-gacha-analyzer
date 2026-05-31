# 頌願抓取時補寫 `lang` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 抓取頌願並寫入 json 時，把 record 的 `lang` 補成擷取 URL 的 `lang`（而非空字串），並回填既有空 `lang` 的頌願記錄。

**Architecture:** 取向 A，三檔改動。`GachaUrl` 暴露 `lang` getter；`GachaRecord.fromApiJson` 新增 `fallbackLang` 參數讓頌願新記錄出生即帶 lang，並加 `copyWith` 供回填；`GachaFetcher` 的 `fetchPage` 傳入 URL 的 lang 作 fallback，`fetchBannerWithMerge` 回傳前回填 `existing` 中空 lang 者。下游（HoYoWiki 批次與 on-demand）已用 gachaType 在兩層擋掉頌願，故無副作用、不需守衛。

**Tech Stack:** Dart / Flutter、`http` + `http/testing` MockClient、`logging`、`flutter_test`。

**Spec:** `docs/superpowers/specs/2026-05-31-odes-fetch-write-lang-design.md`

---

## File Structure

- `lib/services/gacha_url.dart` — 新增 `lang` getter（讀 query 參數）。
- `lib/models/gacha_record.dart` — `fromApiJson` 加 `fallbackLang`；新增 `copyWith({String? lang})`。
- `lib/services/gacha_fetcher.dart` — `fetchPage` 傳 `fallbackLang`；`fetchBannerWithMerge` 回填 existing。
- `test/services/gacha_url_test.dart` — `lang` getter 測試。
- `test/models/gacha_record_test.dart` — fallback 行為、API lang 優先、copyWith 測試。
- `test/services/gacha_fetcher_test.dart` — fresh 頌願帶 lang、existing 回填、URL 無 lang 不動。

---

### Task 1: `GachaUrl.lang` getter

**Files:**
- Modify: `lib/services/gacha_url.dart`
- Test: `test/services/gacha_url_test.dart`

- [ ] **Step 1: Write the failing test**

在 `test/services/gacha_url_test.dart` 的 `group('GachaUrl', () {` 內、最後一個 `test(...)` 之後加入：

```dart
    test('lang getter 讀 query 的 lang', () {
      expect(GachaUrl.parse(_capturedUrl).lang, 'zh-tw');
    });

    test('lang getter 缺 lang 參數時回空字串', () {
      final url = GachaUrl.parse(
        'https://example.com/gacha_info/api/getGachaLog?authkey=AAA&gacha_type=301&end_id=0',
      );
      expect(url.lang, '');
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/gacha_url_test.dart`
Expected: FAIL — `The getter 'lang' isn't defined for the type 'GachaUrl'`（編譯錯誤）。

- [ ] **Step 3: Write minimal implementation**

在 `lib/services/gacha_url.dart` 的 `GachaUrl` class 內、`final Uri _uri;` 之後加入：

```dart
  /// 擷取 URL 的 `lang` query 參數；缺漏時為空字串。
  String get lang => _uri.queryParameters['lang'] ?? '';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/gacha_url_test.dart`
Expected: PASS（All tests passed!）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/gacha_url.dart test/services/gacha_url_test.dart
git commit -m "feat(gacha): expose lang getter on GachaUrl"
```

---

### Task 2: `GachaRecord` fallbackLang 與 copyWith

**Files:**
- Modify: `lib/models/gacha_record.dart:48-62`（`fromApiJson`），並新增 `copyWith`
- Test: `test/models/gacha_record_test.dart`

- [ ] **Step 1: Write the failing test**

在 `test/models/gacha_record_test.dart` 的 `group('GachaRecord.fromApiJson', () {` 內加入兩個 test（接在既有兩個 test 之後）：

```dart
    test('頌願無 lang 時，以 fallbackLang 補上', () {
      final json = {
        'id': '1761240000000038925',
        'uid': '801057625',
        'item_type': '裝扮套裝',
        'item_name': '女性裝扮·「燭影狂歡夜」',
        'rank_type': '5',
        'time': '2025-10-24 01:51:25',
        'op_gacha_type': '20021',
      };
      final record = GachaRecord.fromApiJson(
        json,
        gachaType: '2000',
        fallbackLang: 'ja',
      );
      expect(record.lang, 'ja');
    });

    test('API 已帶 lang 時，fallbackLang 被忽略', () {
      final json = {
        'uid': '801057625',
        'gacha_type': '200',
        'time': '2025-09-23 21:27:37',
        'name': '討龍英傑譚',
        'lang': 'zh-tw',
        'item_type': '武器',
        'rank_type': '3',
        'id': '1758632760000221425',
      };
      final record = GachaRecord.fromApiJson(
        json,
        gachaType: '200',
        fallbackLang: 'ja',
      );
      expect(record.lang, 'zh-tw');
    });
```

再於 `group('GachaRecord JSON 持久化序列化', () {` 之後新增一個 group：

```dart
  group('GachaRecord.copyWith', () {
    test('只改 lang，其餘欄位不變', () {
      final original = GachaRecord(
        id: '1',
        uid: '801057625',
        gachaType: '2000',
        name: 'x',
        itemType: '裝扮套裝',
        rankType: 5,
        time: DateTime(2025, 10, 24, 1, 51, 25),
        lang: '',
      );
      final updated = original.copyWith(lang: 'zh-tw');
      expect(updated.lang, 'zh-tw');
      expect(updated.id, original.id);
      expect(updated.uid, original.uid);
      expect(updated.gachaType, original.gachaType);
      expect(updated.name, original.name);
      expect(updated.itemType, original.itemType);
      expect(updated.rankType, original.rankType);
      expect(updated.time, original.time);
    });

    test('不傳 lang 則沿用原值', () {
      final original = GachaRecord(
        id: '1',
        uid: '801057625',
        gachaType: '2000',
        name: 'x',
        itemType: '裝扮套裝',
        rankType: 5,
        time: DateTime(2025, 10, 24, 1, 51, 25),
        lang: 'en',
      );
      expect(original.copyWith().lang, 'en');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/gacha_record_test.dart`
Expected: FAIL — `fromApiJson` 沒有 `fallbackLang` 具名參數、`copyWith` 未定義（編譯錯誤）。

- [ ] **Step 3: Write minimal implementation**

在 `lib/models/gacha_record.dart` 把 `fromApiJson`（行 48-62）整段替換為：

```dart
  factory GachaRecord.fromApiJson(
    Map<String, dynamic> json, {
    required String gachaType,
    String fallbackLang = '',
  }) {
    final apiLang = json['lang'] as String?;
    return GachaRecord(
      id: json['id'] as String,
      uid: json['uid'] as String,
      gachaType: gachaType,
      name: (json['name'] ?? json['item_name']) as String,
      itemType: json['item_type'] as String,
      rankType: int.parse(json['rank_type'] as String),
      time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
      lang: (apiLang == null || apiLang.isEmpty) ? fallbackLang : apiLang,
    );
  }
```

並把 `fromApiJson` 上方的 dartdoc 末段（描述 `頌願 (getBeyondGachaLog): ... 無 lang`）補一句說明 fallback。在原 dartdoc 行 44 的「無 `lang`」之後、`///` 區塊內加入一行：

```dart
  ///   無 `lang`，故由呼叫端傳入的 [fallbackLang]（擷取 URL 的 lang）補上。
```

接著在 `toStorageJson()`（行 78-94）之後、class 結尾 `}` 之前新增 `copyWith`：

```dart

  /// 複製本 record，可覆寫 [lang]（其餘欄位沿用原值）。
  GachaRecord copyWith({String? lang}) => GachaRecord(
    id: id,
    uid: uid,
    gachaType: gachaType,
    name: name,
    itemType: itemType,
    rankType: rankType,
    time: time,
    lang: lang ?? this.lang,
  );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/gacha_record_test.dart`
Expected: PASS（All tests passed!）。既有「解析頌願 API 回傳」測試未傳 `fallbackLang`，預設 `''`，`record.lang` 仍為 `''`，不受影響。

- [ ] **Step 5: Commit**

```bash
git add lib/models/gacha_record.dart test/models/gacha_record_test.dart
git commit -m "feat(gacha): add fallbackLang and copyWith to GachaRecord"
```

---

### Task 3: `fetchPage` 以 URL lang 補頌願新記錄

**Files:**
- Modify: `lib/services/gacha_fetcher.dart:105-127`（`fetchPage`）
- Test: `test/services/gacha_fetcher_test.dart`

- [ ] **Step 1: Write the failing test**

在 `test/services/gacha_fetcher_test.dart` 的 `group('GachaFetcher.fetchPage', () {` 內加入（接在既有 test 之後）：

```dart
    test('頌願回傳無 lang 時，以 URL 的 lang 補上', () async {
      final mock = MockClient(
        (req) async => _ok([
          {
            'uid': '801057625',
            'op_gacha_type': '20021',
            'item_id': '265044',
            'count': '1',
            'time': '2025-10-24 01:51:25',
            'item_name': 'x',
            'item_type': '裝扮套裝',
            'rank_type': '5',
            'id': '99',
          },
        ]),
      );
      final fetcher = GachaFetcher(rateLimit: Duration.zero);
      final page = await fetcher.fetchPage(
        GachaUrl.parse(
          _baseUrl,
        ).build(gachaType: '2000', endId: '0', endpoint: GachaEndpoint.odes),
        mock,
      );
      expect(page.records.first.lang, 'zh-tw');
    });
```

> `_baseUrl` 的 query 帶 `lang=zh-tw`，`build` 會保留，故 fetchPage 取得的 URL lang 為 `zh-tw`。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/gacha_fetcher_test.dart --plain-name "頌願回傳無 lang"`
Expected: FAIL — `Expected: 'zh-tw' Actual: ''`（fetchPage 尚未傳 fallbackLang）。

- [ ] **Step 3: Write minimal implementation**

在 `lib/services/gacha_fetcher.dart` 的 `fetchPage`：

在行 106 `final queryGachaType = url.queryParameters['gacha_type'] ?? '';` 之後新增一行：

```dart
    final queryLang = url.queryParameters['lang'] ?? '';
```

並把 `GachaRecord.fromApiJson(...)`（行 120-123）改為傳入 `fallbackLang`：

```dart
                (e) => GachaRecord.fromApiJson(
                  e as Map<String, dynamic>,
                  gachaType: queryGachaType,
                  fallbackLang: queryLang,
                ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/gacha_fetcher_test.dart`
Expected: PASS（All tests passed!）。既有測試不受影響（一般祈願 mock 帶 lang，fallback 不啟用）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/gacha_fetcher.dart test/services/gacha_fetcher_test.dart
git commit -m "feat(gacha): backfill odes record lang from URL on fetch"
```

---

### Task 4: `fetchBannerWithMerge` 回填既有空 lang 記錄

**Files:**
- Modify: `lib/services/gacha_fetcher.dart:206-208`（`fetchBannerWithMerge` 回傳段）
- Test: `test/services/gacha_fetcher_test.dart`

- [ ] **Step 1: Write the failing test**

先在 `test/services/gacha_fetcher_test.dart` 頂部 import 區（行 8 之後）加入 `GachaRecord` import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
```

在 `group('GachaFetcher.fetchBannerWithMerge', () {` 內加入兩個 test（接在既有兩個 test 之後）：

```dart
    test('既有空 lang 記錄回填為 URL 的 lang', () async {
      final client = MockClient((req) async => _ok(const []));
      final fetcher = GachaFetcher(rateLimit: Duration.zero);
      final existing = [
        GachaRecord(
          id: '50',
          uid: '801057625',
          gachaType: '2000',
          name: 'x',
          itemType: '裝扮套裝',
          rankType: 5,
          time: DateTime(2025, 10, 24, 1, 51, 25),
          lang: '',
        ),
      ];
      final merged = await fetcher.fetchBannerWithMerge(
        url: GachaUrl.parse(_baseUrl),
        gachaType: '2000',
        endpoint: GachaEndpoint.odes,
        existing: existing,
        primer: null,
        onProgress: (_) {},
        client: client,
      );
      expect(merged, hasLength(1));
      expect(merged.first.lang, 'zh-tw');
    });

    test('URL 無 lang 時不動既有記錄', () async {
      final client = MockClient((req) async => _ok(const []));
      final fetcher = GachaFetcher(rateLimit: Duration.zero);
      final existing = [
        GachaRecord(
          id: '50',
          uid: '801057625',
          gachaType: '2000',
          name: 'x',
          itemType: '裝扮套裝',
          rankType: 5,
          time: DateTime(2025, 10, 24, 1, 51, 25),
          lang: '',
        ),
      ];
      final merged = await fetcher.fetchBannerWithMerge(
        url: GachaUrl.parse(
          'https://example.com/gacha_info/api/getBeyondGachaLog'
          '?authkey=AAA&gacha_type=2000&end_id=0',
        ),
        gachaType: '2000',
        endpoint: GachaEndpoint.odes,
        existing: existing,
        primer: null,
        onProgress: (_) {},
        client: client,
      );
      expect(merged.first.lang, '');
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/gacha_fetcher_test.dart --plain-name "既有空 lang 記錄回填"`
Expected: FAIL — `Expected: 'zh-tw' Actual: ''`（尚未回填）。

- [ ] **Step 3: Write minimal implementation**

在 `lib/services/gacha_fetcher.dart` 的 `fetchBannerWithMerge`，把行 206-208：

```dart
    // fresh + existing 都是 desc
    _log.info('banner=$gachaType done, fresh=${fresh.length} pages=$pageIndex');
    return [...fresh, ...existing];
```

替換為：

```dart
    // fresh + existing 都是 desc
    _log.info('banner=$gachaType done, fresh=${fresh.length} pages=$pageIndex');

    // 頌願 API 不回傳 lang；既有空 lang 記錄以擷取 URL 的 lang 回填（一般祈願
    // existing 必有非空 lang，不受影響）。URL 缺 lang 則不動，避免以空蓋空。
    final urlLang = url.lang;
    final List<GachaRecord> normalizedExisting;
    if (urlLang.isEmpty) {
      normalizedExisting = existing;
    } else {
      var backfilled = 0;
      normalizedExisting = existing.map((r) {
        if (r.lang.isEmpty) {
          backfilled++;
          return r.copyWith(lang: urlLang);
        }
        return r;
      }).toList(growable: false);
      if (backfilled > 0) {
        _log.info(
          'banner=$gachaType backfilled lang for $backfilled records '
          'to "$urlLang"',
        );
      }
    }
    return [...fresh, ...normalizedExisting];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/gacha_fetcher_test.dart`
Expected: PASS（All tests passed!）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/gacha_fetcher.dart test/services/gacha_fetcher_test.dart
git commit -m "feat(gacha): backfill empty lang on existing odes records during merge"
```

---

### Task 5: 全量驗收

**Files:** 無（僅執行檢查）。

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected: 顯示已格式化檔案數，無錯誤。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全量測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 若格式化動到檔案則補一個 commit**

```bash
git add -A
git commit -m "style: dart format"
```

（若 `git status` 乾淨則略過此步。）

---

## Self-Review

**Spec coverage：**
- 「新抓頌願帶 URL lang」→ Task 2（fromApiJson fallback）＋ Task 3（fetchPage 傳入）。✔
- 「回填既有空 lang」→ Task 2（copyWith）＋ Task 4（merge 回填）。✔
- 「URL 缺 lang 不以空蓋空」→ Task 4 第二個 test 與 `urlLang.isEmpty` 分支。✔
- 「一般祈願不受影響」→ Task 2「API 已帶 lang 時 fallbackLang 被忽略」test、Task 4 通用 `isEmpty` 判斷。✔
- 「下游零副作用、無守衛」→ 設計層結論，無程式碼改動，無對應 task（正確）。✔
- 驗收（format / analyze / test 全綠）→ Task 5。✔

**Placeholder scan：** 無 TBD/TODO，所有步驟含實際程式碼與指令。✔

**Type consistency：** `fallbackLang`（具名、預設 `''`）、`copyWith({String? lang})`、`GachaUrl.lang`、`urlLang`／`normalizedExisting`／`backfilled` 在各 task 命名一致。Task 4 依賴 Task 1 的 `url.lang` 與 Task 2 的 `copyWith`，順序正確。✔
