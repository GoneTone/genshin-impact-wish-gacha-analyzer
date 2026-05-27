# Footer 團隊資訊與社群連結 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把舊版 (master) topbar 右側的 Facebook / Discord / Line / GitHub 四個社群 icon 以及團隊名稱+網站連結，搬到 Flutter 改寫版 `AppShell` 底部 footer「最後更新」列的右側。

**Architecture:** 新增資料常數檔 `lib/data/team_info.dart` 與無狀態元件 `lib/widgets/team_links_bar.dart`；修改 `lib/pages/app_shell.dart` 把原本只有 `Text` 的底部 Container 換成 `Row(Expanded(Text), TeamLinksBar)`。Icon 改用 `font_awesome_flutter`（與 master 同源），點擊行為走既有 `openExternalUrl()`。

**Tech Stack:** Flutter / Dart、`font_awesome_flutter`（新增）、`url_launcher`（已存在）、Riverpod / go_router（不變動）。

**Spec：** `docs/superpowers/specs/2026-05-13-footer-team-links-design.md`

---

## File Structure

- 新增：
  - `lib/data/team_info.dart` — 團隊與社群相關常數
  - `lib/widgets/team_links_bar.dart` — 右側 icon + 團隊名稱的 Row 元件
  - `test/widgets/team_links_bar_test.dart` — 上述元件的 widget 測試
- 修改：
  - `pubspec.yaml` — 加入 `font_awesome_flutter`
  - `lib/pages/app_shell.dart:116-133` — footer Container 內容改為 Row

---

## Task 1：新增 `TeamInfo` 常數檔與 `font_awesome_flutter` 套件

**Files:**
- Create: `lib/data/team_info.dart`
- Modify: `pubspec.yaml` (加入 `font_awesome_flutter`)

- [ ] **Step 1: 新增 `lib/data/team_info.dart`**

完整內容如下（直接寫入新檔）：

```dart
// lib/data/team_info.dart
//
// 團隊資訊與社群連結常數。對齊舊版 (master) `src/store/index.js` 中的
// configs.team / configs.app.githubUrl，從環境變數搬到 dart 常數。

class TeamInfo {
  const TeamInfo._();

  static const String name = '原神資訊站 Genshin Impact Info';
  static const String websiteUrl = 'https://genshininfo.reh.tw/';
  static const String facebookUrl = 'https://genshininfo.reh.tw/facebook';
  static const String discordUrl = 'https://genshininfo.reh.tw/discord';
  static const String lineUrl = 'https://genshininfo.reh.tw/line';
}

/// 專案 GitHub repo。對齊 master `configs.app.githubUrl`（屬於 app 而非 team）。
const String appGithubUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer';
```

- [ ] **Step 2: 加入 `font_awesome_flutter` 套件**

執行：

```powershell
flutter pub add font_awesome_flutter
```

預期：`pubspec.yaml` 的 `dependencies:` 區段會多一行類似 `font_awesome_flutter: ^10.7.0`（版本以 `pub add` 實際結果為準），且 `pubspec.lock` 更新。

- [ ] **Step 3: 跑格式化與靜態分析**

```powershell
dart format lib/ test/
flutter analyze
```

預期 `flutter analyze` 輸出 `No issues found!`。

- [ ] **Step 4: 跑測試（無新測試，但確認既有測試全綠）**

```powershell
flutter test
```

預期 `All tests passed!`。

- [ ] **Step 5: Commit**

```powershell
git add lib/data/team_info.dart pubspec.yaml pubspec.lock
git commit -m "chore(deps): add font_awesome_flutter and TeamInfo constants for footer team links"
```

---

## Task 2：TDD 建立 `TeamLinksBar` 元件

**Files:**
- Create: `lib/widgets/team_links_bar.dart`
- Test:   `test/widgets/team_links_bar_test.dart`

- [ ] **Step 1: 寫失敗測試 `test/widgets/team_links_bar_test.dart`**

直接寫入新檔，完整內容：

```dart
// test/widgets/team_links_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/team_links_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('TeamLinksBar 渲染 4 個社群 IconButton 與團隊名稱', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    // 4 個社群 icon（用 FaIcon 找）
    expect(find.byType(FaIcon), findsNWidgets(4));

    // 團隊名稱出現
    expect(find.text(TeamInfo.name), findsOneWidget);
  });

  testWidgets('每個社群 IconButton 都有正確 tooltip', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    for (final label in const ['Facebook', 'Discord', 'Line', 'GitHub']) {
      expect(
        find.byTooltip(label),
        findsOneWidget,
        reason: '應該有 tooltip 為 $label 的 IconButton',
      );
    }
  });

  testWidgets('4 個社群 IconButton 的 onPressed 都不為 null', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    final buttons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .toList();
    expect(buttons.length, 4);
    for (final b in buttons) {
      expect(b.onPressed, isNotNull);
    }
  });

  testWidgets('團隊名稱被 AppLink 包住且 URL 為 TeamInfo.websiteUrl', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    final appLink = tester.widget<AppLink>(find.byType(AppLink));
    expect(appLink.url, TeamInfo.websiteUrl);
  });

  testWidgets('點擊任一 IconButton 或團隊名稱不會拋例外', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    await tester.tap(find.byTooltip('Facebook'));
    await tester.tap(find.byTooltip('Discord'));
    await tester.tap(find.byTooltip('Line'));
    await tester.tap(find.byTooltip('GitHub'));
    await tester.tap(find.text(TeamInfo.name));
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: 跑測試驗證 fail**

```powershell
flutter test test/widgets/team_links_bar_test.dart
```

預期：編譯錯誤，訊息中包含 `Target of URI doesn't exist: 'package:genshin_impact_wish_gacha_analyzer/widgets/team_links_bar.dart'` 或 `Undefined name 'TeamLinksBar'`。

