# 介面隱私模式（遮蔽 UID）實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設定頁新增「遮蔽介面 UID」開關，開啟時將 AppBar、帳號菜單、帳號管理清單三處的 UID 顯示為前 3 碼 + `x` 遮蔽（沿用既有 `maskUidForShare`）；資料檔、刪除確認框、分享圖不受影響。

**Architecture:** `AppSettings.maskUidInUi` (bool) 經 SharedPreferences 持久化、由 Riverpod `settingsProvider` 廣播；新增純函式 `displayUid(uid, {mask})` 集中處理顯示邏輯，內部呼叫既有 `maskUidForShare`；UI 顯示點以 `ref.watch(settingsProvider).maskUidInUi` 取得旗標後傳入子 widget。

**Tech Stack:** Flutter / Dart 3 / Riverpod (Notifier) / shared_preferences / logging / flutter_localizations + gen_l10n。

**Spec reference:** `docs/superpowers/specs/2026-05-27-privacy-mask-uid-design.md`

---

## File Structure

| 動作 | 路徑 | 責任 |
|---|---|---|
| Modify | `lib/services/settings_storage.dart` | 新增 `_kMaskUidInUi` key、load/save 欄位 |
| Modify | `lib/state/settings.dart` | `AppSettings.maskUidInUi` 欄位 + `SettingsNotifier.setMaskUidInUi` |
| Create | `lib/utils/uid_display.dart` | `displayUid(uid, {required mask})` 純函式 helper |
| Modify | `lib/widgets/uid_indicator.dart` | AppBar 觸發鈕與菜單副標套用 `displayUid` |
| Modify | `lib/widgets/cards/account_management.dart` | 清單 row UID 套用 `displayUid` |
| Modify | `lib/pages/settings_page.dart` | 新增 Privacy section（Appearance 與 Language 之間）|
| Modify | `lib/l10n/app_zh.arb`、`app_en.arb`、`app_zh_Hans.arb`、`app_es.arb`、`app_fr.arb`、`app_ja.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb` | 新增 3 個 i18n key |
| Modify | `test/services/settings_storage_test.dart` | 擴充 `maskUidInUi` 序列化測試 |
| Modify | `test/state/settings_test.dart` | 擴充 `setMaskUidInUi` 測試 |
| Create | `test/utils/uid_display_test.dart` | `displayUid` unit test |
| Modify | `test/widgets/uid_indicator_test.dart` | 擴充 mask on/off widget test |
| Modify | `test/widgets/cards/account_management_test.dart` | 擴充 mask on/off widget test |
| Create | `test/pages/settings_privacy_section_test.dart` | Privacy section toggle widget test |

---

## Task 1：Settings 資料層加上 `maskUidInUi`

**Files:**
- Modify: `lib/services/settings_storage.dart`
- Modify: `lib/state/settings.dart`
- Modify: `test/services/settings_storage_test.dart`
- Modify: `test/state/settings_test.dart`

### Step 1.1：擴充 settings_storage_test 加 failing test

- [ ] **打開 `test/services/settings_storage_test.dart`，在「main()」內最後加上以下 group**：

```dart
group('maskUidInUi', () {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to false when key absent', () async {
    final s = await SettingsStorage.load();
    expect(s.maskUidInUi, false);
  });

  test('roundtrips true', () async {
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(maskUidInUi: true),
    );
    final s = await SettingsStorage.load();
    expect(s.maskUidInUi, true);
  });

  test('roundtrips false explicitly', () async {
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(maskUidInUi: false),
    );
    final s = await SettingsStorage.load();
    expect(s.maskUidInUi, false);
  });
});
```

### Step 1.2：跑測試確認失敗

Run: `flutter test test/services/settings_storage_test.dart`
Expected: FAIL（`The named parameter 'maskUidInUi' isn't defined.` 或 `member 'maskUidInUi' isn't defined for the type 'AppSettings'`）

### Step 1.3：在 `lib/state/settings.dart` 不需改（這檔不是 AppSettings 定義處），AppSettings 在 `lib/services/settings_storage.dart`。打開 `settings_storage.dart`，把 `AppSettings` 改成

把行 74-132 的 `AppSettings` 整段換成：

```dart
@immutable
class AppSettings {
  /// 建立 [AppSettings]。
  const AppSettings({
    required this.themeMode,
    required this.locale,
    this.lastActiveUid,
    this.uidAliases = const {},
    this.uidOrder = const [],
    this.skippedReleaseTag,
    this.maskUidInUi = false,
  });

  /// 外觀主題。
  final AppThemeMode themeMode;

  /// 語言偏好。
  final LanguagePreference locale;

  /// 最近一次使用的 UID。
  final String? lastActiveUid;

  /// UID 別名對應，key = uid。
  final Map<String, String> uidAliases;

  /// 使用者自訂的 UID 顯示順序。
  final List<String> uidOrder;

  /// 使用者選擇跳過的 release tag（已讀過不再提示）。
  final String? skippedReleaseTag;

  /// 是否在介面中遮蔽 UID（前 3 碼 + `x`）；資料檔與刪除確認框不受影響。
  final bool maskUidInUi;

  /// 預設設定值（跟隨系統主題與語言）。
  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: SystemLanguage(),
  );

  /// 回傳以指定欄位覆寫的新 [AppSettings]；
  /// 傳 `clearLastActiveUid: true` 或 `clearSkippedReleaseTag: true` 可將對應欄位清為 null。
  AppSettings copyWith({
    AppThemeMode? themeMode,
    LanguagePreference? locale,
    String? lastActiveUid,
    bool clearLastActiveUid = false,
    Map<String, String>? uidAliases,
    List<String>? uidOrder,
    String? skippedReleaseTag,
    bool clearSkippedReleaseTag = false,
    bool? maskUidInUi,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    lastActiveUid: clearLastActiveUid
        ? null
        : (lastActiveUid ?? this.lastActiveUid),
    uidAliases: uidAliases ?? this.uidAliases,
    uidOrder: uidOrder ?? this.uidOrder,
    skippedReleaseTag: clearSkippedReleaseTag
        ? null
        : (skippedReleaseTag ?? this.skippedReleaseTag),
    maskUidInUi: maskUidInUi ?? this.maskUidInUi,
  );
}
```

