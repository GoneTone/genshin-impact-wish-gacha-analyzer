# 設定頁首幀卡頓修復 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除「第一次進入設定頁卡一下」的觀感,並收斂訂閱粒度避免不必要 rebuild。

**Architecture:** 三個獨立、可單獨 commit 的小重構:(B) `localeMetadataProvider` 從 `FutureProvider` 改成同步 `Provider`,移除 `_LocaleDropdown` / `_LanguageList` 的首幀 loading spinner;(A) `BannerLink` 加 `cacheHeight`,讓 PNG decode 直接縮到 64dp 對應的物理像素而非全解析度;(C) `SettingsPage` / `_DataManagement` / `AccountManagement` 的 `ref.watch` 改用 `select` 收斂訂閱範圍。

**Tech Stack:** Flutter / Dart、`flutter_riverpod`(`Provider` / `FutureProvider` / `select`)、`flutter_test`、Material 3。

**Spec:** `docs/superpowers/specs/2026-05-13-settings-page-first-frame-lag-design.md`

---

## File Structure

| File | Action | 責任 |
|---|---|---|
| `lib/state/localization_metadata.dart` | Modify | provider 改同步、保留 `_isBareBaseOfSpecificVariant` 過濾邏輯 |
| `lib/pages/settings_page.dart` | Modify | `_LocaleDropdown` 拆掉 `.when`;`SettingsPage.build` 與 `_DataManagement.build` 改 `select` |
| `lib/pages/contributors_page.dart` | Modify | `_LanguageList` 拆掉 `.when` |
| `lib/widgets/banner_link.dart` | Modify | `Image.asset` 加 `cacheHeight` |
| `lib/widgets/cards/account_management.dart` | Modify | `AccountManagement.build` 拆成 4 個 `select` |
| `test/l10n/locale_metadata_test.dart` | Modify | 兩處 `localeMetadataProvider.future` 改成同步 `read` |

無新增檔案。每個 task 改完後跑既有測試確認無回歸。

---

## Pre-flight

- [ ] **Step 0: 跑一次 baseline 測試與 analyze 確認當前全綠**

Run:
```powershell
flutter analyze
flutter test
```
Expected:
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`

如果一開始就有失敗,**停下來**確認是否是先前未提交的問題,不要把這些失敗算到本 plan 帳上。

---

## Task 1: B — `localeMetadataProvider` 改同步 `Provider`

**Files:**
- Modify: `lib/state/localization_metadata.dart:28-42`
- Modify: `lib/pages/settings_page.dart:138-181` (`_LocaleDropdown.build`)
- Modify: `lib/pages/contributors_page.dart:113-150` (`_LanguageList.build`)
- Modify: `test/l10n/locale_metadata_test.dart:80,104`

### 為什麼先做這個

改 provider 型別連動 3 個 caller + 1 個測試,先把這個拆乾淨後,後續 task 不再受其牽動。對「首次卡頓」也最直接 — 拿掉 `AsyncLoading` frame。

### Step 1: 先把 test 改成預期同步 API,跑 fail

`test/l10n/locale_metadata_test.dart` 把第 80 行與第 104 行的兩處改寫:

第 80 行附近 (`'排除 bare zh ...'` test):
```dart
test('排除 bare zh（已有 zh-Hant / zh-Hans 變體存在）', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final metadata = container.read(localeMetadataProvider);
  final tags = metadata.keys.toSet();

  // bare zh 應被過濾掉（有 script 變體存在）
  expect(
    tags,
    isNot(contains('zh')),
    reason: 'bare zh 跟 zh_Hant / zh_Hans 重複，應排除',
  );

  // 中文 script 變體保留
  expect(tags, containsAll(<String>['zh-Hant', 'zh-Hans']));

  // 葡萄牙文只有單一 ARB（已整併 pt_BR），bare pt 不被過濾
  expect(tags, contains('pt'));

  // 沒有變體的單一語言（en/ja/...）保留
  expect(tags, containsAll(<String>['en', 'ja', 'es', 'fr', 'th', 'vi']));
});
```

第 100 行附近 (`'每個保留的 locale 都有非空的 nativeName'` test):
```dart
test('每個保留的 locale 都有非空的 nativeName', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final metadata = container.read(localeMetadataProvider);
  for (final entry in metadata.entries) {
    expect(
      entry.value.nativeName,
      isNotEmpty,
      reason: '${entry.key} 的 nativeName 不能為空',
    );
  }
});
```

兩處變動:
- callback 從 `() async {}` 改成 `() {}`(移除 `async`)
- `await container.read(localeMetadataProvider.future)` 改成 `container.read(localeMetadataProvider)`(移除 `await` 與 `.future`)

### Step 2: 跑修改的測試,確認 fail

Run:
```powershell
flutter test test/l10n/locale_metadata_test.dart
```
Expected: 失敗,訊息類似 `The argument type 'FutureProvider<...>' can't be assigned to the parameter type 'ProviderListenable<...>'` 或 build/runtime 編譯錯誤(因為 `.read(provider)` 對 `FutureProvider` 回的是 `AsyncValue` 而非 `Map`)。

