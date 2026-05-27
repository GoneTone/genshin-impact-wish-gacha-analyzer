# 稀有度色票調整 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 1★～5★ 稀有度色票替換為使用者指定的新基準色（dark/light 各微調 ±10～12% L 維持對比），並補上目前缺少的 1★ token。

**Architecture:** 兩個檔案：`lib/theme/tokens.dart`（新增 `oneStar` 欄位 + 改寫 dark/light static const 的稀有度色與連動的 `accentPrimary`/`stateWarning`）；`lib/widgets/rank_palette.dart`（switch 加 `1 => t.oneStar` case）。新增 `test/widgets/rank_palette_test.dart` 以 TDD 保護 rank 1 行為。

**Tech Stack:** Flutter (Dart)、`flutter_test`、現有 `ThemeExtension<GachaTokens>` 架構。

**Spec：** `docs/superpowers/specs/2026-05-25-rarity-color-tokens-design.md`

---

## File Structure

- **Modify** `lib/theme/tokens.dart`
  - `GachaTokens` 新增 `final Color oneStar`、constructor `required this.oneStar`、`copyWith` / `lerp` 各補一行
  - `dark` 與 `light` static const 覆寫 `fiveStar`/`fourStar`/`threeStar`/`twoStar`、新增 `oneStar`、改 `accentPrimary` 與 `stateWarning`（後兩者目前慣例與 5★ 同色）
- **Modify** `lib/widgets/rank_palette.dart`
  - `accentForRank()` switch 加 `1 => t.oneStar`，default `_ => t.textMuted` 保留
- **Create** `test/widgets/rank_palette_test.dart`
  - 覆蓋 rank 1～5 對應 token、rank 0 / rank 99 fallback 行為

新色票（方案 B，±10～12% L 微調，色相不變）：

| 星級 | Dark | Light |
|---|---|---|
| 5★ | `#cd8e48` | `#8d5a25` |
| 4★ | `#b594c5` | `#7e589a` |
| 3★ | `#73a8c5` | `#437897` |
| 2★ | `#6dad8a` | `#467b62` |
| 1★ | `#a3a2a3` | `#686769` |

---

## Task 1：擴充 `GachaTokens` 結構（加入 `oneStar` 欄位）

**Files:**
- Modify: `lib/theme/tokens.dart`（既有檔案，整段 `GachaTokens` class 都要動）

這個 task 只動結構，不換 hex（hex 在 Task 4 換）。先讓 oneStar 欄位存在、可被引用，後續 Task 2 的測試才能編譯。

- [ ] **Step 1.1：在 `GachaTokens` constructor 加入 `required this.oneStar`**

  位置：`lib/theme/tokens.dart` 約 line 64-81 的 `const GachaTokens({...})`。在 `required this.twoStar,` 之後、`required this.accentPrimary,` 之前插入新行：

  ```dart
  required this.oneStar,
  ```

  改完後 constructor 為：

  ```dart
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
    required this.twoStar,
    required this.oneStar,
    required this.accentPrimary,
    required this.stateDanger,
    required this.stateSuccess,
    required this.stateWarning,
  });
  ```

- [ ] **Step 1.2：在欄位宣告區加入 `oneStar` 欄位**

  位置：`lib/theme/tokens.dart` 約 line 116-117（`twoStar` 欄位宣告之後）。插入：

  ```dart
  /// 一星稀有度色。
  final Color oneStar;
  ```

  必須加上一行 dartdoc，與既有 `fiveStar` / `fourStar` / ... 風格一致（CLAUDE.md 規則：所有宣告寫一行 `///`）。

