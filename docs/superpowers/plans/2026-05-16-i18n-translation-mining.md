# 舊版翻譯挖掘對照報告 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 寫一支獨立 Python 腳本，比對 `app_zh.arb` 與舊版 `master:src/locales/zh_TW.json` 的中文原文，產出 7 語言的翻譯候選對照 Markdown 報告（不修改任何 ARB）。

**Architecture:** 純標準庫 Python。以「新版中文值 == 舊 zh_TW 值」為橋樑做 exact / 正規化兩階比對；命中後從 7 個舊語言檔取譯文，附信心階與旗標寫入報告。所有舊檔經 `git show` 讀取，不動工作區。

**Tech Stack:** Python 3（stdlib `json` / `subprocess` / `unittest` / `re`）。

**重要慣例：** `docs/superpowers/` 已被 git ignore（已驗證 `git check-ignore docs/superpowers` 回傳路徑）。本計畫**不含任何 git commit 步驟**，也不得 `git add` 這些檔案。測試框架用 stdlib `unittest`（零第三方依賴，與腳本一致）。

**TDD 注意：** 測試需讀真實檔案（`lib/l10n/app_zh.arb` 與 `git show master:...`），故純函式（normalize / 索引 / 比對 / 旗標）用合成資料做單元測試；I/O 與報告產出做一次整合冒煙測試。

---

## File Structure

- Create: `docs/superpowers/i18n-migration/extract_candidates.py` — 全部邏輯與 `main()`
- Create: `docs/superpowers/i18n-migration/test_extract_candidates.py` — `unittest` 測試
- Generated（執行產出，非手寫）：`docs/superpowers/i18n-migration/translation-candidates.md`

純函式（可獨立測試）：
- `normalize(s) -> str`
- `placeholder_names(s) -> set[str]`
- `is_icu_complex(s) -> bool`
- `load_arb_zh(text) -> dict`（吃檔案內容字串，便於測試）
- `build_index(zh_tw) -> tuple[dict, dict]`（exact 與 normalized 反向索引）
- `match_key(zh_value, exact_idx, norm_idx) -> (oldkeys, confidence)`
- `render_report(model) -> str`

I/O 殼層：`read_old_json(locale)`（git show）、`main()`。

---

### Task 1: normalize() — 正規化規則

**Files:**
- Create: `docs/superpowers/i18n-migration/extract_candidates.py`
- Test: `docs/superpowers/i18n-migration/test_extract_candidates.py`

- [ ] **Step 1: 寫失敗測試**

```python
# test_extract_candidates.py
import unittest
from extract_candidates import normalize


class TestNormalize(unittest.TestCase):
    def test_trims_whitespace(self):
        self.assertEqual(normalize("  你好  "), "你好")

    def test_unifies_fullwidth_punctuation(self):
        # 全形冒號/驚嘆號/括號/引號 → 半形
        self.assertEqual(normalize("最後更新："), normalize("最後更新:"))
        self.assertEqual(normalize("成功！"), normalize("成功!"))
        self.assertEqual(normalize("（活躍）"), normalize("(活躍)"))
        self.assertEqual(normalize("「取消」"), normalize('"取消"'))

    def test_placeholders_positionalized(self):
        self.assertEqual(
            normalize("正在抓取：{name}"),
            normalize("正在抓取:{gacha_name}"),
        )

    def test_does_not_unify_semantic_differences(self):
        # 5★ 與 5星 屬語義層，不可被正規化抹平
        self.assertNotEqual(normalize("5★ 件數"), normalize("5星 件數"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `python -m unittest -v` （cwd = `docs/superpowers/i18n-migration/`）
Expected: FAIL — `ModuleNotFoundError` 或 `ImportError: cannot import name 'normalize'`

- [ ] **Step 3: 實作 normalize**

```python
# extract_candidates.py
import re

_FULL_TO_HALF = {
    "：": ":", "！": "!", "？": "?", "，": ",", "；": ";",
    "（": "(", "）": ")", "「": '"', "」": '"',
    "『": '"', "』": '"', "【": "[", "】": "]",
    "～": "~", "、": ",",
}
_PLACEHOLDER_RE = re.compile(r"\{[^{}]*\}")


def normalize(s: str) -> str:
    s = s.strip()
    for full, half in _FULL_TO_HALF.items():
        s = s.replace(full, half)
    s = _PLACEHOLDER_RE.sub("{}", s)
    return s
