# Dialog 寬高上限統一：AppDialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 引入 `AppDialog` widget 統一所有 dialog 的寬高上限規則，並把現有 4 個 dialog 全部改用它。

**Architecture:** 新增 `lib/widgets/dialogs/app_dialog.dart` 提供 `AppDialog` widget 與 `AppDialogSize` enum（sm/md/lg → 480/640/720）。內部封裝 `width = min(size.maxWidth, mq.width - 80)`、`maxHeight = min(720, mq.height - 120)`、`scrollable` 開關。4 個既有 dialog (`confirm_dialog`、`update_progress_dialog`、`accounts_picker_dialog`、`new_version_dialog`) 全部移除自寫的 `math.min` + `ConstrainedBox` + `SizedBox` 樣板碼，改套 `AppDialog`。最後同步更新 `CLAUDE.md` / `AGENTS.md` 第 7 條。

**Tech Stack:** Flutter (Material 3)、Dart 3、`flutter_test`、`flutter_riverpod`。

**Spec reference:** `docs/superpowers/specs/2026-05-15-dialog-max-width-design.md`

**File map:**

| 動作       | 路徑                                                  | 責任                                    |
|----------|-----------------------------------------------------|---------------------------------------|
| Create   | `lib/widgets/dialogs/app_dialog.dart`               | `AppDialog` widget + `AppDialogSize` enum |
| Create   | `test/widgets/dialogs/app_dialog_test.dart`         | AppDialog 寬高與 scrollable 行為驗證          |
| Modify   | `lib/widgets/dialogs/confirm_dialog.dart`           | 改用 `AppDialog(size: sm)`               |
| Modify   | `lib/widgets/update_progress_dialog.dart`           | 改用 `AppDialog(size: sm)`，外層 PopScope 保留 |
| Modify   | `lib/widgets/dialogs/accounts_picker_dialog.dart`   | 改用 `AppDialog(size: md)`               |
| Modify   | `lib/widgets/dialogs/new_version_dialog.dart`       | 改用 `AppDialog(size: lg, scrollable: true)` |
| Modify   | `CLAUDE.md`                                         | 替換第 7 條 Dialog 高度上限 → AppDialog 規則     |
| Modify   | `AGENTS.md`                                         | 同上（兩份內容須一致）                            |

**重要提交前檢查（每次 commit 前必跑，從 CLAUDE.md）：**

1. `dart format lib/ test/`（**不要對 `.` 跑**）
2. `flutter analyze` — 必須 `No issues found!`
3. `flutter test` — 必須 `All tests passed!`

任一失敗先修，**不要用 `--no-verify` 跳過 hooks**。

---

## Task 1: 建立 `AppDialog` widget（TDD）

**Files:**
- Create: `lib/widgets/dialogs/app_dialog.dart`
- Create: `test/widgets/dialogs/app_dialog_test.dart`

- [ ] **Step 1.1: 先寫失敗測試**

寫到 `test/widgets/dialogs/app_dialog_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 統一在指定的視窗尺寸下開啟 dialog 並回傳 dialog 內 SizedBox 量到的寬。
Future<void> _pumpDialog(
  WidgetTester tester, {
  required Size surfaceSize,
  required AppDialogSize size,
  bool scrollable = false,
  Widget? content,
}) async {
  // Flutter 3.41+ 上 tester.binding.setSurfaceSize 不會反映到 MediaQuery.size，
  // 改用 tester.view.physicalSize + devicePixelRatio = 1.0。
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => AppDialog(
                  size: size,
                  scrollable: scrollable,
                  title: const Text('Title'),
                  content: content ?? const Text('Body'),
                  actions: [
                    TextButton(
                      onPressed: () {},
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// 從 dialog content 內部最外層 SizedBox 量寬。AppDialog 內部會包一層 SizedBox(width: ...)。
double _innerWidth(WidgetTester tester) {
  final sizedBox = find.descendant(
    of: find.byType(ConstrainedBox),
    matching: find.byType(SizedBox),
  );
  // 找到第一個有設 width 的 SizedBox
  final widths = tester
      .widgetList<SizedBox>(sizedBox)
      .where((s) => s.width != null)
      .map((s) => s.width!);
  return widths.first;
}

void main() {
  testWidgets('sm size uses 480 width in wide window', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.sm,
    );
    expect(_innerWidth(tester), 480);
  });

  testWidgets('md size uses 640 width in wide window', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.md,
    );
    expect(_innerWidth(tester), 640);
  });

  testWidgets('lg size uses 720 width in wide window', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.lg,
    );
    expect(_innerWidth(tester), 720);
  });

  testWidgets('narrow window falls back to mq.width - 80', (tester) async {
    // 視窗寬 400 → 所有 size 都應變成 320
    await _pumpDialog(
      tester,
      surfaceSize: const Size(400, 800),
      size: AppDialogSize.lg,
    );
    expect(_innerWidth(tester), 320);
  });

  testWidgets('maxHeight = min(720, mq.height - 120) — tall window', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 1080),
      size: AppDialogSize.md,
    );
    final cb = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(cb.constraints.maxHeight, 720);
  });

  testWidgets('maxHeight = min(720, mq.height - 120) — short window', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 600),
      size: AppDialogSize.md,
    );
    final cb = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(cb.constraints.maxHeight, 480);
  });

  testWidgets('scrollable: true wraps content in SingleChildScrollView', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.lg,
      scrollable: true,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('scrollable defaults to false — no SingleChildScrollView', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.sm,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('empty actions list → AlertDialog.actions is null', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => const AppDialog(
                    title: Text('Title'),
                    content: Text('Body'),
                    // 不傳 actions，使用預設空陣列
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.actions, isNull);
  });
}
```

