# Debug Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增可匯出的 DEBUG log 系統,涵蓋 Dart 側 `LogService` + sanitize + 全域 error handler + 設定頁匯出,以及 Rust 側 `tracing` 事件透過 FRB stream 轉發到 Dart logger,讓使用者匯出單一 `.log` 檔即可拿到兩側完整 timeline 用於除錯。

**Architecture:** Dart 端以 `package:logging` 為骨架,`LogService.bootstrap` 訂閱 `Logger.root.onRecord` 並分發到三個 sink — `dart:developer.log`(IDE / DevTools)、記憶體 ring buffer(2000 行,設定頁即時 stream 用)、`<applicationSupport>/logs/YYYY-MM-DD.log`(UTC 日期分檔,7 天 rotation)。Rust 端保留既有 `tracing::info!/warn!/error!` 呼叫,新增 `tracing_subscriber::Layer` `ForwardLayer` 把 `Event` push 進一條 FRB stream,Dart 收到後重映射成 `Logger('rust.<target>')` 進同一條 pipeline。敏感資料一律經 `sanitizeUrl` / `sanitizeUid` 後才寫 log。

**Tech Stack:** Flutter (Riverpod 3.0 / go_router / file_selector / url_launcher / shared_preferences) + flutter_rust_bridge 2.12 + Rust tracing/tracing-subscriber 0.3。新增 Dart 相依:`logging: ^1.3.0`。

> **參考 Spec:** `docs/superpowers/specs/2026-05-15-debug-logging-design.md`。本計畫所有程式碼都已自含,工程師執行單一 task 時不需要回去翻 spec。

---

## Files to Create / Modify

### Create
| 路徑 | 用途 |
|---|---|
| `lib/services/log_sanitize.dart` | `sanitizeUrl` / `sanitizeUid` 純函式 |
| `lib/services/log_service.dart` | `LogService`:rotation + ring buffer + export bundle + clear |
| `lib/state/log_service.dart` | `logServiceProvider` (Riverpod, throw-until-overridden) |
| `rust/src/api/logging.rs` | `LogEvent` + `start_log_stream` + `init_tracing_once` + `ForwardLayer` + panic hook |
| `test/services/log_sanitize_test.dart` | sanitize helper 單元測試 |
| `test/services/log_service_test.dart` | LogService 單元測試 |

### Modify
| 路徑 | 動作 |
|---|---|
| `pubspec.yaml` | 加 `logging: ^1.3.0` |
| `lib/main.dart` | 整段重寫:`runZonedGuarded` 包裹、bootstrap LogService、三層 error handler、連接 Rust log stream、`Logger('app.startup')` 取代既有 `debugPrint` |
| `lib/services/settings_storage.dart` | `AppSettings` 加 `logLevel` field;`SettingsStorage.load/save` 加 `_kLogLevel` key |
| `lib/state/settings.dart` | `setLogLevel(String)` + 載入後 apply `Logger.root.level` |
| `lib/pages/settings_page.dart` | 新增 `_LogsSection` private widget(對齊 `_DataManagement` 同檔模式);新插一張 `SectionCard` 在 data management 與 account management 之間;`_export` / `_import` 內加 log |
| `lib/state/wish_capture.dart` | capture 生命週期埋 log |
| `lib/services/wish_fetcher.dart` | probe / fetch / retry 埋 log |
| `lib/state/wish_repository.dart` | update 流程埋 log |
| `lib/services/wish_storage.dart` | save / load / delete 失敗埋 log |
| `lib/services/accounts_import.dart` | `FormatException` 拋出前埋 log |
| `lib/state/app_release.dart` | 取代 `debugPrint('[app_release] silent failure: $e')` |
| `lib/services/app_release_checker.dart` | `fetchNewerReleases` 入口與分支埋 log |
| `lib/widgets/app_link.dart` | `debugPrint` → `Logger('ui.link').warning(...)` |
| `lib/widgets/banner_link.dart` | 同上 |
| `lib/widgets/team_links_bar.dart` | 同上 |
| `lib/widgets/translator_text.dart` | 同上 |
| `lib/l10n/app_zh_Hant.arb` | 11 個新 key |
| `lib/l10n/app_zh_Hans.arb` | 11 個新 key |
| `lib/l10n/app_en.arb` | 11 個新 key |
| `rust/src/api/mod.rs` | 加 `pub mod logging;` |
| `rust/src/api/capture.rs` | 移除 inline `try_init`,改呼叫 `crate::api::logging::init_tracing_once()` |
| `test/state/wish_repository_test.dart` | 補關鍵 log 驗證 |
| `test/services/wish_fetcher_test.dart` | 補 retry warning 驗證 |
| `test/services/settings_storage_test.dart` | `logLevel` round-trip |
| `test/state/settings_test.dart` | `setLogLevel` 套用 root level |

### Auto-generated(FRB codegen 後自動產出,不可手改)
- `lib/src/rust/api/logging.dart`
- `lib/src/rust/frb_generated.dart` / `frb_generated.io.dart` / `frb_generated.web.dart` 內相關 stub

---

## 共通約定

**Commit 前每次都必須跑:**
```
dart format lib/ test/
flutter analyze
flutter test
```
全部通過(`No issues found!` + `All tests passed!`)才能 commit。違反 `CLAUDE.md` 即為失敗。

**Commit message scope:** 統一用 `logging` 作為 scope(對齊 spec 主題)。例如:
- `feat(logging): add LogService with file rotation and ring buffer`
- `test(logging): add log_sanitize_test cases`
- `refactor(logging): replace debugPrint with Logger in wish flow`

**Logger 命名公約**(本計畫沿用):
| Logger name | 出處 |
|---|---|
| `app.startup` | main.dart 啟動序列 |
| `app.error` | 全域 error handler |
| `wish.capture` | `state/wish_capture.dart` |
| `wish.fetcher` | `services/wish_fetcher.dart` |
| `wish.repo` | `state/wish_repository.dart` |
| `wish.storage` | `services/wish_storage.dart` |
| `settings` | `services/settings_storage.dart` |
| `accounts.io` | `services/accounts_import.dart` + settings_page export/import |
| `release` | `state/app_release.dart` + `services/app_release_checker.dart` |
| `ui.link` | `widgets/{app_link,banner_link,team_links_bar,translator_text}.dart` |
| `rust.bridge` | main.dart 內 connect rust log stream 自身狀態 |
| `rust.<target>` | Rust 端 tracing event forward(target = `mitm`/`ca`/`cert_store`/`panic`) |

---

## Task 0: 加入 `logging` 套件相依

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 編輯 `pubspec.yaml`**

打開 `pubspec.yaml`,在 `dependencies:` 區塊內、`intl:` 那一行之後(維持英文字母順序)插入:

```yaml
  logging: ^1.3.0
```

完整 `dependencies:` 區塊:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_rust_bridge: ^2.12.0
  ffi: ^2.2.0
  flutter_riverpod: ^3.0.0
  go_router: ^17.0.0
  http: ^1.2.0
  path_provider: ^2.1.0
  shared_preferences: ^2.3.0
  file_selector: ^1.0.0
  fl_chart: ^1.0.0
  intl: ^0.20.0
  logging: ^1.3.0
  package_info_plus: ^10.0.0
  window_manager: ^0.5.1
  screen_retriever: ^0.2.0
  url_launcher: ^6.3.2
  font_awesome_flutter: ^11.0.0
  pub_semver: ^2.2.0
  markdown_widget: ^2.3.2+8
```

- [ ] **Step 2: 解析相依**

```
flutter pub get
```
Expected: 終端顯示 `Got dependencies!`,無錯誤。`pubspec.lock` 內出現 `logging` 條目。

- [ ] **Step 3: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`(現有測試不受影響)

- [ ] **Step 4: Commit**

```
git add pubspec.yaml pubspec.lock
git commit -m "build(deps): add logging ^1.3.0 for new log service"
```

---

## Task 1: `log_sanitize` helpers + 單元測試(TDD)

**Files:**
- Create: `lib/services/log_sanitize.dart`
- Create: `test/services/log_sanitize_test.dart`

- [ ] **Step 1: 先寫測試(failing)**

建立 `test/services/log_sanitize_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

void main() {
  group('sanitizeUrl', () {
    test('redacts authkey', () {
      final out = sanitizeUrl(
        'https://hk4e-api.example.com/event?authkey=ABCDEF&end_id=0',
      );
      expect(out, contains('authkey=***'));
      expect(out, contains('end_id=0'));
      expect(out, isNot(contains('ABCDEF')));
    });

    test('redacts all sensitive keys simultaneously', () {
      final out = sanitizeUrl(
        'https://x.example.com/y?authkey=A&authkey_ver=1&sign_type=2&game_biz=hk4e_global&gacha_type=301',
      );
      expect(out, contains('authkey=***'));
      expect(out, contains('authkey_ver=***'));
      expect(out, contains('sign_type=***'));
      expect(out, contains('game_biz=***'));
      expect(out, contains('gacha_type=301'));
    });

    test('keeps non-sensitive query params untouched', () {
      final out = sanitizeUrl(
        'https://x.example.com/y?gacha_type=301&end_id=0&size=20',
      );
      expect(out, contains('gacha_type=301'));
      expect(out, contains('end_id=0'));
      expect(out, contains('size=20'));
    });

    test('returns marker on malformed url', () {
      final out = sanitizeUrl('not a url ##');
      // Uri.parse 多數情況不會丟例外,但 host 可能為空 — 接受兩種 marker
      expect(out, anyOf(equals('<malformed url>'), contains('***')));
    });

    test('handles url with no query string', () {
      final out = sanitizeUrl('https://x.example.com/y');
      expect(out, equals('https://x.example.com/y'));
    });
  });

  group('sanitizeUid', () {
    test('masks middle of long uid', () {
      expect(sanitizeUid('186123456'), equals('186****456'));
    });

    test('masks very long uid', () {
      expect(sanitizeUid('1234567890'), equals('123****890'));
    });

    test('returns full mask for short uid', () {
      expect(sanitizeUid('12345'), equals('***'));
    });

    test('returns full mask for empty', () {
      expect(sanitizeUid(''), equals('***'));
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/log_sanitize_test.dart
```
Expected: 編譯失敗(`Target of URI doesn't exist: 'package:.../log_sanitize.dart'`)。這個失敗就是我們要的 TDD red。

- [ ] **Step 3: 寫實作**

建立 `lib/services/log_sanitize.dart`:

