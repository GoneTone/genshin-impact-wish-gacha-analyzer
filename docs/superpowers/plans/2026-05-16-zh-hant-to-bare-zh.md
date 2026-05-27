# zh_Hant 收編為裸 zh 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把繁中翻譯內容收編到裸 `zh` ARB、刪除 `app_zh_Hant.arb`,讓未標記中文 (`zh`) 直接等於繁體中文。

**Architecture:** `app_zh.arb` 由空殼變成完整繁中且成為 gen_l10n 模板;`app_zh_Hans.arb` 維持 script code。移除 `_isBareBaseOfSpecificVariant`(裸 `zh` 現在是真語言不再是重複空殼),`localeListResolution` 的 TW/HK/MO 改指向 `Locale('zh')`。crowdin source 改 `app_zh.arb`,保留既有 1 行 `zh-CN → zh_Hans` mapping。

**Tech Stack:** Flutter gen_l10n (ARB)、Riverpod、flutter_test、Crowdin CLI 設定。

**Spec:** `docs/superpowers/specs/2026-05-16-zh-hant-to-bare-zh-design.md`

**重要約束(專案 CLAUDE.md):**
- 每次 `git commit` 前依序 `dart format lib/ test/` → `flutter analyze`(須 `No issues found!`)→ `flutter test`(須 `All tests passed!`),三關全過才 commit。不得 `--no-verify`。
- ARB 移動、metadata 原始碼、測試三者相依,必須在**同一個 commit** 落地才能維持測試全綠(故 Task 1 較大但為原子變更,內部拆成 bite-sized 步驟)。
- 本計畫檔與 spec 位於 `docs/superpowers/`,**不 git add/commit**(不進版控)。各 Task 的 commit 只含 `lib/`、`test/`、`l10n.yaml`、`crowdin.yml`、`lib/l10n/generated/`。
- commit message 結尾加一行:`Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Task 1: 繁中收編裸 zh + metadata 原始碼 + 測試(原子變更)

**Files:**
- Overwrite: `lib/l10n/app_zh.arb`
- Delete: `lib/l10n/app_zh_Hant.arb`
- Modify: `l10n.yaml`
- Regenerate: `lib/l10n/generated/app_localizations.dart`, `lib/l10n/generated/app_localizations_zh.dart`
- Modify: `lib/state/localization_metadata.dart`
- Rewrite test: `test/l10n/locale_metadata_test.dart`
- Modify test: `test/state/locale_provider_test.dart`, `test/services/settings_storage_test.dart`, `test/services/log_service_test.dart`

- [ ] **Step 1: 用繁中內容覆蓋裸 zh ARB**

Run:
```bash
cp lib/l10n/app_zh_Hant.arb lib/l10n/app_zh.arb
```
這會讓 `app_zh.arb` 帶有全部翻譯 key + 全部 `@key` 描述/placeholder metadata + `localeNativeName`/`localeTranslator`。

- [ ] **Step 2: 把 app_zh.arb 的 @@locale 改成 zh**

在 `lib/l10n/app_zh.arb` 第 1 個欄位,將:
```json
  "@@locale": "zh_Hant",
```
改為:
```json
  "@@locale": "zh",
```

- [ ] **Step 3: 刪除 app_zh_Hant.arb**

Run:
```bash
git rm lib/l10n/app_zh_Hant.arb
```

- [ ] **Step 4: l10n.yaml 模板改成 app_zh.arb**

在 `l10n.yaml`,將:
```yaml
template-arb-file: app_zh_Hant.arb
```
改為:
```yaml
template-arb-file: app_zh.arb
```

- [ ] **Step 5: 重新產生 gen_l10n**

Run:
```bash
flutter gen-l10n
```
Expected: 無錯誤輸出。

- [ ] **Step 6: 驗證 supportedLocales 正確**

Run:
```bash
grep -nE "Locale\('zh'\)|scriptCode: 'Han|case 'Han" lib/l10n/generated/app_localizations.dart
```
Expected:`supportedLocales` 含 `Locale('zh')` 與 `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')`,**不含** `scriptCode: 'Hant'`;`lookupAppLocalizations` 的 zh scriptCode switch 只剩 `case 'Hans'`。

