# 設定頁匯入資料後自動抓取 HoYoWiki 圖片

- 日期：2026-05-25
- 分支起點：`feat/hoyowiki-parallel-fetch`
- 相關既有設計：
  - `2026-05-12-export-import-all-accounts-design.md`（帳號匯出/匯入）
  - `2026-05-23-hoyowiki-item-icon-design.md`（HoYoWiki 補圖流程）
  - `2026-05-24-force-refresh-item-images-design.md`（重抓 HoYoWiki 圖片按鈕）
  - `2026-05-24-hoyowiki-parallel-fetch-design.md`（並行抓取）

## Context

設定頁的「資料管理」目前有三個觸發 HoYoWiki 圖片抓取的時機：

1. **正常 update 流程**（`GachaRepository._fetchAllBanners` 末段）：拉完 banner 後 best-effort 跑 `_fetchHoYoWiki`，整段 emit `UpdateCompleted(hoYoWikiImagesDownloaded: N)`。
2. **「重抓 HoYoWiki 圖片」按鈕**（`forceRefetchAllHoYoWikiImages`）：先 wipe index/cache、再 `_fetchHoYoWiki`。
3. **匯入資料**（`_DataManagement._import` → `GachaRepository.importAccounts`）：**沒有抓圖片**，只寫 storage 與更新偏好，結束彈 snackbar。

第三個流程缺一塊。使用者匯入別人的存檔後，UI 上會看到記錄但圖片缺失，需要再額外按一次「重抓 HoYoWiki 圖片」（且該按鈕還會 wipe 全部 cache 重抓，浪費頻寬）。

## 目標

匯入資料完成後自動接續一段**增量**的 HoYoWiki 圖片抓取，並用既有 `UpdateProgressDialog` 統一呈現「匯入了 N 個帳號 + 下載了 M 張圖」的結果。

## 設計總覽

匯入 confirm 通過後的流程：

```
state.progress = Preparing                  ← app_shell 既有 listener 自動彈 UpdateProgressDialog
↓
_runImport(bundle)                          ← 既有 importAccounts 邏輯改 private
↓
_fetchHoYoWiki(client)                      ← 既有方法，增量補圖三階段
↓
state.progress = UpdateCompleted(
  importSummary: ImportSummary(...),         ← 新增 nullable 欄位
  hoYoWikiImagesDownloaded: M,
)
```

dialog 在 `UpdateCompleted` case 依 `importSummary` 是否非 null 切換顯示文案：
- `importSummary != null`：顯示「本次匯入 N 個帳號（共 M 筆紀錄）」+「下載了 K 張圖」；如有 `failedUids` 一併列出。
- `importSummary == null`：保持原 update 流程顯示「本次新增 N 筆紀錄」。

### 取消行為

`UpdateProgressDialog` 在 `FetchingHoYoWiki` 階段沒有「取消」按鈕（既有 `_actions` 的 `FetchingHoYoWiki()` case 回空陣列）；`Preparing` 階段有取消按鈕。

import 寫入 storage 後**無法回滾**，因此本設計與 `forceRefetchAllHoYoWikiImages` 不同：取消或非取消都 emit `UpdateCompleted`，`importSummary` 反映已成功寫入的帳號數，`hoYoWikiImagesDownloaded` 為取消前的累積。讓使用者明確看到「資料已匯入」這個事實。

### 互斥

repository 層：`state.progress != null || _isUpdating` 任一為真直接 return。共用既有 `_isUpdating` / `_cancelTriggered` / `_activeCancellable` 機制，三條入口（`update` / `forceRefetchAllHoYoWikiImages` / `importAccountsAndFetchHoYoWiki`）不可並行。

UI 層：`_DataManagement` build 內已 watch `progress`，匯入按鈕新增 `progress != null ? null : ...` disable 條件。

## 替代方案比較

| 方案 | 改動 | 採用 | 理由 |
|----|-----|----|------|
| A. 在 `GachaRepository` 新增對稱方法 `importAccountsAndFetchHoYoWiki`，內含完整 progress lifecycle | 中 | ✅ | 重用既有 `_fetchHoYoWiki` 與互斥機制 |
| B. settings_page 端先呼叫 `importAccounts` 再呼叫 `forceRefetchAllHoYoWikiImages` | 小 | ❌ | force-refetch 會 wipe cache、不是增量；UI progress 斷裂；兩段間有 race condition |
| C. 重構 `_runUpdate` 讓 import 與 update 共用同一函式 | 大 | ❌ | 兩者前置完全不同（MITM vs. 讀檔解 bundle）；過度抽象 |

