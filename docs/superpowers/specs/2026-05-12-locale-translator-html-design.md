# localeTranslator HTML 顯示設計

- 狀態：design approved，待 implementation plan
- 日期：2026-05-12
- 範圍：設定頁 About 區塊的譯者署名

## 背景

`AppLocalizations.localeTranslator` 透過 ARB 檔提供「該語系譯者署名」字串，目前在 `lib/pages/settings_page.dart:193` 以 `Text(translator)` 直接顯示。

日文 ARB 已寫入 HTML：

```
"localeTranslator": "jj、<a href=\"https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX\">世界へいわ</a>"
```

但純 `Text` widget 不會 render HTML，整段 `<a href="...">...</a>` 標籤會原樣顯示，造成譯者的署名連結無法點擊、也很醜。

## 目標

讓 `localeTranslator` 在 About 區塊能：

1. 把 `<a href="...">text</a>` 渲染為可點擊的連結（底線 + primary color）。
2. 點擊連結時用系統預設瀏覽器開啟。
3. 其他語系的純文字 translator 維持原樣顯示。

## 非目標（YAGNI）

- 不支援 `<a>` 以外的 HTML 標籤（`<b>`、`<i>`、`<br>` 等）。
- 不抽成通用 i18n HTML 元件，僅供 About 譯者署名一處使用。
- 不處理 HTML entity（`&amp;` 等）— 目前 ARB 沒有用到。
- 不 mock `url_launcher` 寫端對端點擊測試。

## 方案決策

採用「自己 parse」方案。比較過 `flutter_html`（過重）、`flutter_linkify`（不認 `<a href>` 語法），結論：需求極窄（一個標籤、一個地方），自己 parse 約 30 行；外部套件成本高於價值。`url_launcher` 仍引入，是 Flutter 官方 plugin，不算重複造輪子。

## 檔案變更

| 檔案 | 動作 | 內容 |
|---|---|---|
| `pubspec.yaml` | 新增依賴 | `url_launcher: ^6.3.2` |
| `lib/widgets/translator_text.dart` | 新增 | `TranslatorText` widget + `parseTranslatorMarkup` 純函式 |
| `lib/pages/settings_page.dart` | 改 | `_AboutContent` 把 `Text(translator)` 換成 `TranslatorText(raw: translator, style: ...)` |
| `test/widgets/translator_text_test.dart` | 新增 | parse 函式測試 + widget 渲染測試 |

## 元件設計

### `parseTranslatorMarkup`（純函式，可測）

```dart
@visibleForTesting
List<TranslatorSegment> parseTranslatorMarkup(String raw);

sealed class TranslatorSegment {}
class TextSegment extends TranslatorSegment {
  const TextSegment(this.text);
  final String text;
}
class LinkSegment extends TranslatorSegment {
  const LinkSegment(this.text, this.uri);
  final String text;
  final Uri uri;
}
```

**Parse 規則：**

- 正則 `RegExp(r'<a\s+href="([^"]+)">([^<]+)</a>')`
  - 群組 1 = href URL；群組 2 = 顯示文字。
  - `[^<]+` 排除巢狀標籤（目前 ARB 不會用到，YAGNI）。
- 用 `allMatches` 依索引把字串切成「文字段、連結段、文字段、...」。
- href 必須能 `Uri.tryParse` 成功，**且** scheme ∈ `{http, https}`，否則該段降為 `TextSegment(顯示文字)`，URL 丟棄並 `debugPrint` 警告。
  - 安全考量：擋下萬一日後 ARB 塞入 `javascript:` / `file://` 之類的危險 scheme。
- 標籤未閉合或巢狀 → 不 match → 整段保留為原字串的 `TextSegment`。
- 空字串 → 回傳 `[]`（上層既有 `translator.isNotEmpty` 守衛保證不會進來，但回傳值仍需合理）。

### `TranslatorText` widget

`StatefulWidget`，理由：`TapGestureRecognizer` 必須在 `dispose` 釋放，避免記憶體洩漏。

**Recognizer 生命週期：**

state 持有 `List<TapGestureRecognizer> _recognizers`，在 `initState` / `didUpdateWidget`（`widget.raw` 變更時）先把舊的全部 `dispose` 並清空，再依新的 parse 結果中每個 `LinkSegment` 各建立一個新的 recognizer 並 `add`。`dispose` 時 `dispose` 全部。

