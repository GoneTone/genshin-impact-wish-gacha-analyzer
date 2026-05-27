# i18n Fill Other Locales Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 依 `lib/l10n/app_zh.arb`（template，208 keys）補齊七個語系檔 ja / zh_Hans / es / fr / pt / th / vi 的缺漏 key，並於 es / fr / pt / th / vi 的 `localeTranslator` 加上 Claude Code (Opus 4.7) 標記。

**Architecture:** 七個獨立的單檔編輯任務，外加一個跨語系 glossary 查證任務。每個 locale 任務完成後立即跑 `dart format` + `flutter analyze` + `flutter test`，通過後 commit 並 push 到 `flutter-rewrite`。不開 PR。不確定的官方原神術語整筆跳過、不寫入。

**Tech Stack:** Flutter gen-l10n（讀 ARB），既有 `test/l10n/locale_metadata_test.dart` 作為結構性 safety net。

---

## File Structure

修改檔（每個 commit 只動一個 .arb）：
- `lib/l10n/app_ja.arb` — 補 13 個 `shareImage*` key
- `lib/l10n/app_zh_Hans.arb` — 補 13 個 `shareImage*` key
- `lib/l10n/app_es.arb` — 補 171 個 key + 更新 `localeTranslator`
- `lib/l10n/app_th.arb` — 補 171 個 key + 更新 `localeTranslator`
- `lib/l10n/app_fr.arb` — 補 180 個 key + 更新 `localeTranslator`
- `lib/l10n/app_pt.arb` — 補 186 個 key + 更新 `localeTranslator`
- `lib/l10n/app_vi.arb` — 補 195 個 key + 更新 `localeTranslator`

不動（明確 YAGNI）：
- `lib/l10n/app_zh.arb`（template）
- `lib/l10n/app_en.arb`（已完整）
- 任何 dart code、generated/、test/

僅本地參考（不進 git）：
- `docs/superpowers/i18n-glossary-2026-05-20-other-locales.md`（Task 3 新建）

---

## Task 0: Pre-flight verification

**Files:**
- Read: `lib/l10n/app_zh.arb`
- Read: `lib/l10n/app_en.arb`
- Read: 既有 `docs/superpowers/i18n-glossary-2026-05-17.md`

**Goal:** 確認起手狀態與 spec 一致，避免上一個 PR 期間有 key 漂移。

- [ ] **Step 1: 確認目前在 `flutter-rewrite` 分支且工作區乾淨**

```bash
git status
git rev-parse --abbrev-ref HEAD
```

Expected: branch = `flutter-rewrite`, status = `nothing to commit, working tree clean`

- [ ] **Step 2: 確認缺漏 key 數量符合 spec**

執行：

```bash
node -e "
const fs = require('fs');
const dir = 'lib/l10n/';
const zh = JSON.parse(fs.readFileSync(dir+'app_zh.arb','utf8'));
const zhKeys = new Set(Object.keys(zh).filter(k=>!k.startsWith('@')));
for (const f of ['app_ja.arb','app_zh_Hans.arb','app_en.arb','app_es.arb','app_fr.arb','app_pt.arb','app_th.arb','app_vi.arb']) {
  const obj = JSON.parse(fs.readFileSync(dir+f,'utf8'));
  const set = new Set(Object.keys(obj).filter(k=>!k.startsWith('@')));
  const missing = [...zhKeys].filter(k => !set.has(k));
  console.log(f+' missing='+missing.length);
}
"
```

Expected output：

```
app_ja.arb missing=13
app_zh_Hans.arb missing=13
app_en.arb missing=0
app_es.arb missing=171
app_fr.arb missing=180
app_pt.arb missing=186
app_th.arb missing=171
app_vi.arb missing=195
```

若任一數字不符，停下來檢查 template 是否有變動，必要時更新本計畫的 key 數量。

- [ ] **Step 3: 確認 ja / zh_Hans 缺的就是那 13 個 `shareImage*` key**

```bash
node -e "
const fs = require('fs');
const dir = 'lib/l10n/';
const zh = JSON.parse(fs.readFileSync(dir+'app_zh.arb','utf8'));
const zhKeys = new Set(Object.keys(zh).filter(k=>!k.startsWith('@')));
for (const f of ['app_ja.arb','app_zh_Hans.arb']) {
  const obj = JSON.parse(fs.readFileSync(dir+f,'utf8'));
  const set = new Set(Object.keys(obj).filter(k=>!k.startsWith('@')));
  const missing = [...zhKeys].filter(k => !set.has(k));
  console.log(f, missing.join(' '));
}
"
```

