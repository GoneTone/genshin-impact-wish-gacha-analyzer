# Spec:可匯出的 DEBUG log 系統(Dart + Rust)

- 日期:2026-05-15
- 分支:`flutter-rewrite`
- 來源:使用者要求新增「方便 DEBUG」的 log 記錄,需(a)能在開發控制台看到,(b)使用者可在設定頁匯出,(c)log 內容要足以實際定位問題,而不是「看了等於沒看」。

## 1. 背景

目前專案 logging 現況:

| 層 | 現況 |
|---|---|
| Dart 散落 6 處 | `lib/main.dart:35/38`、`lib/state/app_release.dart:71`、`lib/widgets/{app_link,banner_link,team_links_bar,translator_text}.dart` 用 `debugPrint`。沒等級、沒時間戳、release build 完全消失、無法匯出。 |
| Dart 業務 hot path | `WishRepository._runUpdate`(`lib/state/wish_repository.dart:157`)、`WishFetcher.fetchPage`(`lib/services/wish_fetcher.dart:61`)、`WishCapture`(`lib/state/wish_capture.dart`)、`WishStorage`、`SettingsStorage`、`accounts_import/export` 完全沒 log。使用者回報「更新失敗」、「卡在抓取」幾乎無法 reproduce 定位。 |
| Rust | `rust/src/{ca,cert_store,mitm}.rs` 已使用 `tracing::info!/debug!/error!`,`tracing_subscriber::fmt()` 在 `start_capture` 內 try_init,但只寫到 stdout — `flutter run` 期間可見,使用者匯出抓不到。 |

問題:更新流程牽涉 Dart (Riverpod state machine)+ Rust (MITM proxy + cert install + sys proxy registry),失敗點分散兩側。要遠端 DEBUG 必須同時擁有兩側的 timeline,目前完全做不到。

## 2. 目標

1. 建立 **Dart 側 `LogService`**:用 `package:logging` 當骨架,LogRecord 同時轉發到「開發控制台」「記憶體 ring buffer」「當日檔案」。
2. **業務 hot path 全面埋 log**(WishRepository / WishFetcher / WishCapture / WishStorage / SettingsStorage / accounts_import-export / app_release_checker),每條 log 帶足夠 context(banner / uid / retcode / retry / 脫敏 URL)直接定位問題。
3. **全域 error handler**:`FlutterError.onError` + `PlatformDispatcher.onError` + `runZonedGuarded` 三層,uncaught 進 log。
4. **敏感資料脫敏**:`authkey` / `game_biz` / `sign_type` 等 query value 改 `***`,UID 中段遮蔽。
5. **Rust 側 logging bridge**:新增 FRB stream `start_log_stream`,自訂 `tracing_subscriber::Layer` 把 Rust `tracing` 事件轉發到 Dart `LogService`,兩側共用同一份檔案、同一份匯出。Rust panic 也接進來。
6. **設定頁 SectionCard「Log 偵錯」**:匯出 log(單一 `.log`,含 7 天合併 + 系統資訊 header)、開啟 log 資料夾、清除所有 log、log 等級下拉。
7. **檔案輪替**:`<applicationSupport>/logs/YYYY-MM-DD.log`,保留 7 天,啟動時清舊檔。

## 3. 非目標(YAGNI)

- 不引入 `talker` / `talker_flutter` / `logger` 第三方套件(Dart 端只用 `package:logging` 官方套件)。
- 不在設定頁實作 log viewer(內建瀏覽 UI)。使用者 DEBUG 流程 = 匯出 → 把檔案丟給開發者。
- 不做 Dart → Rust 反向 log bridge(Dart 自己有 logger,無需委託 Rust 印)。
- 不在 Rust 端寫檔案 — 所有檔案 I/O 集中 Dart 側,單一來源。
- 不做 log 上傳到遠端 server / Sentry 之類整合 — YAGNI,本次只做本地可匯出。
- 不為「log 等級」每一檔做 fine-grained tuning UI — 只有全域 root level 一個下拉。
- 不在 7 種 fallback 語系(`ja` / `es` / `fr` / `pt` / `th` / `vi` / `zh_Hans` 部分)為新增 settings i18n key 全寫,僅 `zh_Hant` / `zh_Hans` / `en` 3 份,其餘 fallback 到 template(對齊既有 `2026-05-14-overview-section-separation-and-empty-state-design.md` 慣例)。
- 不做日誌壓縮(`.log.gz`)— 7 天文字 log 預估 < 5 MB,可接受。