- [ ] **Step 1.3：在 `copyWith` 補上 `oneStar`**

  位置：`lib/theme/tokens.dart` 約 line 172-206。在參數列加 `Color? oneStar,`（位置：`Color? twoStar,` 之後），在 body 加 `oneStar: oneStar ?? this.oneStar,`。

  改完後 `copyWith` 為：

  ```dart
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
    Color? twoStar,
    Color? oneStar,
    Color? accentPrimary,
    Color? stateDanger,
    Color? stateSuccess,
    Color? stateWarning,
  }) => GachaTokens(
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
    twoStar: twoStar ?? this.twoStar,
    oneStar: oneStar ?? this.oneStar,
    accentPrimary: accentPrimary ?? this.accentPrimary,
    stateDanger: stateDanger ?? this.stateDanger,
    stateSuccess: stateSuccess ?? this.stateSuccess,
    stateWarning: stateWarning ?? this.stateWarning,
  );
  ```

- [ ] **Step 1.4：在 `lerp` 補上 `oneStar`**

  位置：`lib/theme/tokens.dart` 約 line 208-233。在 `twoStar:` 之後插入：

  ```dart
  oneStar: Color.lerp(oneStar, other.oneStar, t)!,
  ```

- [ ] **Step 1.5：在 `dark` static const 補上 `oneStar`（直接寫最終色）**

  位置：`lib/theme/tokens.dart` 約 line 132-149。在 `twoStar: Color(0xFF6A7080),` 之後插入：

  ```dart
  oneStar: Color(0xFFA3A2A3),
  ```

  直接寫最終色，避免 Task 2 的「rank 1 maps to oneStar」測試誤過（若 placeholder = textMuted 會讓 fallback 與 oneStar 撞色）。

- [ ] **Step 1.6：在 `light` static const 補上 `oneStar`（直接寫最終色）**

  位置：`lib/theme/tokens.dart` 約 line 152-169。在 `twoStar: Color(0xFF8A92A6),` 之後插入：

  ```dart
  oneStar: Color(0xFF686769),
  ```

  同 Step 1.5 理由。

- [ ] **Step 1.7：跑 `flutter analyze` 確認 compile OK**

  Run：

  ```bash
  flutter analyze
  ```

  Expected：`No issues found!`

- [ ] **Step 1.8：跑既有測試確認沒破**

  Run：

  ```bash
  flutter test
  ```

  Expected：`All tests passed!`

---

## Task 2：寫 `accentForRank` 測試（先紅）

**Files:**
- Create: `test/widgets/rank_palette_test.dart`

- [ ] **Step 2.1：建立測試檔案**

  寫入 `test/widgets/rank_palette_test.dart`：

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
  import 'package:genshin_impact_wish_gacha_analyzer/widgets/rank_palette.dart';

  void main() {
    group('accentForRank', () {
      const tokens = GachaTokens.dark;

      test('rank 5 maps to fiveStar', () {
        expect(accentForRank(5, tokens), tokens.fiveStar);
      });

      test('rank 4 maps to fourStar', () {
        expect(accentForRank(4, tokens), tokens.fourStar);
      });

      test('rank 3 maps to threeStar', () {
        expect(accentForRank(3, tokens), tokens.threeStar);
      });

      test('rank 2 maps to twoStar', () {
        expect(accentForRank(2, tokens), tokens.twoStar);
      });

      test('rank 1 maps to oneStar', () {
        expect(accentForRank(1, tokens), tokens.oneStar);
      });

      test('rank 0 falls back to textMuted', () {
        expect(accentForRank(0, tokens), tokens.textMuted);
      });

      test('out-of-range rank 99 falls back to textMuted', () {
        expect(accentForRank(99, tokens), tokens.textMuted);
      });
    });
  }
  ```

- [ ] **Step 2.2：跑測試確認 rank 1 失敗**

  Run：

  ```bash
  flutter test test/widgets/rank_palette_test.dart
  ```

  Expected：「rank 1 maps to oneStar」測試**失敗**——目前 `accentForRank()` 對 rank 1 走 default fallback 到 `textMuted`（`#8a92a6` dark / `#6a7080` light），但 expected 為 `oneStar`（`#a3a2a3` / `#686769`），兩值不同，必紅。其餘 6 個 case 應該綠燈（rank 5/4/3/2 早已對應、rank 0/99 走 fallback）。

