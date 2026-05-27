# 設計:zh_Hant 收編為裸 zh,讓中文預設為繁體中文

日期:2026-05-16
分支:flutter-rewrite
狀態:已核准,待寫實作計畫

## 背景與目標

flutter-rewrite 目前中文有三個 ARB:

- `app_zh.arb` — 內容只有 `{"@@locale":"zh"}` 的空 fallback base
- `app_zh_Hant.arb` — 完整繁中內容,且是 `l10n.yaml` 指定的 `template-arb-file`(帶全部 `@key` metadata)
- `app_zh_Hans.arb` — 完整簡中內容

目標:把繁中內容收編到裸 `zh`,刪除 `app_zh_Hant.arb`,讓「未標記的中文 (`zh`)」直接等於繁體中文(此 app 為台灣出身的原神工具,未標記中文 = 繁體是合理預設)。簡中維持 script code `app_zh_Hans.arb`。

非目標:不消除 crowdin 的 1 行 mapping(簡中仍需 `zh-CN → zh_Hans`);不改簡中為地區碼。

前提:app 尚未發布,無既有使用者偏好資料,**不做任何偏好遷移**。

## 元件變更

### 1. ARB 檔案

- `app_zh.arb`:內容整個替換為現 `app_zh_Hant.arb` 的完整內容(所有翻譯 key + 所有 `@key` 描述/placeholder metadata + `localeNativeName: "繁體中文"` + `localeTranslator`),唯一改動是 `@@locale` 由 `"zh_Hant"` → `"zh"`。
- 刪除 `app_zh_Hant.arb`。
- `app_zh_Hans.arb`:不變(`@@locale: zh_Hans`)。

### 2. `l10n.yaml`

- `template-arb-file: app_zh_Hant.arb` → `template-arb-file: app_zh.arb`。模板必須是帶完整 `@` metadata 的那份,現在那份是 `app_zh.arb`。

### 3. `lib/state/localization_metadata.dart`

- gen_l10n 重生後,`AppLocalizations.supportedLocales` = `Locale('zh')`(繁中)+ `Locale.fromSubtags(languageCode:'zh', scriptCode:'Hans')`(簡中)+ `en/es/fr/ja/pt/th/vi`,不再有 `Locale('zh','Hant')`。
- **刪除 `_isBareBaseOfSpecificVariant` 函式及其在 `localeMetadataProvider` 的呼叫點。** 此函式存在的唯一理由是「裸 `zh` 是與 zh_Hant/zh_Hans 重複的空殼,需從語言選單排除」。改動後裸 `zh` 是真正可選的繁中;若不刪,現有邏輯(`zh_Hans` 帶 scriptCode → 視 `zh` 為 bare base)會把繁中整個從語言選單濾掉。目前 ARB 集合無其他語言會觸發它(`pt` 為裸 `pt`,無 `pt_BR`),故刪除為淨簡化,符合 YAGNI。
- `localeListResolution`:`TW/HK/MO` 區域的解析目標由 `Locale.fromSubtags(languageCode:'zh', scriptCode:'Hant')` 改為 `Locale('zh')`。`CN/SG/MY → Locale.fromSubtags(languageCode:'zh', scriptCode:'Hans')` 不變。已帶 scriptCode 的 `zh-Hant-*` 維持回傳 `null`(交給 Flutter `basicLocaleListResolution`;supportedLocales 無 `zh_Hant` 時,Flutter 以 languageCode 比對落到裸 `zh` = 繁中,結果正確)。
- 更新此檔案中以 `zh_Hant` / `zh-Hant` 為例的註解(如 `_isBareBaseOfSpecificVariant` 上方說明、`localeListResolution` 的映射說明),對齊新行為。

### 4. 註解清理

- `lib/services/settings_storage.dart`、`lib/state/settings.dart` 中以 `"zh-Hant"` 當 BCP-47 格式範例的註解,改成仍存在的碼(如 `"zh-Hans"`),避免註解誤導。純文件改動,無邏輯變更。

### 5. 測試(`test/l10n/locale_metadata_test.dart` 及其他引用處)

- `supportedLocales` 斷言:含 `zh`(非 `zh-Hant`)與 `zh-Hans`。
- 移除「排除 bare zh」測試。
- `localeListResolution` 測試:`zh-TW / zh-HK / zh-MO → Locale('zh')`;`zh-CN / zh-SG / zh-MY → Locale(zh, Hans)`;`zh-Hant-TW`(帶 scriptCode)→ `null`。
- `localeTranslator` 空字串測試改用 `Locale('zh')` + `Locale('zh','Hans')`。
- contributors keys 模板測試改用 `Locale('zh')`。
- 實作計畫階段 grep 全 `test/`,把所有 `zh_Hant` / `zh-Hant` 引用一併補齊(含 `locale_provider_test`、`translator_text_test`、settings 相關測試等若有)。
- 不含任何偏好遷移測試。

### 6. `crowdin.yml`

- `source` → `/lib/l10n/app_zh.arb`。
- 保留 `languages_mapping: { two_letters_code: { zh-CN: zh_Hans } }`。`zh-TW` 為源語言,繁中譯文直接寫回 `source` 路徑,不需 mapping。
- Crowdin 後台需將專案源語言設為 **Chinese, Traditional (`zh-TW`)**(網站設定,非 `crowdin.yml`,文件註明即可)。

## 驗證(完成定義)

依 CLAUDE.md「提交前品質檢查」,依序全過才算完成:

1. `dart format lib/ test/`
2. `flutter analyze` → 必須 `No issues found!`
3. `flutter test` → 必須 `All tests passed!`

額外手動驗證:`flutter gen-l10n`(或 build)後確認生成的 `AppLocalizations.supportedLocales` 含 `Locale('zh')` 與 `Locale('zh', 'Hans')`、不含 `zh_Hant`;語言選單能看到「繁體中文」可選項。

## 風險與注意

- gen_l10n 以檔名 + `@@locale` 決定 locale;務必把 `@@locale` 改成 `zh`,否則模板 locale 與檔名不一致。
- `app_zh.arb` 必須承接全部 `@key` metadata(它變成 template),遺漏會導致 gen_l10n 缺描述/placeholder 定義。
- `_isBareBaseOfSpecificVariant` 刪除後,需確認 `localeMetadataProvider` 不再有任何呼叫殘留導致編譯錯誤。

## 文件/版控

依使用者偏好,本 spec 寫於 `docs/superpowers/specs/` 但**不 git add/commit**(`docs/superpowers` 不進版控)。
