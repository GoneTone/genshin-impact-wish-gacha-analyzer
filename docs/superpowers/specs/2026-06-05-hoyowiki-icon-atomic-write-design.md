# HoYoWiki 圖檔原子寫入 — 修正更新時的 icon 破圖

## 問題

「更新」抓取 HoYoWiki 物品圖片時，列表上**部分** icon 會出現紅色破圖錯誤，**切換頁面再回來才會恢復正常**。

## 根因

破圖發生在更新的圖片下載階段（`gacha_repository.dart` 的 `_fetchHoYoWiki`），是一個**並發寫檔 × 重繪競態**：

1. 下載階段有 8 個 worker 並行（`downloadConcurrency = 8`）。每個 worker 先
   `file.writeAsBytes(bytes, flush: true)` **直接寫到最終路徑**（非原子），寫完才呼叫
   `indexNotifier.bumpCacheRevision()`。
2. `bumpCacheRevision()` 一換 state identity，**所有** `ref.watch(hoyowikiIndexProvider)` 的
   `GachaItemIcon` 全部重繪。
3. `GachaItemIcon.build()` 只用 `file.existsSync()` 判斷就直接 `Image.file(file)`。worker A 的
   bump 觸發重繪那一刻，worker B 的檔案**可能正寫到一半**（檔已建立、bytes 不完整）。此時 icon B 的
   `existsSync()` 為 true，`Image.file` 去解碼一個截斷的 PNG → 解碼失敗 → Flutter 預設**紅色破圖**
   （`GachaItemIcon` 的 `Image.file` 目前**沒有 `errorBuilder`**）。

「**切換頁面才恢復**」是這個 bug 的指紋：`Image.file` 內部的 `FileImage` 以**檔案路徑**為 cache
key（不含內容）。一旦某張因半成品檔解碼失敗，後續 `bumpCacheRevision` 觸發的重繪，因為 `FileImage`
路徑相等而被視為「同一個 provider」、**不會重新解碼**，icon 就一直卡破圖；只有離開頁面讓該 element
unmount、回來重建全新 `Image` 時才會重讀（此時檔案已完整）→ 正常顯示。

對照組：`hoyowiki_index.json` 自己用 **tmp + rename 原子寫入**（`HoYoWikiIndexStorage.save`），唯獨
圖檔下載沒有。另外，詳情對話框（`gacha_item_detail_dialog.dart`）與 zoom overlay
（`zoomable_image_overlay.dart`）的 `Image.file` **本來就有 `errorBuilder`** fallback，這正好解釋了
破圖只出現在「列表」、不出現在詳情頁。

## 核心觀念

讓「磁碟上某路徑的圖檔」永遠只有兩種狀態——**不存在**，或**內容完整**。`existsSync()` 為 true 時必為
完整檔，破圖的根（讀到截斷檔）就消失了。

## 做法

採「原子寫入（根治成因）＋ 補 `errorBuilder`（消除症狀、對齊既有一致性）」，不動 `bumpCacheRevision`
頻率、不動 ImageCache eviction。

### 1. 新增共用原子寫入 helper

`lib/services/hoyowiki_index.dart`，緊鄰既有 `hoyowikiIconCacheFile` / `hoyowikiGalleryCacheFile`
（純 service 層，維持不引入 flutter；`Uint8List` 取自 `dart:typed_data`）：

```dart
/// 原子寫入 HoYoWiki cache 圖檔：先寫同目錄的 `<path>.tmp`（flush）再 rename 蓋到
/// 最終路徑。避免並發更新（多 worker 寫檔 + bumpCacheRevision 觸發全列表重繪）時，
/// 其他 widget 的 Image.file 讀到寫一半的截斷檔而出現破圖。對齊
/// HoYoWikiIndexStorage.save 既有的 tmp+rename 策略。
Future<void> writeHoYoWikiCacheImage({
  required File file,
  required Uint8List bytes,
}) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(file.path);
}
```

### 2. 兩個寫檔點改用 helper（消除重複輪子）

- `lib/state/gacha_repository.dart` ~973：icon 下載（破圖風暴本體）。原 `file.writeAsBytes(bytes,
  flush: true)` → `await writeHoYoWikiCacheImage(file: file, bytes: bytes)`。