## 4. 設計

### 4.1 依賴新增

`pubspec.yaml`:
```yaml
dependencies:
  logging: ^1.3.0
```

Rust 端 `rust/Cargo.toml` 已有 `tracing` / `tracing-subscriber`,無需新增。

### 4.2 `LogService` — 核心抽象

新檔 `lib/services/log_service.dart`。職責:訂閱 root `Logger.root.onRecord`,把每條 `LogRecord` 分發到四個出口(開發控制台 / ring buffer / 當日檔案 / 設定頁 stream)。

```dart
import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class LogService {
  LogService._(this.logsDir);

  final Directory logsDir;

  /// 最多保留多少天的 log file
  static const int _retentionDays = 7;

  /// 記憶體 ring buffer 上限(行)— 設定頁即時預覽用
  static const int _ringBufferCapacity = 2000;

  final Queue<String> _ringBuffer = Queue<String>();
  final StreamController<String> _liveController =
      StreamController<String>.broadcast();

  IOSink? _todaySink;
  DateTime? _todayDate; // UTC date(year, month, day)

  StreamSubscription<LogRecord>? _rootSubscription;

  /// `main()` 內呼叫:建立 logs/ 資料夾、刪舊檔、開今天的 sink、訂閱 root Logger
  static Future<LogService> bootstrap(Directory baseDir) async {
    final logsDir = Directory('${baseDir.path}/logs');
    if (!await logsDir.exists()) await logsDir.create(recursive: true);

    final svc = LogService._(logsDir);
    await svc._rotate();
    await svc._openTodaySink();

    Logger.root.level = Level.INFO; // 預設,SettingsStorage 載入後可覆蓋
    svc._rootSubscription = Logger.root.onRecord.listen(svc._handle);
    return svc;
  }

  void _handle(LogRecord r) {
    final line = _format(r);

    // 1. dev console:`dart:developer` log() → DevTools / IDE
    developer.log(
      r.message,
      time: r.time,
      level: r.level.value,
      name: r.loggerName,
      error: r.error,
      stackTrace: r.stackTrace,
    );
    if (kDebugMode) {
      // 同步給 `flutter run` console
      // ignore: avoid_print
      debugPrint(line);
    }

    // 2. ring buffer
    _ringBuffer.addLast(line);
    while (_ringBuffer.length > _ringBufferCapacity) _ringBuffer.removeFirst();
    if (!_liveController.isClosed) _liveController.add(line);

    // 3. 當日檔案(fire-and-forget,確保不阻塞 caller)
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
    // 跨日 rollover:r.time 跟 _todayDate 不同 → 換 sink
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
    final entries = await logsDir.list().toList();
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: _retentionDays));
    for (final e in entries) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.log$').firstMatch(name);
      if (m == null) continue;
      final fd = DateTime.utc(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
      if (fd.isBefore(cutoff)) {
        try {
          await e.delete();
        } catch (_) {/* ignore, 下次再試 */}
      }
    }
  }

  /// 設定頁「匯出」按鈕呼叫:把 logs/ 內所有 .log 合併 + header → 字串
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
      ..writeln('files: ${entries.map((e) => e.uri.pathSegments.last).join(', ')}')
      ..writeln('=== begin ===');

    for (final f in entries) {
      buf
        ..writeln()
        ..writeln('--- ${f.uri.pathSegments.last} ---');
      buf.write(await f.readAsString());
    }
    return buf.toString();
  }

  /// 設定頁「清除」按鈕呼叫
  Future<void> clearAll() async {
    await _todaySink?.flush();
    await _todaySink?.close();
    _todaySink = null;
    final entries = await logsDir.list().toList();
    for (final e in entries) {
      if (e is File && e.path.endsWith('.log')) {
        try { await e.delete(); } catch (_) {/* ignore */}
      }
    }
    await _openTodaySink();
  }

  /// 設定頁即時 stream + 取現有 buffer 給初始化
  List<String> snapshot() => _ringBuffer.toList(growable: false);
  Stream<String> get live => _liveController.stream;

  Future<void> dispose() async {
    await _rootSubscription?.cancel();
    await _todaySink?.flush();
    await _todaySink?.close();
    await _liveController.close();
  }
}
```

