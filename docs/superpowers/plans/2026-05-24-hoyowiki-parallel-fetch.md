# HoYoWiki Parallel Fetch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `_fetchHoYoWiki()` 三個串行階段（search → entry_page → download）改為階段內並行 worker-pool，並先用一次性探針量化各 host 的安全並行度。

**Architecture:** 分兩個 Phase。**Phase 0** 寫一支臨時 Dart 腳本（不進版控）對三個 host 各掃 1/2/4/8/16 並行度，輸出 Markdown 報告。**Phase 1** 把 `_fetchHoYoWiki` 三個 `for` 迴圈各換成 `runConcurrent` helper，三階段仍串行（資料依賴），階段內並行；`HoYoWikiIndexNotifier` 加 `Lock` 保護 read-modify-write；`HoYoWikiFetcher.rateLimit` 移除（並行度上限本身即是限流）。

**Tech Stack:** Dart 3.11 / Flutter, `package:http`, `package:logging`, **新增** `package:synchronized ^3.4.0`。

**Spec:** `docs/superpowers/specs/2026-05-24-hoyowiki-parallel-fetch-design.md`

---

## Phase 0：探針腳本（Milestone A）

### Task 1：`.gitignore` 加探針 pattern

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1：加 ignore pattern**

在 `.gitignore` 第 58 行 `/tool/i18n_port/` 下方插入：

```gitignore

# One-shot probes (run once, then discard locally — not tracked)
/tool/probe_*.dart
```

- [ ] **Step 2：驗證 pattern 生效**

```powershell
git check-ignore tool/probe_hoyowiki_concurrency.dart
```

Expected: 印 `tool/probe_hoyowiki_concurrency.dart`（被 ignored）

- [ ] **Step 3：Commit**

```powershell
git add .gitignore
git commit -m @'
chore(gitignore): ignore one-shot probe scripts under tool/

Reason: probe scripts (e.g. tool/probe_hoyowiki_concurrency.dart) are
local-only investigation tools, never meant to land in version control.
'@
```

---

### Task 2：寫探針腳本 `tool/probe_hoyowiki_concurrency.dart`

**Files:**
- Create: `tool/probe_hoyowiki_concurrency.dart`

- [ ] **Step 1：建立檔案**

`tool/probe_hoyowiki_concurrency.dart`：