---

## Task 3：修改 `accentForRank` 加入 rank 1（綠）

**Files:**
- Modify: `lib/widgets/rank_palette.dart`

- [ ] **Step 3.1：在 switch 加入 `1 => t.oneStar` case**

  改 `lib/widgets/rank_palette.dart` 為：

  ```dart
  import 'package:flutter/material.dart';

  import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

  /// 依稀有度 rank 取對應主色 token。
  Color accentForRank(int rank, GachaTokens t) => switch (rank) {
    5 => t.fiveStar,
    4 => t.fourStar,
    3 => t.threeStar,
    2 => t.twoStar,
    1 => t.oneStar,
    _ => t.textMuted,
  };
  ```

  注意：default `_ => t.textMuted` 保留——`rank` 是 `int`，理論上可能傳 0 或負數，fallback 保留可避免 null 或 throw。

- [ ] **Step 3.2：跑 `rank_palette_test.dart` 確認全綠**

  Run：

  ```bash
  flutter test test/widgets/rank_palette_test.dart
  ```

  Expected：`All tests passed!`（7 個測試全綠）。

---

## Task 4：換上 5/4/3/2 與連動色的最終 hex（方案 B 新色）

**Files:**
- Modify: `lib/theme/tokens.dart`（`dark`、`light` 兩個 static const）

把 5★/4★/3★/2★ 與連動的 `accentPrimary`、`stateWarning` 換成 spec 定的方案 B 色。`oneStar` 已在 Task 1 寫入最終色，此 task 不再動它。

- [ ] **Step 4.1：改寫 `dark` static const 的稀有度與連動色**

  位置：`lib/theme/tokens.dart` 約 line 131-149。把整個 `dark` static const 改為：

  ```dart
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
    fiveStar: Color(0xFFCD8E48),
    fourStar: Color(0xFFB594C5),
    threeStar: Color(0xFF73A8C5),
    twoStar: Color(0xFF6DAD8A),
    oneStar: Color(0xFFA3A2A3),
    accentPrimary: Color(0xFFCD8E48),
    stateDanger: Color(0xFFE6736B),
    stateSuccess: Color(0xFF46B07A),
    stateWarning: Color(0xFFCD8E48),
  );
  ```

  改動：`fiveStar`、`fourStar`、`threeStar`、`twoStar`、`accentPrimary`、`stateWarning` 六個欄位（`oneStar` 已在 Task 1.5 設定為最終色）。其餘維持原樣。

- [ ] **Step 4.2：改寫 `light` static const 的稀有度與連動色**

  位置：`lib/theme/tokens.dart` 約 line 151-169。把整個 `light` static const 改為：

  ```dart
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
    fiveStar: Color(0xFF8D5A25),
    fourStar: Color(0xFF7E589A),
    threeStar: Color(0xFF437897),
    twoStar: Color(0xFF467B62),
    oneStar: Color(0xFF686769),
    accentPrimary: Color(0xFF8D5A25),
    stateDanger: Color(0xFFC62828),
    stateSuccess: Color(0xFF2E7D32),
    stateWarning: Color(0xFF8D5A25),
  );
  ```

  改動：同 dark 的六個欄位（`oneStar` 已在 Task 1.6 設定為最終色）。

- [ ] **Step 4.3：跑 `flutter analyze` 與 `flutter test`**

  Run：

  ```bash
  flutter analyze
  ```

  Expected：`No issues found!`

  Run：

  ```bash
  flutter test
  ```

  Expected：`All tests passed!`（既有測試讀 token 不寫死 hex，預期不破；rank_palette_test 也全綠）。

---

## Task 5：品質檢查與手動驗證

