# 卡池資料抓取與儀表板設計

> **目的：** 把現有「攔到 1 條 getGachaLog URL 即停」的 PoC 擴充成完整的卡池歷史儀表板：點「更新資料」一次抓 5 個卡池所有紀錄、本地儲存、多帳號分軌、URL 快取、綜合與分卡池統計圖表。
>
> **範圍：** 不改 Rust 端的 MITM 攔截邏輯（介面不動）。HTTP 抓取 / 儲存 / State / UI / 路由 / 圖表全部在 Dart 端新增；新增五個 Dart 套件（`flutter_riverpod`、`http`、`path_provider`、`fl_chart`、`go_router`）。

## 1. 背景與目標

PoC（spec `2026-05-08-https-capture-poc-design.md` 起算的四個 iteration）已完成 MITM 攔截 + getGachaLog URL 取得；資料層 `gachaTypes` 5 筆 hardcode 也已在 `lib/data/gacha_types.dart`。本 iteration 把這條 pipeline 接上：

- 點「更新資料」→ 取得 URL → 對 5 個 gacha_type 各自分頁抓取 → merge 既有資料 → 持久化
- UI 端：NavigationRail 切換綜合 / 5 個 banner 頁；每頁顯示 2 張圓餅圖 + 5 個中獎率；banner 頁多一個分頁紀錄列表
- URL 與資料皆按 UID 分軌，多帳號自然支援；UID indicator 與「重新攔截」action 預留切帳號入口

## 2. 關鍵決策（已對齊）

| 項目 | 決定 | 理由 |
|---|---|---|
| HTTP 抓取層 | Dart 端（`package:http`） | 改動最小；UI 進度回饋自然；Rust 專注 MITM |
| 儲存格式 | JSON 檔，per-UID 一個 | <10k 紀錄；切帳號直接換檔；YAGNI（不上 SQLite） |
| 圓餅圖數量 | **兩張**：稀有度 / 物品類型各一 | `5★/4★/3★` 與 `角色/武器` 為兩個維度，不能塞同一張 |
| Per-UID 分軌 | 自動分軌（每 UID 一個檔） | 多帳號使用者資料不互相汙染 |
| URL 快取 | per-UID（`<uid>.url.json`） | 認證 token 跟帳號綁；多帳號獨立生命週期 |
| 認證失敗自動 fallback | 1 次重攔上限 | 失效 → 自動 MITM → 第二次仍失敗即 `UpdateFailed` |
| 切帳號 UI | AppBar UID indicator + popup menu | 「重新攔截」action 強制 MITM；已知 UID 列表可純 view 切換 |
| 路由 | `go_router` 的 `ShellRoute` | NavigationRail 持久化、子頁切換不重建 shell |
| State 管理 | `flutter_riverpod` 的 `Notifier` + 不可變 `WishState` | 比 ChangeNotifier 更 testable；`select` 做 granular rebuild；avoid 自寫 InheritedNotifier wrapper（CLAUDE.md「不要造輪子」） |
| 圖表 | `fl_chart` | 社群最廣、pie 完整 |

## 3. 整體架構

```
┌─────────────────────────────────────────────────────────┐
│  Flutter (Dart)                                         │
│                                                         │
│  routing/app_router.dart        ShellRoute + 6 子路由    │
│                                                         │
│  pages/                                                 │
│    app_shell.dart               NavigationRail + AppBar │
│    overview_page.dart           綜合（首頁，'/')         │
│    banner_page.dart             5 個 banner（'/banner/:type')│
│                                                         │
│  widgets/                                               │
│    stats_panel.dart             5 個中獎率文字面板       │
│    rarity_pie.dart  item_type_pie.dart                  │
│    record_list_table.dart       分頁紀錄列表             │
│    uid_indicator.dart           AppBar UID popup        │
│    update_progress_dialog.dart                          │
│    empty_state.dart                                     │
│                                                         │
│  state/                                                 │
│    wish_repository.dart         Riverpod Notifier + 不可變 WishState │
│                                                         │
│  services/                                              │
│    gacha_url.dart               URL 解析 / 重組          │
│    wish_fetcher.dart            HTTP + 分頁 + merge     │
│    wish_storage.dart            JSON 讀寫（atomic）      │
│    wish_stats.dart              統計計算（pure）         │
│                                                         │
│  models/wish_record.dart                                │
│  data/gacha_types.dart          既有，不動               │
│  src/rust/                      FRB 產出，不動           │
└─────────────────────────────────────────────────────────┘
                            ↕ FRB（介面不變）
┌─────────────────────────────────────────────────────────┐
│  Rust core (cdylib)                                     │
│  capture / mitm / sys_proxy / ca / cert_store           │
│  ↑ 完全沿用                                              │
└─────────────────────────────────────────────────────────┘
                            ↓
            <applicationSupportDirectory>/wish_data/
              <uid>.json
              <uid>.url.json
```