```dart
// One-shot probe for HoYoWiki API concurrency safety.
// Run: dart run tool/probe_hoyowiki_concurrency.dart
// NOT tracked in git — delete after running.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';

/// 公開角色 / 武器名單，作為 search keyword（≈ 30 筆，中英混合）。
const _names = <(String name, String lang)>[
  ('胡桃', 'zh-tw'),
  ('鍾離', 'zh-tw'),
  ('雷電將軍', 'zh-tw'),
  ('神里綾華', 'zh-tw'),
  ('甘雨', 'zh-tw'),
  ('刻晴', 'zh-tw'),
  ('莫娜', 'zh-tw'),
  ('魈', 'zh-tw'),
  ('溫迪', 'zh-tw'),
  ('阿莫斯之弓', 'zh-tw'),
  ('天空之刃', 'zh-tw'),
  ('狼的末路', 'zh-tw'),
  ('飛雷之弦振', 'zh-tw'),
  ('磐岩結綠', 'zh-tw'),
  ('Hu Tao', 'en-us'),
  ('Zhongli', 'en-us'),
  ('Raiden Shogun', 'en-us'),
  ('Kamisato Ayaka', 'en-us'),
  ('Ganyu', 'en-us'),
  ('Keqing', 'en-us'),
  ('Mona', 'en-us'),
  ('Xiao', 'en-us'),
  ('Venti', 'en-us'),
  ("Amos' Bow", 'en-us'),
  ('Aquila Favonia', 'en-us'),
  ('Wolf\'s Gravestone', 'en-us'),
  ('Thundering Pulse', 'en-us'),
  ('Primordial Jade Cutter', 'en-us'),
  ('Diluc', 'en-us'),
  ('Jean', 'en-us'),
];

const _concurrencies = <int>[1, 2, 4, 8, 16];

/// 單一請求的結果。
class _ProbeResult {
  _ProbeResult({
    required this.success,
    required this.elapsedMs,
    this.statusCode,
    this.retcode,
    this.error,
  });
  final bool success;
  final int elapsedMs;
  final int? statusCode;
  final int? retcode;
  final String? error;
}

Future<void> _runConcurrent<T>({
  required List<T> items,
  required int concurrency,
  required Future<void> Function(T item) worker,
}) async {
  var next = 0;
  Future<void> spawn() async {
    while (true) {
      final i = next++;
      if (i >= items.length) return;
      await worker(items[i]);
    }
  }

  final n = math.min(concurrency, items.length);
  await Future.wait(List.generate(n, (_) => spawn()));
}

String _formatRow({
  required int conc,
  required List<_ProbeResult> results,
  required Duration wallclock,
}) {
  final ok = results.where((r) => r.success).toList();
  final times = ok.map((r) => r.elapsedMs).toList()..sort();
  final p50 = times.isEmpty ? '-' : times[times.length ~/ 2].toString();
  final p95 = times.isEmpty
      ? '-'
      : times[math.min(times.length - 1, (times.length * 0.95).ceil() - 1)]
            .toString();
  final blocked = results.length - ok.length;
  final statusDist = <int, int>{};
  for (final r in results) {
    if (r.statusCode == null) continue;
    statusDist[r.statusCode!] = (statusDist[r.statusCode!] ?? 0) + 1;
  }
  final retcodeDist = <int, int>{};
  for (final r in results) {
    if (r.retcode == null) continue;
    retcodeDist[r.retcode!] = (retcodeDist[r.retcode!] ?? 0) + 1;
  }
  final tput = wallclock.inMilliseconds == 0
      ? '-'
      : (ok.length / (wallclock.inMilliseconds / 1000)).toStringAsFixed(2);
  return '| $conc | ${ok.length}/${results.length} | $p50 | $p95 '
      '| $blocked | $statusDist | $retcodeDist | $tput |';
}

Future<List<_ProbeResult>> _probeSearch({
  required HoYoWikiFetcher fetcher,
  required http.Client client,
  required int concurrency,
}) async {
  final out = <_ProbeResult>[];
  await _runConcurrent<(String, String)>(
    items: _names,
    concurrency: concurrency,
    worker: (pair) async {
      final start = DateTime.now();
      try {
        await fetcher.searchEntryId(
          name: pair.$1,
          lang: pair.$2,
          client: client,
        );
        out.add(
          _ProbeResult(
            success: true,
            elapsedMs: DateTime.now().difference(start).inMilliseconds,
            statusCode: 200,
            retcode: 0,
          ),
        );
      } catch (e) {
        out.add(
          _ProbeResult(
            success: false,
            elapsedMs: DateTime.now().difference(start).inMilliseconds,
            error: e.toString(),
          ),
        );
      }
    },
  );
  return out;
}

Future<List<_ProbeResult>> _probeEntry({
  required HoYoWikiFetcher fetcher,
  required http.Client client,
  required List<String> ids,
  required int concurrency,
}) async {
  final out = <_ProbeResult>[];
  await _runConcurrent<String>(
    items: ids,
    concurrency: concurrency,
    worker: (id) async {
      final start = DateTime.now();
      try {
        await fetcher.fetchEntryPage(id: id, client: client);
        out.add(
          _ProbeResult(
            success: true,
            elapsedMs: DateTime.now().difference(start).inMilliseconds,
            statusCode: 200,
            retcode: 0,
          ),
        );
      } catch (e) {
        out.add(
          _ProbeResult(
            success: false,
            elapsedMs: DateTime.now().difference(start).inMilliseconds,
            error: e.toString(),
          ),
        );
      }
    },
  );
  return out;
}

Future<List<_ProbeResult>> _probeDownload({
  required HoYoWikiFetcher fetcher,
  required http.Client client,
  required List<String> urls,
  required int concurrency,
}) async {
  final out = <_ProbeResult>[];
  await _runConcurrent<String>(
    items: urls,
    concurrency: concurrency,
    worker: (url) async {
      final start = DateTime.now();
      try {
        final bytes = await fetcher.downloadImage(url, client);
        out.add(
          _ProbeResult(
            success: bytes != null,
            elapsedMs: DateTime.now().difference(start).inMilliseconds,
            statusCode: bytes != null ? 200 : null,
          ),
        );
      } catch (e) {
        out.add(
          _ProbeResult(
            success: false,
            elapsedMs: DateTime.now().difference(start).inMilliseconds,
            error: e.toString(),
          ),
        );
      }
    },
  );
  return out;
}

Future<void> main() async {
  final fetcher = HoYoWikiFetcher();
  final client = http.Client();
  try {
    // ----- baseline: search at concurrency 1 to collect ids + urls -----
    stdout.writeln('Collecting baseline samples (search at concurrency=1)…');
    final baseStart = DateTime.now();
    final baseResults = await _probeSearch(
      fetcher: fetcher,
      client: client,
      concurrency: 1,
    );
    final baseWall = DateTime.now().difference(baseStart);

    // 再跑一輪取得 ids（baseResults 不含 ids，需要實際 search 拿到 hit）
    final ids = <String>{};
    for (final pair in _names) {
      try {
        final hit = await fetcher.searchEntryId(
          name: pair.$1,
          lang: pair.$2,
          client: client,
        );
        if (hit != null) ids.add(hit.id);
      } catch (_) {}
    }
    if (ids.length < 5) {
      stderr.writeln(
        'search baseline insufficient: hit ${ids.length}/${_names.length}, abort',
      );
      exit(2);
    }
    stdout.writeln('baseline: search hit ${ids.length}/${_names.length}');

    // 從 entry 取得 urls
    final urls = <String>[];
    for (final id in ids) {
      try {
        final e = await fetcher.fetchEntryPage(id: id, client: client);
        if (e.iconUrl.isNotEmpty) urls.add(e.iconUrl);
        if (e.headerImgUrl.isNotEmpty) urls.add(e.headerImgUrl);
      } catch (_) {}
    }
    stdout.writeln('baseline: entry produced ${urls.length} image urls\n');

    // ----- search -----
    stdout.writeln('## search (sg-act-public-api.hoyolab.com)');
    stdout.writeln(
      '| conc | success | p50 (ms) | p95 (ms) | blocked '
      '| status dist | retcode dist | throughput (req/s) |',
    );
    stdout.writeln(
      '|------|---------|----------|----------|---------'
      '|-------------|--------------|--------------------|',
    );
    stdout.writeln(
      _formatRow(conc: 1, results: baseResults, wallclock: baseWall),
    );
    for (final c in _concurrencies.where((c) => c != 1)) {
      final start = DateTime.now();
      final r = await _probeSearch(
        fetcher: fetcher,
        client: client,
        concurrency: c,
      );
      stdout.writeln(
        _formatRow(
          conc: c,
          results: r,
          wallclock: DateTime.now().difference(start),
        ),
      );
    }
    stdout.writeln('');

    // ----- entry -----
    stdout.writeln('## entry_page (sg-act-public-api-static.hoyolab.com)');
    stdout.writeln(
      '| conc | success | p50 (ms) | p95 (ms) | blocked '
      '| status dist | retcode dist | throughput (req/s) |',
    );
    stdout.writeln(
      '|------|---------|----------|----------|---------'
      '|-------------|--------------|--------------------|',
    );
    for (final c in _concurrencies) {
      final start = DateTime.now();
      final r = await _probeEntry(
        fetcher: fetcher,
        client: client,
        ids: ids.toList(),
        concurrency: c,
      );
      stdout.writeln(
        _formatRow(
          conc: c,
          results: r,
          wallclock: DateTime.now().difference(start),
        ),
      );
    }
    stdout.writeln('');

    // ----- download -----
    stdout.writeln('## download (image CDN)');
    stdout.writeln(
      '| conc | success | p50 (ms) | p95 (ms) | blocked '
      '| status dist | retcode dist | throughput (req/s) |',
    );
    stdout.writeln(
      '|------|---------|----------|----------|---------'
      '|-------------|--------------|--------------------|',
    );
    for (final c in _concurrencies) {
      final start = DateTime.now();
      final r = await _probeDownload(
        fetcher: fetcher,
        client: client,
        urls: urls,
        concurrency: c,
      );
      stdout.writeln(
        _formatRow(
          conc: c,
          results: r,
          wallclock: DateTime.now().difference(start),
        ),
      );
    }
  } finally {
    client.close();
  }
}
```

