# HoYoWiki 圖片抓取流程平行化

- 狀態：草案
- 撰寫日期：2026-05-24
- 受影響範圍：HoYoWiki 補圖流程（search / entry_page / download）

## 動機

現行 `lib/state/gacha_repository.dart::_fetchHoYoWiki()` 三個階段（search → entry_page → download）以 `for` 迴圈完全串行執行，每筆完成後 `Future.delayed(600ms)`（`HoYoWikiFetcher.rateLimit`）。對於跨 UID 聚合後常見的 50～200 筆物品而言，整段補圖會花到分鐘級。

實際上 HoYoWiki 三個端點分屬不同 host，未必有那麼緊的 per-IP 限流。在動手寫平行化之前先用一支臨時探針驗證安全並行度，再以最小變動把三個串行迴圈換成 worker-pool，是最低風險路徑。

## 範圍

兩個 milestone：

- **A — 探針腳本**：一次性 Dart 腳本，量化各 host 在不同並行度下的成功率與延遲；跑完判斷各階段安全並行度後刪除。
- **B — Production 改寫**：依 A 的結論為 `HoYoWikiFetcher` 三個階段各 hardcode 一個保守並行度，把 `_fetchHoYoWiki` 三個串行迴圈換成 worker-pool。

明確 **不在範圍**：
- 三階段 pipeline 重疊（search 還沒跑完就丟給 entry）
- 動態 concurrency / token bucket / 指數退避
- 使用者可調整的並行度旋鈕（settings UI）
- 重抓失敗 item 的 retry 機制（沿用「失敗就 log warning、下次更新重試」現狀）

## Milestone A — 探針腳本

### 路徑與版控

- `tool/probe_hoyowiki_concurrency.dart`
- 驗證完並決定 production 並行度後**直接刪除**，不留在版控
- `.gitignore` 加 `/tool/probe_*.dart`，避免後續類似探針誤 commit

### 執行

- `dart run tool/probe_hoyowiki_concurrency.dart`
- 純命令列、無視窗、不需任何 flag

### 樣本來源

腳本內 hardcode 一份公開角色 / 武器名單作為 search keyword（≈ 30 筆，中文 + 英文混合，覆蓋 5 / 4 星與多語系），不依賴本機 `hoyowiki_index.json`，任何人 clone repo 都能跑：

- search 階段：直接用 hardcode 名單 + `lang ∈ {zh-tw, en-us}`
- entry 階段：使用 search 階段第一輪（concurrency = 1）成功命中拿到的 `id` 集合
- download 階段：使用 entry 階段拿到的 `iconUrl` + `headerImgUrl`（過濾空字串）

各階段固定樣本（不每輪重抽），讓不同並行度結果可比。

若 search 階段第一輪成功命中數 < 5（hardcode 名單失效或 search API 整段掛），
腳本直接 abort 並印 `search baseline insufficient: hit X/30, abort`，避免後續階段
拿到不可信的小樣本得出錯誤結論。

### 並行度與請求量

每階段掃 5 個並行度 `[1, 2, 4, 8, 16]`：

| 階段 | host | 每階段 ≈ 請求數 |
|------|------|-----------------|
| search | `sg-act-public-api.hoyolab.com` | 30 |
| entry_page | `sg-act-public-api-static.hoyolab.com` | 30 |
| download | 圖片 CDN（多個域名） | 60（每 entry 兩張） |

複用 `HoYoWikiFetcher` 的三個方法，與 production 同一段程式碼，避免量出來的數字跟實際行為不一致。

### 「被擋」訊號

任一條件即記錄為 blocked：

- HTTP status 非 2xx（特別關注 429 / 403 / 418 / 5xx）
- HoYoWiki `retcode != 0`
- HTTP timeout 或 connection exception

被擋**不中斷**，繼續跑下一個並行度，讓報告完整。

### 輸出

跑完在 stdout 印 Markdown 報告（不寫檔，使用者複製貼出即可），每階段一張表：

```
## search (sg-act-public-api.hoyolab.com)
| conc | success | p50 (ms) | p95 (ms) | blocked | status dist | retcode dist | throughput (req/s) |
|------|---------|----------|----------|---------|-------------|--------------|--------------------|
| 1    | 30/30   | 412      | 580      | 0       | {200: 30}   | {0: 30}      | 1.6                |
| 2    | ...
| ...  | ...
```