- [ ] **Step 7: 改寫 localization_metadata.dart — 移除 bare-base 排除、修 localeListResolution、更新註解**

把 `lib/state/localization_metadata.dart` 第 25–55 行(自 `/// 自動排除 gen_l10n...` 註解段、`localeMetadataProvider`、到 `_isBareBaseOfSpecificVariant` 函式結尾 `}`)整段替換為:

```dart
/// 註:此 provider 的同步性依賴 gen_l10n 對 const 內容回 SynchronousFuture
/// 的實作慣例。若未來 gen_l10n 改變 (例如改 async load asset)，此 provider
/// 內 `result` 會空，需退回 FutureProvider。
///
/// 每個 supported locale 都是可選的真實語言（裸 `zh` = 繁體中文，
/// `zh_Hans` = 簡體中文），不再有重複的空殼 base，故全部納入。
final localeMetadataProvider = Provider<Map<String, LocaleMetadata>>((ref) {
  final all = AppLocalizations.supportedLocales;
  final result = <String, LocaleMetadata>{};
  for (final locale in all) {
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

(這刪掉了 `if (_isBareBaseOfSpecificVariant(locale, all)) continue;` 與整個 `_isBareBaseOfSpecificVariant` 函式。)

- [ ] **Step 8: localeListResolution 的繁中目標改 Locale('zh') 並更新映射註解**

在 `lib/state/localization_metadata.dart`,將映射說明註解:
```dart
/// 映射：CN / SG / MY → `zh-Hans`；TW / HK / MO → `zh-Hant`。
```
改為:
```dart
/// 映射：CN / SG / MY → `zh-Hans`；TW / HK / MO → 裸 `zh`（繁體中文）。
```

並將:
```dart
      final wanted = simplifiedRegions.contains(user.countryCode)
          ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
          : const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
```
改為:
```dart
      final wanted = simplifiedRegions.contains(user.countryCode)
          ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
          : const Locale('zh');
```

- [ ] **Step 9: 全量改寫 test/l10n/locale_metadata_test.dart**

將 `test/l10n/locale_metadata_test.dart` 整檔替換為:

```dart
// test/l10n/locale_metadata_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';