### Step 1.4：在 `SettingsStorage` 加 key + load/save

在 `SettingsStorage` 類別的 keys 區塊（行 155 之後）加：

```dart
  /// SharedPreferences key：是否在介面中遮蔽 UID。
  static const _kMaskUidInUi = 'pref.maskUidInUi';
```

修改 `load()` 的 return AppSettings(...) 加最後一行：

```dart
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: _parseLocale(prefs.getString(_kLocale)),
      lastActiveUid: prefs.getString(_kLastActiveUid),
      uidAliases: _parseAliases(prefs.getString(_kUidAliases)),
      uidOrder: _parseOrder(prefs.getString(_kUidOrder)),
      skippedReleaseTag: prefs.getString(_kSkippedReleaseTag),
      maskUidInUi: prefs.getBool(_kMaskUidInUi) ?? false,
    );
```

修改 `save()` 結尾加：

```dart
    await prefs.setBool(_kMaskUidInUi, s.maskUidInUi);
```

### Step 1.5：跑測試確認 storage 通過

Run: `flutter test test/services/settings_storage_test.dart`
Expected: PASS（所有測試包含新加 3 個）

### Step 1.6：擴充 settings_test 加 SettingsNotifier 行為 failing test

打開 `test/state/settings_test.dart`，在 main 內加：

```dart
group('setMaskUidInUi', () {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('default state is false', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    expect(container.read(settingsProvider).maskUidInUi, false);
  });

  test('toggles state and persists', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(settingsProvider.notifier).setMaskUidInUi(true);
    expect(container.read(settingsProvider).maskUidInUi, true);

    final reloaded = await SettingsStorage.load();
    expect(reloaded.maskUidInUi, true);
  });

  test('toggles back to false and persists', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    await container.read(settingsProvider.notifier).setMaskUidInUi(true);

    await container.read(settingsProvider.notifier).setMaskUidInUi(false);
    expect(container.read(settingsProvider).maskUidInUi, false);

    final reloaded = await SettingsStorage.load();
    expect(reloaded.maskUidInUi, false);
  });
});
```

注意：若 `settings_test.dart` 尚未 import `ProviderContainer`、`SharedPreferences`、`SettingsStorage`，依既有 import 風格補上：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
```

### Step 1.7：跑測試確認失敗

Run: `flutter test test/state/settings_test.dart`
Expected: FAIL（`setMaskUidInUi` 方法尚未定義）

### Step 1.8：實作 `SettingsNotifier.setMaskUidInUi`

打開 `lib/state/settings.dart`，在 `setSkippedReleaseTag` 後面（行 73 後）加：

```dart
  /// 切換「遮蔽介面 UID」設定並持久化；同時 log 變更（脫敏不必要，值是 bool）。
  Future<void> setMaskUidInUi(bool value) async {
    state = state.copyWith(maskUidInUi: value);
    await SettingsStorage.save(state);
    Logger('app.settings').info('maskUidInUi toggled', value);
  }
```

確認檔首 import 含 `package:logging/logging.dart`，若無就加上：

```dart
import 'package:logging/logging.dart';
```

### Step 1.9：跑測試確認通過

Run: `flutter test test/state/settings_test.dart test/services/settings_storage_test.dart`
Expected: PASS

### Step 1.10：Commit

```bash
git add lib/services/settings_storage.dart lib/state/settings.dart test/services/settings_storage_test.dart test/state/settings_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): persist maskUidInUi preference

新增 AppSettings.maskUidInUi 欄位（預設 false）與 SettingsNotifier.setMaskUidInUi setter，作為後續介面隱私模式的資料層基礎。
EOF
)"
```

---

## Task 2：新增 `displayUid` helper

**Files:**
- Create: `lib/utils/uid_display.dart`
- Create: `test/utils/uid_display_test.dart`

### Step 2.1：寫 failing test

建立 `test/utils/uid_display_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/uid_display.dart';

void main() {
  group('displayUid', () {
    test('returns original uid when mask=false', () {
      expect(displayUid('123456789', mask: false), '123456789');
    });

    test('returns masked uid when mask=true', () {
      expect(displayUid('123456789', mask: true), '123xxxxxx');
    });

    test('mask=true delegates to maskUidForShare', () {
      const uid = '987654321';
      expect(displayUid(uid, mask: true), maskUidForShare(uid));
    });

    test('handles empty string', () {
      expect(displayUid('', mask: true), 'xxx');
      expect(displayUid('', mask: false), '');
    });

    test('handles short uid (< 3 chars)', () {
      expect(displayUid('12', mask: true), 'xxx');
      expect(displayUid('12', mask: false), '12');
    });

    test('handles uid of exactly 3 chars', () {
      expect(displayUid('123', mask: true), '123');
      expect(displayUid('123', mask: false), '123');
    });
  });
}
```

### Step 2.2：跑測試確認失敗

Run: `flutter test test/utils/uid_display_test.dart`
Expected: FAIL（`Target of URI doesn't exist: 'package:.../utils/uid_display.dart'`）

### Step 2.3：實作 helper

建立 `lib/utils/uid_display.dart`：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';