## 4. 資料模型

### 4.1 `WishRecord`

```dart
enum WishItemKind { character, weapon, unknown }

class WishRecord {
  final String id;          // primary key（dedup 用，等長 19 字元字串）
  final String uid;
  final String gachaType;   // '100' / '200' / '301' / '302' / '500'
  final String name;        // 物品名稱（原語系）
  final String itemType;    // 原 API 字串（"角色"/"武器"/"Character"...）
  final WishItemKind kind;  // 解析時推導，pie chart 分類用
  final int rankType;       // 3 / 4 / 5
  final DateTime time;      // 解析自 "yyyy-MM-dd HH:mm:ss"（伺服器時區）
  final String lang;        // 抓取當下語系（例：'zh-tw'）
}
```

| 欄位決策 | 理由 |
|---|---|
| `id` 用 `String` | API 19 位字串；統一用 String 避免 web 端 53-bit int round-trip |
| 略過 `count` / `item_id` | `count` 永遠 1；`item_id` 大多空字串；YAGNI |
| 多一個 `WishItemKind` 推導欄位 | API `item_type` 隨語系變（zh-tw="角色"/en="Character"），pie chart 分類需要穩定 enum |
| `kind` derived，**不**寫進 JSON | 由 `lang + itemType` 推導；單一資料源 |
| `time` 存 raw string，記憶體用 `DateTime` | API 字串無時區；存原字串避免轉換誤差 |
| 保留 `lang` 欄位 | debug；混語系資料可辨識來源 |

`WishItemKind` 推導：

```dart
const _characterStrings = {'角色', 'Character', 'キャラクター', '캐릭터'};
const _weaponStrings = {'武器', 'Weapon', '무기'};
// itemType in _characterStrings → character
// itemType in _weaponStrings → weapon
// otherwise → unknown
```

### 4.2 Per-UID 資料檔 `<uid>.json`

路徑：`<applicationSupportDirectory>/wish_data/<uid>.json`

```json
{
  "uid": "801057625",
  "last_updated": "2026-05-08T14:30:00.000Z",
  "banners": {
    "301": [ /* WishRecord[]，desc by id */ ],
    "302": [ ... ],
    "500": [ ... ],
    "200": [ ... ],
    "100": [ ... ]
  }
}
```

| 結構決策 | 理由 |
|---|---|
| 一 UID 一檔 | 帳號隔離 = 檔案隔離；多帳號零互擾 |
| `banners` 用 map by gacha_type | 每 banner 獨立 max id 比對；merge 邏輯只看自己 list |
| `last_updated` ISO 8601 UTC | UI 顯示時轉本機；ISO 字串方便 debug |
| 每筆紀錄保留 `uid` | export / 移檔不丟失；空間成本可忽略 |
| 每 banner list 排序 desc by `id` | 對齊遊戲 UI；列表頁直接 slice 即分頁 |
| 寫檔用 atomic rename | 寫 `.json.tmp` → rename；中途 crash 不破壞舊檔 |

### 4.3 Per-UID URL 檔 `<uid>.url.json`

路徑：`<applicationSupportDirectory>/wish_data/<uid>.url.json`

```json
{
  "uid": "801057625",
  "url": "https://.../getGachaLog?...&authkey=...&...",
  "captured_at": "2026-05-08T14:30:00.000Z"
}
```

| 決策 | 理由 |
|---|---|
| URL 與資料分檔 | URL 寫入時機（MITM hit 即寫）vs 資料寫入時機（fetch 完成）不同步；分檔避免無謂大物件序列化 |
| 檔內冗餘記 `uid` | 一致性；export/移檔場景容錯 |
| `captured_at` 可選但保留 | debug 用；顯示「URL 已快取 X 小時」未來可考慮 |

### 4.4 Merge / Dedup 演算法（單一 banner）

