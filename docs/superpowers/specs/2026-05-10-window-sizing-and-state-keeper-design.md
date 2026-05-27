# 啟動視窗大小與位置記憶設計

- 日期：2026-05-10
- 範圍：
  - 新增 `lib/services/window_state_keeper.dart`
  - 新增 `test/services/window_state_keeper_test.dart`
  - 修改 `lib/main.dart`（啟動時呼叫 `WindowStateKeeper.bootstrap()`）
  - 修改 `pubspec.yaml`（新增 `window_manager`、`screen_retriever`）
- 不影響：`windows/runner/main.cpp`、現有 routing / theme / state / Rust 整合

## 目標

把舊版 (`master:src/background.js`) 的「**首次依公式置中、之後記住上次位置/尺寸/最大化狀態**」帶回 flutter-rewrite。

舊版邏輯（節錄）：

```js
const { width, height } = screen.getPrimaryDisplay().workAreaSize
if (width > height) {
  defaultHeight = height - 100
  defaultWidth  = defaultHeight * 16 / 9
}
if (height > width) {
  defaultWidth  = (width - 100) * 9 / 16
  defaultHeight = defaultWidth * 16 / 9
}
// + electron-window-state 持久化
```

目前 flutter-rewrite 在 `windows/runner/main.cpp:28-30` 寫死 `origin (10, 10)`、`size (1280, 720)`，沒有居中、沒有持久化。

## 非目標

- 不做 macOS / Linux / Android / iOS 行為（runner 不存在，YAGNI）。
- 不做多視窗 / sub-window 管理。
- 不做 frameless / 自訂 titlebar（舊版 `frame: false`，這次沿用系統 frame）。
- 不做 fullscreen 狀態記憶（舊版也沒記）。
- 不開放使用者調整邊距 X 值（寫死常數 `100`）。
- 不抽 `WindowState` model class（5 個原始型別欄位、檔案內流動，YAGNI）。

## 異動檔案總覽

| 檔案 | 動作 | 說明 |
|---|---|---|
| `pubspec.yaml` | 修改 | 新增 `window_manager`、`screen_retriever` 依賴 |
| `lib/main.dart` | 修改 | `runApp` 之前呼叫 `WindowStateKeeper.bootstrap()` |
| `lib/services/window_state_keeper.dart` | 新增 | 公式、持久化、套用、監聽全部封裝於此 |
| `test/services/window_state_keeper_test.dart` | 新增 | 純函式單元測試 |
| `windows/runner/main.cpp` | 不動 | `window_manager` 透過 plugin 將初始視窗 hide，`waitUntilReadyToShow` 在第一幀前 setBounds，舊的 (1280, 720) 不會被使用者看到 |

## 依賴選擇與單位

- `window_manager: ^0.5.x`（撰寫實作時取最新穩定版）— Flutter 桌面視窗管理主流套件。
- `screen_retriever: ^0.x`（同上）— 取得 display 資訊（`window_manager` 不直接提供）。
- 兩者 API 都使用 **logical pixels (dp)**，與舊版 Electron `screen.workAreaSize` 同單位。
- X = 100 沿用舊版 100 dp，DPI scaling 由 Flutter / OS 自動處理（150% DPI 下實際 150 物理像素），與舊版行為一致。

## 計算公式（純函式）

```dart
@visibleForTesting
Size computeDefaultWindowSize(Size workArea, {double margin = 100}) {
  final w = workArea.width;
  final h = workArea.height;

  // 極端小螢幕保護
  if (w < 200 || h < 200) {
    return const Size(800, 450);
  }

  if (w > h) {
    final height = h - margin;
    return Size(height * 16 / 9, height);
  }
  if (h > w) {
    final width = (w - margin) * 9 / 16;
    return Size(width, width * 16 / 9);
  }
  return Size(w - margin, h - margin); // 正方形 fallback
}
```

最小尺寸保護：若計算結果**兩個維度都**低於 `(800, 450)`（視為「螢幕太小、formula 結果完全無法使用」），fallback 到 `(800, 450)`。只有**一個**維度低於最小（如直向螢幕 9:16 width<800、height≥450）則**信任公式**保留比例，由 `setMinimumSize(800, 450)` 在使用者拖拉時提供下限。

> 為什麼不做 component-wise clamp：那會打破 16:9 / 9:16 比例（例如 1080×1920 portrait 螢幕的 551×980 會被 clamp 成 800×980，已非 9:16）。

## 最小視窗尺寸

`windowManager.setMinimumSize(Size(800, 450))`。舊版沒設此限，本次新增；理由：Flutter 在極窄寬度容易 overflow，與舊版 web 渲染容忍度不同。

## `WindowStateKeeper` 元件

### 單一進入點

```dart
class WindowStateKeeper with WindowListener {
  WindowStateKeeper._(this._prefs);
  static WindowStateKeeper? _instance;

  static Future<void> bootstrap() async { … }
}
```

`main.dart` 啟動：

```dart
if (Platform.isWindows) {
  await windowManager.ensureInitialized();
  await WindowStateKeeper.bootstrap();
}
```