之所以用 `List` 而非 `Map<Uri, _>`：同一 raw 字串中若出現兩個相同 URL 的 `<a>`（雖少見），共用同一個 recognizer 在多個 `TextSpan` 之間行為不可靠，依序一一對應比較穩。

**`build()` 流程：**

```dart
final segments = parseTranslatorMarkup(widget.raw);
final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
final linkColor = widget.linkColor ?? Theme.of(context).colorScheme.primary;

var linkIndex = 0;
return Text.rich(TextSpan(children: [
  for (final seg in segments)
    if (seg is TextSegment)
      TextSpan(text: seg.text, style: baseStyle)
    else if (seg is LinkSegment)
      TextSpan(
        text: seg.text,
        style: baseStyle.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
        ),
        recognizer: _recognizers[linkIndex++],
      ),
]));
```

（`_recognizers` 在 build 之前已由 `initState` / `didUpdateWidget` 依 `LinkSegment` 數量備好。為避免 build 時又跑一次 parse，可在 state 額外快取 `_segments`；初版可先讓 build 重 parse，效能影響可忽略。）

### `_open(Uri uri)`

```dart
Future<void> _open(Uri uri) async {
  if (!await canLaunchUrl(uri)) {
    debugPrint('TranslatorText: cannot launch $uri');
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
```

- `LaunchMode.externalApplication` → 強制系統預設瀏覽器，桌面 / 行動皆適用。
- 失敗時靜默 `debugPrint`，不顯示 SnackBar：連結來源是我們審核過的 ARB，例外情境罕見且不影響核心功能。
- 不額外 try/catch `PlatformException`，例外屬程式 bug，讓堆疊噴出便於除錯。

### `_AboutContent` 改動

`lib/pages/settings_page.dart:193` 從：

```dart
Text(
  translator,
  style: Theme.of(context).textTheme.bodySmall,
)
```

改為：

```dart
TranslatorText(
  raw: translator,
  style: Theme.of(context).textTheme.bodySmall,
)
```

其他結構（外層 `Icon` + `Row` + `Expanded`、`translator.isNotEmpty` 守衛）不動。

## 測試計畫

### `test/widgets/translator_text_test.dart`

**Group 1：`parseTranslatorMarkup` 純函式**

| # | 輸入 | 預期 |
|---|---|---|
| 1 | `"Alice, Bob"` | `[TextSegment("Alice, Bob")]` |
| 2 | `'jj、<a href="https://home.gamer.com.tw/...">世界へいわ</a>'`（日文 ARB 實例） | `[TextSegment("jj、"), LinkSegment("世界へいわ", https://...)]` |
| 3 | `'<a href="https://x">A</a> end'`（連結在開頭） | `[LinkSegment, TextSegment(" end")]` |
| 4 | `'<a href="https://a">A</a>、<a href="https://b">B</a>'`（多連結） | `[Link, Text("、"), Link]` |
| 5 | `'<a href="x">未閉合'` | `[TextSegment(原字串)]` |
| 6 | `'<a href="u"><b>x</b></a>'`（巢狀） | `[TextSegment(原字串)]` |
| 7 | `'<a href="javascript:alert(1)">x</a>'` | `[TextSegment("x")]` |
| 8 | `'<a href=":::">x</a>'`（無效 Uri） | `[TextSegment("x")]` |
| 9 | `""` | `[]` |

**Group 2：Widget 渲染（`flutter_test` + `WidgetTester`）**

| # | 內容 |
|---|---|
| 1 | 含連結字串：找到對應 `TextSpan`，斷言 `style.decoration == TextDecoration.underline` 且 color 為 theme primary |
| 2 | 純文字輸入：走訪 `Text.rich` 的 `TextSpan` tree，確認所有 span 的 `recognizer == null` |

**不寫**：點擊真的呼叫 `launchUrl` 的端對端測試。需要把 `launchUrl` 注入可替換，會把 widget API 弄複雜；`_open` 太薄，被測價值低於成本。

### 手動驗證

實機 `flutter run`，切到日文，進設定頁，確認：

- 譯者列「jj、世界へいわ」中「世界へいわ」是底線藍色，可點擊。
- 點擊用系統瀏覽器開啟巴哈姆特連結。
- 切到英文、簡中、繁中等其他語言，譯者列顯示正常（沒看到 HTML 標籤、純文字不可點）。

## 提交前品質檢查（依 CLAUDE.md）

依序執行並全通過後才 commit：

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`