```
existingMaxId = existing.banners[bannerType]?.first?.id ?? '0'
fresh = []
endId = '0'
isFirstPage = true

loop:
    if isFirstPage and primerPages contains bannerType:
        page = primerPages[bannerType]              // UID 探測階段預先抓的
    else:
        await Future.delayed(rateLimit)
        page = await httpFetch(gachaUrl.build(bannerType, endId: endId))

    isFirstPage = false
    if page.list isEmpty: break

    for record in page.list:                         // page.list 已是 desc
        if record.id > existingMaxId:
            fresh.add(record)
        else:
            return fresh                              // 碰到舊資料 → 整 banner 收工

    if page.list.length < SIZE_20: break              // 末頁，整 banner 抓完
    endId = page.list.last.id

merged = [...fresh, ...existing.banners[bannerType] ?? []]
```

| 演算法決策 | 理由 |
|---|---|
| Dedup key = `id` | API 保證唯一、單調遞增 |
| 字串字典序比對（無需 BigInt） | id 等長 19 字元 → 字典序 = 數值序 |
| 嚴格 `id > maxId` | maxId 那筆已存在；無需重存 |
| 不依賴 `data.total` | hoyoverse 該欄位常回 "0"，不可信 |
| All-or-nothing per banner（失敗整 banner 棄置） | 避免「中段缺洞」：page 1-3 抓到、page 4 失敗、下次 maxId 已過頭，page 4+ 永遠抓不到 |

### 4.5 Active UID 概念與 State 結構

```dart
/// 一個 UID 的記憶體版資料（對應 §4.2 的 <uid>.json）
class BannerStorage {
  final String uid;
  final DateTime lastUpdated;
  final Map<String, List<WishRecord>> banners;  // gachaType → records desc by id
}

/// 整個 app 的 in-memory 狀態，不可變（copyWith 產生新 instance）
@immutable
class WishState {
  final String? activeUid;
  final Map<String, BannerStorage> byUid;
  final UpdateProgress? progress;   // null = idle / 已完成且使用者已關 dialog

  const WishState({
    this.activeUid,
    this.byUid = const {},
    this.progress,
  });

  BannerStorage? get activeData =>
      activeUid == null ? null : byUid[activeUid];
  Iterable<String> get knownUids => byUid.keys;

  WishState copyWith({...});
}

final wishRepositoryProvider =
    NotifierProvider<WishRepository, WishState>(WishRepository.new);

class WishRepository extends Notifier<WishState> {
  @override
  WishState build() {
    _bootstrapLoad();           // fire-and-forget：掃 wish_data/ 全載入
    return const WishState();
  }

  Future<void> update();
  Future<void> setActiveUid(String uid);
  Future<void> forceRecaptureAndUpdate();
  void clearProgress();         // 使用者關 dialog 後呼叫，progress → null
  Future<void> _bootstrapLoad();
}
```

| 決策 | 理由 |
|---|---|
| 用 Riverpod `Notifier` 而非 `AsyncNotifier` | initial state 可同步建立（空 `WishState`）；async load 用 fire-and-forget |
| 狀態一個整包 `WishState`（非分散多 provider） | 一個 Repository 規模，整包簡單；UI 用 `ref.watch(provider.select(...))` 做 granular rebuild |
| 啟動時掃 `wish_data/*.json` 全部載入 | 紀錄量小；in-memory 切換零延遲；省掉懶載入複雜度 |
| 預設 `activeUid` = `last_updated` 最大者 | 啟動體驗「最近一次同步的帳號」；無「上次選哪個」持久化（YAGNI） |
| 抓取結束 `activeUid` 自動 = fetch 回傳的 UID | 「更新資料」即同步即看到，包括切換帳號的場景 |
| `setActiveUid` 不重抓網路 | 已抓過的 UID 之間切換完全離線 |
| `clearProgress` 由 dialog 關閉時呼叫 | progress 從 Completed/Failed → null；下一次 update() 才會觸發 dialog 重新 show |

## 5. 抓取流程

### 5.1 端到端時序

