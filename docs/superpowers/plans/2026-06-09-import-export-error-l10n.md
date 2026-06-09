# 匯入／匯出失敗原因在地化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓匯入／匯出失敗時顯示的原因改為使用者語言（目前是硬編碼英文），採分桶策略。

**Architecture:** 底層 `FormatException` 的英文訊息保留（從此只供 log／測試），改在 UI 層依「捕捉到的例外型別」挑在地化文案；只為「版本過新」這個可行動特例新增專屬例外 `UnsupportedSchemaVersionException`，其餘解析錯誤全歸「格式不正確」一桶。重用既有 `settingsImportFailed`／`settingsExportFailed` wrapper，只替換帶入的原因字串。

**Tech Stack:** Flutter／Dart、FVM 釘住 SDK、ARB + `flutter gen-l10n`（template = `app_zh.arb`，輸出 `lib/l10n/generated/`，未進版控）。

> 設計來源：`docs/superpowers/specs/2026-06-09-import-export-error-l10n-design.md`
> 指令一律優先用 `fvm`（`fvm flutter` / `fvm dart`）；找不到 `fvm` 才退回直接 `flutter` / `dart`。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|------|------|------|
| `lib/models/accounts_bundle.dart` | Modify | 新增 `UnsupportedSchemaVersionException`；版本過新改丟此例外 |
| `lib/services/accounts_import.dart` | Modify | 讓 `UnsupportedSchemaVersionException` 原樣上拋（先 log），不被泛用 catch 吞 |
| `lib/pages/settings_page.dart` | Modify | 三個失敗點停止把英文丟進 UI，改帶在地化 reason key；匯入讀檔失敗補 log |
| `lib/l10n/app_zh.arb`（template）+ 另 8 個已翻語系 | Modify | 新增 4 個 reason key（含譯文） |
| `test/models/accounts_bundle_test.dart` | Modify | 版本過新測試改斷言 `UnsupportedSchemaVersionException` |
| `test/services/accounts_import_test.dart` | Modify | 新增版本過新傳播測試 |

已翻語系（有實體翻譯、要補 key 的 9 個）：`zh`（來源）、`en`、`fr`、`es`、`ja`、`vi`、`th`、`zh_Hans`、`pt_BR`。其餘約 22 個空殼 ARB **不要碰**（留給 Crowdin pipeline）。

---

## Task 1: 新增 `UnsupportedSchemaVersionException`（model 層）

**Files:**
- Modify: `lib/models/accounts_bundle.dart`（新增 class；改 `AccountsBundle.fromJson` 內版本檢查，約 `:73-77`）
- Test: `test/models/accounts_bundle_test.dart:58-76`

- [ ] **Step 1: 改寫版本過新的失敗測試（先紅）**

把 `test/models/accounts_bundle_test.dart` 第 58–76 行整個 `test('schema_version > 1 throws with "update the app" hint', ...)` 區塊替換為：

```dart
  test('schema_version > currentSchemaVersion throws '
      'UnsupportedSchemaVersionException', () {
    final json = {
      'schema_version': 999,
      'exported_at': '2026-05-12T00:00:00.000Z',
      'app_version': '1.0.0',
      'last_active_uid': null,
      'accounts': <Map<String, dynamic>>[],
    };
    expect(
      () => AccountsBundle.fromJson(json),
      throwsA(
        isA<UnsupportedSchemaVersionException>().having(
          (e) => e.version,
          'version',
          999,
        ),
      ),
    );
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/models/accounts_bundle_test.dart`
Expected: FAIL — 編譯錯誤 `Undefined name 'UnsupportedSchemaVersionException'`（型別還沒建立）。

- [ ] **Step 3: 新增例外型別並改丟它**

在 `lib/models/accounts_bundle.dart` 檔案最上方（`ExportedAccount` class 之前、`import` 之後）新增：

```dart
/// 匯入檔的 schema 版本高於目前 App 支援版本時拋出，供 UI 給出「請更新 App」指引。
class UnsupportedSchemaVersionException implements Exception {
  /// 建立 [UnsupportedSchemaVersionException]。
  const UnsupportedSchemaVersionException(this.version);

  /// 匯入檔宣告的 schema 版本（高於 [AccountsBundle.currentSchemaVersion]）。
  final int version;
}
```

在 `AccountsBundle.fromJson` 內，把原本的版本過新分支：

```dart
    if (version > currentSchemaVersion) {
      throw FormatException(
        'Unsupported schema version: $version. Please update the app.',
      );
    }
```

替換為：

```dart
    if (version > currentSchemaVersion) {
      throw UnsupportedSchemaVersionException(version);
    }
```