- [ ] **Step 2：格式化與分析**

```powershell
dart format tool/probe_hoyowiki_concurrency.dart
```

Expected: 印 `Formatted 1 file` 或 `Unchanged 1 file`。

```powershell
dart analyze tool/probe_hoyowiki_concurrency.dart
```

Expected: `No issues found!`。

- [ ] **Step 3：驗證沒被 git tracked**

```powershell
git status
```

Expected: 工作目錄 clean（`.gitignore` 已 commit、`tool/probe_*.dart` 已 ignored，新檔不出現）。

---

### Task 3：跑探針並向使用者拿到 production 並行度決策

- [ ] **Step 1：執行探針**

```powershell
dart run tool/probe_hoyowiki_concurrency.dart
```

Expected: stdout 印三張 Markdown 表（search / entry_page / download），每張 5 行（並行度 1/2/4/8/16）。整段執行時間 ≈ 3–5 分鐘。

若印 `search baseline insufficient: hit X/30, abort` → hardcode 名單失效或 search API 整段掛，停下回報使用者，不要硬跑。

- [ ] **Step 2：向使用者呈現報告，請使用者決定三個 hardcode 並行度**

把 stdout 內容原樣貼回 user 並用 AskUserQuestion 問：

> "依下面探針報告，請決定 production hardcode 並行度。各 host 推薦取『success 100% 的最高並行度』與 8 兩者取小。「跌破 2」（即 success < 100% @ conc=2）的 host 維持並行度 1。三個 host 全跌破 2 → spec 標 Rejected。"

問項：
- `searchConcurrency` (預設建議: 4)
- `entryConcurrency` (預設建議: 4)
- `downloadConcurrency` (預設建議: 8)

- [ ] **Step 3：把使用者決定的三個值記下**

之後 Task 6 會用到這三個值。

---

## Phase 1：Production 平行化改寫（Milestone B）

### Task 4：加 `synchronized` 依賴

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock` (auto-regenerate)

- [ ] **Step 1：加 dependency**

在 `pubspec.yaml` 的 `dependencies:` 區塊（介於 `super_clipboard:` 與 `dev_dependencies:` 之間）加：

```yaml
  super_clipboard: ^0.9.1
  synchronized: ^3.4.0

dev_dependencies:
```

- [ ] **Step 2：拉新依賴**

```powershell
flutter pub get
```

Expected: 解析成功，`pubspec.lock` 更新（會新增 `synchronized` entry）。

- [ ] **Step 3：Commit**

```powershell
git add pubspec.yaml pubspec.lock
git commit -m @'
chore(deps): add synchronized ^3.4.0

Reason: HoYoWiki parallel fetch refactor needs a mutex to protect
HoYoWikiIndexNotifier's read-modify-write paths from concurrent
worker-pool writes.
'@
```

---

### Task 5：新增 `runConcurrent` helper（TDD）

**Files:**
- Test: `test/services/concurrent_pool_test.dart`
- Create: `lib/services/concurrent_pool.dart`

- [ ] **Step 1：寫失敗測試**

建 `test/services/concurrent_pool_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/concurrent_pool.dart';

