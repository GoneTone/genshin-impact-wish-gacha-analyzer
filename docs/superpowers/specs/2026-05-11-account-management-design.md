# 多帳號管理（持久化最後切換、自訂排序、別名）設計

- 日期：2026-05-11
- 範圍：
  - 修改 `lib/services/settings_storage.dart`（`AppSettings` 新增 3 個欄位、SharedPreferences 序列化）
  - 修改 `lib/state/settings.dart`（`SettingsNotifier` 新增 4 個 API）
  - 修改 `lib/state/wish_repository.dart`（`_bootstrapLoad` 改用 `lastActiveUid`；`setActiveUid` / `removeUid` / `clearActive` / `clearAll` / `importData` / `_fetchAllBanners` 同步 settings）
  - 修改 `lib/widgets/uid_indicator.dart`（主按鈕與下拉選單呈現別名、依排序顯示）
  - 修改 `lib/pages/settings_page.dart`（新增「帳號管理」區塊）
  - 新增 `lib/services/uid_ordering.dart`（純函式 `mergeUidOrder`）
  - 新增 `lib/widgets/cards/account_manager_section.dart`（Settings 頁的帳號管理 UI）
  - 修改 `lib/l10n/app_en.arb` / `app_zh.arb` / `app_zh_Hant.arb`（新增字串）
  - 新增 `test/services/uid_ordering_test.dart`
  - 修改 `test/services/settings_storage_test.dart`（若不存在則新增）
  - 修改 `test/state/wish_repository_test.dart`（新增持久化與 fallback 測試）
  - 新增 `test/widgets/account_manager_section_test.dart`
- 不影響：抽卡資料同步流程（capture / fetch / merge）、其他 page、theme / locale 偏好行為、UpdateProgressDialog

## 目標

1. **持久化最後切換的帳號**：使用者透過 `UidIndicator` 切換 UID 後，下次啟動 app 自動回到上次選擇的 UID。
2. **多帳號排序**：使用者可在 Settings 頁手動拖曳排序自己的帳號清單，影響 `UidIndicator` 下拉選單與啟動 fallback 順序。
3. **帳號別名**：使用者可為每個 UID 設定可讀的別名（例如「主帳」），於 `UidIndicator` 與帳號管理區塊顯示。

## 非目標

- **別名搜尋／分組／emoji**：YAGNI，待真實需求出現再做。
- **別名長度上限**：除了 trim 與「空字串 = 移除別名」的最小驗證，不加任何長度限制；TextField 本身的視覺寬度即為自然約束。
- **雲端同步**：偏好僅存本機。
- **`UidIndicator` 內聯編輯別名**：別名編輯統一在 Settings 頁的帳號管理區塊（單一入口，避免重複實作）。
- **更動 `WishStorage` 檔案格式或目錄結構**：所有偏好用 SharedPreferences 存。
- **自動把新發現的 UID 寫入 `uidOrder`**：採 lazy 策略，未動過排序的使用者直接 fallback 到 `lastUpdated` 排序。

## 異動檔案總覽

| 檔案 | 動作 | 說明 |
|---|---|---|
| `lib/services/settings_storage.dart` | 修改 | `AppSettings` 加 `lastActiveUid` / `uidAliases` / `uidOrder`；SharedPreferences 多 3 個 key |
| `lib/state/settings.dart` | 修改 | `SettingsNotifier` 加 `setLastActiveUid` / `setUidAlias` / `setUidOrder` / `removeUidFromSettings` |
| `lib/state/wish_repository.dart` | 修改 | `_bootstrapLoad` 改 fallback 邏輯；切換 / 刪除 / 匯入 / fetch 完成同步 settings |
| `lib/widgets/uid_indicator.dart` | 修改 | 主按鈕顯示「別名 (UID)」；下拉選單依 `mergeUidOrder` 排序、含別名 |
| `lib/pages/settings_page.dart` | 修改 | 新增「帳號管理」`SectionCard`，內容委派給 `AccountManagerSection` |
| `lib/services/uid_ordering.dart` | 新增 | 純函式 `mergeUidOrder` 提供 UI 與 repository 共用排序邏輯 |
| `lib/widgets/cards/account_manager_section.dart` | 新增 | `ReorderableListView` + 別名 TextField + 刪除按鈕 |
| `lib/l10n/app_en.arb` / `app_zh.arb` / `app_zh_Hant.arb` | 修改 | 新增帳號管理相關字串 |
| `lib/l10n/generated/*` | 由 `flutter gen-l10n` 自動產出 | 不手寫 |
| `test/services/uid_ordering_test.dart` | 新增 | `mergeUidOrder` 純函式測試 |
| `test/services/settings_storage_test.dart` | 新增或修改 | round-trip 新增的 3 個欄位 |
| `test/state/wish_repository_test.dart` | 修改 | 啟動 fallback 各情境、切換 / 刪除持久化測試 |
| `test/widgets/account_manager_section_test.dart` | 新增 | 拖曳 → 寫入 order；編輯別名；刪除走 confirm |