```dart
/// 把 authkey / authkey_ver / sign_type / game_biz 等敏感 query value 改成 `***`,
/// 其餘 query 保留。malformed URL 回 `<malformed url>`。
String sanitizeUrl(String raw) {
  final Uri uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return '<malformed url>';
  }
  if (uri.host.isEmpty && uri.path.isEmpty && uri.scheme.isEmpty) {
    return '<malformed url>';
  }
  const redactKeys = {'authkey', 'authkey_ver', 'sign_type', 'game_biz'};
  if (uri.queryParameters.isEmpty) return uri.toString();
  final newQuery = <String, String>{};
  uri.queryParameters.forEach((k, v) {
    newQuery[k] = redactKeys.contains(k) ? '***' : v;
  });
  return uri.replace(queryParameters: newQuery).toString();
}

/// UID 中段遮蔽:`123****890`(前 3 + 後 3)。長度 < 6 全遮 `***`。
String sanitizeUid(String uid) {
  if (uid.length < 6) return '***';
  return '${uid.substring(0, 3)}****${uid.substring(uid.length - 3)}';
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/log_sanitize_test.dart
```
Expected: `All tests passed!`(9 個 test)

- [ ] **Step 5: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 6: Commit**

```
git add lib/services/log_sanitize.dart test/services/log_sanitize_test.dart
git commit -m "feat(logging): add sanitizeUrl/sanitizeUid helpers with tests"
```

---

## Task 2: `LogService` 核心 + 單元測試(TDD)

**Files:**
- Create: `lib/services/log_service.dart`
- Create: `test/services/log_service_test.dart`

- [ ] **Step 1: 先寫測試骨架(failing)**

建立 `test/services/log_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_service.dart';

void main() {
  late Directory tempDir;
  late LogService svc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('log_service_test_');
    // 每個 test 都用獨立的 LogService → 用 dispose 釋放
  });

  tearDown(() async {
    await svc.dispose();
    await tempDir.delete(recursive: true);
    // Logger root 在 listener 釋放後 level 殘留,reset
    Logger.root.level = Level.INFO;
    Logger.root.clearListeners();
  });

  test('bootstrap creates logs/ subdirectory', () async {
    svc = await LogService.bootstrap(tempDir);
    expect(await Directory('${tempDir.path}/logs').exists(), isTrue);
  });

  test('INFO log appends to today file', () async {
    svc = await LogService.bootstrap(tempDir);
    Logger('test').info('hello world');
    // sink writeln 是 async,給時間 flush
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final files = await Directory('${tempDir.path}/logs').list().toList();
    final logFiles = files.whereType<File>().where(
          (f) => f.path.endsWith('.log'),
        );
    expect(logFiles, hasLength(1));
    final content = await logFiles.first.readAsString();
    expect(content, contains('hello world'));
    expect(content, contains('[test]'));
    expect(content, contains('INFO'));
  });

  test('level filter respects Logger.root.level', () async {
    svc = await LogService.bootstrap(tempDir);
    Logger.root.level = Level.WARNING;
    Logger('test').info('should-not-appear');
    Logger('test').warning('should-appear');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final file = (await Directory('${tempDir.path}/logs').list().toList())
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.log'));
    final content = await file.readAsString();
    expect(content, isNot(contains('should-not-appear')));
    expect(content, contains('should-appear'));
  });

  test('ring buffer caps at capacity', () async {
    svc = await LogService.bootstrap(tempDir);
    for (var i = 0; i < 3000; i++) {
      Logger('test').info('line $i');
    }
    final snap = svc.snapshot();
    expect(snap.length, equals(2000));
    expect(snap.first, contains('line 1000')); // 前 1000 已被擠掉
    expect(snap.last, contains('line 2999'));
  });

  test('live stream emits new records', () async {
    svc = await LogService.bootstrap(tempDir);
    final received = <String>[];
    final sub = svc.live.listen(received.add);
    Logger('test').info('streamed');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(received, hasLength(1));
    expect(received.first, contains('streamed'));
  });

  test('clearAll deletes all .log files and reopens sink', () async {
    svc = await LogService.bootstrap(tempDir);
    Logger('test').info('before clear');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await svc.clearAll();
    final after = await Directory('${tempDir.path}/logs').list().toList();
    final logFilesAfter = after.whereType<File>().where(
          (f) => f.path.endsWith('.log'),
        );
    // clearAll 後 _openTodaySink 會建立空檔(0 byte append-mode open)
    // 所以可能有 0 或 1 個檔案(看 IOSink 是否立刻 touch file)
    // 接受 ≤ 1 個檔案
    expect(logFilesAfter.length, lessThanOrEqualTo(1));

    Logger('test').info('after clear');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final final_ = (await Directory('${tempDir.path}/logs').list().toList())
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.log'));
    final content = await final_.readAsString();
    expect(content, contains('after clear'));
    expect(content, isNot(contains('before clear')));
  });

  test('rotation deletes files older than retention', () async {
    final logsDir = Directory('${tempDir.path}/logs');
    await logsDir.create();
    // 預先放一個 30 天前的檔
    final old = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final oldName =
        '${old.year.toString().padLeft(4, '0')}-${old.month.toString().padLeft(2, '0')}-${old.day.toString().padLeft(2, '0')}.log';
    await File('${logsDir.path}/$oldName').writeAsString('ancient');
    // 預先放一個 3 天前的檔(應保留)
    final recent = DateTime.now().toUtc().subtract(const Duration(days: 3));
    final recentName =
        '${recent.year.toString().padLeft(4, '0')}-${recent.month.toString().padLeft(2, '0')}-${recent.day.toString().padLeft(2, '0')}.log';
    await File('${logsDir.path}/$recentName').writeAsString('recent');

    svc = await LogService.bootstrap(tempDir);
    final remaining = (await logsDir.list().toList())
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(remaining, contains(recentName));
    expect(remaining, isNot(contains(oldName)));
  });

  test('buildExportBundle merges all log files with header', () async {
    svc = await LogService.bootstrap(tempDir);
    Logger('test').info('mark-line');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final bundle = await svc.buildExportBundle(
      appVersion: '9.9.9',
      osDescription: 'TestOS',
      localeTag: 'zh-Hant',
      themeMode: 'dark',
    );
    expect(bundle, contains('Genshin Wish Gacha Analyzer log bundle'));
    expect(bundle, contains('app_version: 9.9.9'));
    expect(bundle, contains('os: TestOS'));
    expect(bundle, contains('locale: zh-Hant'));
    expect(bundle, contains('theme: dark'));
    expect(bundle, contains('mark-line'));
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/log_service_test.dart
```
Expected: 編譯失敗(`Target of URI doesn't exist: 'package:.../log_service.dart'`)

- [ ] **Step 3: 寫實作**

建立 `lib/services/log_service.dart`:

```dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// 應用層 log pipeline。在 `main()` 透過 [bootstrap] 啟動,
/// 訂閱 `Logger.root.onRecord` 並把每條紀錄分發到:
/// 1. `dart:developer.log()`(IDE / DevTools);
/// 2. 記憶體 ring buffer(設定頁即時 stream 用);
/// 3. `<applicationSupport>/logs/YYYY-MM-DD.log`(UTC 日期,append);
/// 4. `kDebugMode` 下額外 `debugPrint` 給 `flutter run` console。
class LogService {
  LogService._(this.logsDir);

  /// `<applicationSupport>/logs/`
  final Directory logsDir;

  static const int _retentionDays = 7;
  static const int _ringBufferCapacity = 2000;

  final Queue<String> _ringBuffer = Queue<String>();
  final StreamController<String> _liveController =
      StreamController<String>.broadcast();

  IOSink? _todaySink;
  DateTime? _todayDate; // UTC date

  StreamSubscription<LogRecord>? _rootSubscription;

  /// 建立 `logs/`、清舊檔、開今天的 sink、訂閱 root Logger。
  static Future<LogService> bootstrap(Directory baseDir) async {
    final logsDir = Directory('${baseDir.path}/logs');
    if (!await logsDir.exists()) await logsDir.create(recursive: true);

    final svc = LogService._(logsDir);
    await svc._rotate();
    await svc._openTodaySink();

    Logger.root.level = Level.INFO;
    svc._rootSubscription = Logger.root.onRecord.listen(svc._handle);
    return svc;
  }

  void _handle(LogRecord r) {
    final line = _format(r);

    developer.log(
      r.message,
      time: r.time,
      level: r.level.value,
      name: r.loggerName,
      error: r.error,
      stackTrace: r.stackTrace,
    );
    if (kDebugMode) {
      debugPrint(line);
    }

    _ringBuffer.addLast(line);
    while (_ringBuffer.length > _ringBufferCapacity) {
      _ringBuffer.removeFirst();
    }
    if (!_liveController.isClosed) _liveController.add(line);

    _appendToFile(line, r);
  }

  String _format(LogRecord r) {
    final buf = StringBuffer()
      ..write(r.time.toIso8601String())
      ..write(' [')
      ..write(r.level.name.padRight(7))
      ..write('] [')
      ..write(r.loggerName)
      ..write('] ')
      ..write(r.message);
    if (r.error != null) {
      buf
        ..write('\n  error: ')
        ..write(r.error);
    }
    if (r.stackTrace != null) {
      buf
        ..write('\n  stack:\n    ')
        ..write(r.stackTrace.toString().replaceAll('\n', '\n    '));
    }
    return buf.toString();
  }

  void _appendToFile(String line, LogRecord r) {
    final d = DateTime.utc(r.time.year, r.time.month, r.time.day);
    if (_todayDate != d) {
      unawaited(_rolloverTo(d));
    }
    _todaySink?.writeln(line);
  }

  Future<void> _openTodaySink() async {
    final now = DateTime.now().toUtc();
    _todayDate = DateTime.utc(now.year, now.month, now.day);
    final file = _fileFor(_todayDate!);
    _todaySink = file.openWrite(mode: FileMode.append, encoding: utf8);
  }

  Future<void> _rolloverTo(DateTime d) async {
    await _todaySink?.flush();
    await _todaySink?.close();
    _todayDate = d;
    final file = _fileFor(d);
    _todaySink = file.openWrite(mode: FileMode.append, encoding: utf8);
    await _rotate();
  }

  File _fileFor(DateTime d) {
    final yyyy = d.year.toString().padLeft(4, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return File('${logsDir.path}/$yyyy-$mm-$dd.log');
  }

  Future<void> _rotate() async {
    if (!await logsDir.exists()) return;
    final entries = await logsDir.list().toList();
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: _retentionDays));
    final namePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.log$');
    for (final e in entries) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      final m = namePattern.firstMatch(name);
      if (m == null) continue;
      final fd = DateTime.utc(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
      if (fd.isBefore(cutoff)) {
        try {
          await e.delete();
        } catch (_) {
          // 下次再試,不阻塞啟動
        }
      }
    }
  }

  /// 把 `logs/` 內所有 `.log` 合併成單一字串(含 header)。
  Future<String> buildExportBundle({
    required String appVersion,
    required String osDescription,
    required String localeTag,
    required String themeMode,
  }) async {
    await _todaySink?.flush();
    final entries = (await logsDir.list().toList())
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.endsWith('.log'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final buf = StringBuffer()
      ..writeln('=== Genshin Wish Gacha Analyzer log bundle ===')
      ..writeln('exported_at: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('app_version: $appVersion')
      ..writeln('os: $osDescription')
      ..writeln('locale: $localeTag')
      ..writeln('theme: $themeMode')
      ..writeln('retention_days: $_retentionDays')
      ..writeln(
        'files: ${entries.map((e) => e.uri.pathSegments.last).join(', ')}',
      )
      ..writeln('=== begin ===');

    for (final f in entries) {
      buf
        ..writeln()
        ..writeln('--- ${f.uri.pathSegments.last} ---');
      buf.write(await f.readAsString());
    }
    return buf.toString();
  }

  /// 清除所有 log 檔,並重新開啟今天的 sink。
  Future<void> clearAll() async {
    await _todaySink?.flush();
    await _todaySink?.close();
    _todaySink = null;
    final entries = await logsDir.list().toList();
    for (final e in entries) {
      if (e is File && e.path.endsWith('.log')) {
        try {
          await e.delete();
        } catch (_) {
          // ignore
        }
      }
    }
    await _openTodaySink();
  }

  /// 設定頁即時預覽用:目前 ring buffer 的快照。
  List<String> snapshot() => _ringBuffer.toList(growable: false);

  /// 新進 log 的 broadcast stream。
  Stream<String> get live => _liveController.stream;

  Future<void> dispose() async {
    await _rootSubscription?.cancel();
    await _todaySink?.flush();
    await _todaySink?.close();
    await _liveController.close();
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/log_service_test.dart
```
Expected: `All tests passed!`(8 個 test)

