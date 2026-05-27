# UID Indicator 切換帳號下拉重排 — Design

日期: 2026-05-13
範圍: `lib/widgets/uid_indicator.dart` 一個檔案

## 動機

切換帳號下拉的 `PopupMenuItem` 與 AppBar 觸發鈕都用 `'$alias ($uid)'` 單行格式,且未做寬度限制與 ellipsis。當別名較長時:

- 觸發鈕會把 AppBar 上其他元件擠到邊界外。
- 選單項目把 popup 整個撐寬,跨越合理 UI 寬度。

## 設計

把 alias 與 UID 從「同一行 + 括號」改成「上下兩行 + 副標題風格」,並補上 ellipsis 截字。

### 觸發鈕 (AppBar 上)

- 維持單行,不增加 AppBar 高度。
- 格式: `alias (uid)` (保留現狀格式),但 alias 部分套用 ellipsis,UID 完整保留。
  - 有別名: `<alias…> (<uid>)` ▾
  - 無別名: `<uid>` ▾
  - `activeUid == null`: 仍顯示 `l.uidNotSynced` ("未同步" / "Not synced")。
- 整體寬度由 `ConstrainedBox(maxWidth: ...)` 限制,讓 alias 在達到上限時截字。

### Popup 選單項目

每一個帳號項目改成 alias 主標 + UID 副標兩行格式:

```
┌────────────────────────────────────┐
│ ✓  <alias …>（活躍）              │ ← 主標 (alias),用 ellipsis 截字
│    <uid>                          │ ← 副標 (UID),tokens.textMuted, 較小字
│                                    │
│ ○  <alias>                        │
│    <uid>                          │
│                                    │
│ ○  <uid>           ← 無別名單行   │ ← 沒 alias 時,主標直接顯示 UID,無副標
└────────────────────────────────────┘
─────────
⊕ 新增帳號
```

Widget 結構(每個帳號項目):

```
Row(crossAxisAlignment: CrossAxisAlignment.center)
├─ Icon (check / radio_button_unchecked, 大小不變)
├─ SizedBox(width: AppSpacing.s)
└─ Expanded
   └─ Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: min)
      ├─ Row (主標列)
      │  ├─ Flexible
      │  │  └─ Text(alias, maxLines: 1, overflow: TextOverflow.ellipsis)
      │  └─ if activeUid: Text(l.uidActiveSuffix, style: 11/textMuted)
      └─ if alias != null: Text(uid, style: 12/textMuted)
```

要點:

- **主標 (alias 或 fallback 的 UID)**: 預設文字樣式,單行,`TextOverflow.ellipsis`。後面接「（活躍）」suffix(僅當該項目為 activeUid),樣式維持與原本相同(`fontSize: 11`, `tokens.textMuted`)。
- **副標 (UID)**: `tokens.textMuted` 顏色 + `fontSize: 12`,單行(UID 長度固定 9 位數,不需 ellipsis)。
- **無別名 fallback**: 主標的 `Text` 內容直接是 UID,且不渲染副標 `Text`(整個 if 區塊跳過,Column 只有一個 child,自然單行)。
- **icon 對齊**: Row 的 `crossAxisAlignment: CrossAxisAlignment.center` — 兩行情況 icon 對齊 Column 垂直中心;單行 fallback 情況 icon 也自然置中。
- **「新增帳號」項目**: 不在這次改動範圍,維持原本單行 Row。
- **Divider**: 維持原本「新增帳號」前的 `PopupMenuDivider`,位置不變。

### 寬度限制

- **PopupMenuItem**: 把 `child` 整個 Row 外包 `ConstrainedBox(maxWidth: 280)`,並讓 alias 主標 `Text` 包在 `Flexible` 內,ellipsis 才能觸發。
- **觸發鈕**: 在 `Padding` 內的 Row 用 `ConstrainedBox(maxWidth: 220)`,alias `Text` 包 `Flexible`,讓 UID + `▾` 仍完整顯示、alias 過長截字。
- 280 / 220 是初值,實作時依視覺微調並固定下來;不在 spec 內留浮動值。

## 不在範圍

- `accounts_picker_dialog.dart`(匯出匯入勾選對話框)— 該檔案版面屬於另一條功能,不在本次改動。
- `account_management.dart` — 帳號管理卡片,本次不動。
- 多語系字串 — 沒有新增 / 改動字串。

## 測試

- 既有的 widget 測試若有對 `displayName` / 文字格式的斷言,需更新。沒有則新增最小 widget 測試:
  - 有 alias + 短: 主標 = alias、副標 = UID、無 ellipsis 截字。
  - 有 alias + 過長: 主標出現 ellipsis;副標 UID 不受影響。
  - 無 alias: 主標 = UID、沒有副標 widget。
  - activeUid: 「（活躍）」suffix 出現在主標後。
  - 觸發鈕: maxWidth 內 alias 截字、UID 仍可見。

## 風險

- `PopupMenuItem` 改成多行會影響 popup 整體高度,可能讓選單在帳號數多時超出視窗 — 但 Flutter PopupMenuButton 預設有 scroll,且帳號上限通常個位數,實務影響低。
- ellipsis 觸發依賴外層寬度限制,須在實作時實測 (Windows / 不同 DPI) 確認 maxWidth 數值合理。
