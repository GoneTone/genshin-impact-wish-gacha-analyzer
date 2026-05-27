# 啟動視窗大小與位置記憶 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把舊版 Electron `electron-window-state` 的「首次依公式（最窄方向扣 100、16:9）置中、之後記住位置/尺寸/最大化狀態」帶回 flutter-rewrite。

**Architecture:** 在 `lib/services/window_state_keeper.dart` 集中三件事：(1) 兩個 top-level `@visibleForTesting` 純函式（公式、初始 bounds 解析）— 跑單元測試；(2) `WindowStateKeeper` 類別 with `WindowListener` — 持久化、debounce、套用；(3) 對外只暴露 `WindowStateKeeper.bootstrap()`。`main.dart` 在 `runApp` 之前呼叫一次即可。`windows/runner/main.cpp` 不動。

**Tech Stack:** Dart / Flutter；新增依賴 `window_manager`、`screen_retriever`；既有依賴 `shared_preferences`。

**Spec：** `docs/superpowers/specs/2026-05-10-window-sizing-and-state-keeper-design.md`

**前置條件：**
- 工作分支：`flutter-rewrite`
- 開發環境：Windows（手動驗收必須在 Windows 桌面跑 `flutter run -d windows`）
- 每次 commit 前必須通過：`dart format lib/ test/`、`flutter analyze`（`No issues found!`）、`flutter test`（`All tests passed!`）— 規則出處 `CLAUDE.md`。

---

### Task 1: 新增 `window_manager` 與 `screen_retriever` 依賴

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`（自動）

- [ ] **Step 1: 加入依賴**

Run（PowerShell）:
```powershell
flutter pub add window_manager screen_retriever
```

Expected: `pubspec.yaml` 自動加入兩個 entry，`pubspec.lock` 更新；終端列印 `Changed N dependencies!`。

- [ ] **Step 2: 確認 `pubspec.yaml` 變動**

讀 `pubspec.yaml`，確認 `dependencies:` 區塊內出現：

```yaml
  window_manager: ^X.Y.Z
  screen_retriever: ^X.Y.Z
```

（版本號由 `flutter pub add` 決定，不需手改。）

- [ ] **Step 3: 跑一次 analyze 確認沒破現有編譯**

Run（PowerShell）:
```powershell
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

Run（PowerShell）:
```powershell
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add window_manager and screen_retriever"
```

---

### Task 2: TDD `computeDefaultWindowSize` 純函式

**Files:**
- Create: `lib/services/window_state_keeper.dart`
- Create: `test/services/window_state_keeper_test.dart`

- [ ] **Step 1: 建立空檔（含必要 imports 與常數）**

Write `lib/services/window_state_keeper.dart`：

```dart
// lib/services/window_state_keeper.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const Size _kMinWindowSize = Size(800, 450);
const double _kMargin = 100;
```

- [ ] **Step 2: 寫測試（包含全部四個 case）**

Write `test/services/window_state_keeper_test.dart`：

```dart
// test/services/window_state_keeper_test.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/window_state_keeper.dart';

void main() {
  group('computeDefaultWindowSize', () {
    test('橫向 1920×1080 → 1742×980 (16:9)', () {
      final size = computeDefaultWindowSize(const Size(1920, 1080));
      expect(size.width, closeTo(1742.22, 0.5));
      expect(size.height, 980);
    });

    test('直向 1080×1920 → 551×980 (9:16)', () {
      final size = computeDefaultWindowSize(const Size(1080, 1920));
      expect(size.width, closeTo(551.25, 0.5));
      expect(size.height, 980);
    });

    test('正方形 1000×1000 → 900×900 (扣 100 fallback)', () {
      final size = computeDefaultWindowSize(const Size(1000, 1000));
      expect(size.width, 900);
      expect(size.height, 900);
    });

    test('極端小螢幕 150×100 → fallback 800×450', () {
      final size = computeDefaultWindowSize(const Size(150, 100));
      expect(size.width, 800);
      expect(size.height, 450);
    });

    test('結果小於最小尺寸時 clamp 到 800×450', () {
      // workArea 200×201：橫向分支，height=101，width=101*16/9≈179
      // → 同時小於最小 (800, 450) → clamp
      final size = computeDefaultWindowSize(const Size(201, 200));
      expect(size.width, 800);
      expect(size.height, 450);
    });
  });
}
```