void main() {
  group('runConcurrent', () {
    test('N 個 worker 真同時 in-flight', () async {
      final completers = List.generate(8, (_) => Completer<void>());
      var maxInFlight = 0;
      var current = 0;
      final futures = runConcurrent<int>(
        items: List.generate(8, (i) => i),
        concurrency: 4,
        shouldAbort: () => false,
        worker: (i) async {
          current++;
          if (current > maxInFlight) maxInFlight = current;
          await completers[i].future;
          current--;
        },
      );
      // 等所有 worker 都進到 await
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(maxInFlight, 4);
      for (final c in completers) {
        c.complete();
      }
      await futures;
    });

    test('單一 worker 拋例外不中斷其他 worker', () async {
      final done = <int>[];
      await runConcurrent<int>(
        items: const [0, 1, 2, 3, 4],
        concurrency: 2,
        shouldAbort: () => false,
        worker: (i) async {
          if (i == 2) throw StateError('boom');
          done.add(i);
        },
      );
      expect(done..sort(), [0, 1, 3, 4]);
    });

    test('shouldAbort 第一輪即 true 時不執行任何 item', () async {
      final done = <int>[];
      await runConcurrent<int>(
        items: const [0, 1, 2],
        concurrency: 2,
        shouldAbort: () => true,
        worker: (i) async {
          done.add(i);
        },
      );
      expect(done, isEmpty);
    });

    test('items 為空時不起任何 worker，立刻 resolve', () async {
      var calls = 0;
      await runConcurrent<int>(
        items: const [],
        concurrency: 4,
        shouldAbort: () => false,
        worker: (_) async {
          calls++;
        },
      );
      expect(calls, 0);
    });

    test('completion 順序不保證但所有 item 都跑過', () async {
      final done = <int>[];
      await runConcurrent<int>(
        items: List.generate(20, (i) => i),
        concurrency: 5,
        shouldAbort: () => false,
        worker: (i) async {
          await Future<void>.delayed(Duration(milliseconds: (i * 7) % 20));
          done.add(i);
        },
      );
      expect(done..sort(), List.generate(20, (i) => i));
    });
  });
}
```

- [ ] **Step 2：跑測試確認失敗**

```powershell
flutter test test/services/concurrent_pool_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:.../concurrent_pool.dart'`。

- [ ] **Step 3：實作 helper**

建 `lib/services/concurrent_pool.dart`：

```dart
import 'dart:async';
import 'dart:math' as math;

/// 跑 [items] 一輪，最多 [concurrency] 個 worker 同時 in-flight。
///
/// - [worker] 拋例外不會中斷其他 worker；caller 應在 worker 內自行 try/catch
///   並決定是否要 swallow。
/// - [shouldAbort] 在每個 worker 取下一筆前查；回 true 即所有 worker 早退。
/// - items 完成順序不保證，caller 不可依賴。
/// - [concurrency] 必須 ≥ 1，否則拋 [ArgumentError]。
Future<void> runConcurrent<T>({
  required List<T> items,
  required int concurrency,
  required Future<void> Function(T item) worker,
  required FutureOr<bool> Function() shouldAbort,
}) async {
  if (concurrency < 1) {
    throw ArgumentError.value(concurrency, 'concurrency', 'must be >= 1');
  }
  if (items.isEmpty) return;

  var next = 0;

  Future<void> spawn() async {
    while (true) {
      if (await shouldAbort()) return;
      final i = next++;
      if (i >= items.length) return;
      try {
        await worker(items[i]);
      } catch (_) {
        // 吞掉避免中斷其他 worker；caller 自行 log。
      }
    }
  }

  final n = math.min(concurrency, items.length);
  await Future.wait(List.generate(n, (_) => spawn()));
}
```

- [ ] **Step 4：跑測試確認通過**

```powershell
flutter test test/services/concurrent_pool_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5：格式化、分析**

```powershell
dart format lib/ test/
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 6：Commit**

```powershell
git add lib/services/concurrent_pool.dart test/services/concurrent_pool_test.dart
git commit -m @'
feat(util): add runConcurrent worker-pool helper

Generic helper that runs N workers in parallel against a list of items,
with per-iteration abort check and exception isolation. Used by the
upcoming HoYoWiki parallel fetch refactor.
'@
```

---

### Task 6：改 `HoYoWikiFetcher`——加並行度欄位、移除 `rateLimit`

**Files:**
- Modify: `lib/services/hoyowiki_fetcher.dart`
- Modify: `test/services/hoyowiki_fetcher_test.dart` (23 處)
- Modify: `test/state/gacha_repository_hoyowiki_test.dart` (1 處)
- Modify: `test/state/gacha_repository_refetch_test.dart` (4 處)

> **重要：** 把 Task 3 拿到的三個並行度值填入下方 `_kSearch` / `_kEntry` / `_kDownload`。本 plan 用「預設保守值 4 / 4 / 8」做佔位；若 Task 3 結論不同，請改成實測值再 commit。

- [ ] **Step 1：改 HoYoWikiFetcher**

`lib/services/hoyowiki_fetcher.dart` 的 class 定義（行 39–55）改成：

