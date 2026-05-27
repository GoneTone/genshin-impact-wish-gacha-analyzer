# UI/UX Redesign — Phase 1 (Skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把專案從目前的 M3 預設 indigo + 單一 NavigationRail，改為「左 Rail + Bento 網格 + 深藍夜空 dark/light + i18n 架構 + 設定頁框架」。Phase 1 完成後 UI 看起來是新的，但保底 / 時間軸 / 表格進階互動仍是 placeholder（這些屬於 Phase 2）。

**Architecture:** Token-driven theming（`ThemeData` + `ThemeExtension<GachaTokens>`）+ Riverpod `Notifier` 管 `themeMode`/`locale` + `shared_preferences` 持久化 + Flutter 內建 `flutter gen-l10n` 做 arb→Dart codegen。新增三條共用元件路徑：`lib/widgets/cards/` 卡片原件、`lib/state/settings.dart` 偏好狀態、`lib/l10n/` 翻譯檔。既有 `wish_repository` / `wish_storage` / capture 流程**不動**。

**Tech Stack:** Flutter 3.x、Dart 3、`flutter_riverpod ^3.0.0`、`go_router ^17.0.0`、`fl_chart ^1.0.0`、`flutter_localizations`（SDK）、`intl ^0.20.0`（已有）、新增 `shared_preferences ^2.x`。

**Spec reference:** `docs/superpowers/specs/2026-05-09-ui-ux-redesign-design.md`

---

## File Structure

### 新增

```
lib/
  l10n/
    app_zh_Hant.arb        ← 主要翻譯（最完整）
    app_zh_Hans.arb         ← 骨架（先用 zh-Hant 內容當 placeholder）
    app_en.arb              ← 骨架
  state/
    settings.dart           ← settingsProvider, themeModeProvider, localeProvider
  services/
    settings_storage.dart   ← SharedPreferences wrapper
  theme/
    tokens.dart             ← Dark/Light tokens + GachaTokens ThemeExtension
  widgets/
    cards/
      stat_card.dart
      chart_card.dart
      section_card.dart
    page_header.dart
  pages/
    settings_page.dart

l10n.yaml                   ← Flutter gen-l10n 設定

test/
  services/
    settings_storage_test.dart
  state/
    settings_test.dart
  widgets/
    cards/
      stat_card_test.dart
      chart_card_test.dart
      section_card_test.dart
    page_header_test.dart
```

### 修改

```
pubspec.yaml                ← 加 shared_preferences、generate: true
lib/
  main.dart                 ← 接 settingsProvider + l10n delegates
  routing/app_router.dart   ← 加 /settings、改用 fade transition
  theme/app_theme.dart      ← 從 tokens 構建 dark+light ThemeData
  data/gacha_types.dart     ← name 改用 i18n key、加 fiveStarPity/fourStarPity
  pages/
    app_shell.dart          ← rail spacer + 設定入口 + breakpoint 邏輯
    overview_page.dart      ← bento layout（用既有資料填）
    banner_page.dart        ← bento layout（用既有資料填）
  widgets/
    empty_state.dart        ← token + factories
    rarity_pie.dart         ← 包進 ChartCard
    item_type_pie.dart      ← 包進 ChartCard
    stats_panel.dart        ← 拆成多個 StatCard 後刪除（或留 deprecated 包裝）
    record_list_table.dart  ← token 化、5★/4★ 改 pill；行為不變
    update_progress_dialog.dart  ← token + i18n + emoji→Icon
    uid_indicator.dart      ← i18n
```

### 退役（Phase 1 結束時刪 / deprecate）

- `lib/theme/app_theme.dart` 內 `GachaColors` → 移到 `tokens.dart` 後可刪薄包裝（callsite 全換完後執行）
- `lib/widgets/stats_panel.dart` → 拆成多 StatCard 後可刪

### 不動

- `lib/services/wish_*.dart`（`wish_storage` / `wish_fetcher` / `wish_stats` / `wish_url`）
- `lib/state/wish_repository.dart`、`wish_capture.dart`、`update_progress.dart`
- `lib/src/rust/`（Rust bridge）
- `lib/models/`、`lib/app_info.dart`

---

## Coding Conventions（這份計畫所有任務共用）

- 全部新檔以絕對 import：`package:genshin_impact_wish_gacha_analyzer/...`
- Riverpod 使用 `Notifier` / `NotifierProvider` 風格（與既有 `wish_repository.dart` 一致）
- 所有顏色、間距、圓角、字級**禁止**寫 hex 或 magic number 在元件內，一律走 `Theme.of(context)` / `Theme.of(context).extension<GachaTokens>()!`
- Test 使用 `flutter_test` + 既有風格（看 `test/services/wish_stats_test.dart` 範本）
- Commit 訊息英文、imperative：`feat: add...`、`refactor: ...`、`chore: ...`
- 每個 task 結尾必有一個 commit step

---

## Task 1: Add dependencies and configure i18n in pubspec

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Update `pubspec.yaml` dependencies**

把 `pubspec.yaml` 改成下列內容（保留現有版本、加入 flutter_localizations / shared_preferences、加入 `flutter: generate: true`）：

```yaml
name: genshin_impact_wish_gacha_analyzer
description: "原神祈願卡池分析 Genshin Impact Wish Gacha Analyzer | A utility for analyzing gacha history, where all data and numbers are well-organized in a convenient manner!"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.11.5

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
  fl_chart: ^1.0.0
  intl: ^0.20.0
  package_info_plus: ^10.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
  generate: true
```

- [ ] **Step 2: Run pub get**

Run: `flutter pub get`
Expected: 解析成功、新依賴下載完成、無錯誤輸出。

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add shared_preferences and enable flutter generate for i18n"
```

---

## Task 2: Create initial l10n scaffolding

目的：建立 `l10n.yaml` 與三個 arb 檔（先放最少 1 個 key 確保 codegen 成功），後續任務再陸續搬 string。

**Files:**
- Create: `l10n.yaml`
- Create: `lib/l10n/app_zh_Hant.arb`
- Create: `lib/l10n/app_zh_Hans.arb`
- Create: `lib/l10n/app_zh.arb` ← Flutter 要求 base locale 當 script-suffixed (`zh_Hant` / `zh_Hans`) 的 fallback；少了會 codegen 失敗
- Create: `lib/l10n/app_en.arb`

- [ ] **Step 1: Create `l10n.yaml`**

```yaml
arb-dir: lib/l10n
template-arb-file: app_zh_Hant.arb
output-localization-file: app_localizations.dart
```

- [ ] **Step 2: Create `lib/l10n/app_zh_Hant.arb`**

```json
{
  "@@locale": "zh_Hant",
  "appName": "原神祈願卡池分析",
  "@appName": {
    "description": "App display name in title bar"
  }
}
```

- [ ] **Step 3: Create `lib/l10n/app_zh_Hans.arb`**

```json
{
  "@@locale": "zh_Hans",
  "appName": "原神祈愿卡池分析"
}
```

- [ ] **Step 4: Create `lib/l10n/app_en.arb`**

```json
{
  "@@locale": "en",
  "appName": "Genshin Wish Analyzer"
}
```

- [ ] **Step 5: Trigger codegen**

Run: `flutter gen-l10n`
Expected: 無錯誤；確認 `lib/l10n/generated/app_localizations.dart` 已產生。Flutter 3.41+ 已棄用 synthetic package，必須輸出到 tracked 目錄；`l10n.yaml` 需設 `output-dir: lib/l10n/generated`。

- [ ] **Step 6: Commit**

```bash
git add l10n.yaml lib/l10n/
git commit -m "feat(i18n): scaffold flutter gen-l10n with zh-Hant/zh-Hans/en arb files"
```

---

## Task 3: Create design tokens

**Files:**
- Create: `lib/theme/tokens.dart`

- [ ] **Step 1: Write tokens file**

```dart
// lib/theme/tokens.dart
import 'package:flutter/material.dart';

/// 中性 scale：間距 / 圓角 / 字級。dark 與 light 共用。
abstract class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract class AppRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
}

/// 字級語意（搭配 ThemeData.textTheme 對應 M3 名稱）。
abstract class AppFontSize {
  static const double display = 32; // 保底大數字
  static const double title = 18;   // 頁標 / 卡標
  static const double body = 14;
  static const double label = 11;   // uppercase 小寫上標
}

/// 卡池 / 應用層級的色 token。透過 ThemeExtension 注入。
@immutable
class GachaTokens extends ThemeExtension<GachaTokens> {
  const GachaTokens({
    required this.surfaceBackground,
    required this.surfaceCard,
    required this.surfaceCardHigh,
    required this.borderSubtle,
    required this.borderEmphasis,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.fiveStar,
    required this.fourStar,
    required this.threeStar,
    required this.character,
    required this.weapon,
    required this.accentPrimary,
    required this.stateDanger,
    required this.stateSuccess,
    required this.stateWarning,
  });

  final Color surfaceBackground;
  final Color surfaceCard;
  final Color surfaceCardHigh;
  final Color borderSubtle;
  final Color borderEmphasis;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color fiveStar;
  final Color fourStar;
  final Color threeStar;
  final Color character;
  final Color weapon;
  final Color accentPrimary;
  final Color stateDanger;
  final Color stateSuccess;
  final Color stateWarning;

