# 設定頁首幀卡頓修復

> 2026-05-13

## 背景與問題

第一次進入設定頁時會「明顯卡一下」,離開再進入(熱快取)就不太感覺到。
平台:Windows debug build。

## 根因(來自程式碼閱讀)

進設定頁的首次冷成本主要來自兩處,加上一處間接的 rebuild 噪音:

### 1. Banner 圖片 cold decode(`lib/widgets/banner_link.dart:51-55`)

`_AboutContent` 同時渲染兩張 banner,使用 `Image.asset(..., height: 64)` 但**未指定** `cacheWidth` / `cacheHeight`。
Flutter 因此把 PNG decode 成原生解析度再縮到 64dp:

| 檔案                       | 原生解析度  |
|--------------------------|--------|
| `gonetone_banner.png`    | 954×200 |
| `genshin_info_banner.png`  | 360×191 |

Windows debug 上 raster 寫入與 GPU 上傳成本可感。第二次進入因為 `ImageCache` 已有 cache,觀感變順。

### 2. `localeMetadataProvider` 的 loading frame(`lib/state/localization_metadata.dart:28-42`)

`localeMetadataProvider` 是 `FutureProvider<Map<String, LocaleMetadata>>`。
即使內部的 `AppLocalizations.delegate.load(locale)` 對 `gen_l10n` 編譯後的 const 內容回 `SynchronousFuture`(provider 自己的註解已承認這點),`FutureProvider` 仍會先 yield 一個 `AsyncLoading` frame。
`_LocaleDropdown` 因此在進設定頁的首幀畫一個 `CircularProgressIndicator`(`lib/pages/settings_page.dart:175-178`),microtask 後才換成真正的 `DropdownButtonFormField`。這就是「進入瞬間閃一下」的元兇。

### 3. 訂閱粒度過粗(間接)

`SettingsPage`、`_DataManagement`、`AccountManagement` 都 `ref.watch(整顆 provider)`。
任何 settings 欄位變更會觸發整頁 rebuild。對「首次卡」沒幫助,但會放大「在設定頁裡操作時的延遲」。

## 修復範圍(YAGNI)

| 做                                                   | 不做                                            |
|-----------------------------------------------------|-----------------------------------------------|
| A. `BannerLink` 加 `cacheHeight`                     | 不改 banner 圖檔本身解析度                              |
| B. `localeMetadataProvider` 改同步 `Provider`          | 不預熱 image / provider(B 改完已不需要)                 |
| C. 收斂 `SettingsPage` / `_DataManagement` / `AccountManagement` 訂閱粒度 | 不改 router 200ms fade(設計動畫,非 lag)              |
|                                                     | 不重寫 SettingsPage 結構,不引入 sliver / lazy build   |

## 詳細設計

### A. `BannerLink` 加 `cacheHeight`

**位置**:`lib/widgets/banner_link.dart` `_BannerLinkState.build` 內 `Image.asset` 的呼叫點。

**改前**:
```dart
Image.asset(
  widget.assetPath,
  height: widget.height,
  fit: BoxFit.contain,
)
```

**改後**:
```dart
final dpr = MediaQuery.devicePixelRatioOf(context);
...
Image.asset(
  widget.assetPath,
  height: widget.height,
  fit: BoxFit.contain,
  cacheHeight: (widget.height * dpr).round(),
)
```

**設計選擇**:
- 只設 `cacheHeight`,不設 `cacheWidth` — 寬度按比例縮,避免 banner 變形。
- 用 `MediaQuery.devicePixelRatioOf(context)` 而非寫死 dpr,以正確支援高 DPI 螢幕。
- 不額外做 `precacheImage`,避免提前佔用 ImageCache 與啟動時間。

### B. `localeMetadataProvider` 改同步 `Provider`

**位置**:`lib/state/localization_metadata.dart`