Expected: 兩個檔案的 missing 都是 `shareImageButton shareImageDialogTitle shareImageThemeLabel shareImageThemeDark shareImageThemeLight shareImageShowFullUid shareImageShowFullUidHint shareImageGenerate shareImageUpdatedAt shareImageSavedAndCopied shareImageSavedOnly shareImageCopiedOnly shareImageFailed`

- [ ] **Step 4: 跑既有測試確保起手綠燈**

```bash
flutter test test/l10n/locale_metadata_test.dart
```

Expected: All tests passed!

若失敗，先解決才能繼續（本任務不該破壞既有測試）。

---

## Task 1: Fill `app_ja.arb` (13 share-image keys)

**Files:**
- Modify: `lib/l10n/app_ja.arb`（在現有 `settingsImportData` 之後，`exportDialogSuccessTitle` 之前插入 13 個 key — 對齊 template 順序）

**Reference — template 原文（`app_zh.arb`）：**

```json
"shareImageButton": "生成分享圖",
"shareImageDialogTitle": "分享圖設定",
"shareImageThemeLabel": "主題",
"shareImageThemeDark": "深色",
"shareImageThemeLight": "淺色",
"shareImageShowFullUid": "在圖上顯示完整 UID",
"shareImageShowFullUidHint": "關閉時只顯示前 3 碼，其餘以 x 遮罩",
"shareImageGenerate": "生成",
"shareImageUpdatedAt": "資料更新 {time}",
"shareImageSavedAndCopied": "已存檔並複製到剪貼簿：{path}",
"shareImageSavedOnly": "已存檔：{path}（剪貼簿不支援）",
"shareImageCopiedOnly": "已複製到剪貼簿",
"shareImageFailed": "分享圖生成失敗",
```

風格基準：`app_ja.arb` 既有用詞「データ更新」「保存しました」「クリップボード」「シェア」「テーマ」「ダーク／ライト」。

- [ ] **Step 1: 編輯 `app_ja.arb`，在 `"settingsImportData": "データをインポート",` 該行之後插入下列區塊（與既有檔案縮排對齊，2 spaces）**

```json
  "shareImageButton": "シェア画像を生成",
  "shareImageDialogTitle": "シェア画像の設定",
  "shareImageThemeLabel": "テーマ",
  "shareImageThemeDark": "ダーク",
  "shareImageThemeLight": "ライト",
  "shareImageShowFullUid": "画像に UID をすべて表示",
  "shareImageShowFullUidHint": "オフにすると先頭 3 桁のみ表示し、残りは x でマスクします",
  "shareImageGenerate": "生成",
  "shareImageUpdatedAt": "データ更新 {time}",
  "shareImageSavedAndCopied": "保存してクリップボードにコピーしました：{path}",
  "shareImageSavedOnly": "保存しました：{path}（クリップボード非対応）",
  "shareImageCopiedOnly": "クリップボードにコピーしました",
  "shareImageFailed": "シェア画像の生成に失敗しました",
```

**鏡像 template 的 `@key` metadata**（review 後修正規則）：經 code review 發現既有所有 locale 檔對 placeholder-bearing key 都鏡像 template 的 `@key` 區塊。新增 key 也照辦：template 中該 key 有 `@key` 區塊 → locale 檔也加（內容完全照抄 template）；template 中沒有或為空 `{}` → locale 檔也不加。針對 shareImage 段，template 在 `shareImageUpdatedAt` / `shareImageSavedAndCopied` / `shareImageSavedOnly` 三個 key 之後各有一個 `@<key>` 區塊宣告 placeholder（type: String）；其他 10 個 shareImage key 沒有 `@` 區塊，locale 檔也不加。

- [ ] **Step 2: 確認 JSON 合法**

```bash
node -e "JSON.parse(require('fs').readFileSync('lib/l10n/app_ja.arb','utf8')); console.log('OK')"
```

Expected: `OK`

- [ ] **Step 3: 確認 key 數量現為 208 / 208**

```bash
node -e "
const o = JSON.parse(require('fs').readFileSync('lib/l10n/app_ja.arb','utf8'));
const keys = Object.keys(o).filter(k=>!k.startsWith('@'));
console.log('ja keys =', keys.length);
"
```

Expected: `ja keys = 208`

