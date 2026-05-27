# Dialog 寬高上限統一：AppDialog widget 設計

> Date: 2026-05-15
> Status: Draft → 待 review
> 影響範圍：`lib/widgets/dialogs/**`、`lib/widgets/update_progress_dialog.dart`、`CLAUDE.md`、`AGENTS.md`

## 背景

目前專案內 4 個 dialog 對「寬高上限」的處理不一致：

| Dialog                       | 寬度上限                   | 高度上限              |
|------------------------------|------------------------|-------------------|
| `confirm_dialog.dart`        | **無**                  | **無**             |
| `update_progress_dialog.dart`| **無**                  | **無**             |
| `accounts_picker_dialog.dart`| `min(480, mq.width-80)` | `mq.height * 0.6` |
| `new_version_dialog.dart`    | `min(720, mq.width-80)` | `mq.height * 0.6` |

兩個問題：

1. **重複造輪子**：後兩個 dialog 各自抄一份相同的「`min(maxWidth, mq.size.width - 80)` + `ConstrainedBox(maxHeight: mq.size.height * 0.6)`」邏輯（違反專案規則）。
2. **規則不對稱 + 邊界 case 卡死**：寬度有「視窗安全邊距」fallback，高度卻只有比例。在低視窗高度（例如 600px）`0.6 * 600 = 360px`，內容反而被強迫捲動，明明還有上下各 100px 空間可用。
3. **前兩個 dialog 完全沒上限**：超寬螢幕會被內容撐很開。

## 目標

- 提供統一的 `AppDialog` widget 包裝寬高上限邏輯，使用端不再手寫 `AlertDialog` + `ConstrainedBox` + `math.min(...)`。
- 三檔語意尺寸 `sm / md / lg`，使用端用 `size:` 參數選，不直接寫死數字。
- 高度上限規則對稱於寬度上限，避免低視窗 over-restrict。
- 一次重構掉 4 個既有 dialog，移除重複的計算邏輯。
- 更新 `CLAUDE.md` 與 `AGENTS.md`，新規則取代舊「Dialog 高度上限」條目。

## 設計