```dart
/// 與 HoYoLab Wiki API 互動的 fetcher，涵蓋 search / entry_page / image download。
class HoYoWikiFetcher {
  /// 建立 [HoYoWikiFetcher]，可調整各階段並行度與逾時。
  HoYoWikiFetcher({
    this.searchConcurrency = 4,
    this.entryConcurrency = 4,
    this.downloadConcurrency = 8,
    this.timeout = const Duration(seconds: 10),
  });

  /// search 階段 worker-pool 同時 in-flight 上限。
  final int searchConcurrency;

  /// entry_page 階段 worker-pool 同時 in-flight 上限。
  final int entryConcurrency;

  /// download 階段 worker-pool 同時 in-flight 上限。
  final int downloadConcurrency;

  /// 單次 HTTP 請求超時。
  final Duration timeout;

  /// Logger 實例（gacha.hoyowiki 命名空間，對齊既有 `gacha.fetcher`）。
  static final _log = Logger('gacha.hoyowiki');
```

> 注意：上方預設值 `4 / 4 / 8` 若與 Task 3 探針結論不一致，請以 Task 3 結論為準改寫後再進 Step 2。

- [ ] **Step 2：批次更新測試 fixture**

下列三檔，所有 `HoYoWikiFetcher(rateLimit: Duration.zero)` 字串都替換成 `HoYoWikiFetcher()`：

`test/services/hoyowiki_fetcher_test.dart`（23 處）：Edit `replace_all`：
- old: `HoYoWikiFetcher(rateLimit: Duration.zero)`
- new: `HoYoWikiFetcher()`

`test/state/gacha_repository_hoyowiki_test.dart`（1 處）：同上 replace_all。

`test/state/gacha_repository_refetch_test.dart`（4 處）：同上 replace_all。

- [ ] **Step 3：跑相關測試**

```powershell
flutter test test/services/hoyowiki_fetcher_test.dart test/state/gacha_repository_hoyowiki_test.dart test/state/gacha_repository_refetch_test.dart
```

Expected: `All tests passed!`（既有測試行為不變，僅替換 constructor）。

> **若失敗**：檢查 `lib/state/gacha_repository.dart:796` 那行 `final fetcherDelay = ref.read(hoyowikiFetcherProvider).rateLimit;`——它會編譯失敗，但 Task 8 才會處理；本 task 編譯失敗時暫時把那行改成 `final fetcherDelay = Duration.zero;` 以通過 build，Task 8 會徹底刪除整段 `checkCancel` 邏輯。

- [ ] **Step 4：格式化、分析**

```powershell
dart format lib/ test/
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 5：Commit**

```powershell
git add lib/services/hoyowiki_fetcher.dart test/services/hoyowiki_fetcher_test.dart test/state/gacha_repository_hoyowiki_test.dart test/state/gacha_repository_refetch_test.dart lib/state/gacha_repository.dart
git commit -m @'
feat(hoyowiki): swap rateLimit for per-phase concurrency knobs

Drop HoYoWikiFetcher.rateLimit (caller-paced sleep no longer needed
once we move to worker-pool parallelism). Add searchConcurrency,
entryConcurrency, downloadConcurrency hardcoded constants tuned by
the one-shot concurrency probe (see spec for measurements).
'@
```

---

### Task 7：`HoYoWikiIndexNotifier` 加 `Lock` 保護 read-modify-write

**Files:**
- Test: `test/state/hoyowiki_index_test.dart` (新增測試)
- Modify: `lib/state/hoyowiki_index.dart`

- [ ] **Step 1：寫失敗測試**

在 `test/state/hoyowiki_index_test.dart` 加新 group（檔尾）：

```dart
  group('HoYoWikiIndexNotifier concurrent writes', () {
    test('並發 setEntry 全部寫入不丟失', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'hoyowiki_index_race_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final container = ProviderContainer(
        overrides: [
          hoyowikiIndexStorageProvider.overrideWithValue(
            _SlowSaveStorage(tempDir),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.waitForLoad();

      // 同時跑 10 個 setEntry：無 lock 時各自從相同 baseline Map.from(state.entries)
      // 拿快照、寫回時後者覆蓋前者，final 只剩最後一筆。
      await Future.wait([
        for (var i = 0; i < 10; i++)
          notifier.setEntry(
            id: 'id_$i',
            entry: HoYoWikiEntry(
              iconUrl: 'http://x/$i.png',
              headerImgUrl: '',
              fetchedAt: DateTime.utc(2026, 5, 24),
            ),
          ),
      ]);

      final finalState = container.read(hoyowikiIndexProvider);
      expect(finalState.entries.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(finalState.entries['id_$i']?.iconUrl, 'http://x/$i.png');
      }
    });
  });
}

/// 強制 save 內出現 async gap，迫使 read-modify-write race 觀察得到。
class _SlowSaveStorage extends HoYoWikiIndexStorage {
  _SlowSaveStorage(super.baseDir);

