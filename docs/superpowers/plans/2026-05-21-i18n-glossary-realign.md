# i18n Glossary Realign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 依更新後的 `docs/術語表.md` 重新對齊 en/ja/es/fr/pt/th/vi 七語系的祈願/頌願分類與連動術語，並補齊 es/fr/pt/th/vi 的頌願 key，使五語系達 208/208。

**Architecture:** 七個獨立單檔編輯任務（每語系一個 commit）。每個 task 套用 glossary 鎖定值 + 推導連動 key，跑 `dart format`/`flutter analyze`/`flutter test`，通過後 commit、push 到 `flutter-rewrite`。不開 PR。`app_zh.arb`/`app_zh_Hans.arb` 不動。`docs/術語表.md` 不 commit。

**Tech Stack:** Flutter gen-l10n（ARB），既有 `test/l10n/locale_metadata_test.dart` 為結構 net。

---

## File Structure

修改檔（每 commit 一檔）：
- `lib/l10n/app_en.arb` — 4 個 key 改值（含 Odes 單數）
- `lib/l10n/app_ja.arb` — 1 個 key 改值
- `lib/l10n/app_es.arb` — Gachapón 化 + 補頌願 7 key（→208）
- `lib/l10n/app_fr.arb` — Beginner 改值 + 補頌願 7 key（→208）
- `lib/l10n/app_pt.arb` — Orar/Comum/Novato + 補頌願 7 key（→208）
- `lib/l10n/app_th.arb` — Standard/Beginner 改值 + 補頌願 7 key（→208）
- `lib/l10n/app_vi.arb` — char/weapon/Standard/Beginner 改值 + 補頌願 7 key（→208）

不動：`app_zh.arb`、`app_zh_Hans.arb`、`docs/術語表.md`（本地參考）。

**頌願 7 key（es/fr/pt/th/vi 待補）皆無 placeholder**，不需 `@key` metadata。

---

## Task 0: Pre-flight verification

**Files:** Read-only.

- [ ] **Step 1: 確認分支與乾淨工作區**

```bash
git rev-parse --abbrev-ref HEAD
git status --short
```
Expected: `flutter-rewrite`，工作區乾淨（`docs/術語表.md` 為 untracked 且不納入，可忽略）。

- [ ] **Step 2: 確認各語系起始 key 數**

```bash
node -e "
const fs=require('fs');const dir='lib/l10n/';
for (const f of ['app_en.arb','app_ja.arb','app_es.arb','app_fr.arb','app_pt.arb','app_th.arb','app_vi.arb']) {
  const o=JSON.parse(fs.readFileSync(dir+f,'utf8'));
  console.log(f, Object.keys(o).filter(k=>!k.startsWith('@')).length);
}"
```
Expected: `app_en.arb 208`, `app_ja.arb 208`, 其餘 `201`。

- [ ] **Step 3: 起手測試綠燈**

```bash
flutter test test/l10n/locale_metadata_test.dart
```
Expected: All tests passed!

---

## Task 1: Realign `app_en.arb`

**Files:** Modify `lib/l10n/app_en.arb`

英文改用 glossary 新值（Novice Wishes、Ode 單數），並連動 navBeginner。`navSectionOdes`/`pageOverviewOdesSection`/`emptyNoOdesRecords` 維持複數 "Odes"（overview/records 語境複數較自然，glossary 的「頌願系統名」單複數不影響這些語境）。

- [ ] **Step 1: 套用 4 個 key 變更**

| key | 現值 | 新值 |
|---|---|---|
| `gachaTypeBeginner` | `Beginners' Wish` | `Novice Wishes` |
| `gachaTypeOdesEvent` | `Event Odes` | `Event Ode` |
| `gachaTypeOdesStandard` | `Standard Odes` | `Standard Ode` |
| `navBeginner` | `Beginner` | `Novice` |

用 Edit 逐一替換對應行的值，不動其他 key。

- [ ] **Step 2: 驗證**