### Step 3: 改 provider 為同步 `Provider`

`lib/state/localization_metadata.dart` 把 `localeMetadataProvider` 整段 (28-42 行) 換成:

```dart
/// 一次性 load 所有 [AppLocalizations.supportedLocales] 的 metadata；
/// Settings 語言選單與 About / Contributors 區塊讀此 provider。
///
/// `delegate.load` 對 gen_l10n 編譯後的 const 內容回傳 [SynchronousFuture]，
/// 所以 `.then` callback 在同個 stack frame 內同步觸發、無 microtask 跳轉，
/// 也就不會多畫一個 `AsyncLoading` frame（避免設定頁進入時的 spinner 閃）。
///
/// 自動排除 gen_l10n 為支援 script/country 變體而生成的「裸」base locale
/// （如 `zh` 是 `zh_Hant` + `zh_Hans` 的 fallback base、`pt` 是 `pt_BR` 的
/// fallback base）——這些 bare locale 沒有獨立的 `localeNativeName`，在
/// dropdown 會跟具體變體重複顯示。
///
/// 註：此 provider 的同步性依賴 gen_l10n 對 const 內容回 SynchronousFuture
/// 的實作慣例。若未來 gen_l10n 改變 (例如改 async load asset)，此 provider
/// 內 `result` 會空，需退回 FutureProvider。
final localeMetadataProvider = Provider<Map<String, LocaleMetadata>>((ref) {
  final all = AppLocalizations.supportedLocales;
  final result = <String, LocaleMetadata>{};
  for (final locale in all) {
    if (_isBareBaseOfSpecificVariant(locale, all)) continue;
    AppLocalizations.delegate.load(locale).then((l) {
      result[locale.toLanguageTag()] = LocaleMetadata(
        nativeName: l.localeNativeName,
        translator: l.localeTranslator,
      );
    });
  }
  return result;
});
```

不要動 `_isBareBaseOfSpecificVariant`、`localeListResolution`、`sortedLocaleMetadata`,以及檔案上方 `LocaleMetadata` class 與 import。

### Step 4: 跑 test,確認 pass

Run:
```powershell
flutter test test/l10n/locale_metadata_test.dart
```
Expected: PASS(全部 group 綠)。

### Step 5: 改 `_LocaleDropdown` 移除 `.when`