```
[使用者點 AppBar「更新資料」]
   ↓
WishRepository.update()
   ↓
1. activeUid?
   ├─[無 activeUid（首次啟動）]
   │     → 走 MITM 流程（URL 暫存記憶體；step 3）
   └─[有 activeUid]
         WishStorage.loadCapturedUrl(activeUid) → cachedUrl?
         ├─[有]  → 跳到 step 4 用 cachedUrl
         └─[無]  → 走 MITM 流程
   ↓
2. emit waitingForCapture
   ↓
3. rust_capture.startCapture() → first hit
     URL **暫不落盤**（UID 未知；先記憶體）
   ↓
4. fetchAll(url) → UID 探測 → 5 個 banner 分頁 + merge
   ↓
   ├─[retcode = 0 全程]
   │     5a. WishStorage.saveCapturedUrl(uidFromFetch, url)
   │     5b. WishStorage.save(uidFromFetch, mergedData)
   │     5c. _activeUid = uidFromFetch
   │     5d. emit UpdateCompleted
   │
   └─[retcode = -101 / -100，authkey 失效]
         6a. cached URL 對應的 UID 那支 .url.json 刪掉
         6b. 進 MITM 流程拿新 URL（記憶體）
         6c. fetchAll(newUrl)；retcode=0 後同 5a~5d
         6d. 第二次仍 -101/-100 → emit UpdateFailed
```

### 5.2 URL 解析（`gacha_url.dart`）

```dart
class GachaUrl {
  GachaUrl._(this._uri);
  final Uri _uri;

  static GachaUrl parse(String capturedUrl) =>
      GachaUrl._(Uri.parse(capturedUrl));

  Uri build({
    required String gachaType,
    required String endId,
    int size = 20,
    int page = 1,
  }) {
    final params = Map<String, String>.from(_uri.queryParameters)
      ..['gacha_type'] = gachaType
      ..['page'] = page.toString()
      ..['size'] = size.toString()
      ..['end_id'] = endId;
    return _uri.replace(queryParameters: params);
  }
}
```

| 決策 | 理由 |
|---|---|
| 用 `Uri.replace` 整批覆蓋 query | 避免手字串拼接 escaping 問題 |
| `size = 20` 寫死 | API 上限 |
| `page = 1` 寫死 | hoyoverse 不靠 page 翻頁，靠 `end_id` cursor；保留 page=1 與遊戲行為一致 |
| 不 strip 其他 query | hoyoverse 對未知 query 容忍；YAGNI |

### 5.3 UID 探測

```
for bannerType in gachaTypes order [301, 302, 500, 200, 100]:
    page = fetch(gachaUrl.build(bannerType, endId: '0'))
    if page.list.isNotEmpty:
        uid = page.list[0].uid
        primerPages[bannerType] = page    // 留給 §4.4 不重抓
        break

if uid == null:
    throw NoDataError("此帳號尚無任何卡池紀錄")
```

| 決策 | 理由 |
|---|---|
| 順序與 `gachaTypes` 一致 | 角色活動祈願（301）放第一；多數使用者最常打 → 探測命中率高 |
| primer page 重用 | 避免 step 4 重抓造成多 1 次請求 + rate limit 浪費 |

### 5.4 認證失敗判定

| retcode | 視為 | 行為 |
|---|---|---|
| `0` | 成功 | 正常處理 list |
| `-101` | authkey timeout | 觸發 §5.5 fallback |
| `-100` | authkey error | 同上 |
| `-110` | visit too frequently | rate limit 退避（§5.7），**不**走 fallback |
| 其他 `!= 0` | 未知失敗 | 立刻 `UpdateFailed`，cached URL 保留（不確定是否認證問題） |

### 5.5 Fallback 細節

| 議題 | 決定 |
|---|---|
| 自動 fallback 重試上限 | 1 次；第二次仍失敗即放棄 |
| 觸發點 | 任一 banner 任一頁回 -101/-100 即觸發；後續所有未抓 banner 共用新 URL |
| Fallback 觸發時刪哪一個 URL 檔 | 兩種情況：<br>(a) 用 cached URL 觸發 -101 → 刪 `<activeUid>.url.json`<br>(b) MITM 剛攔到的 URL 在第一次 fetch 就 -101（極少見） → 無 .url.json 檔可刪（URL 還在記憶體未落盤），直接 fallback |
| Fallback 中累積的 `fresh` 處理 | 整批棄置（all-or-nothing 原則）；新 URL 重抓 |
| Fallback 後 fetch 回傳新 UID（中途換帳號） | 視為正常：URL 與資料寫到新 UID 的檔；`_activeUid` 切換 |

### 5.6 進度事件 model