- [ ] **Step 4: 確認 placeholder 名稱與 template 一致**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const ja = JSON.parse(fs.readFileSync('lib/l10n/app_ja.arb','utf8'));
function ph(s){ return [...s.matchAll(/\{(\w+)\}/g)].map(m=>m[1]).sort().join(','); }
for (const k of ['shareImageUpdatedAt','shareImageSavedAndCopied','shareImageSavedOnly']) {
  const a = ph(zh[k]), b = ph(ja[k]);
  console.log(k, 'zh=['+a+'] ja=['+b+']', a===b?'OK':'MISMATCH');
}
"
```

Expected: 三行都顯示 `OK`

- [ ] **Step 5: 跑提交前三項檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全部通過（`flutter analyze` → `No issues found!`；`flutter test` → `All tests passed!`）

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_ja.arb
git commit -m "$(cat <<'EOF'
chore(i18n): complete Japanese share-image strings

Add 13 shareImage* keys to bring ja.arb to full parity with the
zh.arb template (208/208). Wording follows existing ja style
(katakana UI terms, native Japanese phrasing).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Fill `app_zh_Hans.arb` (13 share-image keys)

**Files:**
- Modify: `lib/l10n/app_zh_Hans.arb`（同 Task 1 位置，插入 13 個 key）

風格基準：簡中大陸 UI 慣用語（资料→数据、复制→复制、剪贴板→剪贴板、保存→保存、设置→设置）。

- [ ] **Step 1: 編輯 `app_zh_Hans.arb`，在 `"settingsImportData": "导入数据",`（或對等行）之後插入：**

```json
  "shareImageButton": "生成分享图",
  "shareImageDialogTitle": "分享图设置",
  "shareImageThemeLabel": "主题",
  "shareImageThemeDark": "深色",
  "shareImageThemeLight": "浅色",
  "shareImageShowFullUid": "在图上显示完整 UID",
  "shareImageShowFullUidHint": "关闭时只显示前 3 位，其余以 x 遮挡",
  "shareImageGenerate": "生成",
  "shareImageUpdatedAt": "数据更新 {time}",
  "shareImageSavedAndCopied": "已保存并复制到剪贴板：{path}",
  "shareImageSavedOnly": "已保存：{path}（剪贴板不支持）",
  "shareImageCopiedOnly": "已复制到剪贴板",
  "shareImageFailed": "分享图生成失败",
```

- [ ] **Step 2: 確認 JSON 合法**

```bash
node -e "JSON.parse(require('fs').readFileSync('lib/l10n/app_zh_Hans.arb','utf8')); console.log('OK')"
```

Expected: `OK`

- [ ] **Step 3: 確認 key 數量 = 208，placeholder 一致**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const hans = JSON.parse(fs.readFileSync('lib/l10n/app_zh_Hans.arb','utf8'));
const keys = Object.keys(hans).filter(k=>!k.startsWith('@'));
console.log('zh_Hans keys =', keys.length);
function ph(s){ return [...s.matchAll(/\{(\w+)\}/g)].map(m=>m[1]).sort().join(','); }
for (const k of ['shareImageUpdatedAt','shareImageSavedAndCopied','shareImageSavedOnly']) {
  console.log(k, ph(zh[k])===ph(hans[k]) ? 'OK' : 'MISMATCH');
}
"
```

Expected: `zh_Hans keys = 208`，三行 `OK`。

- [ ] **Step 4: 提交前三項檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_zh_Hans.arb
git commit -m "$(cat <<'EOF'
chore(i18n): complete Simplified Chinese share-image strings

Add 13 shareImage* keys to bring zh_Hans.arb to full parity with the
zh.arb template (208/208). Wording uses mainland conventions
(数据/剪贴板/保存/设置).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Extend glossary for es / fr / pt / th / vi

**Files:**
- Create: `docs/superpowers/i18n-glossary-2026-05-20-other-locales.md`（本地，不進 git，`docs/superpowers/` 已 gitignored）

**Goal:** 在後續 5 個 locale 任務開始前，把所有遊戲專有名詞的官方在地譯名鎖定。查不到可靠官方來源者**列入「待查證／跳過」清單**，後續 locale 任務遇到對應 key 就跳過不寫入。

需要查證的核心術語清單（從 `app_zh.arb` 萃取，影響多個 key）：

