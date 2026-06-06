# 設定頁「關於」區塊新增「其他遊戲版本」

## 目標

在本專案（原神祈願分析器）設定頁「關於」區塊底部，新增一個「其他遊戲版本」小區塊，指向同作者維護的姊妹專案**鳴潮喚取分析器**（[wuthering-waves-convene-gacha-analyzer](https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer)）。

做法與鳴潮專案**完全對稱**——鳴潮專案已在其「關於」區塊放了一個反向指回本專案的相同區塊，本次即把同一結構鏡像回原神專案。

## 背景：鳴潮專案現行做法（鏡像來源）

鳴潮專案以三個檔案構成此功能：

- `lib/data/related_projects.dart`：`RelatedProjects` 常數類，集中存放姊妹專案 URL。
- `lib/widgets/other_game_versions.dart`：`OtherGameVersion`（資料模型）+ `kOtherGameVersions`（清單常數）+ `OtherGameVersions`（`StatelessWidget`）。
- `lib/pages/settings_page.dart`：在 `_AboutContent` 的 banner 列之後加入 `const OtherGameVersions()`。

視覺結構：上方分隔線 + 小標（次要色、`titleSmall` 加粗）+ 每個遊戲一列（`AppLink` 文字連結 + 固定 `textSecondary` 色的 `open_in_new` 圖示）+ 底部未來說明文字（`bodySmall`、`textMuted`）。**純文字連結，不使用 banner 圖片，無需新增任何 asset。**

資料抽成清單常數 `kOtherGameVersions`，未來新增遊戲只需在清單補一筆 + 對應 ARB key，不必改動 widget 與設定頁。

## 採用方案：完全對稱鏡像

本專案的 `_AboutContent`（`lib/pages/settings_page.dart`）結構與鳴潮一致，故鏡像時只需對應替換「指向的遊戲」即可。所有相依元件（`AppLink`、`theme.gacha.textSecondary`／`textMuted`、`AppSpacing`）本專案皆已具備。

### 變更清單

| 動作 | 檔案 | 內容 |
|---|---|---|
| 新增 | `lib/data/related_projects.dart` | `RelatedProjects` 常數類，含 `wutheringWavesAnalyzer = 'https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer'` |
| 新增 | `lib/widgets/other_game_versions.dart` | `OtherGameVersion` 模型 + top-level `_wutheringWavesLabel` resolver + `kOtherGameVersions`（目前一筆：鳴潮）+ `OtherGameVersions` widget |
| 修改 | `lib/pages/settings_page.dart` | import 新 widget；在 `_AboutContent` build 的 banner `Wrap`（現行第 321–339 行）之後加上 `const OtherGameVersions()` |
| 新增 ARB key | 9 個非空殼 ARB | 見下方「i18n」 |

### 新增元件骨架（對齊鳴潮）

```dart
// lib/data/related_projects.dart
class RelatedProjects {
  const RelatedProjects._();

  /// 鳴潮喚取分析器專案 GitHub 頁面。
  static const String wutheringWavesAnalyzer =
      'https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer';
}
```

```dart
// lib/widgets/other_game_versions.dart（結構鏡像鳴潮）
class OtherGameVersion {
  const OtherGameVersion({required this.label, required this.url});
  final String Function(AppLocalizations l) label;
  final String url;
}

String _wutheringWavesLabel(AppLocalizations l) =>
    l.settingsOtherGamesWutheringWaves;

const List<OtherGameVersion> kOtherGameVersions = [
  OtherGameVersion(
    label: _wutheringWavesLabel,
    url: RelatedProjects.wutheringWavesAnalyzer,
  ),
];

class OtherGameVersions extends StatelessWidget {
  const OtherGameVersions({super.key});
  // Column：分隔線 + 小標 + 每遊戲一列（AppLink + open_in_new）+ 未來說明
}
```

`open_in_new` 圖示刻意放在 `AppLink` 之外、固定 `textSecondary` 色：`AppLink` 的 hover 僅透過 `DefaultTextStyle` 染文字、不影響 `Icon`（`Icon` 取 `IconTheme`），放進去顏色會對不上；此圖示僅作「會開外部瀏覽器」提示，不需隨 hover 變色。