```dart
sealed class UpdateProgress { const UpdateProgress(); }

class WaitingForCapture extends UpdateProgress {
  final bool isFallback;   // true 時 dialog 顯示「先前認證已失效」副標題
}

class FetchingBanner extends UpdateProgress {
  final String gachaType;     // '301'
  final String displayName;   // '角色活動祈願'
  final int pageIndex;        // 1-based
  final int newRecordsSoFar;  // 該 banner 累計已新增
}

class UpdateCompleted extends UpdateProgress {
  final int totalNewRecords;
  final List<String> failedBanners;  // 部分失敗時記在這
  final DateTime updatedAt;
}

class UpdateFailed extends UpdateProgress {
  final String message;
}
```

`progress` 是 `WishState` 的欄位；AppShell 用 `ref.listen(wishRepositoryProvider.select((s) => s.progress), ...)` 觀察 null → 非 null 時呼叫 `showDialog`；dialog 內以 `ConsumerWidget` + `ref.watch(wishRepositoryProvider.select((s) => s.progress))` 即時更新顯示內容。

### 5.7 Rate limit / 重試

| 規則 | 設定 | 理由 |
|---|---|---|
| 每次 HTTP 請求間隔 | `Future.delayed(600ms)` | hoyoverse 經驗值 |
| `retcode = -110` | 等 5s 重試該頁，最多 3 次 | 退避；超過視為失敗 |
| HTTP timeout | 10s | 防止網路斷線無限等待 |
| Network error | 失敗，不自動重試 | 避免 silently long delay |
| 5 個 banner 串行（非並行） | rate limit 友善；UI 進度回饋自然 | 並行可能觸發 -110 |

### 5.8 錯誤處理策略

| 場景 | 行為 |
|---|---|
| MITM rust 層 throw | `UpdateFailed`；既存資料不動 |
| UID 探測 5 支 banner 都空 | `UpdateFailed("此帳號尚無任何卡池紀錄")` |
| 某 banner 抓到一半失敗 | 該 banner 累計的 `fresh` **棄置**；繼續抓下一 banner；最後 `failedBanners` 列出 |
| 全 5 個 banner 都成功（含 0 筆新增） | `UpdateCompleted`；`last_updated` 更新並寫檔 |
| 部分 banner 失敗 | `UpdateCompleted` 但 `failedBanners` 非空；成功的 banner 仍寫檔 |

### 5.9 取消支援

| 階段 | 是否可取消 |
|---|---|
| `waitingForCapture`（含 fallback） | ✅ Dialog 顯示「取消」按鈕；按下呼叫 `rust_capture.stopCapture()`，progress → idle |
| `fetchingBanner` | ❌ 過程僅數十秒；YAGNI |
| 完成 / 失敗 | dialog 顯示「關閉」按鈕 |

### 5.10 Force Re-capture（手動切換帳號）

```
WishRepository.forceRecaptureAndUpdate()
  ↓
1. activeUid != null → WishStorage.deleteCapturedUrl(activeUid)
   activeUid == null → 不刪
   ↓
2. update()    // bootstrap 時必走 MITM（cached 已被刪）
```

行為與自動 fallback 共用 MITM 路徑，差別只在 entry point。

## 6. UI 結構

### 6.1 路由（`routing/app_router.dart`）

```dart
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const OverviewPage()),
        GoRoute(
          path: '/banner/:type',
          builder: (_, state) => BannerPage(
            gachaType: state.pathParameters['type']!,
          ),
        ),
      ],
    ),
  ],
);
```

| 決策 | 理由 |
|---|---|
| `ShellRoute` 包外殼 | NavigationRail 持久化、子頁切換不重建 shell |
| `:type` path param 而非 5 條獨立路由 | 5 個 banner 同一 widget，type 決定渲染 |
| 不引入 `go_router_builder` | 路由表 6 條，codegen 過度 |

### 6.2 AppShell（`pages/app_shell.dart`）

```
┌──────────────────────────────────────────────────────────┐
│ AppBar: 卡池分析  [UID: 801057625 ▾]      [更新資料]      │
├──────┬───────────────────────────────────────────────────┤
│ ▣ 綜合│                                                    │
│ ▣ 角色│                                                    │
│ ▣ 武器│              child（OverviewPage / BannerPage）    │
│ ▣ 集錄│                                                    │
│ ▣ 常駐│                                                    │
│ ▣ 新手│                                                    │
│      │   底部 status bar：最後更新 2026-05-08 14:30        │
└──────┴───────────────────────────────────────────────────┘
```