```bash
node -e "
const o=JSON.parse(require('fs').readFileSync('lib/l10n/app_en.arb','utf8'));
console.log('total =', Object.keys(o).filter(k=>!k.startsWith('@')).length);
for (const [k,v] of Object.entries({gachaTypeBeginner:'Novice Wishes',gachaTypeOdesEvent:'Event Ode',gachaTypeOdesStandard:'Standard Ode',navBeginner:'Novice'})) {
  console.log(k, o[k]===v ? 'OK' : 'FAIL got '+JSON.stringify(o[k]));
}"
```
Expected: `total = 208`，4 行 `OK`。

- [ ] **Step 3: 提交前檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: No issues found! / All tests passed!（若 `app_release_checker`/`log_service` 在 parallel 偶發 flaky，單獨重跑該檔確認綠燈，屬已知非回歸）

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb
git commit -m "$(cat <<'EOF'
chore(i18n): realign English gacha-type terms to glossary

Per docs/術語表.md: gachaTypeBeginner -> "Novice Wishes",
gachaTypeOdesEvent/Standard -> singular "Event Ode"/"Standard Ode",
navBeginner -> "Novice".

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Realign `app_ja.arb`

**Files:** Modify `lib/l10n/app_ja.arb`

- [ ] **Step 1: 套用 1 個 key 變更**

| key | 現值 | 新值 |
|---|---|---|
| `gachaTypeBeginner` | `初心者応援祈願` | `初心者向け祈願` |

`navBeginner` 維持 `初心者`（不變）。

- [ ] **Step 2: 驗證**

```bash
node -e "
const o=JSON.parse(require('fs').readFileSync('lib/l10n/app_ja.arb','utf8'));
console.log('total =', Object.keys(o).filter(k=>!k.startsWith('@')).length);
console.log('gachaTypeBeginner', o.gachaTypeBeginner==='初心者向け祈願' ? 'OK' : 'FAIL '+JSON.stringify(o.gachaTypeBeginner));
console.log('navBeginner', o.navBeginner==='初心者' ? 'OK' : 'FAIL '+JSON.stringify(o.navBeginner));
"
```
Expected: `total = 208`，2 行 `OK`。

- [ ] **Step 3: 提交前檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_ja.arb
git commit -m "$(cat <<'EOF'
chore(i18n): realign Japanese beginners' wish term to glossary

Per docs/術語表.md: gachaTypeBeginner 初心者応援祈願 -> 初心者向け祈願.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Realign `app_es.arb` (Gachapón + fill Odes)

**Files:** Modify `lib/l10n/app_es.arb`

es 把祈願系統名從官方 `Deseo` 改成社群慣用 `Gachapón`（使用者明確指定）。所有 gachaType 與內文 `Deseo(s)`（祈願系統語意）改成 Gachapón，並補頌願 7 key。

- [ ] **Step 1: 套用變更值（gachaType + navSection + 連動）**

| key | 現值 | 新值 |
|---|---|---|
| `navSectionGacha` | `Deseo` | `Gachapón` |
| `gachaTypeCharacter` | `Deseo de Evento de Personaje` | `Gachapón promocional de personaje` |
| `gachaTypeWeapon` | `Deseo de Evento de Arma` | `Gachapón promocional de arma` |
| `gachaTypeChronicled` | `Deseo Crónico` | `Gachapón recopilatorio` |
| `gachaTypeStandard` | `Deseo Estándar` | `Gachapón permanente` |
| `gachaTypeBeginner` | `Deseo para Principiantes` | `Gachapón de principiante` |
| `navChronicled` | `Crónico` | `Recopilatorio` |
| `navStandard` | `Estándar` | `Permanente` |
| `navBeginner` | `Principiantes` | `Principiante` |
| `pageOverviewGachaSection` | `Resumen de Deseos` | `Resumen de Gachapón` |
| `emptyNoGachaRecords` | `Aún no hay registros de deseos` | `Aún no hay registros de Gachapón` |

- [ ] **Step 2: 新增頌願 7 key**

| key | 新值 |
|---|---|
| `navSectionOdes` | `Odas` |
| `gachaTypeOdesEvent` | `Oda promocional` |
| `gachaTypeOdesStandard` | `Oda permanente` |
| `navOdesEvent` | `Promocional` |
| `navOdesStandard` | `Permanente` |
| `pageOverviewOdesSection` | `Resumen de Odas` |
| `emptyNoOdesRecords` | `Aún no hay registros de odas` |

