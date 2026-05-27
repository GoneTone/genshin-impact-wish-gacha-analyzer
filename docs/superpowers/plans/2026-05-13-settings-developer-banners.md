# Settings Developer Banners Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在設定頁「關於」區塊現有 "Developed by" 文字行下方,新增兩張可點擊的橫幅圖片 (旋風之音 GoneTone、原神資訊站),並抽出可重用的 `BannerLink` widget。

**Architecture:** 新增 `lib/widgets/banner_link.dart`,提供 `BannerLink` widget 包裝 `Image.asset` + `MouseRegion` + `AnimatedOpacity` + `Tooltip` + `Semantics` + `GestureDetector`,點擊呼叫 `app_link.dart` 已匯出的 `openExternalUrl()`。`_AboutContent` 加入響應式 `Wrap` 容納兩個 `BannerLink`。

**Tech Stack:** Flutter (Material 3) + Riverpod + url_launcher。測試用 `flutter_test`。圖片打包至 `assets/banners/`。

---

## File Structure

- **Create** `lib/widgets/banner_link.dart` — 圖片連結 widget,單一職責、可重用
- **Create** `test/widgets/banner_link_test.dart` — `BannerLink` 的 widget 測試
- **Create** `assets/banners/gonetone_banner.png` — 旋風之音橫幅資產
- **Create** `assets/banners/genshin_info_banner.png` — 原神資訊站橫幅資產
- **Modify** `pubspec.yaml` — `flutter.assets` 加入 `- assets/banners/`
- **Modify** `lib/pages/settings_page.dart` — `_AboutContent` 末端加 `Wrap` + 2 個 `BannerLink`

---

## Task 1: 複製橫幅圖片資產與註冊 pubspec

**Files:**
- Create: `assets/banners/gonetone_banner.png`
- Create: `assets/banners/genshin_info_banner.png`
- Modify: `pubspec.yaml` (行 37-38 附近)

- [ ] **Step 1: 建立 assets/banners/ 目錄**

Run (PowerShell):
```powershell
New-Item -ItemType Directory -Path "assets\banners" -Force
```
Expected: `Directory: ...\assets`,出現 `banners` 目錄。

- [ ] **Step 2: 複製兩張橫幅圖**

Run (PowerShell):
```powershell
Copy-Item -Path "G:\_圖片\_個人圖片\_旋風之音 GonTone\橫幅\GoneTone Banner_954x200.png" -Destination "assets\banners\gonetone_banner.png"
Copy-Item -Path "G:\_圖片\原神資訊站 Genshin Impact Info\Logo\banner.png" -Destination "assets\banners\genshin_info_banner.png"
```
Expected: 無錯誤輸出。執行後可用 `Get-ChildItem assets\banners\` 確認兩個檔案存在。

> 若來源路徑不存在或檔名異動,請先確認實際檔名;這兩個來源是使用者本機檔案。

- [ ] **Step 3: 更新 pubspec.yaml**

修改 `pubspec.yaml` 末段 `flutter.assets`,從:

```yaml
flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/icons/
```

改為:

```yaml
flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/icons/
    - assets/banners/
```

- [ ] **Step 4: 確認 pub get 解析無誤**

Run:
```
flutter pub get
```
Expected: 結束於 `Got dependencies!` 或 `Resolving dependencies...` 後無錯誤。

- [ ] **Step 5: Commit**

```bash
git add assets/banners/gonetone_banner.png assets/banners/genshin_info_banner.png pubspec.yaml
git commit -m "$(cat <<'EOF'
feat(assets): add developer banner images for settings page

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: BannerLink 骨架 + 渲染測試 (TDD)

**Files:**
- Create: `lib/widgets/banner_link.dart`
- Create: `test/widgets/banner_link_test.dart`

- [ ] **Step 1: 寫第一個測試 — 渲染指定 height 的 Image**

建立 `test/widgets/banner_link_test.dart` 內容:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_link.dart';