設計取捨:

- **`package:logging` Logger 樹**:`Logger('wish.repo')` / `Logger('rust.mitm')` 自動掛在 `Logger.root` 下,任何地方拿 `Logger('xxx')` 都進同一個 sink,呼叫端無需 inject。
- **`_appendToFile` 不 await**:`Logger.log` 是同步介面,我們不能 block。`IOSink.writeln` 內部有 buffer + async flush,順序由 sink 保證(同一個 sink 上 writeln 依序排隊)。
- **跨日 rollover 在 `_handle` 內 detect**:`r.time` 跟 `_todayDate` 比對,簡單可靠(不靠 timer)。
- **`_rotate` 只在開檔/換日呼叫**:不每條 log 都掃資料夾。
- **`developer.log` + `debugPrint` 並列**:前者給 DevTools / Observatory(IDE 整合好),後者給 `flutter run` console(看 raw 文字方便)。release build 中 `kDebugMode=false`,`debugPrint` 那條會 short-circuit;`developer.log` 在 release 也安全(no-op for level < INFO 時影響可忽略)。
- **Ring buffer 大小寫死 2000**:約 200 KB 記憶體,不暴露給設定 — YAGNI。

### 4.3 Provider 接入

新檔 `lib/state/log_service.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_service.dart';

/// 必須在 main.dart 用 overrideWithValue 注入(LogService.bootstrap 是 async)
final logServiceProvider = Provider<LogService>((ref) {
  throw UnimplementedError('logServiceProvider must be overridden in main()');
});
```

對齊 `wishStorageProvider` 既有模式。

### 4.4 敏感資料脫敏

新檔 `lib/services/log_sanitize.dart`:

```dart
/// 把 authkey / authkey_ver / game_biz / sign_type 等敏感 query 改 `***`,
/// 其餘 query 保留。失敗(非合法 URL)直接回 `<malformed url>`。
String sanitizeUrl(String raw) {
  final Uri uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return '<malformed url>';
  }
  const redactKeys = {'authkey', 'authkey_ver', 'sign_type', 'game_biz'};
  final newQuery = <String, String>{};
  uri.queryParameters.forEach((k, v) {
    newQuery[k] = redactKeys.contains(k) ? '***' : v;
  });
  return uri.replace(queryParameters: newQuery).toString();
}

/// UID:`123****890` 前 3 + 後 3。長度 < 6 全遮 `***`。
String sanitizeUid(String uid) {
  if (uid.length < 6) return '***';
  return '${uid.substring(0, 3)}****${uid.substring(uid.length - 3)}';
}
```

**用法**:WishCapture / WishFetcher / WishStorage 一律經這兩個 helper 後才 log。stack trace 內如果還是 leak URL 是 edge case,使用者匯出時自己再剪 — 不在 LogService 層做 stack-rewrite(成本不值)。

### 4.5 全域 error handler