### 儲存格式（shared_preferences 五個 key）

| Key | Type | 說明 |
|---|---|---|
| `window.state.x` | double | 上次「非最大化」位置 |
| `window.state.y` | double | 同上 |
| `window.state.width` | double | 上次「非最大化」尺寸 |
| `window.state.height` | double | 同上 |
| `window.state.isMaximized` | bool | 上次關閉時是否最大化 |

關鍵：**最大化時不覆蓋 x/y/w/h**，只更新 `isMaximized`。否則「最大化下關閉 → 還原時 bounds = 螢幕全尺寸」會吃掉之前手調的視窗大小（沿用 `electron-window-state` 策略）。

### `bootstrap()` 流程

1. `prefs ← SharedPreferences.getInstance()`
2. `saved ← _loadSaved(prefs)`（可能為 null）
3. `displays ← screenRetriever.getAllDisplays()`
4. `bounds ← resolveInitialBounds(saved, displays)`（純函式，可測）
5. ```dart
   await windowManager.waitUntilReadyToShow(
     const WindowOptions(skipTaskbar: false),
     () async {
       await windowManager.setMinimumSize(const Size(800, 450));
       await windowManager.setBounds(bounds);
       if (saved?.isMaximized == true) await windowManager.maximize();
       await windowManager.show();
       await windowManager.focus();
     },
   );
   ```
6. `windowManager.addListener(keeper)`

### `resolveInitialBounds`（純函式，主要測試對象）

```
saved == null
   → 公式算 size → clamp 到最小 800×450 → 在 primary display 居中
saved != null && off-screen（拔掉外接螢幕）
   → 公式重算 + 居中
saved != null && on-screen
   → 直接用 saved bounds
```

「On-screen」判定：列舉所有 displays，**saved 矩形與某個 display visibleRect 重疊面積 ≥ saved 面積的 30%** 即算可見。低於 30% 視為螢幕配置改變，重設居中。30% 是允許「視窗有少部分被裁掉」但「大部分仍在某螢幕內」就接受的合理門檻。

### 監聽與儲存（`WindowListener` overrides）

| 事件 | 動作 |
|---|---|
| `onWindowResize` | 排程 debounced save（800 ms） |
| `onWindowMove` | 排程 debounced save（800 ms） |
| `onWindowMaximize` | 立即 save（不 debounce） |
| `onWindowUnmaximize` | 立即 save |
| `onWindowClose` | cancel debounce → flush save |

`_saveNow()`：

```dart
final isMax = await windowManager.isMaximized();
await _prefs.setBool(kMaximized, isMax);
if (!isMax) {
  final b = await windowManager.getBounds();
  await _prefs.setDouble(kX, b.left);
  await _prefs.setDouble(kY, b.top);
  await _prefs.setDouble(kW, b.width);
  await _prefs.setDouble(kH, b.height);
}
```

## 測試策略

### 單元測試（`test/services/window_state_keeper_test.dart`）

純函式測試，不需 mock：

| 函式 | 測試案例 |
|---|---|
| `computeDefaultWindowSize` | 橫向 1920×1080 → 1742×980（16:9）；直向 1080×1920 → 551×980（9:16）；正方形 1000×1000 → 900×900；極小 150×100 → fallback 800×450 |
| `resolveInitialBounds` | saved=null → 公式 + 居中；saved 在 primary display 內 → 原樣回傳；重疊 < 30% → 公式 + 居中；重疊 ≥ 30% → 原樣回傳 |

### 手動驗收（`flutter test` 無法覆蓋的部分）

清掉 `shared_preferences` 後逐項驗證：

1. 全新環境 → 視窗以 16:9、扣 100 顯示，居中
2. 手動移動 / 縮放 → 關閉 → 重開：位置 & 大小還原
3. 最大化 → 關閉 → 重開：以最大化開啟
4. 最大化 → 還原 → 關閉 → 重開：還原為「最大化前的 bounds」（驗證最大化時不覆蓋 bounds 的策略）
5. 在外接螢幕內某位置 → 關閉 → 拔掉外接螢幕 → 重開：重設居中（off-screen 防呆）
6. 縮到極小：被 800×450 擋住

## 與舊版的差異

| 項目 | 舊版 (Electron) | 本次 (Flutter) |
|---|---|---|
| 公式 | width > height → 16:9；height > width → 9:16；扣 100 | 完全相同 |
| 取得 workArea | `screen.getPrimaryDisplay().workAreaSize` | `screenRetriever.getPrimaryDisplay().visibleSize` |
| 持久化 | `electron-window-state` 套件 | 自寫 `WindowStateKeeper` + `shared_preferences` |
| 最大化時保存 bounds | 否（套件策略） | 否（沿用） |
| Off-screen 重設門檻 | （`electron-window-state` 內部判斷） | 30%（與 saved 矩形重疊面積） |
| 最小視窗尺寸 | 無 | 800×450（**新增**） |
| frame | `frame: false` + custom titlebar | 系統 frame（**不延用**） |
| Fullscreen 記憶 | 無 | 無 |
