# Spec:綜合頁區塊視覺分隔 + 空狀態保護

- 日期:2026-05-14
- 分支:`flutter-rewrite`
- 來源:使用者要求綜合頁「祈願綜合」與「頌願綜合」兩區塊在視覺上明顯分開,且任一區塊沒資料時要保留區塊標題、僅在內容區顯示「尚無...」。

## 1. 背景

`lib/pages/overview_page.dart` 的 `OverviewPage` 目前流程:

1. `PageHeader`
2. `_OverviewSection`(祈願綜合)
3. `SizedBox(height: AppSpacing.xl)`
4. 若 `odesAll.isEmpty` → 整段換成 `Padding + EmptyState.noOdesRecords`(滿屏置中、icon 72px);否則 `_OverviewSection`(頌願綜合)

問題:

- 兩區塊之間只有 24px 空白,視覺辨識度不足。
- 頌願沒資料時整個 section 標題消失,只剩一個浮在頁面中央的大 EmptyState,跟祈願區塊在版面上完全不對稱、語意也不清楚(看起來像「頁面狀態」而非「頌願段落內的狀態」)。
- 祈願完全沒資料的情境目前未保護(雖然 `activeData == null` 已在外層攔截,但個別玩家若僅匯入頌願、祈願為空,行為未定義)。

## 2. 目標

1. **兩 section 之間插入 Divider**,加上下呼吸間距,視覺明顯分開。
2. **任一 section 沒資料時保留標題**,內容區改顯示縮小版的空狀態 placeholder(icon 40px + 文字,實線邊框框出範圍)。
3. 祈願、頌願**行為對稱**,使用同一個 `EmptyState` factory,僅 title 文案差異。
4. **EmptyState API 簡化**:移除 `EmptyState.noOdesRecords` factory,改用 `EmptyState.noRecords` 加 title override + compact mode。

## 3. 非目標(YAGNI)

- 不改 `EmptyState.noSync` / `EmptyState.noFiltered` 既有 factory。
- 不為 `PageHeader` / `InlineSectionTitle` / Theme tokens 加新屬性。
- 不改 `banner_page.dart` 既有 `EmptyState.noRecords(context)` 呼叫(那是「該卡池無紀錄」場景,非 compact)。
- 不引入虛線邊框套件 — 採實線 1px `borderSubtle`。
- 不額外新建 `SectionEmptyPlaceholder` widget — 統一在 `EmptyState` 內以 `compact` 變體呈現。

## 4. 設計

### 4.1 `EmptyState` 擴充:`compact` 變體 + `noRecords` title override

`lib/widgets/empty_state.dart`:

```dart
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// 縮小版:用於「頁面內某個 section 的空位佔位」(icon 40px + 邊框框出範圍),
  /// 非滿屏置中。
  final bool compact;

  factory EmptyState.noSync(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: l.emptyNoSyncTitle,
      message: l.emptyNoSyncMessage,
      action: action,
    );
  }

  /// `title` 可選 override 既定 `l.emptyNoRecords`,讓不同 section 共用此 factory。
  /// `compact: true` 時改為縮小版邊框 placeholder,非滿屏。
  factory EmptyState.noRecords(
    BuildContext context, {
    String? title,
    bool compact = false,
  }) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.inbox_outlined,
      title: title ?? l.emptyNoRecords,
      compact: compact,
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

  // factory EmptyState.noOdesRecords ← 移除

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl,
          horizontal: AppSpacing.l,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: tokens.textMuted),
            const SizedBox(height: AppSpacing.s),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.m),
              action!,
            ],
          ],
        ),
      );
    }

    // 既有滿屏版(icon 72px、Center)— 完全不變
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: tokens.textMuted),
          const SizedBox(height: AppSpacing.l),
          Text(title, style: theme.textTheme.titleLarge),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
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

設計取捨:

- **不新增 `SectionEmptyPlaceholder` widget**:`EmptyState` 內以 `compact` 變體承擔「section 內小型空狀態」職責,所有空狀態場景統一一個 widget、一組 factory,呼叫端不必選 widget。
- **`compact` 內仍保留 `message` / `action` 分支**:雖然這次祈願/頌願都不用,但留著對應既有 API,避免 compact 模式有功能缺口。

### 4.2 ARB 新增 `emptyNoWishRecords`

範圍:**僅 3 份 ARB 動 key**,其餘 7 份(`zh` / `ja` / `es` / `fr` / `pt` / `th` / `vi`)由 Flutter gen-l10n fallback 到 `zh_Hant`(template)。

| 檔案 | key 值 |
|---|---|
| `app_zh_Hant.arb`(template) | `"emptyNoWishRecords": "尚無祈願記錄"` |
| `app_zh_Hans.arb` | `"emptyNoWishRecords": "尚无祈愿记录"` |
| `app_en.arb` | `"emptyNoWishRecords": "No wish records yet"` |

> **副作用**:`ja` / `es` / `fr` / `pt` / `th` / `vi` 在祈願綜合空狀態這一行會 fallback 顯示繁中。可接受 — 對齊 `2026-05-14-banner-average-pulls-design.md` 已採過相同做法。

既有 `emptyNoOdesRecords`(8 語系皆有)**保留不動**。

### 4.3 `_OverviewSection` 加 empty 保護

`lib/pages/overview_page.dart` 內 `_OverviewSection`:

- 增加一個必填參數 `emptyTitle`(由 `OverviewPage` 傳入)。
- `build()` 開頭判斷 `final hasData = banners.values.any((r) => r.isNotEmpty);`
- `hasData == false` → 只 render `InlineSectionTitle` + `SizedBox(height: m)` + `EmptyState.noRecords(context, title: emptyTitle, compact: true)`,後續 stat / pie / bar / timeline 全部跳過。

```dart
@override
Widget build(BuildContext context) {
  final l = AppLocalizations.of(context)!;
  final tokens = Theme.of(context).gacha;
  final hasData = banners.values.any((r) => r.isNotEmpty);

  if (!hasData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineSectionTitle(icon: Icons.summarize_outlined, title: title),
        const SizedBox(height: AppSpacing.m),
        EmptyState.noRecords(context, title: emptyTitle, compact: true),
      ],
    );
  }

  // ...既有 stat / pie / bar / timeline 結構不變
}
```

### 4.4 `OverviewPage` 分隔線 + 移除早返

```dart
return SingleChildScrollView(
  padding: const EdgeInsets.all(AppSpacing.l),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeader(title: l.pageOverviewTitle, icon: Icons.dashboard_outlined),
      _OverviewSection(
        title: l.pageOverviewWishSection,
        types: wishTypes,
        banners: wishBanners,
        stats: wishStats,
        bannerColors: bannerColors,
        statCards: wishStatCards,
        emptyTitle: l.emptyNoWishRecords,
      ),
      const SizedBox(height: AppSpacing.xl),
      Divider(color: tokens.borderEmphasis, height: 1, thickness: 1),
      const SizedBox(height: AppSpacing.xl),
      _OverviewSection(
        title: l.pageOverviewOdesSection,
        types: odesTypes,
        banners: odesBanners,
        stats: odesStats,
        bannerColors: bannerColors,
        statCards: odesStatCards,
        emptyTitle: l.emptyNoOdesRecords,
      ),
    ],
  ),
);
```

設計取捨:

- **Divider 放 `OverviewPage` 而非 `_OverviewSection` 內**:section 不需要知道自己在哪個位置;`OverviewPage` 控制版面、section 控制內容,職責分離。
- **保留 `wishStatCards` / `odesStatCards` 的計算**:即使 `!hasData` 時 section 不會用到它們,計算成本可忽略(`computeWishStats(empty list)` 直接回 0),不為這個 fast path 加 lazy 邏輯(YAGNI)。
- **頌願原本的 `Padding(... EmptyState.noOdesRecords)` 早返完全移除**。

### 4.5 noOdesRecords factory 移除清單

| 位置 | 動作 |
|---|---|
| `lib/widgets/empty_state.dart:44-50` | 整個 `factory EmptyState.noOdesRecords` 區塊移除 |
| `lib/pages/overview_page.dart:152-156` | `if (odesAll.isEmpty) Padding(...)` 早返區塊移除,改走 `_OverviewSection` 路徑 |

ARB key `emptyNoOdesRecords` **不**從 ARB 檔移除 — `OverviewPage._OverviewSection` 改用 `l.emptyNoOdesRecords` 當 `emptyTitle` 傳入,翻譯仍會用到。

## 5. 測試

### 5.1 新增 `test/widgets/empty_state_test.dart`

EmptyState 過去沒有獨立測試,本次新增,聚焦 `compact` 變體:

| Test case | 驗證點 |
|---|---|
| `compact = false renders 72px icon centered` | 取 `Icon`,`size == 72`;`Center` widget 出現 |
| `compact = true renders 40px icon with bordered container` | 取 `Icon`,`size == 40`;最外層 `Container` 的 `decoration.border` 顏色為 `tokens.borderSubtle`、radius 為 `AppRadius.md`;**不**在 `Center` 內 |
| `EmptyState.noRecords applies title override` | 傳 `title: 'X'` → 找得到 `find.text('X')`,找不到 `l.emptyNoRecords` 預設文字 |
| `EmptyState.noRecords without override uses default` | 不傳 `title` → 找得到 `l.emptyNoRecords` 文字 |
| `EmptyState.noRecords compact toggles compact mode` | 傳 `compact: true` → `Icon.size == 40` |

### 5.2 既有測試

確認以下仍綠:
- `test/widgets/inline_section_title_test.dart`
- `test/services/wish_stats_test.dart`(`computeWishStats(empty)` 行為應已覆蓋)

## 6. 提交前品質檢查

依 `CLAUDE.md`:

1. `flutter gen-l10n`(新增了 ARB key,需重生 `app_localizations*.dart`)
2. `dart format lib/ test/`
3. `flutter analyze` → `No issues found!`
4. `flutter test` → `All tests passed!`

## 7. 風險與權衡

- **`EmptyState` 內邏輯分支增加**:加 `compact` flag 後 `build` 有兩條路徑。可接受 — 兩條路徑都不複雜,且職責語意一致(都是「空狀態」)。
- **`_OverviewSection` 新增一個必填參數**:呼叫端只有 `OverviewPage` 兩處,改動範圍封閉。
- **7 語系翻譯 fallback 到繁中**:祈願空狀態文案,`zh` / `ja` / `es` / `fr` / `pt` / `th` / `vi` 暫時顯示「尚無祈願記錄」。已徵得使用者同意,對齊既有 `pityAverageInterval` 採法。