**改前**:
```dart
final localeMetadataProvider = FutureProvider<Map<String, LocaleMetadata>>((
  ref,
) async {
  final all = AppLocalizations.supportedLocales;
  final result = <String, LocaleMetadata>{};
  for (final locale in all) {
    if (_isBareBaseOfSpecificVariant(locale, all)) continue;
    final l = await AppLocalizations.delegate.load(locale);
    result[locale.toLanguageTag()] = LocaleMetadata(
      nativeName: l.localeNativeName,
      translator: l.localeTranslator,
    );
  }
  return result;
});
```

**改後**:
```dart
final localeMetadataProvider = Provider<Map<String, LocaleMetadata>>((ref) {
  final all = AppLocalizations.supportedLocales;
  final result = <String, LocaleMetadata>{};
  for (final locale in all) {
    if (_isBareBaseOfSpecificVariant(locale, all)) continue;
    // gen_l10n 對 const 內容回 SynchronousFuture，.then 在同個 stack
    // frame 內同步執行；無 await，無 microtask 跳轉，無 loading frame。
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

**連動修改 1 — `lib/pages/settings_page.dart` `_LocaleDropdown.build`**
- 移除 `asyncMeta.when(data: ..., loading: ..., error: ...)` 包裝
- 直接 `final metadata = ref.watch(localeMetadataProvider);` 然後組 dropdown

**連動修改 2 — `lib/pages/contributors_page.dart` `_LanguageList.build`**(spec 漏寫,review 補)
- 同樣移除 `asyncMeta.when(...)` 包裝,改成直接 `metadata`
- `loading` / `error` 分支可一併刪除

**連動修改 3 — `test/l10n/locale_metadata_test.dart`**(spec 漏寫,review 補)
- `await container.read(localeMetadataProvider.future)` 兩處(行 80、104)改為同步 `container.read(localeMetadataProvider)`
- 兩個 test callback 仍可保留 `async`(對其他 `await` 來說無害),也可改成同步,擇其一即可

**已確認**:全 repo grep `localeMetadataProvider` 共 3 個 caller(`settings_page` / `contributors_page` / `locale_metadata_test`),全部都在本 spec 內處理,無遺漏。

**Trade-off / 風險**:
- 若未來 `gen_l10n` 改變實作,`delegate.load` 不再回 SynchronousFuture,則 `result` map 會空 → dropdown 無項目。
- 緩解:provider 內留註解明確標示此假設;若真改可再退回 `FutureProvider`。

### C. 收斂訂閱粒度

**位置 1**:`lib/pages/settings_page.dart:34`
- 改 `final settings = ref.watch(settingsProvider);` 為 `select` 出 `themeMode` 與 `locale`。
- `notifier` 仍 `ref.read(settingsProvider.notifier)`(read 不訂閱)。

**位置 2**:`lib/pages/settings_page.dart:243-244`(`_DataManagement.build`)
- 改 `final state = ref.watch(wishRepositoryProvider);` 為 `select` 出 `byUid.isNotEmpty` 與 `activeUid` 兩個欄位。

**位置 3**:`lib/widgets/cards/account_management.dart:21-22`(`AccountManagement.build`)
- 拆成四個 `select`:`byUid` / `activeUid` / `uidAliases` / `uidOrder`。
- `_export` / `_import` 內的 `ref.read` **不動**。

## 驗收標準

1. **觀感**:冷啟後第一次進設定頁,語言下拉不再閃 spinner,整頁無明顯卡頓。
2. **正確性**:語言切換、主題切換、帳號管理(reorder / alias / active / remove)、匯入匯出 全部仍正常。
3. **視覺**:Banner 仍清晰、可點、hover opacity 動畫仍正常。
4. **品質檢查**(CLAUDE.md 提交前流程):
   - `dart format lib/ test/`
   - `flutter analyze` → `No issues found!`
   - `flutter test` → `All tests passed!`

## 備註

- 不需要新增測試檔。既有 `settingsProvider` / `wishRepositoryProvider` 結構未變,既有測試足夠 cover。
- 若 `localeMetadataProvider` 有對應的測試,需更新型別預期(由 `AsyncValue<Map>` 改為 `Map`)。