`lib/pages/settings_page.dart` 把 `_LocaleDropdown.build`(行 137-181)整個 method body 換成:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final metadata = ref.watch(localeMetadataProvider);
  final sorted = sortedLocaleMetadata(metadata);
  final selectableTags = metadata.keys.toSet();
  // 防禦：使用者過去可能存了 supportedLocales 已不存在的代碼（例如
  // 整併前的 "pt-BR"）。若 current 不在當前 dropdown 選項裡，顯示為
  // SystemLanguage 避免 DropdownButtonFormField 因 value 找不到對應
  // 項目而 assert failed。
  final effectiveCurrent =
      current is SystemLanguage ||
          (current is LocaleLanguage &&
              selectableTags.contains((current as LocaleLanguage).code))
      ? current
      : const SystemLanguage();
  return DropdownButtonFormField<LanguagePreference>(
    initialValue: effectiveCurrent,
    decoration: const InputDecoration(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    items: [
      DropdownMenuItem(
        value: const SystemLanguage(),
        child: Text(l.settingsLocaleSystem),
      ),
      for (final entry in sorted)
        DropdownMenuItem(
          value: LocaleLanguage(entry.key),
          child: Text(entry.value.nativeName),
        ),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}
```

對比變動:
- 移除 `final asyncMeta = ref.watch(localeMetadataProvider);` 與外層的 `asyncMeta.when(data: ..., loading: ..., error: ...)`
- `metadata` 直接從 `ref.watch` 拿到 `Map<String, LocaleMetadata>`
- 內部建構 dropdown 的程式碼原樣保留(從 `final sorted` 到 return 結束)

### Step 6: 改 `_LanguageList` 移除 `.when`

`lib/pages/contributors_page.dart` 把 `_LanguageList.build`(行 116-149)整個 method body 換成:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final metadata = ref.watch(localeMetadataProvider);
  final sorted = sortedLocaleMetadata(metadata);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in sorted)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: entry.value.translator.isEmpty
              ? Text(entry.value.nativeName)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${entry.value.nativeName} — '),
                    Expanded(
                      child: TranslatorText(raw: entry.value.translator),
                    ),
                  ],
                ),
        ),
    ],
  );
}
```

對比變動:
- 拿掉 `asyncMeta.when(...)` 包裝與其 `loading` / `error` 分支
- `metadata` 與 `sorted` 直接同步取得

### Step 7: 跑相關 widget 測試確認無回歸

Run:
```powershell
flutter test test/pages/contributors_page_test.dart test/l10n/locale_metadata_test.dart
```
Expected: PASS。

### Step 8: 全部測試 + analyze + format

Run:
```powershell
dart format lib/ test/
flutter analyze
flutter test
```
Expected:
- `dart format` 可能更動空白,確認沒改到非預期檔
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`

### Step 9: Commit

```powershell
git add lib/state/localization_metadata.dart lib/pages/settings_page.dart lib/pages/contributors_page.dart test/l10n/locale_metadata_test.dart
git commit -m @'
perf(settings): make localeMetadataProvider sync to drop loading frame

The FutureProvider always yielded an AsyncLoading frame on first watch,
even though delegate.load returns SynchronousFuture for gen_l10n const
content. That frame painted a CircularProgressIndicator before the locale
dropdown rendered, producing the "settings page flashes when entering"
feel. Switch to a sync Provider and drop the .when wrappers.
'@
```

---

## Task 2: A — `BannerLink` 加 `cacheHeight`

**Files:**
- Modify: `lib/widgets/banner_link.dart:51-55`
- Test: `test/widgets/banner_link_test.dart`(既有測試)

### Step 1: 新增測試驗證 cacheHeight 套用

在 `test/widgets/banner_link_test.dart` 第一個 `testWidgets('渲染 Image 並套用指定 height', ...)`(行 7-26)後面、`testWidgets('hover 時 cursor ...')`(行 28)前面新增:

```dart
testWidgets('指定 cacheHeight 為 height × devicePixelRatio', (tester) async {
  // 用一個明確的 dpr 確保斷言可預期；MediaQuery 預設 dpr=1.0。
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2.0),
        child: const Scaffold(
          body: BannerLink(
            assetPath: 'assets/banners/gonetone_banner.png',
            url: 'https://example.test',
            semanticLabel: 'test banner',
            height: 64,
          ),
        ),
      ),
    ),
  );

  final image = tester.widget<Image>(find.byType(Image));
  // height=64, dpr=2.0 → cacheHeight=128
  expect(image, isA<Image>());
  expect(
    (image.image as ResizeImage).height,
    128,
    reason: 'cacheHeight 應為 height(64) × devicePixelRatio(2.0) = 128',
  );
});
```

註:Flutter `Image.asset(..., cacheHeight: x)` 內部會把 provider 包成 `ResizeImage(height: x)`。`ResizeImage.width / height` 是 nullable;這裡只設 `cacheHeight` 所以 `width` 應為 `null`。

### Step 2: 跑測試確認 fail

Run:
```powershell
flutter test test/widgets/banner_link_test.dart -p vm
```
Expected: FAIL — 因為原始 `Image.asset` 無 `cacheHeight`,`image.image` 仍為 `AssetImage` 而非 `ResizeImage`,cast 會丟例外。

### Step 3: 修改 `BannerLink` 加 `cacheHeight`

`lib/widgets/banner_link.dart` `_BannerLinkState.build`(行 35-61)整段 method body 換成:

```dart
@override
Widget build(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return Tooltip(
    message: widget.semanticLabel,
    child: Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: AnimatedOpacity(
            opacity: _hovering ? 0.85 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Image.asset(
              widget.assetPath,
              height: widget.height,
              fit: BoxFit.contain,
              // 只設 cacheHeight，寬度按比例縮，避免 banner 變形。
              // 用 MediaQuery 的 dpr 而非寫死，正確支援高 DPI 螢幕。
              cacheHeight: (widget.height * dpr).round(),
            ),
          ),
        ),
      ),
    ),
  );
}
```

不要動其他 method (`_handleTap`、widget class 本身)。

### Step 4: 跑測試確認 pass

Run:
```powershell
flutter test test/widgets/banner_link_test.dart
```
Expected: PASS — 既有 6 個 test 與新增 1 個 test 全綠。

### Step 5: format + analyze

Run:
```powershell
dart format lib/widgets/banner_link.dart test/widgets/banner_link_test.dart
flutter analyze
```
Expected: `flutter analyze` → `No issues found!`。

### Step 6: Commit

```powershell
git add lib/widgets/banner_link.dart test/widgets/banner_link_test.dart
git commit -m @'
perf(banner-link): set cacheHeight to avoid full-resolution decode

