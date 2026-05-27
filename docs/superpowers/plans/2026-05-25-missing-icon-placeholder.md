# Missing-icon Placeholder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `GachaItemIcon` 缺 icon 時的 `_Placeholder` 從純色方塊升級為「純色方塊 + 中央 `?`」，讓使用者一眼看出這格是 placeholder 而非真實 icon。

**Architecture:** 只動 `lib/widgets/gacha_item_icon.dart` 的 private `_Placeholder.build`：在現有 `Container` 內加一個 `Center(child: Icon(Icons.question_mark, size: size * 0.55, color: accent))`。其餘 `Container` 屬性（依稀有度 tint 的底色 / 邊框 / 圓角）全數沿用。零外部 API 變動。

**Tech Stack:** Flutter / `flutter_test`（widget test，既有 `test/widgets/gacha_item_icon_test.dart` 已涵蓋 placeholder 觸發路徑）。

**Spec:** `docs/superpowers/specs/2026-05-25-missing-icon-placeholder-design.md`

---

## File Structure

- **Modify** `lib/widgets/gacha_item_icon.dart` — 在 `_Placeholder.build` 的 `Container` 加 `Center + Icon` child。
- **Modify** `test/widgets/gacha_item_icon_test.dart` — 新增一個 `testWidgets`，覆蓋 3 / 4 / 5 星 placeholder 都含 `Icons.question_mark` 與 size = `size * 0.55`。

## Task 1: 加上「placeholder 應含 ? icon」的失敗測試

**Files:**
- Test: `test/widgets/gacha_item_icon_test.dart`（新增一個 group / testWidgets，放在現有 `main()` 內最後一個 testWidgets 之後、`_minimalPng()` 之前）

- [ ] **Step 1: 寫新測試 case**

在 `test/widgets/gacha_item_icon_test.dart` 內，第 239 行（`});` 結束最後一個 testWidgets，正好在 `_minimalPng` 上方）後、`_minimalPng` 宣告之前，新增以下 testWidgets：

```dart
  testWidgets('placeholder 應顯示 Icons.question_mark 且 size = host * 0.55', (
    tester,
  ) async {
    for (final rank in [3, 4, 5]) {
      await tester.pumpWidget(
        _wrap(
          GachaItemIcon(
            record: _rec(
              name: 'Missing $rank',
              gachaType: '301',
              rankType: rank,
            ),
            size: 32,
          ),
          container,
        ),
      );
      final iconFinder = find.byIcon(Icons.question_mark);
      expect(
        iconFinder,
        findsOneWidget,
        reason: 'rank=$rank placeholder 應含 question_mark',
      );
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.size, 32 * 0.55, reason: 'rank=$rank icon size');
    }
  });
```

> 設計重點：
> - 走 `_rec` + `gachaType: '301'`（非頌願）+ 空 index（`setUp` 已建立 empty container）→ 落到 `_Placeholder` 分支。
> - 一個 testWidgets 內 loop 3/4/5 三個稀有度，避免重覆 setup boilerplate。
> - 斷言 `Icons.question_mark` 而非 `Icons.help_outline`（spec 已拍板用前者）。
> - 斷言 `icon.size == size * 0.55`（spec 鎖定比例）。

- [ ] **Step 2: 跑測試確認 fail**

Run:
```powershell
flutter test test/widgets/gacha_item_icon_test.dart --plain-name "placeholder 應顯示 Icons.question_mark"
```

Expected: FAIL — 訊息應類似「Expected: exactly one matching node in the widget tree / Actual: _IconFinder:<zero widgets with icon "IconData(U+0...)">」，因為目前 `_Placeholder` 沒有 child。

- [ ] **Step 3: format + commit 失敗測試**

```powershell
dart format lib/ test/
git add test/widgets/gacha_item_icon_test.dart
git commit -m "test(gacha-item-icon): assert placeholder shows question_mark icon"
```

> 故意先 commit failing test，符合 TDD 紀律也方便 reviewer 看見「先有期待，後有實作」。

---

## Task 2: 實作 `_Placeholder` 內的 `?` icon

**Files:**
- Modify: `lib/widgets/gacha_item_icon.dart`（`_Placeholder.build`，約第 92–108 行）

- [ ] **Step 1: 修改 `_Placeholder.build`**

把 `_Placeholder.build` 的 `return Container(...)` 區塊改為：

```dart
  @override
  Widget build(BuildContext context) {
    final accent = switch (rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => tokens.textMuted,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Icon(
          Icons.question_mark,
          size: size * 0.55,
          color: accent,
        ),
      ),
    );
  }
```

> 與既有版本的 diff：`Container` 多了一個 `child: Center(...)` 參數，內含 `Icon(Icons.question_mark, size: size * 0.55, color: accent)`。其他全部沿用。