- [ ] **Step 3: 跑測試確認失敗**

Run（PowerShell）:
```powershell
flutter test test/services/window_state_keeper_test.dart
```

Expected: 編譯錯誤（`computeDefaultWindowSize` 未定義）。這是預期的失敗，**不要 commit**。

- [ ] **Step 4: 寫 minimal implementation**

在 `lib/services/window_state_keeper.dart` 末端追加：

```dart
@visibleForTesting
Size computeDefaultWindowSize(Size workArea, {double margin = _kMargin}) {
  final w = workArea.width;
  final h = workArea.height;

  // 極端小螢幕保護：未達 200dp 直接走 fallback
  if (w < 200 || h < 200) {
    return _kMinWindowSize;
  }

  late Size raw;
  if (w > h) {
    final height = h - margin;
    raw = Size(height * 16 / 9, height);
  } else if (h > w) {
    final width = (w - margin) * 9 / 16;
    raw = Size(width, width * 16 / 9);
  } else {
    raw = Size(w - margin, h - margin);
  }

  // 兩個維度都低於最小尺寸 → 視為螢幕太小，fallback 到 min。
  // 單一維度低於（例如 portrait 螢幕 9:16 寬度<800）則保留比例信任公式，
  // 由 setMinimumSize 在使用者拖拉時提供下限保護。
  if (raw.width < _kMinWindowSize.width &&
      raw.height < _kMinWindowSize.height) {
    return _kMinWindowSize;
  }
  return raw;
}
```

- [ ] **Step 5: 跑測試確認通過**

