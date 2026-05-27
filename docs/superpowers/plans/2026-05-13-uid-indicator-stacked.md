# UID Indicator Stacked Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把切換帳號下拉(`UidIndicator`)的觸發鈕與選單項目的「alias (uid)」單行格式改成「alias 主標 + UID 副標」上下兩行,並在 alias 過長時用 ellipsis 截字,避免撐爆 AppBar 與選單寬度。

**Architecture:** 把選單項目顯示與觸發鈕顯示抽成兩個獨立 `StatelessWidget`(`AccountMenuLabel` / `AccountTriggerLabel`),保留在 `lib/widgets/uid_indicator.dart` 內,方便 widget test。原 `UidIndicator` 只負責 provider wiring 與選單組裝,顯示細節下放到抽出的 widget。

**Tech Stack:** Flutter (Material 3), Riverpod, `flutter_test`, AppLocalizations。

**Spec:** `docs/superpowers/specs/2026-05-13-uid-indicator-stacked-design.md`

---

## File Structure

- **Modify:** `lib/widgets/uid_indicator.dart` — 新增兩個 widget class,改寫 `PopupMenuButton` 內部與觸發鈕,刪除舊的 `displayName` 局部函式。
- **Create:** `test/widgets/uid_indicator_test.dart` — 兩個 widget class 的 widget 測試。

`UidIndicator` 本身與 `wishRepositoryProvider` / `settingsProvider` 耦合,直接測試成本高;改抽 widget 後可只測 props-driven 的 `AccountMenuLabel` / `AccountTriggerLabel`,不需 provider override。

---

### Task 1: 新增 `AccountMenuLabel` widget + 測試

選單項目的兩行版面(alias 主標 + UID 副標,fallback 為單行 UID)。

**Files:**
- Create: `test/widgets/uid_indicator_test.dart`
- Modify: `lib/widgets/uid_indicator.dart` (新增 class,不動既有 `UidIndicator`)

- [ ] **Step 1: 建立測試檔,寫 4 個 `AccountMenuLabel` failing test**

完整檔案內容(新檔):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh', 'Hant'),
  theme: buildDarkTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AccountMenuLabel', () {
    testWidgets('有 alias:渲染 alias 主標 + UID 副標', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountMenuLabel(
          uid: '123456789',
          alias: 'MainAcc',
          isActive: false,
        )),
      );
      expect(find.text('MainAcc'), findsOneWidget);
      expect(find.text('123456789'), findsOneWidget);
    });

    testWidgets('無 alias:只渲染 UID 主標(沒有副標)', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountMenuLabel(
          uid: '987654321',
          alias: null,
          isActive: false,
        )),
      );
      // UID 只出現一次(主標),沒有第二次的副標 Text
      expect(find.text('987654321'), findsOneWidget);
    });

    testWidgets('isActive=true:接「（活躍）」suffix', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountMenuLabel(
          uid: '123456789',
          alias: 'MainAcc',
          isActive: true,
        )),
      );
      expect(find.text('（活躍）'), findsOneWidget);
    });

    testWidgets('alias 主標 Text:overflow=ellipsis、maxLines=1', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountMenuLabel(
          uid: '123456789',
          alias: 'VeryLongAliasName',
          isActive: false,
        )),
      );
      final aliasText = tester.widget<Text>(find.text('VeryLongAliasName'));
      expect(aliasText.overflow, TextOverflow.ellipsis);
      expect(aliasText.maxLines, 1);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認 4 個 fail(class 不存在)**

```
flutter test test/widgets/uid_indicator_test.dart
```

預期:測試編譯失敗,訊息類似 `Undefined name 'AccountMenuLabel'`。

- [ ] **Step 3: 在 `lib/widgets/uid_indicator.dart` 加入 `AccountMenuLabel` class**

在檔案結尾(現有 `UidIndicator` class 之後)加入:

```dart
/// 選單項目顯示:alias 主標 + UID 副標。沒 alias 時退化為 UID 單行。
class AccountMenuLabel extends StatelessWidget {
  const AccountMenuLabel({
    super.key,
    required this.uid,
    required this.isActive,
    this.alias,
  });

  final String uid;
  final String? alias;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final l = AppLocalizations.of(context)!;
    final hasAlias = alias != null && alias!.isNotEmpty;
    final primary = hasAlias ? alias! : uid;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Text(
                  l.uidActiveSuffix,
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
            ],
          ),
          if (hasAlias)
            Text(
              uid,
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 跑測試確認 4 個 pass**

```
flutter test test/widgets/uid_indicator_test.dart
```

預期:`All tests passed!`(4 個 group `AccountMenuLabel` 測試)。

- [ ] **Step 5: 跑品質檢查 + 提交**

依 `CLAUDE.md` 規則,提交前依序:

```
dart format lib/widgets/uid_indicator.dart test/widgets/uid_indicator_test.dart
flutter analyze
flutter test
```

每一步都要通過(`flutter analyze` → `No issues found!`、`flutter test` → `All tests passed!`)。然後:

```
git add lib/widgets/uid_indicator.dart test/widgets/uid_indicator_test.dart
git commit -m "refactor(uid-indicator): introduce AccountMenuLabel widget"
```

> 不要 `git add` `docs/superpowers/` 下的任何檔案(`docs/superpowers/` 不進版控,依使用者偏好)。

---

### Task 2: 新增 `AccountTriggerLabel` widget + 測試

AppBar 觸發鈕的單行顯示(`alias (uid)`,alias 部分 ellipsis;無 alias 顯示 UID;`activeUid == null` 顯示「未同步」)。

**Files:**
- Modify: `lib/widgets/uid_indicator.dart` (新增第二個 class)
- Modify: `test/widgets/uid_indicator_test.dart` (新增第二個 group)

- [ ] **Step 1: 在測試檔尾加入 `AccountTriggerLabel` 的 failing test group**

在 `test/widgets/uid_indicator_test.dart` 的 `void main() { ... }` 內,接在第一個 `group(...)` 之後新增:

```dart
  group('AccountTriggerLabel', () {
    testWidgets('activeUid=null:顯示「未同步」', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountTriggerLabel(activeUid: null, alias: null)),
      );
      expect(find.text('未同步'), findsOneWidget);
    });

    testWidgets('有 alias:顯示 alias + 完整 UID', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountTriggerLabel(activeUid: '123456789', alias: 'MainAcc')),
      );
      expect(find.text('MainAcc'), findsOneWidget);
      // UID 用 " (123456789)" 形式接在 alias 後
      expect(find.text(' (123456789)'), findsOneWidget);
    });

    testWidgets('無 alias:只顯示 UID', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountTriggerLabel(activeUid: '987654321', alias: null)),
      );
      expect(find.text('987654321'), findsOneWidget);
    });

    testWidgets('alias Text:overflow=ellipsis、maxLines=1', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountTriggerLabel(
          activeUid: '123456789',
          alias: 'VeryLongAliasName',
        )),
      );
      final aliasText = tester.widget<Text>(find.text('VeryLongAliasName'));
      expect(aliasText.overflow, TextOverflow.ellipsis);
      expect(aliasText.maxLines, 1);
    });
  });
```

- [ ] **Step 2: 跑測試確認新增 4 個 fail**

```
flutter test test/widgets/uid_indicator_test.dart
```

預期:第二個 group 的 4 個測試編譯失敗(`Undefined name 'AccountTriggerLabel'`),第一個 group 仍 pass。

- [ ] **Step 3: 在 `lib/widgets/uid_indicator.dart` 加入 `AccountTriggerLabel` class**

在 `AccountMenuLabel` class 之後加入:

```dart
/// AppBar 觸發鈕的單行顯示:alias (uid),alias 過長 ellipsis;
/// 無 alias 顯示 UID;activeUid==null 顯示「未同步」。
class AccountTriggerLabel extends StatelessWidget {
  const AccountTriggerLabel({super.key, this.activeUid, this.alias});

  final String? activeUid;
  final String? alias;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final uid = activeUid;
    if (uid == null) {
      return _row([
        const Icon(Icons.person_outline, size: 18),
        const SizedBox(width: AppSpacing.xs),
        Text(l.uidNotSynced),
        const Icon(Icons.arrow_drop_down, size: 18),
      ]);
    }
    final hasAlias = alias != null && alias!.isNotEmpty;
    return _row([
      const Icon(Icons.person_outline, size: 18),
      const SizedBox(width: AppSpacing.xs),
      if (hasAlias) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            alias!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(' ($uid)'),
      ] else
        Text(uid),
      const Icon(Icons.arrow_drop_down, size: 18),
    ]);
  }

  Widget _row(List<Widget> children) => Row(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}
