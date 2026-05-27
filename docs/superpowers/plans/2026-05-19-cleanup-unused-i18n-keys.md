# 清理未使用的翻譯 key — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一次性移除 i18n 中 `lib/` 未使用的 key 與孤兒 key，使 9 個 arb 與模板 key 集合一致並通過品質閘。

**Architecture:** grep 偵測未使用 key → 比對找孤兒 key → 用一次性 Python 腳本做「行為基準」刪除（保留排版、不重排）→ 重新產生 l10n → 修壞掉的測試 → 三項品質閘全綠。腳本用完即刪（YAGNI，不留工具）。

**Tech Stack:** Flutter / Dart, Flutter gen-l10n, ripgrep, Python 3（一次性腳本），PowerShell / Bash。

參考 spec：`docs/superpowers/specs/2026-05-19-cleanup-unused-i18n-keys-design.md`

---

## 背景事實（執行前必讀）

- 模板：`lib/l10n/app_zh.arb`。9 個 arb：`app_zh, app_zh_Hans, app_en, app_es, app_fr, app_ja, app_pt, app_th, app_vi`。
- arb 格式：每個 key 一行 `  "keyName": "value",`（2 空白縮排，value 單行）。
- metadata 區塊 `"@keyName": { ... }` 可能是單行或跨多行（含 `placeholders`），主要存在於 `app_zh.arb` / `app_en.arb` / `app_ja.arb` / `app_zh_Hans.arb`；小型 arb（es/fr/pt/vi）多半只有純 key 行、無 `@` 區塊。
- `@@locale`、`@@x-*` 是 directive，**不是** key，永遠保留。
- 存取一律 `AppLocalizations.of(context)!.keyName` 或 `final l = ...; l.keyName`。無動態組 key、無反射。
- 偵測誤差天然安全方向：若 `lib/` 有非 l10n 的同名 `.xxx`，該 key 會被當「有用」保留 → 只會少刪，不會誤刪在用的。
- 本任務是資料清理，無新增產品程式碼；「測試」= `flutter analyze` + `flutter test` + key 集合一致性，而非新增單元測試。

---

## Task 1: 產生「未使用 key」候選清單

**Files:**
- 讀取：`lib/l10n/app_zh.arb`、`lib/**/*.dart`
- 產出（暫存，不 commit）：`docs/superpowers/plans/.unused-keys.txt`

- [ ] **Step 1: 抽出模板所有 key**

Run（Bash 工具）：
```bash
grep -oP '^\s{2}"\K[A-Za-z0-9_]+(?=":)' lib/l10n/app_zh.arb | sort -u > /tmp/all_keys.txt
wc -l /tmp/all_keys.txt
```
說明：`"@..."` 與 `"@@locale"` 開頭為 `@`，`[A-Za-z0-9_]+` 不會匹配，自動排除。
Expected：約 380+ 行。

- [ ] **Step 2: 對每個 key 在 lib/（排除 l10n）搜存取，篩出零命中者**

Run：
```bash
: > docs/superpowers/plans/.unused-keys.txt
while read -r k; do
  if ! rg -q "\.${k}\b" lib --glob '!lib/l10n/**'; then
    echo "$k" >> docs/superpowers/plans/.unused-keys.txt
  fi
done < /tmp/all_keys.txt
echo "未使用候選數："; wc -l < docs/superpowers/plans/.unused-keys.txt
cat docs/superpowers/plans/.unused-keys.txt
```
Expected：印出未使用候選 key 清單（數量未知，可能 0~數十）。

- [ ] **Step 3: 不 commit，進入下一個 Task**

`.unused-keys.txt` 在 `docs/superpowers/` 下（依專案慣例 gitignored），純暫存，不需 commit。

---

## Task 2: 產生「孤兒 key」清單（各非模板 arb 有、模板無）

**Files:**
- 讀取：9 個 arb
- 產出（暫存）：`docs/superpowers/plans/.orphan-keys.txt`（格式：`檔名<TAB>key`）