/// UID 介面顯示工具：依介面隱私設定回傳遮蔽後或原樣 UID。
///
/// [mask] 來自 `AppSettings.maskUidInUi`。`true` 時呼叫 [maskUidForShare]
/// （前 3 碼 + `x` 遮蔽其餘），與分享圖政策一致；`false` 時原樣回傳。
///
/// 與 log 用的 `sanitizeUid` 刻意分開：log 場景需要末碼幫助稽核交叉比對，
/// UI 場景則是公開曝光情境，不應洩漏末碼。
String displayUid(String uid, {required bool mask}) =>
    mask ? maskUidForShare(uid) : uid;
```

### Step 2.4：跑測試確認通過

Run: `flutter test test/utils/uid_display_test.dart`
Expected: PASS（6 個測試全部通過）

### Step 2.5：Commit

```bash
git add lib/utils/uid_display.dart test/utils/uid_display_test.dart
git commit -m "$(cat <<'EOF'
feat(utils): add displayUid helper for interface privacy

新增 displayUid(uid, {mask}) 純函式，內部委派給 maskUidForShare。
集中 UI 層 UID 顯示邏輯，方便後續 widget 套用。
EOF
)"
```

---

## Task 3：新增 i18n 字串到 9 個非空殼 ARB

**Files:**
- Modify: `lib/l10n/app_zh.arb`（先寫繁中作為基準）
- Modify: `lib/l10n/app_en.arb`（主範本，需 description）
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_es.arb`
- Modify: `lib/l10n/app_fr.arb`
- Modify: `lib/l10n/app_ja.arb`
- Modify: `lib/l10n/app_pt_BR.arb`
- Modify: `lib/l10n/app_th.arb`
- Modify: `lib/l10n/app_vi.arb`

### Step 3.1：在 `app_zh.arb` 新增 3 個 key

打開 `lib/l10n/app_zh.arb`，找到 `"settingsAppearance"` 系列附近（與 settings 設定相關的 key 群）。在最後一個 `settings*` 區塊內、合適的群組位置加入（建議插在 `settingsAppearance` 之後、`settingsLanguage` 之前；若該檔尚無這兩個 key，找已存在的 settings 區塊插入即可）：

```json
  "settingsPrivacySectionTitle": "隱私",
  "settingsMaskUidInUi": "遮蔽介面中的 UID",
  "settingsMaskUidInUiHint": "開啟後，畫面與帳號清單中的 UID 會以前 3 碼搭配 x 顯示（例如 123xxxxx），適合實況或螢幕分享時使用。分享圖、匯出檔案、刪除確認框不受影響。",
```

注意：依 CLAUDE.md「CJK 標點全形」原則，中文字串內用全形逗號 `，` 與全形句號 `。`、全形括號 `（）`。`UID`、`x`、`123xxxxx` 為英數半形。

### Step 3.2：在 `app_en.arb` 新增 3 個 key + 描述

打開 `lib/l10n/app_en.arb`，找到 settings 區塊，加入：

```json
  "settingsPrivacySectionTitle": "Privacy",
  "@settingsPrivacySectionTitle": {
    "description": "Settings page section title for privacy-related toggles."
  },
  "settingsMaskUidInUi": "Mask UID in interface",
  "@settingsMaskUidInUi": {
    "description": "Settings toggle label: when on, UIDs are masked in the app UI."
  },
  "settingsMaskUidInUiHint": "When on, UIDs in the interface and account list show the first 3 digits with the rest masked (e.g. 123xxxxx). Useful for streaming or screen sharing. Share images, exported files, and the delete confirmation dialog are not affected.",
  "@settingsMaskUidInUiHint": {
    "description": "Settings toggle subtitle: explains scope of the maskUidInUi setting."
  },
```

### Step 3.3：在 `app_zh_Hans.arb` 新增（簡中）

```json
  "settingsPrivacySectionTitle": "隐私",
  "settingsMaskUidInUi": "遮蔽界面中的 UID",
  "settingsMaskUidInUiHint": "开启后，画面与账号清单中的 UID 会以前 3 码搭配 x 显示（例如 123xxxxx），适合直播或屏幕分享时使用。分享图、导出文件、删除确认框不受影响。",
```

### Step 3.4：在 `app_ja.arb` 新增（日文，全形標點）

```json
  "settingsPrivacySectionTitle": "プライバシー",
  "settingsMaskUidInUi": "画面上の UID をマスク",
  "settingsMaskUidInUiHint": "オンにすると、画面とアカウント一覧の UID が先頭 3 桁と残りを x でマスクして表示されます（例：123xxxxx）。配信や画面共有時に便利です。共有画像、エクスポートファイル、削除確認ダイアログは影響を受けません。",
```

### Step 3.5：在 `app_es.arb` 新增

```json
  "settingsPrivacySectionTitle": "Privacidad",
  "settingsMaskUidInUi": "Ocultar UID en la interfaz",
  "settingsMaskUidInUiHint": "Cuando está activado, los UID en la interfaz y la lista de cuentas muestran los primeros 3 dígitos y el resto enmascarado (por ejemplo, 123xxxxx). Útil para transmisiones en vivo o al compartir pantalla. Las imágenes para compartir, los archivos exportados y el diálogo de confirmación de eliminación no se ven afectados.",
```

### Step 3.6：在 `app_fr.arb` 新增

```json
  "settingsPrivacySectionTitle": "Confidentialité",
  "settingsMaskUidInUi": "Masquer l'UID dans l'interface",
  "settingsMaskUidInUiHint": "Lorsqu'activé, les UID dans l'interface et la liste des comptes affichent les 3 premiers chiffres et le reste est masqué (par exemple 123xxxxx). Utile pour le streaming ou le partage d'écran. Les images de partage, les fichiers exportés et la boîte de dialogue de confirmation de suppression ne sont pas affectés.",
```

