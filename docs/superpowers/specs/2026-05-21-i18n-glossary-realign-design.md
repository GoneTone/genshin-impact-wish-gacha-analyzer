# 依 docs/術語表.md 重新對齊翻譯：設計

- 日期：2026-05-21
- 分支：flutter-rewrite（直接 push，不開 PR）
- 狀態：設計已確認（使用者 2026-05-21），待寫實作計畫

## 背景

使用者手動改寫了 `docs/術語表.md`（本地、不進版控），調整了原神祈願/頌願分類的各語系譯名，並把先前 SKIP 的頌願（Odes）系列補上譯名。本任務依此 glossary 重新對齊 7 個語系的 `.arb`。

## 目標

把 en / ja / es / fr / pt / th / vi 七個語系的祈願/頌願分類與相關術語對齊 `docs/術語表.md`，並補齊 es/fr/pt/th/vi 原本 SKIP 的頌願 key，使五語系達到 208/208 全對齊。

- `app_zh.arb`（template）、`app_zh_Hans.arb` **不動**（glossary 這兩欄與現值一致）。

## 已確認決策

1. **en/ja 也套用** glossary 變更（覆蓋先前已 commit 的官方遊戲譯名）。
2. **連動 key 全部更新**（nav 短標籤、頌願 nav/綜合頁/空狀態、內文祈願/頌願提及）以保持術語一致。
3. **pt `navSectionGacha` = `Orar`**（照 glossary 原樣，動詞形）。
4. `docs/術語表.md` **不 commit**（維持本地參考）。
5. 執行方式：**逐語系 subagent + spec/quality 雙階段 review**，逐語系一個 commit。

## glossary 鎖定術語（直接 key）

| key | en | ja | es | fr | pt | th | vi |
|---|---|---|---|---|---|---|---|
| `navSectionGacha` (祈願) | Wish | 祈願 | Gachapón | Vœux | Orar | การอธิษฐาน | Cầu Nguyện |
| `navSectionOdes` (頌願) | Odes | 星願 | Odas | Odes | Odes | ภาวนา | Ca Tụng |
| `gachaTypeCharacter` | Character Event Wish | イベント祈願・キャラクター | Gachapón promocional de personaje | Vœux événements de personnage | Oração de Evento de Personagem | กิจกรรมอธิษฐานตัวละคร | Cầu Nguyện Nhân Vật |
| `gachaTypeWeapon` | Weapon Event Wish | イベント祈願・武器 | Gachapón promocional de arma | Vœux événements d'armes | Oração de Evento de Arma | กิจกรรมอธิษฐานอาวุธ | Cầu Nguyện Vũ Khí |
| `gachaTypeChronicled` | Chronicled Wish | 集録祈願 | Gachapón recopilatorio | Vœux nostalgie | Registro de Oração | การอธิษฐานรวมปรารถนา | Sử Ký Cầu Nguyện |
| `gachaTypeStandard` | Standard Wish | 通常祈願 | Gachapón permanente | Vœux permanents | Oração Comum | อธิษฐานถาวร | Cầu Nguyện Thường |
| `gachaTypeBeginner` | Novice Wishes | 初心者向け祈願 | Gachapón de principiante | Vœux des débutants | Desejos de Novato | ผู้เริ่มอธิษฐาน | Cầu Nguyện Tân Thủ |
| `gachaTypeOdesEvent` (活動頌願) | Event Ode | イベント星願 | Oda promocional | Odes événements | Evento de Ode | กิจกรรมภาวนา | Ca Tụng Sự Kiện |
| `gachaTypeOdesStandard` (常駐頌願) | Standard Ode | 通常星願 | Oda permanente | Odes permanentes | Ode Permanente | ภาวนาถาวร | Ca Tụng Thường |

`tableRarity` 等其餘術語無變化，不動。

## 連動 key 推導規則

下列 key 不在 glossary 表內，但須依更新後術語推導，保持一致：

1. **nav 短標籤** `navChronicled` / `navStandard` / `navBeginner`：取對應 gachaType 全名的自然短形。例：
   - vi：`navStandard` `Thường Trú`→`Thường`（對齊 `Cầu Nguyện Thường`）、`navBeginner` `Người Mới`→`Tân Thủ`（對齊 `Cầu Nguyện Tân Thủ`）
   - th：`navStandard` `แห่งการเดินทาง`→`ถาวร`（對齊 `อธิษฐานถาวร`）、`navBeginner` `ผู้เริ่มต้น`→`ผู้เริ่ม`（對齊 `ผู้เริ่มอธิษฐาน`）
   - en：`navBeginner` `Beginner`→`Novice`（對齊 `Novice Wishes`）
   - 其餘語系若 gachaType 短形未變則 nav 短標籤不動。