| 元件 | 細節 |
|---|---|
| `NavigationRail` | 6 個 destination（綜合 + 5 banner，順序對齊 `gachaTypes`，綜合放最前）；`selectedIndex` 由 `GoRouterState.uri.path` 決定 |
| AppBar trailing：UID indicator | `PopupMenuButton<String>`：trigger 顯示 `UID: 801057625` + 下拉箭頭；點開 menu 列已知 UID + 「重新攔截 / 切換帳號」 |
| AppBar trailing：「更新資料」 | `FilledButton.icon(icon: Icons.refresh)`；點下 → `repository.update()` |
| 底部 status bar | 顯示 `repository.activeData?.lastUpdated`，無資料時「尚未同步」 |
| repository 注入 | `main.dart` 在 `MaterialApp` 上層包 `ProviderScope`；任一 widget 用 `ref.watch(wishRepositoryProvider.select(...))` 取狀態，`ref.read(wishRepositoryProvider.notifier).update()` / `setActiveUid(...)` 呼叫 method |

UID popup menu：

```
┌──────────────────────────┐
│  ✓ 801057625（活躍）     │
│    912345678            │
│    ─────────────        │
│    🔄 重新攔截 / 切換帳號 │
└──────────────────────────┘
```

### 6.3 OverviewPage（`pages/overview_page.dart`）

```
┌─────────────────────────────────────────────┐
│ 綜合數據（全卡池合計）                        │
│                                             │
│  ┌─────────────────┐  ┌─────────────────┐  │
│  │  稀有度分布      │  │  物品類型分布    │  │
│  │   (pie chart)   │  │   (pie chart)   │  │
│  │  5★ 4★ 3★      │  │  角色 / 武器     │  │
│  └─────────────────┘  └─────────────────┘  │
│                                             │
│  總抽數 / 5 個中獎率（StatsPanel）            │
│                                             │
│  （此頁無紀錄列表）                          │
└─────────────────────────────────────────────┘
```

### 6.4 BannerPage（`pages/banner_page.dart`）

```
┌─────────────────────────────────────────────┐
│ 角色活動祈願（gacha_type=301）                │
│                                             │
│  pie × 2 + StatsPanel（與 OverviewPage 同）  │
│                                             │
│  ─── 紀錄列表 ─────────────────────────      │
│  時間              名稱      類型    稀有度   │
│  2025-09-23 21:27 雷電將軍   角色   5★      │
│  ...                                        │
│  ─────────────────────────────────────       │
│  上一頁 [1] 2 3 4 5 ... 38  下一頁          │
└─────────────────────────────────────────────┘
```

| 決策 | 理由 |
|---|---|
| 與 OverviewPage 共用上半部 | 共用 widget `StatsPanel` / `RarityPie` / `ItemTypePie` |
| 紀錄列表自寫 widget | 不上 `PaginatedDataTable`；slice + 簡易 page controls 更可控 |
| 每頁 20 筆 | 對齊 API 分頁慣例 |
| 排序預設 `id` desc | 對齊遊戲 UI；§4.2 已存即 desc，不再排序 |
| 不做欄位排序、過濾 | YAGNI |

### 6.5 Widgets 拆分

```
widgets/
  stats_panel.dart            ← 5 個中獎率文字面板（pure）
  rarity_pie.dart             ← 稀有度圓餅；input: List<WishRecord>
  item_type_pie.dart          ← 類型圓餅；input: List<WishRecord>
  record_list_table.dart      ← 紀錄列表 + 分頁控制
  uid_indicator.dart          ← AppBar UID popup
  update_progress_dialog.dart ← 抓取進度
  empty_state.dart            ← 「尚未同步」/「此卡池無紀錄」共用
```

| 決策 | 理由 |
|---|---|
| Pie 拆兩個 widget | 配色、label 規則不同；分開比 mode switch 清楚 |
| `stats_panel` 入口接 `List<WishRecord>` | 計算邏輯封在 `services/wish_stats.dart`；widget 只負責 layout |
| 抽 `empty_state` | OverviewPage / BannerPage / 無 active UID 三處共用 |

### 6.6 Update Progress Dialog