### 為何 `UpdateCompleted.importSummary` 用 nullable 欄位而非新增 sealed 子類別

`UpdateCompleted` 已混合「紀錄數 + HoYoWiki 圖片數 + 失敗 banners」，多一個 `ImportSummary?` 不違和。`UpdateProgressDialog` 既有 `UpdateCompleted` case 不必拆，i18n 只需新增 import 專屬字串。新增 sealed 子類別會逼 `_actions` / `_Title` / `_Body` 都多一個 case 卻僅多顯示一行差異，不值。

## 詳細改動

### A. `lib/state/update_progress.dart`

新增 `ImportSummary` value class、`UpdateCompleted` 加 `importSummary` (nullable) 欄位。

```dart
/// 匯入流程的結果摘要，供 [UpdateCompleted] 在 dialog 顯示。
@immutable
class ImportSummary {
  const ImportSummary({
    required this.successAccounts,
    required this.totalRecords,
    required this.failedUids,
  });

  /// 成功寫入 storage 的帳號數。
  final int successAccounts;

  /// 成功匯入的總祈願紀錄數。
  final int totalRecords;

  /// 寫入 storage 失敗的 UID 列表（空 list 表示全成功）。
  final List<String> failedUids;
}

class UpdateCompleted extends UpdateProgress {
  const UpdateCompleted({
    required this.totalNewRecords,
    required this.failedBanners,
    required this.updatedAt,
    required this.hoYoWikiImagesDownloaded,
    this.importSummary,
  });

  // ... 原欄位 ...

  /// 匯入流程的結果摘要；非 import 入口為 null。
  final ImportSummary? importSummary;
}
```

### B. `lib/state/gacha_repository.dart`

1. 將現有 `Future<ImportResult> importAccounts(AccountsBundle bundle)` body 抽成 private `_runImport`，新增 `@visibleForTesting Future<ImportResult> debugImportOnly(...)` 暴露給單元測試（沿用既有 `debugRunHoYoWikiOnly` 模式）。
2. 新增 public `Future<void> importAccountsAndFetchHoYoWiki(AccountsBundle bundle)`：

```dart
static final _importLog = Logger('gacha.import');

Future<void> importAccountsAndFetchHoYoWiki(AccountsBundle bundle) async {
  if (state.progress != null) {
    _importLog.info('skip: another progress in-flight');
    return;
  }
  if (_isUpdating) return;
  _isUpdating = true;
  _cancelTriggered = false;
  _importLog.info('start, accounts=${bundle.accounts.length}');

  final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
  _activeCancellable = cancellable;
  state = state.copyWith(progress: const Preparing());

  try {
    final result = await _runImport(bundle);
    if (!ref.mounted) return;
    _importLog.info(
      'import done: success=${result.successAccounts} '
      'failed=[${result.failedUids.join(",")}] records=${result.totalRecords}',
    );

    var images = 0;
    try {
      images = await _fetchHoYoWiki(cancellable.client);
    } catch (e, st) {
      _importLog.warning('hoyowiki stage threw (ignored)', e, st);
    }
    if (!ref.mounted) return;

    // 取消與否都 emit UpdateCompleted：import 已寫入無法回滾。
    if (_cancelTriggered) {
      _importLog.info('cancelled during hoyowiki, still emitting completed');
    }
    state = state.copyWith(
      progress: UpdateCompleted(
        totalNewRecords: 0,
        failedBanners: const [],
        updatedAt: DateTime.now().toUtc(),
        hoYoWikiImagesDownloaded: images,
        importSummary: ImportSummary(
          successAccounts: result.successAccounts,
          totalRecords: result.totalRecords,
          failedUids: result.failedUids,
        ),
      ),
    );
  } finally {
    _activeCancellable?.client.close();
    _activeCancellable = null;
    _cancelTriggered = false;
    _isUpdating = false;
  }
}
```

3. 移除 public `importAccounts(bundle)`（YAGNI：只有 settings_page 一個 caller）。

### C. `lib/widgets/update_progress_dialog.dart`

`_Body` 的 `UpdateCompleted` case 加分歧：