- [ ] **Step 5.1：格式化**

  Run：

  ```bash
  dart format lib/ test/
  ```

  Expected：可能 reformat 0~3 個檔。CLAUDE.md 規則：不要對 `.` 跑（會動到 `rust_builder/`）。

- [ ] **Step 5.2：靜態分析**

  Run：

  ```bash
  flutter analyze
  ```

  Expected：`No issues found!`

- [ ] **Step 5.3：全套測試**

  Run：

  ```bash
  flutter test
  ```

  Expected：`All tests passed!`

- [ ] **Step 5.4：手動視覺驗證（請使用者執行）**

  跑：

  ```bash
  flutter run -d windows
  ```

  使用者在 app 內逐項確認：

  1. 切換 dark / light theme（設定頁）。
  2. **覽覽頁（overview）**：5★/4★ stat card accent 顏色（金棕 / 紫）。
  3. **卡池頁（banner）**：top-rarity-bars、pity-card、timeline 的 5★/4★/3★ chip 色。
  4. **rarity pie**：圓餅圖各扇 5★/4★/3★/2★（若該帳號有 2★ 資料）。
  5. **分享圖（share-card）**：rank5 / rank4 accent 與 `accentPrimary`（按鈕主色）的銅金色感。
  6. **任何 stateWarning 觸發點**（如更新提示、警告 dialog）：警告色從亮金變銅金，但仍清楚可辨識。

  使用者若指出某個色在實際 app 看起來不對，回來調該欄 hex（不會破測試，因為 rank_palette_test 不寫死 hex）。

---

## Task 6：Commit

CLAUDE.md 規則：不要主動 `git push`。本 task 只 commit。

- [ ] **Step 6.1：檢視 diff**

  Run：

  ```bash
  git status
  git diff lib/theme/tokens.dart lib/widgets/rank_palette.dart test/widgets/rank_palette_test.dart
  ```

  確認動到的檔案只有這三個。

- [ ] **Step 6.2：Commit**

  Run（PowerShell）：

  ```powershell
  git add lib/theme/tokens.dart lib/widgets/rank_palette.dart test/widgets/rank_palette_test.dart
  git commit -m @'
  feat(theme): adjust rarity color tokens and add 1-star token

  Replace 5/4/3/2-star color tokens with a new baseline aligned with
  Genshin's weapon/artifact rarity convention (5★ bronze-gold, 4★ purple,
  3★ blue, 2★ green). Add oneStar token so accentForRank no longer falls
  back to textMuted for rank 1. accentPrimary and stateWarning track
  fiveStar per existing convention.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  '@
  ```

  Expected：commit 成功，pre-commit hook（若有）通過。若 hook 失敗，依錯誤訊息修，再 `git add` 後跑**新的** `git commit`（不要 `--amend`，CLAUDE.md 與 system rules 明令）。

- [ ] **Step 6.3：確認 commit**

  Run：

  ```bash
  git log -1 --stat
  ```

  Expected：看到上述 commit 訊息，三個檔案各有改動行數。

---

## Spec Coverage 檢查

對應 spec `docs/superpowers/specs/2026-05-25-rarity-color-tokens-design.md` 每段：

- **決策 → 範圍 dark+light**：Task 4 兩個 static const 都改 ✓
- **決策 → 1★ token**：Task 1.2 加欄位 / Task 3 接通 switch ✓
- **決策 → 微調強度方案 B**：Task 4 hex 採用方案 B 色票 ✓
- **決策 → accentPrimary / stateWarning 連動**：Task 4.1 / 4.2 同步換 ✓
- **最終色票**：Task 4 全數寫入 ✓
- **程式碼變動 → tokens.dart 結構**：Task 1 全覆蓋 ✓
- **程式碼變動 → accentForRank**：Task 3 ✓
- **驗證計畫**：Task 5 ✓
- **範圍外項目**：plan 不含 BannerColors、borderEmphasis、stateDanger/stateSuccess、HSL helper 等動作 ✓