AppShell 內 `ref.listen(wishRepositoryProvider.select((s) => s.progress), (prev, next) { ... })`：
- `prev == null && next != null` → `showDialog(barrierDismissible: false)` 開 dialog
- Dialog 內部以 `ConsumerWidget` + `ref.watch` 訂閱 progress 即時更新內容
- 使用者點「關閉」/「取消」按鈕 → 呼叫 `ref.read(provider.notifier).clearProgress()`，`progress → null`，dialog 自動 pop（內部 `ref.listen` 觀察 null 時 `Navigator.pop`）

| 狀態 | 內容 |
|---|---|
| `WaitingForCapture(isFallback: false)` | 「等待卡池歷史頁開啟…」<br>「請開啟原神 → 卡池 → 歷史紀錄」<br>indeterminate progress<br>[取消] |
| `WaitingForCapture(isFallback: true)` | 同上 + 副標題：「先前的認證已失效，需重新攔截」 |
| `FetchingBanner(name, page, count)` | 「正在抓取：角色活動祈願」<br>「第 3 頁，已新增 37 筆」<br>indeterminate（無取消） |
| `UpdateCompleted(total, failed, at)` | 「✅ 更新完成」<br>「新增 N 筆紀錄」<br>若 `failed.isNotEmpty`：「⚠ 部分失敗：${failed.join('、')}」<br>[關閉] |
| `UpdateFailed(msg)` | 「❌ 失敗：$msg」<br>[關閉] |

### 6.7 Empty state

| 場景 | 顯示 |
|---|---|
| 啟動時無任何 UID 資料 | OverviewPage `EmptyState`（圖示 + 「點右上『更新資料』開始」提示） |
| 有 active UID 但某 banner 無紀錄 | BannerPage stats 全 0；pie 「無資料」placeholder；列表 empty |

### 6.8 Theme / 色票

| 元素 | 色 |
|---|---|
| 5★ | `Color(0xFFB8860B)` 金 |
| 4★ | `Color(0xFF8E44AD)` 紫 |
| 3★ | `Color(0xFF3498DB)` 藍 |
| 角色 / 武器 | 暫定深綠 / 深紅 |
| 整體 theme | `ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo))` Material 3 |

色票一致用於 pie / stats panel / record list。

## 7. 套件依賴

### 7.1 新增（pubspec.yaml）

```yaml
dependencies:
  flutter_riverpod: ^3.x
  http: ^1.x
  path_provider: ^2.x
  fl_chart: ^1.x
  go_router: ^17.x
```

| 套件 | 用途 |
|---|---|
| `flutter_riverpod` | State 管理；`Notifier` + `WishState` |
| `http` | HTTP client（getGachaLog 抓取） |
| `path_provider` | `getApplicationSupportDirectory()` 取 `wish_data/` 路徑 |
| `fl_chart` | 兩張圓餅圖 |
| `go_router` | Routing + ShellRoute |

### 7.2 既有不動

`flutter_rust_bridge`、`ffi` 與 Rust 端依賴均不變。

## 8. 手動驗收

按以下順序執行，全部通過代表本 iteration 完成：

### 8.1 首次啟動（無資料）

1. 全新環境（`wish_data/` 不存在）→ `flutter run -d windows --release`
2. 預設停在 `/`（OverviewPage），顯示 `EmptyState`：「尚未同步任何資料，點右上『更新資料』」
3. AppBar UID indicator 顯示「未同步」，popup menu 只有「重新攔截」一項
4. 底部 status bar：「尚未同步」

### 8.2 首次抓取

1. 點「更新資料」→ 走 MITM → dialog 顯示 `WaitingForCapture`
2. 開原神 → 卡池 → 歷史紀錄 → dialog 切到 `FetchingBanner`，逐 banner 顯示進度
3. 抓完 → `UpdateCompleted`，「新增 N 筆」、「最後更新：…」
4. 點關閉 → OverviewPage 顯示 2 張 pie + stats panel
5. 檢查 `<applicationSupportDirectory>/wish_data/`：
   - `<uid>.json` 存在，5 個 banner key 都有 list
   - `<uid>.url.json` 存在
6. NavigationRail 切到 5 個 banner 各自看：pie + stats + 分頁列表都正確
7. 列表分頁：第 1 頁顯示最新 20 筆；最後一頁顯示剩餘；翻頁正常

### 8.3 二次抓取（cached URL 直通）

1. 不關 app，原神也不打開，再點「更新資料」
2. dialog **不**顯示 `WaitingForCapture`，直接 `FetchingBanner`（cached URL 命中）
3. 各 banner 顯示「已新增 0 筆」（無新抽）
4. 完成 → `last_updated` 時間更新