## 設計

### 1. `AppSettings` 與 `SettingsStorage`

`lib/services/settings_storage.dart`：

```dart
@immutable
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.locale,
    this.lastActiveUid,
    this.uidAliases = const {},
    this.uidOrder = const [],
  });

  final AppThemeMode themeMode;
  final AppLocale locale;
  final String? lastActiveUid;
  final Map<String, String> uidAliases; // 沒設別名的 UID 不在 map
  final List<String> uidOrder;          // 自訂順序，可能含已不存在的 UID

  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: AppLocale.system,
  );

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppLocale? locale,
    String? lastActiveUid,
    bool clearLastActiveUid = false,
    Map<String, String>? uidAliases,
    List<String>? uidOrder,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    lastActiveUid:
        clearLastActiveUid ? null : (lastActiveUid ?? this.lastActiveUid),
    uidAliases: uidAliases ?? this.uidAliases,
    uidOrder: uidOrder ?? this.uidOrder,
  );
}
```

SharedPreferences key：
- `pref.lastActiveUid`：String（不存在 = null）
- `pref.uidAliases`：JSON 字串，序列化 `Map<String, String>`
- `pref.uidOrder`：JSON 字串，序列化 `List<String>`

`SettingsStorage.load()` 對 JSON 解析失敗（格式錯誤、舊版本殘留）採「fallback 到預設空值」策略，不丟例外，確保啟動流程穩定。

### 2. 共用合併函式 `mergeUidOrder`

`lib/services/uid_ordering.dart`：

```dart
/// 把使用者自訂排序與目前已知 UID 合併成最終顯示順序。
///
/// 1. customOrder 中仍存在於 knownUids 的 → 保留順序
/// 2. knownUids 中不在 customOrder 的 → 按 lastUpdatedOf desc 接在後面
List<String> mergeUidOrder({
  required Iterable<String> knownUids,
  required List<String> customOrder,
  required DateTime Function(String uid) lastUpdatedOf,
}) {
  final knownSet = knownUids.toSet();
  final inCustom = customOrder.where(knownSet.contains).toList();
  final inCustomSet = inCustom.toSet();
  final rest = knownUids.where((u) => !inCustomSet.contains(u)).toList()
    ..sort((a, b) => lastUpdatedOf(b).compareTo(lastUpdatedOf(a)));
  return [...inCustom, ...rest];
}
```

純函式、無 side effect，方便單元測試與在 UI／repository 任意處共用。

### 3. `SettingsNotifier` 新增 API

`lib/state/settings.dart`：

```dart
Future<void> setLastActiveUid(String? uid) async {
  state = state.copyWith(
    lastActiveUid: uid,
    clearLastActiveUid: uid == null,
  );
  await SettingsStorage.save(state);
}

Future<void> setUidAlias(String uid, String? alias) async {
  final trimmed = alias?.trim();
  final next = Map<String, String>.from(state.uidAliases);
  if (trimmed == null || trimmed.isEmpty) {
    next.remove(uid);
  } else {
    next[uid] = trimmed;
  }
  state = state.copyWith(uidAliases: next);
  await SettingsStorage.save(state);
}

Future<void> setUidOrder(List<String> order) async {
  state = state.copyWith(uidOrder: List.unmodifiable(order));
  await SettingsStorage.save(state);
}

Future<void> removeUidFromSettings(String uid) async {
  final aliases = Map<String, String>.from(state.uidAliases)..remove(uid);
  final order = state.uidOrder.where((u) => u != uid).toList();
  state = state.copyWith(uidAliases: aliases, uidOrder: order);
  await SettingsStorage.save(state);
}

Future<void> clearAllUidPreferences() async {
  state = state.copyWith(
    clearLastActiveUid: true,
    uidAliases: const {},
    uidOrder: const [],
  );
  await SettingsStorage.save(state);
}
```