void main() {
  group('AppLocalizations locale metadata', () {
    test('每個 supported locale 都能 load 且 localeNativeName 非空', () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = await AppLocalizations.delegate.load(locale);
        expect(
          l.localeNativeName,
          isNotEmpty,
          reason: '${locale.toLanguageTag()} 的 localeNativeName 不能為空',
        );
      }
    });

    test('裸 zh（繁中）/ zh_Hans 的 localeTranslator 為空字串', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(zh.localeTranslator, isEmpty);

      final hans = await AppLocalizations.delegate.load(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(hans.localeTranslator, isEmpty);
    });

    test('裸 zh localeNativeName = "繁體中文"', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(zh.localeNativeName, '繁體中文');
    });

    test('日文 localeNativeName = "日本語"', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.localeNativeName, '日本語');
    });

    test('葡萄牙文 localeNativeName 含 "Portugu"', () async {
      final pt = await AppLocalizations.delegate.load(const Locale('pt'));
      expect(
        pt.localeNativeName.toLowerCase(),
        contains('portugu'),
        reason: 'pt localeNativeName 看起來不像葡萄牙文',
      );
    });

    test('裸 zh 提供全部 contributors keys（模板必填）', () async {
      final l = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(l.navContributors, isNotEmpty);
      expect(l.contributorsTitle, isNotEmpty);
      expect(l.contributorsSubtitle, isNotEmpty);
      expect(l.contributorsProjectLeader, isNotEmpty);
      expect(l.contributorsTesters, isNotEmpty);
      expect(l.contributorsGithubContributors, isNotEmpty);
      expect(l.contributorsTranslationReviewer, isNotEmpty);
      expect(l.contributorsTranslatedLanguages, isNotEmpty);
      expect(l.contributorsHelpTranslate, isNotEmpty);
      expect(l.contributorsProjectLicense, isNotEmpty);
    });

    test('supportedLocales 包含 zh / zh-Hans / en / ja / pt，且不含 zh-Hant', () {
      final tags = AppLocalizations.supportedLocales
          .map((l) => l.toLanguageTag())
          .toSet();
      expect(tags, contains('zh'));
      expect(tags, contains('zh-Hans'));
      expect(tags, isNot(contains('zh-Hant')));
      expect(tags, contains('en'));
      expect(tags, contains('ja'));
      expect(tags, contains('pt'));
    });
  });

  group('localeMetadataProvider', () {
    test('裸 zh（繁中）與 zh-Hans 都保留，無重複空殼被排除', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final metadata = container.read(localeMetadataProvider);
      final tags = metadata.keys.toSet();

      expect(tags, containsAll(<String>['zh', 'zh-Hans']));
      expect(tags, isNot(contains('zh-Hant')));
      expect(tags, contains('pt'));
      expect(tags, containsAll(<String>['en', 'ja', 'es', 'fr', 'th', 'vi']));
    });

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
  });

  group('localeListResolution', () {
    // 代表性 supportedLocales：裸 zh（繁中）、zh-Hans、單一 pt、其他 bare。
    const supported = <Locale>[
      Locale('en'),
      Locale('es'),
      Locale('fr'),
      Locale('ja'),
      Locale('pt'),
      Locale('th'),
      Locale('vi'),
      Locale('zh'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    ];

    test('zh-CN → zh-Hans（region 大陸映射到簡體）', () {
      final result = localeListResolution([
        const Locale('zh', 'CN'),
      ], supported);
      expect(
        result,
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
    });

    test('zh-SG / zh-MY → zh-Hans', () {
      expect(
        localeListResolution([const Locale('zh', 'SG')], supported),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(
        localeListResolution([const Locale('zh', 'MY')], supported),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
    });

    test('zh-TW / zh-HK / zh-MO → 裸 zh（繁體中文）', () {
      for (final region in ['TW', 'HK', 'MO']) {
        expect(
          localeListResolution([Locale('zh', region)], supported),
          const Locale('zh'),
          reason: 'zh-$region 應映射到裸 zh（繁中）',
        );
      }
    });

    test('zh-Hant-TW (帶 scriptCode) → null，交給 Flutter 預設邏輯', () {
      final result = localeListResolution([
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
      ], supported);
      expect(result, isNull);
    });

    test('en-US (其他語言) → null', () {
      expect(
        localeListResolution([const Locale('en', 'US')], supported),
        isNull,
      );
    });

    test('ja-JP / pt-BR / de-DE (其他語言) → null', () {
      expect(
        localeListResolution([const Locale('ja', 'JP')], supported),
        isNull,
      );
      expect(
        localeListResolution([const Locale('pt', 'BR')], supported),
        isNull,
      );
      expect(
        localeListResolution([const Locale('de', 'DE')], supported),
        isNull,
      );
    });

    test('使用者偏好順序：[en-US, zh-CN] → null（en 先匹配到，尊重順序）', () {
      final result = localeListResolution([
        const Locale('en', 'US'),
        const Locale('zh', 'CN'),
      ], supported);
      expect(result, isNull);
    });

    test('[yue-HK, zh-CN] → zh-Hans (yue 不支援，繼續處理 zh-CN)', () {
      final result = localeListResolution([
        const Locale('yue', 'HK'),
        const Locale('zh', 'CN'),
      ], supported);
      expect(
        result,
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
    });

    test('裸 zh (no script no country) → null', () {
      // 沒有 region 資訊無法判定，交給 Flutter 預設（會 fallback 到裸 zh = 繁中）
      expect(localeListResolution([const Locale('zh')], supported), isNull);
    });

    test('空 / null systemLocales → null', () {
      expect(localeListResolution(null, supported), isNull);
      expect(localeListResolution(const [], supported), isNull);
    });

    test('完全不支援的語言 [ko-KR] → null', () {
      expect(
        localeListResolution([const Locale('ko', 'KR')], supported),
        isNull,
      );
    });
  });

  group('sortedLocaleMetadata', () {
    test('依 nativeName 字典序排列', () {
      final input = <String, LocaleMetadata>{
        'b': const LocaleMetadata(nativeName: 'Banana', translator: ''),
        'a': const LocaleMetadata(nativeName: 'Apple', translator: ''),
        'c': const LocaleMetadata(nativeName: 'Cherry', translator: ''),
      };
      final sorted = sortedLocaleMetadata(input);
      expect(sorted.map((e) => e.value.nativeName), [
        'Apple',
        'Banana',
        'Cherry',
      ]);
    });

    test('空 Map → 空 List', () {
      expect(sortedLocaleMetadata(const {}), isEmpty);
    });
  });
}
```

- [ ] **Step 10: 修正 test/state/locale_provider_test.dart 語意過時的 zh-Hant 範例**

將該檔第 27–36 行的測試:
```dart
  test(
    'LocaleLanguage("zh-Hant") → Locale.fromSubtags(scriptCode: "Hant")',
    () async {
      final c = await makeContainer(const LocaleLanguage('zh-Hant'));
      expect(
        c.read(localeProvider),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    },
  );
```
替換為(改用仍存在的 `zh-Hans`,測同一條 scriptCode 解析路徑):
```dart
  test(
    'LocaleLanguage("zh-Hans") → Locale.fromSubtags(scriptCode: "Hans")',
    () async {
      final c = await makeContainer(const LocaleLanguage('zh-Hans'));
      expect(
        c.read(localeProvider),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
    },
  );
```

- [ ] **Step 11: 修正 test/services/settings_storage_test.dart 語意過時的 zh-Hant**

(a) 第 16–20 行:
```dart
    test('fromCode("zh-Hant") 回傳 LocaleLanguage("zh-Hant")', () {
      final pref = LanguagePreference.fromCode('zh-Hant');
      expect(pref, isA<LocaleLanguage>());
      expect((pref as LocaleLanguage).code, 'zh-Hant');
    });
```
改為:
```dart
    test('fromCode("zh-Hans") 回傳 LocaleLanguage("zh-Hans")', () {
      final pref = LanguagePreference.fromCode('zh-Hans');
      expect(pref, isA<LocaleLanguage>());
      expect((pref as LocaleLanguage).code, 'zh-Hans');
    });
```

(b) 第 27–41 行 roundtrip:把測試名與清單裡的 `'zh-Hant'` 移除(已含 `'zh-Hans'`):
```dart
    test(
      'toCode roundtrip 在 system / zh-Hant / zh-Hans / en / pt-BR / ja 都保持原值',
      () {
        for (final code in [
          'system',
          'zh-Hant',
          'zh-Hans',
          'en',
          'pt-BR',
          'ja',
        ]) {
```
改為:
```dart
    test(
      'toCode roundtrip 在 system / zh-Hans / en / pt-BR / ja 都保持原值',
      () {
        for (final code in [
          'system',
          'zh-Hans',
          'en',
          'pt-BR',
          'ja',
        ]) {
```

(c) 第 48–57 行相等比較:把 `zh-Hant`/`zh-Hans` 配對改為 `zh-Hans`/`en`:
```dart
    test('LocaleLanguage 依 code 相等', () {
      expect(
        const LocaleLanguage('zh-Hant') == const LocaleLanguage('zh-Hant'),
        isTrue,
      );
      expect(
        const LocaleLanguage('zh-Hant') == const LocaleLanguage('zh-Hans'),
        isFalse,
      );
    });
```
改為:
```dart
    test('LocaleLanguage 依 code 相等', () {
      expect(
        const LocaleLanguage('zh-Hans') == const LocaleLanguage('zh-Hans'),
        isTrue,
      );
      expect(
        const LocaleLanguage('zh-Hans') == const LocaleLanguage('en'),
        isFalse,
      );
    });
```

(d) 第 100–104 行「向後相容」測試(app 未發布、無舊資料概念,改成驗證已存碼正常解析):
```dart
    test('舊資料 "zh-Hant" 仍能正確解析（向後相容）', () async {
      SharedPreferences.setMockInitialValues({'pref.locale': 'zh-Hant'});
      final s = await SettingsStorage.load();
      expect(s.locale, const LocaleLanguage('zh-Hant'));
    });
```
改為:
```dart
    test('已存的 pref.locale 字串能正確解析為 LocaleLanguage', () async {
      SharedPreferences.setMockInitialValues({'pref.locale': 'zh-Hans'});
      final s = await SettingsStorage.load();
      expect(s.locale, const LocaleLanguage('zh-Hans'));
    });
```

- [ ] **Step 12: 修正 test/services/log_service_test.dart 的 zh-Hant 範例**

該檔第 136 行 `localeTag: 'zh-Hant',` 改為 `localeTag: 'zh',`;第 142 行:
```dart
    expect(bundle, contains('locale: zh-Hant'));
```
改為:
```dart
    expect(bundle, contains('locale: zh'));
```

- [ ] **Step 13: 三關品質檢查**

Run:
```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected:`flutter analyze` → `No issues found!`;`flutter test` → `All tests passed!`。
若 analyze 報 `_isBareBaseOfSpecificVariant` 未定義/未使用,回 Step 7 確認整個函式與呼叫點都已移除。

- [ ] **Step 14: Commit**

```bash
git add lib/l10n/app_zh.arb l10n.yaml lib/l10n/generated/ lib/state/localization_metadata.dart test/l10n/locale_metadata_test.dart test/state/locale_provider_test.dart test/services/settings_storage_test.dart test/services/log_service_test.dart
git commit -m "$(cat <<'EOF'
i18n(zh): fold zh_Hant into bare zh; default Chinese to Traditional

- app_zh.arb now carries full Traditional content + template metadata
- delete app_zh_Hant.arb; l10n.yaml template -> app_zh.arb
- drop _isBareBaseOfSpecificVariant (bare zh is now a real language)
- localeListResolution: TW/HK/MO -> Locale('zh')
- rewrite locale_metadata_test; fix stale zh-Hant refs in 3 tests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```
注意:`app_zh_Hant.arb` 已於 Step 3 用 `git rm` 標記刪除,會隨此 commit 一併移除。**不要** add `docs/`。

---

## Task 2: 清理 settings_storage.dart / settings.dart 註解範例

**Files:**
- Modify: `lib/services/settings_storage.dart:11,41`
- Modify: `lib/state/settings.dart`(第 124 行附近 `_localeFromCode` doc 註解)

- [ ] **Step 1: settings_storage.dart 註解範例改 zh-Hans**

`lib/services/settings_storage.dart` 第 11 行:
```dart
/// （[LocaleLanguage]，例如 "zh-Hant"、"pt-BR"、"ja"）。
```
改為:
```dart
/// （[LocaleLanguage]，例如 "zh-Hans"、"pt-BR"、"ja"）。
```
第 41 行:
```dart
  /// BCP-47 code，例如 "zh-Hant"、"pt-BR"、"ja"。
```
改為:
```dart
  /// BCP-47 code，例如 "zh-Hans"、"pt-BR"、"ja"。
```

- [ ] **Step 2: settings.dart 的 _localeFromCode doc 註解改用仍存在的碼**

`lib/state/settings.dart` 第 124–131 行附近的 doc 註解,將以 `"zh-Hant"` / `app_zh_Hant.arb` / `Locale('zh', 'Hant')` 為例的敘述,改寫為以 `"zh-Hans"` / `app_zh_Hans.arb` / `Locale('zh', 'Hans')` 為例,語意與行為不變(此函式邏輯不改,僅文件對齊現況)。例如將:
```dart
/// 把 BCP-47 dash-form (e.g. "zh-Hant", "pt-BR", "ja") 轉成 Flutter [Locale]。
```
改為:
```dart
/// 把 BCP-47 dash-form (e.g. "zh-Hans", "pt-BR", "ja") 轉成 Flutter [Locale]。
```
並把同段落內其餘 `Hant` / `app_zh_Hant.arb` 字樣一致改為 `Hans` / `app_zh_Hans.arb`(scriptCode 解析說明照舊適用)。

- [ ] **Step 3: 三關品質檢查**

Run:
```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected:`No issues found!` 與 `All tests passed!`(純註解改動,行為不變)。

- [ ] **Step 4: Commit**

```bash
git add lib/services/settings_storage.dart lib/state/settings.dart
git commit -m "$(cat <<'EOF'
docs(i18n): update locale doc comments from zh-Hant to zh-Hans

zh-Hant is no longer an app-produced code after folding into bare zh;
align example codes in settings doc comments. No behavior change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: crowdin.yml source 指向 app_zh.arb

**Files:**
- Modify: `crowdin.yml`

- [ ] **Step 1: 改 source**

`crowdin.yml` 將:
```yaml
  - source: /lib/l10n/app_zh_Hant.arb
```
改為:
```yaml
  - source: /lib/l10n/app_zh.arb
```
其餘(`translation`、`languages_mapping: two_letters_code: { zh-CN: zh_Hans }`、`commit_message`)維持不變。`zh-TW` 為源語言,直接寫回 source 路徑,不需 mapping。

- [ ] **Step 2: 驗證 yaml 仍合法**

Run:
```bash
grep -nE "source:|translation:|zh-CN" crowdin.yml
```
Expected:`source: /lib/l10n/app_zh.arb`、`translation: /lib/l10n/app_%two_letters_code%.arb`、`zh-CN: zh_Hans` 三者都在。

- [ ] **Step 3: Commit**

```bash
git add crowdin.yml
git commit -m "$(cat <<'EOF'
chore(crowdin): point source to app_zh.arb after zh_Hant fold

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

備註:Crowdin 後台需另將專案源語言設為 Chinese, Traditional (`zh-TW`)——屬網站設定,非本 repo 變更。

---

## Task 4: 最終全量驗證

**Files:** 無(僅驗證)

- [ ] **Step 1: 全量品質閘**

Run:
```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected:`flutter analyze` → `No issues found!`;`flutter test` → `All tests passed!`。

- [ ] **Step 2: 手動行為抽查**

確認 `lib/l10n/generated/app_localizations.dart`:
- `supportedLocales` 含 `Locale('zh')` 與 `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')`
- 不含任何 `scriptCode: 'Hant'`
- `lookupAppLocalizations` 內 `case 'zh'` 的 scriptCode switch 只剩 `case 'Hans'`,其餘 zh 落到 `AppLocalizationsZh()`(= 繁中)

- [ ] **Step 3: 若 dart format 有改動則補 commit**

```bash
git status --porcelain
```
若有格式化造成的改動:
```bash
git add -u
git commit -m "$(cat <<'EOF'
style: apply dart format

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```
否則跳過。

---

## Self-Review

**Spec coverage:**
- 設計 §1 ARB 檔案 → Task 1 Step 1–3 ✓
- 設計 §2 l10n.yaml → Task 1 Step 4 ✓
- 設計 §3 localization_metadata(刪 `_isBareBaseOfSpecificVariant`、localeListResolution、註解)→ Task 1 Step 7–8 ✓
- 設計 §4 註解清理 → Task 2 ✓
- 設計 §5 測試(locale_metadata_test 重寫 + 語意錯的三檔)→ Task 1 Step 9–12 ✓(範圍依使用者決定:純渲染夾具 widget 測試不動)
- 設計 §6 crowdin.yml → Task 3 ✓
- 設計 §7 驗證(三關)→ 每 Task 內含 + Task 4 ✓
- 設計「不做偏好遷移」→ 計畫無任何遷移步驟 ✓

**Placeholder scan:** 無 TBD/TODO;每個改碼步驟皆附完整 old→new 程式碼或精確指令。ARB 內容以 `cp` 指令完整轉移(不需內嵌數百行 ARB)。✓

**Type consistency:** `localeListResolution` / `localeMetadataProvider` / `sortedLocaleMetadata` / `LocaleMetadata` 簽名沿用現有,未更名;測試引用一致。`Locale('zh')` 與 `Locale.fromSubtags(languageCode:'zh', scriptCode:'Hans')` 全計畫用法一致。✓

**已知相依:** Task 1 為原子變更(ARB+原始碼+測試同 commit)以滿足「commit 須三關全綠」的專案閘;Task 2/3 為獨立綠燈 commit。