- [ ] **Step 1.2: 跑測試確認失敗**

```powershell
flutter test test/widgets/dialogs/app_dialog_test.dart
```

Expected: 編譯錯誤 `Target of URI doesn't exist: 'package:.../app_dialog.dart'`（檔案還沒建）。

- [ ] **Step 1.3: 實作最小可行 AppDialog**

寫到 `lib/widgets/dialogs/app_dialog.dart`：

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dialog 寬度語意尺寸。
///
/// 三檔對應的最大內容寬：sm = 480、md = 640、lg = 720。
/// 視窗較窄時實際寬度會 fallback 到 `mq.size.width - 80`（扣掉 AlertDialog
/// 預設左右 insetPadding 40 * 2）。
enum AppDialogSize {
  sm,
  md,
  lg;

  double get maxWidth => switch (this) {
    AppDialogSize.sm => 480,
    AppDialogSize.md => 640,
    AppDialogSize.lg => 720,
  };
}

/// 專案統一使用的 dialog 容器。包裝 `AlertDialog` 並自動套寬高上限：
///
/// - 寬：`min(size.maxWidth, mq.size.width - 80)`
/// - 高：`min(720, mq.size.height - 120)`
///
/// 整體需要捲動時設 `scrollable: true`；內容已自帶捲動元件（`ListView` 等）
/// 維持預設 `false` 避免雙層捲動衝突。
///
/// 不要再自己手寫 `AlertDialog` + `ConstrainedBox` + `math.min(...)` — 用這個。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const <Widget>[],
    this.size = AppDialogSize.sm,
    this.scrollable = false,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final AppDialogSize size;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dialogWidth = math.min(size.maxWidth, mq.size.width - 80);
    final maxHeight = math.min(720.0, mq.size.height - 120);

    Widget body = SizedBox(width: dialogWidth, child: content);
    if (scrollable) {
      body = SingleChildScrollView(child: body);
    }

    return AlertDialog(
      constraints: BoxConstraints(maxHeight: maxHeight),
      title: title,
      content: body,
      actions: actions.isEmpty ? null : actions,
    );
  }
}
```

> 說明：maxHeight 透過 `AlertDialog.constraints` 套用於**整個 dialog**（title + content + actions），對應使用者規格表中的「視窗 1080 → 720（上限生效）」是整個 dialog 高度的上限。若改寫成 content 內包 `ConstrainedBox`，dialog 總高會被 title + actions 撐超過 720，與規格不符。

- [ ] **Step 1.4: 跑測試確認 pass**

```powershell
flutter test test/widgets/dialogs/app_dialog_test.dart
```

Expected: `All tests passed!`，9 個測試全 pass。

- [ ] **Step 1.5: 提交前品質檢查**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 三者皆通過（`No issues found!` + `All tests passed!`）。

- [ ] **Step 1.6: Commit**

```powershell
git add lib/widgets/dialogs/app_dialog.dart test/widgets/dialogs/app_dialog_test.dart
git commit -m "feat(dialogs): add AppDialog widget with sm/md/lg size enum"
```

---

## Task 2: 重構 `confirm_dialog.dart` → AppDialog (sm)

**Files:**
- Modify: `lib/widgets/dialogs/confirm_dialog.dart`

既有測試 `test/widgets/dialogs/confirm_dialog_test.dart` 必須重構後仍 pass，不修測試。

- [ ] **Step 2.1: 改寫 build()**

把 `lib/widgets/dialogs/confirm_dialog.dart` 內 `_ConfirmDialogState.build()` 整段替換。原本：

```dart
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final matches = _ctrl.text == widget.expectedText;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: AppSpacing.l),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close, size: 18),
          label: Text(widget.cancelLabel),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: tokens.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          icon: Icon(widget.confirmIcon, size: 18),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