throughput 算法：`成功筆數 / wallclock 秒數`（含失敗者的 elapsed，但分子只算成功）。

### URL / UID 脫敏

腳本內所有 log 都走 `lib/services/log_sanitize.dart` 既有 `sanitizeUrl` / `sanitizeUid`，與 production 一致。

## Milestone B — Production 平行化改寫

### 核心改動

#### 1. `lib/services/hoyowiki_fetcher.dart`

- 新增三個欄位（值為依 Milestone A 結論填的保守數，例如 4 / 4 / 8；A 跑完前在 spec 留 placeholder）：
  ```dart
  final int searchConcurrency;
  final int entryConcurrency;
  final int downloadConcurrency;
  ```
- **移除** `rateLimit` 欄位（現有唯一 caller `_fetchHoYoWiki` 與測試會一併清理）
- `searchEntryId` / `fetchEntryPage` / `downloadImage` 三個方法簽名與行為**完全不變**（僅讀傳進來的 client，本身無 mutable state，並行安全）

#### 2. 新增 worker-pool helper

放在 `lib/services/concurrent_pool.dart`（新檔，因為這是 generic utility，不限於 HoYoWiki）：

```dart
/// 跑 [items] 一輪，最多 [concurrency] 個 worker 同時 in-flight。
///
/// - `worker` 拋例外不會中斷其他 worker；caller 在 worker 內自行 try/catch
///   並決定要不要 swallow（HoYoWiki 場景一律 swallow + log warning）
/// - `shouldAbort` 在每個 worker 取下一筆前查；回 true 即所有 worker 早退
/// - items 順序不保證，caller 不可假設完成順序
Future<void> runConcurrent<T>({
  required List<T> items,
  required int concurrency,
  required Future<void> Function(T item) worker,
  required FutureOr<bool> Function() shouldAbort,
});
```

實作 ≈ 30 行：
- atomic int `nextIndex = 0`（Dart 單 isolate，無需 lock）
- 起 `min(concurrency, items.length)` 個 worker future
- 每個 worker `while` 迴圈：`shouldAbort()` true → return；`i = nextIndex++`；越界 → return；否則 `await worker(items[i])`
- 最後 `await Future.wait(workers)`

對應測試 `test/services/concurrent_pool_test.dart`：
- N 個 worker 真同時 in-flight（用 N 個 Completer 驗證）
- 單一 worker 拋例外不中斷其他 worker
- `shouldAbort` 第一輪即 true 時 0 筆執行
- items 為空時不起任何 worker、立刻 resolve

#### 3. `lib/state/gacha_repository.dart::_fetchHoYoWiki()`

三個 `for` 迴圈各換成一個 `runConcurrent` 呼叫：

```dart
final fetcher = ref.read(hoyowikiFetcherProvider);
var doneSearch = 0;
await runConcurrent<(String, String)>(
  items: searchTodo,
  concurrency: fetcher.searchConcurrency,
  shouldAbort: () => !ref.mounted || _cancelTriggered,
  worker: (pair) async {
    try {
      final hit = await fetcher.searchEntryId(
        name: pair.$1,
        lang: pair.$2,
        client: client,
      );
      if (hit != null) {
        await indexNotifier.setSearch(...);  // 已 lock 保護
        ...
      }
    } catch (e) {
      _log.warning('hoyowiki search failed name=${pair.$1} err=$e');
    }
    if (!ref.mounted) return;
    doneSearch++;
    state = state.copyWith(
      progress: FetchingHoYoWiki(
        phase: HoYoWikiPhase.searching,
        doneCount: doneSearch,
        totalCount: searchTodo.length,
      ),
    );
  },
);
if (!ref.mounted || _cancelTriggered) return downloaded;
```

entry 與 download 階段同樣模式套用。

三階段**仍維持串行**（搜尋完才能 entry、entry 完才能 download），只在階段內部並行。

#### 4. `HoYoWikiIndexNotifier` 加 lock

`lib/state/hoyowiki_index.dart`：

