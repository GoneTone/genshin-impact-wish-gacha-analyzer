# 補齊 zh_Hans / en / ja 三語翻譯 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 依 template `lib/l10n/app_zh.arb` 完整重建 `app_zh_Hans.arb` / `app_en.arb` / `app_ja.arb`，每檔 259 個翻譯 key 全數補齊、結構逐行鏡像 template，遊戲專有名詞用 HoYoverse 官方譯名。

**Architecture:** 先上網查證鎖定一份官方術語表（glossary）。再逐檔重建：讀 `app_zh.arb` 取 key 順序與結構，每個 key 依「現有正確人工譯 → 否則本地化新譯 → 一律套 glossary 校正」決定值，輸出逐行鏡像 template 的 ARB。最後用一次性腳本＋Flutter 工具鏈驗證零差異。

**Tech Stack:** Flutter gen-l10n、ARB（JSON）、Python 3 標準庫（驗證腳本）、WebSearch/WebFetch（術語查證）。

**參考 spec:** `docs/superpowers/specs/2026-05-17-i18n-complete-zh-hans-en-ja-design.md`

**版控注意:** 本 plan、glossary、驗證腳本沿用 `docs/superpowers` gitignored 慣例，**不進版控、不 git add、不建議 commit**。唯一交付物與唯一 commit 內容為三個 `lib/l10n/app_*.arb`。

---

## 前置：基準事實（執行前先確認，勿假設）

- `l10n.yaml` 的 `template-arb-file: app_zh.arb`，故 Flutter 只從 template 讀 placeholder metadata；locale 檔的 `@`-metadata 為結構對齊用。
- `app_zh.arb` 全部 placeholder 皆為簡單 `{name}` 代換，**無 ICU `plural`/`select`**。驗證只需比對 key 集合與 placeholder 名稱集合。
- `app_zh.arb` 為基準，**整個任務不得修改**它，也不得改其他語系檔（fr/es/pt/th/vi）與 `l10n.yaml`。
- 現有 `app_en.arb` / `app_ja.arb` 有人工譯文與 `localeTranslator` 掛名 → 保留沿用。`app_zh_Hans.arb` 的 `localeTranslator` 維持空字串 `""`。

---

### Task 1: 建立並鎖定官方術語表（glossary）

**Files:**
- Create: `docs/superpowers/i18n-glossary-2026-05-17.md`（gitignored，不進版控）

- [ ] **Step 1: 列出待查證詞條**

從 `app_zh.arb` 出現的遊戲專有名詞，至少涵蓋下列（全部都要查證，不只不確定者）：

```
祈願 / 角色活動祈願 / 武器活動祈願 / 集錄祈願 / 常駐祈願 / 新手祈願
頌願（活動頌願 / 常駐頌願）/ 保底 / 稀有度 / UID / 5★ 4★ 3★ 星級寫法
```

- [ ] **Step 2: 上網查證每個詞的 EN / JA / zh_Hans 官方 in-game 譯名**

對每個詞用 WebSearch，再用 WebFetch 取可靠來源內文。來源優先序：HoYoverse 官方公告／官方 wiki（hoyolab、genshin-impact 官方）→ Fandom Genshin Wiki（英日各語版）。重點查：
- `集錄祈願` → 預期 EN "Chronicled Wish"，JA 需確認（如「集録祈願」）。
- `頌願`（本 app 才有的較新玩法）→ EN/JA 官方名未知，**重點查證**。
- `常駐祈願` JA 官方（預期「通常祈願」非「常駐祈願」）。
- `新手祈願` EN（預期 "Novice Wishes"）、JA（預期「初心者向け祈願」）。
- `保底` EN（遊戲 UI 無 "pity"，社群慣用 Pity）、JA（社群／官方「天井」）。

- [ ] **Step 3: 寫定 glossary 表**

`docs/superpowers/i18n-glossary-2026-05-17.md` 寫成下表，每列附查證來源 URL；查不到可靠官方來源者，值寫「暫譯：<譯法>（待確認）」並在備註欄標明：