void main() {
  testWidgets('渲染 Image 並套用指定 height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: 'test banner',
            height: 64,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.height, 64);
    expect(image.fit, BoxFit.contain);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗 (找不到 BannerLink 類別)**

Run:
```
flutter test test/widgets/banner_link_test.dart
```
Expected: 編譯失敗,訊息類似 `Error: Couldn't find constructor 'BannerLink'` 或 `Type 'BannerLink' not found`。

- [ ] **Step 3: 建立 BannerLink 最小實作**

建立 `lib/widgets/banner_link.dart` 內容:

```dart
import 'package:flutter/material.dart';

class BannerLink extends StatelessWidget {
  const BannerLink({
    super.key,
    required this.assetPath,
    required this.url,
    required this.semanticLabel,
    required this.height,
  });

  final String assetPath;
  final String url;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(assetPath, height: height, fit: BoxFit.contain);
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run:
```
flutter test test/widgets/banner_link_test.dart
```
Expected: `All tests passed!` (1 個測試)。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/banner_link.dart test/widgets/banner_link_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add BannerLink widget skeleton with image rendering

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: hover 行為 — cursor + opacity (TDD)

**Files:**
- Modify: `lib/widgets/banner_link.dart`
- Modify: `test/widgets/banner_link_test.dart`

- [ ] **Step 1: 加 cursor 測試**

在 `test/widgets/banner_link_test.dart` 的 `main()` 內,於現有測試後加入:

```dart
  testWidgets('hover 時 cursor 為 SystemMouseCursors.click', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: 'test banner',
            height: 64,
          ),
        ),
      ),
    );

    final region = tester.widget<MouseRegion>(
      find
          .descendant(
            of: find.byType(BannerLink),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(region.cursor, SystemMouseCursors.click);
  });
```

- [ ] **Step 2: 加 hover opacity 測試**

繼續在 `main()` 內加入:

```dart
  testWidgets('hover 時 AnimatedOpacity 變為 0.85,離開後變回 1.0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: Center(
            child: BannerLink(
              assetPath: 'assets/banners/gonetone_banner.png',
              url: 'https://example.test',
              semanticLabel: 'test banner',
              height: 64,
            ),
          ),
        ),
      ),
    );

    double readOpacity() {
      final ao = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      return ao.opacity;
    }

    expect(readOpacity(), 1.0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.byType(BannerLink)));
    await tester.pump();
    expect(readOpacity(), 0.85);

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(readOpacity(), 1.0);
  });
```

並在檔案頂端加入需要的 import:

```dart
import 'package:flutter/gestures.dart';
```

- [ ] **Step 3: 跑測試確認失敗 (找不到 MouseRegion / AnimatedOpacity)**

Run:
```
flutter test test/widgets/banner_link_test.dart
```
Expected: 後兩個測試失敗,訊息類似 `Could not find ... MouseRegion` / `Could not find ... AnimatedOpacity`。

- [ ] **Step 4: 改 BannerLink 為 StatefulWidget 加 hover 行為**

將 `lib/widgets/banner_link.dart` 整檔替換為:

```dart
import 'package:flutter/material.dart';

class BannerLink extends StatefulWidget {
  const BannerLink({
    super.key,
    required this.assetPath,
    required this.url,
    required this.semanticLabel,
    required this.height,
  });

  final String assetPath;
  final String url;
  final String semanticLabel;
  final double height;

  @override
  State<BannerLink> createState() => _BannerLinkState();
}