```dart
UpdateCompleted(
  :final totalNewRecords,
  :final failedBanners,
  :final hoYoWikiImagesDownloaded,
  :final importSummary,
) =>
  Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (importSummary != null)
        Text(l.progressDoneImportSummary(
          importSummary.successAccounts,
          importSummary.totalRecords,
        ))
      else
        Text(l.progressDoneSummary(totalNewRecords)),
      const SizedBox(height: AppSpacing.xs),
      Text(l.progressDoneImagesSummary(hoYoWikiImagesDownloaded)),
      if (failedBanners.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.s),
        Text(
          l.progressPartialFailed(
            failedBanners.map(resolveBannerName).join('、'),
          ),
          style: TextStyle(color: tokens.stateDanger),
        ),
      ],
      if (importSummary != null && importSummary.failedUids.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.s),
        Text(
          l.progressPartialImportFailed(importSummary.failedUids.join(', ')),
          style: TextStyle(color: tokens.stateDanger),
        ),
      ],
    ],
  ),
```

`_Title` / `_actions` 無需變動。

### D. `lib/pages/settings_page.dart`

`_DataManagement._import` 末段（confirm 通過後）改 fire-and-forget：

```dart
// 移除：
// final result = await ref.read(gachaRepositoryProvider.notifier).importAccounts(filteredBundle);
// final SnackBar snack; if (result.failedUids.isEmpty) {...} else {...}
// ScaffoldMessenger.of(ctx).showSnackBar(snack);

// 改為：
unawaited(
  ref.read(gachaRepositoryProvider.notifier)
       .importAccountsAndFetchHoYoWiki(filteredBundle),
);
```

匯入按鈕 disable 條件補上 `progress != null`：

```dart
OutlinedButton.icon(
  onPressed: progress != null ? null : () => _import(context, ref),
  icon: const Icon(Icons.upload_outlined, size: 18),
  label: Text(l.settingsImportData),
),
```

匯入流程內 import 邏輯本身保留（picker、conflicts/preserved 計算、IMPORT confirm dialog 不變）。

### E. i18n（從 `lib/l10n/app_zh.arb` 起手，依術語表與既有風格）

#### E.1 新增字串（source `app_zh.arb`）

```jsonc
"progressDoneImportSummary": "本次匯入 {accounts} 個帳號（共 {records} 筆紀錄）",
"@progressDoneImportSummary": {
  "placeholders": {
    "accounts": { "type": "int" },
    "records":  { "type": "int" }
  }
},
"progressPartialImportFailed": "⚠ 部分匯入失敗：{uids}",
"@progressPartialImportFailed": {
  "placeholders": { "uids": { "type": "String" } }
}
```

對齊既有 `progressPartialFailed` 的 `⚠` 前綴與「部分…失敗」措辭。

#### E.2 同步補上「成熟翻譯語系」共 9 個檔

依現況檢查（以 `progressDoneImagesSummary` 是否存在判定一個語系是否「已翻譯到位」），這 9 個檔**必須在此 PR 一併補上新 key**：

| 檔案 | 補翻譯 | 備註 |
|----|---|---|
| `app_zh.arb` | source | 簡潔 placeholders 寫法 |
| `app_zh_Hans.arb` | ✓ | 簡中 |
| `app_en.arb` | ✓ | **加 plural form**（對齊 `progressDoneImagesSummary` 樣式：`{count, plural, =1{...} other{...}}`） |
| `app_ja.arb` | ✓ | 日文 |
| `app_es.arb` | ✓ | 西文 |
| `app_fr.arb` | ✓ | 法文 |
| `app_pt_BR.arb` | ✓ | 巴西葡文 |
| `app_th.arb` | ✓ | 泰文 |
| `app_vi.arb` | ✓ | 越文 |

格式必須對齊既有 key 在該檔的展開風格（`description` 在 zh.arb 以外的檔通常有；placeholders 多採展開寫法）。新 key 的 `@progressDoneImportSummary.description` 內容對齊 `progressDoneImagesSummary` 的 description 風格，描述「Completion dialog: imported accounts and total records this run」。

#### E.3 其他 22 個 arb 檔（Crowdin pipeline 處理）