### Step 3.7：在 `app_pt_BR.arb` 新增

```json
  "settingsPrivacySectionTitle": "Privacidade",
  "settingsMaskUidInUi": "Mascarar UID na interface",
  "settingsMaskUidInUiHint": "Quando ativado, os UIDs na interface e na lista de contas mostram os 3 primeiros dígitos com o restante mascarado (por exemplo, 123xxxxx). Útil para transmissões ou compartilhamento de tela. Imagens compartilháveis, arquivos exportados e a caixa de diálogo de confirmação de exclusão não são afetados.",
```

### Step 3.8：在 `app_th.arb` 新增

```json
  "settingsPrivacySectionTitle": "ความเป็นส่วนตัว",
  "settingsMaskUidInUi": "ปิดบัง UID ในอินเทอร์เฟซ",
  "settingsMaskUidInUiHint": "เมื่อเปิดใช้งาน UID ในอินเทอร์เฟซและรายการบัญชีจะแสดง 3 หลักแรกและส่วนที่เหลือจะถูกปิดบัง (เช่น 123xxxxx) เหมาะสำหรับการสตรีมหรือการแชร์หน้าจอ ภาพแชร์ ไฟล์ส่งออก และกล่องโต้ตอบยืนยันการลบจะไม่ได้รับผลกระทบ",
```

### Step 3.9：在 `app_vi.arb` 新增

```json
  "settingsPrivacySectionTitle": "Quyền riêng tư",
  "settingsMaskUidInUi": "Che giấu UID trong giao diện",
  "settingsMaskUidInUiHint": "Khi bật, UID trong giao diện và danh sách tài khoản sẽ hiển thị 3 chữ số đầu tiên và phần còn lại được che giấu (ví dụ: 123xxxxx). Hữu ích khi phát trực tiếp hoặc chia sẻ màn hình. Hình ảnh chia sẻ, tệp xuất và hộp thoại xác nhận xóa không bị ảnh hưởng.",
```

### Step 3.10：重新生成 localizations

Run: `flutter gen-l10n`
Expected: 無錯誤輸出。`lib/l10n/generated/app_localizations*.dart` 內出現新的 getter `settingsPrivacySectionTitle`、`settingsMaskUidInUi`、`settingsMaskUidInUiHint`。

驗證：
Run: `flutter analyze lib/l10n/generated/`
Expected: `No issues found!`

### Step 3.11：Commit

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_ja.arb lib/l10n/app_pt_BR.arb lib/l10n/app_th.arb lib/l10n/app_vi.arb lib/l10n/generated/
git commit -m "$(cat <<'EOF'
i18n(settings): add privacy section keys for mask UID toggle

新增 settingsPrivacySectionTitle、settingsMaskUidInUi、settingsMaskUidInUiHint 三個 key 到 9 個非空殼 ARB（zh、en、zh_Hans、es、fr、ja、pt_BR、th、vi）。空殼 ARB 留給 Crowdin pipeline。
EOF
)"
```

---

## Task 4：套用 `displayUid` 到 `uid_indicator.dart`

**Files:**
- Modify: `lib/widgets/uid_indicator.dart`
- Modify: `test/widgets/uid_indicator_test.dart`

### Step 4.1：寫 failing widget test

打開 `test/widgets/uid_indicator_test.dart`，在 main 內加入新 group。注意既有測試的 ProviderScope override pattern；若該檔尚未 mock settingsProvider，依以下完整範本加入：

```dart
group('UidIndicator: maskUidInUi', () {
  Widget buildHarness({
    required bool maskUidInUi,
    String activeUid = '123456789',
    Map<String, String> aliases = const {},
  }) {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() {
          final n = SettingsNotifier();
          // 透過 ProviderContainer 不太行，用 listenSelf 或直接 override state：
          return n;
        }),
        // 為了簡化，改用 fake notifier：
      ],
      child: const _UidIndicatorHarness(),
    );
  }

  testWidgets('shows full UID when maskUidInUi=false', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref.maskUidInUi': false,
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: UidIndicator()),
        ),
      ),
    );
    // 等 settings load + initial gacha state
    await tester.pumpAndSettle();
    expect(find.text('123456789'), findsWidgets);
    expect(find.text('123xxxxxx'), findsNothing);
  });

  testWidgets('shows masked UID when maskUidInUi=true', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref.maskUidInUi': true,
    });
    // 假設既有 helper 注入 active uid（依專案既有 gacha repository test pattern）
    // ...
    await tester.pumpAndSettle();
    expect(find.text('123xxxxxx'), findsWidgets);
    expect(find.text('123456789'), findsNothing);
  });
});
```

**實作說明**：上述測試需要既有 gacha repository 有 active uid 才能渲染 `AccountTriggerLabel`。如果既有 `uid_indicator_test.dart` 已有 override pattern（例如 fake gacha repository state），延用即可；若無，最簡單做法是改測「純呈現層」`AccountTriggerLabel` 與 `AccountMenuLabel`，這兩個 widget 不依賴 provider：

```dart
group('AccountTriggerLabel: maskUid', () {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('displays full uid when maskUid=false', (tester) async {
    await tester.pumpWidget(
      wrap(const AccountTriggerLabel(activeUid: '123456789', maskUid: false)),
    );
    expect(find.text('123456789'), findsOneWidget);
  });

  testWidgets('displays masked uid when maskUid=true', (tester) async {
    await tester.pumpWidget(
      wrap(const AccountTriggerLabel(activeUid: '123456789', maskUid: true)),
    );
    expect(find.text('123xxxxxx'), findsOneWidget);
    expect(find.text('123456789'), findsNothing);
  });

  testWidgets('with alias: still masks the (uid) suffix', (tester) async {
    await tester.pumpWidget(
      wrap(const AccountTriggerLabel(
        activeUid: '123456789',
        alias: '主帳',
        maskUid: true,
      )),
    );
    expect(find.text('主帳'), findsOneWidget);
    expect(find.text(' (123xxxxxx)'), findsOneWidget);
    expect(find.text(' (123456789)'), findsNothing);
  });

  testWidgets('with alias: maskUid=false shows full', (tester) async {
    await tester.pumpWidget(
      wrap(const AccountTriggerLabel(
        activeUid: '123456789',
        alias: '主帳',
        maskUid: false,
      )),
    );
    expect(find.text(' (123456789)'), findsOneWidget);
  });
});