```

改成：

```dart
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final matches = _ctrl.text == widget.expectedText;
    return AppDialog(
      // size 預設 sm，符合短訊息語意，不必顯式傳。
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: AppSpacing.l),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close, size: 18),
          label: Text(widget.cancelLabel),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: tokens.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          icon: Icon(widget.confirmIcon, size: 18),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
```

並把檔案頂部 `import` 加上：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
```

- [ ] **Step 2.2: 跑 confirm_dialog 測試**

```powershell
flutter test test/widgets/dialogs/confirm_dialog_test.dart
```

Expected: `All tests passed!`（3 個 testWidgets）。

- [ ] **Step 2.3: 提交前品質檢查**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 三者皆通過。

- [ ] **Step 2.4: Commit**

```powershell
git add lib/widgets/dialogs/confirm_dialog.dart
git commit -m "refactor(dialogs): migrate confirm dialog to AppDialog"
```

---

## Task 3: 重構 `update_progress_dialog.dart` → AppDialog (sm)

**Files:**
- Modify: `lib/widgets/update_progress_dialog.dart`

無專屬測試，靠 `flutter test` 整體與 `flutter analyze` 確認沒破。

- [ ] **Step 3.1: 改寫 build()**

把 `lib/widgets/update_progress_dialog.dart` 內 `UpdateProgressDialog.build()` 的 `AlertDialog` 換成 `AppDialog`，**外層 `PopScope` 保留**。原本：

```dart
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: _Title(progress: progress, l: l, tokens: tokens),
        content: _Body(progress: progress, l: l),
        actions: _actions(context, progress, notifier, l),
      ),
    );
```

改成：

```dart
    return PopScope(
      canPop: false,
      child: AppDialog(
        // size 預設 sm，符合短訊息 + LinearProgressIndicator 語意。
        title: _Title(progress: progress, l: l, tokens: tokens),
        content: _Body(progress: progress, l: l),
        actions: _actions(context, progress, notifier, l),
      ),
    );
```

檔案頂部 `import` 加上：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
```

備註：`_actions(...)` 在 `FetchingBanner()` / `null` 兩個 case 會回傳 `const <Widget>[]`，傳給 AppDialog 後它會把 AlertDialog 的 actions 設為 null（行為等價，Task 1 測試已驗證）。

- [ ] **Step 3.2: 提交前品質檢查**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 三者皆通過。

- [ ] **Step 3.3: Commit**

```powershell
git add lib/widgets/update_progress_dialog.dart
git commit -m "refactor(dialogs): migrate update progress dialog to AppDialog"
```

---

## Task 4: 重構 `accounts_picker_dialog.dart` → AppDialog (md)

**Files:**
- Modify: `lib/widgets/dialogs/accounts_picker_dialog.dart`

既有測試 `test/widgets/dialogs/accounts_picker_dialog_test.dart` 必須仍 pass，不修測試。

- [ ] **Step 4.1: 改寫 build()**

把 `lib/widgets/dialogs/accounts_picker_dialog.dart` 內 `_AccountsPickerDialogState.build()` 換掉。原本：

```dart
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mq = MediaQuery.of(context);
    // AlertDialog 預設左右 insetPadding 共 80,先扣掉再卡 480 上限,避免窄視窗撐爆。
    final dialogWidth = math.min(480.0, mq.size.width - 80);
    final maxHeight = mq.size.height * 0.6;

    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                tristate: true,
                value: _selectAllValue,
                title: Text(l.accountsPickerSelectAll),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                onChanged: (_) => _onSelectAllTap(),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = widget.entries[i];
                    return _PickerRow(
                      entry: e,
                      selected: _selected.contains(e.uid),
                      onChanged: (v) => _toggle(e.uid, v ?? false),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 18),
          label: Text(l.confirmCancel),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final ordered = [
                    for (final e in widget.entries)
                      if (_selected.contains(e.uid)) e.uid,
                  ];
                  Navigator.of(context).pop(ordered);
                },
          icon: const Icon(Icons.check, size: 18),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