`app_af / app_ar / app_ca / app_cs / app_da / app_de / app_el / app_fi / app_he / app_hu / app_it / app_ko / app_nl / app_no / app_pl / app_pt / app_ro / app_ru / app_sr / app_sv / app_tr / app_uk` 等尚未翻譯到 `progressDoneImagesSummary` 的語系**不在此 PR 範圍**，依既有 Crowdin l10n pipeline 處理（fallback 至 en）。

#### E.4 術語對齊

- 「帳號」沿用既有 `settingsAccountManagement` / `settingsImportData` / `settingsImportSuccess(accounts, records)` 的措辭。
- 「紀錄」對齊 `progressDoneSummary` 的「records」。
- 「匯入」對齊 `settingsImportData`。
- 仍有疑問的譯名以 `docs/術語表.md` 為準（不要從其他來源質疑）。

## 測試計畫

### 既有測試修改

`test/state/gacha_repository_test.dart` 4 個 `importAccounts` test（行 928, 1010, 1076, 1139）：
caller 從 `.importAccounts(bundle)` 改為 `.debugImportOnly(bundle)`。其他斷言保持不變。

### 新增整合測試 `test/state/gacha_repository_import_with_hoyowiki_test.dart`

照 `gacha_repository_refetch_test.dart` 樣板：

| Case | 驗證 |
|----|---|
| 主路徑：bundle 含 N 帳號 + M 筆 record | `state.progress` 走 Preparing → FetchingHoYoWiki 各階段 → `UpdateCompleted(importSummary.successAccounts == N, hoYoWikiImagesDownloaded == K)` |
| 空 bundle | `_fetchHoYoWiki` 跳過、emit `UpdateCompleted(images == 0, importSummary.successAccounts == 0)` |
| 互斥：`state.progress` 非 null 時呼叫 | no-op |
| HoYoWiki 階段取消 | **仍 emit `UpdateCompleted`**，`importSummary` 反映已寫入帳號數 |
| 部分 UID 寫 storage 失敗 | `importSummary.failedUids` 非空、`successAccounts` 為剩餘數 |

### 新增 settings_page 按鈕 disable 測試

照 `test/pages/settings_page_refetch_button_test.dart` 樣板新增：

- `progress != null` 時匯入按鈕 disable
- `hasData == false` 時匯入按鈕**仍可按**（匯入主要用途是 from-empty）

## 非範圍（YAGNI）

- 不支援「只匯入、不抓圖片」的入口（生產不需要）。
- 不新增 `UpdateError` 子類別表達 import 失敗（per-UID 失敗已用 `importSummary.failedUids` 表達）。
- 不為 import 階段加獨立 progress phase（如 `ImportingAccounts`）。import 同步寫 storage 在多數情境下 <1 秒，`Preparing` 已能涵蓋。
- 不改 `_fetchHoYoWiki` 內部邏輯。
- 不改現有「重抓 HoYoWiki 圖片」按鈕。

## 行為注意事項

- `_fetchHoYoWiki` 內部已能在「無新工作」時提早 return 0，所以匯入「與既有完全重複的存檔」也會在進入 download 階段前就結束（dialog 仍會 emit `UpdateCompleted`，圖片數為 0）。
- 匯入會更新 `activeUid`（依 bundle.lastActiveUid 或現有 fallback 邏輯），這層既有行為不變。
- progress dialog `PopScope(canPop: false)`：使用者按 ESC 不會關掉 dialog，僅 `UpdateCompleted` 後可手動按 Close。
- **Preparing 階段按取消**：`cancelPreparing` 僅設 `_cancelTriggered = true` 並關 HTTP client。`_runImport` 是純 storage 寫入、不看 cancel flag、也不需要 client，所以 import 仍會跑完；隨後 `_fetchHoYoWiki` 進入後第一個 `isAborted()` 檢查即提早返回。最終仍 emit `UpdateCompleted`，反映「資料已匯入、圖片下載被略過」。

## Logger 規範

- 樹 `gacha.import` 用於匯入子流程，獨立於 `gacha.repo`（通用 update）與 `gacha.hoyowiki.refetch`（重抓按鈕）。
- 關鍵節點記 log：start (含 totalAccounts) / `_runImport` 完成 (含 success/failed/records) / hoyowiki 階段例外 / cancelled / done。
- UID 與 URL 經 `sanitizeUid` / `sanitizeUrl`。

## 提交品質檢查（CLAUDE.md 規定）

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`