  /// Dark = 深藍夜空 (palette A)
  static const dark = GachaTokens(
    surfaceBackground: Color(0xFF0C1220),
    surfaceCard: Color(0xFF141C30),
    surfaceCardHigh: Color(0xFF1A2438),
    borderSubtle: Color(0xFF1F2A44),
    borderEmphasis: Color(0xFF27314C),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFDDE3EE),
    textMuted: Color(0xFF8A92A6),
    fiveStar: Color(0xFFE6C477),
    fourStar: Color(0xFFA385E0),
    threeStar: Color(0xFF5B9BD5),
    character: Color(0xFF46B07A),
    weapon: Color(0xFFE6736B),
    accentPrimary: Color(0xFFE6C477),
    stateDanger: Color(0xFFE6736B),
    stateSuccess: Color(0xFF46B07A),
    stateWarning: Color(0xFFE6C477),
  );

  /// Light = 由 dark 衍生（背景反轉、卡池色稍降亮度）
  static const light = GachaTokens(
    surfaceBackground: Color(0xFFFAFBFD),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceCardHigh: Color(0xFFF1F4FA),
    borderSubtle: Color(0xFFE5E8EF),
    borderEmphasis: Color(0xFFD0D5E0),
    textPrimary: Color(0xFF0C1220),
    textSecondary: Color(0xFF2C3245),
    textMuted: Color(0xFF6A7080),
    fiveStar: Color(0xFFB8860B),
    fourStar: Color(0xFF7A4FB8),
    threeStar: Color(0xFF2E7CC2),
    character: Color(0xFF2E7D32),
    weapon: Color(0xFFC62828),
    accentPrimary: Color(0xFFB8860B),
    stateDanger: Color(0xFFC62828),
    stateSuccess: Color(0xFF2E7D32),
    stateWarning: Color(0xFFB8860B),
  );

  @override
  GachaTokens copyWith({
    Color? surfaceBackground,
    Color? surfaceCard,
    Color? surfaceCardHigh,
    Color? borderSubtle,
    Color? borderEmphasis,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? fiveStar,
    Color? fourStar,
    Color? threeStar,
    Color? character,
    Color? weapon,
    Color? accentPrimary,
    Color? stateDanger,
    Color? stateSuccess,
    Color? stateWarning,
  }) =>
      GachaTokens(
        surfaceBackground: surfaceBackground ?? this.surfaceBackground,
        surfaceCard: surfaceCard ?? this.surfaceCard,
        surfaceCardHigh: surfaceCardHigh ?? this.surfaceCardHigh,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        borderEmphasis: borderEmphasis ?? this.borderEmphasis,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        fiveStar: fiveStar ?? this.fiveStar,
        fourStar: fourStar ?? this.fourStar,
        threeStar: threeStar ?? this.threeStar,
        character: character ?? this.character,
        weapon: weapon ?? this.weapon,
        accentPrimary: accentPrimary ?? this.accentPrimary,
        stateDanger: stateDanger ?? this.stateDanger,
        stateSuccess: stateSuccess ?? this.stateSuccess,
        stateWarning: stateWarning ?? this.stateWarning,
      );

  @override
  GachaTokens lerp(ThemeExtension<GachaTokens>? other, double t) {
    if (other is! GachaTokens) return this;
    return GachaTokens(
      surfaceBackground: Color.lerp(surfaceBackground, other.surfaceBackground, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceCardHigh: Color.lerp(surfaceCardHigh, other.surfaceCardHigh, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderEmphasis: Color.lerp(borderEmphasis, other.borderEmphasis, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      fiveStar: Color.lerp(fiveStar, other.fiveStar, t)!,
      fourStar: Color.lerp(fourStar, other.fourStar, t)!,
      threeStar: Color.lerp(threeStar, other.threeStar, t)!,
      character: Color.lerp(character, other.character, t)!,
      weapon: Color.lerp(weapon, other.weapon, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      stateDanger: Color.lerp(stateDanger, other.stateDanger, t)!,
      stateSuccess: Color.lerp(stateSuccess, other.stateSuccess, t)!,
      stateWarning: Color.lerp(stateWarning, other.stateWarning, t)!,
    );
  }
}

/// Theme.of(context) 取 token 的便捷 extension。
extension GachaTokensX on ThemeData {
  GachaTokens get gacha => extension<GachaTokens>()!;
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/theme/tokens.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/theme/tokens.dart
git commit -m "feat(theme): add GachaTokens ThemeExtension and spacing/radius/font scales"
```

---

## Task 4: Build dark/light ThemeData from tokens

**Files:**
- Modify: `lib/theme/app_theme.dart`

- [ ] **Step 1: Replace `app_theme.dart`**

```dart
// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 提供給 callsite 的舊 GachaColors 包裝（過渡用，搬完後移除）。
///
/// 新程式請改用 `Theme.of(context).extension<GachaTokens>()!`。
@Deprecated('Use Theme.of(context).extension<GachaTokens>()! instead')
abstract class GachaColors {
  static Color fiveStar = GachaTokens.dark.fiveStar;
  static Color fourStar = GachaTokens.dark.fourStar;
  static Color threeStar = GachaTokens.dark.threeStar;
  static Color character = GachaTokens.dark.character;
  static Color weapon = GachaTokens.dark.weapon;
  static const Color unknown = Color(0xFF9E9E9E);
}

ThemeData buildDarkTheme() => _buildTheme(
      brightness: Brightness.dark,
      tokens: GachaTokens.dark,
    );

ThemeData buildLightTheme() => _buildTheme(
      brightness: Brightness.light,
      tokens: GachaTokens.light,
    );

ThemeData _buildTheme({
  required Brightness brightness,
  required GachaTokens tokens,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: tokens.accentPrimary,
    brightness: brightness,
    surface: tokens.surfaceBackground,
    surfaceContainerLow: tokens.surfaceCard,
    surfaceContainerHigh: tokens.surfaceCardHigh,
    onSurface: tokens.textPrimary,
    primary: tokens.accentPrimary,
    error: tokens.stateDanger,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: tokens.surfaceBackground,
    dividerColor: tokens.borderSubtle,
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[tokens],
    cardTheme: CardThemeData(
      color: tokens.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      margin: EdgeInsets.zero,
    ),
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: AppFontSize.title,
        fontWeight: FontWeight.w700,
        color: tokens.textPrimary,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: AppFontSize.body,
        color: tokens.textSecondary,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontSize: AppFontSize.label,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: tokens.textMuted,
      ),
    ),
  );
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/theme/`
Expected: 唯一 warning 應該是 `GachaColors` deprecated（暫時保留給其他檔過渡）。

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_theme.dart
git commit -m "feat(theme): build dark+light ThemeData from GachaTokens"
```

---

## Task 5: Implement SettingsStorage with TDD

**Files:**
- Create: `lib/services/settings_storage.dart`
- Create: `test/services/settings_storage_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/services/settings_storage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsStorage', () {
    test('預設回傳 system theme 與 system locale', () async {
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.locale, AppLocale.system);
    });

    test('save 後 load 回得到相同值', () async {
      await SettingsStorage.save(const AppSettings(
        themeMode: AppThemeMode.dark,
        locale: AppLocale.en,
      ));
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.locale, AppLocale.en);
    });

    test('未知 key 值降級為 system', () async {
      SharedPreferences.setMockInitialValues({
        'pref.themeMode': 'rainbow',
        'pref.locale': 'klingon',
      });
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.locale, AppLocale.system);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/settings_storage_test.dart`
Expected: FAIL（檔案不存在）。

- [ ] **Step 3: Write `settings_storage.dart`**

```dart
// lib/services/settings_storage.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, dark, light }

enum AppLocale { system, zhHant, zhHans, en }

@immutable
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.locale,
  });

  final AppThemeMode themeMode;
  final AppLocale locale;

  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: AppLocale.system,
  );

  AppSettings copyWith({AppThemeMode? themeMode, AppLocale? locale}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
      );
}

abstract final class SettingsStorage {
  static const _kThemeMode = 'pref.themeMode';
  static const _kLocale = 'pref.locale';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: _parseLocale(prefs.getString(_kLocale)),
    );
  }

  static Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, _themeModeToString(s.themeMode));
    await prefs.setString(_kLocale, _localeToString(s.locale));
  }

  static AppThemeMode _parseThemeMode(String? raw) => switch (raw) {
        'dark' => AppThemeMode.dark,
        'light' => AppThemeMode.light,
        _ => AppThemeMode.system,
      };

  static String _themeModeToString(AppThemeMode m) => switch (m) {
        AppThemeMode.dark => 'dark',
        AppThemeMode.light => 'light',
        AppThemeMode.system => 'system',
      };

  static AppLocale _parseLocale(String? raw) => switch (raw) {
        'zh-Hant' => AppLocale.zhHant,
        'zh-Hans' => AppLocale.zhHans,
        'en' => AppLocale.en,
        _ => AppLocale.system,
      };

  static String _localeToString(AppLocale l) => switch (l) {
        AppLocale.zhHant => 'zh-Hant',
        AppLocale.zhHans => 'zh-Hans',
        AppLocale.en => 'en',
        AppLocale.system => 'system',
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/settings_storage_test.dart`
Expected: PASS（3 tests）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/settings_storage.dart test/services/settings_storage_test.dart
git commit -m "feat(settings): add SettingsStorage backed by shared_preferences"
```

---

## Task 6: Create settings provider with TDD

**Files:**
- Create: `lib/state/settings.dart`
- Create: `test/state/settings_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/state/settings_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('初始狀態 = defaults', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 等 build 內 _bootstrap 完成
    await container.read(settingsProvider.notifier).waitForLoad();
    final s = container.read(settingsProvider);
    expect(s.themeMode, AppThemeMode.system);
    expect(s.locale, AppLocale.system);
  });

  test('setThemeMode(dark) 後 state 與 prefs 同步', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container
        .read(settingsProvider.notifier)
        .setThemeMode(AppThemeMode.dark);

    expect(container.read(settingsProvider).themeMode, AppThemeMode.dark);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.themeMode, AppThemeMode.dark);
  });

  test('themeModeFlutter 將 system 對應到 ThemeMode.system', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    expect(container.read(themeModeProvider), ThemeMode.system);

    await container
        .read(settingsProvider.notifier)
        .setThemeMode(AppThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/settings_test.dart`
Expected: FAIL（檔案不存在）。

- [ ] **Step 3: Write `lib/state/settings.dart`**

```dart
// lib/state/settings.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  late Future<void> _loadFuture;

  @override
  AppSettings build() {
    _loadFuture = _load();
    return AppSettings.defaults;
  }

  Future<void> _load() async {
    final loaded = await SettingsStorage.load();
    if (!ref.mounted) return;
    state = loaded;
  }

  /// 給 test 用：等首次 load 完。
  @visibleForTesting
  Future<void> waitForLoad() => _loadFuture;

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await SettingsStorage.save(state);
  }

  Future<void> setLocale(AppLocale locale) async {
    state = state.copyWith(locale: locale);
    await SettingsStorage.save(state);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// 給 MaterialApp 直接吃的 ThemeMode（system → ThemeMode.system）
final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(settingsProvider).themeMode;
  return switch (mode) {
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.system => ThemeMode.system,
  };
});