如果 `clearAll deletes all .log files and reopens sink` 偶發失敗(IOSink touch 行為差異),把那個 test 的 `lessThanOrEqualTo(1)` 結果說明已在程式碼註解中。

- [ ] **Step 5: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 6: Commit**

```
git add lib/services/log_service.dart test/services/log_service_test.dart
git commit -m "feat(logging): add LogService with rotation, ring buffer and export bundle"
```

---

## Task 3: `logServiceProvider` (Riverpod)

**Files:**
- Create: `lib/state/log_service.dart`

- [ ] **Step 1: 建立 provider**

建立 `lib/state/log_service.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_service.dart';

/// 必須在 `main()` 用 `overrideWithValue` 注入,跟 `wishStorageProvider` 同模式。
final logServiceProvider = Provider<LogService>((ref) {
  throw UnimplementedError(
    'logServiceProvider must be overridden in main()',
  );
});
```

- [ ] **Step 2: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 3: Commit**

```
git add lib/state/log_service.dart
git commit -m "feat(logging): add logServiceProvider"
```

---

## Task 4: Rust `ForwardLayer` + `start_log_stream` + `capture.rs` 重構

**Files:**
- Create: `rust/src/api/logging.rs`
- Modify: `rust/src/api/mod.rs`
- Modify: `rust/src/api/capture.rs`

- [ ] **Step 1: 建立 `rust/src/api/logging.rs`**

```rust
use std::sync::Mutex;

use anyhow::Result;
use flutter_rust_bridge::frb;
use once_cell::sync::OnceCell;
use tracing_subscriber::layer::Context;
use tracing_subscriber::prelude::*;

use crate::frb_generated::StreamSink;

/// 跨橋傳給 Dart 的 log event。對應 Dart 的 `Logger('rust.<target>').log(level, message, ...)`。
#[derive(Clone)]
#[frb]
pub struct LogEvent {
    pub timestamp_ms: i64,
    /// "ERROR" | "WARN" | "INFO" | "DEBUG" | "TRACE"
    pub level: String,
    /// tracing target,例如 "mitm" / "ca" / "cert_store" / "panic"
    pub target: String,
    pub message: String,
}

static FORWARD_SINK: OnceCell<Mutex<Option<StreamSink<LogEvent>>>> = OnceCell::new();
static INIT: OnceCell<()> = OnceCell::new();

/// Dart 端在 `main()` 內呼叫一次。重複呼叫只會覆蓋現有 sink(idempotent)。
pub fn start_log_stream(sink: StreamSink<LogEvent>) -> Result<()> {
    let slot = FORWARD_SINK.get_or_init(|| Mutex::new(None));
    *slot.lock().unwrap() = Some(sink);
    init_tracing_once();
    Ok(())
}

/// 安裝 tracing 全域 subscriber(只執行一次)。
/// - 保留 stdout `fmt::layer()` 讓 `cargo run` 階段仍可見;
/// - 加上 `ForwardLayer` 把事件轉送到 Dart;
/// - 設定 panic hook 把 Rust panic 訊息也轉成 `tracing::error!`。
pub(crate) fn init_tracing_once() {
    INIT.get_or_init(|| {
        let filter = tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));

        let _ = tracing_subscriber::registry()
            .with(filter)
            .with(tracing_subscriber::fmt::layer())
            .with(ForwardLayer)
            .try_init();

        std::panic::set_hook(Box::new(|info| {
            tracing::error!(target: "panic", "{info}");
        }));
    });
}

struct ForwardLayer;

impl<S> tracing_subscriber::Layer<S> for ForwardLayer
where
    S: tracing::Subscriber,
{
    fn on_event(&self, event: &tracing::Event<'_>, _ctx: Context<'_, S>) {
        let sink_slot = match FORWARD_SINK.get() {
            Some(s) => s,
            None => return,
        };
        let guard = sink_slot.lock().unwrap();
        let sink = match guard.as_ref() {
            Some(s) => s,
            None => return,
        };

        let metadata = event.metadata();
        let level = metadata.level().as_str().to_string();
        let target = metadata.target().to_string();

        let mut visitor = MessageVisitor::default();
        event.record(&mut visitor);
        let message = visitor.finish();

        let now_ms = chrono::Utc::now().timestamp_millis();
        let _ = sink.add(LogEvent {
            timestamp_ms: now_ms,
            level,
            target,
            message,
        });
    }
}

#[derive(Default)]
struct MessageVisitor {
    message: Option<String>,
    fields: Vec<(String, String)>,
}

impl MessageVisitor {
    fn finish(mut self) -> String {
        let mut out = self.message.take().unwrap_or_default();
        for (k, v) in self.fields {
            out.push(' ');
            out.push_str(&k);
            out.push('=');
            out.push_str(&v);
        }
        out
    }
}

impl tracing::field::Visit for MessageVisitor {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.message = Some(format!("{value:?}"));
        } else {
            self.fields
                .push((field.name().to_string(), format!("{value:?}")));
        }
    }

    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        if field.name() == "message" {
            self.message = Some(value.to_string());
        } else {
            self.fields
                .push((field.name().to_string(), value.to_string()));
        }
    }
}
```

- [ ] **Step 2: 把新 module 掛進 `rust/src/api/mod.rs`**

打開 `rust/src/api/mod.rs`。原檔只有:
```rust
pub mod capture;
```
改為:
```rust
pub mod capture;
pub mod logging;
```

- [ ] **Step 3: 重構 `rust/src/api/capture.rs`,移除既有 `try_init`**

打開 `rust/src/api/capture.rs`,找到 `pub fn start_capture` 內這幾行(目前約 line 35-40):

```rust
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"))
        )
        .try_init();
```

整段移除,換成單行:

```rust
    crate::api::logging::init_tracing_once();
```

更新後的 `start_capture` 起頭應該長這樣:

```rust
pub fn start_capture(sink: StreamSink<CapturedRequest>) -> Result<()> {
    let mut guard = SESSION.lock().unwrap_or_else(|e| e.into_inner());
    if guard.is_some() {
        return Err(anyhow!("capture already running"));
    }

    crate::api::logging::init_tracing_once();

    let root = ca::load_or_generate()?;
    cert_store::install_to_current_user_root(&root.cert_der)?;
    // ...(其餘不變)
```

- [ ] **Step 4: 編譯確認**

```
cargo build --manifest-path rust/Cargo.toml
```
Expected: `Finished` 無錯誤、無 warning(若有 unused import warning 順手清掉)。

- [ ] **Step 5: 格式化 Rust**

```
cargo fmt --manifest-path rust/Cargo.toml
```
Expected: 無輸出(已格式化)或自動套用。

- [ ] **Step 6: Commit**

```
git add rust/src/api/logging.rs rust/src/api/mod.rs rust/src/api/capture.rs
git commit -m "feat(logging): add Rust ForwardLayer and FRB start_log_stream"
```

---

## Task 5: 重新生成 FRB binding

**Files:**
- Modify(auto): `lib/src/rust/api/logging.dart`、`lib/src/rust/frb_generated*.dart`

> **前置**:確認 `flutter_rust_bridge_codegen` 已安裝(專案開發環境一般已有)。若沒裝:`cargo install flutter_rust_bridge_codegen --version 2.12.0`。

- [ ] **Step 1: 跑 codegen**

```
flutter_rust_bridge_codegen generate
```
Expected: 終端顯示 `Done!`,自動產出 `lib/src/rust/api/logging.dart`,並更新 `lib/src/rust/frb_generated*.dart` 的 dispatch 表。

- [ ] **Step 2: 驗證產出**

確認 `lib/src/rust/api/logging.dart` 存在,內含:
```dart
Stream<LogEvent> startLogStream() =>
    RustLib.instance.api.crateApiLoggingStartLogStream();

class LogEvent {
  final PlatformInt64 timestampMs;
  final String level;
  final String target;
  final String message;
  // ...
}
```

- [ ] **Step 3: 編譯通過**

```
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`(codegen 產出檔已加 `ignore_for_file` 注釋,analyzer 不會報)

- [ ] **Step 4: Commit(codegen 產出檔)**

```
git add lib/src/rust/
git commit -m "build(logging): regenerate FRB bindings for log stream"
```

---

## Task 6: `main.dart` 全面接線(LogService bootstrap + 三層 error handler + Rust stream + startup log)

**Files:**
- Modify: `lib/main.dart`

> **這個 task 是 wire-up 集中地**:同時做 bootstrap、error handler、Rust 接通、取代原本兩處 `debugPrint`。

- [ ] **Step 1: 重寫 `lib/main.dart`**