Image.asset without cacheWidth/cacheHeight decodes the PNG at native
resolution before scaling to the displayed height. The settings page
about section renders two banners (954x200 and 360x191) at 64dp; the
cold decode cost is perceptible on Windows debug. Compute cacheHeight
from MediaQuery dpr so the raster matches the physical display size.
'@
```

---

## Task 3: C — 收斂訂閱粒度

**Files:**
- Modify: `lib/pages/settings_page.dart:32-36` (`SettingsPage.build`)
- Modify: `lib/pages/settings_page.dart:240-282` (`_DataManagement.build`)
- Modify: `lib/widgets/cards/account_management.dart:18-32` (`AccountManagement.build`)

### Step 1: 改 `SettingsPage.build`

`lib/pages/settings_page.dart` 把 `SettingsPage.build` 開頭(行 32-36):

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final settings = ref.watch(settingsProvider);
  final notifier = ref.read(settingsProvider.notifier);
```

換成:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
  final localePref = ref.watch(settingsProvider.select((s) => s.locale));
  final notifier = ref.read(settingsProvider.notifier);
```

然後把 method 後續用到 `settings.themeMode` / `settings.locale` 的地方換成新名稱:
- `current: settings.themeMode` → `current: themeMode`(行 50)
- `current: settings.locale` → `current: localePref`(行 60)

`settings.uidAliases` / `settings.uidOrder` 不在此 method 直接使用,不用改。

### Step 2: 改 `_DataManagement.build`

`lib/pages/settings_page.dart` 把 `_DataManagement.build`(行 241-282)開頭兩行:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final state = ref.watch(wishRepositoryProvider);
  final hasData = state.byUid.isNotEmpty;
```

換成:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final hasData = ref.watch(
    wishRepositoryProvider.select((s) => s.byUid.isNotEmpty),
  );
  final activeUid = ref.watch(
    wishRepositoryProvider.select((s) => s.activeUid),
  );
```

method 內後續用到 `state.activeUid` 的兩處(行 265、267)換成 `activeUid`:
- `onPressed: state.activeUid == null` → `onPressed: activeUid == null`
- `() => _clearActive(context, ref, state.activeUid!)` → `() => _clearActive(context, ref, activeUid!)`

`_export` / `_import` / `_clearActive` / `_clearAll` 等 method 內的 `ref.read(...)` 不動。

### Step 3: 改 `AccountManagement.build`

`lib/widgets/cards/account_management.dart` 把 `AccountManagement.build`(行 17-33)開頭:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final tokens = Theme.of(context).gacha;
  final state = ref.watch(wishRepositoryProvider);
  final settings = ref.watch(settingsProvider);
  final notifier = ref.read(wishRepositoryProvider.notifier);
  final settingsNotifier = ref.read(settingsProvider.notifier);

  final ordered = state.byUid.isEmpty
      ? const <String>[]
      : mergeUidOrder(
          knownUids: state.byUid.keys,
          customOrder: settings.uidOrder,
          lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
        );
```

換成:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final tokens = Theme.of(context).gacha;
  final byUid = ref.watch(
    wishRepositoryProvider.select((s) => s.byUid),
  );
  final activeUid = ref.watch(
    wishRepositoryProvider.select((s) => s.activeUid),
  );
  final uidAliases = ref.watch(
    settingsProvider.select((s) => s.uidAliases),
  );
  final uidOrder = ref.watch(
    settingsProvider.select((s) => s.uidOrder),
  );
  final notifier = ref.read(wishRepositoryProvider.notifier);
  final settingsNotifier = ref.read(settingsProvider.notifier);

  final ordered = byUid.isEmpty
      ? const <String>[]
      : mergeUidOrder(
          knownUids: byUid.keys,
          customOrder: uidOrder,
          lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
        );