Run（PowerShell）:
```powershell
flutter test test/services/window_state_keeper_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: 品質檢查**

Run（PowerShell）:
```powershell
dart format lib/services/window_state_keeper.dart test/services/window_state_keeper_test.dart
flutter analyze
flutter test
```

Expected: format 不更動內容（或回 `Formatted N file(s)` 後再次跑無更動）；analyze 印 `No issues found!`；test 印 `All tests passed!`。

- [ ] **Step 7: Commit**

Run（PowerShell）:
```powershell
git add lib/services/window_state_keeper.dart test/services/window_state_keeper_test.dart
git commit -m "feat(services): add computeDefaultWindowSize formula"
```

---

### Task 3: TDD `resolveInitialBounds` 純函式

**Files:**
- Modify: `lib/services/window_state_keeper.dart`
- Modify: `test/services/window_state_keeper_test.dart`

- [ ] **Step 1: 在 test 檔追加 `resolveInitialBounds` 測試 group**

在 `test/services/window_state_keeper_test.dart` 的 `void main()` 內、`group('computeDefaultWindowSize', ...)` 之**後**追加：

```dart
  group('resolveInitialBounds', () {
    const primary = Rect.fromLTWH(0, 0, 1920, 1080);

    test('saved == null → 公式 + 居中 primary', () {
      final r = resolveInitialBounds(
        saved: null,
        displayVisibleRects: const [primary],
      );
      // 1920×1080 → window 1742×980；置中 → x≈89, y=50
      expect(r.width, closeTo(1742, 1));
      expect(r.height, 980);
      expect(r.left, closeTo(89, 1));
      expect(r.top, 50);
    });

    test('saved 完全在 primary 內 → 原樣回傳', () {
      const saved = Rect.fromLTWH(100, 100, 1280, 720);
      final r = resolveInitialBounds(
        saved: saved,
        displayVisibleRects: const [primary],
      );
      expect(r, saved);
    });

    test('saved 與螢幕重疊 < 30% → 公式 + 居中', () {
      // saved 大部分在 primary 外（模擬拔掉外接螢幕）
      const saved = Rect.fromLTWH(2500, 100, 1280, 720);
      final r = resolveInitialBounds(
        saved: saved,
        displayVisibleRects: const [primary],
      );
      expect(r.width, closeTo(1742, 1));
      expect(r.height, 980);
    });

    test('saved 與螢幕重疊 ≥ 30% → 原樣回傳', () {
      // saved Rect(1000, 100, 1280, 720)，與 primary 重疊面積 ≈ 920×720 = 662400
      // savedArea = 921600，ratio ≈ 0.72 > 0.3
      const saved = Rect.fromLTWH(1000, 100, 1280, 720);
      final r = resolveInitialBounds(
        saved: saved,
        displayVisibleRects: const [primary],
      );
      expect(r, saved);
    });

    test('saved 落在第二顯示器 → 原樣回傳', () {
      const secondary = Rect.fromLTWH(1920, 0, 1920, 1080);
      const saved = Rect.fromLTWH(2000, 100, 1280, 720);
      final r = resolveInitialBounds(
        saved: saved,
        displayVisibleRects: const [primary, secondary],
      );
      expect(r, saved);
    });

    test('displays 為空 → 用內建 fallback rect 公式 + 居中', () {
      final r = resolveInitialBounds(
        saved: null,
        displayVisibleRects: const [],
      );
      // fallback rect = 1280×720；公式：height=620, width=620*16/9≈1102
      expect(r.width, closeTo(1102, 1));
      expect(r.height, 620);
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run（PowerShell）:
```powershell
flutter test test/services/window_state_keeper_test.dart
```

Expected: 編譯錯誤（`resolveInitialBounds` 未定義）。

- [ ] **Step 3: 寫 minimal implementation**

在 `lib/services/window_state_keeper.dart` 的 `computeDefaultWindowSize` 函式之後追加：

```dart
@visibleForTesting
Rect resolveInitialBounds({
  required Rect? saved,
  required List<Rect> displayVisibleRects,
}) {
  final primary = displayVisibleRects.isNotEmpty
      ? displayVisibleRects.first
      : const Rect.fromLTWH(0, 0, 1280, 720);

  Rect formulaCentered() {
    final size = computeDefaultWindowSize(primary.size);
    final dx = primary.left + (primary.width - size.width) / 2;
    final dy = primary.top + (primary.height - size.height) / 2;
    return Rect.fromLTWH(dx, dy, size.width, size.height);
  }

  if (saved == null) return formulaCentered();

  final savedArea = saved.width * saved.height;
  if (savedArea <= 0) return formulaCentered();

  for (final d in displayVisibleRects) {
    final overlap = saved.intersect(d);
    if (overlap.isEmpty) continue;
    final overlapArea = overlap.width * overlap.height;
    if (overlapArea / savedArea >= 0.3) {
      return saved;
    }
  }
  return formulaCentered();
}
```

- [ ] **Step 4: 跑測試確認通過**

Run（PowerShell）:
```powershell
flutter test test/services/window_state_keeper_test.dart
```

Expected: 兩個 group 全部 `All tests passed!`。

- [ ] **Step 5: 品質檢查**

Run（PowerShell）:
```powershell
dart format lib/services/window_state_keeper.dart test/services/window_state_keeper_test.dart
flutter analyze
flutter test
```

Expected: 全部通過。

- [ ] **Step 6: Commit**

Run（PowerShell）:
```powershell
git add lib/services/window_state_keeper.dart test/services/window_state_keeper_test.dart
git commit -m "feat(services): add resolveInitialBounds with off-screen reset"
```

---

### Task 4: 新增 `WindowStateKeeper` 類別與 `bootstrap()`

無 unit test（涉及 `window_manager` plugin、`screen_retriever` plugin、Timer，需要 Windows runtime 才能驗證）。手動驗收放在 Task 6。

**Files:**
- Modify: `lib/services/window_state_keeper.dart`

- [ ] **Step 1: 加上類別**

在 `lib/services/window_state_keeper.dart` 的 `resolveInitialBounds` 函式之後追加：

```dart
class WindowStateKeeper with WindowListener {
  WindowStateKeeper._(this._prefs);

  static WindowStateKeeper? _instance;

  static const _kX = 'window.state.x';
  static const _kY = 'window.state.y';
  static const _kWidth = 'window.state.width';
  static const _kHeight = 'window.state.height';
  static const _kMaximized = 'window.state.isMaximized';
  static const _saveDebounce = Duration(milliseconds: 800);

  final SharedPreferences _prefs;
  Timer? _debounceTimer;

  /// 初始化視窗：讀取持久化狀態 → 解析初始 bounds → 套用 → 開始監聽。
  /// 呼叫端負責先 await `windowManager.ensureInitialized()`。
  static Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final keeper = WindowStateKeeper._(prefs);

    final saved = keeper._loadSaved();
    final wasMaximized = prefs.getBool(_kMaximized) ?? false;

    final displays = await screenRetriever.getAllDisplays();
    final visibleRects = displays.map((d) {
      final pos = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      return Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
    }).toList();

    final bounds = resolveInitialBounds(
      saved: saved,
      displayVisibleRects: visibleRects,
    );

    const opts = WindowOptions(skipTaskbar: false);
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.setMinimumSize(_kMinWindowSize);
      await windowManager.setBounds(bounds);
      if (wasMaximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(keeper);
    _instance = keeper;
  }

  Rect? _loadSaved() {
    final x = _prefs.getDouble(_kX);
    final y = _prefs.getDouble(_kY);
    final w = _prefs.getDouble(_kWidth);
    final h = _prefs.getDouble(_kHeight);
    if (x == null || y == null || w == null || h == null) return null;
    return Rect.fromLTWH(x, y, w, h);
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_saveDebounce, () => unawaited(_saveNow()));
  }

  Future<void> _saveNow() async {
    final isMax = await windowManager.isMaximized();
    await _prefs.setBool(_kMaximized, isMax);
    // 最大化時刻意不覆蓋 x/y/w/h，保留上次「非最大化」的值。
    if (!isMax) {
      final b = await windowManager.getBounds();
      await _prefs.setDouble(_kX, b.left);
      await _prefs.setDouble(_kY, b.top);
      await _prefs.setDouble(_kWidth, b.width);
      await _prefs.setDouble(_kHeight, b.height);
    }
  }

  @override
  void onWindowResize() => _scheduleSave();

  @override
  void onWindowMove() => _scheduleSave();

  @override
  void onWindowMaximize() {
    _debounceTimer?.cancel();
    unawaited(_saveNow());
  }

  @override
  void onWindowUnmaximize() {
    _debounceTimer?.cancel();
    unawaited(_saveNow());
  }

  @override
  void onWindowClose() async {
    _debounceTimer?.cancel();
    await _saveNow();
  }
}
```

- [ ] **Step 2: 品質檢查**

Run（PowerShell）:
```powershell
dart format lib/services/window_state_keeper.dart
flutter analyze
flutter test
```

Expected:
- format：無更動或會自動排版
- analyze：`No issues found!`
- test：`All tests passed!`（先前的兩個 group 仍應通過）

- [ ] **Step 3: Commit**

Run（PowerShell）:
```powershell
git add lib/services/window_state_keeper.dart
git commit -m "feat(services): add WindowStateKeeper with persistence and listener"
```

---

### Task 5: `main.dart` 接入 `WindowStateKeeper.bootstrap()`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 新增 imports**

在 `lib/main.dart` 既有 import 區塊（約檔頭 14 行附近，與其他 `package:genshin_impact_wish_gacha_analyzer/...` 並列），加入：

```dart
import 'package:window_manager/window_manager.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/window_state_keeper.dart';
```

- [ ] **Step 2: 在 `main()` 加入 bootstrap 呼叫**

修改 `lib/main.dart`，把：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  try {
    final cleaned = await rust_capture.cleanupStaleProxy();
```

改為：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await WindowStateKeeper.bootstrap();
  }

  try {
    final cleaned = await rust_capture.cleanupStaleProxy();
```

> 為什麼用 `Platform.isWindows` 守備：目前只有 `windows/` runner，但這個守備讓未來新增 macOS/Linux runner 時不會誤觸（YAGNI 但成本低）。`Platform` 來自 `dart:io`，已在現有 import 內。

- [ ] **Step 3: 品質檢查**

Run（PowerShell）:
```powershell
dart format lib/main.dart
flutter analyze
flutter test
```

Expected: 全部通過。

- [ ] **Step 4: Commit**

Run（PowerShell）:
```powershell
git add lib/main.dart
git commit -m "feat(window): bootstrap window sizing and state keeper on Windows"
```

---

### Task 6: 手動驗收（必須在 Windows 桌面執行）

無 commit。如發現問題，回到對應 Task 修正後重跑。

**前置：**
```powershell
flutter clean
flutter pub get
```

**清掉舊狀態：** Windows 上 `shared_preferences` 預設存在 `%LOCALAPPDATA%\<bundle>\shared_preferences.json` 或 Registry。最簡單做法：第一次驗收前在 Run dialog 開：
```
%APPDATA%\genshin_impact_wish_gacha_analyzer
```
刪掉（或改名備份）整個資料夾後再啟動，確保是「全新環境」。

> 註：Windows 上 `shared_preferences` 實際使用 Registry (`HKCU\Software\<package>`)，路徑視套件版本而異。最保險：用 Registry Editor 找 `HKEY_CURRENT_USER\Software` 下的專案 key 刪掉 `window.state.*` 五個值。或在程式內臨時加 `prefs.clear()`，跑一次後刪掉。

執行驗收：
```powershell
flutter run -d windows
```

- [ ] **驗收 1：全新環境 → 16:9 + 居中**

操作：刪掉 `window.state.*` 五個 prefs 後啟動。
預期：視窗以 1742×980（在 1920×1080 螢幕上）顯示，**居中**於主螢幕。

- [ ] **驗收 2：手動移動 / 縮放 → 重開還原**

操作：拖視窗到某位置、縮放到某尺寸 → 關閉 → 再次 `flutter run -d windows`。
預期：視窗以**完全相同**的位置與尺寸開啟。

- [ ] **驗收 3：最大化 → 重開仍最大化**

操作：最大化 → 關閉 → 重開。
預期：以最大化狀態開啟。

- [ ] **驗收 4：最大化前 bounds 被正確保留**

操作：手動縮成 1000×700 並擺在 (200, 200) → 最大化 → 關閉 → 重開（仍最大化） → 還原最大化 → 確認還原後是 1000×700 / (200, 200)。
預期：還原後尺寸與位置=最大化前的值，**不是**全螢幕尺寸。這是 spec 的「最大化時不覆蓋 bounds」策略生效驗證。

- [ ] **驗收 5：拔掉外接螢幕後重設居中**

操作：把視窗拖到外接螢幕的某位置 → 關閉 → 拔掉外接螢幕 → 重開。
預期：視窗以公式重算 + 居中於主螢幕（**不**出現在不存在的螢幕座標）。
（如無外接螢幕，可用 Registry Editor 把 `window.state.x` 改成 5000 模擬，以驗證 off-screen reset。）

- [ ] **驗收 6：縮到極小被擋住**

操作：嘗試把視窗縮到比 800×450 還小。
預期：縮放被 `setMinimumSize` 擋住，無法低於 800×450。

- [ ] **驗收 7：debounce 拖拉**

操作：連續快速拖拉 / 縮放視窗約 5 秒後停止 → 再過 1 秒關閉視窗 → 重開。
預期：位置與最後停止位置一致（debounce 在停止 800 ms 後存檔，close 也會 flush）。

- [ ] **驗收 8：跑一遍既有功能 sanity**

操作：登入 / 抓取祈願 / 切換主題與語言。
預期：無 regression（與 main 加入 `WindowStateKeeper.bootstrap()` 之前行為一致）。

---

### Task 7: 完工檢查

- [ ] **Step 1: 確認所有 commit 已就位**

Run（PowerShell）:
```powershell
git log --oneline master..HEAD
```

Expected（從新到舊）：
```
feat(window): bootstrap window sizing and state keeper on Windows
feat(services): add WindowStateKeeper with persistence and listener
feat(services): add resolveInitialBounds with off-screen reset
feat(services): add computeDefaultWindowSize formula
chore(deps): add window_manager and screen_retriever
```

- [ ] **Step 2: 最終全面檢查**

Run（PowerShell）:
```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全部通過。如 `dart format` 有更動，補一個 `style: apply dart format` commit。

- [ ] **Step 3: 通知使用者完工**

回報：
- 5 個 commit 已加入 `flutter-rewrite` 分支
- 8 項手動驗收結果（哪些通過、哪些有觀察到的問題）
- 提醒下一步：可進入 `superpowers:finishing-a-development-branch` skill 決定如何整合