```

- [ ] **Step 4: 跑測試確認通過**

Run: `python -m unittest -v`
Expected: PASS（`TestNormalize` 全綠）

---

### Task 2: placeholder_names() 與 is_icu_complex()

**Files:**
- Modify: `docs/superpowers/i18n-migration/extract_candidates.py`
- Test: `docs/superpowers/i18n-migration/test_extract_candidates.py`

- [ ] **Step 1: 寫失敗測試**

```python
from extract_candidates import placeholder_names, is_icu_complex


class TestPlaceholders(unittest.TestCase):
    def test_extracts_simple_names(self):
        self.assertEqual(
            placeholder_names("第 {page} 頁，已新增 {count} 筆"),
            {"page", "count"},
        )

    def test_empty_when_none(self):
        self.assertEqual(placeholder_names("取消"), set())

    def test_icu_argument_name_only(self):
        # ICU 複數：取得引數名 count，而非整段
        self.assertEqual(
            placeholder_names("{count, plural, =1{1 秒} other{{count} 秒}}"),
            {"count"},
        )


class TestIcuComplex(unittest.TestCase):
    def test_plural_is_complex(self):
        self.assertTrue(is_icu_complex("{count, plural, =1{a} other{b}}"))

    def test_select_is_complex(self):
        self.assertTrue(is_icu_complex("{g, select, male{他} other{他}}"))

    def test_simple_placeholder_not_complex(self):
        self.assertFalse(is_icu_complex("已新增 {count} 筆"))
        self.assertFalse(is_icu_complex("取消"))
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `python -m unittest -v`
Expected: FAIL — `ImportError: cannot import name 'placeholder_names'`

- [ ] **Step 3: 實作**

```python
# extract_candidates.py 追加
_ICU_COMPLEX_RE = re.compile(r"\{\s*\w+\s*,\s*(plural|select|selectordinal)\s*,")
_ARG_NAME_RE = re.compile(r"\{\s*(\w+)")


def is_icu_complex(s: str) -> bool:
    return _ICU_COMPLEX_RE.search(s) is not None


def placeholder_names(s: str) -> set[str]:
    return {m.group(1) for m in _ARG_NAME_RE.finditer(s)}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `python -m unittest -v`
Expected: PASS（注意 `placeholder_names` 對 ICU 段會回傳 `{count}`，符合測試預期；`other{{count} 秒}}` 內層 `{count}` 亦被 `_ARG_NAME_RE` 抓到同名，集合去重後仍為 `{"count"}`）

---

### Task 3: load_arb_zh() — 解析 app_zh.arb 並過濾

**Files:**
- Modify: `docs/superpowers/i18n-migration/extract_candidates.py`
- Test: `docs/superpowers/i18n-migration/test_extract_candidates.py`

- [ ] **Step 1: 寫失敗測試**

```python
from extract_candidates import load_arb_zh


class TestLoadArbZh(unittest.TestCase):
    def test_filters_meta_and_locale_keys(self):
        text = """{
          "@@locale": "zh",
          "localeNativeName": "繁體中文",
          "localeTranslator": "",
          "actionCancel": "取消",
          "@actionCancel": { "description": "x" },
          "footerLastUpdated": "最後更新：{time}",
          "@footerLastUpdated": { "placeholders": {} }
        }"""
        result = load_arb_zh(text)
        self.assertEqual(
            result,
            {"actionCancel": "取消", "footerLastUpdated": "最後更新：{time}"},
        )
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `python -m unittest -v`
Expected: FAIL — `ImportError: cannot import name 'load_arb_zh'`

- [ ] **Step 3: 實作**

```python
# extract_candidates.py 追加
import json

_EXCLUDED_KEYS = {"@@locale", "localeNativeName", "localeTranslator"}


def load_arb_zh(text: str) -> dict[str, str]:
    raw = json.loads(text)
    return {
        k: v
        for k, v in raw.items()
        if not k.startswith("@") and k not in _EXCLUDED_KEYS
    }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `python -m unittest -v`
Expected: PASS

---

### Task 4: build_index() 與 match_key() — 兩階比對

**Files:**
- Modify: `docs/superpowers/i18n-migration/extract_candidates.py`
- Test: `docs/superpowers/i18n-migration/test_extract_candidates.py`

- [ ] **Step 1: 寫失敗測試**

```python
from extract_candidates import build_index, match_key


