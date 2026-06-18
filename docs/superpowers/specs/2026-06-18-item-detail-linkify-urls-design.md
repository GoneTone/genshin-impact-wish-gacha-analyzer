# 物品詳情純文字網址自動連結化 — 設計

## 背景與問題

物品詳情 dialog（`lib/widgets/dialogs/gacha_item_detail_dialog.dart`）有兩處用 `flutter_html` 的 `Html` 渲染 HoYoWiki 內容：

1. **標題區的 `desc`** — 詞條說明（資料層註解標明「可能為純文字或含 HTML」）。
2. **圖片區的 `current.descHtml`** — gallery 圖片說明 HTML。

目前兩處 `Html` 都沒有傳 `onLinkTap`，因此：

- 內容中的**純文字網址**（例如 `詳見 https://example.com`）只會以純文字呈現，無法點擊前往。
- 即使內容本來就含 `<a href>`，因為沒有 `onLinkTap`，一樣點不動。

需求：物品詳情內的純文字網址要自動變成可點擊前往；既有 `<a href>` 連結也應一併可點，避免「這個 URL 可點、那個不可點」的不一致。

## 目標與範圍

- **偵測範圍（保守）**：只比對 `http://` 與 `https://` 開頭的完整網址。不處理 `www.` 前綴與裸網域（`foo.com`），以杜絕把版本號（`版本 2.0`）、檔名、含點英文縮寫誤判成網址。
- **既有 `<a href>` 一併可點**：裸 URL 與既有 `<a>` 透過同一 `onLinkTap` 開啟外部瀏覽器，體驗一致。
- **行內連結風格對齊現有應用程式**：採靜態 primary 連結色（與 `release_notes_content.dart` 的 markdown 行內連結一致），**不做** per-link hover 重新著色。
- **適用兩處**：標題區 `desc` 與圖片區 `descHtml` 皆涵蓋。

### 不做（YAGNI）

- 不支援 `www.` 前綴與裸網域。
- 不做行內連結 hover 變色（流動文字裡的行內連結，現行 app 即為靜態 primary 色；要做 hover 需 `TagExtension.inline` + 自訂 inline 元件，較複雜且 `WidgetSpan` 在 rich text 中無法換行、長 URL 會溢出，超出需求）。
- 不把 `AppHtml` 套用到物品詳情以外的既有 `Html` 用途（其他有需要再說）。

## 既有資產與風格基準

- `lib/widgets/app_link.dart`：`openExternalUrl(Uri)` 已統一以系統瀏覽器開啟連結並在失敗時 `warning`；`AppLink._handleTap` 內含 `Uri.tryParse` + 無效時 `warning` 的樣板。
- `lib/utils/github_release_linkify.dart`：既有 linkify 工具（純字串轉換、無副作用、放 `lib/utils/`）— 作為新工具的擺放位置與 dartdoc 風格基準。注意它針對 **Markdown** 做 raw-regex 改寫；HTML 情境的差異見下節。
- `lib/widgets/dialogs/release_notes_content.dart`：既有**行內連結風格的權威基準** — `LinkConfig(style: TextStyle(color: linkBaseColor(theme)))`，靜態 primary 色、無 hover。
- `linkBaseColor(theme)`（`app_link.dart`）：全應用統一連結色（`colorScheme.primary`）。

## 取向決策

採 **HTML parser 走訪文字節點做 linkify**，而非對原始字串跑 regex。

原因：內容是「純文字或含 HTML 混雜」。對 HTML raw-string 跑 regex 難以安全避開兩種情境——(1) URL 出現在既有 `href="…"` 屬性值內、(2) URL 出現在既有 `<a>…</a>` 連結文字內（linkify 會造出非法的巢狀 `<a>`）。用 parser 只走訪「非 `<a>` 子孫的 text node」可從結構上乾淨避開兩者。此分歧於 `github_release_linkify.dart`（Markdown，靠 `(?<![(<])` lookbehind 防重複包裝）是刻意的：HTML 需要結構感知，raw-regex 無法安全提供。

`html` 套件目前已是 `flutter_html` 的傳遞依賴，將其**提升為顯式依賴**（pubspec 一行）後直接使用其 DOM parser。

## 架構與元件

### 1. `lib/utils/html_linkify.dart` — 純函式 `linkifyHtml`

```
String linkifyHtml(String html)
```

- 用 `html` 套件 `parseFragment(html)` 解析成 DOM 片段。
- 遞迴走訪節點；遇到 `<a>` 元素則**整棵子樹略過**（其內文字不再 linkify，避免巢狀 `<a>`）。
- 對其餘 text node：以 regex `https?://[^\s<]+` 找出裸 URL，**剝除尾端標點**後，將 URL 段替換為 `<a href="URL">URL</a>` 元素，URL 前後文字保留為 text node。
  - 尾端標點剝除集合涵蓋半形 `. , ; : ! ? ) ] }` 與全形 `。 ， ！ ？ ； ： ） 」 』 】`，避免「…網站 https://foo.com。」把句號吃進連結。