`lib/main.dart` 改造(節錄):

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
// ...

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await RustLib.init();

    final supportDir = await getApplicationSupportDirectory();
    final logService = await LogService.bootstrap(supportDir);

    // 必須在 LogService.bootstrap 之後設定
    FlutterError.onError = (details) {
      Logger('app.error').severe(
        'FlutterError: ${details.exceptionAsString()}',
        details.exception,
        details.stack,
      );
      FlutterError.presentError(details); // 保留既有 stderr 紅字
    };
    PlatformDispatcher.instance.onError = (e, st) {
      Logger('app.error').severe('Uncaught async error', e, st);
      return true;
    };

    // Rust → Dart log bridge,fire-and-forget(見 4.9)
    unawaited(_connectRustLogStream());

    // ...(既存的 windowManager / cleanupStaleProxy / wishStorage / pkgInfo)
    // 把 cleanupStaleProxy 內既有 debugPrint 改為 Logger('app.startup').info/warning

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
  }, (e, st) {
    // 備援:zone 層接到的 uncaught(`PlatformDispatcher.onError` 漏掉的少數案例)
    Logger('app.error').severe('Zone uncaught', e, st);
  });
}
```

三層 error handler 分工:

| 層 | 接到的錯誤 |
|---|---|
| `FlutterError.onError` | Widget build / framework 階段的同步錯誤 |
| `PlatformDispatcher.onError` | uncaught async error(Future / Stream 沒接 `.catchError`) |
| `runZonedGuarded` | 上面兩個都漏掉的 zone 層 error(極少數,雙保險) |

實務上 `PlatformDispatcher.onError` 接 ~95% 的 async error,`runZonedGuarded` 的價值較低,但成本可忽略,本次保留三層。

### 4.6 設定頁「Log 偵錯」SectionCard

`lib/pages/settings_page.dart` 在「資料管理」之後、「帳號管理」之前插入新 SectionCard:

```dart
SectionCard(
  title: l.settingsLogs,
  icon: Icons.bug_report_outlined,
  child: const _LogsSection(),
),
const SizedBox(height: AppSpacing.xl),
```

`_LogsSection` 內元素(由上到下):

| Widget | 行為 |
|---|---|
| 灰色 hint 文字(`l.settingsLogsHint`) | 排在 section 內最上方,一行小字,風格對齊 `_DataManagement` 的說明態度(若該 section 有 hint;沒有則本次新增即為慣例首例) |
| `_LogLevelDropdown` | 5 選 1:`OFF / SEVERE / WARNING / INFO / FINE`,標籤用 `l.settingsLogsLevel`,選項用 `l.settingsLogsLevelOff/Severe/Warning/Info/Fine`。變動寫進 `SettingsStorage.logLevel`,同時 `Logger.root.level = ...` |
| `OutlinedButton` 匯出 log | 呼叫 `LogService.buildExportBundle(...)`(注入 appVersion / OS / locale / theme)→ `file_selector.getSaveLocation(suggestedName: 'gwga_logs_YYYY-MM-DD_HHmmss.log')` → `File.writeAsString` → SnackBar 提示路徑 |
| `OutlinedButton` 開啟 log 資料夾 | `url_launcher.launchUrl(Uri.file(logsDir.path))` |
| `FilledButton`(danger 色)清除 log | `showConfirmTypeDialog` 期待輸入 `CLEAR` → `LogService.clearAll()` → SnackBar |

對齊既有 `_DataManagement` 風格(`Wrap(spacing: AppSpacing.s, runSpacing: AppSpacing.s, ...)`)。

**設計取捨**:
- 不顯示 ring buffer 即時內容 — 使用者要看內容直接「開啟 log 資料夾」用記事本看更直觀,設定頁裡跑 listview 沒附加價值。
- log 等級下拉**不分 sink**(檔案 / console 同 level)— 簡化模型,使用者只需理解一個概念。
- 匯出檔名 `gwga_logs_<timestamp>.log`(`gwga` = Genshin Wish Gacha Analyzer 縮寫),對齊既有 `genshin_wish_backup_<stamp>.json` 命名慣例。

### 4.7 `SettingsStorage` 擴充 `logLevel`

`lib/services/settings_storage.dart` 新增:

```dart
abstract final class SettingsStorage {
  // ...既有 keys
  static const _kLogLevel = 'pref.logLevel';
  // load() 內補:
  // logLevel: prefs.getString(_kLogLevel) ?? 'INFO',
  // save() 內補:setString(_kLogLevel, s.logLevel)
}