- [ ] **Step 1: 比對每個非模板 arb 與模板的 key 差集**

Run：
```bash
: > docs/superpowers/plans/.orphan-keys.txt
for f in app_zh_Hans app_en app_es app_fr app_ja app_pt app_th app_vi; do
  grep -oP '^\s{2}"\K[A-Za-z0-9_]+(?=":)' "lib/l10n/${f}.arb" | sort -u > /tmp/k_${f}.txt
  comm -23 /tmp/k_${f}.txt /tmp/all_keys.txt | while read -r k; do
    printf '%s\t%s\n' "$f" "$k" >> docs/superpowers/plans/.orphan-keys.txt
  done
done
echo "孤兒 key 數："; wc -l < docs/superpowers/plans/.orphan-keys.txt
cat docs/superpowers/plans/.orphan-keys.txt
```
Expected：印出 `arb<TAB>key` 清單（可能為空）。

- [ ] **Step 2: 不 commit，進入下一個 Task**

---

## Task 3: 人工複核（特別保護 key + 候選 sanity）

**Files:** 讀取 `docs/superpowers/plans/.unused-keys.txt`、`lib/`

- [ ] **Step 1: 確認特別 key 不在誤刪清單**

Run：
```bash
rg -n "\.localeNativeName\b|\.localeTranslator\b|\.localeTranslatorLabel\b" lib --glob '!lib/l10n/**'
grep -E '^(localeNativeName|localeTranslator|localeTranslatorLabel)$' docs/superpowers/plans/.unused-keys.txt || echo "OK：特別 key 不在未使用清單"
```
Expected：上半部印出 `lib/` 中對這三個 key 的存取位置；下半部印出 `OK：特別 key 不在未使用清單`。
若這三個任一出現在未使用清單 → **停下**，逐一人工確認其實際取用方式（語言切換器逐語系走訪），確認無誤才可從 `.unused-keys.txt` 移除該行不刪。

- [ ] **Step 2: 抽樣 5 個候選 key 反向確認真的沒用**

Run（把 `<KEY>` 換成清單中任 5 個）：
```bash
for KEY in <KEY1> <KEY2> <KEY3> <KEY4> <KEY5>; do
  echo "== $KEY =="; rg -n "${KEY}" lib --glob '!lib/l10n/**' || echo "  （lib 無任何出現，確為未使用）"
done
```
Expected：每個抽樣 key 在 `lib/`（非 l10n）完全無出現，或僅出現在無關上下文（非 `.${KEY}` 存取）。若發現其實有用，從 `.unused-keys.txt` 刪掉該行。

- [ ] **Step 2.5（防呆）：候選清單為空時跳過刪除**

若 `.unused-keys.txt` 與 `.orphan-keys.txt` 皆為空 → 無事可清，直接跳到「最終總結」，不需執行 Task 4–7，並向使用者回報「未發現未使用 / 孤兒 key」。

- [ ] **Step 3: 不 commit，進入移除階段**

---

## Task 4: 移除未使用 + 孤兒 key（保留排版，行基準刪除）

**Files:**
- 修改：`lib/l10n/app_zh.arb` 等 9 個 arb
- 一次性腳本（用完即刪）：`tools/_strip_keys.py`

- [ ] **Step 1: 寫一次性刪除腳本**