其餘所有 `FormatException`（`schema_version` 缺漏、`accounts` 非陣列、`accounts[$i]`、`Duplicate UID` 等）**保持不變**。

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/models/accounts_bundle_test.dart`
Expected: PASS（All tests passed!）。其餘 `FormatException` 測試（missing schema_version、accounts must be an array、duplicate UID）仍應綠。

- [ ] **Step 5: Commit**

```bash
git add lib/models/accounts_bundle.dart test/models/accounts_bundle_test.dart
git commit -m "feat(import): add UnsupportedSchemaVersionException for newer-than-supported backups"
```

---

## Task 2: 讓 `importAccounts` 原樣上拋版本例外（service 層）

**Files:**
- Modify: `lib/services/accounts_import.dart:24-32`（包住 `AccountsBundle.fromJson` 的 try/catch）
- Test: `test/services/accounts_import_test.dart`

- [ ] **Step 1: 新增版本過新傳播測試（先紅）**

在 `test/services/accounts_import_test.dart` 的 `main()` 內、最後一個 `test(...)` 之後（第 44 行 `});` 之後、`}` 之前）插入：

```dart

  test('schema_version > 1 → UnsupportedSchemaVersionException', () {
    const text = '''
{
  "schema_version": 999,
  "exported_at": "2026-05-12T08:30:00.000Z",
  "app_version": "1.0.0",
  "last_active_uid": null,
  "accounts": []
}
''';
    expect(
      () => importAccounts(text),
      throwsA(
        isA<UnsupportedSchemaVersionException>().having(
          (e) => e.version,
          'version',
          999,
        ),
      ),
    );
  });
```

並在檔案頂端的 import 區塊（第 2 行 `import '.../services/accounts_import.dart';` 之後）補上 model 的 import，讓測試看得到例外型別：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/accounts_import_test.dart`
Expected: FAIL — 目前 `importAccounts` 的泛用 `catch (e, st)` 會把版本例外包成 `FormatException('Failed to parse: ...')`，故拋出的型別不是 `UnsupportedSchemaVersionException`。

- [ ] **Step 3: 加一條 `on UnsupportedSchemaVersionException` 讓它原樣上拋**

把 `lib/services/accounts_import.dart` 內第 24–32 行的：

```dart
  try {
    return AccountsBundle.fromJson(raw);
  } on FormatException catch (e) {
    _log.warning('import failed: ${e.message}');
    rethrow;
  } catch (e, st) {
    _log.warning('import failed: parse error', e, st);
    throw FormatException('Failed to parse: $e');
  }
```

替換為（在 `on FormatException` 之前先攔版本例外）：

```dart
  try {
    return AccountsBundle.fromJson(raw);
  } on UnsupportedSchemaVersionException catch (e) {
    _log.warning('import failed: unsupported schema version ${e.version}');
    rethrow;
  } on FormatException catch (e) {
    _log.warning('import failed: ${e.message}');
    rethrow;
  } catch (e, st) {
    _log.warning('import failed: parse error', e, st);
    throw FormatException('Failed to parse: $e');
  }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/accounts_import_test.dart`
Expected: PASS（含既有的 Invalid JSON、top-level array → FormatException 兩條仍綠）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/accounts_import.dart test/services/accounts_import_test.dart
git commit -m "feat(import): propagate UnsupportedSchemaVersionException from importAccounts"
```

---

## Task 3: 新增 4 個在地化 reason key（9 語系）+ 重新產生 l10n

**Files:**
- Modify: `lib/l10n/app_zh.arb`（template）、`app_en.arb`、`app_fr.arb`、`app_es.arb`、`app_ja.arb`、`app_vi.arb`、`app_th.arb`、`app_zh_Hans.arb`、`app_pt_BR.arb`

> 每個檔案：找到 `settingsImportFailed` 條目及其 `@settingsImportFailed` metadata 區塊，在該 `@settingsImportFailed` 區塊的結尾 `},` 之後，插入該語系對應的 4 行（頂層 2 空格縮排，第 4 行尾端保留逗號——後面還有其他 key）。這 4 個 key **不需** `@key` 區塊（比照同層 `settingsImportSelectTitle` / `settingsImportMergeBadge` 等無 placeholder 的簡單字串）。**只改下列 9 個檔案**，其餘 ARB 不動。

- [ ] **Step 1: `app_zh.arb`（template，來源）**

```json
  "importReasonInvalidFormat": "檔案格式不正確或已損毀",
  "importReasonUnsupportedVersion": "此檔案由較新版本的 App 匯出，請先更新 App 後再匯入",
  "importReasonUnreadable": "無法讀取檔案",
  "exportReasonWriteFailed": "無法寫入檔案，請確認儲存位置與權限",