```

接著 method 後續(行 34-86)用到的舊變數對應換新:
- `state.byUid[uid]!.lastUpdated`(itemBuilder 內) → `byUid[uid]!.lastUpdated`
- `uid == state.activeUid` → `uid == activeUid`
- `settings.uidAliases[uid] ?? ''` → `uidAliases[uid] ?? ''`

注意:`_remove` private method 內部 `ref.read(wishRepositoryProvider.notifier).removeUid(uid)` 不動(read 不訂閱)。

### Step 4: 跑全測試 + analyze + format

Run:
```powershell
dart format lib/ test/
flutter analyze
flutter test
```
Expected:
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`

如有測試 fail,常見原因是:
- `select` 用到的 `byUid: Map<String, AccountData>` 等型別 — 確認 `wish_repository.dart` 的對應 getter 名稱與型別一致
- `hasData` 變成 `bool` 後,`onPressed: !hasData ? null : ...` 仍然可用

### Step 5: Commit

```powershell
git add lib/pages/settings_page.dart lib/widgets/cards/account_management.dart
git commit -m @'
perf(settings): narrow ref.watch to fields actually used

SettingsPage / _DataManagement / AccountManagement watched whole
providers, so any unrelated field change rebuilt the entire page (e.g.,
flipping uidAliases rebuilt _ThemeRadios and _LocaleDropdown). Use
ref.watch(...select(...)) so each widget only rebuilds on the slice it
reads.
'@
```

---

## Final Verification

- [ ] **Step 1: 完整品質檢查**

Run(順序按 CLAUDE.md):
```powershell
dart format lib/ test/
flutter analyze
flutter test
```
Expected:
- `dart format` 應無輸出(前面 task 都已 format 過)
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`

- [ ] **Step 2: 手動觀感驗證(無法自動化,只能跑 app 看)**

Run:
```powershell
flutter run -d windows
```

驗證項:
1. **冷啟後第一次進設定頁**:不再閃 spinner、不再有明顯卡頓
2. **語言切換**:dropdown 正常開合、選擇生效
3. **主題切換**:radio 正常切換
4. **帳號管理**(若有帳號資料):
   - 列表正常顯示
   - alias 編輯後 blur 自動保存
   - reorder drag handle 可拖動
   - "設為作用中" / "移除" 按鈕正常
5. **匯入 / 匯出**:dialog 正常開合
6. **About 區塊**:兩張 banner 仍清晰、可點(會開外部瀏覽器)、hover opacity 動畫正常
7. **Contributors 頁**:語言列表正常顯示翻譯者署名

- [ ] **Step 3:(可選)如果想確認 perf 改善幅度**

在 `_LocaleDropdown` 改前後分別跑:
```powershell
flutter run -d windows --profile
```
從第一次切到設定頁時的 frame timing(透過 DevTools Performance tab)觀察:
- 改前:首幀有明顯 raster build > 16ms 的 spike
- 改後:首幀 build 時間應 < 16ms,連續幀無 dropped frames

此步驟是 nice-to-have,不是必要驗證。

---

## Self-Review Checklist

(本 plan 寫完後自我檢視結果,留紀錄供 review 時參考)

1. **Spec coverage** ✓
   - A → Task 2
   - B → Task 1(含 settings_page、contributors_page、test 3 個 caller)
   - C → Task 3(含 SettingsPage、_DataManagement、AccountManagement 3 個位置)
   - 驗收標準 1-3 → Final Verification Step 2
   - 驗收標準 4(format / analyze / test) → 各 task Step 內有,Final Verification Step 1 再跑一次

2. **Placeholder scan** ✓ — 無 TBD / TODO / "appropriate ..." / "similar to Task N"

3. **Type consistency** ✓
   - `localeMetadataProvider` 在 Task 1 改成 `Provider<Map<String, LocaleMetadata>>`,Task 1 內所有 caller 對應改 `ref.watch` 直接拿 `Map`
   - `byUid` / `activeUid` 等 `select` 名稱在 Task 3 內統一
   - `localePref`(SettingsPage)與 `current`(`_LocaleDropdown` 參數)是不同 scope,沒衝突

4. **YAGNI 對齊** ✓ — 沒新增 abstraction、沒預留參數、沒做 lazy build / sliver 等過度工程
