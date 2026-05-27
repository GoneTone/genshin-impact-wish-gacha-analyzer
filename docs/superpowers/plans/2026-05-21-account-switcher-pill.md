# 帳號切換鈕改為外框膠囊 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 AppBar 右上帳號切換觸發鈕改為與「更新資料」按鈕同高 (40dp)、同樣 `StadiumBorder` 橢圓形的外框膠囊（透明底 + 邊框）。

**Architecture:** 將觸發鈕抽成無 provider 依賴的 public 小元件 `AccountTriggerButton`（標準 M3 `OutlinedButton`，可獨立 widget test）；`UidIndicator` 改為組合該元件並在 `onPressed` 內以 `showMenu()` 彈出現有的 `PopupMenuEntry` 清單，菜單內容不動。

**Tech Stack:** Flutter (Material 3)、Riverpod、`flutter_test`、現有 `AccountTriggerLabel` / `AccountMenuLabel` 子元件。

設計依據：`docs/superpowers/specs/2026-05-21-account-switcher-pill-design.md`

---

## File Structure

- `lib/widgets/uid_indicator.dart`（修改）
  - 新增 public 元件 `AccountTriggerButton`：外框膠囊觸發鈕，內容為 `AccountTriggerLabel`，無 provider 依賴。
  - `UidIndicator`：改用 `AccountTriggerButton`，`onPressed` 內計算 `RelativeRect` 並 `showMenu()`；保留原 `onSelected` 分支與菜單項建構。
- `test/widgets/uid_indicator_test.dart`（修改）
  - 新增 `AccountTriggerButton` 群組測試。既有 `AccountTriggerLabel` / `AccountMenuLabel` 測試不動。

---

### Task 1: 抽出 `AccountTriggerButton` 外框膠囊元件

**Files:**
- Modify: `lib/widgets/uid_indicator.dart`
- Test: `test/widgets/uid_indicator_test.dart`

- [ ] **Step 1: 寫失敗測試**

在 `test/widgets/uid_indicator_test.dart` 的 `main()` 內、現有 `group('AccountTriggerLabel', ...)` 之後新增：

```dart
  group('AccountTriggerButton', () {
    testWidgets('渲染 OutlinedButton 且形狀為 StadiumBorder（橢圓）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AccountTriggerButton(
            tooltip: 'switch',
            onPressed: () {},
            child: const AccountTriggerLabel(activeUid: '123456789', alias: null),
          ),
        ),
      );

      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final shape = button.style!.shape!.resolve(<WidgetState>{});
      expect(shape, isA<StadiumBorder>());
    });

    testWidgets('點擊觸發 onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          AccountTriggerButton(
            tooltip: 'switch',
            onPressed: () => tapped = true,
            child: const AccountTriggerLabel(activeUid: '123456789', alias: null),
          ),
        ),
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('內含傳入的 child 內容（UID 文字）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AccountTriggerButton(
            tooltip: 'switch',
            onPressed: () {},
            child: const AccountTriggerLabel(activeUid: '987654321', alias: null),
          ),
        ),
      );
      expect(find.text('987654321'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/uid_indicator_test.dart`
Expected: FAIL —「The name 'AccountTriggerButton' isn't defined」之類的編譯錯誤。

- [ ] **Step 3: 實作 `AccountTriggerButton`**

在 `lib/widgets/uid_indicator.dart` 檔尾新增（緊接 `AccountTriggerLabel` 之後，`AccountMenuLabel` 之前或之後皆可）：