```markdown
| 繁中 | EN | JA | zh_Hans | 來源 | 備註 |
|---|---|---|---|---|---|
| 祈願 | ... | ... | 祈愿 | <url> | |
| 頌願 | ... | ... | 颂愿 | <url> | |
（涵蓋 Step 1 全部詞條）
```

- [ ] **Step 4: 鎖定**

確認表中每列三語皆已填（含「暫譯…（待確認）」）。此表為後續所有 Task 唯一術語依據，跨語言一致。Task 1 不改任何 `.arb`。

---

### Task 2: 寫一次性驗證腳本

**Files:**
- Create: `docs/superpowers/verify_arb_2026-05-17.py`（gitignored，不進版控）

- [ ] **Step 1: 寫腳本**

```python
"""比對 locale ARB 與 template app_zh.arb：key 集合、placeholder 名稱集合。
用法：python verify_arb_2026-05-17.py
回傳碼 0 = 全通過；非 0 = 有差異（細節印 stderr）。"""
import json, re, sys, pathlib

L10N = pathlib.Path(__file__).resolve().parents[2] / "lib" / "l10n"
TEMPLATE = "app_zh.arb"
TARGETS = ["app_zh_Hans.arb", "app_en.arb", "app_ja.arb"]
PH = re.compile(r"\{(\w+)\}")

def load(name):
    with open(L10N / name, encoding="utf-8") as f:
        return json.load(f)

def msg_keys(d):
    # 翻譯 key：非 @@locale、非 @-開頭、非 localeNativeName/localeTranslator
    skip = {"@@locale", "localeNativeName", "localeTranslator"}
    return {k for k in d if not k.startswith("@") and k not in skip}

def main():
    tpl = load(TEMPLATE)
    tpl_keys = msg_keys(tpl)
    tpl_ph = {k: set(PH.findall(str(tpl[k]))) for k in tpl_keys}
    ok = True
    for t in TARGETS:
        d = load(t)
        keys = msg_keys(d)
        missing = sorted(tpl_keys - keys)
        extra = sorted(keys - tpl_keys)
        if missing:
            ok = False; print(f"[{t}] 缺 key: {missing}", file=sys.stderr)
        if extra:
            ok = False; print(f"[{t}] 多餘 key: {extra}", file=sys.stderr)
        for k in tpl_keys & keys:
            got = set(PH.findall(str(d[k])))
            if got != tpl_ph[k]:
                ok = False
                print(f"[{t}] {k} placeholder 不符: 期望 {sorted(tpl_ph[k])} 得到 {sorted(got)}", file=sys.stderr)
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 對現況跑一次（預期 FAIL）**

Run: `python docs/superpowers/verify_arb_2026-05-17.py`
Expected: 印 `FAIL`，stderr 列出三檔目前缺漏 key（zh_Hans 缺 ~54、en 缺 ~27、ja 缺 ~224）。確認腳本能正確讀檔與偵測差異。

---

### Task 3: 重建 `app_zh_Hans.arb`

**Files:**
- Modify: `lib/l10n/app_zh_Hans.arb`（整檔重寫）
- Read: `lib/l10n/app_zh.arb`（取 key 順序與結構）、`docs/superpowers/i18n-glossary-2026-05-17.md`

- [ ] **Step 1: 取得 template 完整結構**

完整讀 `lib/l10n/app_zh.arb`，記下：每一行的順序、分組空行位置、每個 `@`-metadata 區塊內容。輸出檔將逐行鏡像此結構。

- [ ] **Step 2: 逐 key 決定 zh_Hans 值**

對 `app_zh.arb` 每個翻譯 key，依序：
1. 現有 `app_zh_Hans.arb` 已有此 key 且譯文正確 → 沿用該值。
2. 否則依繁中原文做**大陸在地化**新譯（非逐字繁→簡）：軟體→软件、網路→网络、資料→数据、帳號→账号、復原→撤销、專案→项目、檔案→文件、滑鼠→鼠标、預設→默认、登入→登录 等慣用語。
3. 凡含 glossary 詞條者，一律改用 glossary 的 zh_Hans 欄譯名（含對既有譯文回頭校正，例如把現有 `contributorsProjectLicense` 「专案许可证」校為「项目许可证」、`contributorsProjectLeader`「专案负责人」校為「项目负责人」）。
保留每個值內的 `{placeholder}` 名稱與原文完全一致；保留 `5★`/`4★`/`3★` 寫法。

- [ ] **Step 3: 寫出鏡像結構檔**

用 Write 整檔覆寫 `lib/l10n/app_zh_Hans.arb`：
- `"@@locale": "zh_Hans"`
- `"localeNativeName": "简体中文"`、`"localeTranslator": ""`
- 之後 259 個 key 依 `app_zh.arb` 完全相同順序與分組空行排列，`@`-metadata 區塊內容照抄 template。
- UTF-8、2-space 縮排、合法 JSON、結尾無 trailing comma。

- [ ] **Step 4: 驗證此檔結構**

Run: `python -c "import json; json.load(open('lib/l10n/app_zh_Hans.arb', encoding='utf-8')); print('JSON OK')"`
Expected: `JSON OK`（JSON 合法）。

- [ ] **Step 5: 暫不 commit**

三檔全部完成後於 Task 6 統一驗證並一次 commit。此步不做 git 操作。

---

### Task 4: 重建 `app_en.arb`

**Files:**
- Modify: `lib/l10n/app_en.arb`（整檔重寫）
- Read: `lib/l10n/app_zh.arb`、`docs/superpowers/i18n-glossary-2026-05-17.md`、現有 `lib/l10n/app_en.arb`（取既有人工譯與譯者掛名）

- [ ] **Step 1: 取既有人工譯與掛名**

完整讀現有 `lib/l10n/app_en.arb`，記下 `localeTranslator` 值（如 `"Zanah_68, pan93412, Lemon7777"`）與每個既有 key 的英文譯文。

- [ ] **Step 2: 逐 key 決定 en 值**

對 `app_zh.arb` 每個翻譯 key：
1. 現有 `app_en.arb` 有此 key 且譯文正確 → 沿用。
2. 否則依繁中原文做自然英文 UI 新譯：sentence case、與既有英文風格一致、簡潔。
3. 凡含 glossary 詞條者一律用 glossary 的 EN 欄譯名（含回頭校正既有譯文中的遊戲術語使其與 glossary 一致）。
保留 `{placeholder}` 名稱與 `5★` 等寫法不變。

- [ ] **Step 3: 寫出鏡像結構檔**

用 Write 整檔覆寫 `lib/l10n/app_en.arb`：
- `"@@locale": "en"`、`"localeNativeName": "English"`
- `"localeTranslator"` = Step 1 取得的既有掛名值（原樣保留）。
- 259 個 key 依 `app_zh.arb` 順序與分組空行排列，`@`-metadata 照抄 template。
- UTF-8、2-space 縮排、合法 JSON、無 trailing comma。

- [ ] **Step 4: 驗證此檔結構**

Run: `python -c "import json; json.load(open('lib/l10n/app_en.arb', encoding='utf-8')); print('JSON OK')"`
Expected: `JSON OK`

- [ ] **Step 5: 暫不 commit**（同 Task 3 Step 5）

---

### Task 5: 重建 `app_ja.arb`

**Files:**
- Modify: `lib/l10n/app_ja.arb`（整檔重寫）
- Read: `lib/l10n/app_zh.arb`、`docs/superpowers/i18n-glossary-2026-05-17.md`、現有 `lib/l10n/app_ja.arb`（取既有人工譯與譯者掛名）

- [ ] **Step 1: 取既有人工譯與掛名**

完整讀現有 `lib/l10n/app_ja.arb`，記下 `localeTranslator` 值（含其中的 HTML `<a>` 連結，原樣保留）與既有 35 個 key 的日文譯文。

- [ ] **Step 2: 逐 key 決定 ja 值**

對 `app_zh.arb` 每個翻譯 key：
1. 現有 `app_ja.arb` 有此 key 且譯文正確 → 沿用。
2. 否則依繁中原文做自然日文 UI 新譯：日文 UI 慣用語與助詞，數字／`{placeholder}` 與單位（抽→回、件 等）間距符合日文排版慣例。
3. 凡含 glossary 詞條者一律用 glossary 的 JA 欄譯名（保底→天井 等；含回頭校正既有譯文使其與 glossary 一致）。
保留 `{placeholder}` 名稱與 `5★` 等寫法不變。

- [ ] **Step 3: 寫出鏡像結構檔**

用 Write 整檔覆寫 `lib/l10n/app_ja.arb`：
- `"@@locale": "ja"`、`"localeNativeName": "日本語"`
- `"localeTranslator"` = Step 1 既有掛名值（含 HTML 連結原樣保留）。
- 259 個 key 依 `app_zh.arb` 順序與分組空行排列，`@`-metadata 照抄 template。
- UTF-8、2-space 縮排、合法 JSON、無 trailing comma。

- [ ] **Step 4: 驗證此檔結構**

Run: `python -c "import json; json.load(open('lib/l10n/app_ja.arb', encoding='utf-8')); print('JSON OK')"`
Expected: `JSON OK`

- [ ] **Step 5: 暫不 commit**（同 Task 3 Step 5）

---

### Task 6: 全量驗證、品質檢查、提交

**Files:**
- Read: 三個 `lib/l10n/app_*.arb`

- [ ] **Step 1: 跑一次性比對腳本**

Run: `python docs/superpowers/verify_arb_2026-05-17.py`
Expected: 印 `PASS`，回傳碼 0（三檔 key 集合 == app_zh、placeholder 名稱集合一致、無多無缺）。FAIL 則依 stderr 修對應檔後重跑。

- [ ] **Step 2: 格式化**

Run: `dart format lib/ test/`
Expected: 正常結束（勿對 `.` 跑，避免動到 `rust_builder/`）。

- [ ] **Step 3: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`（gen-l10n 重新產碼後無錯）。