```

改成（注意：`AppDialog` 改用 `md` 而非原本的 480，依 spec 升級為 640；內部已自帶 ListView 捲動，scrollable 維持預設 false）：

```dart
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      size: AppDialogSize.md,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            tristate: true,
            value: _selectAllValue,
            title: Text(l.accountsPickerSelectAll),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            onChanged: (_) => _onSelectAllTap(),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = widget.entries[i];
                return _PickerRow(
                  entry: e,
                  selected: _selected.contains(e.uid),
                  onChanged: (v) => _toggle(e.uid, v ?? false),
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 18),
          label: Text(l.confirmCancel),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final ordered = [
                    for (final e in widget.entries)
                      if (_selected.contains(e.uid)) e.uid,
                  ];
                  Navigator.of(context).pop(ordered);
                },
          icon: const Icon(Icons.check, size: 18),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
```

並做以下 import 調整：

- **加上**：`import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';`
- **移除**：`import 'dart:math' as math;`（已不再使用）

- [ ] **Step 4.2: 跑 accounts_picker_dialog 測試**

```powershell
flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart
```

Expected: `All tests passed!`（12 個 testWidgets）。

- [ ] **Step 4.3: 提交前品質檢查**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 三者皆通過。

- [ ] **Step 4.4: Commit**

```powershell
git add lib/widgets/dialogs/accounts_picker_dialog.dart
git commit -m "refactor(dialogs): migrate accounts picker to AppDialog"
```

---

## Task 5: 重構 `new_version_dialog.dart` → AppDialog (lg, scrollable: true)

**Files:**
- Modify: `lib/widgets/dialogs/new_version_dialog.dart`

無專屬測試，靠 `flutter test` 整體與 `flutter analyze`。

- [ ] **Step 5.1: 改寫 build()**