class TestMatching(unittest.TestCase):
    def setUp(self):
        self.zh_tw = {
            "ui.text.cancel": "取消",
            "ui.text.paginate.previous": "上一頁",
            "ui.text.table.previous": "上一頁",
            "ui.text.footer": "最後更新：{time}",
        }
        self.exact_idx, self.norm_idx = build_index(self.zh_tw)

    def test_exact_match_high(self):
        keys, conf = match_key("取消", self.exact_idx, self.norm_idx)
        self.assertEqual(conf, "high")
        self.assertEqual(keys, ["ui.text.cancel"])

    def test_collision_lists_all_oldkeys(self):
        keys, conf = match_key("上一頁", self.exact_idx, self.norm_idx)
        self.assertEqual(conf, "high")
        self.assertEqual(
            sorted(keys),
            ["ui.text.paginate.previous", "ui.text.table.previous"],
        )

    def test_normalized_match_medium(self):
        # 新版用半形冒號 + 不同 placeholder 名
        keys, conf = match_key(
            "最後更新:{lastTime}", self.exact_idx, self.norm_idx
        )
        self.assertEqual(conf, "medium")
        self.assertEqual(keys, ["ui.text.footer"])

    def test_no_match_returns_none(self):
        keys, conf = match_key("不存在的句子", self.exact_idx, self.norm_idx)
        self.assertEqual(conf, None)
        self.assertEqual(keys, [])
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `python -m unittest -v`
Expected: FAIL — `ImportError: cannot import name 'build_index'`

- [ ] **Step 3: 實作**

```python
# extract_candidates.py 追加
from collections import defaultdict


def build_index(zh_tw: dict[str, str]):
    exact_idx: dict[str, list[str]] = defaultdict(list)
    norm_idx: dict[str, list[str]] = defaultdict(list)
    for old_key, value in zh_tw.items():
        exact_idx[value].append(old_key)
        norm_idx[normalize(value)].append(old_key)
    return dict(exact_idx), dict(norm_idx)


def match_key(zh_value: str, exact_idx, norm_idx):
    if zh_value in exact_idx:
        return sorted(exact_idx[zh_value]), "high"
    n = normalize(zh_value)
    if n in norm_idx:
        return sorted(norm_idx[n]), "medium"
    return [], None
```

- [ ] **Step 4: 跑測試確認通過**

Run: `python -m unittest -v`
Expected: PASS（4 測試全綠）

---

### Task 5: render_report() — Markdown 產出

**Files:**
- Modify: `docs/superpowers/i18n-migration/extract_candidates.py`
- Test: `docs/superpowers/i18n-migration/test_extract_candidates.py`

報告資料模型（`main()` 組裝後傳入 `render_report`）：

```python
# 每筆候選 = dict:
# {
#   "lang": "es",
#   "new_key": "footerLastUpdated",
#   "zh": "最後更新：{time}",
#   "old_translation": "Ultima actualizacion: {time}",
#   "new_current": "",            # 新版現值，空字串=空缺
#   "confidence": "high"|"medium",
#   "old_keys": ["ui.text.footer"],
#   "flags": ["⬜","🟢", ...],   # 已由 main 算好
# }
# model = {"es": [候選...], "th": [...], ...}  依語言固定順序
```

- [ ] **Step 1: 寫失敗測試**

```python
from extract_candidates import render_report


class TestRenderReport(unittest.TestCase):
    def test_groups_by_lang_and_has_table_row(self):
        model = {
            "es": [
                {
                    "lang": "es", "new_key": "actionCancel", "zh": "取消",
                    "old_translation": "Cancelar", "new_current": "",
                    "confidence": "high", "old_keys": ["ui.text.cancel"],
                    "flags": ["🟢", "⬜"],
                }
            ],
            "th": [],
        }
        out = render_report(model)
        self.assertIn("## es", out)
        self.assertIn("## th", out)
        self.assertIn("| actionCancel |", out)
        self.assertIn("Cancelar", out)
        self.assertIn("ui.text.cancel", out)
        # 空語言組要有「無候選」字樣，不可整段消失
        self.assertIn("無候選", out)
        # 組末統計
        self.assertIn("可填補", out)
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `python -m unittest -v`
Expected: FAIL — `ImportError: cannot import name 'render_report'`

- [ ] **Step 3: 實作**

```python
# extract_candidates.py 追加
LANG_ORDER = ["es", "th", "ja", "zh_Hans", "fr", "pt", "vi"]