插入到 template `app_zh.arb` 對應的相對位置（gachaTypeOdes* 接在 gachaTypeBeginner 後、navOdes* 接在 navSection* 區、pageOverviewOdesSection 接在 pageOverviewGachaSection 後、emptyNoOdesRecords 接在 emptyNoGachaRecords 後）。無 `@key` metadata。

- [ ] **Step 3: 掃描遺漏的 Deseo 系統名殘留**

```bash
node -e "
const o=JSON.parse(require('fs').readFileSync('lib/l10n/app_es.arb','utf8'));
for (const [k,v] of Object.entries(o)) {
  if (typeof v==='string' && /deseo/i.test(v)) console.log('CONTAINS Deseo:', k, '=', JSON.stringify(v));
}"
```
檢查列出的每一筆：若 `Deseo(s)` 指祈願系統 → 改 Gachapón；若為一般語意（無）→ 保留。預期改完後此清單應為空或只剩非系統語意者。

- [ ] **Step 4: 驗證 key 數 / parity / 無全形括號**

```bash
node -e "
const fs=require('fs');
const zh=JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const es=JSON.parse(fs.readFileSync('lib/l10n/app_es.arb','utf8'));
const zhK=new Set(Object.keys(zh).filter(k=>!k.startsWith('@')));
const esK=new Set(Object.keys(es).filter(k=>!k.startsWith('@')));
console.log('es total =', esK.size);
console.log('missing =', [...zhK].filter(k=>!esK.has(k)).join(','));
console.log('extra =', [...esK].filter(k=>!zhK.has(k)).join(','));
const text=fs.readFileSync('lib/l10n/app_es.arb','utf8');
console.log('fullwidth parens =', (text.match(/[（）]/g)||[]).length);
"
```
Expected: `es total = 208`、`missing =`（空）、`extra =`（空）、`fullwidth parens = 0`。

- [ ] **Step 5: 提交前檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_es.arb
git commit -m "$(cat <<'EOF'
chore(i18n): realign Spanish to Gachapón terms + fill Odes keys

Per docs/術語表.md: switch the wish system from official "Deseo" to
the community term "Gachapón" across all gacha types and inline
mentions; fill the 7 Odes keys (Odas) bringing es to 208/208.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Realign `app_fr.arb` (Beginner + fill Odes)

**Files:** Modify `lib/l10n/app_fr.arb`

- [ ] **Step 1: 套用變更值**

| key | 現值 | 新值 |
|---|---|---|
| `gachaTypeBeginner` | `Vœux pour débutants` | `Vœux des débutants` |

`navBeginner` 維持 `Débutants`（不變）。

- [ ] **Step 2: 新增頌願 7 key**

| key | 新值 |
|---|---|
| `navSectionOdes` | `Odes` |
| `gachaTypeOdesEvent` | `Odes événements` |
| `gachaTypeOdesStandard` | `Odes permanentes` |
| `navOdesEvent` | `Événements` |
| `navOdesStandard` | `Permanentes` |
| `pageOverviewOdesSection` | `Vue d'ensemble des odes` |
| `emptyNoOdesRecords` | `Aucun enregistrement d'odes` |

使用 `œ` 連字僅在 `Vœux` 系列；`odes`（頌願）無連字。

- [ ] **Step 3: 驗證**

```bash
node -e "
const fs=require('fs');
const zh=JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const fr=JSON.parse(fs.readFileSync('lib/l10n/app_fr.arb','utf8'));
const zhK=new Set(Object.keys(zh).filter(k=>!k.startsWith('@')));
const frK=new Set(Object.keys(fr).filter(k=>!k.startsWith('@')));
console.log('fr total =', frK.size);
console.log('missing =', [...zhK].filter(k=>!frK.has(k)).join(','));
console.log('gachaTypeBeginner', fr.gachaTypeBeginner==='Vœux des débutants'?'OK':'FAIL '+JSON.stringify(fr.gachaTypeBeginner));
const text=fs.readFileSync('lib/l10n/app_fr.arb','utf8');
console.log('fullwidth parens =', (text.match(/[（）]/g)||[]).length);
"
```
Expected: `fr total = 208`、`missing =`（空）、`gachaTypeBeginner OK`、`fullwidth parens = 0`。