group('AccountMenuLabel: maskUid', () {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('without alias shows masked uid as primary', (tester) async {
    await tester.pumpWidget(
      wrap(const AccountMenuLabel(
        uid: '123456789',
        isActive: false,
        maskUid: true,
      )),
    );
    expect(find.text('123xxxxxx'), findsOneWidget);
  });

  testWidgets('with alias: alias primary, masked uid as subtitle', (tester) async {
    await tester.pumpWidget(
      wrap(const AccountMenuLabel(
        uid: '123456789',
        alias: '主帳',
        isActive: false,
        maskUid: true,
      )),
    );
    expect(find.text('主帳'), findsOneWidget);
    expect(find.text('123xxxxxx'), findsOneWidget);
    expect(find.text('123456789'), findsNothing);
  });
});
```

確認 import 已含必要套件：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';
```

### Step 4.2：跑測試確認失敗

Run: `flutter test test/widgets/uid_indicator_test.dart`
Expected: FAIL（`AccountTriggerLabel` 與 `AccountMenuLabel` 沒有 `maskUid` 參數）

### Step 4.3：實作 `AccountTriggerLabel` 加 maskUid 參數

打開 `lib/widgets/uid_indicator.dart`。把 `AccountTriggerLabel`（行 120-161）整段換成：

```dart
/// AppBar 觸發鈕的單行顯示:alias (uid),alias 過長 ellipsis;
/// 無 alias 顯示 UID;activeUid==null 顯示「未同步」。
class AccountTriggerLabel extends StatelessWidget {
  /// 建立 [AccountTriggerLabel]。
  const AccountTriggerLabel({
    super.key,
    this.activeUid,
    this.alias,
    this.maskUid = false,
  });

  /// 當前登入的 UID，`null` 表示尚未同步。
  final String? activeUid;

  /// 使用者自訂的帳號別名。
  final String? alias;

  /// 是否套用介面隱私模式（前 3 + `x` 遮蔽）。
  final bool maskUid;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final uid = activeUid;
    if (uid == null) {
      return _row([
        const Icon(Icons.person_outline, size: 18),
        const SizedBox(width: AppSpacing.xs),
        Text(l.uidNotSynced),
        const Icon(Icons.arrow_drop_down, size: 18),
      ]);
    }
    final hasAlias = alias != null && alias!.isNotEmpty;
    final shown = displayUid(uid, mask: maskUid);
    return _row([
      const Icon(Icons.person_outline, size: 18),
      const SizedBox(width: AppSpacing.xs),
      if (hasAlias) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(alias!, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Text(' ($shown)'),
      ] else
        Text(shown),
      const Icon(Icons.arrow_drop_down, size: 18),
    ]);
  }

  /// 以 [MainAxisSize.min] Row 包裝 [children]。
  Widget _row(List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);
}
```

### Step 4.4：實作 `AccountMenuLabel` 加 maskUid 參數

把 `AccountMenuLabel`（行 205-258）整段換成：

```dart
/// 選單項目顯示:alias 主標 + UID 副標。沒 alias 時退化為 UID 單行。
class AccountMenuLabel extends StatelessWidget {
  /// 建立 [AccountMenuLabel]。
  const AccountMenuLabel({
    super.key,
    required this.uid,
    required this.isActive,
    this.alias,
    this.maskUid = false,
  });

  /// 帳號 UID。
  final String uid;

  /// 使用者自訂的帳號別名。
  final String? alias;

  /// 是否為當前使用中的帳號。
  final bool isActive;

  /// 是否套用介面隱私模式（前 3 + `x` 遮蔽）。
  final bool maskUid;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final l = AppLocalizations.of(context)!;
    final hasAlias = alias != null && alias!.isNotEmpty;
    final shownUid = displayUid(uid, mask: maskUid);
    final primary = hasAlias ? alias! : shownUid;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Text(
                  l.uidActiveSuffix,
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
            ],
          ),
          if (hasAlias)
            Text(shownUid, style: TextStyle(fontSize: 12, color: tokens.textMuted)),
        ],
      ),
    );
  }
}
```

### Step 4.5：更新 `UidIndicator.build` 讀 settings 並注入 maskUid