/// 給 MaterialApp 直接吃的 Locale?（system → null）
final localeProvider = Provider<Locale?>((ref) {
  final locale = ref.watch(settingsProvider).locale;
  return switch (locale) {
    AppLocale.zhHant => const Locale('zh', 'Hant'),
    AppLocale.zhHans => const Locale('zh', 'Hans'),
    AppLocale.en => const Locale('en'),
    AppLocale.system => null,
  };
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/state/settings_test.dart`
Expected: PASS（3 tests）。

- [ ] **Step 5: Commit**

```bash
git add lib/state/settings.dart test/state/settings_test.dart
git commit -m "feat(settings): add Riverpod settingsProvider with theme/locale providers"
```

---

## Task 7: Migrate hardcoded UI strings to arb

把整個 codebase 內的中文常量集中到 `app_zh_Hant.arb`，`zh-Hans` / `en` 暫用 zh-Hant 內容當 placeholder（讓 codegen 通過、後續再翻）。**這個 task 不改業務邏輯，只搬字串到生成 class。**

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: Identify all UI string literals**

要搬的字串清單（grep 自 `lib/`，**不含**錯誤訊息的內部字串例外，例如 `wish_repository.dart` 的 `'認證持續失效，請重新登入遊戲'` — 這是 user-facing，要搬）：

| 檔 | 字串 |
|---|---|
| `app_shell.dart` | `'更新資料'`、`'尚未同步'`、`'最後更新：'`、`'綜合'`、`'角色'`、`'武器'`、`'集錄'`、`'常駐'`、`'新手'` |
| `data/gacha_types.dart` | `'角色活動祈願'`、`'武器活動祈願'`、`'集錄祈願'`、`'常駐祈願'`、`'新手祈願'` |
| `widgets/uid_indicator.dart` | `'切換帳號'`、`'未同步'`、`'（活躍）'`、`'重新攔截 / 切換帳號'` |
| `widgets/empty_state.dart` | `'尚未同步任何資料'`、`'點右上「更新資料」開始'`、`'此卡池無紀錄'` |
| `widgets/stats_panel.dart` | `'總抽數：'`、`'5★ 中獎率'`、`'4★ 中獎率'`、`'3★ 中獎率'`、`'角色中獎率'`、`'武器中獎率'` |
| `widgets/rarity_pie.dart` / `item_type_pie.dart` | `'無資料'`、`'角色 '`、`'武器 '`、`'未知 '`（後者三個是 prefix） |
| `widgets/record_list_table.dart` | `'時間'`、`'名稱'`、`'類型'`、`'稀有度'`、`'上一頁'`、`'下一頁'` |
| `widgets/update_progress_dialog.dart` | `'等待攔截…'`、`'抓取中…'`、`'更新完成'`、`'失敗'`、`'取消'`、`'關閉'`、`'請開啟原神 → 卡池 → 歷史紀錄'`、`'（先前的認證已失效，需重新攔截）'`、`'正在抓取：'`、`'第 ?? 頁，已新增 ?? 筆'`、`'新增 ?? 筆紀錄'`、`'⚠ 部分失敗：'` |
| `pages/overview_page.dart` | `'綜合數據（全卡池合計）'` |
| `pages/banner_page.dart` | `'紀錄列表'` |

- [ ] **Step 2: Update `app_zh_Hant.arb`**

完整內容（覆寫）：

```json
{
  "@@locale": "zh_Hant",

  "appName": "原神祈願卡池分析",

  "actionUpdate": "更新資料",
  "actionCancel": "取消",
  "actionClose": "關閉",
  "actionPrevPage": "上一頁",
  "actionNextPage": "下一頁",

  "navOverview": "綜合",
  "navCharacter": "角色",
  "navWeapon": "武器",
  "navChronicled": "集錄",
  "navStandard": "常駐",
  "navBeginner": "新手",
  "navSettings": "設定",

  "gachaTypeCharacter": "角色活動祈願",
  "gachaTypeWeapon": "武器活動祈願",
  "gachaTypeChronicled": "集錄祈願",
  "gachaTypeStandard": "常駐祈願",
  "gachaTypeBeginner": "新手祈願",

  "footerNotSynced": "尚未同步",
  "footerLastUpdated": "最後更新：{time}",
  "@footerLastUpdated": {
    "placeholders": { "time": { "type": "String" } }
  },

  "uidSwitchTooltip": "切換帳號",
  "uidNotSynced": "未同步",
  "uidActiveSuffix": "（活躍）",
  "uidRecapture": "重新攔截 / 切換帳號",

  "emptyNoSyncTitle": "尚未同步任何資料",
  "emptyNoSyncMessage": "點右上「更新資料」開始",
  "emptyNoRecords": "此卡池無紀錄",
  "emptyNoFiltered": "沒有符合條件的紀錄",

  "statsTotal": "總抽數",
  "statsFiveStarRate": "5★ 中獎率",
  "statsFourStarRate": "4★ 中獎率",
  "statsThreeStarRate": "3★ 中獎率",
  "statsCharacterRate": "角色中獎率",
  "statsWeaponRate": "武器中獎率",
  "statsNoData": "無資料",

  "kindCharacter": "角色",
  "kindWeapon": "武器",
  "kindUnknown": "未知",

  "tableTime": "時間",
  "tableName": "名稱",
  "tableKind": "類型",
  "tableRarity": "稀有度",

  "progressWaiting": "等待攔截…",
  "progressFetching": "抓取中…",
  "progressDone": "更新完成",
  "progressFailed": "失敗",
  "progressOpenGameHint": "請開啟原神 → 卡池 → 歷史紀錄",
  "progressFallbackHint": "（先前的認證已失效，需重新攔截）",
  "progressFetchingBanner": "正在抓取：{name}",
  "@progressFetchingBanner": {
    "placeholders": { "name": { "type": "String" } }
  },
  "progressPageStatus": "第 {page} 頁，已新增 {count} 筆",
  "@progressPageStatus": {
    "placeholders": {
      "page": { "type": "int" },
      "count": { "type": "int" }
    }
  },
  "progressDoneSummary": "新增 {count} 筆紀錄",
  "@progressDoneSummary": {
    "placeholders": { "count": { "type": "int" } }
  },
  "progressPartialFailed": "⚠ 部分失敗：{names}",
  "@progressPartialFailed": {
    "placeholders": { "names": { "type": "String" } }
  },

  "errorAuthExpired": "認證持續失效，請重新登入遊戲",
  "errorRateLimited": "請求過於頻繁，請稍後再試",
  "errorServer": "伺服器錯誤：{message}",
  "@errorServer": {
    "placeholders": { "message": { "type": "String" } }
  },
  "errorNoRecords": "此帳號尚無任何卡池紀錄",

  "pageOverviewTitle": "綜合數據（全卡池合計）",
  "pageBannerRecordList": "紀錄列表",

  "settingsTitle": "設定",
  "settingsAppearance": "外觀",
  "settingsTheme": "主題",
  "settingsThemeSystem": "跟隨系統",
  "settingsThemeDark": "深色",
  "settingsThemeLight": "淺色",
  "settingsLanguage": "語言",
  "settingsLocaleSystem": "跟隨系統",
  "settingsLocaleZhHant": "繁體中文",
  "settingsLocaleZhHans": "简体中文",
  "settingsLocaleEn": "English",
  "settingsDataManagement": "資料管理",
  "settingsAccountManagement": "帳號管理",
  "settingsAbout": "關於",
  "settingsAboutVersion": "版本 {version}",
  "@settingsAboutVersion": {
    "placeholders": { "version": { "type": "String" } }
  },
  "settingsPlaceholderPhase2": "（即將推出）"
}
```

- [ ] **Step 3: Update `app_zh_Hans.arb`**

複製 `app_zh_Hant.arb` 全部 keys、把 value 暫用 zh-Hant 內容（**或**改寫成簡體；至少要每個 key 都存在以通過 codegen）。本任務範圍內 zh-Hans 暫用 zh-Hant 內容（每個 value 後面加 `// TODO i18n` 是 arb 不允許的；單純 placeholder 即可）。

範例（精簡版）：

```json
{
  "@@locale": "zh_Hans",
  "appName": "原神祈愿卡池分析",
  "actionUpdate": "更新数据",
  "_TODO_i18n_": "其余 keys 暂沿用繁中内容，待后续翻译"
}
```

> 完整 keys 必須出現，否則 codegen 對 zh-Hans 會 fall back 到 template，runtime 不會壞，但 lint 會抱怨。先全部 copy zh-Hant 字面值；後續可逐個翻譯（不在 phase 1 範圍）。

寫法：直接把 zh-Hant 整份內容 copy 過來、把 `"@@locale": "zh_Hant"` 改成 `"zh_Hans"`，部分常見字翻成簡體（appName 等），其餘維持繁中可接受。

- [ ] **Step 4: Update `app_en.arb`**

同上策略。能翻就翻、不能翻先用 zh-Hant 字面值。範例 key 翻譯：

```json
{
  "@@locale": "en",
  "appName": "Genshin Wish Analyzer",
  "actionUpdate": "Update",
  "actionCancel": "Cancel",
  "actionClose": "Close",
  "actionPrevPage": "Previous",
  "actionNextPage": "Next",
  "navOverview": "Overview",
  "navCharacter": "Character",
  "navWeapon": "Weapon",
  "navChronicled": "Chronicled",
  "navStandard": "Standard",
  "navBeginner": "Beginner",
  "navSettings": "Settings",
  "...": "..."
}
```

剩餘 keys 暫用 zh-Hant 字面值即可（會出現繁中字，phase 2 / 後續再補）。

- [ ] **Step 5: Run codegen**

Run: `flutter gen-l10n`
Expected: 無錯誤；`AppLocalizations` class 含全部新 keys 的 getter。

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/
git commit -m "feat(i18n): migrate hardcoded UI strings to arb files"
```

---

## Task 8: Wire MaterialApp with theme + locale + i18n delegates

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace `MainApp` build**

把 `lib/main.dart` 內 `MainApp.build` 改成：

```dart
// lib/main.dart 上方 import 補：
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
// ...

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      routerConfig: buildAppRouter(),
    );
  }
}
```

- [ ] **Step 2: Update import in main.dart**

把 `import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';` 仍保留（提供 `buildDarkTheme` / `buildLightTheme`）；移除 `appName` 用 const 那一行（改由 `onGenerateTitle` 走 i18n）。

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/main.dart`
Expected: No issues found.

- [ ] **Step 4: Build & smoke test**

Run: `flutter run -d windows`（手動：應用啟動，dark/light 跟系統，UI 仍是舊 indigo 樣子但配色改深藍夜空 / 白底）
Expected: 啟動成功；切換 OS 主題會即時切換。

關閉應用程式。

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat: wire MaterialApp with token-driven themes and i18n delegates"
```

