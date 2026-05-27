# 帳號切換鈕改為外框膠囊

日期：2026-05-21
範圍：`lib/widgets/uid_indicator.dart`（單檔）

## 目標

AppBar 右上的帳號切換觸發鈕（`UidIndicator`）目前是一段裸文字 `Row`（圖示 + alias/UID + 下拉箭頭），無固定高度、無背景、無形狀，點擊範圍僅文字自然高度。

要讓它變成與右側「更新資料」按鈕（`FilledButton.icon`，M3 預設 40dp 高、`StadiumBorder` 橢圓形、primary 實心）**同高、同樣橢圓形**的**外框膠囊**：透明底 + 邊框，屬次要強度，並排時與 primary 實心鈕層次分明。

## 採用方案：`OutlinedButton` 觸發 + `showMenu()`

觸發鈕換成標準 M3 `OutlinedButton`，點擊時呼叫 `showMenu()` 彈出**現有的 `PopupMenuEntry` 清單**。菜單內容（帳號項、勾選圖示、`PopupMenuDivider`、新增帳號項）整段不動，只替換觸發鈕本體與彈出方式。

選此方案的理由：
- 高度 40dp、`StadiumBorder`、邊框色、**點擊漣漪自動裁切成膠囊形** —— 全部由 `OutlinedButton` 免費提供，與更新鈕像素級對齊；`PopupMenuButton` 內建 `InkWell` 為矩形、漣漪會溢出橢圓兩端，達不到「橢圓形」要求。
- 用標準按鈕而非手刻 40dp `Material`，符合「不重複造輪子、好維護」。
- 菜單外觀零改動，回歸風險低。

## 實作細節

### 結構改動

`UidIndicator` 從 `ConsumerWidget` 內 `return PopupMenuButton<String>(...)` 改為 `return OutlinedButton(...)`，`onPressed` 內：

1. 從觸發鈕的 `RenderBox` 與 overlay 的 `RenderBox` 計算 `RelativeRect`（彈在按鈕正下方、靠右對齊 AppBar）。
2. 呼叫 `showMenu<String>(context:, position:, items:)`，`items` 為原本 `itemBuilder` 產出的 `List<PopupMenuEntry<String>>`（抽成一個 `_buildItems(...)` 或 inline）。
3. `showMenu` 回傳 `Future<String?>`，沿用原 `onSelected` 邏輯：`__recapture__` → `notifier.forceRecaptureAndUpdate()`，否則 `notifier.setActiveUid(key)`。

`RelativeRect` 取法（標準寫法）：

```dart
final button = context.findRenderObject() as RenderBox;
final overlay =
    Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
final position = RelativeRect.fromRect(
  Rect.fromPoints(
    button.localToGlobal(Offset.zero, ancestor: overlay),
    button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
  ),
  Offset.zero & overlay.size,
);
```

> 因 `context.findRenderObject()` 需指向觸發鈕本體，`onPressed` 內取的 `context` 即 `OutlinedButton` build 出來的位置，可直接用；若有疑慮可用 `Builder` 包一層確保 context 落在按鈕上。

### 視覺

- 觸發鈕內容**沿用現有 `AccountTriggerLabel`** widget（`person_outline` 圖示 + alias/UID 文字 + `arrow_drop_down` 箭頭；alias `maxWidth 160` + ellipsis；`activeUid == null` 顯示「未同步」）—— 不重寫。
- `OutlinedButton` 以 `style: OutlinedButton.styleFrom(...)` 設定：
  - `shape: const StadiumBorder()`（橢圓）
  - 邊框色用主題 outline；若與 `tokens.borderEmphasis` 視覺更搭則用後者，實作時對照 light/dark 擇一。
  - 文字/圖示色用 `tokens.textPrimary` / `textSecondary`，確保 light/dark 對比足夠。
  - 高度交由 M3 預設（40dp），不硬寫，以與更新鈕一致。
- `tooltip` 沿用 `l.uidSwitchTooltip`：`OutlinedButton` 無 `tooltip` 屬性，外層用 `Tooltip(message: ...)` 包裹。

### Log

依 CLAUDE.md「新功能要埋 log」，在 widget 層補關鍵節點（命名對齊既有 `ui.*` 樹，如 `ui.account`）：
- 切換帳號時 `info`：帶**脫敏後**的 uid（經 `sanitizeUid`）。
- 觸發「新增帳號 / 重新捕獲」時 `info`。

（`setActiveUid` / `forceRecaptureAndUpdate` 屬既有業務邏輯、本次不改，不在其內補 log。）

## 不做（YAGNI / 範圍外）

- 不改菜單項目外觀、排序、`AccountMenuLabel`。
- 不改更新資料按鈕。
- 不抽共用「膠囊按鈕」元件——目前只有一處外框膠囊需求，需要第二處時再抽。
- 不改 `setActiveUid` / `forceRecaptureAndUpdate` 行為。

## 驗收

- AppBar 右上帳號鈕與更新鈕**等高**、皆為橢圓形；帳號鈕為外框透明底、更新鈕為 primary 實心。
- 點擊帳號鈕漣漪裁切於膠囊內、不溢出。
- 點擊彈出選單位置與原本相近（按鈕下方），切換帳號 / 新增帳號功能不變。
- light / dark 下邊框與文字對比皆清楚。
- 視窗縮窄時 alias 仍 ellipsis、不溢出邊界（RWD）。
- `flutter analyze` 無 issue、`flutter test` 全綠。