```

> 註:spec 寫整體 trigger maxWidth ≈ 220px,扣掉 icon(18)+space(4)+`▾`(18)+`" (uid)"`(~60)+padding,留給 alias 約 160px。直接限制 alias 內部 ConstrainedBox 與 spec 等價,且不需在外層再加一層 ConstrainedBox。

- [ ] **Step 4: 跑測試確認新增 4 個 pass**

```
flutter test test/widgets/uid_indicator_test.dart
```

預期:`All tests passed!`(共 8 個 widget 測試)。

- [ ] **Step 5: 跑品質檢查 + 提交**

```
dart format lib/widgets/uid_indicator.dart test/widgets/uid_indicator_test.dart
flutter analyze
flutter test
```

全部通過後:

```
git add lib/widgets/uid_indicator.dart test/widgets/uid_indicator_test.dart
git commit -m "refactor(uid-indicator): introduce AccountTriggerLabel widget"
```

---

### Task 3: 把 `PopupMenuButton` 與觸發鈕接上抽出的 widget

刪除舊的 `displayName` 局部函式,改用 `AccountMenuLabel` / `AccountTriggerLabel`,完成版面切換。

**Files:**
- Modify: `lib/widgets/uid_indicator.dart` (改寫 `UidIndicator.build` 內部)

- [ ] **Step 1: 改寫 `UidIndicator.build`**

把 `lib/widgets/uid_indicator.dart` 內現有的 `UidIndicator.build` 方法(目前在 line 14-95)整段替換成:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wishRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final activeUid = state.activeUid;
    final l = AppLocalizations.of(context)!;

    final orderedUids = state.byUid.isEmpty
        ? const <String>[]
        : mergeUidOrder(
            knownUids: state.byUid.keys,
            customOrder: settings.uidOrder,
            lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
          );

    return PopupMenuButton<String>(
      tooltip: l.uidSwitchTooltip,
      onSelected: (key) async {
        if (key == '__recapture__') {
          await notifier.forceRecaptureAndUpdate();
        } else {
          await notifier.setActiveUid(key);
        }
      },
      itemBuilder: (context) => [
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
                AccountMenuLabel(
                  uid: uid,
                  alias: settings.uidAliases[uid],
                  isActive: uid == activeUid,
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
              Text(l.uidRecapture),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        child: AccountTriggerLabel(
          activeUid: activeUid,
          alias: activeUid == null ? null : settings.uidAliases[activeUid],
        ),
      ),
    );
  }
```

注意:
- `displayName` 局部函式已不再使用,連同它一起被移除(上面整段替換已經不包含它)。
- 「（活躍）」suffix 的渲染現在由 `AccountMenuLabel` 內部處理,不再寫在 `itemBuilder` 裡。
- `PopupMenuItem` 的 Row 加上 `crossAxisAlignment: CrossAxisAlignment.center`,讓 icon 在兩行內容下置中。
- 觸發鈕的 `Icon(Icons.person_outline)` + `Icon(Icons.arrow_drop_down)` 已搬進 `AccountTriggerLabel`,所以 `Padding` 的 child 直接是它。

- [ ] **Step 2: 確認 import 沒缺(`tokens.dart` 仍需要嗎?)**

替換後 `UidIndicator.build` 不再直接用 `Theme.of(context).gacha`,但 `AccountMenuLabel` 仍用,因此 `tokens.dart` import 留著即可。檢視檔案 import 區塊,確保以下都存在:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
```

- [ ] **Step 3: 跑全部品質檢查**

```
dart format lib/ test/
flutter analyze
flutter test
```

預期:
- `dart format`:輸出格式化結果(通常 0 或 2 個 changed file)。
- `flutter analyze`:`No issues found!`。
- `flutter test`:`All tests passed!`(現有 8 個 `uid_indicator_test` + 全專案其他測試)。

如有 analyze warning(例如 `displayName` unused 殘留),回到 Step 1 確認整段替換確實移除了該函式。

- [ ] **Step 4: 手動視覺驗證(Windows release)**

依 `feedback_perf_check_release_first.md` 的精神,UI 改動先跑 release 對照(避免 debug overlay 干擾觀感):

```
flutter run -d windows --release
```

驗收清單:
- [ ] 開 AppBar 帳號下拉:選單裡每個有別名的帳號顯示兩行(alias 主標 + UID 副標 muted),無別名只顯示一行 UID。
- [ ] 活躍帳號項目主標旁出現「（活躍）」suffix,12 號副標 UID 顏色比主標淺。
- [ ] 把某個帳號的別名設長字串(可在帳號管理改 alias)→ 選單裡主標 ellipsis 截字,UID 副標不被影響。
- [ ] AppBar 觸發鈕:長別名也只用 ellipsis 截 alias 部分,UID 與 `▾` 仍完整可見;AppBar 高度未變。
- [ ] `activeUid == null` 情境(未登入過任何帳號):觸發鈕仍顯示「未同步」。
- [ ] 切換語言成 `en`:`uidActiveSuffix` 變 ` (active)`、`uidNotSynced` 變 `Not synced`,版面不破壞。

> 如果 release build 取得不便,debug build 也能驗證,但要意識到 debug 不能反映實際 perf(此次改動不涉效能,主要看版面正確性)。

- [ ] **Step 5: 提交**

```
git add lib/widgets/uid_indicator.dart
git commit -m "feat(uid-indicator): stack alias over uid in account switcher"
```

---

## 驗收條件

完成本 plan 後:
- `flutter analyze` 與 `flutter test` 皆通過。
- `AccountMenuLabel` / `AccountTriggerLabel` 兩個 widget 由 widget test 覆蓋(共 8 個 test)。
- `UidIndicator` 的 `build` 不再直接渲染文字,只負責 provider wiring 與選單組裝。
- 視覺驗收清單全部通過(手動)。