- [ ] **Step 4: 提交前檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_fr.arb
git commit -m "$(cat <<'EOF'
chore(i18n): realign French beginner term + fill Odes keys

Per docs/術語表.md: gachaTypeBeginner -> "Vœux des débutants"; fill
the 7 Odes keys (Odes) bringing fr to 208/208.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Realign `app_pt.arb` (Orar/Comum/Novato + fill Odes)

**Files:** Modify `lib/l10n/app_pt.arb`

- [ ] **Step 1: 套用變更值**

| key | 現值 | 新值 |
|---|---|---|
| `navSectionGacha` | `Oração` | `Orar` |
| `gachaTypeStandard` | `Oração Padrão` | `Oração Comum` |
| `gachaTypeBeginner` | `Oração de Novatos` | `Desejos de Novato` |
| `navStandard` | `Padrão` | `Comum` |
| `navBeginner` | `Novatos` | `Novato` |

`pageOverviewGachaSection`（`Resumo de Orações`）與 `emptyNoGachaRecords`（`Sem registros de Oração`）**不動**——複合詞仍用名詞 Oração，只有 `navSectionGacha` 用 glossary 指定的動詞 `Orar`。

- [ ] **Step 2: 新增頌願 7 key**

| key | 新值 |
|---|---|
| `navSectionOdes` | `Odes` |
| `gachaTypeOdesEvent` | `Evento de Ode` |
| `gachaTypeOdesStandard` | `Ode Permanente` |
| `navOdesEvent` | `Evento` |
| `navOdesStandard` | `Permanente` |
| `pageOverviewOdesSection` | `Resumo de Odes` |
| `emptyNoOdesRecords` | `Sem registros de Ode` |

- [ ] **Step 3: 驗證**

```bash
node -e "
const fs=require('fs');
const zh=JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const pt=JSON.parse(fs.readFileSync('lib/l10n/app_pt.arb','utf8'));
const zhK=new Set(Object.keys(zh).filter(k=>!k.startsWith('@')));
const ptK=new Set(Object.keys(pt).filter(k=>!k.startsWith('@')));
console.log('pt total =', ptK.size);
console.log('missing =', [...zhK].filter(k=>!ptK.has(k)).join(','));
for (const [k,v] of Object.entries({navSectionGacha:'Orar',gachaTypeStandard:'Oração Comum',gachaTypeBeginner:'Desejos de Novato',navStandard:'Comum',navBeginner:'Novato'})) {
  console.log(k, pt[k]===v?'OK':'FAIL '+JSON.stringify(pt[k]));
}
const text=fs.readFileSync('lib/l10n/app_pt.arb','utf8');
console.log('fullwidth parens =', (text.match(/[（）]/g)||[]).length);
"
```
Expected: `pt total = 208`、`missing =`（空）、5 行 `OK`、`fullwidth parens = 0`。

- [ ] **Step 4: 提交前檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_pt.arb
git commit -m "$(cat <<'EOF'
chore(i18n): realign Portuguese terms + fill Odes keys

Per docs/術語表.md: navSectionGacha -> "Orar", gachaTypeStandard ->
"Oração Comum", gachaTypeBeginner -> "Desejos de Novato" (+ nav short
forms); fill the 7 Odes keys (Odes) bringing pt to 208/208.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Realign `app_th.arb` (Standard/Beginner + fill Odes)

**Files:** Modify `lib/l10n/app_th.arb`

- [ ] **Step 1: 套用變更值**

| key | 現值 | 新值 |
|---|---|---|
| `gachaTypeStandard` | `การอธิษฐานแห่งการเดินทาง` | `อธิษฐานถาวร` |
| `gachaTypeBeginner` | `การอธิษฐานแนะนำสำหรับผู้เริ่มต้น` | `ผู้เริ่มอธิษฐาน` |
| `navStandard` | `แห่งการเดินทาง` | `ถาวร` |
| `navBeginner` | `ผู้เริ่มต้น` | `ผู้เริ่ม` |

- [ ] **Step 2: 新增頌願 7 key**

