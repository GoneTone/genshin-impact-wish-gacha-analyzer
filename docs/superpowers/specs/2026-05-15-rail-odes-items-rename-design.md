# 側選單頌願區塊項目重新命名 — 與祈願風格統一

## 背景

側選單 (`lib/pages/app_shell.dart` 的 `_Rail`) 分成兩個 section：

- **祈願 (Wish)**：項目為純修飾語（角色 / 武器 / 集錄 / 常駐 / 新手）
- **頌願 (Odes)**：項目卻多帶「頌願」字尾（活動頌願 / 常駐頌願）

風格不一致，且 section header 本身已標示「頌願」，項目再帶尾綴是冗餘。

## 目標

頌願 section 內的兩個項目改為純修飾語，與祈願 section 對齊。section header 與 `gachaType*`（卡池正式名稱，用於頁面標題等）維持不動。

## 變更內容

只動 i18n arb 檔的字面值，程式碼不需要改動。

### `lib/l10n/app_zh_Hant.arb`

| key | 舊值 | 新值 |
|---|---|---|
| navOdesEvent | 活動頌願 | 活動 |
| navOdesStandard | 常駐頌願 | 常駐 |

### `lib/l10n/app_zh_Hans.arb`

| key | 舊值 | 新值 |
|---|---|---|
| navOdesEvent | 活动颂愿 | 活动 |
| navOdesStandard | 常驻颂愿 | 常驻 |

### `lib/l10n/app_en.arb`

| key | 舊值 | 新值 |
|---|---|---|
| navOdesEvent | Event Odes | Event |
| navOdesStandard | Standard Odes | Standard |

其他語言檔 (`ja / fr / es / pt / th / vi / zh / en`) 未翻譯或 `navOdes*` 字串為 fallback 候選；本專案 `l10n.yaml` 將 `app_zh_Hant.arb` 設為模板 (`template-arb-file: app_zh_Hant.arb`)，缺失 key 由模板填補，所以這些語言畫面會自動跟著 zh_Hant 的新值走。為了維持語意一致，本次仍主動把 `app_en.arb` 對應兩個 key 一起改成新英文版本（避免英文使用者顯示繁中字）。

## 不在範圍內

- **`navSectionWish` / `navSectionOdes`**（section header）保留「祈願 / 頌願」，這是使用者明確指定的風格基準。
- **`gachaTypeOdesEvent` / `gachaTypeOdesStandard`**（卡池正式名稱，出現在頁面標題、tooltip 等位置）保留「活動頌願 / 常駐頌願」。
- 程式碼結構：`_railLabel` switch（`app_shell.dart:479-488`）、icon 對應、_Rail 佈局通通不動。

## 已知取捨

**「常駐」碰撞**：頌願 section 的 `navOdesStandard = 常駐` 會與祈願 section 的 `navStandard = 常駐` 同名（英文 `Standard` 也一樣）。

緩解方式：

1. 兩個項目分別位於不同 section，中間有 `_SectionLabel` 的分隔線
2. icon 不同：祈願「常駐」用 `Icons.history`，頌願「常駐」用 `Icons.auto_awesome_motion`
3. collapsed-no-label 模式（`width < 800`）下 label 不顯示，只看 icon

實務上可接受。若日後使用者覺得混淆，再考慮改用獨特修飾語（如「經典 / Classic」）。

## 影響範圍

- 直接消費這兩個 i18n key 的位置：只有 `lib/pages/app_shell.dart:485-486`
- 測試：grep 顯示沒有測試直接斷言這兩個字串
- 自動生成檔 (`lib/l10n/generated/`)：執行 `flutter pub get` 或 `flutter gen-l10n` 會由 arb 重新生成

## 驗收標準

1. 啟動 app，繁中 / 簡中 / 英文三種語系下：
    - 側選單祈願 section 仍為「角色 / 武器 / 集錄 / 常駐 / 新手」
    - 側選單頌願 section 顯示「活動 / 常駐」（或對應簡中、英文）
    - section header「祈願 / 頌願」維持不變
2. 點選頌願 section 內項目仍能正確導航到對應卡池頁面
3. 頁面標題等使用 `gachaTypeOdes*` 的位置仍顯示完整名稱「活動頌願 / 常駐頌願」
4. 通過 `dart format lib/ test/` / `flutter analyze` / `flutter test`
