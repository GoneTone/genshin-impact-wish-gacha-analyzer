# 側選單頌願區塊項目重新命名 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓側選單頌願 (Odes) section 內的兩個項目顯示為純修飾語「活動 / 常駐」，與祈願 section 風格對齊。

**Architecture:** 純 i18n 字串改動 — 修改 `app_zh_Hant.arb`、`app_zh_Hans.arb`、`app_en.arb` 內的 `navOdesEvent` / `navOdesStandard` 兩個 key，重新生成 Flutter localization。`app_shell.dart` 透過 `l.navOdesEvent / l.navOdesStandard` 取值，直接吃新字串，程式碼不動。

**Tech Stack:** Flutter (Dart), `flutter_localizations` + gen-l10n (`l10n.yaml` 設定 `app_zh_Hant.arb` 為 template-arb-file)

**測試策略：** 本次無新增 unit / widget test。grep 結果顯示沒有測試直接斷言這兩個 i18n 值；新增測試只為 cosmetic string 違反 YAGNI 原則。驗收靠 `flutter analyze` + `flutter test` 通過既有 suite，加上手動跑 app 觀察三語系側選單。

---

## File Structure

僅修改以下檔案，**不新增**任何檔案：

| 檔案 | 修改內容 |
|---|---|
| `lib/l10n/app_zh_Hant.arb` | 第 39、40 行：navOdesEvent / navOdesStandard 字面值 |
| `lib/l10n/app_zh_Hans.arb` | 第 27、28 行：navOdesEvent / navOdesStandard 字面值 |
| `lib/l10n/app_en.arb` | 第 31、32 行：navOdesEvent / navOdesStandard 字面值 |
| `lib/l10n/generated/app_localizations_*.dart` | `flutter gen-l10n` 自動重新生成（不手動編輯） |

`lib/pages/app_shell.dart`（line 485-486 使用這兩個 key）**不修改**。

---

### Task 1: 改三個 arb 檔 + 重新生成 + 品質檢查 + commit

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb` (line 39-40)
- Modify: `lib/l10n/app_zh_Hans.arb` (line 27-28)
- Modify: `lib/l10n/app_en.arb` (line 31-32)
- Auto-generated: `lib/l10n/generated/app_localizations_zh.dart` 等

- [ ] **Step 1: 改 `lib/l10n/app_zh_Hant.arb`**

把第 39-40 行：

```json
  "navOdesEvent": "活動頌願",
  "navOdesStandard": "常駐頌願",
```

改成：

```json
  "navOdesEvent": "活動",
  "navOdesStandard": "常駐",
```

- [ ] **Step 2: 改 `lib/l10n/app_zh_Hans.arb`**

把第 27-28 行：

```json
  "navOdesEvent": "活动颂愿",
  "navOdesStandard": "常驻颂愿",
```

改成：

```json
  "navOdesEvent": "活动",
  "navOdesStandard": "常驻",
```

- [ ] **Step 3: 改 `lib/l10n/app_en.arb`**

把第 31-32 行：

```json
  "navOdesEvent": "Event Odes",
  "navOdesStandard": "Standard Odes",
```

改成：

```json
  "navOdesEvent": "Event",
  "navOdesStandard": "Standard",
```

- [ ] **Step 4: 重新生成 Flutter localization**

Run:

```bash
flutter gen-l10n
```

Expected: 命令成功結束（無錯誤輸出）。`lib/l10n/generated/app_localizations_*.dart` 內含新字面值。可選驗證：

```bash
grep -n "navOdesEvent\|navOdesStandard" lib/l10n/generated/app_localizations_zh.dart
```

預期看到 `"活動"` 與 `"常駐"`（zh_Hant 模板）。

- [ ] **Step 5: 格式化**

Run:

```bash
dart format lib/ test/
```

Expected: 命令成功；通常 arb 不會被 format 動到，generated 檔可能會被微調。

注意：依 CLAUDE.md，**不要對 `.` 跑 `dart format`**，避免動到 `rust_builder/` 內 vendored 程式碼。

- [ ] **Step 6: 靜態分析**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

若出現 `lib/l10n/generated/...` 相關錯誤，多半是 gen-l10n 沒跑成功，回 Step 4 重跑。

- [ ] **Step 7: 跑測試**

Run:

```bash
flutter test
```

Expected: `All tests passed!`

若有測試斷言到舊字面值（例如 `expect(find.text('活動頌願'), ...)`），就把該測試的期望值同步改成新字串並 grep 確認沒有其他遺漏；不要為了讓測試過去就跳過或改回 arb。

- [ ] **Step 8: 手動驗收（跑 app，三語系都看）**

啟動 app：

```bash
flutter run -d windows
```

依序在「設定 → 語言」切換 **繁體中文 / 简体中文 / English** 三個語系，觀察側選單：

| 預期 | 繁中 | 簡中 | 英文 |
|---|---|---|---|
| 祈願 section header | 祈願 | 祈愿 | Wish |
| 祈願項目 | 角色 / 武器 / 集錄 / 常駐 / 新手 | 角色 / 武器 / 集录 / 常驻 / 新手 | Character / Weapon / Chronicled / Standard / Beginner |
| 頌願 section header | 頌願 | 颂愿 | Odes |
| **頌願項目** | **活動 / 常駐** | **活动 / 常驻** | **Event / Standard** |

額外確認：

- 點擊頌願 section 內「活動」「常駐」項目，仍能正確導航到對應卡池頁面
- 卡池內頁標題（如果有顯示 `gachaTypeOdesEvent` / `gachaTypeOdesStandard`）仍是「活動頌願 / 常駐頌願」，**不應該**變短
- 側選單寬度切到 extended (>1180px) / collapsed (<1180px) / collapsed-no-label (<800px) 三檔，「常駐」項目在祈願與頌願 section 各出現一次但 icon 不同（`history` vs `auto_awesome_motion`），這是預期行為

關閉 app。

- [ ] **Step 9: Commit**

```bash
git add lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb
git commit -m "i18n(rail): rename Odes items to drop suffix, align with Wish section"
```

注意：
- `lib/l10n/generated/` 已被 `.gitignore` 第 64 行排除（build-time 重新生成），**不要**也**不能** `git add`。
- **不要** `git add docs/superpowers/`（spec 與 plan 留本地，不進版控）。

---

## Self-Review

**Spec coverage：**

- ✅ Spec「變更內容」3 個 arb 表格 → Task 1 Step 1-3
- ✅ Spec「不在範圍內」`navSectionWish/Odes`、`gachaTypeOdes*` → 本 plan 從未提到要改它們，Step 8 驗收還反向確認 `gachaType*` 仍是長名稱
- ✅ Spec「驗收標準」第 1 條（三語系顯示對） → Step 8
- ✅ Spec「驗收標準」第 2 條（導航正確） → Step 8
- ✅ Spec「驗收標準」第 3 條（頁面標題用 `gachaTypeOdes*` 不動） → Step 8
- ✅ Spec「驗收標準」第 4 條（format / analyze / test） → Step 5-7

**Placeholder scan：** 無 TBD / TODO；每個 step 都有具體 code block 或 command。

**Type consistency：** N/A（沒有新增類型或方法簽名）。

**已知 edge cases 提示：**

- `flutter gen-l10n` 沒跑也能 `flutter run` 觸發生成，但顯式跑能在 CI 前就抓到 arb 語法錯
- generated 檔要進 commit（專案已 commit 過 `lib/l10n/generated/`，跟著走）