class _BannerLinkState extends State<BannerLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedOpacity(
        opacity: _hovering ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Image.asset(
          widget.assetPath,
          height: widget.height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 跑測試確認通過**

Run:
```
flutter test test/widgets/banner_link_test.dart
```
Expected: `All tests passed!` (3 個測試)。

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/banner_link.dart test/widgets/banner_link_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add hover cursor and opacity feedback to BannerLink

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Tooltip 與 Semantics (TDD)

**Files:**
- Modify: `lib/widgets/banner_link.dart`
- Modify: `test/widgets/banner_link_test.dart`

- [ ] **Step 1: 加 Tooltip 與 Semantics 測試**

在 `test/widgets/banner_link_test.dart` 的 `main()` 末端加入:

```dart
  testWidgets('Tooltip 使用 semanticLabel 作為 message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: '旋風之音 GoneTone',
            height: 64,
          ),
        ),
      ),
    );

    expect(find.byTooltip('旋風之音 GoneTone'), findsOneWidget);
  });

  testWidgets('提供 Semantics button label 給螢幕閱讀器', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: '旋風之音 GoneTone',
            height: 64,
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('旋風之音 GoneTone'),
      findsAtLeastNWidgets(1),
    );
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run:
```
flutter test test/widgets/banner_link_test.dart
```
Expected: 後兩個測試失敗 (找不到 Tooltip / 找不到 Semantics label)。

- [ ] **Step 3: 把 Tooltip + Semantics 加進 BannerLink**

修改 `lib/widgets/banner_link.dart` 的 `build()`,在 `MouseRegion` 外層包入 `Tooltip` + `Semantics`。整個 `build` 改為:

```dart
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.semanticLabel,
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: AnimatedOpacity(
            opacity: _hovering ? 0.85 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Image.asset(
              widget.assetPath,
              height: widget.height,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: 跑測試確認通過**

Run:
```
flutter test test/widgets/banner_link_test.dart
```
Expected: `All tests passed!` (5 個測試)。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/banner_link.dart test/widgets/banner_link_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add Tooltip and Semantics label to BannerLink

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 點擊行為 — GestureDetector + openExternalUrl (TDD)

**Files:**
- Modify: `lib/widgets/banner_link.dart`
- Modify: `test/widgets/banner_link_test.dart`

- [ ] **Step 1: 加點擊相關測試**

在 `test/widgets/banner_link_test.dart` 的 `main()` 末端加入:

```dart
  testWidgets('BannerLink 內的 GestureDetector 有連上 onTap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: 'test banner',
            height: 64,
          ),
        ),
      ),
    );

    final detector = tester.widget<GestureDetector>(
      find
          .descendant(
            of: find.byType(BannerLink),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(detector.onTap, isNotNull);
    expect(detector.behavior, HitTestBehavior.opaque);
  });

  testWidgets('點擊 BannerLink 不會丟例外', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: 'test banner',
            height: 64,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(BannerLink), warnIfMissed: false);
    await tester.pumpAndSettle();
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run:
```
flutter test test/widgets/banner_link_test.dart
```
Expected: 新增的 `GestureDetector` 測試失敗 (找不到 `GestureDetector`)。

- [ ] **Step 3: 加 GestureDetector + 串接 openExternalUrl**

修改 `lib/widgets/banner_link.dart`,於檔案頂端 import 區加入:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
```

然後在 `_BannerLinkState` 內加入私有方法 `_handleTap`:

```dart
  Future<void> _handleTap() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      debugPrint('BannerLink: invalid url "${widget.url}"');
      return;
    }
    await openExternalUrl(uri);
  }
```

並把 `build()` 內的 `MouseRegion` 內部 `AnimatedOpacity` 改為包在 `GestureDetector` 內:

```dart
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: AnimatedOpacity(
              opacity: _hovering ? 0.85 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: Image.asset(
                widget.assetPath,
                height: widget.height,
                fit: BoxFit.contain,
              ),
            ),
          ),
```

最終 `lib/widgets/banner_link.dart` 完整內容:

```dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

class BannerLink extends StatefulWidget {
  const BannerLink({
    super.key,
    required this.assetPath,
    required this.url,
    required this.semanticLabel,
    required this.height,
  });

  final String assetPath;
  final String url;
  final String semanticLabel;
  final double height;

  @override
  State<BannerLink> createState() => _BannerLinkState();
}

class _BannerLinkState extends State<BannerLink> {
  bool _hovering = false;

  Future<void> _handleTap() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      debugPrint('BannerLink: invalid url "${widget.url}"');
      return;
    }
    await openExternalUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.semanticLabel,
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: AnimatedOpacity(
              opacity: _hovering ? 0.85 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: Image.asset(
                widget.assetPath,
                height: widget.height,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run:
```
flutter test test/widgets/banner_link_test.dart
```
Expected: `All tests passed!` (7 個測試)。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/banner_link.dart test/widgets/banner_link_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): wire BannerLink tap to openExternalUrl

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 整合到設定頁 _AboutContent

**Files:**
- Modify: `lib/pages/settings_page.dart:174-208` (`_AboutContent.build`)

- [ ] **Step 1: 加 BannerLink import 到 settings_page.dart**

於 `lib/pages/settings_page.dart` 的 import 區 (第 19 行 `app_link.dart` 之後) 加入:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_link.dart';
```

- [ ] **Step 2: 於 _AboutContent.build 末端加入兩張橫幅**

修改 `_AboutContent` (約行 174-208) 內的 `Column.children`,在現有 `Wrap(...)` 之後加入 `SizedBox` + 新的 `Wrap`。完整 `_AboutContent` 改為:

```dart
class _AboutContent extends ConsumerWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.settingsAboutVersion(version)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.code, size: 16, color: theme.gacha.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            const Text('Developed by '),
            const AppLink(
              url: 'https://github.com/GoneTone',
              child: Text('GoneTone'),
            ),
            const Text(' ('),
            const AppLink(
              url: 'https://genshininfo.reh.tw/',
              child: Text('原神資訊站 Genshin Impact Info'),
            ),
            const Text(')'),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: const [
            BannerLink(
              assetPath: 'assets/banners/gonetone_banner.png',
              url: 'https://blog.reh.tw/',
              semanticLabel: '旋風之音 GoneTone',
              height: 64,
            ),
            BannerLink(
              assetPath: 'assets/banners/genshin_info_banner.png',
              url: 'https://genshininfo.reh.tw/',
              semanticLabel: '原神資訊站 Genshin Impact Info',
              height: 64,
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: 跑 analyze**

Run:
```
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: 跑全部測試**

Run:
```
flutter test
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "$(cat <<'EOF'
feat(settings-page): show developer banner links under About section

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 最終品質檢查 + 實機驗證

**Files:** (no changes — verification only)

- [ ] **Step 1: 格式化**

Run:
```
dart format lib/ test/
```
Expected: 無檔案被修改 (或修改後仍維持應有格式)。若有修改,加碼一次 commit。

- [ ] **Step 2: 靜態分析**

Run:
```
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 3: 完整測試**

Run:
```
flutter test
```
Expected: `All tests passed!`

- [ ] **Step 4: 實機跑起來,人工驗證 UI**

Run:
```
flutter run -d windows
```

驗證項目:
- 設定頁的「關於」區塊可看到兩張橫幅,順序為旋風之音 GoneTone → 原神資訊站
- 兩張橫幅同高度 (64px)
- 滑鼠移到任一張時:游標變手指、圖片有 opacity 變化 (略透)、出現 Tooltip 顯示對應名稱
- 點擊旋風之音橫幅 → 系統瀏覽器開啟 `https://blog.reh.tw/`
- 點擊原神資訊站橫幅 → 系統瀏覽器開啟 `https://genshininfo.reh.tw/`
- 縮小視窗寬度時兩張橫幅自動換行堆疊 (寬視窗並排)
- 既有 "Developed by GoneTone (原神資訊站 ...)" 文字行仍正常顯示且 GitHub 連結仍能點

任一驗證項失敗就停下找原因,不要強行視為完成。

- [ ] **Step 5: 若格式化在 Step 1 有變更,加碼 commit**

若 Step 1 有修改任何檔案:

```bash
git add lib/ test/
git commit -m "$(cat <<'EOF'
style: dart format

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

若無變更,跳過此步驟。
