# Footer 團隊資訊與社群連結 — Design Spec

- 日期：2026-05-13
- Branch：`flutter-rewrite`
- 主題：在 `AppShell` 底部「最後更新」列右側補上團隊資訊（Facebook / Discord / Line / GitHub icon + 團隊名稱與網站連結），對齊舊版 (master) topbar 的呈現。

## 1. 目標與動機

舊版本（master，Vue/Electron）的 topbar 右側放有：
- Facebook / Discord / Line / GitHub 四個 icon 連結
- 一條分隔線
- 團隊名稱「原神資訊站 Genshin Impact Info」連到團隊網站

Flutter 改寫版尚未把這塊搬過來。底部 footer 目前只有左側「最後更新 / 尚未同步」文字。本次設計：

- 將上述五個外部連結搬到 footer 列右側
- 不改動 AppBar，避免擠到既有的 UID 與「更新」按鈕
- 保留底部 footer 文字置左，icon 與團隊名稱置右

## 2. 範圍

In scope：
- 新增 `lib/data/team_info.dart` 常數檔
- 新增 `lib/widgets/team_links_bar.dart` 元件
- 修改 `lib/pages/app_shell.dart` 的 footer Container
- 在 `pubspec.yaml` 加入 `font_awesome_flutter` 套件
- 對應單元測試

Out of scope（不做）：
- 不變更 AppBar
- 不調整既有 footer 樣式（顏色、padding、字級）以外的視覺
- 不新增 ARB l10n 字串（tooltip 用品牌名稱本字，跨語系一致）

## 3. 設定常數

新檔 `lib/data/team_info.dart`：

```dart
class TeamInfo {
  const TeamInfo._();

  static const String name = '原神資訊站 Genshin Impact Info';
  static const String websiteUrl = 'https://genshininfo.reh.tw/';
  static const String facebookUrl = 'https://genshininfo.reh.tw/facebook';
  static const String discordUrl = 'https://genshininfo.reh.tw/discord';
  static const String lineUrl = 'https://genshininfo.reh.tw/line';
}

const String appGithubUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer';
```

設計取捨：
- 採與 `lib/data/contributors.dart` 相同的 dart 常數風格。沒有跨環境差異，不用 dart-define 或 .env。
- `appGithubUrl` 不放入 `TeamInfo`，因為它屬於專案本體而非團隊（對齊 master 把它放在 `configs.app.githubUrl` 而非 `configs.team`）。
- `licenseUrl`、`githubContributorsUrl` 已存在於 `contributors.dart`，不重複。

## 4. 元件設計：`TeamLinksBar`

新檔 `lib/widgets/team_links_bar.dart`，無狀態 widget。

```
[fb]  [dc]  [line]  [gh]  │  原神資訊站 Genshin Impact Info ↗
```

結構：
```dart
Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    _IconLink(icon: FontAwesomeIcons.facebookF, tooltip: 'Facebook', url: TeamInfo.facebookUrl),
    _IconLink(icon: FontAwesomeIcons.discord,   tooltip: 'Discord',  url: TeamInfo.discordUrl),
    _IconLink(icon: FontAwesomeIcons.line,      tooltip: 'Line',     url: TeamInfo.lineUrl),
    _IconLink(icon: FontAwesomeIcons.github,    tooltip: 'GitHub',   url: appGithubUrl),
    const SizedBox(width: AppSpacing.xs),
    const _Divider(),
    const SizedBox(width: AppSpacing.s),
    AppLink(
      url: TeamInfo.websiteUrl,
      child: Text(TeamInfo.name, style: Theme.of(context).textTheme.bodySmall),
    ),
  ],
)
```