---

## Task 9: Refactor `gacha_types.dart` for i18n + add pity thresholds

**Files:**
- Modify: `lib/data/gacha_types.dart`

- [ ] **Step 1: Replace contents**

```dart
// lib/data/gacha_types.dart
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

class GachaType {
  const GachaType({
    required this.gachaType,
    required this.nameKey,
    required this.fiveStarPity,
    required this.fourStarPity,
  });

  /// 對應 getGachaLog API 的 query string `gacha_type=...`，String 型別跟 query 對齊。
  final String gachaType;

  /// i18n key（透過 [resolveName] 取顯示字串）。
  final String nameKey;

  /// 5★ 保底閾值（新手池為 20 = 池子總抽數，已結束）。
  final int fiveStarPity;

  /// 4★ 保底閾值（新手池無 4★ 機制，仍給 10 作 fallback）。
  final int fourStarPity;

  String resolveName(AppLocalizations l) => switch (nameKey) {
        'gachaTypeCharacter' => l.gachaTypeCharacter,
        'gachaTypeWeapon' => l.gachaTypeWeapon,
        'gachaTypeChronicled' => l.gachaTypeChronicled,
        'gachaTypeStandard' => l.gachaTypeStandard,
        'gachaTypeBeginner' => l.gachaTypeBeginner,
        _ => nameKey,
      };
}

const gachaTypes = <GachaType>[
  GachaType(
    gachaType: '301',
    nameKey: 'gachaTypeCharacter',
    fiveStarPity: 90,
    fourStarPity: 10,
  ),
  GachaType(
    gachaType: '302',
    nameKey: 'gachaTypeWeapon',
    fiveStarPity: 80,
    fourStarPity: 10,
  ),
  GachaType(
    gachaType: '500',
    nameKey: 'gachaTypeChronicled',
    fiveStarPity: 90,
    fourStarPity: 10,
  ),
  GachaType(
    gachaType: '200',
    nameKey: 'gachaTypeStandard',
    fiveStarPity: 90,
    fourStarPity: 10,
  ),
  GachaType(
    gachaType: '100',
    nameKey: 'gachaTypeBeginner',
    fiveStarPity: 20,
    fourStarPity: 10,
  ),
];
```

- [ ] **Step 2: Update callers — `lib/state/wish_repository.dart`**

找到 `displayName: t.name,`（約 line 240），保留為 `displayName: t.nameKey,`（暫存 key，由 dialog 端解析）。會導致 type 仍是 `String`，但語意改成「key」。確保 `update_progress.dart` 與 dialog 後續會處理。

> 此次先把 caller 編過：`lib/state/wish_repository.dart` 內所有 `t.name` 改 `t.nameKey`（同一份字符差別只是含義不同）；`failed.add(t.name)` 也改 `failed.add(t.nameKey)`。

實際 edit：
- `displayName: t.name,` → `displayName: t.nameKey,`
- `failed.add(t.name);` → `failed.add(t.nameKey);`

- [ ] **Step 3: Update caller — `lib/pages/banner_page.dart`**

找到 `_displayName` getter，改成 `Builder` 取 context 解析：

```dart
String _resolveDisplayName(BuildContext context) {
  final l = AppLocalizations.of(context)!;
  return gachaTypes
      .firstWhere(
        (t) => t.gachaType == gachaType,
        orElse: () => GachaType(
          gachaType: gachaType,
          nameKey: gachaType,
          fiveStarPity: 90,
          fourStarPity: 10,
        ),
      )
      .resolveName(l);
}
```

並把 `build` 中 `Text('$_displayName（gacha_type=$gachaType）'…` 改成 `Text('${_resolveDisplayName(context)}（gacha_type=$gachaType）'…`。

> import 新增：`import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';`

- [ ] **Step 4: Update caller — `lib/pages/app_shell.dart` Rail**

`_bannerDestinations` 目前是 const list 含 `Text('角色')` 等。改成在 build 內動態建構：

```dart
List<NavigationRailDestination> _buildBannerDestinations(
    AppLocalizations l) {
  return [
    NavigationRailDestination(
      icon: const Icon(Icons.person_outline),
      selectedIcon: const Icon(Icons.person),
      label: Text(l.navCharacter),
    ),
    NavigationRailDestination(
      icon: const Icon(Icons.shield_outlined),
      selectedIcon: const Icon(Icons.shield),
      label: Text(l.navWeapon),
    ),
    NavigationRailDestination(
      icon: const Icon(Icons.collections_bookmark_outlined),
      selectedIcon: const Icon(Icons.collections_bookmark),
      label: Text(l.navChronicled),
    ),
    NavigationRailDestination(
      icon: const Icon(Icons.history),
      selectedIcon: const Icon(Icons.history_toggle_off),
      label: Text(l.navStandard),
    ),
    NavigationRailDestination(
      icon: const Icon(Icons.school_outlined),
      selectedIcon: const Icon(Icons.school),
      label: Text(l.navBeginner),
    ),
  ];
}
```

`build` 中 `destinations:` 改 `[NavigationRailDestination(...overview), ..._buildBannerDestinations(l)]`，其中 `l = AppLocalizations.of(context)!`、overview 也用 `l.navOverview`。

設定 destination 在 Task 14 補。

- [ ] **Step 5: Run analyze**

Run: `flutter analyze`
Expected: No issues found（僅 GachaColors deprecated warning）。

- [ ] **Step 6: Commit**

```bash
git add lib/data/gacha_types.dart lib/state/wish_repository.dart \
        lib/pages/banner_page.dart lib/pages/app_shell.dart
git commit -m "refactor(gacha-types): use i18n keys and add pity thresholds"
```

---

## Task 10: StatCard widget with TDD