### 1. 新增 `lib/widgets/dialogs/app_dialog.dart`

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum AppDialogSize {
  sm,  // 480 — confirm / 短訊息 / progress
  md,  // 640 — 中等列表（accounts picker）
  lg;  // 720 — 長 markdown / release notes

  double get maxWidth => switch (this) {
    AppDialogSize.sm => 480,
    AppDialogSize.md => 640,
    AppDialogSize.lg => 720,
  };
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const <Widget>[],
    this.size = AppDialogSize.sm,
    this.scrollable = false,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final AppDialogSize size;

  /// 整體內容是否需要外層 SingleChildScrollView 包起來。
  /// 內容已自帶捲動元件（如 ListView）時保持 false，避免雙層捲動衝突。
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // AlertDialog 預設左右 insetPadding 共 80（40 * 2），先扣再卡尺寸上限
    final dialogWidth = math.min(size.maxWidth, mq.size.width - 80);
    // 高度規則對稱：絕對上限 720 / 視窗高度扣除上下各 60 padding，取較小
    final maxHeight = math.min(720.0, mq.size.height - 120);

    Widget body = SizedBox(
      width: dialogWidth,
      child: content,
    );
    if (scrollable) {
      body = SingleChildScrollView(child: body);
    }

    return AlertDialog(
      // maxHeight 透過 AlertDialog.constraints 套用於整個 dialog
      // （title + content + actions），這樣 dialog 總高度才真的 ≤ maxHeight，
      // 對應使用者規格表「視窗 1080 → 720」的 dialog 總高上限語意。
      constraints: BoxConstraints(maxHeight: maxHeight),
      title: title,
      content: body,
      actions: actions.isEmpty ? null : actions,
    );
  }
}
```

### 2. 4 個既有 dialog 重構對應

| 檔案                              | size | scrollable | 說明                                           |
|---------------------------------|------|------------|----------------------------------------------|
| `confirm_dialog.dart`           | `sm` | `false`    | 短文字 + TextField                              |
| `update_progress_dialog.dart`   | `sm` | `false`    | 進度文字 + LinearProgressIndicator，外層 PopScope 保留 |
| `accounts_picker_dialog.dart`   | `md` | `false`    | 內部已用 ListView 自帶捲動                            |
| `new_version_dialog.dart`       | `lg` | `true`     | 整體 markdown 內容靠外層 scroll                      |

重構手法：

- 移除原本的 `math.min(X, mq.size.width - 80)`、`ConstrainedBox(maxHeight: ...)`、`SizedBox(width: ...)` 樣板碼。
- 改為直接 `return AppDialog(size: ..., title: ..., content: ..., actions: ...)`。
- `accounts_picker_dialog` 原本 content 內 `SizedBox(width: dialogWidth, child: Column(...))` → 直接給 `Column`，寬度交給 AppDialog。
- `new_version_dialog` 原本 `SingleChildScrollView(child: Column(...))` → `scrollable: true` + `Column(...)`，外層 scroll 由 AppDialog 負責。
- `accounts_picker_dialog` 與 `new_version_dialog` 移除 `import 'dart:math' as math;`。

### 3. 規則文件更新（`CLAUDE.md` 與 `AGENTS.md`）

把現有第 7 條：

```markdown
- **Dialog 高度上限**：`AlertDialog` 內容可能很長時，content 外面包一層 `ConstrainedBox(maxHeight: MediaQuery.of(context).size.height * 0.6)` 並讓內部自行滾動，避免吃滿整個視窗。
```

替換為：

```markdown
- **Dialog 一律用 `AppDialog`**：新建 dialog 一律使用 `AppDialog`（`lib/widgets/dialogs/app_dialog.dart`），透過 `size: AppDialogSize.sm/md/lg`（480 / 640 / 720）指定最大寬度。內部自動套寬高上限（width = `min(size.maxWidth, mq.width - 80)`，height = `min(720, mq.height - 120)`），低視窗下也不會被卡死。整體需要捲動時加 `scrollable: true`；內容已自帶捲動元件（`ListView` 等）維持預設 `false`。**不要再自己手寫 `AlertDialog` + `ConstrainedBox` + `math.min(...)`**。
```

`CLAUDE.md` 與 `AGENTS.md` 內容必須保持一致（兩份目前完全相同）。

### 4. 測試

新增 `test/widgets/dialogs/app_dialog_test.dart`，驗證：

- **三尺寸對應正確**：sm / md / lg 在足夠寬視窗下 dialog 內容寬度分別為 480 / 640 / 720。
- **窄視窗 fallback**：給 `mq.size.width = 400` 時，所有尺寸都應 fallback 為 `400 - 80 = 320`。
- **高度上限對稱**：給 `mq.size.height = 1080` 時 maxHeight 應為 720；給 `mq.size.height = 600` 時應為 480。
- **scrollable 開關**：`scrollable: true` 時樹中有 `SingleChildScrollView`，預設 false 時沒有。
- **actions 預設為空時**：傳給 AlertDialog 的 actions 為 null（不顯示空 actions 區）。

既有 dialog 若有測試（透過 `flutter test` 全跑）需確認重構後仍 pass。

## 為何這樣設計（trade-offs）

- **語意尺寸 vs 自由數字**：選 sm/md/lg enum 而非任意 `maxWidth: double`。理由：避免散落各處出現任意常數，未來要全域微調只動一處；現況最寬就 720，沒有自由度需求。代價：若未來真的有 dialog 需要 `1024`，要新增 `xl` 或加 `customMaxWidth` 參數 — 那時再說（YAGNI）。
- **共用 widget vs helper function**：選 widget。理由：把「寬高上限 + 視窗安全邊距」完全封裝，使用端不需要重複寫 `ConstrainedBox` + `SizedBox`，重複造輪子的機會降到 0。代價：使用端只能用 `AlertDialog` 樣式 — 但既有 4 個都是這個樣式，沒問題。
- **scrollable 開關 vs 一律包 scroll**：避免雙層捲動衝突（`accounts_picker` 用 ListView 自帶捲動）。
- **maxHeight 規則改用 `min(720, height - 120)`**：對稱於 width，最小可預測值；放棄原本「視窗高度 60%」的比例魔術數字。

## 風險與緩解

- **重構引入回歸**：4 個 dialog 是常用路徑（更新、匯出、匯入、確認清除）。緩解：
  - 重構完跑 `flutter analyze` + `flutter test`。
  - 在 debug build 手動跑一次：開設定頁的匯出 dialog（accounts_picker）、開更新流程（update_progress）、模擬新版本 dialog（new_version）、清空 UID 流程（confirm）。
- **既有測試覆蓋不足**：若 4 個 dialog 沒有 widget test，重構正確性靠 manual + analyze。Mitigation：新 widget AppDialog 自己有測試覆蓋寬高邏輯；既有 dialog 重構是純結構搬移、無業務邏輯變動。

## 不在本次範圍

- 不引入 dialog 動畫變化、不改 Material 預設 inset / shape / elevation。
- 不替 `AppDialog` 加 `xl`、`customMaxWidth`、`maxHeight` 自訂參數（YAGNI）。
- 不處理 `showSnackBar` / `BottomSheet` — 那是另外的元件。
