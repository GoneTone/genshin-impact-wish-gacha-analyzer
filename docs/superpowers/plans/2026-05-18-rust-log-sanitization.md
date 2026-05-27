# Rust log 跨橋脫敏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rust log 跨橋進 Dart 寫入共用 log 檔前,在單一匣道統一脫敏 URL 中的 authkey 等敏感 query,杜絕明文外洩。

**Architecture:** 新增 `sanitizeLogMessage(String)` 於既有 `lib/services/log_sanitize.dart`,以 regex 抽出訊息內嵌的 http(s) URL,逐段套用既有 `sanitizeUrl()` 後原位替換;`lib/main.dart` 的 rust log listener 改經此匣道。Rust 端不改,不複製脫敏邏輯。

**Tech Stack:** Dart / Flutter,`flutter_test`,`package:logging`,既有 `sanitizeUrl`。

參考 spec：`docs/superpowers/specs/2026-05-18-rust-log-sanitization-design.md`

---

## File Structure

- `lib/services/log_sanitize.dart` — 既有脫敏工具集；新增 `sanitizeLogMessage`,沿用同檔 `sanitizeUrl`。
- `test/services/log_sanitize_test.dart` — 既有測試；新增 `sanitizeLogMessage` group。
- `lib/main.dart` — `_connectRustLogStream()` listener 接 `event.message` 處改經匣道。

---

## Task 1: 新增 sanitizeLogMessage helper（TDD）

**Files:**
- Modify: `lib/services/log_sanitize.dart`
- Test: `test/services/log_sanitize_test.dart`

- [ ] **Step 1: 寫失敗測試**

在 `test/services/log_sanitize_test.dart` 的 `main()` 內、`sanitizeUrl` group 之後、`sanitizeUid` group 之前，插入新 group：

```dart
  group('sanitizeLogMessage', () {
    test('redacts authkey inside a rust mitm log line', () {
      const msg =
          'hit gacha endpoint: GET https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?authkey_ver=1&sign_type=2&authkey=X%2bYD8cYuvO2c&game_biz=hk4e_global&gacha_type=301&region=os_asia&page=1';
      final out = sanitizeLogMessage(msg);
      expect(out, startsWith('hit gacha endpoint: GET https://'));
      expect(out, contains('authkey=***'));
      expect(out, contains('authkey_ver=***'));
      expect(out, contains('sign_type=***'));
      expect(out, contains('game_biz=***'));
      expect(out, contains('gacha_type=301'));
      expect(out, contains('region=os_asia'));
      expect(out, isNot(contains('X%2bYD8cYuvO2c')));
      expect(out, isNot(contains('XYD8cYuvO2c')));
    });

    test('returns message without url unchanged', () {
      expect(sanitizeLogMessage('capture started'), equals('capture started'));
      expect(
        sanitizeLogMessage('MITM session done, hasUrl=false'),
        equals('MITM session done, hasUrl=false'),
      );
    });

    test('sanitizes only the url segment, keeps trailing fields', () {
      final out = sanitizeLogMessage(
        'fetched url=https://x.example.com/y?authkey=SECRET&size=5 status=200',
      );
      expect(out, contains('authkey=***'));
      expect(out, contains('size=5'));
      expect(out, contains('status=200'));
      expect(out, isNot(contains('SECRET')));
    });

    test('replaces malformed url token with marker', () {
      final out = sanitizeLogMessage('bad link https://');
      expect(out, contains('<malformed url>'));
      expect(out, startsWith('bad link '));
    });

    test('sanitizes multiple urls in one message', () {
      final out = sanitizeLogMessage(
        'a https://h1.example.com/p?authkey=AAA b https://h2.example.com/q?authkey=BBB',
      );
      expect(out, isNot(contains('AAA')));
      expect(out, isNot(contains('BBB')));
      expect('authkey=***'.allMatches(out).length, equals(2));
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/log_sanitize_test.dart`
Expected: 編譯失敗 / FAIL，訊息類似 `The function 'sanitizeLogMessage' isn't defined`。

- [ ] **Step 3: 實作 sanitizeLogMessage**

在 `lib/services/log_sanitize.dart` 結尾（`sanitizeFsPath` 之後）新增：

```dart
/// 掃描自由文字 log 訊息中內嵌的 http(s) URL,逐段套 [sanitizeUrl] 後原位替換,
/// 非 URL 內容原樣保留。Rust log 跨橋進 Dart 時統一呼叫,作為單一脫敏匣道,
/// 避免在 Rust 端複製脫敏邏輯(見 docs/superpowers/specs/2026-05-18-rust-log-sanitization-design.md)。
String sanitizeLogMessage(String message) {
  // log 訊息中 URL 皆為末段或後接空白,以非空白序列界定 token 邊界即足夠。
  final urlPattern = RegExp(r'https?://\S+');
  return message.replaceAllMapped(
    urlPattern,
    (m) => sanitizeUrl(m.group(0)!),
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/log_sanitize_test.dart`
Expected: PASS（All tests passed!）。

- [ ] **Step 5: 提交前品質檢查**

依序執行，三項皆須通過：

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/log_sanitize.dart test/services/log_sanitize_test.dart
git commit -m "fix(log): add sanitizeLogMessage to redact urls in free-text log messages"
```

---

## Task 2: rust log listener 改經脫敏匣道

**Files:**
- Modify: `lib/main.dart`（`_connectRustLogStream()` 內 listener，現約 `lib/main.dart:113-117`）

- [ ] **Step 1: 確認既有 import**

`lib/main.dart` 應已 import log_sanitize（其他脫敏呼叫處用到）。若無，於 import 區加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
```

驗證方式：`flutter analyze` 在 Step 3 會抓出未定義符號，屆時補上即可。

- [ ] **Step 2: 改 listener 改用匣道**

把 `_connectRustLogStream()` 內這段：

```dart
      (event) {
        Logger(
          'rust.${event.target}',
        ).log(_levelFromRust(event.level), event.message);
      },
```

改為：

```dart
      (event) {
        Logger(
          'rust.${event.target}',
        ).log(_levelFromRust(event.level), sanitizeLogMessage(event.message));
      },
```

- [ ] **Step 3: 提交前品質檢查**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`（若報 `sanitizeLogMessage` 未定義，回 Step 1 補 import）
Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "fix(log): route rust log messages through sanitizeLogMessage gateway"
```

---

## 驗證（人工，非自動化測試）

實作完成後，建議實機跑一次祈願更新流程，匯出 log，確認檔內：

```
[rust.mitm] hit gacha endpoint: GET https://...&authkey=***&sign_type=***&game_biz=***&gacha_type=301&region=os_asia&...
```

`authkey` 等已變 `***`，與 Flutter 端 `wish.capture` 那行脫敏規則一致。

**已知限制（spec 已裁決，不處理）**：dev `cargo run` 終端機 stdout 不走跨橋路徑，仍會印原始 authkey。

---

## Self-Review

- **Spec coverage**：spec 三項改動 → 改動 1（`sanitizeLogMessage`）= Task 1；改動 2（main.dart 匣道）= Task 2；改動 3（測試群組）= Task 1 Step 1。spec「不做」清單（不改 Rust、不移植、stdout 限制）已於計畫對應註明。無遺漏。
- **Placeholder scan**：無 TBD/TODO，所有 code step 均含完整程式碼與確切指令。
- **Type consistency**：`sanitizeLogMessage(String) -> String` 於 Task 1 定義，Task 2 以相同簽章呼叫；沿用既有 `sanitizeUrl(String) -> String` 簽章一致。