**Files:**
- Create: `lib/widgets/cards/stat_card.dart`
- Create: `test/widgets/cards/stat_card_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/widgets/cards/stat_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';

void main() {
  Widget _wrap(Widget child) => MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(body: child),
      );

  testWidgets('renders label and value', (tester) async {
    await tester.pumpWidget(_wrap(const StatCard(
      label: 'TOTAL',
      value: '428',
    )));
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('428'), findsOneWidget);
  });

  testWidgets('renders subtitle and trailing when provided',
      (tester) async {
    await tester.pumpWidget(_wrap(const StatCard(
      label: 'PITY',
      value: '73 / 90',
      subtitle: 'distance 17',
      trailing: Icon(Icons.trending_up, key: Key('t')),
    )));
    expect(find.text('distance 17'), findsOneWidget);
    expect(find.byKey(const Key('t')), findsOneWidget);
  });

  testWidgets('accent color shows as left border', (tester) async {
    await tester.pumpWidget(_wrap(const StatCard(
      label: 'L',
      value: 'V',
      accent: Color(0xFFE6C477),
    )));
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/cards/stat_card_test.dart`
Expected: FAIL（檔案不存在）。

- [ ] **Step 3: Write StatCard**

```dart
// lib/widgets/cards/stat_card.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.accent,
    this.trailing,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: accent != null
            ? Border(left: BorderSide(color: accent!, width: 3))
            : Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: AppFontSize.display,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: tokens.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.s),
            trailing!,
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/cards/stat_card_test.dart`
Expected: PASS（3 tests）。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/stat_card.dart test/widgets/cards/stat_card_test.dart
git commit -m "feat(widgets): add StatCard primitive"
```

---

## Task 11: ChartCard widget

**Files:**
- Create: `lib/widgets/cards/chart_card.dart`
- Create: `test/widgets/cards/chart_card_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/widgets/cards/chart_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';

void main() {
  testWidgets('renders title and chart child', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: ChartCard(
          title: 'Rarity',
          chart: Center(child: Text('chart-content')),
        ),
      ),
    ));
    expect(find.text('Rarity'), findsOneWidget);
    expect(find.text('chart-content'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/cards/chart_card_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write ChartCard**

```dart
// lib/widgets/cards/chart_card.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.chart,
    this.legend,
    this.height = 220,
  });

  final String title;
  final Widget chart;
  final Widget? legend;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.s),
          Expanded(child: chart),
          if (legend != null) ...[
            const SizedBox(height: AppSpacing.s),
            legend!,
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/cards/chart_card_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/chart_card.dart test/widgets/cards/chart_card_test.dart
git commit -m "feat(widgets): add ChartCard primitive"
```

---

## Task 12: SectionCard and PageHeader

**Files:**
- Create: `lib/widgets/cards/section_card.dart`
- Create: `lib/widgets/page_header.dart`
- Create: `test/widgets/cards/section_card_test.dart`
- Create: `test/widgets/page_header_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/widgets/cards/section_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';

void main() {
  testWidgets('renders title and child', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: SectionCard(
          title: 'Theme',
          child: Text('inside'),
        ),
      ),
    ));
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('inside'), findsOneWidget);
  });
}
```

```dart
// test/widgets/page_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

void main() {
  testWidgets('renders title only', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: PageHeader(title: 'Overview'),
      ),
    ));
    expect(find.text('Overview'), findsOneWidget);
  });

  testWidgets('renders subtitle when provided', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: PageHeader(title: 'Overview', subtitle: 'all banners'),
      ),
    ));
    expect(find.text('all banners'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/cards/section_card_test.dart test/widgets/page_header_test.dart`
Expected: FAIL（檔案不存在）。

- [ ] **Step 3: Write SectionCard**

```dart
// lib/widgets/cards/section_card.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.m),
          child,
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write PageHeader**

```dart
// lib/widgets/page_header.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: tokens.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widgets/cards/section_card_test.dart test/widgets/page_header_test.dart`
Expected: PASS（3 tests）。

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/cards/section_card.dart lib/widgets/page_header.dart \
        test/widgets/cards/section_card_test.dart test/widgets/page_header_test.dart
git commit -m "feat(widgets): add SectionCard and PageHeader primitives"
```

---

## Task 13: Refactor existing chart widgets to use tokens & ChartCard

**Files:**
- Modify: `lib/widgets/rarity_pie.dart`
- Modify: `lib/widgets/item_type_pie.dart`

- [ ] **Step 1: Replace `rarity_pie.dart`**

```dart
// lib/widgets/rarity_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class RarityPie extends StatelessWidget {
  const RarityPie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (stats.total == 0) {
      return Center(
        child: Text(l.statsNoData,
            style: TextStyle(color: tokens.textMuted)),
      );
    }
    final sections = <PieChartSectionData>[
      _section('5★ ${stats.fiveStarCount}', stats.fiveStarCount, tokens.fiveStar),
      _section('4★ ${stats.fourStarCount}', stats.fourStarCount, tokens.fourStar),
      _section('3★ ${stats.threeStarOrBelowCount}',
          stats.threeStarOrBelowCount, tokens.threeStar),
    ].where((s) => s.value > 0).toList(growable: false);

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 32,
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  PieChartSectionData _section(String title, int value, Color color) =>
      PieChartSectionData(
        title: title,
        value: value.toDouble(),
        color: color,
        radius: 60,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
}
```

- [ ] **Step 2: Replace `item_type_pie.dart`**

```dart
// lib/widgets/item_type_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class ItemTypePie extends StatelessWidget {
  const ItemTypePie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (stats.total == 0) {
      return Center(
        child: Text(l.statsNoData,
            style: TextStyle(color: tokens.textMuted)),
      );
    }
    final sections = <PieChartSectionData>[
      _section('${l.kindCharacter} ${stats.characterCount}',
          stats.characterCount, tokens.character),
      _section('${l.kindWeapon} ${stats.weaponCount}',
          stats.weaponCount, tokens.weapon),
      if (stats.unknownCount > 0)
        _section('${l.kindUnknown} ${stats.unknownCount}',
            stats.unknownCount, const Color(0xFF9E9E9E)),
    ].where((s) => s.value > 0).toList(growable: false);

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 32,
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  PieChartSectionData _section(String title, int value, Color color) =>
      PieChartSectionData(
        title: title,
        value: value.toDouble(),
        color: color,
        radius: 60,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
}
```

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/widgets/rarity_pie.dart lib/widgets/item_type_pie.dart`
Expected: No issues。

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/rarity_pie.dart lib/widgets/item_type_pie.dart
git commit -m "refactor(charts): drive colors from GachaTokens and use i18n strings"
```

---

## Task 14: Refactor `EmptyState` with tokens and factories

**Files:**
- Modify: `lib/widgets/empty_state.dart`

- [ ] **Step 1: Replace contents**

```dart
// lib/widgets/empty_state.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  factory EmptyState.noSync(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: l.emptyNoSyncTitle,
      message: l.emptyNoSyncMessage,
      action: action,
    );
  }

  factory EmptyState.noRecords(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.inbox_outlined,
      title: l.emptyNoRecords,
    );
  }

  factory EmptyState.noFiltered(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.search_off_outlined,
      title: l.emptyNoFiltered,
      action: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: tokens.textMuted),
          const SizedBox(height: AppSpacing.l),
          Text(title, style: theme.textTheme.titleLarge),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(message!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: tokens.textMuted)),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.l),
            action!,
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Update callers — `lib/pages/overview_page.dart` & `banner_page.dart`**

把：

```dart
return const EmptyState(
  icon: Icons.cloud_off_outlined,
  title: '尚未同步任何資料',
  message: '點右上「更新資料」開始',
);
```

改成：

```dart
return EmptyState.noSync(context);
```

兩頁皆改。

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/widgets/empty_state.dart lib/pages/`
Expected: No issues。

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/empty_state.dart lib/pages/overview_page.dart lib/pages/banner_page.dart
git commit -m "refactor(empty-state): tokenize and add i18n factories"
```

---

## Task 15: Refactor `UpdateProgressDialog` with tokens, i18n, and Icons

**Files:**
- Modify: `lib/widgets/update_progress_dialog.dart`

- [ ] **Step 1: Replace contents**