`_IconLink`：以 `IconButton` 包 `FaIcon`，使用 `IconButton` 內建 `tooltip`、`onPressed` 呼叫 `openExternalUrl()`（既有於 `lib/widgets/app_link.dart`）。視覺：
- `iconSize`: 16
- `visualDensity`: `VisualDensity.compact`
- `padding`: `EdgeInsets.symmetric(horizontal: AppSpacing.xs)`
- `constraints`: 緊縮（`BoxConstraints(minWidth: 32, minHeight: 32)`），避免 footer 高度被撐大
- 色：未 hover 用 `tokens.textSecondary`，hover 由 `IconButton` `overlayColor` 自動處理

`_Divider`：一條 16dp 高的薄垂直線，色用 `tokens.borderSubtle`（對齊既有 `_BottomRailButton` 的 border 色源）。

## 5. `AppShell` 修改

`lib/pages/app_shell.dart:116-133` 的 Container：

修改前：
```dart
child: Text(
  activeData == null ? ... : ...,
  style: Theme.of(context).textTheme.bodySmall,
),
```

修改後：
```dart
child: Row(
  children: [
    Expanded(
      child: Text(
        activeData == null ? ... : ...,
        style: Theme.of(context).textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    const SizedBox(width: AppSpacing.s),
    const TeamLinksBar(),
  ],
),
```

要點：
- `Expanded` 包左側文字，視窗變窄時文字 ellipsis，icon 永遠可見可點。
- 維持原本的 `padding` / `color`（`tokens.surfaceCardHigh`）。
- 為避免 IconButton 預設高度撐大 footer，第 4 節 `_IconLink` 直接套用 `visualDensity: VisualDensity.compact` + `iconSize: 16`，由元件自身保證 footer 高度與既有設計一致。

## 6. 依賴與資源

`pubspec.yaml`：
- 新增 `font_awesome_flutter: ^10.7.0`（撰寫時最新穩定版；實作時鎖到 `flutter pub add` 給出的版本即可）

不新增 asset；不新增 ARB key。

## 7. 測試

新檔 `test/widgets/team_links_bar_test.dart`，採與既有 `test/widgets/app_link_test.dart` 相同的「不 mock url_launcher」務實風格：
- 渲染 `TeamLinksBar`，驗證：
  - 出現 4 個 `IconButton`，tooltip 分別為 `Facebook` / `Discord` / `Line` / `GitHub`
  - 出現團隊名稱文字
  - 4 個 `IconButton.onPressed` 都不為 null（代表 callback 連上）
  - `TeamInfo.name` 那段被 `AppLink` 包住、URL 等於 `TeamInfo.websiteUrl`
- 點擊任一 icon / 團隊名稱：呼叫 `tester.tap()` 並 `pumpAndSettle()`，斷言不拋例外（測試環境下 `canLaunchUrl` 回 false，會 `debugPrint` 後 return — 行為與 `AppLink` 一致）。

不新增 app_shell-level 測試（覆蓋面太大且需 mock provider）。

提交前 quality gate 依 CLAUDE.md：
1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`

## 8. Edge cases

- **視窗窄**：左側文字 `Expanded` + `ellipsis`，icon 永遠在右側可見。
- **未同步**：左側顯示 `footerNotSynced`，右側照常顯示連結。
- **無網路 / 連結失敗**：`openExternalUrl()` 內部 `canLaunchUrl()` 失敗時 `debugPrint`，使用者體感為點擊無反應，與現有 `AppLink` 行為一致，不另外吐 SnackBar。

## 9. 風險與權衡

- 新增套件 `font_awesome_flutter` 會增加 app 體積（~1.5MB icon font）。CLAUDE.md 允許「需要時引入套件」，且 master 即用 FontAwesome 同源 icon，視覺一致性最高，採此方案。
- Tooltip 不走 ARB：品牌名稱本身是全球通用標識，符合 YAGNI。

## 10. 完成定義（DoD）

- 4 個社群 icon + 團隊名稱出現在 footer 右側
- 點擊各 icon 開啟對應外部 URL（驗證手段：實機點擊或 test mock）
- footer 整體 layout 在 800px / 1180px / 1400px 寬度下不破版
- format / analyze / test 全綠