def _esc(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", " ")


def render_report(model: dict[str, list[dict]]) -> str:
    lines = ["# 舊版翻譯候選對照報告", ""]
    for lang in LANG_ORDER:
        rows = model.get(lang, [])
        lines.append(f"## {lang}")
        lines.append("")
        if not rows:
            lines.append("_無候選_")
            lines.append("")
            continue
        lines.append(
            "| 新 key | 中文原文 | 舊翻譯候選 | 新版現值 | 信心 | 舊 oldKey 路徑 | 旗標 |"
        )
        lines.append("|---|---|---|---|---|---|---|")
        fillable = high = ph = icu = 0
        for r in rows:
            if r["new_current"] == "":
                fillable += 1
            if r["confidence"] == "high":
                high += 1
            if "⚠️PH" in r["flags"]:
                ph += 1
            if "⚠️ICU" in r["flags"]:
                icu += 1
            lines.append(
                "| {k} | {zh} | {ot} | {nc} | {cf} | {ok} | {fl} |".format(
                    k=_esc(r["new_key"]),
                    zh=_esc(r["zh"]),
                    ot=_esc(r["old_translation"]),
                    nc=_esc(r["new_current"]) or "_(空)_",
                    cf=r["confidence"],
                    ok=_esc(", ".join(r["old_keys"])),
                    fl=" ".join(r["flags"]),
                )
            )
        lines.append("")
        lines.append(
            f"**統計** — 可填補 {fillable} / 高信心 {high} / "
            f"需手改 placeholder {ph} / 需手改 ICU {icu}（共 {len(rows)} 筆）"
        )
        lines.append("")
    return "\n".join(lines)
```

- [ ] **Step 4: 跑測試確認通過**

Run: `python -m unittest -v`
Expected: PASS（全部 task 1-5 測試綠）

---

### Task 6: I/O 殼層 + main()，排序與旗標組裝

**Files:**
- Modify: `docs/superpowers/i18n-migration/extract_candidates.py`

旗標規則（`main()` 內，對每筆候選計算 `flags` list）：
- `confidence=="high"` → `🟢`，`"medium"` → `🟡`
- `new_current==""` → `⬜`，否則 → `📝`
- 新版 zh 值 `is_icu_complex` 為真 → `⚠️ICU`
- 新版 zh placeholder 名 != 舊 zh_TW 對應 oldKey 的 placeholder 名 → `⚠️PH`
- `len(old_keys) > 1` → `🔀`

排序（每語言組內）：先 `new_current==""`（空缺優先），再 `confidence`（high 先 medium 後），最後 `new_key` 字母序。

- [ ] **Step 1: 實作 I/O 與 main**

```python
# extract_candidates.py 追加
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]  # docs/superpowers/i18n-migration → repo root
ARB_DIR = REPO / "lib" / "l10n"
OLD_LOCALE = {
    "es": "es_ES", "th": "th_TH", "ja": "ja_JP", "zh_Hans": "zh_CN",
    "fr": "fr_FR", "pt": "pt_BR", "vi": "vi_VN",
}
OUT = Path(__file__).resolve().parent / "translation-candidates.md"


def read_old_json(locale_file: str) -> dict[str, str]:
    raw = subprocess.run(
        ["git", "show", f"master:src/locales/{locale_file}.json"],
        cwd=REPO, capture_output=True, text=True, encoding="utf-8", check=True,
    ).stdout
    return json.loads(raw)


def _flags(conf, new_current, zh_value, new_ph, old_ph, n_oldkeys):
    f = []
    f.append("🟢" if conf == "high" else "🟡")
    f.append("⬜" if new_current == "" else "📝")
    if is_icu_complex(zh_value):
        f.append("⚠️ICU")
    if new_ph != old_ph:
        f.append("⚠️PH")
    if n_oldkeys > 1:
        f.append("🔀")
    return f