@immutable
class AppSettings {
  // ...既有 fields
  final String logLevel; // "OFF"|"SEVERE"|"WARNING"|"INFO"|"FINE"
  // defaults: logLevel: 'INFO'
}
```

`SettingsNotifier` 加 `setLogLevel(String)` 方法,同時呼叫 `Logger.root.level = _parseLevel(value)`。

**設計取捨**:存字串而非 `int`(`Level.value`)— 升級 / 跨平台讀檔更可讀;parse 在 notifier 一處處理。

### 4.8 業務 hot path 埋 log — 完整插入點清單

每條 log 都帶**能直接定位問題的 context**。

**`lib/main.dart`**(改寫既有 `debugPrint`):

| 位置 | Logger | Level | 訊息 |
|---|---|---|---|
| `main()` 起頭 | `app.startup` | INFO | `app start v${version} on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}, locale=${Platform.localeName}` |
| `cleanupStaleProxy` 命中 | `app.startup` | INFO | `cleanup_stale_proxy: stale proxy detected and reset` |
| `cleanupStaleProxy` 例外 | `app.startup` | WARNING | with error |

**`lib/state/wish_capture.dart`**:

| 事件 | Logger | Level | 訊息 |
|---|---|---|---|
| `start()` 觸發 | `wish.capture` | INFO | `capture started` |
| 收到 event | `wish.capture` | FINE | `captured: host=${host}` |
| `onError` | `wish.capture` | SEVERE | `capture error` + error/stack |
| `onDone(url 命中)` | `wish.capture` | INFO | `capture done, url=${sanitizeUrl(url)}` |
| `onDone(url null)` | `wish.capture` | INFO | `capture done with no match` |
| `cancel()` | `wish.capture` | INFO | `capture cancelled by user` |

**`lib/services/wish_fetcher.dart`**:

| 事件 | Logger | Level | 訊息 |
|---|---|---|---|
| `fetchPage` 開始(每次 retry attempt) | `wish.fetcher` | FINE | `fetchPage gachaType=${type} endId=${endId} attempt=${attempt}` |
| `retcode != 0` 但會 retry(`-110`) | `wish.fetcher` | WARNING | `rate-limited (retcode=-110), backoff ${retryBackoff}, attempt=${attempt}/${_maxRetryOnRateLimit}` |
| `retcode = -101 / -100` | `wish.fetcher` | WARNING | `auth expired retcode=${retcode}` |
| `retcode` 其他非零 | `wish.fetcher` | SEVERE | `ApiError retcode=${retcode} message=${message}` |
| `probeUid` 命中 | `wish.fetcher` | INFO | `probe ${category}: hit uid=${sanitizeUid(uid)} via gachaType=${type}` |
| `probeUid` 全空 | `wish.fetcher` | INFO | `probe: no records in any banner` |
| `fetchBannerWithMerge` 開始 | `wish.fetcher` | INFO | `banner=${gachaType} start, existing=${existing.length}` |
| `fetchBannerWithMerge` 結束 | `wish.fetcher` | INFO | `banner=${gachaType} done, fresh=${fresh.length} pages=${pageIndex}` |

**`lib/state/wish_repository.dart`**:

| 事件 | Logger | Level | 訊息 |
|---|---|---|---|
| `_runUpdate` 起頭 | `wish.repo` | INFO | `update start, forceRecapture=${forceRecapture}` |
| `loadCapturedUrl` 命中 | `wish.repo` | INFO | `using cached url for uid=${sanitizeUid(uid)}` |
| `_runMitm` 開始/結束 | `wish.repo` | INFO | `MITM ${isFallback ? "fallback" : "primary"} session ${started/done}` |
| MITM url=null(取消) | `wish.repo` | INFO | `update aborted (user cancelled capture)` |
| AuthExpired catch | `wish.repo` | WARNING | `auth expired, falling back to MITM recapture` |
| `ClientException` + cancel | `wish.repo` | INFO | `update cancelled (http client closed)` |
| `ClientException` 一般 | `wish.repo` | WARNING | `http client error: ${e.message} uri=${sanitizeUrl(e.uri)}` |
| 任意 banner `failed.add` | `wish.repo` | WARNING | `banner=${nameKey} failed: ${error}` |
| `_fetchAllBanners` 完成 | `wish.repo` | INFO | `update completed: uid=${sanitizeUid} totalNew=${totalNew} failed=[${nameKeys}]` |
| `removeUid` / `clearActive` / `clearAll` | `wish.repo` | INFO | `cleared uid=${sanitizeUid}` / `cleared all` |
| `importAccounts` 完成 | `wish.repo` | INFO | `import: success=${n} failed=[${uids}] records=${total}` |
| 全 catch 失敗 | `wish.repo` | SEVERE | `update unexpected error` + stack |

**`lib/services/wish_storage.dart`**:

| 事件 | Logger | Level | 訊息 |
|---|---|---|---|
| `save` 完成 | `wish.storage` | FINE | `saved uid=${sanitizeUid} records=${total}` |
| `load` 失敗(`FormatException` 等) | `wish.storage` | SEVERE | `load failed for uid=${sanitizeUid}` + error/stack |
| `save` 失敗 | `wish.storage` | SEVERE | `save failed for uid=${sanitizeUid}` + error/stack |
| `delete` / `clearAll` | `wish.storage` | INFO | `delete uid=${sanitizeUid}` / `clear all wish data` |
| `saveCapturedUrl` | `wish.storage` | FINE | `saved captured url for uid=${sanitizeUid}` |
| `deleteCapturedUrl` | `wish.storage` | FINE | `deleted captured url for uid=${sanitizeUid}` |

**`lib/services/settings_storage.dart`**:在 `_parseAliases` / `_parseOrder` 既有 `catch (_)` 區塊加 `Logger('settings').warning(...)`,讓使用者 alias/order 損毀時看得到。

**`lib/services/accounts_import.dart` / `accounts_export.dart`**:

| 事件 | Logger | Level | 訊息 |
|---|---|---|---|
| `importAccounts` 拋 `FormatException` 之前 | `accounts.io` | WARNING | `import failed: ${e.message}` |
| `exportAccounts` 完成(由 caller `_export` 呼叫) | `accounts.io` | INFO | `export: uids=${n} records=${total}` |

**`lib/services/app_release_checker.dart`**(取代 `app_release.dart` 既有 `debugPrint`):

| 事件 | Logger | Level | 訊息 |
|---|---|---|---|
| `check` 開始 | `release` | INFO | `release check start manual=${manual}` |
| 結果有新版 | `release` | INFO | `release check: ${n} newer release(s), latest=${tag}` |
| up-to-date | `release` | INFO | `release check: up-to-date` |
| silent failure | `release` | WARNING | `release check failed (silent): ${error}` |
| manual failure | `release` | WARNING | `release check failed (manual): ${error}` |

**`lib/widgets/{app_link,banner_link,team_links_bar,translator_text}.dart`**:既有 `debugPrint` 替換為 `Logger('ui.link').warning(...)`,內容不變(URL 不合法等)。

### 4.9 Rust 端 logging bridge

**4.9.1 新 FRB API** `rust/src/api/logging.rs`:

```rust
use anyhow::Result;
use flutter_rust_bridge::frb;
use std::sync::Mutex;
use once_cell::sync::OnceCell;
use crate::frb_generated::StreamSink;