把 `lib/widgets/dialogs/new_version_dialog.dart` 內 `NewVersionDialog.build()` 換掉。原本：

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final latest = releases.first;
    final mq = MediaQuery.of(context);
    // AlertDialog 預設左右 insetPadding 共 80,先扣掉再卡 720 上限,避免窄視窗撐爆。
    final dialogWidth = math.min(720.0, mq.size.width - 80);
    final maxHeight = mq.size.height * 0.6;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: tokens.stateSuccess),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.updateTitle(latest.tagName))),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < releases.length; i++) ...[
                  _ReleaseCard(release: releases[i], l: l),
                  if (i < releases.length - 1)
                    const SizedBox(height: AppSpacing.m),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref
                .read(appReleaseProvider.notifier)
                .skipVersion(latest.tagName);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(l.updateButtonSkip),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.updateButtonLater),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: Text(l.updateButtonDownload),
          onPressed: () async {
            await openExternalUrl(Uri.parse(latest.htmlUrl));
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
```

改成（注意：原本內層 `SingleChildScrollView` 移除，改靠 AppDialog 的 `scrollable: true`）：

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final latest = releases.first;

    return AppDialog(
      size: AppDialogSize.lg,
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.system_update, color: tokens.stateSuccess),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.updateTitle(latest.tagName))),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < releases.length; i++) ...[
            _ReleaseCard(release: releases[i], l: l),
            if (i < releases.length - 1)
              const SizedBox(height: AppSpacing.m),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref
                .read(appReleaseProvider.notifier)
                .skipVersion(latest.tagName);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(l.updateButtonSkip),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.updateButtonLater),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: Text(l.updateButtonDownload),
          onPressed: () async {
            await openExternalUrl(Uri.parse(latest.htmlUrl));
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
```

並做以下 import 調整：

- **加上**：`import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';`
- **移除**：`import 'dart:math' as math;`（已不再使用）

- [ ] **Step 5.2: 提交前品質檢查**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 三者皆通過。

- [ ] **Step 5.3: Commit**

```powershell
git add lib/widgets/dialogs/new_version_dialog.dart
git commit -m "refactor(dialogs): migrate new version dialog to AppDialog"
```

---

## Task 6: 更新 `CLAUDE.md` 與 `AGENTS.md`

**Files:**
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`

`CLAUDE.md` 與 `AGENTS.md` 兩份目前完全一致，更新後也必須完全一致。

- [ ] **Step 6.1: 替換 `CLAUDE.md` 第 7 條**

用 Edit 工具，把 `CLAUDE.md` 內這一行：

```markdown
- **Dialog 高度上限**：`AlertDialog` 內容可能很長時，content 外面包一層 `ConstrainedBox(maxHeight: MediaQuery.of(context).size.height * 0.6)` 並讓內部自行滾動，避免吃滿整個視窗。
```

換成：

```markdown
- **Dialog 一律用 `AppDialog`**：新建 dialog 一律使用 `AppDialog`（`lib/widgets/dialogs/app_dialog.dart`），透過 `size: AppDialogSize.sm/md/lg`（480 / 640 / 720）指定最大寬度。內部自動套寬高上限（width = `min(size.maxWidth, mq.width - 80)`，height = `min(720, mq.height - 120)`），低視窗下也不會被卡死。整體需要捲動時加 `scrollable: true`；內容已自帶捲動元件（`ListView` 等）維持預設 `false`。**不要再自己手寫 `AlertDialog` + `ConstrainedBox` + `math.min(...)`**。
```

- [ ] **Step 6.2: 套同樣替換到 `AGENTS.md`**

對 `AGENTS.md` 做完全相同的 Edit（兩份內容必須保持一致）。

- [ ] **Step 6.3: 驗證兩份一致**

```powershell
fc CLAUDE.md AGENTS.md
```

Expected: `FC: no differences encountered`（或 PowerShell 等價輸出）。

- [ ] **Step 6.4: 提交前品質檢查**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 三者皆通過（雖然只改 md，但規則照跑）。

- [ ] **Step 6.5: Commit**

```powershell
git add CLAUDE.md AGENTS.md
git commit -m "docs: document AppDialog rule replacing dialog height-cap guidance"
```

---

## Task 7: 最終全綠驗證

**Files:** 無（純驗證）

- [ ] **Step 7.1: 全域 format + analyze + test**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected:
- `dart format` 無檔案被改（前面 Task 已經 format 過）
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`

如果 `dart format` 動到任何檔案，那是前面 task 漏跑，補一個 commit 修正。

- [ ] **Step 7.2: 確認 git status 乾淨**

```powershell
git status
```

Expected: `nothing to commit, working tree clean`。

- [ ] **Step 7.3: Manual smoke test（重要 — 4 個 dialog 都跑一遍）**

啟動 debug build：

```powershell
flutter run -d windows
```

在 app 內各觸發一次：

1. **`confirm_dialog`** — 設定頁 → 帳號管理 → 任選一個「清空 / 匯入覆蓋」流程，確認 dialog 出現、寬度看起來合理、TextField 可輸入、確認/取消按鈕正常。
2. **`update_progress_dialog`** — 觸發一次抓卡記錄更新（任何 banner），觀察進度 dialog 出現、寬度合理、各狀態切換正常。
3. **`accounts_picker_dialog`** — 設定頁 → 匯出帳號，確認多帳號 picker 出現、寬度為 md (640)、checkbox 全選/單選正常、按確認回到原頁。
4. **`new_version_dialog`** — 若不便觸發真實流程，可暫時把 `state/app_release.dart` 內判斷強制成 `ReleaseAvailable` 看 dialog 樣式，看完還原。或留待自然出現時觀察。

如 dialog 在窄視窗有 layout 異常（例如 700px 寬視窗），觀察是否 fallback 為 `width - 80` 看起來正常。

`flutter run` 後手動關掉視窗結束 debug build。

---

## Self-Review 檢查

**1. Spec 覆蓋掃描：**

| Spec 段落                                       | 實作於          |
|-----------------------------------------------|--------------|
| 新增 `AppDialog` widget + `AppDialogSize` enum  | Task 1       |
| `AppDialog` 測試（三尺寸、窄視窗 fallback、maxHeight、scrollable） | Task 1.1 測試  |
| confirm_dialog → `sm`, scrollable false       | Task 2       |
| update_progress_dialog → `sm`, scrollable false, PopScope 保留 | Task 3       |
| accounts_picker_dialog → `md`, scrollable false | Task 4       |
| new_version_dialog → `lg`, scrollable true    | Task 5       |
| 移除 `accounts_picker_dialog` / `new_version_dialog` 的 `import 'dart:math' as math;` | Task 4.1 / 5.1 |
| `CLAUDE.md` 第 7 條替換                            | Task 6.1     |
| `AGENTS.md` 第 7 條替換（內容須一致）                     | Task 6.2     |
| 風險緩解：manual smoke 4 個 dialog                   | Task 7.3     |

無缺漏。

**2. Placeholder 掃描：** 無 TBD / TODO / 「適當處理」等模糊字眼。所有 code block 為完整可貼可跑的內容。

**3. 型別一致性：** `AppDialogSize.sm/md/lg`、`AppDialog(title, content, actions, size, scrollable)`、`maxWidth getter` — Task 1 定義後 Task 2-5 引用完全一致。

無問題。