def main() -> int:
    zh_arb = load_arb_zh((ARB_DIR / "app_zh.arb").read_text(encoding="utf-8"))
    zh_tw = read_old_json("zh_TW")
    exact_idx, norm_idx = build_index(zh_tw)
    # oldKey → 該 oldKey 在 zh_TW 的 placeholder 名（取第一個命中 oldKey 即可）
    old_ph_by_key = {k: placeholder_names(v) for k, v in zh_tw.items()}

    old_lang_data = {}
    for lang, lf in OLD_LOCALE.items():
        try:
            old_lang_data[lang] = read_old_json(lf)
        except subprocess.CalledProcessError:
            old_lang_data[lang] = {}

    model: dict[str, list[dict]] = {lang: [] for lang in OLD_LOCALE}
    for new_key, zh_value in zh_arb.items():
        old_keys, conf = match_key(zh_value, exact_idx, norm_idx)
        if conf is None:
            continue
        new_ph = placeholder_names(zh_value)
        old_ph = set()
        for ok in old_keys:
            old_ph |= old_ph_by_key.get(ok, set())
        for lang, lf in OLD_LOCALE.items():
            old_map = old_lang_data[lang]
            translation = None
            for ok in old_keys:
                v = old_map.get(ok)
                if v:  # 非 None 且非空字串
                    translation = v
                    break
            if not translation:
                continue
            new_current_map = json.loads(
                (ARB_DIR / f"app_{lang}.arb").read_text(encoding="utf-8")
            )
            new_current = new_current_map.get(new_key, "")
            if not isinstance(new_current, str):
                new_current = ""
            model[lang].append({
                "lang": lang, "new_key": new_key, "zh": zh_value,
                "old_translation": translation, "new_current": new_current,
                "confidence": conf, "old_keys": old_keys,
                "flags": _flags(conf, new_current, zh_value,
                                new_ph, old_ph, len(old_keys)),
            })

    order = {"high": 0, "medium": 1}
    for lang in model:
        model[lang].sort(key=lambda r: (
            r["new_current"] != "",            # 空缺優先
            order[r["confidence"]],            # high 先
            r["new_key"],
        ))

    OUT.write_text(render_report(model), encoding="utf-8")
    for lang in LANG_ORDER:
        rows = model.get(lang, [])
        fillable = sum(1 for r in rows if r["new_current"] == "")
        print(f"{lang:8s}: {len(rows):3d} 候選 / {fillable:3d} 可填補")
    print(f"\n報告已寫入 {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: 全測試回歸**

Run: `python -m unittest -v`（cwd = `docs/superpowers/i18n-migration/`）
Expected: PASS（task 1-5 全綠，main 未被單元測試覆蓋，下一步整合驗證）

---

### Task 7: 整合冒煙驗證

**Files:** 無（執行驗證）

- [ ] **Step 1: 跑真實資料**

Run（cwd = repo root）：
`python docs/superpowers/i18n-migration/extract_candidates.py`
Expected：終端印出 7 語言摘要（每行 `候選 / 可填補`），結尾 `報告已寫入 ...`，exit 0，無 traceback。

- [ ] **Step 2: 抽查報告內容**

Run: `python -c "import pathlib;t=pathlib.Path('docs/superpowers/i18n-migration/translation-candidates.md').read_text(encoding='utf-8');print(len(t),'chars');print(t[:1500])"`
Expected：含 `## es` 等 7 個語言標題、表格表頭 `| 新 key |`、至少 es 組有資料列。

- [ ] **Step 3: 健全性人工檢查**

打開 `translation-candidates.md`，確認：
- `actionCancel`（中文「取消」）在 es 組對到合理西語譯文
- 含 placeholder 的句子（如 `footerLastUpdated`）有 `⚠️PH` 旗標（舊 `{time}` 名稱可能不同）
- 複數 key（如 `relativeSecondsAgo`，新版 ICU）若命中則帶 `⚠️ICU`
- 空語言組顯示 `_無候選_` 而非整段消失

若任一不符 → 回對應 Task 修純函式後重跑 Task 7。

---

## Self-Review

**Spec coverage：**
- 比對引擎兩階 → Task 1（normalize）、Task 4（build_index/match_key）✅
- 排除 @meta/@@locale/localeNativeName/localeTranslator → Task 3 ✅
- 7 語言、固定順序 → Task 5 `LANG_ORDER`、Task 6 `OLD_LOCALE` ✅
- 旗標 🟢🟡⚠️PH⚠️ICU⬜📝🔀 → Task 6 `_flags` ✅
- oldKey 路徑欄 + 撞中文 🔀 → Task 5 表格 + Task 6 ✅
- 報告排序（空缺→信心→key）→ Task 6 sort ✅
- git show 讀舊檔不動工作區 → Task 6 `read_old_json` ✅
- 缺失/空字串該語言不列 → Task 6 `if not translation: continue` ✅
- 查無中文不出現 → Task 6 `if conf is None: continue` ✅
- 不改 ARB → 全程唯一寫檔為 `OUT`（報告）✅
- 不進版控 → 計畫明示無 commit 步驟，目錄已 gitignore ✅

**Placeholder scan：** 無 TBD/TODO；每個 code step 均含完整程式碼。

**Type consistency：** `match_key` 回傳 `(list, conf|None)` 全程一致；`model` 結構在 Task 5 註解定義、Task 6 組裝、Task 5 render 消費，欄位名一致（`new_key`/`old_translation`/`new_current`/`confidence`/`old_keys`/`flags`）；旗標 sentinel `⚠️PH`/`⚠️ICU` 在 `_flags` 產生、`render_report` 統計時比對，字串一致。

**REPO 路徑：** `Path(__file__).resolve().parents[3]` — 檔案在 `repo/docs/superpowers/i18n-migration/extract_candidates.py`，parents[0]=i18n-migration, [1]=superpowers, [2]=docs, [3]=repo root ✅