#[derive(Clone)]
#[frb]
pub struct LogEvent {
    pub timestamp_ms: i64,
    pub level: String,   // "ERROR" | "WARN" | "INFO" | "DEBUG" | "TRACE"
    pub target: String,  // tracing target,例如 "mitm" / "ca" / "cert_store" / "panic"
    pub message: String,
}

static FORWARD_SINK: OnceCell<Mutex<Option<StreamSink<LogEvent>>>> = OnceCell::new();
static INIT: OnceCell<()> = OnceCell::new();

pub fn start_log_stream(sink: StreamSink<LogEvent>) -> Result<()> {
    let slot = FORWARD_SINK.get_or_init(|| Mutex::new(None));
    *slot.lock().unwrap() = Some(sink);
    init_tracing_once();
    Ok(())
}

pub(crate) fn init_tracing_once() {
    INIT.get_or_init(|| {
        use tracing_subscriber::{prelude::*, EnvFilter};
        let filter = EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| EnvFilter::new("info"));
        tracing_subscriber::registry()
            .with(filter)
            .with(tracing_subscriber::fmt::layer())  // 保留 stdout(cargo run 期間)
            .with(ForwardLayer)
            .init();

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
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _ctx: tracing_subscriber::layer::Context<'_, S>,
    ) {
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
        // sink.add 是 non-blocking;失敗(stream closed)就 drop
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
            out.push_str(&format!(" {k}={v}"));
        }
        out
    }
}