| key | 新值 |
|---|---|
| `navSectionOdes` | `ภาวนา` |
| `gachaTypeOdesEvent` | `กิจกรรมภาวนา` |
| `gachaTypeOdesStandard` | `ภาวนาถาวร` |
| `navOdesEvent` | `กิจกรรม` |
| `navOdesStandard` | `ถาวร` |
| `pageOverviewOdesSection` | `สรุปภาวนา` |
| `emptyNoOdesRecords` | `ยังไม่มีบันทึกภาวนา` |

- [ ] **Step 3: 驗證**

```bash
node -e "
const fs=require('fs');
const zh=JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const th=JSON.parse(fs.readFileSync('lib/l10n/app_th.arb','utf8'));
const zhK=new Set(Object.keys(zh).filter(k=>!k.startsWith('@')));
const thK=new Set(Object.keys(th).filter(k=>!k.startsWith('@')));
console.log('th total =', thK.size);
console.log('missing =', [...zhK].filter(k=>!thK.has(k)).join(','));
for (const [k,v] of Object.entries({gachaTypeStandard:'อธิษฐานถาวร',gachaTypeBeginner:'ผู้เริ่มอธิษฐาน',navStandard:'ถาวร',navBeginner:'ผู้เริ่ม'})) {
  console.log(k, th[k]===v?'OK':'FAIL '+JSON.stringify(th[k]));
}
const text=fs.readFileSync('lib/l10n/app_th.arb','utf8');
console.log('fullwidth parens =', (text.match(/[（）]/g)||[]).length);
"
```
Expected: `th total = 208`、`missing =`（空）、4 行 `OK`、`fullwidth parens = 0`。

- [ ] **Step 4: 提交前檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_th.arb
git commit -m "$(cat <<'EOF'
chore(i18n): realign Thai standard/beginner terms + fill Odes keys

Per docs/術語表.md: move gachaTypeStandard off the flagship banner
name to generic อธิษฐานถาวร, gachaTypeBeginner -> ผู้เริ่มอธิษฐาน
(+ nav short forms); fill the 7 Odes keys (ภาวนา) bringing th to
208/208.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Realign `app_vi.arb` (char/weapon/Standard/Beginner + fill Odes)

**Files:** Modify `lib/l10n/app_vi.arb`

- [ ] **Step 1: 套用變更值**

| key | 現值 | 新值 |
|---|---|---|
| `gachaTypeCharacter` | `Cầu Nguyện Sự Kiện Nhân Vật` | `Cầu Nguyện Nhân Vật` |
| `gachaTypeWeapon` | `Cầu Nguyện Sự Kiện Vũ Khí` | `Cầu Nguyện Vũ Khí` |
| `gachaTypeStandard` | `Du Hành Thế Gian` | `Cầu Nguyện Thường` |
| `gachaTypeBeginner` | `Cầu Nguyện Đề Xuất Cho Người Mới` | `Cầu Nguyện Tân Thủ` |
| `navStandard` | `Thường Trú` | `Thường` |
| `navBeginner` | `Người Mới` | `Tân Thủ` |

- [ ] **Step 2: 新增頌願 7 key**

| key | 新值 |
|---|---|
| `navSectionOdes` | `Ca Tụng` |
| `gachaTypeOdesEvent` | `Ca Tụng Sự Kiện` |
| `gachaTypeOdesStandard` | `Ca Tụng Thường` |
| `navOdesEvent` | `Sự Kiện` |
| `navOdesStandard` | `Thường` |
| `pageOverviewOdesSection` | `Tổng quan Ca Tụng` |
| `emptyNoOdesRecords` | `Chưa có bản ghi Ca Tụng` |

- [ ] **Step 3: 驗證**