```dart
import 'package:synchronized/synchronized.dart';
...
class HoYoWikiIndexNotifier extends Notifier<HoYoWikiIndex> {
  final _lock = Lock();
  ...

  Future<void> setSearch(...) async {
    await _lock.synchronized(() async {
      final newSearch = Map<String, String>.from(state.searchMap)..[...] = id;
      ...
      await _saveAndEmit(next);
    });
  }

  Future<void> setEntry(...) async {
    await _lock.synchronized(() async { ... });
  }

  void bumpCacheRevision() {
    // 不入 lock — 純 identity bump，無 read-modify-write
  }
}
```

理由：N 個 worker 同時跑 `Map.from(state.x)..[k]=v` 會 race（後寫的覆蓋前寫的）。把 read-modify-write 全部串行化即可。

### 取消行為

- 從「每筆後 `Future.delayed(rateLimit)` + checkCancel」搬到 worker loop 開頭 `shouldAbort()`
- `Future.delayed(rateLimit)` 全砍 — 並行度上限本身即是限流
- 取消響應延遲 ≤ 「目前最久的一筆 in-flight item 完成或 timeout（10s）」
- 取消後 progress 行為與現狀一致：`UpdateCompleted` 仍 emit（best-effort 階段），但 `forceRefetchAllHoYoWikiImages` 走 cancel 分支 emit clearProgress

### Progress UI 一致性

- `UpdateProgress` 的 `FetchingHoYoWiki(phase, doneCount, totalCount)` 結構**不變**
- `HoYoWikiPhase` 列舉**不變**
- UI 顯示文案、進度條、i18n 全部**不變**
- 唯一行為差異：`doneCount` 推進不再嚴格遞增 1（亂序完成），但仍嚴格單調遞增到 `totalCount`

### 測試調整

- `test/services/hoyowiki_fetcher_test.dart`：刪掉 `rateLimit` 相關斷言（如有）
- `test/services/concurrent_pool_test.dart`：新增（見前述）
- `test/state/gacha_repository_hoyowiki_test.dart`：
  - 現有「最終結果一致」斷言應仍通過（已是順序無關）
  - 新增「concurrency 生效」測試：用 stub fetcher 把每個 download 內 await 一個 Completer，驗證 N 個 Completer 確實同時 pending
  - 新增「cancel 在 worker 內生效」測試：第一筆完成後設 `_cancelTriggered`，其餘不應被 dispatch
- 既有測試應全綠（YAGNI，不寫新功能就不加新測試）

## 依賴變更

- `pubspec.yaml` `dependencies` 新增 `synchronized: ^3.4.0`（dart 社群慣用 mutex 套件，零非標準傳遞依賴）
- `flutter pub get` 後 `pubspec.lock` 一併更新進 commit

## 風險與緩解

- **A 跑出的安全並行度只是 30 樣本的快照**：本就無法窮舉，預設策略已偏保守（取 A 量出穩定值 ÷ 2 或取 8 兩者取小），加上失敗 item 下次更新重試的安全網
- **HoYoWiki 改變限流策略**：若使用者實際補圖大量 429，下調 hardcode 並行度即可（半小時內可發 patch release）
- **`synchronized` 套件新依賴**：3.x 系列穩定多年、無傳遞依賴、純 Dart 實作；風險極低
- **三階段仍串行，可能有更高效的 pipeline 解**：YAGNI，待先把「直觀的階段內平行」交付完成、實際 telemetry 不夠快時再 revisit

## 完成定義

- Milestone A 探針報告印在 stdout、人工讀完判斷各 host 安全並行度。
  - 三個 host 都有可用並行度（≥ 2）→ Milestone B 照表 hardcode
  - 任一 host 連 2 都被擋（success rate < 100%）→ 該 host 維持並行度 1（即沿用現狀的串行行為，但拿掉 `Future.delayed(rateLimit)`），其他 host 仍照表平行
  - 三個 host 全都連 2 都被擋 → Milestone B 不執行，spec 標 Rejected 並關掉
- Milestone B 改寫完成後：
  - `dart format lib/ test/` 過
  - `flutter analyze` 輸出 `No issues found!`
  - `flutter test` 輸出 `All tests passed!`
  - 手動跑一次「強制重抓所有 HoYoWiki 圖片」對照改寫前耗時，至少 2× 加速且無 429/403 出現於 log
- 探針腳本 `tool/probe_hoyowiki_concurrency.dart` 已刪除，`.gitignore` `tool/probe_*.dart` pattern 已加入