```dart
/// AppBar 上的帳號切換觸發鈕：外框膠囊（透明底 + 邊框、StadiumBorder），
/// 高度與並排的「更新資料」FilledButton 一致（M3 預設 40dp）。
///
/// 不依賴任何 provider，純呈現；點擊行為由 [onPressed] 注入，
/// 可獨立進行 widget test。
class AccountTriggerButton extends StatelessWidget {
  /// 建立 [AccountTriggerButton]。
  const AccountTriggerButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.tooltip,
  });

  /// 膠囊內顯示的內容（通常為 [AccountTriggerLabel]）。
  final Widget child;

  /// 點擊回呼，用於彈出帳號選單。
  final VoidCallback onPressed;

  /// 滑鼠停留提示文字。
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: tokens.borderEmphasis),
          foregroundColor: tokens.textPrimary,
        ),
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/widgets/uid_indicator_test.dart`
Expected: PASS（含既有 `AccountTriggerLabel` / `AccountMenuLabel` 測試）。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/uid_indicator.dart test/widgets/uid_indicator_test.dart
git commit -m "feat(uid): add AccountTriggerButton outlined pill widget"
```

---

### Task 2: `UidIndicator` 改用膠囊觸發鈕 + `showMenu()`

**Files:**
- Modify: `lib/widgets/uid_indicator.dart`（`UidIndicator.build`，目前 31-85 行）

- [ ] **Step 1: 加入 import**

在 `lib/widgets/uid_indicator.dart` 頂部 import 區補上（與現有 import 風格一致，置於 `package:` 群組）：

```dart
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
```

> `logging` 套件名與既有用法一致（見 `lib/widgets/app_link.dart` 的 `Logger('ui.link')`）。`sanitizeUid` 來自 `lib/services/log_sanitize.dart`，簽名為 `String sanitizeUid(String uid)`。

- [ ] **Step 2: 改寫 `UidIndicator.build` 的 return**

把目前的 `return PopupMenuButton<String>( ... );`（31-85 行）整段替換為：建構菜單項清單、回傳 `AccountTriggerButton`、在 `onPressed` 內 `showMenu()` 並處理結果。將 `build` 內 `return` 之前的變數宣告（`state` / `settings` / `notifier` / `activeUid` / `l` / `orderedUids`）保留不動，僅替換 `return`：

```dart
    final menuItems = <PopupMenuEntry<String>>[
      for (final uid in orderedUids)
        PopupMenuItem<String>(
          value: uid,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                uid == activeUid ? Icons.check : Icons.radio_button_unchecked,
                size: 16,
                color: uid == activeUid
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: AccountMenuLabel(
                  uid: uid,
                  alias: settings.uidAliases[uid],
                  isActive: uid == activeUid,
                ),
              ),
            ],
          ),
        ),
      if (orderedUids.isNotEmpty) const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: '__recapture__',
        child: Row(
          children: [
            const Icon(Icons.person_add_alt, size: 16),
            const SizedBox(width: AppSpacing.s),
            Text(l.accountAdd),
          ],
        ),
      ),
    ];

    return AccountTriggerButton(
      tooltip: l.uidSwitchTooltip,
      onPressed: () async {
        final button = context.findRenderObject() as RenderBox;
        final overlay = Navigator.of(context).overlay!.context
            .findRenderObject() as RenderBox;
        final position = RelativeRect.fromRect(
          Rect.fromPoints(
            button.localToGlobal(Offset.zero, ancestor: overlay),
            button.localToGlobal(
              button.size.bottomRight(Offset.zero),
              ancestor: overlay,
            ),
          ),
          Offset.zero & overlay.size,
        );

        final key = await showMenu<String>(
          context: context,
          position: position,
          items: menuItems,
        );
        if (key == null) return;

        if (key == '__recapture__') {
          Logger('ui.account').info('account add / recapture triggered');
          await notifier.forceRecaptureAndUpdate();
        } else {
          Logger('ui.account').info('switch active uid -> ${sanitizeUid(key)}');
          await notifier.setActiveUid(key);
        }
      },
      child: AccountTriggerLabel(
        activeUid: activeUid,
        alias: activeUid == null ? null : settings.uidAliases[activeUid],
      ),
    );
```

> 註：`AccountTriggerLabel` 內已含 `arrow_drop_down` 箭頭與 alias `maxWidth 160` + ellipsis，不需額外處理。原 `AccountTriggerLabel` 外層的 `Padding(horizontal: AppSpacing.m)` 移除——`OutlinedButton` 自帶內距，交由 M3 預設以與更新鈕一致。

- [ ] **Step 3: 跑靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`（若有未使用 import 或型別錯誤先修）。

- [ ] **Step 4: 跑全套測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: 手動驗收（依設計文件驗收清單）**

依設計文件「驗收」一節，跑 app 目視確認：

```bash
flutter run -d windows
```

逐項確認：
- 帳號鈕與更新鈕**等高**、皆橢圓形；帳號鈕外框透明底、更新鈕 primary 實心。
- 點擊帳號鈕漣漪裁切於膠囊內、不溢出兩端。
- 彈出選單在按鈕下方，切換帳號 / 新增帳號功能正常。
- 切換主題（light / dark）邊框與文字對比皆清楚。
- 縮窄視窗時 alias 仍 ellipsis、不溢出邊界。

- [ ] **Step 6: 格式化**

Run: `dart format lib/ test/`
Expected: 顯示已格式化或無變更。

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/uid_indicator.dart
git commit -m "feat(uid): switch account trigger to outlined pill via showMenu"
```

---

## Self-Review

**Spec coverage：**
- 同高 40dp + StadiumBorder 橢圓 → Task 1 `AccountTriggerButton`（OutlinedButton M3 預設高度 + StadiumBorder），測試覆蓋形狀。✅
- 外框透明底 + 邊框 → Task 1 `OutlinedButton.styleFrom(side:..., shape: StadiumBorder)`。✅
- 漣漪裁切於膠囊 → OutlinedButton 內建 ink 裁切（手動驗收 Task 2 Step 5）。✅
- 沿用 `AccountTriggerLabel`（圖示/箭頭/alias ellipsis）→ Task 2 child。✅
- 菜單內容不動 → Task 2 menuItems 與原 itemBuilder 等價。✅
- `showMenu` + RelativeRect → Task 2 Step 2。✅
- onSelected 分支（recapture / setActiveUid）→ Task 2 Step 2。✅
- tooltip 沿用 `l.uidSwitchTooltip` → Task 1 `Tooltip` + Task 2 傳入。✅
- log（ui.account、sanitizeUid）→ Task 2 Step 1-2。✅
- 邊框色擇一 → 採用 `tokens.borderEmphasis`（spec 允許 outline / borderEmphasis 擇一）。✅
- analyze / test 綠 → Task 2 Step 3-4。✅

**Placeholder scan：** 無 TBD / TODO / 「add error handling」類佔位；每個程式步驟皆附完整程式碼。✅

**Type consistency：** `AccountTriggerButton({child, onPressed, tooltip})` 在 Task 1 定義、Task 2 以相同三參數呼叫；`sanitizeUid(String)`、`Logger('ui.account')`、`notifier.setActiveUid` / `forceRecaptureAndUpdate` 皆對齊既有簽名。✅