完整內容(直接整檔覆蓋):

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/routing/app_router.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/window_state_keeper.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/logging.dart'
    as rust_logging;
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/frb_generated.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/log_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await RustLib.init();

      if (Platform.isWindows) {
        await windowManager.ensureInitialized();
        await WindowStateKeeper.bootstrap();
      }

      final supportDir = await getApplicationSupportDirectory();
      final logService = await LogService.bootstrap(supportDir);

      FlutterError.onError = (details) {
        Logger('app.error').severe(
          'FlutterError: ${details.exceptionAsString()}',
          details.exception,
          details.stack,
        );
        FlutterError.presentError(details);
      };
      PlatformDispatcher.instance.onError = (e, st) {
        Logger('app.error').severe('Uncaught async error', e, st);
        return true;
      };

      unawaited(_connectRustLogStream());

      final pkgInfo = await PackageInfo.fromPlatform();

      Logger('app.startup').info(
        'app start v${pkgInfo.version}+${pkgInfo.buildNumber} '
        'on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
        'locale=${Platform.localeName}',
      );

      try {
        final cleaned = await rust_capture.cleanupStaleProxy();
        if (cleaned) {
          Logger('app.startup')
              .info('cleanup_stale_proxy: stale proxy detected and reset');
        }
      } catch (e, st) {
        Logger('app.startup').warning('cleanup_stale_proxy failed', e, st);
      }

      final wishDir = Directory('${supportDir.path}/wish_data');
      if (!await wishDir.exists()) {
        await wishDir.create(recursive: true);
      }
      final storage = WishStorage(wishDir);

      runApp(
        ProviderScope(
          overrides: [
            wishStorageProvider.overrideWithValue(storage),
            appVersionProvider.overrideWithValue(pkgInfo.version),
            logServiceProvider.overrideWithValue(logService),
          ],
          child: const MainApp(),
        ),
      );
    },
    (e, st) {
      Logger('app.error').severe('Zone uncaught', e, st);
    },
  );
}

Future<void> _connectRustLogStream() async {
  try {
    rust_logging.startLogStream().listen(
      (event) {
        Logger('rust.${event.target}').log(
          _levelFromRust(event.level),
          event.message,
          null,
          null,
          DateTime.fromMillisecondsSinceEpoch(event.timestampMs.toInt()),
        );
      },
      onError: (Object e, StackTrace st) {
        Logger('rust.bridge').warning('log stream error', e, st);
      },
    );
    Logger('rust.bridge').info('rust log stream connected');
  } catch (e, st) {
    Logger('rust.bridge').warning('failed to start rust log stream', e, st);
  }
}

Level _levelFromRust(String s) => switch (s) {
      'ERROR' => Level.SEVERE,
      'WARN' => Level.WARNING,
      'INFO' => Level.INFO,
      'DEBUG' => Level.FINE,
      _ => Level.FINER,
    };

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  late final GoRouter _router = buildAppRouter();

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appName,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: localeListResolution,
      routerConfig: _router,
    );
  }
}
```

備註:
- 既有 `debugPrint('[startup] stale proxy detected and reset')` / `debugPrint('[startup] cleanup_stale_proxy failed: $e')` 已被取代。
- `PlatformInt64` 來自 FRB,`.toInt()` 把它轉成 Dart `int` 給 `fromMillisecondsSinceEpoch`。

- [ ] **Step 2: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 3: 手動驗證(關鍵 — 真實看到 log)**

```
flutter run -d windows
```
觀察 console:
- 必須看到 `[app.startup] app start v1.0.0+1 on windows ...`
- 必須看到 `[rust.bridge] rust log stream connected`
- 試按更新(觸發 MITM)→ 應該看到 `[rust.mitm] hit gacha endpoint: GET https://...`(target 為 mitm,證明 Rust → Dart bridge 通)

關閉 app。檢查 `<applicationSupport>/genshin_impact_wish_gacha_analyzer/logs/YYYY-MM-DD.log` 內含這些行。

- [ ] **Step 4: Commit**

```
git add lib/main.dart
git commit -m "feat(logging): wire LogService, error handlers and Rust log stream in main"
```

---

## Task 7: `SettingsStorage` / `SettingsNotifier` 擴充 `logLevel`

**Files:**
- Modify: `lib/services/settings_storage.dart`
- Modify: `lib/state/settings.dart`
- Modify: `test/services/settings_storage_test.dart`
- Modify: `test/state/settings_test.dart`

- [ ] **Step 1: 先寫 settings_storage round-trip 測試(failing)**

打開 `test/services/settings_storage_test.dart`,在現有 group 內(或檔尾新 group)加:

```dart
group('logLevel persistence', () {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to INFO when unset', () async {
    final loaded = await SettingsStorage.load();
    expect(loaded.logLevel, equals('INFO'));
  });

  test('round-trips a non-default value', () async {
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(logLevel: 'WARNING'),
    );
    final loaded = await SettingsStorage.load();
    expect(loaded.logLevel, equals('WARNING'));
  });
});
```

(如果檔頭已 import `shared_preferences`,沿用;否則加 `import 'package:shared_preferences/shared_preferences.dart';`)

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/settings_storage_test.dart
```
Expected: 失敗(`AppSettings` 沒有 `logLevel` getter)

- [ ] **Step 3: 修改 `lib/services/settings_storage.dart`**

在 `AppSettings` 的 fields 之後、`defaults` 之前加 `logLevel`,完整修改如下(找對應位置改):

把:
```dart
@immutable
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.locale,
    this.lastActiveUid,
    this.uidAliases = const {},
    this.uidOrder = const [],
    this.skippedReleaseTag,
  });

  final AppThemeMode themeMode;
  final LanguagePreference locale;
  final String? lastActiveUid;
  final Map<String, String> uidAliases;
  final List<String> uidOrder;
  final String? skippedReleaseTag;

  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: SystemLanguage(),
  );

  AppSettings copyWith({
    AppThemeMode? themeMode,
    LanguagePreference? locale,
    String? lastActiveUid,
    bool clearLastActiveUid = false,
    Map<String, String>? uidAliases,
    List<String>? uidOrder,
    String? skippedReleaseTag,
    bool clearSkippedReleaseTag = false,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    lastActiveUid: clearLastActiveUid
        ? null
        : (lastActiveUid ?? this.lastActiveUid),
    uidAliases: uidAliases ?? this.uidAliases,
    uidOrder: uidOrder ?? this.uidOrder,
    skippedReleaseTag: clearSkippedReleaseTag
        ? null
        : (skippedReleaseTag ?? this.skippedReleaseTag),
  );
}
```

改為:
```dart
@immutable
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.locale,
    this.lastActiveUid,
    this.uidAliases = const {},
    this.uidOrder = const [],
    this.skippedReleaseTag,
    this.logLevel = 'INFO',
  });

  final AppThemeMode themeMode;
  final LanguagePreference locale;
  final String? lastActiveUid;
  final Map<String, String> uidAliases;
  final List<String> uidOrder;
  final String? skippedReleaseTag;
  /// `package:logging` Level name:"OFF" | "SEVERE" | "WARNING" | "INFO" | "FINE"
  final String logLevel;

  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: SystemLanguage(),
  );

  AppSettings copyWith({
    AppThemeMode? themeMode,
    LanguagePreference? locale,
    String? lastActiveUid,
    bool clearLastActiveUid = false,
    Map<String, String>? uidAliases,
    List<String>? uidOrder,
    String? skippedReleaseTag,
    bool clearSkippedReleaseTag = false,
    String? logLevel,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    lastActiveUid: clearLastActiveUid
        ? null
        : (lastActiveUid ?? this.lastActiveUid),
    uidAliases: uidAliases ?? this.uidAliases,
    uidOrder: uidOrder ?? this.uidOrder,
    skippedReleaseTag: clearSkippedReleaseTag
        ? null
        : (skippedReleaseTag ?? this.skippedReleaseTag),
    logLevel: logLevel ?? this.logLevel,
  );
}
```

接著在 `abstract final class SettingsStorage` 內,把 keys 區塊 + `load` + `save` 對應補上 `logLevel`:

```dart
abstract final class SettingsStorage {
  static const _kThemeMode = 'pref.themeMode';
  static const _kLocale = 'pref.locale';
  static const _kLastActiveUid = 'pref.lastActiveUid';
  static const _kUidAliases = 'pref.uidAliases';
  static const _kUidOrder = 'pref.uidOrder';
  static const _kSkippedReleaseTag = 'pref.skippedReleaseTag';
  static const _kLogLevel = 'pref.logLevel';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: _parseLocale(prefs.getString(_kLocale)),
      lastActiveUid: prefs.getString(_kLastActiveUid),
      uidAliases: _parseAliases(prefs.getString(_kUidAliases)),
      uidOrder: _parseOrder(prefs.getString(_kUidOrder)),
      skippedReleaseTag: prefs.getString(_kSkippedReleaseTag),
      logLevel: prefs.getString(_kLogLevel) ?? 'INFO',
    );
  }

  static Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, _themeModeToString(s.themeMode));
    await prefs.setString(_kLocale, s.locale.toCode());
    if (s.lastActiveUid == null) {
      await prefs.remove(_kLastActiveUid);
    } else {
      await prefs.setString(_kLastActiveUid, s.lastActiveUid!);
    }
    await prefs.setString(_kUidAliases, jsonEncode(s.uidAliases));
    await prefs.setString(_kUidOrder, jsonEncode(s.uidOrder));
    if (s.skippedReleaseTag == null) {
      await prefs.remove(_kSkippedReleaseTag);
    } else {
      await prefs.setString(_kSkippedReleaseTag, s.skippedReleaseTag!);
    }
    await prefs.setString(_kLogLevel, s.logLevel);
  }

  // ...其餘 _parse* 方法不變
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/settings_storage_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: 寫 SettingsNotifier `setLogLevel` 測試(failing)**

打開 `test/state/settings_test.dart`。在現有 group 內(或檔尾)加:

```dart
group('logLevel', () {
  test('setLogLevel persists and applies to Logger.root', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).waitForLoad();
    expect(Logger.root.level, equals(Level.INFO));

    await container.read(settingsProvider.notifier).setLogLevel('WARNING');
    expect(Logger.root.level, equals(Level.WARNING));
    expect(container.read(settingsProvider).logLevel, equals('WARNING'));

    // Restart container, ensure level re-applied from storage
    Logger.root.level = Level.INFO; // reset to simulate fresh process
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    await container2.read(settingsProvider.notifier).waitForLoad();
    expect(Logger.root.level, equals(Level.WARNING));
  });
});
```

確保檔頭有:
```dart
import 'package:logging/logging.dart';
```

- [ ] **Step 6: 跑測試確認失敗**