`removeUidFromSettings` 不處理 `lastActiveUid`，由 `WishRepository` 在計算完新的 active UID 後再呼叫 `setLastActiveUid`，避免兩處同時管理同一個欄位。`clearAllUidPreferences` 一次清三個欄位（給 `WishRepository.clearAll` 使用），避免連續多次寫入。

### 4. `WishRepository` 整合

`lib/state/wish_repository.dart`：

**`_bootstrapLoad`**：

```dart
Future<void> _bootstrapLoad() async {
  final storage = ref.read(wishStorageProvider);
  final settingsNotifier = ref.read(settingsProvider.notifier);
  await settingsNotifier.waitForLoad();
  if (!ref.mounted) return;

  final uids = await storage.listKnownUids();
  if (!ref.mounted) return;

  final byUid = <String, BannerStorage>{};
  for (final uid in uids) {
    final data = await storage.load(uid);
    if (!ref.mounted) return;
    if (data != null) byUid[uid] = data;
  }

  if (byUid.isEmpty) {
    state = state.copyWith(byUid: byUid, isBootstrapping: false);
    return;
  }

  final settings = ref.read(settingsProvider);
  final ordered = mergeUidOrder(
    knownUids: byUid.keys,
    customOrder: settings.uidOrder,
    lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
  );

  final saved = settings.lastActiveUid;
  final activeUid = (saved != null && byUid.containsKey(saved))
      ? saved
      : ordered.first;

  state = state.copyWith(
    byUid: byUid,
    activeUid: activeUid,
    isBootstrapping: false,
  );

  // 若 saved 失效或為 null，把實際選中的寫回 settings 保持一致
  if (saved != activeUid) {
    await settingsNotifier.setLastActiveUid(activeUid);
  }
}
```

**`setActiveUid`**：

```dart
Future<void> setActiveUid(String uid) async {
  if (!state.byUid.containsKey(uid)) return;
  state = state.copyWith(activeUid: uid);
  await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
}
```

**`removeUid` 與 `clearActive`** 抽出共用的「重新計算 active UID」邏輯：

```dart
String? _pickFallbackActive(Map<String, BannerStorage> byUid) {
  if (byUid.isEmpty) return null;
  final order = ref.read(settingsProvider).uidOrder;
  return mergeUidOrder(
    knownUids: byUid.keys,
    customOrder: order,
    lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
  ).first;
}

Future<void> removeUid(String uid) async {
  final storage = ref.read(wishStorageProvider);
  final settingsNotifier = ref.read(settingsProvider.notifier);

  await storage.delete(uid);
  if (!ref.mounted) return;
  await settingsNotifier.removeUidFromSettings(uid);
  if (!ref.mounted) return;

  final newByUid = Map<String, BannerStorage>.from(state.byUid)..remove(uid);
  if (state.activeUid == uid) {
    final next = _pickFallbackActive(newByUid);
    state = next == null
        ? state.copyWith(byUid: newByUid, clearActiveUid: true)
        : state.copyWith(byUid: newByUid, activeUid: next);
    await settingsNotifier.setLastActiveUid(next);
  } else {
    state = state.copyWith(byUid: newByUid);
  }
}

Future<void> clearActive() async {
  final uid = state.activeUid;
  if (uid == null) return;
  await removeUid(uid); // 委派，避免重複邏輯
}
```

**`clearAll`**：

```dart
Future<void> clearAll() async {
  final storage = ref.read(wishStorageProvider);
  await storage.clearAll();
  if (!ref.mounted) return;
  await ref.read(settingsProvider.notifier).clearAllUidPreferences();
  state = const WishState(isBootstrapping: false);
}
```

一次清三個欄位，使用 §3 定義的 `clearAllUidPreferences()`。

**`importData` 與 `_fetchAllBanners`** 在切換 active UID 後呼叫：

```dart
await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
```

### 5. `UidIndicator` 變更