impl tracing::field::Visit for MessageVisitor {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.message = Some(format!("{value:?}"));
        } else {
            self.fields.push((field.name().to_string(), format!("{value:?}")));
        }
    }
    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        if field.name() == "message" {
            self.message = Some(value.to_string());
        } else {
            self.fields.push((field.name().to_string(), value.to_string()));
        }
    }
}
```

**4.9.2 重構 `start_capture`** — 移除原本的 `try_init`:

```rust
pub fn start_capture(sink: StreamSink<CapturedRequest>) -> Result<()> {
    // ...既有 SESSION lock 檢查
    crate::api::logging::init_tracing_once();  // ← 取代既有 fmt().try_init()

    let root = ca::load_or_generate()?;
    // ...(其餘不變)
}
```

**4.9.3 `lib.rs` 加掛 module**:
```rust
pub mod api;
// api/mod.rs:
pub mod capture;
pub mod logging;
```

**4.9.4 Dart 端接通**(`main.dart` 內 `_connectRustLogStream`):

```dart
Future<void> _connectRustLogStream() async {
  try {
    rust_logging.startLogStream().listen(
      (event) {
        final lvl = _levelFromRust(event.level);
        Logger('rust.${event.target}').log(
          lvl,
          event.message,
          null,
          null,
          DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
        );
      },
      onError: (e, st) {
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
  _ => Level.FINER, // TRACE
};
```

**4.9.5 重新生成 FRB binding**:`flutter_rust_bridge_codegen generate`(依專案既有 codegen 設定),會自動產出 `lib/src/rust/api/logging.dart` 對應的 `startLogStream() => Stream<LogEvent>`。

**設計取捨**:
- ForwardLayer 不做 filter — `EnvFilter` 已在 registry 層過濾;layer 內收到的事件都通過了 filter。
- `FORWARD_SINK` 是 `OnceCell<Mutex<Option<_>>>`:`OnceCell` 確保 slot 只建一次,`Mutex<Option<_>>` 容許 sink replace(若 Dart 端因某種原因重連 stream)。
- `sink.add` 失敗忽略(drop event)— Rust 端不該因為 log 失敗 crash 業務邏輯。
- Rust 那邊 `cargo run` 期間的 stdout `fmt::layer()` 保留 — 開發體驗不變。

### 4.10 i18n 新增 keys(3 份 ARB)

| key | zh_Hant | zh_Hans | en |
|---|---|---|---|
| `settingsLogs` | Log 偵錯 | 日志调试 | Debug logs |
| `settingsLogsHint` | 留下執行紀錄，協助回報問題時找出原因。 | 留下运行记录，协助报告问题时找出原因。 | Records app activity to help diagnose issues when reporting bugs. |
| `settingsLogsExport` | 匯出 log 檔 | 导出日志文件 | Export logs |
| `settingsLogsOpenFolder` | 開啟 log 資料夾 | 打开日志文件夹 | Open logs folder |
| `settingsLogsClear` | 清除所有 log | 清除所有日志 | Clear all logs |
| `settingsLogsLevel` | 紀錄等級 | 记录等级 | Log level |
| `settingsLogsLevelOff` | 關閉 | 关闭 | Off |
| `settingsLogsLevelSevere` | 嚴重 | 严重 | Severe |
| `settingsLogsLevelWarning` | 警告 | 警告 | Warning |
| `settingsLogsLevelInfo` | 一般(預設) | 一般(默认) | Info (default) |
| `settingsLogsLevelFine` | 詳細 | 详细 | Fine |
| `settingsLogsExportSuccess` | 已匯出 log:{path} | 已导出日志:{path} | Logs exported: {path} |
| `settingsLogsClearConfirmBody` | 這會永久刪除 logs/ 內所有檔案。若回報問題前需要 log，請先匯出。輸入 CLEAR 確認。 | 这会永久删除 logs/ 内所有文件。若报告问题前需要日志，请先导出。输入 CLEAR 确认。 | This will permanently delete all files in logs/. Export them first if you need them for bug reports. Type CLEAR to confirm. |

其餘 `ja/es/fr/pt/th/vi` fallback 到 template,對齊既有 `pityAverageInterval` 慣例。

## 5. 測試

### 5.1 新增 `test/services/log_sanitize_test.dart`

| Test case | 驗證點 |
|---|---|
| `sanitizeUrl redacts authkey` | `https://...?authkey=abc&end_id=0` → `authkey=***&end_id=0` |
| `sanitizeUrl redacts all sensitive keys` | `authkey/authkey_ver/sign_type/game_biz` 同時出現都被遮 |
| `sanitizeUrl keeps non-sensitive query` | `gacha_type=301` 不動 |
| `sanitizeUrl returns marker on malformed` | `not a url ##` → `<malformed url>` |
| `sanitizeUid masks middle` | `'186123456'` → `'186****456'` |
| `sanitizeUid short` | `'12345'` → `'***'` |

### 5.2 新增 `test/services/log_service_test.dart`

用 `tempfile`-style 建臨時 dir 跑(`Directory.systemTemp.createTemp`):

| Test case | 驗證點 |
|---|---|
| `bootstrap creates logs/ dir` | 資料夾存在 |
| `INFO log appends to today file` | `Logger('test').info('hi')` 後該日檔內含 `'hi'` |
| `level filter respects Logger.root.level` | `Logger.root.level = Level.WARNING` 後 INFO log 不寫入檔案 |
| `ring buffer caps at capacity` | 灌 3000 條 → `snapshot().length == 2000` 且為最後 2000 條 |
| `live stream emits new records` | listen → 灌 1 條 → 收到 1 條 |
| `clearAll deletes all .log` | 灌幾條 → `clearAll()` → 資料夾內無 `.log`,新 sink 重開可寫 |
| `rotation deletes files older than retention` | 預先放 8 天前的 `2026-05-07.log` → `bootstrap` 後該檔被刪 |
| `buildExportBundle merges all files with header` | 多檔合併、header 內含 appVersion/os/locale/theme |

### 5.3 既有測試補充

| 測試檔 | 補強 |
|---|---|
| `test/state/wish_repository_test.dart` | 用 `Logger.root.onRecord.listen` 蒐集,驗證 update 流程關鍵節點(`update start` / `update completed` / `auth expired falling back`)有發 log |
| `test/services/wish_fetcher_test.dart` | 同上,驗證 `retcode=-110` 退避時發 WARNING log |
| `test/services/settings_storage_test.dart` | 新增 `logLevel` round-trip:save → load 後值一致;預設 `'INFO'` |
| `test/state/settings_test.dart` | `setLogLevel('WARNING')` 後 `Logger.root.level == Level.WARNING` |

### 5.4 不測試的部分

- Rust 端 `ForwardLayer`:Rust 單元測試只需驗證 `start_log_stream` 能 init 不 panic;ForwardLayer 真正運作需要 FRB runtime,留給手動 / e2e 測試。本次新增 `rust/src/api/logging.rs` 內**不**寫 unit test。
- Dart 側 `_connectRustLogStream`:單純 listen+forward,行為簡單,本次不寫 widget test。

## 6. 提交前品質檢查

依 `CLAUDE.md`:

1. `flutter_rust_bridge_codegen generate`(新增了 Rust API,需重生 binding;依專案既有 codegen 設定)
2. `flutter gen-l10n`(新增 ARB keys)
3. `dart format lib/ test/`(注意:不要對 `.` 跑,會動到 `rust_builder/` 內 vendored 程式碼)
4. `flutter analyze` → `No issues found!`
5. `flutter test` → `All tests passed!`
6. Rust 側:`cargo fmt --manifest-path rust/Cargo.toml` + `cargo build --manifest-path rust/Cargo.toml`(沒測就不跑 `cargo test`,但 build 必須過)

## 7. 風險與權衡

- **`IOSink.writeln` 非同步 + 順序**:同一個 sink 內 writeln 由 dart:io 內部 queue 保證順序;跨日 rollover 時 `_rolloverTo` 是 async,期間若有新 log 進來會寫到舊 sink — 可接受(實際發生機率極低,午夜瞬間有 log 才會碰到,且就算碰到也只是「昨天最後一行 log 寫在昨天檔案」這個自然行為)。
- **`developer.log` 在 release build**:不會 no-op,但 release 沒有 DevTools attach,等同丟掉。可接受 — 本次 LogService 的「給開發者用」職責由「匯出檔案」承擔,`developer.log` 是 dev-only 額外便利。
- **Logger.root level 全域影響**:設定頁調整 `OFF` 後 LogService 仍會收到「level >= OFF」(也就是無),檔案不寫、ring buffer 不寫。設成 `OFF` 後找不回 log,使用者改回後從那刻開始才有 — 文案會說明。
- **Rust ForwardLayer 性能**:每個 event 一次 mutex lock + 一次 channel send。`hudsucker` 內部高頻 trace 已被 `EnvFilter("info")` 擋掉,實際進到 ForwardLayer 的 event 量低(每次 update 估 10~30 條),無虞。
- **FRB stream 生命週期**:`start_log_stream` 在 app 整個生命週期維持,只有 app 關閉才結束 — Dart 側 `listen()` 不主動 cancel。若 stream 提早 close(Rust 側 panic 後重啟?目前架構不重啟),`onError` 會記一條 warning。
- **`runZonedGuarded` vs `PlatformDispatcher.onError` 重疊**:雙保險,event 不會重複進 log(同一個 error 只會走其中一條路徑)。
- **新增 `package:logging` 相依**:純 Dart,~5 KB,Anthropic-maintained-grade 套件,無風險。
- **既有 6 處 `debugPrint` 全部移除替換**:風險低,純文字到 Logger 介面的機械替換。