```

- [ ] **Step 2: `app_en.arb`**

```json
  "importReasonInvalidFormat": "The file format is invalid or the file is corrupted",
  "importReasonUnsupportedVersion": "This file was exported by a newer version of the app. Please update the app before importing.",
  "importReasonUnreadable": "Unable to read the file",
  "exportReasonWriteFailed": "Unable to write the file, please check the save location and permissions",
```

- [ ] **Step 3: `app_fr.arb`**

```json
  "importReasonInvalidFormat": "Le format du fichier est incorrect ou le fichier est corrompu",
  "importReasonUnsupportedVersion": "Ce fichier a été exporté par une version plus récente de l'application, veuillez la mettre à jour avant de l'importer",
  "importReasonUnreadable": "Impossible de lire le fichier",
  "exportReasonWriteFailed": "Impossible d'écrire le fichier, veuillez vérifier l'emplacement d'enregistrement et les autorisations",
```

- [ ] **Step 4: `app_es.arb`**

```json
  "importReasonInvalidFormat": "El formato del archivo no es válido o está dañado",
  "importReasonUnsupportedVersion": "Este archivo se exportó con una versión más reciente de la aplicación, actualízala antes de importar",
  "importReasonUnreadable": "No se puede leer el archivo",
  "exportReasonWriteFailed": "No se puede escribir el archivo, comprueba la ubicación de guardado y los permisos",
```

- [ ] **Step 5: `app_ja.arb`**

```json
  "importReasonInvalidFormat": "ファイル形式が正しくないか、ファイルが破損しています",
  "importReasonUnsupportedVersion": "このファイルは、より新しいバージョンのツールでエクスポートされています。ツールを更新してからインポートしてください",
  "importReasonUnreadable": "ファイルを読み込めません",
  "exportReasonWriteFailed": "ファイルを書き込めません。保存先と権限を確認してください",
```

- [ ] **Step 6: `app_vi.arb`**

```json
  "importReasonInvalidFormat": "Định dạng tệp không hợp lệ hoặc đã bị hỏng",
  "importReasonUnsupportedVersion": "Tệp này được xuất từ phiên bản ứng dụng mới hơn, vui lòng cập nhật ứng dụng trước khi nhập",
  "importReasonUnreadable": "Không thể đọc tệp",
  "exportReasonWriteFailed": "Không thể ghi tệp, vui lòng kiểm tra vị trí lưu và quyền truy cập",
```

- [ ] **Step 7: `app_th.arb`**

```json
  "importReasonInvalidFormat": "รูปแบบไฟล์ไม่ถูกต้องหรือไฟล์เสียหาย",
  "importReasonUnsupportedVersion": "ไฟล์นี้ถูกส่งออกจากแอปเวอร์ชันที่ใหม่กว่า กรุณาอัปเดตแอปก่อนนำเข้า",
  "importReasonUnreadable": "ไม่สามารถอ่านไฟล์ได้",
  "exportReasonWriteFailed": "ไม่สามารถเขียนไฟล์ได้ กรุณาตรวจสอบตำแหน่งที่บันทึกและสิทธิ์การเข้าถึง",
```

- [ ] **Step 8: `app_zh_Hans.arb`**

```json
  "importReasonInvalidFormat": "文件格式不正确或已损坏",
  "importReasonUnsupportedVersion": "此文件由较新版本的软件导出，请先更新软件后再导入",
  "importReasonUnreadable": "无法读取文件",
  "exportReasonWriteFailed": "无法写入文件，请确认保存位置与权限",
```

- [ ] **Step 9: `app_pt_BR.arb`**

```json
  "importReasonInvalidFormat": "O formato do arquivo é inválido ou o arquivo está corrompido",
  "importReasonUnsupportedVersion": "Este arquivo foi exportado por uma versão mais recente do aplicativo. Atualize o aplicativo antes de importar",
  "importReasonUnreadable": "Não foi possível ler o arquivo",
  "exportReasonWriteFailed": "Não foi possível gravar o arquivo. Verifique o local de salvamento e as permissões",
```

- [ ] **Step 10: 重新產生 l10n 並驗證 ARB 合法**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤輸出；`lib/l10n/generated/app_localizations.dart` 重新產生（此目錄未進版控，不需 commit）。

驗證 getter 已生成：
Run: `fvm flutter analyze`
Expected: `No issues found!`（ARB JSON 合法、key 一致；此時程式還沒用到新 key，但不應因 ARB 出錯）。

- [ ] **Step 11: Commit**

> `lib/l10n/generated/` 未進版控，`git add lib/l10n/` 只會納入 `.arb`。

```bash
git add lib/l10n/
git commit -m "feat(l10n): add localized import/export failure reason strings"
```

---

## Task 4: 接上 UI —— `settings_page.dart` 三個失敗點改用在地化 reason

**Files:**
- Modify: `lib/pages/settings_page.dart`（匯出失敗 `:497`、匯入讀檔失敗 `:527-532`、`importAccounts` catch `:536-544`）

> `settings_page.dart` 已 import `models/accounts_bundle.dart`（`:15`）與 `package:logging/logging.dart`（`:7`），不需補 import。

- [ ] **Step 1: 匯出失敗改用 `exportReasonWriteFailed`**

把第 497 行：

```dart
        message: l.settingsExportFailed(e.toString()),