```dart
// lib/widgets/update_progress_dialog.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class UpdateProgressDialog extends ConsumerWidget {
  const UpdateProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<UpdateProgress?>(
      wishRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next == null && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
    final progress = ref.watch(
        wishRepositoryProvider.select((s) => s.progress));
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: _Title(progress: progress, l: l, tokens: tokens),
        content: _Body(progress: progress, l: l),
        actions: _actions(context, progress, notifier, l),
      ),
    );
  }

  List<Widget> _actions(
    BuildContext ctx,
    UpdateProgress? p,
    WishRepository r,
    AppLocalizations l,
  ) {
    return switch (p) {
      WaitingForCapture() => [
          TextButton(
            onPressed: () async {
              await r.cancelCapture();
            },
            child: Text(l.actionCancel),
          ),
        ],
      FetchingBanner() => const <Widget>[],
      UpdateCompleted() ||
      UpdateFailed() =>
        [
          TextButton(
            onPressed: r.clearProgress,
            child: Text(l.actionClose),
          ),
        ],
      null => const <Widget>[],
    };
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.progress, required this.l, required this.tokens});
  final UpdateProgress? progress;
  final AppLocalizations l;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (progress) {
      WaitingForCapture() => (Icons.hourglass_top, tokens.textPrimary, l.progressWaiting),
      FetchingBanner() => (Icons.cloud_download_outlined, tokens.textPrimary, l.progressFetching),
      UpdateCompleted() => (Icons.check_circle, tokens.stateSuccess, l.progressDone),
      UpdateFailed() => (Icons.error, tokens.stateDanger, l.progressFailed),
      null => (Icons.info_outline, tokens.textMuted, ''),
    };
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.s),
        Text(text),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.progress, required this.l});
  final UpdateProgress? progress;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    String _resolveBannerName(String key) => switch (key) {
          'gachaTypeCharacter' => l.gachaTypeCharacter,
          'gachaTypeWeapon' => l.gachaTypeWeapon,
          'gachaTypeChronicled' => l.gachaTypeChronicled,
          'gachaTypeStandard' => l.gachaTypeStandard,
          'gachaTypeBeginner' => l.gachaTypeBeginner,
          _ => key,
        };

    return switch (progress) {
      WaitingForCapture(:final isFallback) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.l),
            Text(l.progressOpenGameHint),
            if (isFallback) ...[
              const SizedBox(height: AppSpacing.s),
              Text(l.progressFallbackHint,
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      FetchingBanner(
        :final displayName,
        :final pageIndex,
        :final newRecordsSoFar,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.l),
            Text(l.progressFetchingBanner(_resolveBannerName(displayName))),
            const SizedBox(height: AppSpacing.xs),
            Text(l.progressPageStatus(pageIndex, newRecordsSoFar),
                style: theme.textTheme.bodySmall),
          ],
        ),
      UpdateCompleted(
        :final totalNewRecords,
        :final failedBanners,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.progressDoneSummary(totalNewRecords)),
            if (failedBanners.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                l.progressPartialFailed(
                  failedBanners.map(_resolveBannerName).join('、'),
                ),
                style: TextStyle(color: tokens.stateDanger),
              ),
            ],
          ],
        ),
      UpdateFailed(:final message) => Text(message),
      null => const SizedBox.shrink(),
    };
  }
}
```

> **注意**：原本 `UpdateFailed(:final message)` 的 message 來自 `_friendlyError`，內含中文常數。改進不在本任務範圍 — 仍直接顯示原訊息。後續可改成「key」。

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/widgets/update_progress_dialog.dart`
Expected: No issues。

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/update_progress_dialog.dart
git commit -m "refactor(progress-dialog): tokenize, i18n, replace emoji with icons"
```

---

## Task 16: Refactor `record_list_table.dart` to tokens (behavior unchanged)

**Files:**
- Modify: `lib/widgets/record_list_table.dart`

- [ ] **Step 1: Apply token + i18n + pill changes**

把整檔重寫如下：

```dart
// lib/widgets/record_list_table.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class RecordListTable extends StatefulWidget {
  const RecordListTable({super.key, required this.records});
  final List<WishRecord> records;

  @override
  State<RecordListTable> createState() => _RecordListTableState();
}

class _RecordListTableState extends State<RecordListTable> {
  static const _pageSize = 20;
  int _page = 0;

  @override
  void didUpdateWidget(RecordListTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      _page = 0;
    }
  }

  int get _totalPages =>
      (widget.records.length / _pageSize).ceil().clamp(1, 9999);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (widget.records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Center(child: Text(l.emptyNoRecords)),
      );
    }
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.records.length);
    final slice = widget.records.sublist(start, end);
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceCard,
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _HeaderRow(theme: theme, tokens: tokens, l: l),
              for (var i = 0; i < slice.length; i++)
                _DataRow(
                  record: slice[i],
                  isStripe: i.isOdd,
                  theme: theme,
                  tokens: tokens,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        _Pager(
          page: _page,
          totalPages: _totalPages,
          onChanged: (p) => setState(() => _page = p),
          l: l,
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.theme, required this.tokens, required this.l});
  final ThemeData theme;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: tokens.textSecondary,
    );
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: AppSpacing.m, horizontal: AppSpacing.l),
      color: tokens.surfaceCardHigh,
      child: DefaultTextStyle.merge(
        style: style ?? const TextStyle(),
        child: Row(
          children: [
            Expanded(flex: 4, child: Text(l.tableTime)),
            Expanded(flex: 5, child: Text(l.tableName)),
            Expanded(flex: 2, child: Text(l.tableKind)),
            Expanded(flex: 2, child: Text(l.tableRarity)),
          ],
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.record,
    required this.isStripe,
    required this.theme,
    required this.tokens,
  });
  final WishRecord record;
  final bool isStripe;
  final ThemeData theme;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final accent = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => null,
    };
    final highlight = accent == null
        ? null
        : TextStyle(color: accent, fontWeight: FontWeight.bold);
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: AppSpacing.m, horizontal: AppSpacing.l),
      color: isStripe ? tokens.surfaceCardHigh : null,
      child: Row(
        children: [
          if (accent != null)
            Container(width: 2, height: 28, color: accent)
          else
            const SizedBox(width: 2),
          const SizedBox(width: AppSpacing.s),
          Expanded(flex: 4, child: Text(_formatTime(record.time))),
          Expanded(flex: 5, child: Text(record.name, style: highlight)),
          Expanded(flex: 2, child: Text(record.itemType)),
          Expanded(
            flex: 2,
            child: accent != null
                ? _RarityPill(rank: record.rankType, color: accent)
                : Text('${record.rankType}★'),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _RarityPill extends StatelessWidget {
  const _RarityPill({required this.rank, required this.color});
  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '$rank★',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.totalPages,
    required this.onChanged,
    required this.l,
  });
  final int page;
  final int totalPages;
  final void Function(int) onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: page > 0 ? () => onChanged(page - 1) : null,
          child: Text(l.actionPrevPage),
        ),
        const SizedBox(width: AppSpacing.l),
        Text('${page + 1} / $totalPages'),
        const SizedBox(width: AppSpacing.l),
        TextButton(
          onPressed: page + 1 < totalPages ? () => onChanged(page + 1) : null,
          child: Text(l.actionNextPage),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/widgets/record_list_table.dart`