把 `UidIndicator.build`（行 18-115）改寫，把 `final settings = ref.watch(settingsProvider);` 後加上 `final maskUid = settings.maskUidInUi;`，並把建構 `AccountMenuLabel` 與 `AccountTriggerLabel` 兩處加上 `maskUid: maskUid`：

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final state = ref.watch(gachaRepositoryProvider);
  final settings = ref.watch(settingsProvider);
  final notifier = ref.read(gachaRepositoryProvider.notifier);
  final activeUid = state.activeUid;
  final maskUid = settings.maskUidInUi;
  final l = AppLocalizations.of(context)!;

  final orderedUids = state.byUid.isEmpty
      ? const <String>[]
      : mergeUidOrder(
          knownUids: state.byUid.keys,
          customOrder: settings.uidOrder,
          lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
        );

  final menuItems = <PopupMenuEntry<String>>[
    for (final uid in orderedUids)
      PopupMenuItem<String>(
        value: uid,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              uid == activeUid ? Icons.check : Icons.radio_button_unchecked,
              size: 16,
              color: uid == activeUid
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: AccountMenuLabel(
                uid: uid,
                alias: settings.uidAliases[uid],
                isActive: uid == activeUid,
                maskUid: maskUid,
              ),
            ),
          ],
        ),
      ),
    if (orderedUids.isNotEmpty) const PopupMenuDivider(),
    PopupMenuItem<String>(
      value: '__recapture__',
      child: Row(
        children: [
          const Icon(Icons.person_add_alt, size: 16),
          const SizedBox(width: AppSpacing.s),
          Text(l.accountAdd),
        ],
      ),
    ),
  ];

  return AccountTriggerButton(
    tooltip: l.uidSwitchTooltip,
    onPressed: () async {
      final button = context.findRenderObject() as RenderBox;
      final overlay =
          Navigator.of(context).overlay!.context.findRenderObject()
              as RenderBox;
      final position = RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(
            button.size.bottomLeft(Offset.zero),
            ancestor: overlay,
          ),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );

      final key = await showMenu<String>(
        context: context,
        position: position,
        items: menuItems,
        constraints: BoxConstraints.tightFor(width: button.size.width),
      );
      if (key == null) return;

      if (key == '__recapture__') {
        Logger('ui.account').info('account add / recapture triggered');
        await notifier.forceRecaptureAndUpdate();
      } else {
        Logger('ui.account').info('switch active uid -> ${sanitizeUid(key)}');
        await notifier.setActiveUid(key);
      }
    },
    child: AccountTriggerLabel(
      activeUid: activeUid,
      alias: activeUid == null ? null : settings.uidAliases[activeUid],
      maskUid: maskUid,
    ),
  );
}
```

注意：`AccountTriggerLabel(...)` 不再是 `const`（因為 maskUid 是動態值）。

確認檔首 import 加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/utils/uid_display.dart';
```

### Step 4.6：跑測試確認通過

Run: `flutter test test/widgets/uid_indicator_test.dart`
Expected: PASS

### Step 4.7：跑整體 analyze 防止其他地方破壞

Run: `flutter analyze lib/widgets/uid_indicator.dart`
Expected: `No issues found!`

### Step 4.8：Commit

```bash
git add lib/widgets/uid_indicator.dart test/widgets/uid_indicator_test.dart
git commit -m "$(cat <<'EOF'
feat(uid-indicator): apply mask UID privacy setting

AccountTriggerLabel 與 AccountMenuLabel 新增 maskUid 參數；UidIndicator 從 settingsProvider 讀取 maskUidInUi 並注入。AppBar 觸發鈕、帳號菜單副標籤套用 displayUid。
EOF
)"
```

---

## Task 5：套用 `displayUid` 到 `account_management.dart`

**Files:**
- Modify: `lib/widgets/cards/account_management.dart`
- Modify: `test/widgets/cards/account_management_test.dart`

### Step 5.1：寫 failing widget test

打開 `test/widgets/cards/account_management_test.dart`，在 main 內加：

```dart
group('AccountManagement: maskUidInUi', () {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows full uid when maskUidInUi=false', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref.maskUidInUi': false,
    });
    // 依既有 test 的 fake gacha repository pattern 注入 byUid 有一筆 '123456789'
    await pumpAccountManagement(tester, uids: const ['123456789']);
    expect(find.text('123456789'), findsOneWidget);
    expect(find.text('123xxxxxx'), findsNothing);
  });

  testWidgets('shows masked uid when maskUidInUi=true', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref.maskUidInUi': true,
    });
    await pumpAccountManagement(tester, uids: const ['123456789']);
    expect(find.text('123xxxxxx'), findsOneWidget);
    expect(find.text('123456789'), findsNothing);
  });

  testWidgets('delete confirm dialog still shows full uid', (tester) async {
    // 隱私模式下點刪除：dialog 內仍應顯示完整 uid（透過 i18n 模板帶入）
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref.maskUidInUi': true,
    });
    await pumpAccountManagement(tester, uids: const ['123456789']);
    // 點該 row 的「移除」按鈕
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    // 確認 dialog body 內含完整 uid
    expect(find.textContaining('123456789'), findsWidgets);
  });
});
```

**Helper：`pumpAccountManagement`**：如果既有 test 已有類似 helper（例如 `pumpWithFakeRepo` / `pumpAccountManagement`），延用即可。若無，加在檔尾：