- 序列化回字串（`fragment.outerHtml` 之類），回傳。
- **fail-safe**：整段包 `try/catch`；解析或序列化意外失敗時回傳**原字串**（最壞情況裸 URL 維持純文字，絕不讓描述區渲染中斷），並 `Logger('ui.linkify').warning(...)` 帶上脫敏後的長度／前綴等 context（不寫入完整內容）。
- 純函式、無副作用，可獨立單元測試。

### 2. `lib/widgets/app_html.dart` — 共用 `AppHtml`

```
AppHtml({required String data, Map<String, Style> style = const {}})
```

- 內部渲染 `Html(data: linkifyHtml(data), onLinkTap: …, style: {…})`。
- `style` 合併：先放預設 `'a'` 樣式，再展開呼叫端傳入的 `style`（呼叫端可覆蓋，但通常只覆蓋 `body`／`p`）。
  - 預設 `'a'`：`Style(color: linkBaseColor(theme), textDecoration: TextDecoration.underline)`（靜態 primary 色 + 底線作點擊提示；對齊既有行內連結風格）。
- `onLinkTap: (url, _, __) => openExternalUrlString(url)`（`OnTap` 簽名為 `void Function(String? url, Map<String,String> attributes, html.Element? element)`）。
- 手型游標由 flutter_html 對可點 `<a>` 預設提供；實作時驗證，若預設未提供再於 `'a'` 樣式補強。

### 3. `lib/widgets/app_link.dart` — 抽出共用開連結 helper

```
Future<void> openExternalUrlString(String? url)
```

- `url` 為 null 或 `Uri.tryParse` 失敗 → `Logger('ui.link').warning(...)` 後靜默返回。
- 有效 → 呼叫既有 `openExternalUrl(uri)`。
- 重構 `AppLink._handleTap` 改為呼叫此 helper，消除重複的 `tryParse` + `warning` 樣板；`AppHtml.onLinkTap` 亦呼叫之。符合「抽出共用、別造輪子」。

## 資料流與接點

物品詳情 dialog 兩處 `Html(...)` 改為 `AppHtml(...)`，沿用各自原本的 `body`／`p` 樣式：

- **標題區 `desc`**：保留外層 `DefaultTextStyle.merge(height: 1.0)` 與既有 `body`（fontSize、lineHeight 1.2、textSecondary 色、margin/padding 歸零）、`p`（margin 歸零）樣式，僅把 `Html` 換成 `AppHtml`。
- **圖片區 `descHtml`**：保留既有 `body`（margin/padding 歸零）、`p`（上下 4px margin）樣式，`Html` 換成 `AppHtml`。

兩處不再各自寫 `Html`，`onLinkTap` 與連結色集中於 `AppHtml`，杜絕不一致。

## 錯誤處理

| 情境 | 行為 |
| --- | --- |
| `linkifyHtml` 解析／序列化意外失敗 | 回傳原字串 + `warning`，渲染不中斷 |
| `onLinkTap` 收到 null 或無法解析的 URL | `openExternalUrlString` `tryParse` 失敗 → `warning`，不崩 |
| `canLaunchUrl` 回 false（無可用處理程式） | 沿用 `openExternalUrl` 既有 `warning` |

## 測試

### `test/utils/html_linkify_test.dart`（單元，重點）

- 單一 `https://` URL（純文字）→ 包成 `<a href>`。
- `http://` 亦中；`ftp://`、`www.foo.com`、裸網域 `foo.com` **不中**（驗證保守範圍）。
- 尾端半形標點（`https://foo.com.`）與全形標點（`https://foo.com。`）**不吃進連結**。
- 既有 `<a href="…">…</a>` **不被改、不雙重包覆、不產生巢狀 `<a>`**。
- URL 出現在屬性值內（如 `<img src="https://…">`）**不被當文字 linkify**。
- 同一段含多個 URL → 全部各自包成連結。
- 無 URL 的純文字 → 語意不變。
- 空字串 → 不崩、回空。

### `test/widgets/app_html_test.dart`（widget）

- 含裸 URL 的 `data` → render 出對應 anchor。
- 點擊連結 → 觸發外部開啟（以 `url_launcher` 平台 mock 驗證 launch 被呼叫，沿用專案既有 mock 方式）。
- 既有 dialog 測試（`gacha_item_detail_dialog_test.dart` 等）維持綠燈，確認無回歸。

## 提交前品質檢查

依 `CLAUDE.md`：`fvm dart format lib/ test/` → `fvm flutter analyze`（須 `No issues found!`）→ `fvm flutter test`（須 `All tests passed!`）。