Expected: No issues。

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/record_list_table.dart
git commit -m "refactor(record-list-table): tokenize and add rarity pill (behavior unchanged)"
```

---

## Task 17: Refactor `UidIndicator` for tokens & i18n

**Files:**
- Modify: `lib/widgets/uid_indicator.dart`

- [ ] **Step 1: Replace contents**

```dart
// lib/widgets/uid_indicator.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class UidIndicator extends ConsumerWidget {
  const UidIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wishRepositoryProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final activeUid = state.activeUid;
    final knownUids = state.knownUids.toList(growable: false);
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

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
        for (final uid in knownUids)
          PopupMenuItem<String>(
            value: uid,
            child: Row(children: [
              Icon(
                uid == activeUid
                    ? Icons.check
                    : Icons.radio_button_unchecked,
                size: 16,
                color: uid == activeUid
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
              const SizedBox(width: AppSpacing.s),
              Text(uid),
              if (uid == activeUid) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(l.uidActiveSuffix,
                    style: TextStyle(
                        fontSize: 11, color: tokens.textMuted)),
              ],
            ]),
          ),
        if (knownUids.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__recapture__',
          child: Row(children: [
            const Icon(Icons.refresh, size: 16),
            const SizedBox(width: AppSpacing.s),
            Text(l.uidRecapture),
          ]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(activeUid ?? l.uidNotSynced),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/widgets/uid_indicator.dart`
Expected: No issues。

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/uid_indicator.dart
git commit -m "refactor(uid-indicator): tokenize and i18n"
```

---

## Task 18: Add `/settings` route with fade transition

**Files:**
- Modify: `lib/routing/app_router.dart`

- [ ] **Step 1: Replace contents**

```dart
// lib/routing/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:genshin_impact_wish_gacha_analyzer/pages/app_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/banner_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/overview_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';

GoRouter buildAppRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (_, _) => _fade(const OverviewPage()),
            ),
            GoRoute(
              path: '/banner/:type',
              pageBuilder: (_, state) => _fade(
                BannerPage(gachaType: state.pathParameters['type']!),
              ),
            ),
            GoRoute(
              path: '/settings',
              pageBuilder: (_, _) => _fade(const SettingsPage()),
            ),
          ],
        ),
      ],
    );

CustomTransitionPage<T> _fade<T>(Widget child) => CustomTransitionPage<T>(
      child: child,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, animation, _, child) =>
          MediaQuery.of(_).disableAnimations
              ? child
              : FadeTransition(opacity: animation, child: child),
    );
```

- [ ] **Step 2: Verify route requires `SettingsPage`**

`SettingsPage` 在下一個 task 才會被建立；此 task 結束時 import 會 unresolved。**故下一個 task（19）必須緊接著做才不會留 broken state**。實際 commit 在 Task 19 結束後一起 commit；本 task 暫不 commit。

> **Plan note**：Task 18 + Task 19 視為 atomic。只在 Task 19 結尾 commit。

---

## Task 19: Create SettingsPage (theme + language working, others placeholder)

**Files:**
- Create: `lib/pages/settings_page.dart`

- [ ] **Step 1: Write SettingsPage**

```dart
// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(title: l.settingsTitle),
              SectionCard(
                title: l.settingsAppearance,
                child: _ThemeRadios(
                  current: settings.themeMode,
                  onChanged: notifier.setThemeMode,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsLanguage,
                child: _LocaleDropdown(
                  current: settings.locale,
                  onChanged: notifier.setLocale,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsDataManagement,
                child: Text(l.settingsPlaceholderPhase2,
                    style: TextStyle(
                        color: Theme.of(context).gacha.textMuted)),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAccountManagement,
                child: Text(l.settingsPlaceholderPhase2,
                    style: TextStyle(
                        color: Theme.of(context).gacha.textMuted)),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAbout,
                child: _AboutContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeRadios extends StatelessWidget {
  const _ThemeRadios({
    required this.current,
    required this.onChanged,
    required this.l,
  });
  final AppThemeMode current;
  final ValueChanged<AppThemeMode> onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in {
          AppThemeMode.system: l.settingsThemeSystem,
          AppThemeMode.dark: l.settingsThemeDark,
          AppThemeMode.light: l.settingsThemeLight,
        }.entries)
          RadioListTile<AppThemeMode>(
            title: Text(entry.value),
            value: entry.key,
            groupValue: current,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            contentPadding: EdgeInsets.zero,
          ),
      ],
    );
  }
}

class _LocaleDropdown extends StatelessWidget {
  const _LocaleDropdown({
    required this.current,
    required this.onChanged,
    required this.l,
  });
  final AppLocale current;
  final ValueChanged<AppLocale> onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AppLocale>(
      initialValue: current,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        DropdownMenuItem(
            value: AppLocale.system, child: Text(l.settingsLocaleSystem)),
        DropdownMenuItem(
            value: AppLocale.zhHant, child: Text(l.settingsLocaleZhHant)),
        DropdownMenuItem(
            value: AppLocale.zhHans, child: Text(l.settingsLocaleZhHans)),
        DropdownMenuItem(value: AppLocale.en, child: Text(l.settingsLocaleEn)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _AboutContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final version = ref.watch(appVersionProvider);
    return Text(l.settingsAboutVersion(version));
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`
Expected: No issues。

- [ ] **Step 3: Commit (Task 18 + 19 一起)**

```bash
git add lib/routing/app_router.dart lib/pages/settings_page.dart
git commit -m "feat(settings): add SettingsPage with theme/locale switchers and fade routing"
```

---

## Task 20: Update `AppShell` with rail spacer + settings entry + breakpoint logic

**Files:**
- Modify: `lib/pages/app_shell.dart`

- [ ] **Step 1: Replace contents**

```dart
// lib/pages/app_shell.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/update_progress_dialog.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateProgress?>(
      wishRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next != null && !_dialogOpen) {
          _dialogOpen = true;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const UpdateProgressDialog(),
          ).whenComplete(() {
            _dialogOpen = false;
          });
        }
      },
    );

    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final location = GoRouterState.of(context).uri.path;
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));
    final width = MediaQuery.of(context).size.width;
    final extendedRail = width >= 1180;
    final showFooter = location != '/settings';
    final version = ref.watch(appVersionProvider);

    final isSettingsActive = location == '/settings';
    final selectedIndex =
        isSettingsActive ? null : _bannerIndexFromLocation(location);

    return Scaffold(
      appBar: AppBar(
        title: Text('${l.appName} v$version'),
        actions: [
          const UidIndicator(),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l.actionUpdate),
              onPressed: () async {
                await ref.read(wishRepositoryProvider.notifier).update();
              },
            ),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Row(
            children: [
              _Rail(
                selectedIndex: selectedIndex,
                isSettingsActive: isSettingsActive,
                extended: extendedRail,
                l: l,
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: widget.child),
            ],
          ),
        ),
        if (showFooter)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.l, vertical: AppSpacing.xs * 1.5),
            color: tokens.surfaceCardHigh,
            child: Text(
              activeData == null
                  ? l.footerNotSynced
                  : l.footerLastUpdated(
                      DateFormat('yyyy-MM-dd HH:mm')
                          .format(activeData.lastUpdated.toLocal()),
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ]),
    );
  }

  int _bannerIndexFromLocation(String path) {
    if (path == '/') return 0;
    if (path.startsWith('/banner/')) {
      final type = path.substring('/banner/'.length);
      final i = gachaTypes.indexWhere((t) => t.gachaType == type);
      return i < 0 ? 0 : i + 1;
    }
    return 0;
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.selectedIndex,
    required this.isSettingsActive,
    required this.extended,
    required this.l,
  });
  final int? selectedIndex;
  final bool isSettingsActive;
  final bool extended;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationRailDestination>[
      NavigationRailDestination(
        icon: const Icon(Icons.dashboard_outlined),
        selectedIcon: const Icon(Icons.dashboard),
        label: Text(l.navOverview),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: Text(l.navCharacter),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.shield_outlined),
        selectedIcon: const Icon(Icons.shield),
        label: Text(l.navWeapon),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.collections_bookmark_outlined),
        selectedIcon: const Icon(Icons.collections_bookmark),
        label: Text(l.navChronicled),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.history),
        selectedIcon: const Icon(Icons.history_toggle_off),
        label: Text(l.navStandard),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.school_outlined),
        selectedIcon: const Icon(Icons.school),
        label: Text(l.navBeginner),
      ),
    ];

    return IntrinsicHeight(
      child: Column(
        children: [
          Expanded(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => _go(context, i),
              extended: extended,
              labelType:
                  extended ? null : NavigationRailLabelType.all,
              destinations: destinations,
              trailing: const Spacer(),
            ),
          ),
          // 設定入口（與其他 destination 視覺分隔）
          _SettingsRailButton(
            active: isSettingsActive,
            extended: extended,
            label: l.navSettings,
            onPressed: () => context.go('/settings'),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
      ),
    );
  }

  void _go(BuildContext context, int i) {
    if (i == 0) {
      context.go('/');
    } else {
      final type = gachaTypes[i - 1].gachaType;
      context.go('/banner/$type');
    }
  }
}

class _SettingsRailButton extends StatelessWidget {
  const _SettingsRailButton({
    required this.active,
    required this.extended,
    required this.label,
    required this.onPressed,
  });
  final bool active;
  final bool extended;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final color = active
        ? Theme.of(context).colorScheme.primary
        : tokens.textSecondary;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.m, horizontal: AppSpacing.s),
          child: extended
              ? Row(children: [
                  const SizedBox(width: AppSpacing.xs),
                  Icon(active ? Icons.settings : Icons.settings_outlined,
                      color: color),
                  const SizedBox(width: AppSpacing.m),
                  Text(label, style: TextStyle(color: color)),
                ])
              : Column(children: [
                  Icon(active ? Icons.settings : Icons.settings_outlined,
                      color: color),
                  const SizedBox(height: AppSpacing.xs),
                  Text(label,
                      style: TextStyle(color: color, fontSize: 11)),
                ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/pages/app_shell.dart`
Expected: No issues。

- [ ] **Step 3: Smoke test**

Run: `flutter run -d windows`（手動）
Expected:
- 進入後左 Rail 看到 6 個 destination + 底部設定入口（有上分隔線）
- 點設定 → 切到 SettingsPage、底部 footer 隱藏
- 切主題（system/dark/light）即時生效
- 切語言 → 文字切換（zh-Hans / en 大量繁中是預期，placeholder）

關閉。

- [ ] **Step 4: Commit**

```bash
git add lib/pages/app_shell.dart
git commit -m "refactor(app-shell): add settings rail entry and 1180px breakpoint"
```

---

## Task 21: Refactor OverviewPage to Bento layout

**Files:**
- Modify: `lib/pages/overview_page.dart`

- [ ] **Step 1: Replace contents**

```dart
// lib/pages/overview_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

    if (activeData == null) {
      return EmptyState.noSync(context);
    }
    final all = activeData.allRecords;
    final stats = computeWishStats(all);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: l.pageOverviewTitle),

          // Row 1: 三聯 Stat 卡（無保底，因綜合頁不適用）
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1024;
            final mid = c.maxWidth >= 800 && c.maxWidth < 1024;
            return Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 6 / 12
                      : (mid ? c.maxWidth : c.maxWidth),
                  child: StatCard(
                    label: l.statsTotal,
                    value: '${stats.total}',
                    accent: tokens.accentPrimary,
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
                      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
                  child: StatCard(
                    label: l.statsFiveStarRate,
                    value: '${stats.fiveStarCount}',
                    accent: tokens.fiveStar,
                    subtitle:
                        '${(stats.fiveStarRate * 100).toStringAsFixed(2)}%',
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
                      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
                  child: StatCard(
                    label: l.statsFourStarRate,
                    value: '${stats.fourStarCount}',
                    accent: tokens.fourStar,
                    subtitle:
                        '${(stats.fourStarRate * 100).toStringAsFixed(2)}%',
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: AppSpacing.l),

          // Row 2: 兩 Pie + Timeline placeholder（Phase 2 才填 timeline）
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1024;
            final col = wide ? 3 : (c.maxWidth >= 800 ? 2 : 1);
            final tileWidth = col == 1
                ? c.maxWidth
                : (c.maxWidth - AppSpacing.m * (col - 1)) / col;
            return Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: ChartCard(
                    title: '${l.statsFiveStarRate} / ${l.statsFourStarRate} / ${l.statsThreeStarRate}',
                    chart: RarityPie(stats: stats),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: ChartCard(
                    title: '${l.kindCharacter} / ${l.kindWeapon}',
                    chart: ItemTypePie(stats: stats),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: ChartCard(
                    title: '5★',
                    chart: Center(
                      child: Text(l.settingsPlaceholderPhase2,
                          style: TextStyle(color: tokens.textMuted)),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/pages/overview_page.dart`
Expected: No issues。

- [ ] **Step 3: Commit**

```bash
git add lib/pages/overview_page.dart
git commit -m "refactor(overview-page): use bento layout with StatCard + ChartCard"
```

---

## Task 22: Refactor BannerPage to Bento layout

**Files:**
- Modify: `lib/pages/banner_page.dart`

- [ ] **Step 1: Replace contents**

```dart
// lib/pages/banner_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/record_list_table.dart';

class BannerPage extends ConsumerWidget {
  const BannerPage({super.key, required this.gachaType});

  final String gachaType;

  GachaType _resolveType() => gachaTypes.firstWhere(
        (t) => t.gachaType == gachaType,
        orElse: () => GachaType(
          gachaType: gachaType,
          nameKey: gachaType,
          fiveStarPity: 90,
          fourStarPity: 10,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

    if (activeData == null) {
      return EmptyState.noSync(context);
    }
    final type = _resolveType();
    final records = activeData.banners[gachaType] ?? const [];
    final stats = computeWishStats(records);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: type.resolveName(l)),

          // Row 1: 三聯 Stat 卡（Phase 1 還是 placeholder pity，純展示 5★/4★ 數）
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1024;
            final mid = c.maxWidth >= 800 && c.maxWidth < 1024;
            return Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 6 / 12
                      : c.maxWidth,
                  child: StatCard(
                    label: l.statsFiveStarRate,
                    value: '${stats.fiveStarCount} / ${type.fiveStarPity}',
                    accent: tokens.fiveStar,
                    subtitle: l.settingsPlaceholderPhase2,
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
                      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
                  child: StatCard(
                    label: l.statsFourStarRate,
                    value: '${stats.fourStarCount}',
                    accent: tokens.fourStar,
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
                      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
                  child: StatCard(
                    label: l.statsTotal,
                    value: '${stats.total}',
                    accent: tokens.accentPrimary,
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: AppSpacing.l),

          // Row 2: 兩 Pie + Timeline placeholder
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1024;
            final col = wide ? 3 : (c.maxWidth >= 800 ? 2 : 1);
            final tileWidth = col == 1
                ? c.maxWidth
                : (c.maxWidth - AppSpacing.m * (col - 1)) / col;
            return Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: ChartCard(
                    title: l.statsFiveStarRate,
                    chart: RarityPie(stats: stats),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: ChartCard(
                    title: '${l.kindCharacter} / ${l.kindWeapon}',
                    chart: ItemTypePie(stats: stats),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: ChartCard(
                    title: '5★',
                    chart: Center(
                      child: Text(l.settingsPlaceholderPhase2,
                          style: TextStyle(color: tokens.textMuted)),
                    ),
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: AppSpacing.xl),
          Text(l.pageBannerRecordList,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.s),
          RecordListTable(records: records),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/pages/banner_page.dart`
Expected: No issues。

- [ ] **Step 3: Commit**

```bash
git add lib/pages/banner_page.dart
git commit -m "refactor(banner-page): use bento layout with StatCard + ChartCard + existing record table"
```

---

## Task 23: Remove deprecated `stats_panel.dart` and `GachaColors`

`stats_panel.dart` 在 Task 21/22 已被 StatCard 取代，沒有 callers 了；`GachaColors` 也只是過渡。確認無 caller 後刪除。

**Files:**
- Delete: `lib/widgets/stats_panel.dart`
- Modify: `lib/theme/app_theme.dart`（移除 `GachaColors` deprecated wrapper）

- [ ] **Step 1: Verify no callers**

Run: `grep -rn "stats_panel" lib/ test/` → 應該無結果（除 import 殘留）。
Run: `grep -rn "GachaColors" lib/ test/` → 應該無結果。

如有殘留，移除對應 import / usage 後再繼續。

- [ ] **Step 2: Delete `stats_panel.dart`**

```bash
rm lib/widgets/stats_panel.dart
```

- [ ] **Step 3: Edit `app_theme.dart` to remove `GachaColors`**

把 `GachaColors` 整個 abstract class 區塊刪除。剩下：

```dart
// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

ThemeData buildDarkTheme() => _buildTheme(
      brightness: Brightness.dark,
      tokens: GachaTokens.dark,
    );

ThemeData buildLightTheme() => _buildTheme(
      brightness: Brightness.light,
      tokens: GachaTokens.light,
    );

// _buildTheme 不變
```

- [ ] **Step 4: Run analyze + tests**

Run: `flutter analyze`
Expected: No issues。

Run: `flutter test`
Expected: All tests pass。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/stats_panel.dart lib/theme/app_theme.dart
git commit -m "chore: remove deprecated stats_panel and GachaColors wrapper"
```

---

## Task 24: Final smoke test & verification

**Files:**
- 無新增 / 修改

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass，無 skipped/failed。

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Build + run**

Run: `flutter run -d windows`

手動 checklist：
- [ ] 啟動成功，視覺是深藍夜空（dark）或白底（light）
- [ ] 系統切換 dark/light 應用即時跟隨
- [ ] AppBar 標題用 i18n（appName）
- [ ] Rail 6 個 destination + 底部「設定」入口、有上分隔線
- [ ] 點 / → OverviewPage 顯示 PageHeader + 三 StatCard + 三 ChartCard（timeline 是 placeholder）
- [ ] 點任一卡池 → BannerPage 顯示三 StatCard（5★ 是 X / 90 placeholder）+ 三 ChartCard + 紀錄列表（pill 樣式）
- [ ] 點 設定 → SettingsPage：主題切（system/dark/light）即時生效；語言 dropdown 切 zh-Hant 顯示繁中、切 en 大部分仍是繁中（placeholder，預期）；主題與語言重啟後仍持久
- [ ] AppBar 「更新資料」按鈕仍可進入既有攔截流程（dialog 樣式換成 Icon、不再有 emoji）
- [ ] Footer 在 settings 頁隱藏，其他頁顯示
- [ ] 切換頁面有 200ms fade

關閉應用程式。

- [ ] **Step 4: Commit if any tweaks needed**

如果上面 checklist 任一項失敗 → **不算 phase 1 完成**。修到通過再 commit；無問題則跳此步驟。

---

## Phase 1 Done

- 視覺：tokens、dark/light、bento layout 套上
- 架構：i18n 完整搬移、settings 持久化
- 設定頁：主題與語言切換可用，其他區塊 placeholder
- 既有功能：完全沒退化（攔截、抓取、儲存、UID 切換）
- 待 Phase 2：PityCard、TimelineCard、SortableTable、SearchFilterBar、設定頁的資料管理 / 帳號管理 / 完整關於

下一步：等 Phase 1 ship 後，再呼叫 `superpowers:writing-plans` 建立 Phase 2 計畫（context 才會準確）。

---

## Self-Review

**1. Spec coverage** — 對照 design doc 14 節：
- §2 視覺語言 → Task 3, 4
- §3 IA / 路由 → Task 18 (route), Task 20 (Rail)
- §4 頁面版面 → Task 19 (settings), Task 20 (shell), Task 21 (overview), Task 22 (banner)
- §5 元件庫（卡片原件） → Task 10, 11, 12 / Empty (Task 14) / record table (Task 16) / dialog (Task 15)
- §5 退役清單 → Task 23
- §6 計算邏輯（pity / filter） → **不在 Phase 1 範圍**（已標 placeholder）
- §7 狀態管理（settingsProvider 等） → Task 6
- §8 持久化 → Task 5
- §9 i18n → Task 2, 7
- §10 邊界狀態（empty） → Task 14
- §11 階段拆分 → 整份計畫即 Phase 1
- §12 測試策略 → Task 5, 6, 10, 11, 12 含 test
- §13 新增依賴 → Task 1
- §14 YAGNI → 已遵守（沒做不必要的 motion / golden tests / 平台支援）

**2. Placeholder scan** — 全文搜尋 `TBD` / `TODO` / `implement later` / `Add appropriate` / `Similar to Task` → 無匹配。

**3. Type consistency** — `GachaType` 新欄位 `nameKey` / `fiveStarPity` / `fourStarPity` 在 Task 9 定義，Task 22 使用 `type.fiveStarPity` 與 `type.resolveName(l)`，一致。`AppThemeMode` / `AppLocale` enum 在 Task 5 定義，Task 6, 19 使用，一致。`AppSettings` 在 Task 5 定義，Task 6 使用。`GachaTokens` 欄位在 Task 3 定義，Task 4, 10–22 使用，名稱一致（`fiveStar` / `fourStar` / `surfaceCard` / `borderSubtle` / `accentPrimary` 等）。

**4. Ambiguity** — 無重大 ambiguity。Task 7 的 zh-Hans / en placeholder 策略明確（用 zh-Hant 字面值佔位）。Task 18 + 19 的 atomic commit 已標註。