- [ ] **Step 2: 更新 `_Placeholder` 的 class dartdoc**

把 `gacha_item_icon.dart` 第 74 行的 dartdoc 從：

```dart
/// 缺 icon 時的固定尺寸方塊；底色依 rank 上色。
```

改為：

```dart
/// 缺 icon 時的固定尺寸方塊；底色依 rank 上色，中央疊一個 `?` icon。
```

> 讓讀者一眼看出這個 widget 現在不只是純方塊。

- [ ] **Step 3: 跑剛剛的失敗測試，確認綠燈**

Run:
```powershell
flutter test test/widgets/gacha_item_icon_test.dart --plain-name "placeholder 應顯示 Icons.question_mark"
```

Expected: PASS — `+1: All tests passed!`

- [ ] **Step 4: 跑整個 widget 測試檔，確認沒打到既有 case**

Run:
```powershell
flutter test test/widgets/gacha_item_icon_test.dart
```

Expected: 全 6 個 testWidgets 通過（5 個既有 + 1 個新增）。

> 既有 case 可能因為 `Container` 內部多了 `Icon` 而被 `find.byType(Image)` 等斷言誤打到？確認過 — 既有斷言是 `find.byType(Image) → findsNothing` / `find.byType(RawImage)`，與 `Icon` 互不干擾。

- [ ] **Step 5: format + commit 實作**

```powershell
dart format lib/ test/
git add lib/widgets/gacha_item_icon.dart
git commit -m "feat(gacha-item-icon): render ? icon on missing-icon placeholder"
```

---

## Task 3: 提交前完整檢查

**Files:** 無變更，純驗證。

- [ ] **Step 1: 完整 format（保險再跑一次，CLAUDE.md 規定不對 `.` 跑）**

Run:
```powershell
dart format lib/ test/
```

Expected: 無檔案被 format（前面已跑過）。若有殘留排版差異，依 CLAUDE.md「Prefer to create a new commit rather than amending」**另建** `style:` commit，不要 `git commit --amend`。

- [ ] **Step 2: `flutter analyze` 必須 `No issues found!`**

Run:
```powershell
flutter analyze
```

Expected: `No issues found! (ran in X.Xs)`

- [ ] **Step 3: 全套 `flutter test`**

Run:
```powershell
flutter test
```

Expected: `All tests passed!`

> 此變動觸及共用 widget，全套跑一次確認分享圖、timeline、sortable_table 既有測試不受影響。memory 提到曾有「全套測試平行 flaky」議題已修，預期穩定。

- [ ] **Step 4: 手動驗證（推薦但非阻擋）**

啟動 app：
```powershell
flutter run -d windows
```

驗證路徑：
- 找一個 HoYoWiki cache 尚未抓到的物品（或臨時清空 hoyowiki cache 目錄）；
- 觀察 timeline / banner page 上 3 / 4 / 5 星 placeholder：底色 + `?` 應分別呈現灰 / 紫 / 金；
- （可選）執行「分享」流程，截圖確認分享圖內 placeholder 也含 `?`。

> memory `feedback_perf_check_release_first.md` 不適用於此項——此處驗證的是視覺正確性，非效能。

- [ ] **Step 5: 結束 — 不主動 push**

CLAUDE.md 規定不主動 `git push`。把控制權交回使用者決定是否 push / 開 PR。

memory `feedback_small_fixups_no_pr.md`：機械改動 / 翻譯 / typo 才直接 push 到 dev branch；此變動有 spec + plan，視為一般 feature，依使用者指示再 push 或開 PR。

---

## 驗證計畫對應 spec

- **Spec「目標」** → Task 2 Step 1 修改 `_Placeholder.build`，新增 `Center + Icon`。
- **Spec「視覺規格」`size * 0.55` / `Icons.question_mark` / `color: accent`** → Task 1 Step 1 測試斷言 `icon.size == size * 0.55` + `find.byIcon(Icons.question_mark)`；Task 2 Step 1 程式碼直接使用對應常數。
- **Spec「外部 API 零變動」** → 只動 `_Placeholder.build` 內部，未改 ctor、未改 `GachaItemIcon`；Task 2 Step 4 整檔測試驗證。
- **Spec「分享圖正面影響」** → Task 3 Step 4 手動驗證涵蓋分享圖路徑。
- **Spec「i18n / l10n」** → 無新增字串，無 task 涉及 arb 檔。
- **Spec「Log 變更：無」** → 計畫內無 logger 異動 task。
- **CLAUDE.md「提交前品質檢查」** → Task 3 Step 1–3 完整對應 format + analyze + test 三項。