| 繁中 | 影響的 i18n keys |
|---|---|
| 角色活動祈願 | `gachaTypeCharacter` |
| 武器活動祈願 | `gachaTypeWeapon` |
| 集錄祈願 | `gachaTypeChronicled`, `navChronicled` |
| 常駐祈願 | `gachaTypeStandard`, `navStandard` |
| 新手祈願 | `gachaTypeBeginner`, `navBeginner` |
| 活動頌願 | `gachaTypeOdesEvent`, `navOdesEvent` |
| 常駐頌願 | `gachaTypeOdesStandard`, `navOdesStandard` |
| 祈願（系統名） | `navSectionGacha` |
| 頌願（系統名） | `navSectionOdes`, `pageOverviewOdesSection`, `emptyNoOdesRecords` |
| 保底 | `pityRank`, `pityGuaranteed`, `pityDistance`, `pityClose`, `pityNoMainRarity`, `pityBeginnerEnded`, `pityAverageInterval`, `tableMainPity`, `tableMainPityTooltip` |
| 稀有度 | `tableRarity`, `statsRarityDistribution`, `filterRarityAll`, `filterRarityRankOnly` |
| 5★/4★/3★ 字形 | 多處（保留 `5★` 字形原樣，依既有 spec） |
| UID | 多處（不翻譯） |

- [ ] **Step 1: 對每個術語、每個目標語系（es / fr / pt / th / vi），用 WebSearch 查證**

查證策略（按優先序）：

1. `WebSearch` 「Genshin Impact <term> <language>」：找 HoYoverse 官方公告、官方 News 頁、官方在地化網站
2. `WebSearch` 「site:genshin.hoyoverse.com <term>」+ 語系限定
3. Fandom Wiki 各語版（次要參考）：`<lang>.genshin-impact.fandom.com`
4. 玩家社群官方截圖（HoYoLAB、Reddit）

每個語系每個術語做一次查證，每查 3 次仍無可靠官方來源 → 標記「跳過」。

**重點注意項：**
- 「頌願（Odes）」HoYoverse 在 en / ja / zh_Hans 之外的語系**通常沒有公開官方分類名**。預期會在多數語系跳過所有 `Odes` 相關 key。
- 「集錄祈願（Chronicled Wish）」5.x 之後才引入，部分語系可能還在採用舊名或無官方名。
- 「保底」是社群慣用詞，HoYoverse UI 通常用 "guaranteed" / "pity" / 對應翻譯，需確認該語系實際 in-game 顯示用詞。

- [ ] **Step 2: 把查證結果寫入 `docs/superpowers/i18n-glossary-2026-05-20-other-locales.md`**

格式範例：

```markdown
# i18n 官方術語表 — es / fr / pt / th / vi（2026-05-20）

| 繁中 | es | fr | pt | th | vi | 來源 / 備註 |
|---|---|---|---|---|---|---|
| 角色活動祈願 | Deseo de evento de personaje | Vœu d'évent. de personnage | Desejo de Evento de Personagem | ... | ... | HoYoverse <URL> |
| ... | | | | | | |

## 跳過清單（無可靠官方來源）

- es: gachaTypeOdesEvent, gachaTypeOdesStandard, navSectionOdes, navOdesEvent, navOdesStandard, pageOverviewOdesSection, emptyNoOdesRecords
- fr: ...
```

每填一格都要附 URL。**找不到就不要編造**，明確列入跳過清單。

- [ ] **Step 3: 確認 glossary 沒被 git 追蹤**

```bash
git status docs/
git check-ignore docs/superpowers/i18n-glossary-2026-05-20-other-locales.md
```

Expected: `git status` 不顯示該檔，`git check-ignore` 印出該檔路徑（代表已被忽略）。

不需要 commit。Task 3 沒有版控變動。

---

## Task 4: Fill `app_es.arb` (171 keys + localeTranslator)

**Files:**
- Modify: `lib/l10n/app_es.arb`

**Translator update**：
- 現值：`"localeTranslator": "cahoinu",`
- 新值：`"localeTranslator": "cahoinu, <a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",`

**翻譯來源：**
1. 遊戲專有名詞 → Task 3 glossary
2. 非遊戲詞 → 自然西班牙文 UI 用語，沿用既有檔風格（既有譯者去重音的習慣已存在於 `Pagina anterior` 等行，但**新譯一律寫正確重音**，與既有譯文混存）
3. 既有採用 ICU `plural` 形式的 `relative*Ago` 系列：保留既有格式不動。新增 key 若有 `{count}` 計數語意，亦使用 `{count, plural, =1{...} other{...}}` 格式。

**插入策略**：以 template `app_zh.arb` 順序為基準，將每個缺漏 key 插入到該檔最接近的相鄰既有 key 旁。