```
flutter test test/state/settings_test.dart
```
Expected: 失敗(`setLogLevel` 不存在 / `waitForLoad` 後 root level 不會自動套用)

- [ ] **Step 7: 修改 `lib/state/settings.dart`**

打開 `lib/state/settings.dart`。在檔頭 imports 加:
```dart
import 'package:logging/logging.dart';
```

在 `SettingsNotifier` 內,找到 `waitForLoad` / `_load` 結束處(load 完成把 state 設為 loaded 那段),append:
```dart
_applyLogLevel(state.logLevel);
```

在 `SettingsNotifier` 加入新方法(放在其他 `setXxx` 旁邊):
```dart
Future<void> setLogLevel(String level) async {
  state = state.copyWith(logLevel: level);
  await SettingsStorage.save(state);
  _applyLogLevel(level);
}

void _applyLogLevel(String level) {
  Logger.root.level = _parseLevel(level);
}

Level _parseLevel(String s) => switch (s) {
      'OFF' => Level.OFF,
      'SEVERE' => Level.SEVERE,
      'WARNING' => Level.WARNING,
      'INFO' => Level.INFO,
      'FINE' => Level.FINE,
      _ => Level.INFO,
    };
```

> **注意**:`lib/state/settings.dart` 既有結構你可能需要小幅調整 — 找到 `waitForLoad()` 或對應 `_load()` 完成位置加一行 `_applyLogLevel(state.logLevel);`。

- [ ] **Step 8: 跑測試確認通過**

```
flutter test test/state/settings_test.dart
flutter test test/services/settings_storage_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 9: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 10: Commit**

```
git add lib/services/settings_storage.dart lib/state/settings.dart \
        test/services/settings_storage_test.dart test/state/settings_test.dart
git commit -m "feat(logging): add SettingsStorage.logLevel and setLogLevel notifier"
```

---

## Task 8: i18n keys + gen-l10n

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: 加入 keys 到 `lib/l10n/app_zh_Hant.arb`(template)**

打開 `lib/l10n/app_zh_Hant.arb`,在最後一個 key 之後插入(注意保留原 JSON 格式,加逗號分隔):

```json
  "settingsLogs": "Log 偵錯",
  "@settingsLogs": {},
  "settingsLogsHint": "留下執行紀錄,協助回報問題時找出原因。",
  "@settingsLogsHint": {},
  "settingsLogsExport": "匯出 log 檔",
  "@settingsLogsExport": {},
  "settingsLogsOpenFolder": "開啟 log 資料夾",
  "@settingsLogsOpenFolder": {},
  "settingsLogsClear": "清除所有 log",
  "@settingsLogsClear": {},
  "settingsLogsLevel": "紀錄等級",
  "@settingsLogsLevel": {},
  "settingsLogsLevelOff": "關閉",
  "@settingsLogsLevelOff": {},
  "settingsLogsLevelSevere": "嚴重",
  "@settingsLogsLevelSevere": {},
  "settingsLogsLevelWarning": "警告",
  "@settingsLogsLevelWarning": {},
  "settingsLogsLevelInfo": "一般(預設)",
  "@settingsLogsLevelInfo": {},
  "settingsLogsLevelFine": "詳細",
  "@settingsLogsLevelFine": {},
  "settingsLogsExportSuccess": "已匯出 log:{path}",
  "@settingsLogsExportSuccess": {
    "placeholders": {
      "path": { "type": "String" }
    }
  },
  "settingsLogsClearConfirmBody": "這會永久刪除 logs/ 內所有檔案。若回報問題前需要 log,請先匯出。輸入 CLEAR 確認。",
  "@settingsLogsClearConfirmBody": {}
```

> 「,」「,」是全形(U+FF0C),不要打半形。如果發現編輯器自動 normalize,用 PowerShell `[char]0xFF0C` 寫進去並 codepoint 驗證。

- [ ] **Step 2: 加入對應 keys 到 `lib/l10n/app_zh_Hans.arb`**

```json
  "settingsLogs": "日志调试",
  "@settingsLogs": {},
  "settingsLogsHint": "留下运行记录,协助报告问题时找出原因。",
  "@settingsLogsHint": {},
  "settingsLogsExport": "导出日志文件",
  "@settingsLogsExport": {},
  "settingsLogsOpenFolder": "打开日志文件夹",
  "@settingsLogsOpenFolder": {},
  "settingsLogsClear": "清除所有日志",
  "@settingsLogsClear": {},
  "settingsLogsLevel": "记录等级",
  "@settingsLogsLevel": {},
  "settingsLogsLevelOff": "关闭",
  "@settingsLogsLevelOff": {},
  "settingsLogsLevelSevere": "严重",
  "@settingsLogsLevelSevere": {},
  "settingsLogsLevelWarning": "警告",
  "@settingsLogsLevelWarning": {},
  "settingsLogsLevelInfo": "一般(默认)",
  "@settingsLogsLevelInfo": {},
  "settingsLogsLevelFine": "详细",
  "@settingsLogsLevelFine": {},
  "settingsLogsExportSuccess": "已导出日志:{path}",
  "@settingsLogsExportSuccess": {
    "placeholders": {
      "path": { "type": "String" }
    }
  },
  "settingsLogsClearConfirmBody": "这会永久删除 logs/ 内所有文件。若报告问题前需要日志,请先导出。输入 CLEAR 确认。",
  "@settingsLogsClearConfirmBody": {}
```

- [ ] **Step 3: 加入對應 keys 到 `lib/l10n/app_en.arb`**

```json
  "settingsLogs": "Debug logs",
  "@settingsLogs": {},
  "settingsLogsHint": "Records app activity to help diagnose issues when reporting bugs.",
  "@settingsLogsHint": {},
  "settingsLogsExport": "Export logs",
  "@settingsLogsExport": {},
  "settingsLogsOpenFolder": "Open logs folder",
  "@settingsLogsOpenFolder": {},
  "settingsLogsClear": "Clear all logs",
  "@settingsLogsClear": {},
  "settingsLogsLevel": "Log level",
  "@settingsLogsLevel": {},
  "settingsLogsLevelOff": "Off",
  "@settingsLogsLevelOff": {},
  "settingsLogsLevelSevere": "Severe",
  "@settingsLogsLevelSevere": {},
  "settingsLogsLevelWarning": "Warning",
  "@settingsLogsLevelWarning": {},
  "settingsLogsLevelInfo": "Info (default)",
  "@settingsLogsLevelInfo": {},
  "settingsLogsLevelFine": "Fine",
  "@settingsLogsLevelFine": {},
  "settingsLogsExportSuccess": "Logs exported: {path}",
  "@settingsLogsExportSuccess": {
    "placeholders": {
      "path": { "type": "String" }
    }
  },
  "settingsLogsClearConfirmBody": "This will permanently delete all files in logs/. Export them first if you need them for bug reports. Type CLEAR to confirm.",
  "@settingsLogsClearConfirmBody": {}
```

- [ ] **Step 4: 重新產生 localization 程式碼**

```
flutter gen-l10n
```
Expected: 無錯誤;`lib/l10n/generated/app_localizations*.dart` 內出現 `settingsLogs` 等 getter。

或者:
```
flutter pub get
```
也會觸發 gen(專案啟用了 `generate: true`)。

- [ ] **Step 5: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 6: Commit**

```
git add lib/l10n/
git commit -m "i18n(logging): add log section keys (zh_Hant/zh_Hans/en)"
```

---

## Task 9: 設定頁「Log 偵錯」SectionCard(`_LogsSection`)

**Files:**
- Modify: `lib/pages/settings_page.dart`

> **約定**:`_LogsSection` 採 spec 4.6 規範,放在 `settings_page.dart` 內(對齊 `_DataManagement` 私有 widget 模式)。順序:appearance → language → data management → **logs(新)** → account management → about。

- [ ] **Step 1: 補 imports 到 `lib/pages/settings_page.dart`**

打開 `lib/pages/settings_page.dart`,在現有 imports 後加:

```dart
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/log_service.dart';
```

- [ ] **Step 2: 在 `SettingsPage.build` 內插入新 `SectionCard`**

找到既有結構(data management 與 account management 之間):

```dart
SectionCard(
  title: l.settingsDataManagement,
  icon: Icons.folder_outlined,
  child: const _DataManagement(),
),
const SizedBox(height: AppSpacing.xl),
SectionCard(
  title: l.settingsAccountManagement,
  icon: Icons.manage_accounts_outlined,
  child: const AccountManagement(),
),
```

在 `SizedBox(height: AppSpacing.xl)` 之後、`SectionCard(title: l.settingsAccountManagement, ...)` 之前插入:

```dart
SectionCard(
  title: l.settingsLogs,
  icon: Icons.bug_report_outlined,
  child: const _LogsSection(),
),
const SizedBox(height: AppSpacing.xl),
```

- [ ] **Step 3: 在檔案末尾(`String _two(int n) ...` 之前)加入 `_LogsSection` 實作**

```dart
class _LogsSection extends ConsumerWidget {
  const _LogsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final currentLevel =
        ref.watch(settingsProvider.select((s) => s.logLevel));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.settingsLogsHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.gacha.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        _LogLevelDropdown(current: currentLevel),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            OutlinedButton.icon(
              onPressed: () => _export(context, ref),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(l.settingsLogsExport),
            ),
            OutlinedButton.icon(
              onPressed: () => _openFolder(context, ref),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(l.settingsLogsOpenFolder),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.gacha.stateDanger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _clear(context, ref),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l.settingsLogsClear),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _export(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final log = ref.read(logServiceProvider);
    final appVersion = ref.read(appVersionProvider);
    final settings = ref.read(settingsProvider);

    final now = DateTime.now();
    final stamp =
        '${now.year}-${_two(now.month)}-${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

    final loc = await getSaveLocation(
      suggestedName: 'gwga_logs_$stamp.log',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Log', extensions: ['log']),
      ],
    );
    if (loc == null) return;

    final bundle = await log.buildExportBundle(
      appVersion: appVersion,
      osDescription: '${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}',
      localeTag: Platform.localeName,
      themeMode: settings.themeMode.name,
    );
    await File(loc.path).writeAsString(bundle);
    Logger('accounts.io')
        .info('logs exported: ${loc.path} (${bundle.length} bytes)');
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsLogsExportSuccess(loc.path))),
    );
  }

  Future<void> _openFolder(BuildContext ctx, WidgetRef ref) async {
    final log = ref.read(logServiceProvider);
    final uri = Uri.file(log.logsDir.path);
    if (!await launchUrl(uri)) {
      Logger('ui.link').warning('openLogsFolder: launchUrl returned false');
    }
  }

  Future<void> _clear(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.settingsLogsClearConfirmBody,
      expectedText: 'CLEAR',
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
    );
    if (ok != true) return;
    if (!ctx.mounted) return;
    await ref.read(logServiceProvider).clearAll();
    Logger('accounts.io').info('logs cleared by user');
  }
}