Create `tools/_strip_keys.py`：
```python
import sys, re

def strip(path, keys):
    with open(path, encoding='utf-8') as f:
        lines = f.readlines()
    out, i, n = [], 0, len(lines)
    key_line = re.compile(r'^\s*"(@?)([A-Za-z0-9_]+)"\s*:')
    while i < n:
        m = key_line.match(lines[i])
        if m:
            at, name = m.group(1), m.group(2)
            if name in keys:
                # 跳過這一行；若是物件起始（行尾為 '{'），吃到對應 '}' 收尾為止
                if lines[i].rstrip().endswith('{'):
                    depth = lines[i].count('{') - lines[i].count('}')
                    i += 1
                    while i < n and depth > 0:
                        depth += lines[i].count('{') - lines[i].count('}')
                        i += 1
                else:
                    i += 1
                continue
        out.append(lines[i]); i += 1
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.writelines(out)

if __name__ == '__main__':
    target = sys.argv[1]
    keys = set(l.strip() for l in open(sys.argv[2], encoding='utf-8') if l.strip())
    strip(target, keys)
    print(f'stripped {target}: removed up to {len(keys)} key groups')
```
說明：對 `"key"` 與 `"@key"` 同名一併處理；單行值（不以 `{` 結尾）刪一行；物件型（`@key` 帶 placeholders，行尾 `{`）依大括號深度刪到收尾。其餘行原樣保留 → 最小 diff。

- [ ] **Step 2: 對所有 9 個 arb 套用未使用清單**

Run：
```bash
for f in app_zh app_zh_Hans app_en app_es app_fr app_ja app_pt app_th app_vi; do
  python tools/_strip_keys.py "lib/l10n/${f}.arb" docs/superpowers/plans/.unused-keys.txt
done
```
Expected：每檔印出 `stripped ... removed up to N key groups`。

- [ ] **Step 3: 對各 arb 套用其孤兒清單**

Run：
```bash
for f in app_zh_Hans app_en app_es app_fr app_ja app_pt app_th app_vi; do
  awk -F'\t' -v F="$f" '$1==F{print $2}' docs/superpowers/plans/.orphan-keys.txt > /tmp/orphans_${f}.txt
  if [ -s /tmp/orphans_${f}.txt ]; then
    python tools/_strip_keys.py "lib/l10n/${f}.arb" /tmp/orphans_${f}.txt
  fi
done
```
Expected：有孤兒的 arb 印出 stripped 訊息；無孤兒的略過。

- [ ] **Step 4: 刪除一次性腳本（不留工具）**

Run：
```bash
rm tools/_strip_keys.py
rmdir tools 2>/dev/null || true
```
Expected：腳本移除，不進版控。

- [ ] **Step 5: 驗證 arb 仍是合法 JSON**

Run：
```bash
for f in lib/l10n/app_*.arb; do python -c "import json,sys; json.load(open(sys.argv[1],encoding='utf-8')); print('OK', sys.argv[1])" "$f"; done
```
Expected：每檔印出 `OK lib/l10n/app_xx.arb`。任一檔失敗 → 檢查該檔被刪 key 的尾隨逗號 / 物件收尾，手動修正。

- [ ] **Step 6: 先不 commit，待重新產生與測試後一起 commit**

---

## Task 5: 重新產生 l10n 並靜態分析

**Files:** 修改 `lib/l10n/generated/*`

- [ ] **Step 1: 重新產生 generated code**

Run：
```bash
flutter gen-l10n
```
Expected：無錯誤；`lib/l10n/generated/*.dart` 更新（被刪 key 的 getter/method 消失）。

- [ ] **Step 2: 靜態分析**

Run：
```bash
flutter analyze
```
Expected：可能出現「`test/` 引用已刪 key」的錯誤（下一個 Task 修）。若 `lib/` 出現引用已刪 key 的錯誤 → 表示偵測誤刪，**停下**還原該 key（從 git 還原 9 個 arb 該行 + 重新 gen-l10n），並把該 key 從清單剔除。
若僅 `test/` 有錯 → 正常，續下一步。

---

## Task 6: 修正 test/ 中對已刪 key 的引用

**Files:** 視 `flutter analyze` 報錯而定，修改 `test/**/*.dart`

- [ ] **Step 1: 列出 test/ 壞掉的引用**

Run：
```bash
flutter analyze 2>&1 | rg "test[\\/].*\.dart" || echo "test/ 無相關錯誤"
```
Expected：列出引用已刪 key 的測試檔與行號（或印出無錯誤）。

- [ ] **Step 2: 逐一修正**