  @override
  Future<void> save(HoYoWikiIndex index) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await super.save(index);
  }
}
```

> 注意：上方 test 假設既有檔頂已 import `ProviderContainer` / `Directory` / `HoYoWikiEntry` / `HoYoWikiIndexStorage` / `hoyowikiIndexProvider` / `hoyowikiIndexStorageProvider`。先讀檔頂 import 區，缺什麼補什麼。

- [ ] **Step 2：跑測試確認失敗**

```powershell
flutter test test/state/hoyowiki_index_test.dart -p vm --name "並發 setEntry 全部寫入不丟失"
```

Expected: FAIL — `finalState.entries.length` 小於 10（典型 race 結果）。

> **若不 FAIL**：可能 scheduler interleaving 不夠激烈。把 `_SlowSaveStorage.save` 的 delay 從 5ms 改成 50ms 重跑。仍不 FAIL → 既有 implementation 已 atomic（不太可能），改觀察 `state` mutation 是否 race。

- [ ] **Step 3：實作 lock**

`lib/state/hoyowiki_index.dart` 檔頂 import 加：

```dart
import 'package:synchronized/synchronized.dart';
```

但 `HoYoWikiIndexNotifier` 在 `lib/state/hoyowiki_index.dart` 還是 `lib/services/hoyowiki_index.dart`？檢查：notifier 在 **`lib/state/hoyowiki_index.dart`**（不是 services）。改 `lib/state/hoyowiki_index.dart`：

檔頂 import 區加：

```dart
import 'package:synchronized/synchronized.dart';
```

`HoYoWikiIndexNotifier` class 內加 `_lock` 欄位（在 `_loadCompleter` 旁邊）：

```dart
class HoYoWikiIndexNotifier extends Notifier<HoYoWikiIndex> {
  static final _log = Logger('gacha.hoyowiki.notifier');

  Completer<void>? _loadCompleter;

  /// 保護 setSearch / setEntry 的 read-modify-write，避免並發 worker 互相覆蓋。
  final _lock = Lock();
```

把 `setSearch` 與 `setEntry` body 整段包進 `_lock.synchronized`：

```dart
  Future<void> setSearch({
    required String name,
    required String lang,
    required String id,
    required int menuId,
  }) async {
    await _lock.synchronized(() async {
      final newSearch = Map<String, String>.from(state.searchMap)
        ..['$lang::$name'] = id;
      final newMenuIds = Map<String, int>.from(state.menuIds)..[id] = menuId;
      final next = HoYoWikiIndex(
        searchMap: newSearch,
        entries: state.entries,
        menuIds: newMenuIds,
      );
      await _saveAndEmit(next);
    });
  }