```bash
node -e "
const fs=require('fs');
const zh=JSON.parse(fs.readFileSync('lib/l10n/app_zh.arb','utf8'));
const vi=JSON.parse(fs.readFileSync('lib/l10n/app_vi.arb','utf8'));
const zhK=new Set(Object.keys(zh).filter(k=>!k.startsWith('@')));
const viK=new Set(Object.keys(vi).filter(k=>!k.startsWith('@')));
console.log('vi total =', viK.size);
console.log('missing =', [...zhK].filter(k=>!viK.has(k)).join(','));
for (const [k,v] of Object.entries({gachaTypeCharacter:'Cầu Nguyện Nhân Vật',gachaTypeWeapon:'Cầu Nguyện Vũ Khí',gachaTypeStandard:'Cầu Nguyện Thường',gachaTypeBeginner:'Cầu Nguyện Tân Thủ',navStandard:'Thường',navBeginner:'Tân Thủ'})) {
  console.log(k, vi[k]===v?'OK':'FAIL '+JSON.stringify(vi[k]));
}
const text=fs.readFileSync('lib/l10n/app_vi.arb','utf8');
console.log('fullwidth parens =', (text.match(/[（）]/g)||[]).length);
"
```
Expected: `vi total = 208`、`missing =`（空）、6 行 `OK`、`fullwidth parens = 0`。

- [ ] **Step 4: 提交前檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_vi.arb
git commit -m "$(cat <<'EOF'
chore(i18n): realign Vietnamese terms + fill Odes keys

Per docs/術語表.md: drop "Sự Kiện" from character/weapon wish names,
move gachaTypeStandard off the flagship banner name (Du Hành Thế
Gian) to generic "Cầu Nguyện Thường", gachaTypeBeginner -> "Cầu
Nguyện Tân Thủ" (+ nav short forms); fill the 7 Odes keys (Ca Tụng)
bringing vi to 208/208.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Cross-locale verification, push, report

- [ ] **Step 1: 全語系 parity + placeholder 一致性**

```bash
node -e "
const fs=require('fs');const dir='lib/l10n/';
const zh=JSON.parse(fs.readFileSync(dir+'app_zh.arb','utf8'));
const zhK=new Set(Object.keys(zh).filter(k=>!k.startsWith('@')));
function ns(s){const set=new Set();for(const m of String(s||'').matchAll(/\{(\w+)(?:,|\})/g))set.add(m[1]);return [...set].sort().join(',');}
let bad=0;
for (const f of ['app_en.arb','app_ja.arb','app_zh_Hans.arb','app_es.arb','app_fr.arb','app_pt.arb','app_th.arb','app_vi.arb']) {
  const o=JSON.parse(fs.readFileSync(dir+f,'utf8'));
  const k=new Set(Object.keys(o).filter(x=>!x.startsWith('@')));
  const miss=[...zhK].filter(x=>!k.has(x)).length;
  const extra=[...k].filter(x=>!zhK.has(x)).length;
  let ph=0; for (const key of zhK) { if(!k.has(key))continue; if(ns(zh[key])!==ns(o[key]))ph++; }
  console.log(f+': total='+k.size+' missing='+miss+' extra='+extra+' ph_mismatch='+ph);
  bad+=miss+extra+ph;
}
console.log('TOTAL anomalies:', bad);
"
```
Expected: 八檔皆 `total=208 missing=0 extra=0 ph_mismatch=0`，`TOTAL anomalies: 0`。

- [ ] **Step 2: 最終全套測試**

```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: 全綠（parallel flaky 屬已知非回歸，單檔重跑確認）。

- [ ] **Step 3: Push**

```bash
git push origin flutter-rewrite
```

- [ ] **Step 4: 報告**

回報：各語系變更摘要、五語系頌願補齊（201→208）、所有 commit SHA（`git log --oneline -8`）。

---

## Validation Summary

每個 locale task（1–7）跑：`dart format lib/ test/`、`flutter analyze`（No issues found!）、`flutter test`（All tests passed!）。`test/l10n/locale_metadata_test.dart` 為結構 net（檢查 supportedLocales / localeTranslatorLabel placeholder / zh·zh_Hans localeTranslator 為空），本任務不動 localeTranslator 與 localeNativeName，故應全程綠。

## What we are explicitly NOT doing (YAGNI)

- 不動 `app_zh.arb`、`app_zh_Hans.arb`
- 不 commit `docs/術語表.md`
- 不改 localeTranslator / localeNativeName / 非術語相關既有譯文
- 不重排既有 key 順序
- 不為頌願補齊 key 加 `@key` metadata（這些 key 在 template 無 placeholder）
- 不新增測試
- 不開 PR