對每處：若該斷言只是驗證某段文案存在且該文案已無意義 → 移除該斷言 / 該測試案例；若測試仍有意義但引用了被刪 key → 改用仍存在的等效 key 或改寫斷言。逐檔以 Edit 工具修改（不可批次盲改）。

- [ ] **Step 3: 重新分析直到全綠**

Run：
```bash
flutter analyze
```
Expected：`No issues found!`。

---

## Task 7: 品質閘 + 提交

**Files:** 全部變更（9 arb + generated + 受影響 test）

- [ ] **Step 1: 格式化**

Run：
```bash
dart format lib/ test/
```
Expected：格式化完成（arb 不受 dart format 影響；主要影響改過的 test dart）。

- [ ] **Step 2: 靜態分析**

Run：
```bash
flutter analyze
```
Expected：`No issues found!`

- [ ] **Step 3: 全套測試**

Run：
```bash
flutter test
```
Expected：`All tests passed!`
（注意：依專案記憶，`log_service` / `app_release_checker` 平行偶發 flaky；若僅這些非確定性失敗，單獨重跑該檔確認綠即非回歸。）

- [ ] **Step 4: 驗證 key 集合一致性**

Run：
```bash
grep -oP '^\s{2}"\K[A-Za-z0-9_]+(?=":)' lib/l10n/app_zh.arb | sort -u > /tmp/t.txt
for f in app_zh_Hans app_en app_es app_fr app_ja app_pt app_th app_vi; do
  grep -oP '^\s{2}"\K[A-Za-z0-9_]+(?=":)' "lib/l10n/${f}.arb" | sort -u > /tmp/o.txt
  echo "== $f 多出模板沒有的 key（應為空）=="; comm -23 /tmp/o.txt /tmp/t.txt
done
```
Expected：每個 arb 都印出空（無孤兒殘留）。

- [ ] **Step 5: 確認暫存檔未被 commit**

Run：
```bash
git status --porcelain | rg "docs/superpowers|tools/_strip_keys" && echo "注意：上列不應 commit" || echo "OK：無暫存檔待提交"
```
Expected：`OK：無暫存檔待提交`（`docs/superpowers/` 依慣例 gitignored；`tools/` 已刪）。

- [ ] **Step 6: 提交**

Run：
```bash
git add lib/l10n/
git status
git commit -m "chore(i18n): remove unused and orphan translation keys

- 移除 lib/ 未使用的翻譯 key 與只存在於部分語言 arb 的孤兒 key
- 重新產生 l10n generated code
- 同步修正受影響的測試"
```
Expected：commit 成功，diff 僅含 arb 刪除行 + generated 變更 +（如有）test 調整。

- [ ] **Step 7: 清理暫存清單檔**

Run：
```bash
rm -f docs/superpowers/plans/.unused-keys.txt docs/superpowers/plans/.orphan-keys.txt
```

---

## Self-Review 結果

**1. Spec coverage：**
- 偵測（只看 lib/、排除 l10n）→ Task 1 ✓
- 孤兒 key → Task 2、Task 4 Step 3 ✓
- 特別保護 key 複核 → Task 3 ✓
- 行基準移除、保留排版 → Task 4（腳本不重排）✓
- 重新 gen-l10n → Task 5 ✓
- 修 test/ → Task 6 ✓
- 三項品質閘 → Task 7 ✓
- key 集合一致性成功標準 → Task 7 Step 4 ✓
- 不留腳本（YAGNI）→ Task 4 Step 4 刪除腳本 ✓
- 暫存檔不進版控 → Task 7 Step 5 ✓

**2. Placeholder scan：** Task 3 Step 2 的 `<KEY1..5>` 為刻意的執行期填入（候選清單執行時才知），已標明替換方式，非計畫缺漏。其餘無 TBD / 模糊步驟。

**3. Type consistency：** 腳本函式 `strip(path, keys)` 全程一致；清單檔名 `.unused-keys.txt` / `.orphan-keys.txt` 各 Task 引用一致。

無其他問題。