- [ ] **Step 4: 測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: 任一失敗先修**

Step 1–4 任一未達預期，定位並修正對應 `.arb`（不可改 `app_zh.arb`、不可 `--no-verify`），回 Step 1 重跑全序列直到全綠。

- [ ] **Step 6: Commit（僅三個 arb 檔）**

```bash
git add lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/app_ja.arb
git commit -m "feat(i18n): complete zh_Hans/en/ja translations mirroring app_zh template

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

不 git add `docs/superpowers/` 下任何檔（glossary、腳本、plan、spec 皆 gitignored）。

---

## Self-Review

**Spec coverage：**
- 三檔完整重建 259 key、鏡像結構 → Task 3/4/5 Step 3。
- @-metadata 鏡像 template → Task 3/4/5 Step 3 明列照抄。
- 值來源優先序（現有正確人工譯 → 本地化新譯 → glossary 校正）→ Task 3/4/5 Step 2。
- 不沿用 master 舊譯 mining → 計畫無此步，且「不做 YAGNI」一致。
- 術語表全查證後鎖定 → Task 1。
- 在地化要求（zh_Hans 大陸用語、ja 助詞排版、en sentence case）→ Task 3/4/5 Step 2 各列具體規則。
- localeTranslator 處理（en/ja 保留、zh_Hans 空）→ Task 3/4/5 Step 3。
- 驗證（format/analyze/test + 比對腳本零差異）→ Task 6。
- 不進版控慣例 → 標於 header 與 Task 6 Step 6。

**Placeholder scan：** 無 TBD/TODO；glossary 的「暫譯（待確認）」是 spec 明定的查證產物，非計畫佔位；驗證腳本為完整可執行碼。

**Type consistency：** 驗證腳本 `msg_keys` 排除規則與 spec「排除 @@locale/@-meta/localeNativeName/localeTranslator」一致；三檔目標清單與檔名跨 Task 一致。

無待修項。