  Future<void> setEntry({
    required String id,
    required HoYoWikiEntry entry,
  }) async {
    await _lock.synchronized(() async {
      final newEntries = Map<String, HoYoWikiEntry>.from(state.entries)
        ..[id] = entry;
      final next = HoYoWikiIndex(
        searchMap: state.searchMap,
        entries: newEntries,
        menuIds: state.menuIds,
      );
      await _saveAndEmit(next);
    });
  }
```

`bumpCacheRevision` 不入 lock（純 identity bump，無 read-modify-write）。
`resetAll` 不入 lock（呼叫時序保證單一進入，且涉及檔案系統 wipe）。

- [ ] **Step 4：跑測試確認通過**

```powershell
flutter test test/state/hoyowiki_index_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5：跑全套測試確認既有測試未壞**

```powershell
flutter test
```

Expected: `All tests passed!`

- [ ] **Step 6：格式化、分析**

```powershell
dart format lib/ test/
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 7：Commit**

```powershell
git add lib/state/hoyowiki_index.dart test/state/hoyowiki_index_test.dart
git commit -m @'
fix(hoyowiki): guard index notifier writes with a Lock

setSearch / setEntry do read-modify-write on the state map. Once the
fetch pipeline goes parallel in the next commit, concurrent workers
would race and lose updates. Wrap both methods in a single Lock; add
regression test that proves the race surfaces without the lock.
'@
```

---

### Task 8：改 `_fetchHoYoWiki` 三個 for 迴圈為 `runConcurrent`

**Files:**
- Modify: `lib/state/gacha_repository.dart`
- Test: `test/state/gacha_repository_hoyowiki_test.dart` (新增 concurrency + cancel 測試)

- [ ] **Step 1：改 `_fetchHoYoWiki` 三個迴圈**

`lib/state/gacha_repository.dart` 檔頂 import 區加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/concurrent_pool.dart';
```

`_fetchHoYoWiki` 函式內，刪除「`final fetcherDelay = ...` 加上 `Future<bool> checkCancel()` 助手」整段（行 796–803），改寫三個階段（行 805–904）為：

```dart
    bool isAborted() => !ref.mounted || _cancelTriggered;

    // (1) search 階段
    if (searchTodo.isNotEmpty) {
      var doneSearch = 0;
      await runConcurrent<(String, String)>(
        items: searchTodo,
        concurrency: fetcher.searchConcurrency,
        shouldAbort: isAborted,
        worker: (pair) async {
          try {
            final hit = await fetcher.searchEntryId(
              name: pair.$1,
              lang: pair.$2,
              client: client,
            );
            if (hit != null) {
              await indexNotifier.setSearch(
                name: pair.$1,
                lang: pair.$2,
                id: hit.id,
                menuId: hit.menuId,
              );
              if (!entryTodo.contains(hit.id) &&
                  needRefetchEntry(
                    ref.read(hoyowikiIndexProvider).lookupEntry(hit.id),
                    hit.menuId,
                  )) {
                entryTodo.add(hit.id);
              }
            }
          } catch (e) {
            _log.warning('hoyowiki search failed name=${pair.$1} err=$e');
          }
          if (!ref.mounted) return;
          doneSearch++;
          state = state.copyWith(
            progress: FetchingHoYoWiki(
              phase: HoYoWikiPhase.searching,
              doneCount: doneSearch,
              totalCount: searchTodo.length,
            ),
          );
        },
      );
      if (isAborted()) return downloaded;
    }

    // (2) entry 階段
    if (entryTodo.isNotEmpty) {
      final entryList = entryTodo.toList();
      var doneEntry = 0;
      await runConcurrent<String>(
        items: entryList,
        concurrency: fetcher.entryConcurrency,
        shouldAbort: isAborted,
        worker: (id) async {
          try {
            final fetched = await fetcher.fetchEntryPage(
              id: id,
              client: client,
            );
            final entry = HoYoWikiEntry(
              iconUrl: fetched.iconUrl,
              headerImgUrl: fetched.headerImgUrl,
              fetchedAt: DateTime.now().toUtc(),
            );
            await indexNotifier.setEntry(id: id, entry: entry);
            enqueueDownloadsForEntry(id, entry);
          } catch (e) {
            _log.warning('hoyowiki entry failed id=$id err=$e');
          }
          if (!ref.mounted) return;
          doneEntry++;
          state = state.copyWith(
            progress: FetchingHoYoWiki(
              phase: HoYoWikiPhase.fetchingEntries,
              doneCount: doneEntry,
              totalCount: entryList.length,
            ),
          );
        },
      );
      if (isAborted()) return downloaded;
    }

    // (3) download 階段
    if (downloadTodo.isNotEmpty) {
      var doneDownload = 0;
      await runConcurrent<_HoYoWikiDownloadItem>(
        items: downloadTodo,
        concurrency: fetcher.downloadConcurrency,
        shouldAbort: isAborted,
        worker: (item) async {
          try {
            final bytes = await fetcher.downloadImage(item.url, client);
            if (bytes != null) {
              final file = hoyowikiCacheFile(
                baseDir: cacheDir,
                id: item.id,
                kind: item.kind,
                url: item.url,
              );
              await file.writeAsBytes(bytes, flush: true);
              indexNotifier.bumpCacheRevision();
              downloaded++;
            }
          } catch (e) {
            _log.warning(
              'hoyowiki download failed url=${item.url} err=$e',
            );
          }
          if (!ref.mounted) return;
          doneDownload++;
          state = state.copyWith(
            progress: FetchingHoYoWiki(
              phase: HoYoWikiPhase.downloading,
              doneCount: doneDownload,
              totalCount: downloadTodo.length,
            ),
          );
        },
      );
      if (isAborted()) return downloaded;
    }
    return downloaded;
  }
```

> 注意：`enqueueDownloadsForEntry` 是 closure，會操作 `downloadTodo` list。entry worker 並行呼叫 `enqueueDownloadsForEntry` 會對 list `add`——Dart `List.add` 在單 isolate 內不會 race（不會丟元素），但兩個 worker 同時 enqueue 順序不固定，這不影響功能；download 階段在 entry 階段完全結束後才啟動，無 reader/writer 同時存在。

> 注意：`downloaded++` 在多個 worker 內被遞增。Dart 單 isolate scheduling 下 `int++` 不會 race（純值操作非 await 邊界），不需 lock。

- [ ] **Step 2：跑既有測試確認最終結果一致**

```powershell
flutter test test/state/gacha_repository_hoyowiki_test.dart test/state/gacha_repository_refetch_test.dart
```

Expected: `All tests passed!`（既有測試斷言 final state、不依賴 progress 推進順序）。

> **若失敗**：檢查失敗測試是否斷言 `doneCount: i + 1` 嚴格遞增 1。若有，因為 worker 並發完成順序不固定，會看到 `doneCount` 跳號（仍嚴格單調 ≤ totalCount）。改測試斷言為「最終 doneCount == totalCount」或「doneCount 嚴格單調遞增」即可。

- [ ] **Step 3：新增 concurrency 生效測試**

在 `test/state/gacha_repository_hoyowiki_test.dart` 加：

```dart
  test('download 階段 concurrency 生效（N workers 同時 in-flight）', () async {
    final pending = <Completer<List<int>>>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': req.url.queryParameters['keyword'],
                  'entry_page_id': '111_${req.url.queryParameters['keyword']}',
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
        final id = req.url.queryParameters['entry_page_id']!;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {
                'icon_url': 'https://x/$id-icon.png',
                'header_img_url': '',
              },
            },
          }),
          200,
        );
      }
      // image download
      final c = Completer<List<int>>();
      pending.add(c);
      final bytes = await c.future;
      return http.Response.bytes(bytes, 200);
    });

    tempDir = await Directory.systemTemp.createTemp('gacha_concurrency_test_');
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 23),
        banners: {
          '301': [
            for (var i = 0; i < 12; i++)
              _rec(id: '$i', name: 'Char$i', gachaType: '301'),
          ],
          '302': [],
          '500': [],
          '200': [],
          '100': [],
        },
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoYoWikiFetcher(
            searchConcurrency: 4,
            entryConcurrency: 4,
            downloadConcurrency: 3,
          ),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    final repoFuture = container
        .read(gachaRepositoryProvider.notifier)
        .debugRunHoYoWikiOnly();

    // 讓 search + entry 跑完，停在 download stage
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(pending.length, 3, reason: 'download concurrency = 3 應同時 in-flight 3 筆');

    // 完成所有 pending 讓 pipeline 跑完
    for (final c in pending) {
      c.complete(List<int>.filled(4, 0));
    }
    // 後續還有 12-3 = 9 筆會陸續上來
    while (pending.length < 12) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final c in pending.where((c) => !c.isCompleted)) {
        c.complete(List<int>.filled(4, 0));
      }
    }
    await repoFuture;
  });
```

> 注意：這個 test 內 `apiClient` 的 image download branch 用 Completer 控制完成時機。MockClient 的 callback 是 `async`，所以 `await c.future` 不會卡 server；但 client 端會 await 它的 response，這正是我們要的「同時 in-flight」訊號。

- [ ] **Step 4：新增 cancel 在 worker 內生效測試**

接在上一個 test 之後：

```dart
  test('cancel 在 worker 取下一筆前生效，其餘 item 不被 dispatch', () async {
    final dispatched = <String>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        final kw = req.url.queryParameters['keyword']!;
        dispatched.add(kw);
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': kw,
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
      return http.Response('{}', 200);
    });

    tempDir = await Directory.systemTemp.createTemp('gacha_cancel_test_');
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 23),
        banners: {
          '301': [
            for (var i = 0; i < 50; i++)
              _rec(id: '$i', name: 'Char$i', gachaType: '301'),
          ],
          '302': [],
          '500': [],
          '200': [],
          '100': [],
        },
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoYoWikiFetcher(searchConcurrency: 2),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    // 開跑 + 馬上取消
    final repoFuture = container
        .read(gachaRepositoryProvider.notifier)
        .debugRunHoYoWikiOnly();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    container.read(gachaRepositoryProvider.notifier).cancelUpdate();
    await repoFuture;

    // 50 筆中只應 dispatch 少數幾筆（不可能 50 全跑）
    expect(dispatched.length, lessThan(50));
  });
```

> 注意：若 `cancelUpdate` 方法名實際叫別的（例如 `cancel` / `cancelActive`），改成實際名稱。先 `Grep` 找：`grep "_cancelTriggered = true" lib/state/gacha_repository.dart`，看哪個 public method 設它為 true。

- [ ] **Step 5：跑新測試確認通過**

```powershell
flutter test test/state/gacha_repository_hoyowiki_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6：跑全套測試**

```powershell
flutter test
```

Expected: `All tests passed!`

- [ ] **Step 7：格式化、分析**

```powershell
dart format lib/ test/
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 8：Commit**

```powershell
git add lib/state/gacha_repository.dart test/state/gacha_repository_hoyowiki_test.dart
git commit -m @'
perf(hoyowiki): parallelize three-phase fetch with worker pools

Each of the three phases (search, entry_page, download) now runs its
items through runConcurrent at the per-phase hardcoded concurrency.
The 600ms per-item sleep is gone — the worker-pool size itself is the
rate limit. Phases remain serial (data dependency: search emits ids,
entry emits urls). Cancellation now checks before each worker dequeue,
so abort latency is bounded by the longest in-flight item.

Tests added: download N workers in-flight, cancel mid-flight bounds
dispatched items.
'@
```

---

### Task 9：手動驗證

- [ ] **Step 1：啟動 app**

```powershell
flutter run -d windows
```

Expected: app 開啟、可進入「設定」頁。

- [ ] **Step 2：跑強制重抓**

進「設定」→ 點「強制重抓所有 HoYoWiki 圖片」→ 確認 dialog 內按執行。

- [ ] **Step 3：對照耗時**

觀察 progress 進度條 — 三階段 doneCount 應流暢推進至 totalCount。整段耗時應**至少是改寫前的 2 倍快**（具體倍數取決於 Task 3 拿到的並行度）。

- [ ] **Step 4：撈 log 確認無被擋**

從應用程式內的「設定 → 匯出 log」拿到 log 檔，`grep` 看是否出現：

```powershell
Select-String -Path "<匯出的 log 路徑>" -Pattern "(429|403|418|non-2xx)" -CaseSensitive
```

Expected: 無命中。若有 429 / 403 → 調低 `HoYoWikiFetcher` 預設 concurrency 後 commit 修正。

- [ ] **Step 5：回報使用者**

向 user 報告：「強制重抓 X 張圖耗時 Y 秒（改前 Z 秒，加速 Y/Z 倍），log 無 429/403。是否驗收？」等使用者 OK。

> 若使用者回報實測有問題（429 / 卡住 / progress 凍結等），不要急著加 retry/backoff。先回到 spec 重新評估、必要時調 concurrency 預設值並 commit 修正。

---

### Task 10：刪掉探針腳本

**Files:**
- Delete: `tool/probe_hoyowiki_concurrency.dart`

- [ ] **Step 1：刪檔**

```powershell
Remove-Item tool/probe_hoyowiki_concurrency.dart
```

- [ ] **Step 2：確認 git status 不顯示刪除**

```powershell
git status
```

Expected: 工作目錄 clean（探針從未進版控，刪除不影響 git）。

- [ ] **Step 3：不需 commit**

探針本就在 `.gitignore` 內，無需任何 git 操作。

---

## 完工驗收

- [ ] `dart format lib/ test/` 過
- [ ] `flutter analyze` → `No issues found!`
- [ ] `flutter test` → `All tests passed!`
- [ ] 強制重抓圖片實測加速 ≥ 2× 且 log 無 429/403
- [ ] `tool/probe_hoyowiki_concurrency.dart` 已刪除
- [ ] `.gitignore` `tool/probe_*.dart` pattern 已 commit
- [ ] 使用者口頭驗收