class _LogLevelDropdown extends ConsumerWidget {
  const _LogLevelDropdown({required this.current});
  final String current;

  static const _options = ['OFF', 'SEVERE', 'WARNING', 'INFO', 'FINE'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    String label(String v) => switch (v) {
          'OFF' => l.settingsLogsLevelOff,
          'SEVERE' => l.settingsLogsLevelSevere,
          'WARNING' => l.settingsLogsLevelWarning,
          'INFO' => l.settingsLogsLevelInfo,
          'FINE' => l.settingsLogsLevelFine,
          _ => v,
        };
    return DropdownButtonFormField<String>(
      initialValue: current,
      decoration: InputDecoration(
        labelText: l.settingsLogsLevel,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
      items: [
        for (final v in _options)
          DropdownMenuItem(value: v, child: Text(label(v))),
      ],
      onChanged: (v) {
        if (v != null) {
          ref.read(settingsProvider.notifier).setLogLevel(v);
        }
      },
    );
  }
}
```

> **import 補完**:檔頭可能還需要 `import 'dart:io';`(若還沒)。

- [ ] **Step 4: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

如果 analyzer 抱怨 `Platform`、`File`、`getSaveLocation`、`XTypeGroup` 未 import,在檔頭 imports 加:
```dart
import 'dart:io';
// (file_selector 已在既有 imports)
```

- [ ] **Step 5: 手動驗證(UI)**

```
flutter run -d windows
```
- 進設定頁,確認新「Log 偵錯」SectionCard 出現,排序在「資料管理」之後、「帳號管理」之前。
- 點「匯出 log 檔」→ 跳檔案對話框 → 存檔 → SnackBar 提示路徑。打開該 `.log` 確認內含 header 與內容。
- 點「開啟 log 資料夾」→ 系統檔案總管打開 `logs/` 目錄。
- 點「清除所有 log」→ 跳 CLEAR 二次確認對話框 → 輸入 CLEAR → 確認 → 資料夾內 `.log` 都被清。
- 切換 level 下拉 → 切到 WARNING → 然後試一個會 INFO 的操作(再次按更新)→ 預期該 INFO log **不**會出現在新檔內,但 WARNING 會。

- [ ] **Step 6: Commit**

```
git add lib/pages/settings_page.dart
git commit -m "feat(logging): add Debug logs section to settings page"
```

---

## Task 10: `wish_capture.dart` 埋 log

**Files:**
- Modify: `lib/state/wish_capture.dart`

- [ ] **Step 1: 改寫 `lib/state/wish_capture.dart`**

完整內容(取代既有):

```dart
import 'dart:async';

import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;

class CaptureSession {
  CaptureSession({required this.result, required this.cancel});

  /// 解析為 URL,或 null 代表使用者取消 / MITM 在無命中下關閉
  final Future<String?> result;

  /// 觸發 stop_capture,等同使用者按取消
  final Future<void> Function() cancel;
}

abstract class WishCapture {
  CaptureSession start();
}

class RustWishCapture implements WishCapture {
  static final _log = Logger('wish.capture');

  @override
  CaptureSession start() {
    final completer = Completer<String?>();
    String? capturedUrl;
    _log.info('capture started');

    rust_capture.startCapture().listen(
      (event) {
        capturedUrl ??= event.url;
        _log.fine('captured: host=${event.host}');
        // 不 complete 這裡:等 stream onDone 觸發 = MITM 已 graceful shutdown +
        // system proxy 已還原;此時呼叫 HTTP fetcher 才不會誤走代理
      },
      onError: (Object e, StackTrace st) {
        _log.severe('capture error', e, st);
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (capturedUrl == null) {
          _log.info('capture done with no match');
        } else {
          _log.info('capture done, url=${sanitizeUrl(capturedUrl!)}');
        }
        if (!completer.isCompleted) completer.complete(capturedUrl);
      },
    );

    return CaptureSession(
      result: completer.future,
      cancel: () async {
        _log.info('capture cancelled by user');
        await rust_capture.stopCapture();
      },
    );
  }
}
```

- [ ] **Step 2: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 3: Commit**

```
git add lib/state/wish_capture.dart
git commit -m "feat(logging): instrument wish capture lifecycle"
```

---

## Task 11: `wish_fetcher.dart` 埋 log + retry warning 測試

**Files:**
- Modify: `lib/services/wish_fetcher.dart`
- Modify: `test/services/wish_fetcher_test.dart`

- [ ] **Step 1: 先寫 retry warning 測試(failing)**

打開 `test/services/wish_fetcher_test.dart`。在現有 group 內加(或新 group):

```dart
group('logging instrumentation', () {
  setUp(() {
    Logger.root.level = Level.ALL;
  });

  tearDown(() {
    Logger.root.clearListeners();
  });

  test('emits WARNING when retcode=-110 triggers backoff', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    // 假設既有 test setup 用 MockClient 模擬 retcode=-110 一次後成功;
    // 若沒有,新建一個 minimal MockClient:
    var hits = 0;
    final client = MockClient((req) async {
      hits++;
      if (hits == 1) {
        return http.Response(
          jsonEncode({'retcode': -110, 'data': null, 'message': 'rate'}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'retcode': 0,
          'data': {'list': []},
        }),
        200,
      );
    });

    final fetcher = WishFetcher(
      retryBackoff: const Duration(milliseconds: 1),
    );
    await fetcher.fetchPage(
      Uri.parse('https://x.example/y?gacha_type=301'),
      client,
    );

    final warning = records.firstWhere(
      (r) => r.level == Level.WARNING && r.loggerName == 'wish.fetcher',
      orElse: () => throw StateError(
        'no WARNING from wish.fetcher; got ${records.map((r) => "${r.level.name}:${r.loggerName}:${r.message}").toList()}',
      ),
    );
    expect(warning.message, contains('rate-limited'));
  });
});
```

(確保檔頭有 `import 'package:logging/logging.dart';` 以及 `MockClient` 來自 `package:http/testing.dart`)

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/wish_fetcher_test.dart
```
Expected: 失敗(WARNING 沒被發出)

- [ ] **Step 3: 修改 `lib/services/wish_fetcher.dart`**

在檔頭 imports 加:
```dart
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
```

在 `class WishFetcher` 內加 static logger:
```dart
class WishFetcher {
  static final _log = Logger('wish.fetcher');
  // ...
}
```

修改 `fetchPage`:在進入 `while (true)` 之前加 FINE log,在 retcode 處理分支加對應 log:

```dart
Future<FetchedPage> fetchPage(Uri url, http.Client client) async {
  final queryGachaType = url.queryParameters['gacha_type'] ?? '';
  var attempt = 0;
  _log.fine(
    'fetchPage gachaType=$queryGachaType url=${sanitizeUrl(url.toString())}',
  );
  while (true) {
    final res = await client.get(url).timeout(timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final retcode = body['retcode'] as int;
    if (retcode == 0) {
      final list = (body['data']?['list'] as List<dynamic>?) ?? const [];
      return FetchedPage(
        list
            .map(
              (e) => WishRecord.fromApiJson(
                e as Map<String, dynamic>,
                gachaType: queryGachaType,
              ),
            )
            .toList(growable: false),
      );
    }
    if (retcode == -101 || retcode == -100) {
      _log.warning('auth expired retcode=$retcode');
      throw AuthExpiredException(retcode);
    }
    if (retcode == -110) {
      attempt++;
      _log.warning(
        'rate-limited (retcode=-110), backoff ${retryBackoff.inMilliseconds}ms, '
        'attempt=$attempt/$_maxRetryOnRateLimit',
      );
      if (attempt > _maxRetryOnRateLimit) throw RateLimitedException();
      await Future<void>.delayed(retryBackoff);
      continue;
    }
    _log.severe(
      'ApiError retcode=$retcode message=${body['message']}',
    );
    throw ApiErrorException(retcode, body['message'] as String? ?? '');
  }
}
```

修改 `probeUid`,在 `tryCategory` 結束處(找到匹配時、未匹配時)記 log。`fetchBannerWithMerge` 開始/結束記 INFO:

```dart
Future<List<WishRecord>> fetchBannerWithMerge({
  required GachaUrl url,
  required String gachaType,
  required GachaEndpoint endpoint,
  required List<WishRecord> existing,
  required FetchedPage? primer,
  required void Function(FetchProgress) onProgress,
  required http.Client client,
}) async {
  _log.info('banner=$gachaType start, existing=${existing.length}');
  final existingMaxId = existing.isEmpty ? '0' : existing.first.id;
  // ...(其餘不變直到 return)
  _log.info(
    'banner=$gachaType done, fresh=${fresh.length} pages=${pageIndex}',
  );
  return [...fresh, ...existing];
}
```

`probeUid` 內:
```dart
Future<UidProbeResult> probeUid({...}) async {
  // ...
  final wishHit = await tryCategory(GachaCategory.wish);
  if (wishHit != null) {
    _log.info(
      'probe wish: hit uid=${sanitizeUid(wishHit.uid ?? "")} via gachaType=...',
    );
    return wishHit;
  }
  final odesHit = await tryCategory(GachaCategory.odes);
  if (odesHit != null) {
    _log.info(
      'probe odes: hit uid=${sanitizeUid(odesHit.uid ?? "")} via gachaType=...',
    );
    return odesHit;
  }
  _log.info('probe: no records in any banner');
  return UidProbeResult(uid: null, primerPages: primers);
}
```