`lib/widgets/uid_indicator.dart`：

- watch `settingsProvider` 取得 `uidAliases` / `uidOrder`
- 列表用 `mergeUidOrder(...)` 排序
- 顯示 helper：

```dart
String _displayName(String uid, Map<String, String> aliases) {
  final alias = aliases[uid];
  return alias == null ? uid : '$alias ($uid)';
}
```

- **主按鈕**：用 `_displayName(activeUid, aliases)`
- **下拉選單每項**：alias（粗體）為主、UID 為小字 subtitle；沒 alias 就只顯示 UID（與原行為一致）

### 6. Settings 頁「帳號管理」區塊

`lib/pages/settings_page.dart` 插入新的 `SectionCard`，內容委派給新元件：

`lib/widgets/cards/account_manager_section.dart`：

```dart
class AccountManagerSection extends ConsumerWidget {
  const AccountManagerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishState = ref.watch(wishRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final l = AppLocalizations.of(context)!;

    if (wishState.byUid.isEmpty) {
      return EmptyState(text: l.accountManagementEmpty);
    }

    final ordered = mergeUidOrder(
      knownUids: wishState.byUid.keys,
      customOrder: settings.uidOrder,
      lastUpdatedOf: (u) => wishState.byUid[u]!.lastUpdated,
    );

    return ReorderableListView.builder(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      itemCount: ordered.length,
      itemBuilder: (context, index) {
        final uid = ordered[index];
        return _AccountRow(
          key: ValueKey(uid),
          uid: uid,
          alias: settings.uidAliases[uid],
          index: index,
        );
      },
      onReorder: (oldIndex, newIndex) async {
        final next = [...ordered];
        final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
        final item = next.removeAt(oldIndex);
        next.insert(adjusted, item);
        await ref.read(settingsProvider.notifier).setUidOrder(next);
      },
    );
  }
}
```

`_AccountRow` 內含：
- `ReorderableDragStartListener` 包住的拖曳 handle（`Icons.drag_handle`）
- UID 文字
- 別名 `TextField`：`onSubmitted` 與 `onTapOutside`／`focusNode` 失焦時呼叫 `setUidAlias(uid, value)`；空字串 = 移除
- 刪除 `IconButton`：呼叫 `ConfirmDialog`（既有 `lib/widgets/dialogs/confirm_dialog.dart`）→ 確認後呼叫 `wishRepositoryProvider.notifier.removeUid(uid)`

**避免重新發明輪子**：empty state 用既有 `lib/widgets/empty_state.dart`；confirm dialog 用既有 `lib/widgets/dialogs/confirm_dialog.dart`；卡片外觀沿用 `SectionCard`。

### 7. i18n 新字串

`lib/l10n/app_zh_Hant.arb`：

```json
"accountManagementTitle": "帳號管理",
"accountManagementEmpty": "尚未同步任何帳號",
"aliasFieldLabel": "別名",
"aliasFieldHint": "為此帳號取一個好記的名稱",
"accountDeleteConfirmTitle": "刪除此帳號的資料？",
"accountDeleteConfirmMessage": "將會刪除此帳號（{uid}）的所有抽卡紀錄，此動作無法復原。",
"@accountDeleteConfirmMessage": {
  "placeholders": { "uid": { "type": "String" } }
}
```

`lib/l10n/app_zh.arb` 與 `lib/l10n/app_en.arb` 提供對應翻譯。執行 `flutter gen-l10n` 重新產出 `lib/l10n/generated/*`。

### 8. 啟動順序

`WishRepository._bootstrapLoad` 開頭加 `await settingsNotifier.waitForLoad()` 確保 settings 已載入。`SettingsNotifier` 既有的 `waitForLoad` 公開 API（@visibleForTesting 的部分需取消註解或改為正式 API）原本只供測試使用，此處轉為正式用途，應移除 `@visibleForTesting` 註解並寫入文件說明用途。

### 9. 邊界情境