## i18n

新增 3 個 key，沿用鳴潮的 `settingsOtherGames*` 命名，遊戲項改為鳴潮：

- `settingsOtherGamesTitle`：區塊小標。
- `settingsOtherGamesWutheringWaves`：遊戲名。
- `settingsOtherGamesFuture`：未來說明。

### 範圍：只加在「非空殼」ARB（共 9 個）

本專案有 31 個 ARB，分兩層：實心檔（數百個真實翻譯）與空殼檔（僅 2 個 Crowdin 託管字串，其餘交由 Crowdin pipeline 回填）。**新 key 只加在實心檔，空殼檔不碰**（與本專案既有 i18n 慣例一致）。

實心檔（需加 key）：`app_zh.arb`（模板，繁中）、`app_zh_Hans.arb`（簡中）、`app_en.arb`、`app_es.arb`、`app_fr.arb`、`app_ja.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`。

空殼檔（**不**加，留給 Crowdin）：af、ar、ca、cs、da、de、el、fi、he、hu、it、ko、nl、no、pl、pt、ro、ru、sr、sv、tr、uk。

模板 `app_zh.arb` 的 `@` metadata 為選擇性（既有 `settingsAbout` 即無 metadata），鳴潮亦未替這三個 key 加 metadata，故本次**不加 `@` metadata**，維持對稱與簡潔。

### 翻譯字串

遊戲名規則：CJK 用官方在地化名稱；其餘語系沒有把握的在地化名稱一律保留英文「Wuthering Waves」。

| key \ 語系 | settingsOtherGamesTitle | settingsOtherGamesWutheringWaves | settingsOtherGamesFuture |
|---|---|---|---|
| zh（繁中） | 其他遊戲版本 | 鳴潮 | 未來可能新增更多遊戲... |
| zh_Hans（簡中） | 其他游戏版本 | 鸣潮 | 未来可能新增更多游戏... |
| en | Versions for Other Games | Wuthering Waves | More games may be supported in the future... |
| es | Versiones para otros juegos | Wuthering Waves | Es posible que se añadan más juegos en el futuro... |
| fr | Versions pour d'autres jeux | Wuthering Waves | D'autres jeux pourraient être pris en charge à l'avenir... |
| ja | 他のゲーム向けバージョン | 鳴潮 | 今後、対応ゲームが増える可能性があります... |
| pt_BR | Versões para outros jogos | Wuthering Waves | Mais jogos poderão ser adicionados no futuro... |
| th | เวอร์ชันสำหรับเกมอื่น ๆ | Wuthering Waves | อาจมีการรองรับเกมเพิ่มเติมในอนาคต... |
| vi | Phiên bản cho các trò chơi khác | Wuthering Waves | Có thể sẽ hỗ trợ thêm trò chơi trong tương lai... |

**標點**：`settingsOtherGamesFuture` 結尾省略號**一律使用半形 `...`**（含 CJK 語系），此為本功能字串的固定做法，不套用 CLAUDE.md「CJK 用全形」通則。

## 不採用的方案

- **內聯硬寫**：不抽 `RelatedProjects` 與 `kOtherGameVersions`，直接在 `_AboutContent` 寫死一條鳴潮連結。程式更少，但與姊妹專案結構不對稱，違背「做法一樣」的要求。
- **URL 塞進現有 `AppRepo`**：語意不符（`AppRepo` 是「本專案座標」），且偏離鳴潮結構。

> 單一項目卻抽清單乍看略有 over-engineering，但這是姊妹專案既有的對稱結構、量極小，且使用者明確要求對齊，故仍採鏡像方案。

## 驗收條件

- `fvm flutter gen-l10n` 產碼成功（新 key 進入 `AppLocalizations`）。
- `fvm dart format lib/ test/` 無待格式化變更。
- `fvm flutter analyze` 輸出 `No issues found!`。
- `fvm flutter test` 輸出 `All tests passed!`。
- 設定頁「關於」區塊底部出現「其他遊戲版本」小標與「鳴潮」可點連結，點擊以系統瀏覽器開啟鳴潮專案 GitHub 頁面；連結右側有 `open_in_new` 圖示，底部有未來說明文字。