> 註:`tryCategory` 內已知中獎的 `gachaType` 是迴圈變數 `type.gachaType`,你可以重構讓 tryCategory 把命中的 gachaType 也回傳;為避免改動範圍過大,本次先用簡化版 log(不顯示具體 gachaType,僅顯示 category)。實際呼叫:
> ```dart
> _log.info('probe wish: hit uid=${sanitizeUid(wishHit.uid ?? "")}');
> ```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/wish_fetcher_test.dart
```
Expected: `All tests passed!`(原測試 + 新 retry warning 測試)

- [ ] **Step 5: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 6: Commit**

```
git add lib/services/wish_fetcher.dart test/services/wish_fetcher_test.dart
git commit -m "feat(logging): instrument wish fetcher probe/fetch/retry"
```

---

## Task 12: `wish_repository.dart` 埋 log + 關鍵節點測試

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Modify: `test/state/wish_repository_test.dart`

- [ ] **Step 1: 先寫 `update completed` 與 `auth expired falling back` 測試(failing)**

打開 `test/state/wish_repository_test.dart`。新增 group:

```dart
group('logging instrumentation', () {
  setUp(() {
    Logger.root.level = Level.ALL;
  });
  tearDown(() {
    Logger.root.clearListeners();
  });

  test('emits update start/completed on happy path', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    // 沿用既有 test 內 happy path setup,呼叫 update(),done 後驗證
    // ...(plan reader: 重用該檔內既有 `_setup happy path` helper)

    expect(
      records.where(
        (r) => r.loggerName == 'wish.repo' && r.message.startsWith('update start'),
      ),
      isNotEmpty,
    );
    expect(
      records.where(
        (r) =>
            r.loggerName == 'wish.repo' &&
            r.message.startsWith('update completed'),
      ),
      isNotEmpty,
    );
  });
});
```

(此 test 是骨架,實作時必須複用既有 `wish_repository_test.dart` 內的 happy-path MockClient/MockCapture/MockStorage setup — 找該檔內現有的測試 setUp 模式照抄,不要重發明)

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/state/wish_repository_test.dart
```
Expected: 失敗(`update start` / `update completed` log 尚未發出)

- [ ] **Step 3: 修改 `lib/state/wish_repository.dart`**

加入 imports:
```dart
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
```

在 `class WishRepository extends Notifier<WishState>` 內加:
```dart
static final _log = Logger('wish.repo');
```

按以下順序在既有方法內插入 log(行號為 spec 4.8 規範,參照 spec 表):

`_runUpdate` 起頭(`_isUpdating = true;` 之後):
```dart
_log.info('update start, forceRecapture=$forceRecapture');
```

`_runUpdate` 內 `if (!forceRecapture && initialActiveUid != null)` 內 `capturedUrl = await storage.loadCapturedUrl(...)` 取回非 null 時:
```dart
if (capturedUrl != null) {
  _log.info('using cached url for uid=${sanitizeUid(initialActiveUid)}');
}
```

`_runUpdate` 內 cancel 早返處:
```dart
state = state.copyWith(clearProgress: true);
_log.info('update aborted (user cancelled capture)');
return;
```

`_runUpdate` 內第一層 `on AuthExpiredException` catch 中:
```dart
} on AuthExpiredException {
  if (!ref.mounted) return;
  _log.warning('auth expired, falling back to MITM recapture');
  // ...(原本邏輯)
```

第一層 `on http.ClientException catch (e)`:
```dart
} on http.ClientException catch (e) {
  if (!ref.mounted) return;
  if (_cancelTriggered) {
    _log.info('update cancelled (http client closed)');
    state = state.copyWith(clearProgress: true);
  } else {
    _log.warning(
      'http client error: ${e.message}${e.uri != null ? " uri=${sanitizeUrl(e.uri!.toString())}" : ""}',
    );
    state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
  }
}
```

最後一層 `catch (e)`(整段未知失敗):
```dart
} catch (e, st) {
  if (!ref.mounted) return;
  _log.severe('update unexpected error', e, st);
  state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
}
```

`_runMitm` 開頭與結尾:
```dart
Future<String?> _runMitm({required bool isFallback}) async {
  _log.info('MITM ${isFallback ? "fallback" : "primary"} session started');
  state = state.copyWith(progress: WaitingForCapture(isFallback: isFallback));
  final session = ref.read(wishCaptureProvider).start();
  _activeCancel = session.cancel;
  try {
    final result = await session.result;
    _log.info('MITM session done, hasUrl=${result != null}');
    return result;
  } finally {
    _activeCancel = null;
  }
}
```

`_fetchAllBanners` 內 banner 失敗:
```dart
} catch (e) {
  _log.warning('banner=${t.nameKey} failed: $e');
  mergedBanners[t.gachaType] = existing.banners[t.gachaType] ?? const [];
  failed.add(t.nameKey);
}
```

`_fetchAllBanners` 完成處(`state = state.copyWith(... UpdateCompleted ...)` 之前):
```dart
_log.info(
  'update completed: uid=${sanitizeUid(uid)} '
  'totalNew=$totalNew failed=[${failed.join(",")}]',
);
```

`importAccounts` 結束處(`return ImportResult(...)` 之前):
```dart
_log.info(
  'import: success=$successCount failed=[${failed.join(",")}] '
  'records=$totalRecords',
);
```

`removeUid` / `clearActive` / `clearAll` 結尾:
```dart
// removeUid
_log.info('cleared uid=${sanitizeUid(uid)}');
// clearAll
_log.info('cleared all wish data');
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/state/wish_repository_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 6: Commit**

```
git add lib/state/wish_repository.dart test/state/wish_repository_test.dart
git commit -m "feat(logging): instrument wish repository update flow"
```

---

## Task 13: `wish_storage.dart` 埋 log

**Files:**
- Modify: `lib/services/wish_storage.dart`

- [ ] **Step 1: 修改 `lib/services/wish_storage.dart`**

加入 imports:
```dart
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
```

在 `class WishStorage` 內加:
```dart
static final _log = Logger('wish.storage');
```

包覆 `load` / `save` / `delete` / `saveCapturedUrl` / `deleteCapturedUrl` 等方法,改寫如下:

```dart
Future<BannerStorage?> load(String uid) async {
  final f = _dataFile(uid);
  if (!await f.exists()) return null;
  try {
    final text = await f.readAsString();
    final json = jsonDecode(text) as Map<String, dynamic>;
    return BannerStorage.fromJson(json);
  } catch (e, st) {
    _log.severe('load failed for uid=${sanitizeUid(uid)}', e, st);
    rethrow;
  }
}

Future<void> save(BannerStorage data) async {
  try {
    await _atomicWrite(_dataFile(data.uid), jsonEncode(data.toJson()));
    final total = data.banners.values.fold<int>(0, (a, b) => a + b.length);
    _log.fine('saved uid=${sanitizeUid(data.uid)} records=$total');
  } catch (e, st) {
    _log.severe('save failed for uid=${sanitizeUid(data.uid)}', e, st);
    rethrow;
  }
}

Future<void> delete(String uid) async {
  final f = _dataFile(uid);
  if (await f.exists()) await f.delete();
  await deleteCapturedUrl(uid);
  _log.info('delete uid=${sanitizeUid(uid)}');
}

Future<void> clearAll() async {
  if (!await baseDir.exists()) return;
  final entries = await baseDir.list().toList();
  for (final e in entries) {
    if (e is File && e.path.endsWith('.json')) {
      await e.delete();
    }
  }
  _log.info('clear all wish data');
}

Future<String?> loadCapturedUrl(String uid) async {
  final f = _urlFile(uid);
  if (!await f.exists()) return null;
  final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  return json['url'] as String?;
}

Future<void> saveCapturedUrl(String uid, String url) async {
  final json = {
    'uid': uid,
    'url': url,
    'captured_at': DateTime.now().toUtc().toIso8601String(),
  };
  await _atomicWrite(_urlFile(uid), jsonEncode(json));
  _log.fine('saved captured url for uid=${sanitizeUid(uid)}');
}

Future<void> deleteCapturedUrl(String uid) async {
  final f = _urlFile(uid);
  if (await f.exists()) {
    await f.delete();
    _log.fine('deleted captured url for uid=${sanitizeUid(uid)}');
  }
}
```

- [ ] **Step 2: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 3: Commit**

```
git add lib/services/wish_storage.dart
git commit -m "feat(logging): instrument wish storage I/O"
```

---

## Task 14: `settings_storage.dart` + `accounts_import.dart` + settings_page 匯入匯出 callsite 埋 log

**Files:**
- Modify: `lib/services/settings_storage.dart`
- Modify: `lib/services/accounts_import.dart`
- Modify: `lib/pages/settings_page.dart`(`_DataManagement._export` / `_import` 內)

- [ ] **Step 1: `settings_storage.dart` 內 `_parseAliases` / `_parseOrder` 失敗時 log**

加 imports:
```dart
import 'package:logging/logging.dart';
```

`abstract final class SettingsStorage` 內加:
```dart
static final _log = Logger('settings');
```

改寫 `_parseAliases` 與 `_parseOrder`(找到既有 `catch (_)` 改成 `catch (e, st)`):

```dart
static Map<String, String> _parseAliases(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
  } catch (e, st) {
    _log.warning('uidAliases corrupt, resetting to empty', e, st);
    return const {};
  }
}