2. **頌願 nav 短標籤** `navOdesEvent`（活動）/ `navOdesStandard`（常駐）：es/fr/pt/th/vi 從 SKIP 補齊，取頌願分類的短形（如 es `Promocional`/`Permanente`、fr `Événements`/`Permanentes`，依該語系 gachaTypeOdes* 的構詞）。
3. **綜合頁 section** `pageOverviewGachaSection`（祈願綜合）/ `pageOverviewOdesSection`（頌願綜合）：
   - 補 `pageOverviewOdesSection`（5 語系從 SKIP）。
   - es 的 `pageOverviewGachaSection` 內文 `Deseos`→`Gachapón`（因系統名改 Gachapón）。
4. **空狀態** `emptyNoGachaRecords`（尚無祈願記錄）/ `emptyNoOdesRecords`（尚無頌願記錄）：
   - 補 `emptyNoOdesRecords`（5 語系從 SKIP）。
   - es 的 `emptyNoGachaRecords` 內文 `deseos`→`Gachapón`。
5. **en/ja 頌願綜合頁與空狀態**：en 既有 `pageOverviewOdesSection`="Odes Overview"、`emptyNoOdesRecords`="No Odes records yet" — 因 en 頌願改單數 `Ode`，視語感決定是否同步（`Ode` vs `Odes` 複數在 "Overview"/"records" 語境通常用複數，可保留 `Odes`；由 subagent 判斷自然度）。

## es 系統名 Gachapón 連帶影響

es 把祈願系統名從官方 `Deseo` 改為社群慣用 `Gachapón`（使用者明確指定，覆蓋官方）。凡 es 既有譯文內含 `Deseo`/`Deseos` 作「祈願系統」語意者，一併改為 `Gachapón`，包含但不限於：
- `pageOverviewGachaSection`（`Resumen de Deseos`→`Resumen de Gachapón`）
- `emptyNoGachaRecords`（`...registros de deseos`→`...de Gachapón`）

注意：`Deseo` 若出現在**非系統名語意**（如一般動詞/名詞）不需改；由 subagent 判斷。本專案 es 既有譯文中 `Deseo(s)` 幾乎都指祈願系統，須逐一檢查。

## 不變式

- placeholder 名稱、ICU plural 結構、`5★` 字形一律保留。
- 不動非術語相關的既有譯文。
- 補齊頌願 key 時加上對應 `@key` placeholder metadata（若 template 有；頌願這些 key 在 template 多無 placeholder，照 template）。
- 提交前 `dart format lib/ test/` / `flutter analyze`（No issues found!）/ `flutter test`（All tests passed!）三項全過。

## 逐語系流程與預期 key 數

| 語系 | 補完前 | 補完後 | 主要變更 |
|---|---|---|---|
| en | 208 | 208 | gachaTypeBeginner→Novice Wishes、Odes→單數、navBeginner→Novice |
| ja | 208 | 208 | gachaTypeBeginner→初心者向け祈願 |
| es | 201 | 208 | 全面 Gachapón 化 + 補頌願 7 key + 內文 Deseo→Gachapón |
| fr | 201 | 208 | gachaTypeBeginner→des débutants + 補頌願 7 key |
| pt | 201 | 208 | navSectionGacha→Orar、Standard→Comum、Beginner→Desejos de Novato + 補頌願 7 key |
| th | 201 | 208 | Standard/Beginner 改通用分類名 + 補頌願 7 key |
| vi | 201 | 208 | char/weapon 去 Sự Kiện、Standard/Beginner 改通用名 + 補頌願 7 key |

「補頌願 7 key」= `navSectionOdes`、`navOdesEvent`、`navOdesStandard`、`gachaTypeOdesEvent`、`gachaTypeOdesStandard`、`pageOverviewOdesSection`、`emptyNoOdesRecords`。

## Commit 規格

每語系一個 commit，英文訊息，對齊既有 `chore(i18n): ...` 風格。例：
- `chore(i18n): realign English gacha-type terms to glossary`
- `chore(i18n): realign Spanish terms to Gachapón + fill Odes keys`
- …

含 Claude Code 共著者標記。push 到 `flutter-rewrite`，不開 PR。

## 不做（YAGNI）

- 不動 `app_zh.arb`、`app_zh_Hans.arb`
- 不 commit `docs/術語表.md`
- 不改非術語相關既有譯文
- 不重排既有 key 順序
- 不為本次變更新增測試（既有 `test/l10n/locale_metadata_test.dart` 為結構 net）

## 報告

任務結束回報：各語系變更摘要、頌願補齊數、commit SHA 列表。