- `lib/widgets/dialogs/gacha_item_detail_dialog.dart` ~110-111：gallery／詳情 lazy 下載。原
  `await file.parent.create(...)` + `await file.writeAsBytes(bytes)` → 同樣改呼叫 helper（helper 已
  內含 `parent.create`）。

### 3. `GachaItemIcon` 補 `errorBuilder` + log

`lib/widgets/gacha_item_icon.dart`：`Image.file` 加 `errorBuilder` → 回退到既有 `_Placeholder`
（與詳情頁、zoom overlay 一致，它們本來就有）。解碼失敗時 `Logger('gacha.hoyowiki.icon').warning(...)`
帶 id 與 error。這是防線＋一致性，不是主修；原子寫入後它只在「真正損壞的下載」這種罕見狀況觸發。

`errorBuilder` 回傳的 `_Placeholder` 與「無檔」分支回傳的是同一個 widget，外層 `_clipIcon` 的
ClipRRect(4) / ClipOval 套在自帶圓角／圓形的 placeholder 上視覺等價，無副作用。

### 4. 明確不做（YAGNI）

- 不 debounce／序列化 `bumpCacheRevision`：原子寫入後那個重繪風暴本來就無害（每次重繪只是重查
  `existsSync()`，看到的不是完整圖就是 placeholder）。
- 不動 ImageCache eviction：同 id+url 必為同檔同內容，路徑快取的 staleness 在視覺上不可見。
- 不改 share／preload 路徑：走 `RawImage`（預解碼 `ui.Image`），且 `preloadHoYoWikiImages` 已有
  try/catch 跳過解碼失敗；原子寫入後它也不會再讀到截斷檔。

## 錯誤處理 / 平台

`File.rename` 在 Windows 會 replace 既有檔（`hoyowiki_index.json` 長期以同一原語覆寫、已驗證可行）。
icon 只在 `!existsSync()` 時入列下載，rename 撞到「目的檔正被讀取」的機率極低；萬一 rename 失敗，兩個
呼叫端既有的 try/catch 會 log warning，該 icon 維持 placeholder 到下次更新，與下載失敗同級，可接受。
`<path>.tmp` 不會撞名：更新流程內 URL 已去重（`seenUrls`），每筆下載對應唯一最終路徑、唯一 tmp 路徑。

## 測試

- **helper 單元測試**（放既有涵蓋 `hoyowikiIconCacheFile` / `HoYoWikiIndexStorage` 的測試檔）：
  寫入後檔案內容與輸入 bytes 完全一致、寫入後無殘留 `.tmp`、對既有檔可正確覆寫。
- **`test/widgets/gacha_item_icon_test.dart` 新增一例**：當 cache 檔為**損壞／截斷** bytes 時，
  `GachaItemIcon` 渲染 `_Placeholder`（`find.byIcon(Icons.question_mark)` 命中），不丟 `FlutterError`、
  不出現紅色 `ErrorWidget`。既有 `tearDown` 已清 `imageCache` / `clearLiveImages`（避免 Linux CI
  codec cross-test race），沿用即可。

## 影響檔案

| 檔案 | 變更 |
|---|---|
| `lib/services/hoyowiki_index.dart` | 新增 `writeHoYoWikiCacheImage` top-level helper |
| `lib/state/gacha_repository.dart` | icon 下載改用 helper |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | gallery／詳情 lazy 下載改用 helper |
| `lib/widgets/gacha_item_icon.dart` | `Image.file` 加 `errorBuilder` → `_Placeholder` + log |
| `test/...`（helper 測試檔） | helper 原子性單元測試 |
| `test/widgets/gacha_item_icon_test.dart` | 損壞檔 → placeholder 回歸測試 |

## 驗收條件

- `flutter analyze` 輸出 `No issues found!`。
- `flutter test` 輸出 `All tests passed!`，含上述兩組新測試。
- 手動：觸發一次更新，列表 icon 隨下載陸續出現、過程中不再出現紅色破圖，且不需切換頁面即正常顯示。