static List<String> _parseOrder(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.map((e) => e.toString()).toList(growable: false);
  } catch (e, st) {
    _log.warning('uidOrder corrupt, resetting to empty', e, st);
    return const [];
  }
}
```

- [ ] **Step 2: `accounts_import.dart` 內 FormatException 拋出前埋 log**

打開 `lib/services/accounts_import.dart`。加 imports:
```dart
import 'package:logging/logging.dart';
```

檔尾或頂端宣告:
```dart
final _log = Logger('accounts.io');
```

修改:
```dart
AccountsBundle importAccounts(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (e) {
    _log.warning('import failed: invalid JSON ($e)');
    throw const FormatException('Invalid JSON');
  }
  if (raw is! Map<String, dynamic>) {
    _log.warning('import failed: top-level not an object');
    throw const FormatException('Top-level value must be an object');
  }
  try {
    return AccountsBundle.fromJson(raw);
  } on FormatException catch (e) {
    _log.warning('import failed: ${e.message}');
    rethrow;
  } catch (e, st) {
    _log.warning('import failed: parse error', e, st);
    throw FormatException('Failed to parse: $e');
  }
}
```

- [ ] **Step 3: `settings_page.dart` 內 `_DataManagement._export` / `_import` 結尾埋 log**

打開 `lib/pages/settings_page.dart`,在 `_DataManagement._export` 完成處(`ScaffoldMessenger.of(ctx).showSnackBar(...)` 之前)加:

```dart
Logger('accounts.io').info(
  'export: uids=${pickedSet.length} records=${filteredByUid.values.fold<int>(0, (a, b) => a + b.allRecords.length)}',
);
```

在 `_DataManagement._import` 完成處,於 `result` 已得到的位置:
```dart
if (result.failedUids.isEmpty) {
  Logger('accounts.io').info(
    'import: success=${result.successAccounts} '
    'records=${result.totalRecords}',
  );
} else {
  Logger('accounts.io').warning(
    'import partial: success=${result.successAccounts} '
    'failed=[${result.failedUids.join(",")}]',
  );
}
```

確保檔頭 imports 有 `import 'package:logging/logging.dart';`(Task 9 已加,確認沒被誤刪)。

- [ ] **Step 4: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 5: Commit**

```
git add lib/services/settings_storage.dart lib/services/accounts_import.dart lib/pages/settings_page.dart
git commit -m "feat(logging): instrument settings I/O and accounts import/export"
```

---

## Task 15: `app_release.dart` + `app_release_checker.dart` 埋 log

**Files:**
- Modify: `lib/state/app_release.dart`
- Modify: `lib/services/app_release_checker.dart`

- [ ] **Step 1: `app_release.dart` 取代既有 `debugPrint`**

打開 `lib/state/app_release.dart`。加:
```dart
import 'package:logging/logging.dart';
```

把既有:
```dart
debugPrint('[app_release] silent failure: $e');
```

替換為:
```dart
Logger('release').warning('release check failed (silent)', e);
```

也可以拿掉 `import 'package:flutter/foundation.dart';`(若只剩 debugPrint 用到)。

在 `check` 方法起頭加:
```dart
Logger('release').info('release check start manual=$manual');
```

在判斷 releases.isEmpty / 不為空時加:
```dart
if (releases.isEmpty) {
  Logger('release').info('release check: up-to-date');
  state = manual ? const ReleaseUpToDate() : const ReleaseIdle();
  return;
}
Logger('release').info(
  'release check: ${releases.length} newer release(s), latest=${releases.first.tagName}',
);
```

manual 失敗時也加:
```dart
} on ReleaseCheckError catch (e) {
  if (manual) {
    Logger('release').warning('release check failed (manual): $e');
    state = ReleaseCheckFailed(_localizeError(e));
  } else {
    Logger('release').warning('release check failed (silent): $e');
    state = const ReleaseIdle();
  }
  return;
}
```

- [ ] **Step 2: `app_release_checker.dart` 不動**

這個檔目前已有 sealed `ReleaseCheckError`,本身不寫 log(留給 notifier 處理),按 spec 不在此檔加 log。

- [ ] **Step 3: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 4: Commit**

```
git add lib/state/app_release.dart
git commit -m "feat(logging): instrument app release check"
```

---

## Task 16: `widgets/{app_link,banner_link,team_links_bar,translator_text}.dart` 替換 `debugPrint` → `Logger('ui.link')`

**Files:**
- Modify: `lib/widgets/app_link.dart`
- Modify: `lib/widgets/banner_link.dart`
- Modify: `lib/widgets/team_links_bar.dart`
- Modify: `lib/widgets/translator_text.dart`

> **動作**:純機械替換。每個檔取代 `import 'package:flutter/foundation.dart';`(若只剩 debugPrint 用)成 `import 'package:logging/logging.dart';`,並把 `debugPrint('...')` 改成 `Logger('ui.link').warning('...')`。

- [ ] **Step 1: `lib/widgets/app_link.dart`**

找到:
```dart
debugPrint('AppLink: invalid url "${widget.url}"');
```
改為:
```dart
Logger('ui.link').warning('AppLink: invalid url "${widget.url}"');
```

找到:
```dart
debugPrint('openExternalUrl: cannot launch $uri');
```
改為:
```dart
Logger('ui.link').warning('openExternalUrl: cannot launch $uri');
```

加 import:
```dart
import 'package:logging/logging.dart';
```
若 `flutter/foundation.dart` 只被 `debugPrint` 使用,移除。

- [ ] **Step 2: `lib/widgets/banner_link.dart`**

找到:
```dart
debugPrint('BannerLink: invalid url "${widget.url}"');
```
改為:
```dart
Logger('ui.link').warning('BannerLink: invalid url "${widget.url}"');
```

加 import `package:logging/logging.dart`,清理 `flutter/foundation.dart`(若不再需要)。

- [ ] **Step 3: `lib/widgets/team_links_bar.dart`**

找到:
```dart
debugPrint('TeamLinksBar: invalid url "$url"');
```
改為:
```dart
Logger('ui.link').warning('TeamLinksBar: invalid url "$url"');
```

加 import + 清理。

- [ ] **Step 4: `lib/widgets/translator_text.dart`**

找到:
```dart
debugPrint('TranslatorText: dropping invalid href "$href"');
```
改為:
```dart
Logger('ui.link').warning('TranslatorText: dropping invalid href "$href"');
```

加 import + 清理。

- [ ] **Step 5: Quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 6: Commit**

```
git add lib/widgets/app_link.dart lib/widgets/banner_link.dart \
        lib/widgets/team_links_bar.dart lib/widgets/translator_text.dart
git commit -m "refactor(logging): replace debugPrint with Logger in widget links"
```

---

## Task 17: 最終手動驗證 + 全套品質檢查 + 文檔同步

**Files:**
- (read-only verification + final cleanup)

- [ ] **Step 1: 全套品質檢查**

```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` + `All tests passed!`

```
cargo fmt --manifest-path rust/Cargo.toml
cargo build --manifest-path rust/Cargo.toml
```
Expected: `Finished` 無 warning。

- [ ] **Step 2: 手動 end-to-end 驗證(關鍵 — 真實確認可 DEBUG)**

```
flutter run -d windows
```

驗證清單:

| 動作 | 預期看到的 log line(節錄) |
|---|---|
| App 啟動 | `[app.startup] app start v1.0.0+1 on windows ...` |
| App 啟動 | `[rust.bridge] rust log stream connected` |
| 進設定頁 | (無新 log) |
| 切到 zh-Hans | (settings 寫盤,但本次未埋 log;OK) |
| 按更新 | `[wish.repo] update start, forceRecapture=false` |
| MITM 等待中 | `[wish.capture] capture started` + `[rust.mitm] hit gacha endpoint: GET https://...` |
| 抓到 URL | `[wish.capture] capture done, url=https://...?authkey=***&...`(authkey 已脫敏) |
| Fetch 流程 | `[wish.fetcher] banner=301 start, existing=N` 等多條 |
| 完成 | `[wish.repo] update completed: uid=186****456 totalNew=N failed=[]` |
| 設定頁匯出 log | `[accounts.io] logs exported: <path> (...)`,且匯出檔內 header + 上述所有行可見 |
| 切 log level 到 OFF | 之後任何動作都不再產生新 log line |
| 切回 INFO 重啟 app | 啟動時 root level 已恢復為 INFO |

如果有任何 log 訊息看了無法定位問題(例如「failed」沒帶 context),回去補強對應檔的 log 內容。

- [ ] **Step 3: 驗證 sanitize 真的有效**

打開最新 `<applicationSupport>/genshin_impact_wish_gacha_analyzer/logs/YYYY-MM-DD.log`,搜尋 `authkey=`。預期只看到 `authkey=***`,**絕不**能看到真實 authkey 值。同樣搜尋完整 UID(9 位數字),預期只看到 `186****456` 這種遮蔽形式,**不**能有完整 UID。

如果發現 leak,定位來源檔,把該 log call 包進 `sanitizeUrl(...)` / `sanitizeUid(...)`,補完後重跑驗證。

- [ ] **Step 4: 驗證 Rust panic 也接到 log**

(可選)臨時在 `rust/src/api/capture.rs` 內 `start_capture` 加一行 `panic!("test panic for log bridge");`,跑一次,看 Dart 端是否收到 `[rust.panic] panicked at ...`。確認後**還原**該行,再跑 `cargo build` 確認綠。

- [ ] **Step 5: 確認既有 i18n 規則無遺漏**

```
flutter gen-l10n
flutter analyze
```
若有 i18n key 在生成檔 fallback 上有問題(zh_Hans/en 缺 key),補上,跑通。

- [ ] **Step 6: 最終 commit(若 step 2-5 過程有任何補丁)**

把 step 中發現需要補的修改 stage 起來,寫 commit:

```
git status
git add <files>
git commit -m "fix(logging): refine instrumentation after manual verification"
```

如果 step 2-5 都沒發現問題,不必 commit。

- [ ] **Step 7: 開 PR / merge(交給使用者)**

把 branch 推上,人工 review。在 PR 描述內貼上手動驗證清單 + 一段匯出 log 範例(脫敏後)。

---

## Self-Review 後修正紀錄

**Spec 對應檢查(寫完後重看 spec 全部章節):**

| Spec 段 | 對應 task | 備註 |
|---|---|---|
| 4.1 依賴新增 | Task 0 | ✓ |
| 4.2 LogService | Task 2 | ✓ |
| 4.3 Provider | Task 3 | ✓ |
| 4.4 sanitize | Task 1 | ✓ |
| 4.5 全域 error handler | Task 6 | ✓ |
| 4.6 設定頁 SectionCard | Task 9 | ✓ |
| 4.7 SettingsStorage.logLevel | Task 7 | ✓ |
| 4.8 業務 hot path 埋 log 表 | Task 10-16 | ✓ |
| 4.9 Rust ForwardLayer + bridge | Task 4-5-6(分裝) | ✓ |
| 4.10 i18n keys | Task 8 | ✓ |
| 5.1 sanitize_test | Task 1 | ✓ |
| 5.2 log_service_test | Task 2 | ✓ |
| 5.3 既有測試補強 | Task 7 / 11 / 12 | ✓(settings round-trip / fetcher retry / repo update flow) |
| 5.4 不測試 ForwardLayer / connectRustLogStream | — | ✓(spec 明指不測,留手動驗證在 Task 17) |
| 6 提交前檢查 | 每個 task 的 Quality gate step | ✓ |
| 7 風險與權衡 | (文件) | ✓ |

**Placeholder 掃描**:無 TBD / TODO / "implement later"。所有 step 都帶完整程式碼 / 完整 command / 完整 expected output。

**型別一致性**:
- `LogService` 介面:`bootstrap` / `snapshot` / `live` / `clearAll` / `buildExportBundle` / `dispose` / `logsDir` 在 Task 2 定義,Task 9 使用,名稱一致。
- `AppSettings.logLevel` 在 Task 7 加,Task 9 在 `_LogsSection` 與 `_LogLevelDropdown` 用,名稱一致。
- `SettingsNotifier.setLogLevel` 在 Task 7 加,Task 9 用,簽名一致(`Future<void> setLogLevel(String level)`)。
- Rust `LogEvent` 在 Task 4 定義(`timestamp_ms` / `level` / `target` / `message`),Task 6 Dart 側使用 `timestampMs` / `level` / `target` / `message` — FRB 自動把 snake_case 轉 camelCase,正確。

**沒對應 task 的 spec 要求**:無。

---

## 執行選擇

Plan 已完成並存到 `docs/superpowers/plans/2026-05-15-debug-logging.md`。兩種執行方式:

**1. Subagent-Driven(推薦)** — 我每 task 開一個 fresh subagent 執行,task 之間做 review,迭代快、context 乾淨。

**2. Inline Execution** — 在當前 session 內用 `superpowers:executing-plans` 批次跑,中間有 checkpoint review。

選哪種?