```

改為：

```dart
        message: l.settingsExportFailed(l.exportReasonWriteFailed),
```

（此區塊上方第 490–492 行已有 `Logger('accounts.io').severe('export failed ...', e, st)`，英文細節仍進 log，不需再動。）

- [ ] **Step 2: 匯入讀檔失敗——補 log + 改用 `importReasonUnreadable`**

把第 527–532 行：

```dart
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportFailed(e.toString()))),
      );
      return;
    }
```

替換為：

```dart
    } catch (e, st) {
      Logger('accounts.io').warning('import: read file failed', e, st);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportFailed(l.importReasonUnreadable))),
      );
      return;
    }
```

- [ ] **Step 3: `importAccounts` catch——依型別分桶**

把第 536–544 行：

```dart
    try {
      bundle = importAccounts(text);
    } on FormatException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportFailed(e.message))),
      );
      return;
    }
```

替換為：

```dart
    try {
      bundle = importAccounts(text);
    } on UnsupportedSchemaVersionException {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(l.settingsImportFailed(l.importReasonUnsupportedVersion)),
        ),
      );
      return;
    } on FormatException {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(l.settingsImportFailed(l.importReasonInvalidFormat)),
        ),
      );
      return;
    }
```

> 註：英文細節已在 `importAccounts` 內 `_log.warning`，UI 不重複 log。`on FormatException` / `on UnsupportedSchemaVersionException` 不綁變數，避免 unused-variable 警告。

> 不在此加 widget 測試：此改動是「例外型別 → l10n key」的純呈現映射，要測得跑完整 widget pump + mock file picker，成本遠高於價值（既有測試也未覆蓋 settings_page UI）。靠 analyze + 全套 test 綠 + 手動驗收即可。

- [ ] **Step 4: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 顯示已格式化的檔案數，無錯誤。

- [ ] **Step 5: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "fix(import): localize import/export failure reasons in settings"
```

---

## Task 5: 最終驗收

- [ ] **Step 1: 全套品質檢查（對齊 CLAUDE.md 提交前流程）**

依序執行，三項全綠才算完成：

```bash
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
```

Expected:
- format：無錯誤
- analyze：`No issues found!`
- test：`All tests passed!`

- [ ] **Step 2: 手動驗收（擇一語言切到非英文）**

在非英文語系下，於設定頁觸發匯入一個壞掉／非 JSON 的檔案，確認 SnackBar 顯示的失敗原因為該語言（無英文殘留）；若手邊有「schema_version 較新」的測試檔，確認顯示「請更新 App」那條在地化訊息。

> 不要主動 `git push`。

---

## Self-Review

**Spec coverage（逐項對照 spec）：**
- 匯入解析錯誤英文 → Task 3 `importReasonInvalidFormat` + Task 4 Step 3 `on FormatException`。✓
- 版本過新可行動訊息 → Task 1（例外）+ Task 2（傳播）+ Task 3 `importReasonUnsupportedVersion` + Task 4 Step 3 `on UnsupportedSchemaVersionException`。✓
- 匯入讀檔 IO 失敗 → Task 3 `importReasonUnreadable` + Task 4 Step 2（含補 log）。✓
- 匯出 IO 失敗 → Task 3 `exportReasonWriteFailed` + Task 4 Step 1。✓
- 英文細節保留在 log → model/service 既有 `_log.warning`／export 既有 `.severe` 不動；匯入讀檔失敗新增 `.warning`。✓
- 只翻已翻語系、空殼留給 Crowdin → Task 3 限定 9 檔。✓
- analyze + test 全綠 → Task 4 Step 5–6、Task 5。✓

**Placeholder 掃描：** 無 TBD／TODO；每個改動步驟都附完整程式碼與實際譯文。✓

**型別一致性：** `UnsupportedSchemaVersionException`（Task 1 定義 → Task 2 攔截 → Task 4 catch）、`.version` 欄位（Task 1 定義 → Task 1/2 測試斷言）、4 個 ARB key 名（Task 3 定義 → Task 4 引用）全程一致。✓

**不在範圍：** `Text('Developed by ')`、中文 `semanticLabel`、純符號、只進 log 的技術性錯誤、`progressPartialImportFailed`／`settingsImportPartial`。