- [ ] **Step 3: 實作 `lib/widgets/team_links_bar.dart`**

完整內容：

```dart
// lib/widgets/team_links_bar.dart
//
// AppShell 底部 footer 右側的團隊資訊列：
// 4 個社群 icon (Facebook / Discord / Line / GitHub) + 分隔線 + 團隊名稱連結。
// 設計來源：舊版 master `src/components/NavLayout.vue` 的 topbar。

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

class TeamLinksBar extends StatelessWidget {
  const TeamLinksBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconLink(
          icon: FontAwesomeIcons.facebookF,
          tooltip: 'Facebook',
          url: TeamInfo.facebookUrl,
        ),
        _IconLink(
          icon: FontAwesomeIcons.discord,
          tooltip: 'Discord',
          url: TeamInfo.discordUrl,
        ),
        _IconLink(
          icon: FontAwesomeIcons.line,
          tooltip: 'Line',
          url: TeamInfo.lineUrl,
        ),
        _IconLink(
          icon: FontAwesomeIcons.github,
          tooltip: 'GitHub',
          url: appGithubUrl,
        ),
        const SizedBox(width: AppSpacing.xs),
        Container(width: 1, height: 16, color: tokens.borderSubtle),
        const SizedBox(width: AppSpacing.s),
        AppLink(
          url: TeamInfo.websiteUrl,
          child: Text(
            TeamInfo.name,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _IconLink extends StatelessWidget {
  const _IconLink({
    required this.icon,
    required this.tooltip,
    required this.url,
  });

  final IconData icon;
  final String tooltip;
  final String url;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return IconButton(
      tooltip: tooltip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: FaIcon(icon, color: tokens.textSecondary),
      onPressed: () {
        final uri = Uri.tryParse(url);
        if (uri == null) {
          debugPrint('TeamLinksBar: invalid url "$url"');
          return;
        }
        openExternalUrl(uri);
      },
    );
  }
}
```

- [ ] **Step 4: 跑測試驗證 pass**

```powershell
flutter test test/widgets/team_links_bar_test.dart
```

預期：`All tests passed!`。

- [ ] **Step 5: 跑格式化與靜態分析**

```powershell
dart format lib/ test/
flutter analyze
```

預期 `flutter analyze` 輸出 `No issues found!`。

- [ ] **Step 6: 跑全套測試確認沒打到別處**

```powershell
flutter test
```

預期 `All tests passed!`。

- [ ] **Step 7: Commit**

```powershell
git add lib/widgets/team_links_bar.dart test/widgets/team_links_bar_test.dart
git commit -m "feat(app-shell): add TeamLinksBar with social icons and team site link"
```

---

## Task 3：在 `AppShell` footer 整合 `TeamLinksBar`

**Files:**
- Modify: `lib/pages/app_shell.dart:116-133`

- [ ] **Step 1: 修改 footer Container**

把 `lib/pages/app_shell.dart` 第 116–133 行的 Container 改成下列內容（保留原本的 `padding`、`color`，只把 child 從單一 `Text` 換成 `Row`）：

```dart
Container(
  width: double.infinity,
  padding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.l,
    vertical: AppSpacing.xs * 1.5,
  ),
  color: tokens.surfaceCardHigh,
  child: Row(
    children: [
      Expanded(
        child: Text(
          activeData == null
              ? l.footerNotSynced
              : l.footerLastUpdated(
                  DateFormat(
                    'yyyy-MM-dd HH:mm',
                  ).format(activeData.lastUpdated.toLocal()),
                ),
          style: Theme.of(context).textTheme.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: AppSpacing.s),
      const TeamLinksBar(),
    ],
  ),
),
```

同時在檔案頂部的 import 區補一行（按字母順序插入）：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/team_links_bar.dart';
```

- [ ] **Step 2: 跑格式化與靜態分析**

```powershell
dart format lib/ test/
flutter analyze
```

預期 `flutter analyze` 輸出 `No issues found!`。

- [ ] **Step 3: 跑全套測試**

```powershell
flutter test
```

預期 `All tests passed!`。

- [ ] **Step 4: 視覺驗收（手動）**

```powershell
flutter run -d windows
```

驗證：
1. 視窗預設寬度下，底部 footer 左邊顯示「最後更新 …」或「尚未同步」，右邊依序顯示 Facebook / Discord / Line / GitHub 四個 icon + 細直線 + 「原神資訊站 Genshin Impact Info」（hover 變色、底線）。
2. 將視窗縮窄到 800px 寬，左邊文字 ellipsis、右邊 icon 區仍完整。
3. 點擊任一 icon 或團隊名稱，作業系統會開啟瀏覽器並導向對應 URL。
4. footer 高度與整合前目視一致（IconButton compact 設定生效）。

如視覺異常先記錄，再決定是否補修。

- [ ] **Step 5: Commit**

```powershell
git add lib/pages/app_shell.dart
git commit -m "feat(app-shell): show TeamLinksBar on the right side of footer"
```

---

## 完成後 checklist（DoD）

- [ ] 4 個社群 icon + 團隊名稱顯示在 footer 右側、左側「最後更新」文字保留
- [ ] 點擊各 icon / 團隊名稱開啟對應 URL
- [ ] `dart format lib/ test/` 無 diff
- [ ] `flutter analyze` 輸出 `No issues found!`
- [ ] `flutter test` 輸出 `All tests passed!`
- [ ] 3 個 commits 對應 3 個 Task