| 情境 | 行為 |
|---|---|
| 首次安裝、無任何 UID | byUid 空 → activeUid 仍為 null，不寫入 lastActiveUid |
| 上次保存的 UID 已不在 byUid | fallback 到 `mergeUidOrder` 第一個，並把實際選中的寫回 settings |
| `uidOrder` 含已刪除的 UID | `mergeUidOrder` 過濾掉，但保留在 settings.uidOrder（lazy 清理；下一次 `removeUidFromSettings` 或 `setUidOrder` 會清掉） |
| 別名 trim 後為空字串 | 視為移除別名（從 `uidAliases` map 刪除該 key） |
| 編輯別名為純空白 | 同上，trim 後為空 = 移除 |
| 拖曳途中清掉資料／切頁 | `ReorderableListView` 自己處理；`onReorder` 內 await 設定，失敗時下一次 rebuild 會以 settings 為準回正 |
| `clearAll` 後 byUid 與 uid 偏好都清空 | activeUid = null，下次同步新 UID 後正常 |
| 兩個來源（settings vs. byUid）短暫不一致 | UI 都從 `mergeUidOrder` 取，自動過濾不存在的 UID，不會崩潰 |
| 別名重複（兩個 UID 設了相同別名） | 允許；UidIndicator 顯示 `別名 (UID)` 仍可區分 |

### 10. 測試策略

**`test/services/uid_ordering_test.dart`**（新增）：
- 空 `customOrder` → 全部按 `lastUpdated` desc
- `customOrder` 全部覆蓋 → 維持 customOrder
- `customOrder` 含已不存在的 UID → 過濾掉
- `customOrder` 部分覆蓋 → 已排序的優先、新 UID 接尾端
- `knownUids` 為空 → 回傳空 list

**`test/services/settings_storage_test.dart`**（新增或補強）：
- round-trip `lastActiveUid` / `uidAliases` / `uidOrder`
- 舊資料（無新 key）載入 → 對應欄位為預設值
- JSON 解析失敗（手動寫入壞掉的 JSON 字串）→ fallback 為預設值

**`test/state/wish_repository_test.dart`**（修改）：
- bootstrap：`lastActiveUid` 命中 → 用它
- bootstrap：`lastActiveUid` 失效 → fallback 為 `mergeUidOrder.first` 且寫回 settings
- bootstrap：`lastActiveUid` 為 null → fallback 並寫回 settings
- bootstrap：byUid 為空 → activeUid 為 null，不寫 settings
- `setActiveUid` → settings 同步
- `removeUid`（非 active）→ settings.aliases / order 清理，lastActiveUid 不變
- `removeUid`（active）→ settings 完整同步、選出新 active 且寫回
- `clearAll` → settings UID 偏好全清
- 用 `mergeUidOrder` 排序的順序在 `_pickFallbackActive` 的回傳值上得到驗證

**`test/widgets/account_manager_section_test.dart`**（新增）：
- 渲染 N 個 row、別名顯示正確
- 編輯別名 → `setUidAlias` 被呼叫、空字串 → null
- 拖曳 → `setUidOrder` 被呼叫且順序正確（用 `WidgetTester.drag` 或直接觸發 `onReorder`）
- 刪除 → confirm dialog 出現 → 確認 → `removeUid` 被呼叫
- 空狀態：byUid 空時顯示 empty state 文案

### 11. 提交前檢查

- `dart format lib/ test/`
- `flutter analyze` → No issues found!
- `flutter test` → All tests passed!

## 風險與權衡

| 風險 | 緩解 |
|---|---|
| `settings` 與 `wishRepository` 雙向耦合（bootstrap 互相依賴） | `_bootstrapLoad` 內 `await waitForLoad()` 強制單向順序：settings 先就緒、repo 才繼續 |
| `uidOrder` lazy 累積已刪除 UID | `mergeUidOrder` 過濾、`removeUidFromSettings` 主動清理；不影響正確性 |
| 別名 JSON 序列化失敗（使用者手動竄改 prefs） | `SettingsStorage.load` fallback 為預設空 map／list，不丟例外 |
| 別名 TextField 失焦邏輯在 widget test 較難 trigger | 額外暴露 `onSubmitted` callback 路徑供測試呼叫 |
| `ReorderableListView` 在小高度 Settings 頁需要 `shrinkWrap: true` + 外層 scroll | 用既有 Settings 頁 scroll 容器；`shrinkWrap: true` + `NeverScrollableScrollPhysics` 避免內外 scroll 衝突 |
| 別名重複可能讓使用者誤判 | 顯示時並列 UID，足以區分；不強制唯一 |