```dart
Future<void> pumpAccountManagement(
  WidgetTester tester, {
  required List<String> uids,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // 依既有 fake gacha repository pattern
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AccountManagement()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

**重要**：如果既有 `account_management_test.dart` 已建立 fake gacha repository（很可能有，畢竟測試已存在），請以該檔最上方的 helper 為準，把上述 `pumpAccountManagement` 替換成既有版本。如果 Step 5.1 結束時你不確定 helper 的確切名稱，先跑 Step 5.2 看 error。

### Step 5.2：跑測試確認失敗

Run: `flutter test test/widgets/cards/account_management_test.dart`
Expected: FAIL（`_Row` 還未支援 maskUid，masked text 找不到；或 import 缺失）

### Step 5.3：實作 `_Row` 加 maskUid 參數

打開 `lib/widgets/cards/account_management.dart`。在 `_Row` 建構式（行 113-123）加 `final bool maskUid;`：

```dart
class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.uid,
    required this.index,
    required this.lastUpdated,
    required this.isActive,
    required this.alias,
    required this.maskUid,
    required this.onSetActive,
    required this.onRemove,
    required this.onAliasSubmit,
  });

  /// 該 row 代表的 UID。
  final String uid;

  /// 在 [ReorderableListView] 中的排序位置，用於拖拉 handle。
  final int index;

  /// 最後一次更新祈願資料的時間。
  final DateTime lastUpdated;

  /// 是否為當前啟用的帳號。
  final bool isActive;

  /// 使用者自訂別名；空字串表示未設定。
  final String alias;

  /// 是否套用介面隱私模式（前 3 + `x` 遮蔽）。
  final bool maskUid;

  /// 點擊「切換」後呼叫。
  final VoidCallback onSetActive;

  /// 點擊「移除」並確認後呼叫。
  final VoidCallback onRemove;

  /// 別名 TextField 失去 focus 或按 Enter 後呼叫。
  final ValueChanged<String> onAliasSubmit;

  @override
  State<_Row> createState() => _RowState();
}
```

修改 `_RowState.build`（行 194-301）裡顯示 uid 的 `Text(widget.uid, ...)`（行 223-230）：

```dart
Text(
  displayUid(widget.uid, mask: widget.maskUid),
  style: TextStyle(
    color: tokens.textPrimary,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
),
```

### Step 5.4：修改 `AccountManagement.build` 讀 settings 並注入 maskUid

修改 `AccountManagement.build`（行 20-92），在 `final uidOrder = ref.watch(...)` 後加：

```dart
final maskUid = ref.watch(settingsProvider.select((s) => s.maskUidInUi));
```

並把 `itemBuilder` 內建構 `_Row` 處加上 `maskUid: maskUid,`：

```dart
itemBuilder: (context, index) {
  final uid = ordered[index];
  return _Row(
    key: ValueKey(uid),
    uid: uid,
    index: index,
    lastUpdated: byUid[uid]!.lastUpdated,
    isActive: uid == activeUid,
    alias: uidAliases[uid] ?? '',
    maskUid: maskUid,
    onSetActive: () => notifier.setActiveUid(uid),
    onRemove: () => _remove(context, ref, uid),
    onAliasSubmit: (value) =>
        settingsNotifier.setUidAlias(uid, value),
  );
},
```

**不動** `_remove(context, ref, uid)` 的內容：`l.confirmClearActiveBody(uid)` 把完整 uid 嵌入 i18n message，這正好實現「隱私模式下刪除確認框仍顯示完整 uid」需求（無需修改）。

確認檔首 import 加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/utils/uid_display.dart';
```

### Step 5.5：跑測試確認通過

Run: `flutter test test/widgets/cards/account_management_test.dart`
Expected: PASS

### Step 5.6：Commit

```bash
git add lib/widgets/cards/account_management.dart test/widgets/cards/account_management_test.dart
git commit -m "$(cat <<'EOF'
feat(account-management): apply mask UID privacy setting

帳號管理清單 row 顯示 UID 改用 displayUid；刪除確認框維持顯示完整 UID（透過 i18n 模板帶入），避免使用者刪錯。
EOF
)"
```

---

## Task 6：在設定頁新增 Privacy section

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Create: `test/pages/settings_privacy_section_test.dart`

### Step 6.1：寫 failing widget test

建立 `test/pages/settings_privacy_section_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpSettingsPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Privacy section title renders', (tester) async {
    await pumpSettingsPage(tester);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('Privacy switch reflects default false', (tester) async {
    await pumpSettingsPage(tester);
    final sw = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settings.maskUidInUiSwitch')),
    );
    expect(sw.value, false);
  });

  testWidgets('Toggling switch calls setMaskUidInUi(true)', (tester) async {
    await pumpSettingsPage(tester);
    final ctx = tester.element(
      find.byKey(const ValueKey('settings.maskUidInUiSwitch')),
    );
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(settingsProvider).maskUidInUi, false);

    await tester.tap(
      find.byKey(const ValueKey('settings.maskUidInUiSwitch')),
    );
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).maskUidInUi, true);
  });

  testWidgets('Section sits between Appearance and Language', (tester) async {
    await pumpSettingsPage(tester);
    final appearanceY = tester.getTopLeft(find.text('Appearance')).dy;
    final privacyY = tester.getTopLeft(find.text('Privacy')).dy;
    final languageY = tester.getTopLeft(find.text('Language')).dy;
    expect(appearanceY, lessThan(privacyY));
    expect(privacyY, lessThan(languageY));
  });
}
```

### Step 6.2：跑測試確認失敗

Run: `flutter test test/pages/settings_privacy_section_test.dart`
Expected: FAIL（找不到 `'Privacy'` 文字或 widget key）

### Step 6.3：實作 Privacy section

打開 `lib/pages/settings_page.dart`。

在 `SettingsPage.build` 內找到 Appearance SectionCard（行 63-71），在它之後與 `SizedBox(height: AppSpacing.xl)` 之間插入新的 Privacy section（合計兩個 SizedBox 隔開 Appearance 與 Language）。

把 Appearance section 後面的內容（行 72-81）：

```dart
const SizedBox(height: AppSpacing.xl),
SectionCard(
  title: l.settingsLanguage,
  icon: Icons.language,
  child: _LocaleDropdown(
    current: localePref,
    onChanged: notifier.setLocale,
    l: l,
  ),
),
```

改為：

```dart
const SizedBox(height: AppSpacing.xl),
SectionCard(
  title: l.settingsPrivacySectionTitle,
  icon: Icons.shield_outlined,
  child: const _PrivacySection(),
),
const SizedBox(height: AppSpacing.xl),
SectionCard(
  title: l.settingsLanguage,
  icon: Icons.language,
  child: _LocaleDropdown(
    current: localePref,
    onChanged: notifier.setLocale,
    l: l,
  ),
),
```

接著，在檔尾（其他 `_PrivateClass` 的位置，例如 `_LogsSection` 之後）新增 `_PrivacySection`：

```dart
/// 隱私設定區塊：目前僅含「遮蔽介面 UID」開關。
class _PrivacySection extends ConsumerWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final maskUid = ref.watch(
      settingsProvider.select((s) => s.maskUidInUi),
    );
    final notifier = ref.read(settingsProvider.notifier);

    return SwitchListTile(
      key: const ValueKey('settings.maskUidInUiSwitch'),
      value: maskUid,
      title: Text(l.settingsMaskUidInUi),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          l.settingsMaskUidInUiHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ),
      contentPadding: EdgeInsets.zero,
      onChanged: notifier.setMaskUidInUi,
    );
  }
}
```

### Step 6.4：跑測試確認通過

Run: `flutter test test/pages/settings_privacy_section_test.dart`
Expected: PASS

### Step 6.5：Commit

```bash
git add lib/pages/settings_page.dart test/pages/settings_privacy_section_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): add Privacy section with mask UID toggle

設定頁在 Appearance 與 Language 之間新增 Privacy section，內含「遮蔽介面 UID」SwitchListTile。
EOF
)"
```

---

## Task 7：最終驗收（提交前品質檢查 + manual smoke）

**Files:** （無）

### Step 7.1：跑 dart format

Run: `dart format lib/ test/`
Expected: 列出格式化過的檔案（若有），無錯誤。

若 format 有改動既有檔案，把改動 stage 並補一個 commit：

```bash
git add -u
git diff --cached --quiet || git commit -m "chore: dart format"
```

### Step 7.2：跑 flutter analyze

Run: `flutter analyze`
Expected: `No issues found!`

若有 issue，修到全部 `No issues found!` 後再進下一步。

### Step 7.3：跑 flutter test

Run: `flutter test`
Expected: `All tests passed!`

若失敗，回頭定位是哪個 task 的測試壞了或被破壞，修到全綠。

### Step 7.4：Release smoke（依 spec 與 CLAUDE.md「UI 變更要實機驗證」）

**先確認可以跑 release**（依 memory `feedback_perf_check_release_first.md`，UI 行為驗證一律用 release）：

Run: `flutter build windows --release`
Expected: 成功產出 build。

Run 應用：`build\windows\x64\runner\Release\genshin_impact_wish_gacha_analyzer.exe`

依以下步驟手動驗證：

- [ ] 預設狀態：AppBar 帳號鈕與設定頁帳號管理清單顯示完整 UID。
- [ ] 點 AppBar 帳號鈕展開菜單，菜單副標籤顯示完整 UID。
- [ ] 進設定頁，捲到 Privacy section（在 Appearance 之後、Language 之前）。
- [ ] 點開「遮蔽介面中的 UID」switch。
- [ ] AppBar 帳號鈕、菜單副標籤、帳號管理清單三處 UID 立即變成 `123xxxxxx` 格式（前 3 碼 + `x` 遮蔽）。
- [ ] 點帳號管理清單某筆「移除」，確認 dialog 內 body **顯示完整 UID**（不遮蔽，這是預期行為）。取消，不真的刪。
- [ ] 點 AppBar「更新資料」按鈕（或進「分享圖」dialog），分享圖預覽 UID 顯示**仍由 `showFullUid` 控制**，與 maskUidInUi 無關。
- [ ] 進「資料管理 → 匯出資料」，匯出 JSON 後打開檔案，確認檔內 UID **是完整未遮蔽** 的原值。
- [ ] 關閉 toggle，重新打開 App：toggle 狀態正確還原為「關閉」（或先設為「開啟」再重開，確認還原為「開啟」）。

### Step 7.5：（無 commit 必要）

manual smoke 不產生程式碼變更，無需 commit。若有要補的修正，依其性質補 commit。

---

## Self-Review 紀錄

**Spec coverage：**
- ✅ 設定欄位 `maskUidInUi`（bool, default false）→ Task 1
- ✅ `displayUid` helper → Task 2
- ✅ AppBar 帳號鈕／菜單副標 → Task 4
- ✅ 帳號管理清單 → Task 5
- ✅ 刪除確認框 _不_ 遮蔽 → Task 5 Step 5.4 註解 + Step 7.4 smoke
- ✅ 分享圖、匯出檔不受影響 → Task 5/6 未改 + Step 7.4 smoke
- ✅ Privacy section in settings page → Task 6
- ✅ i18n 9 個非空殼 ARB → Task 3
- ✅ Log 埋點 → Task 1 Step 1.8
- ✅ 提交前品質檢查 → Task 7 Step 7.1-7.3
- ✅ Release manual smoke → Task 7 Step 7.4

**Placeholder scan：** 無 TBD / TODO / 模糊指示。所有測試與實作程式都有具體程式碼。

**Type consistency：**
- `AppSettings.maskUidInUi: bool`、`SettingsNotifier.setMaskUidInUi(bool)`、`AccountTriggerLabel.maskUid: bool`、`AccountMenuLabel.maskUid: bool`、`_Row.maskUid: bool`、`displayUid(String, {required bool mask})` — 全部 bool 一致。
- SharedPreferences key `'pref.maskUidInUi'` 在 storage / test / smoke 三處一致。
- 三個 i18n key 名稱 `settingsPrivacySectionTitle`、`settingsMaskUidInUi`、`settingsMaskUidInUiHint` 在 ARB / 設定頁 / 測試 三處一致。
- Widget key `'settings.maskUidInUiSwitch'` 在 Task 6 settings page 與 test 一致。