### 8.4 重啟後

1. 關 app → 再開
2. OverviewPage 直接顯示既有資料（從 `<uid>.json` 載入）
3. 底部 status bar 顯示上次的 `last_updated`
4. 點「更新資料」走 §8.3 cached 路徑

### 8.5 認證失敗 fallback

1. 手動編輯 `<uid>.url.json` 把 authkey 改成無效值（模擬 24h 後過期）
2. 點「更新資料」→ 第一次 fetch 收到 `-101`
3. dialog 自動切到 `WaitingForCapture(isFallback: true)`，副標題「先前的認證已失效…」
4. 開原神歷史頁 → 重攔成功 → fetch 完成 → `UpdateCompleted`

### 8.6 多帳號（Force Re-capture）

1. 已有 `<uidA>.json` + `<uidA>.url.json`
2. 切換遊戲到帳號 B（in-game switch）
3. AppBar UID popup → 「重新攔截 / 切換帳號」
4. dialog `WaitingForCapture` → 開帳號 B 歷史頁 → 重攔
5. 抓取完成 → `<uidB>.json` + `<uidB>.url.json` 新增；`_activeUid` 自動切到 B
6. AppBar UID indicator 顯示「UID: <uidB>」；popup menu 列 A 與 B 兩筆
7. 點 A → 切回 A 的 view（純離線切換，無網路）
8. 在 A view 點「更新資料」→ 用 `<uidA>.url.json` 抓取 A

### 8.7 取消

1. 啟動 MITM 流程後（任一場景）→ 點 dialog 「取消」按鈕
2. progress → idle，dialog 關閉，無資料寫入

### 8.8 部分失敗

1. （難手動製造，可暫拔網路在 banner 3 中觸發）
2. 預期：`UpdateCompleted` 但 `failedBanners` 列出該 banner，dialog 顯示「⚠ 部分失敗」
3. 已成功的 banner 仍寫入檔

## 9. Out of Scope

| 項目 | 為什麼不做 |
|---|---|
| i18n（gacha 名稱、UI 文字） | 留 i18n 專屬 iteration；本次 hardcode 中文 |
| Android 端 | PoC 早期已決議 Windows only |
| 抓取中期取消 | 過程數十秒，YAGNI |
| 自訂分頁大小、欄位排序、過濾 | YAGNI；第一版固定 20 筆 / 時間 desc |
| UID switcher 持久化最後選擇 | 啟動預設「最近同步」即可 |
| 整 banner failure 自動重試 | 使用者再點「更新資料」即重試；YAGNI |
| 完整帳號管理頁（重命名、刪除 UID） | 預留 popup menu 入口，管理操作後續 iteration 加 |
| 資料匯出 / 匯入（uigf） | 後續 iteration |
| 圖表動畫、tooltip 客製 | fl_chart 預設足夠；YAGNI |
| Pie 「未知」切片的處理（`WishItemKind.unknown`） | 顯示為灰色一片即可；不寫專屬 UX |

## 10. 已知風險

| 風險 | 嚴重度 | 處理 |
|---|---|---|
| hoyoverse API 改 retcode 語意 | 中 | §5.4 表只列已知；其他統一視為「未知失敗」surface 訊息給使用者 |
| hoyoverse 改路徑或 query 規則 | 中 | URL 解析用 `Uri.replace`，覆蓋已知 query；新增 query 不影響 |
| `WishItemKind.unknown` 出現（新語系） | 低 | Pie 顯示灰片；使用者可回報補 mapping |
| 多帳號使用者誤點「更新資料」抓到舊帳號（cached URL 仍對 A 有效） | 低 | 提供「重新攔截」明確 action；UI 副標題也提示「切換帳號」用此入口 |
| 紀錄筆數 > 1 萬 → 啟動全載入慢 | 低 | 真實使用者多在數百~數千；超過再考慮 lazy load 或 SQLite |
| atomic rename 在 Windows 下對開啟中的檔失敗 | 低 | `wish_data/` 內檔僅本 app 寫；其他程序無理由開啟 |
| MITM 無限等待（使用者忘了開遊戲） | 低 | dialog 「取消」按鈕兜底 |
| 部分 banner 失敗後使用者重試會否再失敗 | 低 | 重試走同一條 cached URL 路徑；網路問題暫時即可恢復 |