- [ ] **Step 1: 萃取本檔缺漏 key 完整清單**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const es = JSON.parse(fs.readFileSync('lib/l10n/app_es.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const esKeys = new Set(Object.keys(es).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!esKeys.has(k));
console.log('missing count =', missing.length);
for (const k of missing) console.log(k+'\t'+zh[k]);
"
```

Expected: `missing count = 171` 後接 171 行 `key<TAB>原文`。

- [ ] **Step 2: 逐 key 翻譯，套 glossary**

對 Step 1 輸出的每一行：
- 若該 key 對應 glossary 中的「跳過清單」項目 → 不寫入，記入本次的本地 skip log
- 否則：用 glossary 鎖定的官方名 + 既有 es 風格翻譯
- 保留 placeholder：`{n}`、`{star}`、`{count}`、`{path}`、`{uid}`、`{rate}`、`{time}`、`{version}`、`{date}`、`{status}`、`{reason}`、`{message}`、`{error}`、`{accounts}`、`{records}`、`{success}`、`{total}`、`{failedUids}`、`{uids}`、`{year}`、`{month}`、`{page}`、`{names}`、`{name}`、`{current}`、`{threshold}` — 名稱完全不動
- 含 `{count, plural, ...}` 的 key 用 ICU 格式

**rarity star 字形不變**：`5★` / `4★` / `3★` 原樣保留（不寫成 `5 estrellas`）。

- [ ] **Step 3: 寫入 `app_es.arb`：插入新 key 並更新 `localeTranslator`**

`localeTranslator` 改為：

```json
  "localeTranslator": "cahoinu, <a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",
```

新 key 依 template 順序穿插插入既有 key 之間（不重寫整檔，只 Edit 區段）。

- [ ] **Step 4: 確認 JSON 合法、key 數正確、placeholder 一致**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const es = JSON.parse(fs.readFileSync('lib/l10n/app_es.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const esKeys = new Set(Object.keys(es).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!esKeys.has(k));
console.log('es total =', esKeys.size, ' missing(=skipped) =', missing.length);
console.log('skipped:', missing.join(', '));
function ph(s){ if(!s) return ''; return [...String(s).matchAll(/\{(\w+)[,}]/g)].map(m=>m[1]).sort().join(','); }
let mismatches = 0;
for (const k of zhKeys) {
  if (!esKeys.has(k)) continue;
  if (ph(zh[k]) !== ph(es[k])) { console.log('PH MISMATCH', k, 'zh=['+ph(zh[k])+']', 'es=['+ph(es[k])+']'); mismatches++; }
}
console.log('placeholder mismatches:', mismatches);
"
```

Expected:
- `es total = (208 - 跳過數)`
- `placeholder mismatches: 0`

若 mismatch > 0，修正後再跑一次。

- [ ] **Step 5: 提交前三項檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

`flutter test` 要 pass，特別注意 `test/l10n/locale_metadata_test.dart` 中對 `localeTranslatorLabel('__TESTER__')` 帶入測試 — 既有 es 已含 `{translator}` placeholder 且本任務不動 `localeTranslatorLabel`，故應自動 pass。

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_es.arb
git commit -m "$(cat <<'EOF'
chore(i18n): fill Spanish translations from Traditional Chinese template

Bulk-fill missing keys in es.arb based on app_zh.arb. Game-specific
terms (gacha types, pity wording) use HoYoverse official Spanish
in-game terminology where confirmed. Keys with no confirmable
official term are skipped. Existing community translations are
preserved unchanged. Append Claude Code to localeTranslator credit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Fill `app_th.arb` (171 keys + localeTranslator)

**Files:**
- Modify: `lib/l10n/app_th.arb`

**Translator update**：
- 現值：`"localeTranslator": "Armzyaec1234",`
- 新值：`"localeTranslator": "Armzyaec1234, <a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",`

**翻譯來源：**
1. 遊戲專有名詞 → Task 3 glossary 中 th 欄
2. 非遊戲詞 → 自然泰文 UI，沿用既有 th.arb 風格（既有有 `อัพเดทข้อมูล` `ตัวละคร` `อาวุธ` `ปรับปรุงล่าสุด` 等用詞）
3. 數字與單位空格依既有檔風格（`{count} วินาทีที่แล้ว` 中間有空格）

**插入策略**：同 Task 4，照 template 順序穿插。

- [ ] **Step 1: 萃取本檔缺漏 key 清單**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const th = JSON.parse(fs.readFileSync('lib/l10n/app_th.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const thKeys = new Set(Object.keys(th).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!thKeys.has(k));
console.log('missing count =', missing.length);
for (const k of missing) console.log(k+'\t'+zh[k]);
"
```

Expected: `missing count = 171` 後接 171 行 `key<TAB>原文`。

- [ ] **Step 2: 逐 key 翻譯，套 glossary**

同 Task 4 流程：跳過清單項不寫入；placeholder 名稱完全照搬；`5★` 字形原樣保留。

- [ ] **Step 3: 寫入 `app_th.arb`：插入新 key 並更新 `localeTranslator`**

`localeTranslator` 改為：

```json
  "localeTranslator": "Armzyaec1234, <a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",
```

- [ ] **Step 4: 確認 JSON 合法、key 數、placeholder 一致**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const th = JSON.parse(fs.readFileSync('lib/l10n/app_th.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const thKeys = new Set(Object.keys(th).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!thKeys.has(k));
console.log('th total =', thKeys.size, ' skipped =', missing.length);
console.log('skipped:', missing.join(', '));
function ph(s){ if(!s) return ''; return [...String(s).matchAll(/\{(\w+)[,}]/g)].map(m=>m[1]).sort().join(','); }
let mismatches = 0;
for (const k of zhKeys) {
  if (!thKeys.has(k)) continue;
  if (ph(zh[k]) !== ph(th[k])) { console.log('PH MISMATCH', k); mismatches++; }
}
console.log('placeholder mismatches:', mismatches);
"
```

Expected: `placeholder mismatches: 0`

- [ ] **Step 5: 提交前三項檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_th.arb
git commit -m "$(cat <<'EOF'
chore(i18n): fill Thai translations from Traditional Chinese template

Bulk-fill missing keys in th.arb based on app_zh.arb. Game-specific
terms use HoYoverse official Thai in-game terminology where
confirmed; keys with no confirmable official term are skipped.
Existing community translations preserved unchanged. Append Claude
Code to localeTranslator credit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Fill `app_fr.arb` (180 keys + localeTranslator)

**Files:**
- Modify: `lib/l10n/app_fr.arb`

**Translator update**：
- 現值：`"localeTranslator": "",`（空字串）
- 新值：`"localeTranslator": "<a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",`

**翻譯來源：**
1. 遊戲專有名詞 → Task 3 glossary 中 fr 欄
2. 非遊戲詞 → 自然法文 UI。**oe 連字注意**：既有檔已用 `vœu` / `voeux`（混用 — 沿用既有，新譯統一用 `vœu`/`vœux` 連字）
3. 既有 ICU `plural` 形式保留

**注意**：原 `localeTranslator` 為空 → 修改後 `test/l10n/locale_metadata_test.dart` 仍 pass（測試只檢查 `localeTranslatorLabel` 帶 placeholder，不檢查 `localeTranslator` 非空）。

- [ ] **Step 1: 萃取本檔缺漏 key 清單**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const fr = JSON.parse(fs.readFileSync('lib/l10n/app_fr.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const frKeys = new Set(Object.keys(fr).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!frKeys.has(k));
console.log('missing count =', missing.length);
for (const k of missing) console.log(k+'\t'+zh[k]);
"
```

Expected: `missing count = 180` 後接 180 行 `key<TAB>原文`。

- [ ] **Step 2: 逐 key 翻譯，套 glossary**

同前；跳過清單照辦。

- [ ] **Step 3: 寫入 `app_fr.arb`：插入新 key 並更新 `localeTranslator`**

`localeTranslator` 改為：

```json
  "localeTranslator": "<a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",
```

- [ ] **Step 4: 確認 JSON 合法、key 數、placeholder 一致**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const fr = JSON.parse(fs.readFileSync('lib/l10n/app_fr.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const frKeys = new Set(Object.keys(fr).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!frKeys.has(k));
console.log('fr total =', frKeys.size, ' skipped =', missing.length);
console.log('skipped:', missing.join(', '));
function ph(s){ if(!s) return ''; return [...String(s).matchAll(/\{(\w+)[,}]/g)].map(m=>m[1]).sort().join(','); }
let mismatches = 0;
for (const k of zhKeys) {
  if (!frKeys.has(k)) continue;
  if (ph(zh[k]) !== ph(fr[k])) { console.log('PH MISMATCH', k); mismatches++; }
}
console.log('placeholder mismatches:', mismatches);
"
```

Expected: `placeholder mismatches: 0`

- [ ] **Step 5: 提交前三項檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_fr.arb
git commit -m "$(cat <<'EOF'
chore(i18n): fill French translations from Traditional Chinese template

Bulk-fill missing keys in fr.arb based on app_zh.arb. Game-specific
terms use HoYoverse official French in-game terminology where
confirmed; keys with no confirmable official term are skipped.
Existing community translations preserved unchanged. Set
localeTranslator to credit Claude Code (was empty).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Fill `app_pt.arb` (186 keys + localeTranslator)

**Files:**
- Modify: `lib/l10n/app_pt.arb`

**Translator update**：
- 現值：`"localeTranslator": "Mirusausiliq & Boemio",`
- 新值：`"localeTranslator": "Mirusausiliq & Boemio, <a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",`

（保留 `&` 與既有譯者連接；新項用 `, ` 附加。）

**翻譯來源：**
1. 遊戲專有名詞 → Task 3 glossary 中 pt 欄。原神官方葡萄牙文網站偏 pt-BR；既有譯者風格也偏 pt-BR（`personangem` 看似 typo `personagem`、`tipo` 小寫）。**沿用既有譯者風格不動既有 key**，新譯使用標準 pt-BR。
2. 既有 ICU `plural` 形式保留

**Care**：既有檔 pt 的 `relative*Ago` 用 `=1{Há 1 ...} other{Há {count} ...s}` 格式，新增複數 key 比照。

- [ ] **Step 1: 萃取本檔缺漏 key 清單**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const pt = JSON.parse(fs.readFileSync('lib/l10n/app_pt.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const ptKeys = new Set(Object.keys(pt).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!ptKeys.has(k));
console.log('missing count =', missing.length);
for (const k of missing) console.log(k+'\t'+zh[k]);
"
```

Expected: `missing count = 186` 後接 186 行 `key<TAB>原文`。

- [ ] **Step 2: 逐 key 翻譯**

同前；跳過清單照辦。

- [ ] **Step 3: 寫入 `app_pt.arb`：插入新 key 並更新 `localeTranslator`**

`localeTranslator` 改為：

```json
  "localeTranslator": "Mirusausiliq & Boemio, <a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",
```

- [ ] **Step 4: 確認 JSON 合法、key 數、placeholder 一致**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const pt = JSON.parse(fs.readFileSync('lib/l10n/app_pt.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const ptKeys = new Set(Object.keys(pt).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!ptKeys.has(k));
console.log('pt total =', ptKeys.size, ' skipped =', missing.length);
console.log('skipped:', missing.join(', '));
function ph(s){ if(!s) return ''; return [...String(s).matchAll(/\{(\w+)[,}]/g)].map(m=>m[1]).sort().join(','); }
let mismatches = 0;
for (const k of zhKeys) {
  if (!ptKeys.has(k)) continue;
  if (ph(zh[k]) !== ph(pt[k])) { console.log('PH MISMATCH', k); mismatches++; }
}
console.log('placeholder mismatches:', mismatches);
"
```

Expected: `placeholder mismatches: 0`

- [ ] **Step 5: 提交前三項檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

特別檢查 `test/l10n/locale_metadata_test.dart::葡萄牙文 localeNativeName 含 "Portugu"` — 我們不動 `localeNativeName`，應自動 pass。

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_pt.arb
git commit -m "$(cat <<'EOF'
chore(i18n): fill Portuguese translations from Traditional Chinese template

Bulk-fill missing keys in pt.arb based on app_zh.arb. Game-specific
terms use HoYoverse official Portuguese in-game terminology where
confirmed; keys with no confirmable official term are skipped.
Existing community translations preserved unchanged. Append Claude
Code to localeTranslator credit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Fill `app_vi.arb` (195 keys + localeTranslator)

**Files:**
- Modify: `lib/l10n/app_vi.arb`

**Translator update**：
- 現值：`"localeTranslator": "",`（空字串）
- 新值：`"localeTranslator": "<a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",`

**翻譯來源：**
1. 遊戲專有名詞 → Task 3 glossary 中 vi 欄
2. 非遊戲詞 → 自然越南文 UI，沿用既有 vi 風格（`Nhân Vật`、`Vũ Khí`、`{count} giây trước`）
3. 既有 `relative*Ago` 為**單純帶 placeholder**（無 ICU plural）— 越南文無單複數變化，新增 key 若是 count 類型同樣使用 `{count} ...` 格式即可，**不需引入 ICU plural**

- [ ] **Step 1: 萃取本檔缺漏 key 清單**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const vi = JSON.parse(fs.readFileSync('lib/l10n/app_vi.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const viKeys = new Set(Object.keys(vi).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!viKeys.has(k));
console.log('missing count =', missing.length);
for (const k of missing) console.log(k+'\t'+zh[k]);
"
```

Expected: `missing count = 195` 後接 195 行 `key<TAB>原文`。

- [ ] **Step 2: 逐 key 翻譯**

同前；跳過清單照辦。

- [ ] **Step 3: 寫入 `app_vi.arb`：插入新 key 並更新 `localeTranslator`**

`localeTranslator` 改為：

```json
  "localeTranslator": "<a href=\"https://claude.com/claude-code\">Claude Code (Opus 4.7)</a>",
```

- [ ] **Step 4: 確認 JSON 合法、key 數、placeholder 一致**

```bash
node -e "
const fs = require('fs');
const zh = JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const vi = JSON.parse(fs.readFileSync('lib/l10n/app_vi.arb','utf8'));
const zhKeys = Object.keys(zh).filter(k=>!k.startsWith('@'));
const viKeys = new Set(Object.keys(vi).filter(k=>!k.startsWith('@')));
const missing = zhKeys.filter(k=>!viKeys.has(k));
console.log('vi total =', viKeys.size, ' skipped =', missing.length);
console.log('skipped:', missing.join(', '));
function ph(s){ if(!s) return ''; return [...String(s).matchAll(/\{(\w+)[,}]/g)].map(m=>m[1]).sort().join(','); }
let mismatches = 0;
for (const k of zhKeys) {
  if (!viKeys.has(k)) continue;
  if (ph(zh[k]) !== ph(vi[k])) { console.log('PH MISMATCH', k); mismatches++; }
}
console.log('placeholder mismatches:', mismatches);
"
```

Expected: `placeholder mismatches: 0`

- [ ] **Step 5: 提交前三項檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_vi.arb
git commit -m "$(cat <<'EOF'
chore(i18n): fill Vietnamese translations from Traditional Chinese template

Bulk-fill missing keys in vi.arb based on app_zh.arb. Game-specific
terms use HoYoverse official Vietnamese in-game terminology where
confirmed; keys with no confirmable official term are skipped.
Existing community translations preserved unchanged. Set
localeTranslator to credit Claude Code (was empty).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Push and final report

- [ ] **Step 1: 確認 7 個 commit 已準備好**

```bash
git log --oneline -7
```

Expected: 看到本任務的 7 個 commit（從 `chore(i18n): complete Japanese share-image strings` 到 `chore(i18n): fill Vietnamese translations ...`）。

- [ ] **Step 2: 全套測試最後一次 sanity check**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全綠。

- [ ] **Step 3: Push 到 `flutter-rewrite`**

```bash
git push origin flutter-rewrite
```

- [ ] **Step 4: 產出最終報告給使用者**

在對話中回報：

- 各語系實際補完數量（總/跳過 = 寫入）
- 完整跳過清單：每個語系列出跳過的 key 與原因（例：`vi: gachaTypeOdesEvent — HoYoverse 越南文官方無對應分類名`）
- 7 個 commit 的 SHA list（`git log --format="%h %s" -7`）
- glossary 本地路徑：`docs/superpowers/i18n-glossary-2026-05-20-other-locales.md`

---

## Validation Summary

每個 Task（1, 2, 4, 5, 6, 7, 8）執行完都跑相同的三項：

1. `dart format lib/ test/`
2. `flutter analyze` — `No issues found!`
3. `flutter test` — `All tests passed!`

外加：

- `test/l10n/locale_metadata_test.dart` 為結構性 safety net：檢查每個 supported locale 的 `localeTranslatorLabel('__TESTER__')` 可代入 `{translator}`、`localeNativeName` 非空、zh/zh_Hans 的 `localeTranslator` 為空。本任務不動 `localeNativeName`、不動 zh/zh_Hans 的 `localeTranslator`、`localeTranslatorLabel` 也不在缺漏 key 清單中（每個語系都已有），故此檔應全程 pass。

---

## What we are explicitly NOT doing (YAGNI)

- 不改既有譯文（即使 pt 既有 `personangem` 看似 typo 也不修）
- 不動 `lib/l10n/app_zh.arb`、`lib/l10n/app_en.arb`
- 不動 zh / zh_Hans / en / ja 的 `localeTranslator`
- 不重排既有 key 順序
- 為 placeholder-bearing 的新 key 加 `@key` metadata 區塊鏡像 template（修正後規則，原 plan 寫「不加」是錯的；既有 locale 檔都是鏡像 template @-metadata）
- 不為跳過的 key 寫 fallback 英文/原文（保留為缺）
- 不為本次翻譯新增測試（既有測試已涵蓋 ARB 結構）
- 不開 PR（直接 push 到 `flutter-rewrite`）
- 不動 dart code、generated 檔
