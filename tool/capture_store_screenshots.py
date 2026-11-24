"""在 Android 模擬器上拍 Play 商店截圖（也是 README 的 Android 截圖）。

每個語言 × 裝置拍 8 張，依序是：綜合、角色活動、時間軸與 5★ 一覽、武器活動、物品詳情、
分享圖設定、等待開啟祈願歷史記錄頁、設定。輸出到
`docs/images/play-store/screenshots/<語言>/<裝置>/1–8.png`（24 位元 PNG，無 alpha）。
規格與拍法的來龍去脈見鳴潮專案 `docs/Android移植筆記.md` 第 54 節。

事前準備（腳本不會幫你做）：
  1. 只開一台模擬器（adb 只看得到它；還連著其他裝置時先設 `ANDROID_SERIAL`），裝好除錯版或 profile 版 App。
     其他自動化工具（例如 agent-device）要先關掉，否則 `uiautomator dump` 讀不到畫面。
  2. 用電腦版「匯出資料」→ 推到模擬器 →「匯入資料」，切到要拍的帳號，並在設定頁打開「遮蔽介面中的 UID」。
  3. 系統是深色主題、App 的外觀是「跟隨系統」。
  4. 已在 App 裡設定好無線偵錯讀取方式（配對過），等待畫面才會出現。
  5. 模擬器上要有 `com.miHoYo.GenshinImpact` 套件（可用 aapt2 做一個只有 LAUNCHER activity 的空殼），
     不然等待畫面會變成「找不到遊戲」。
  6. 存過的網址（`<UID>.cred.json`）過期時，等待畫面會多一行提示；模擬器上沒有存網址就不會。

用法：
  python tool/capture_store_screenshots.py                        # 四種語言 × 四種裝置
  python tool/capture_store_screenshots.py --langs en --devices phone tablet-10

拍完會還原解析度、密度、Wi-Fi、通知橫幅與狀態列，App 語言改回開始前的設定；資料語言停在最後拍的語言。
"""

import argparse
import html
import io
import json
import os
import re
import subprocess
import time
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / 'docs' / 'images' / 'play-store' / 'screenshots'
PKG = 'tw.reh.genshin.gacha'
GAME_PKG = 'com.miHoYo.GenshinImpact'

# 商店語言資料夾 → (ARB 檔, App 語言, 資料語言選單上的名稱, 詳情要打開的角色)
LANGS = {
    'zh-TW': ('app_zh', 'zh-Hant', '繁體中文', '薇斯納'),
    'en': ('app_en', 'en', 'English', 'Vesna'),
    'ja': ('app_ja', 'ja', '日本語', 'ヴェスナ'),
    'zh-CN': ('app_zh_Hans', 'zh-Hans', '简体中文', '薇斯纳'),
}
# 裝置資料夾 → (wm size, wm density)；Play 平板與 Chromebook 要 16:9、手機 9:16
DEVICES = {
    'phone': ('1080x1920', 420),
    'tablet-7': ('1920x1080', 280),
    'tablet-10': ('2560x1440', 288),
    'chromebook': ('2560x1440', 213),
}
# 平板與 Chromebook 的側欄項目沒有無障礙文字，只能點座標（綜合、角色活動、武器活動、設定）。
# shortcut: 座標是照目前側欄版面量的，側欄改版或換尺寸參數就要重量
RAIL = {
    'tablet-7': [(62, 210), (62, 368), (62, 478), (62, 872)],
    'tablet-10': [(150, 203), (150, 333), (150, 419), (120, 1246)],
    'chromebook': [(96, 150), (113, 246), (113, 310), (82, 1297)],
}
MENU = r'^(開啟導覽選單|Open navigation menu|ナビゲーション メニューを開く|打开导航菜单)$'
NOW = r'^(現在|Now|现在) '  # 時間軸最左邊的「現在」節點；時間軸標題被併進大元件，無法單獨定位
VALIDATOR_BLUE = (26, 115, 232)  # AdMob 原生廣告驗證器 Dismiss 按鈕的顏色
ORDER = ['O', 'C', 'T', 'Wp', 'D', 'Sh', 'W', 'St']


def adb(*args, binary=False):
    """執行 adb 指令並回傳輸出。"""
    r = subprocess.run(['adb', *args], capture_output=True, env=dict(os.environ, MSYS_NO_PATHCONV='1'))
    return r.stdout if binary else r.stdout.decode('utf-8', 'replace')


def screencap():
    """抓目前畫面；偶爾會抓到空資料，重試幾次。"""
    for _ in range(5):
        data = adb('exec-out', 'screencap', '-p', binary=True)
        try:
            return Image.open(io.BytesIO(data)).convert('RGB')
        except Exception:
            time.sleep(1)
    raise SystemExit('screencap failed')


def nodes():
    """用 uiautomator 讀畫面上的元件：[(文字或描述, (x1, y1, x2, y2))]。"""
    adb('shell', 'uiautomator', 'dump', '/sdcard/ui.xml')
    out = []
    for m in re.finditer(r'<node [^>]*>', adb('shell', 'cat', '/sdcard/ui.xml')):
        n = m.group(0)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        for attr in ('text', 'content-desc'):
            v = re.search(attr + r'="([^"]*)"', n)
            if b and v and v.group(1):
                out.append((html.unescape(v.group(1)).replace('\n', ' '), tuple(map(int, b.groups()))))
    return out


def press(x, y, wait):
    """點座標後等一下。"""
    adb('shell', 'input', 'tap', str(x), str(y))
    time.sleep(wait)


def tap(pattern, wait=2.0):
    """點第一個文字符合 pattern 的元件。"""
    hits = [b for l, b in nodes() if re.search(pattern, l)]
    if not hits:
        raise SystemExit(f'not found: {pattern}')
    x1, y1, x2, y2 = hits[0]
    press((x1 + x2) // 2, (y1 + y2) // 2, wait)


def tap_avatar(name, wait):
    """點時間軸上露出最寬的那個角色節點的頭像一帶（節點下半部是空白，點了沒反應）。"""
    hits = [b for l, b in nodes() if name in l]
    if not hits:
        raise SystemExit(f'not found: {name}')
    x1, y1, x2, y2 = max(hits, key=lambda b: b[2] - b[0])
    press((x1 + x2) // 2, y1 + (y2 - y1) * 2 // 5, wait)


def exact(s):
    """完全相符的 regex。"""
    return '^' + re.escape(s) + '$'


def strings(arb_file):
    """讀 ARB 字串（缺的 key 由繁中補）。"""
    base = json.loads((REPO / 'lib/l10n/app_zh.arb').read_text('utf-8'))
    base.update(json.loads((REPO / f'lib/l10n/{arb_file}.arb').read_text('utf-8')))
    return base


def screen_size():
    """目前畫面寬高。"""
    s = adb('shell', 'wm', 'size')
    m = re.search(r'Override size: (\d+)x(\d+)', s) or re.search(r'Physical size: (\d+)x(\d+)', s)
    return int(m.group(1)), int(m.group(2))


def demo_mode():
    """狀態列展示模式：12:00、電量滿、只顯示 Wi-Fi、不顯示通知圖示。"""
    adb('shell', 'settings', 'put', 'global', 'sysui_demo_allowed', '1')
    adb('shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', 'exit')
    for c in (['enter'], ['clock', '-e', 'hhmm', '1200'], ['battery', '-e', 'level', '100', '-e', 'plugged', 'false'],
              ['network', '-e', 'wifi', 'show', '-e', 'level', '4', '-e', 'fully', 'true', '-e', 'mobile', 'hide',
               '-e', 'airplane', 'hide', '-e', 'nosim', 'hide'], ['notifications', '-e', 'visible', 'false']):
        adb('shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', *c)
    time.sleep(1)


def restart_app():
    """重開 App 並重設狀態列。"""
    adb('shell', 'am', 'force-stop', PKG)
    adb('shell', 'am', 'start', '-n', f'{PKG}/.MainActivity')
    time.sleep(7)
    demo_mode()


def dismiss_validator():
    """關掉 AdMob 驗證器提示：從截圖找它的藍色 Dismiss 按鈕（平板上讀不到它的文字）。"""
    for _ in range(3):
        a = np.asarray(screencap()).astype(int)
        m = np.all(np.abs(a - VALIDATOR_BLUE) < 6, axis=-1)
        ys, xs = m.nonzero()
        if len(xs) < 2000:
            return
        press(int(xs.mean()), int(ys.mean()), 1.2)


def scroll_to(pattern, frac):
    """慢速拖曳，讓符合 pattern 的元件頂端停在畫面高度 frac 處；20px 內的拖曳會被當成點擊，所以容許 40px 誤差。"""
    w, h = screen_size()
    for _ in range(6):
        hit = [b for l, b in nodes() if re.search(pattern, l)]
        step = h // 2
        if hit:
            dy = hit[0][1] - int(h * frac)
            if abs(dy) < 40:
                return
            step = max(-h // 2, min(h // 2, dy))
        y0 = h * 3 // 4 if step > 0 else h // 4
        adb('shell', 'input', 'swipe', str(w // 2), str(y0), str(w // 2), str(y0 - step), '1500')
        time.sleep(1.2)
    if not any(re.search(pattern, l) for l, _ in nodes()):
        raise SystemExit(f'scroll_to failed: {pattern}')


class Shooter:
    """一個語言的操作：切頁、轉換資料語言、拍一組。"""

    def __init__(self, lang):
        """依 [lang] 準備 ARB 字串與名稱。"""
        arb_file, self.app_locale, self.data_name, self.character = LANGS[lang]
        self.lang = lang
        self.s = strings(arb_file)
        self.rail = {}

    def nav(self, key):
        """切到 ARB key 對應的頁面：手機開抽屜點文字，平板與 Chromebook 點側欄座標。"""
        label = self.s[key]
        dismiss_validator()
        ns = nodes()
        if any(re.search(MENU, l) for l, _ in ns):
            tap(MENU, wait=1.2)
            ns = nodes()
        if any(l == label for l, _ in ns):
            tap(exact(label), wait=3)
        elif key in self.rail:
            press(*self.rail[key], 3)
        else:
            raise SystemExit(f'nav: {label} not found')

    def convert_data_language(self):
        """在設定頁把資料語言轉成這個語言（手機尺寸下操作）。"""
        self.nav('navSettings')
        scroll_to(exact(self.s['settingsDataLanguage']), 0.15)
        ns = nodes()
        ty = [b for l, b in ns if l == self.s['settingsDataLanguage']][0][1]
        names = {v[2] for v in LANGS.values()} | {'Deutsch', 'Français', 'Español', '한국어', 'ภาษาไทย'}
        field = min((b for l, b in ns if l.split()[0] in names and b[1] > ty), key=lambda b: b[1])
        press((field[0] + field[2]) // 2, (field[1] + field[3]) // 2, 1.5)
        opt = [b for l, b in nodes() if l == self.data_name and b != field][-1]
        press((opt[0] + opt[2]) // 2, (opt[1] + opt[3]) // 2, 3)
        tap(exact(self.s['settingsDataLanguageUnify']), wait=25)
        print(' ', [l for l, _ in nodes() if re.search(r'\d{3,}', l)][:1])
        adb('shell', 'input', 'keyevent', 'BACK')
        time.sleep(1)

    def capture(self, device):
        """拍一組 8 張並存成 24 位元 PNG。"""
        wh, dpi = DEVICES[device]
        keys = ['navOverview', 'navCharacter', 'navWeapon', 'navSettings']
        self.rail = dict(zip(keys, RAIL.get(device, [])))
        adb('shell', 'wm', 'size', wh)
        adb('shell', 'wm', 'density', str(dpi))
        adb('shell', 'svc', 'wifi', 'enable')
        adb('shell', 'settings', 'put', 'global', 'heads_up_notifications_enabled', '0')
        time.sleep(4)
        restart_app()
        dismiss_validator()
        # 手機也讓時間軸卡片緊接在標題列下方，下面的 5★ 一覽才完整（原神 5★ 一覽有三列）
        frac = 0.2
        shots = {}

        def snap(k):
            """關掉驗證器提示後截圖。"""
            dismiss_validator()
            shots[k] = screencap()

        # 連網才拍得到等待畫面（要無線偵錯）；寬畫面的角色活動頁看得到廣告，改用設定頁當背景
        self.nav('navSettings' if device in ('tablet-10', 'chromebook') else 'navCharacter')
        tap(exact(self.s['actionUpdate']), wait=8)
        snap('W')
        tap(exact(self.s['actionCancel']), wait=3)
        # 先連網打開一次詳情，讓立繪與說明下載進快取
        self.nav('navCharacter')
        scroll_to(NOW, frac)
        dismiss_validator()
        tap_avatar(self.character, 12)
        adb('shell', 'input', 'keyevent', 'BACK')
        time.sleep(1.5)
        # 斷網重開：原生廣告載入失敗會收起不佔位
        adb('shell', 'svc', 'wifi', 'disable')
        time.sleep(2)
        restart_app()
        self.nav('navOverview')
        snap('O')
        self.nav('navWeapon')
        snap('Wp')
        self.nav('navCharacter')
        snap('C')
        tap(exact(self.s['shareImageButton']), wait=2)
        snap('Sh')
        adb('shell', 'input', 'keyevent', 'BACK')
        time.sleep(1.5)
        scroll_to(NOW, frac)
        snap('T')
        tap_avatar(self.character, 4)
        snap('D')
        adb('shell', 'input', 'keyevent', 'BACK')
        time.sleep(1.5)
        self.nav('navSettings')
        snap('St')
        adb('shell', 'svc', 'wifi', 'enable')
        out = OUT / self.lang / device
        out.mkdir(parents=True, exist_ok=True)
        expect = tuple(map(int, wh.split('x')))
        for i, k in enumerate(ORDER, 1):
            assert shots[k].size == expect, (device, k, shots[k].size)
            for attempt in range(5):
                try:
                    shots[k].save(out / f'{i}.png', optimize=True)
                    break
                except OSError:  # Windows 上檔案偶爾被縮圖或防毒軟體短暫鎖住
                    if attempt == 4:
                        raise
                    time.sleep(2)
        print(f'  wrote {out.relative_to(REPO).as_posix()}/1-8.png')


def app_locales():
    """目前的 App 語言（例如 `zh-Hant`；跟隨系統時是空字串）。"""
    m = re.search(r'\[(.*)\]', adb('shell', 'cmd', 'locale', 'get-app-locales', PKG))
    return m.group(1) if m else ''


def restore(locales):
    """還原模擬器的顯示、網路、通知，App 語言改回 [locales]。"""
    for cmd in (['wm', 'size', 'reset'], ['wm', 'density', 'reset'], ['svc', 'wifi', 'enable'],
                ['am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', 'exit'],
                ['settings', 'put', 'global', 'sysui_demo_allowed', '0'],
                ['settings', 'put', 'global', 'heads_up_notifications_enabled', '1'],
                ['cmd', 'locale', 'set-app-locales', PKG, '--locales', locales or '""']):
        adb('shell', *cmd)


def main():
    """依參數拍指定的語言與裝置。"""
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--langs', nargs='+', choices=LANGS, default=list(LANGS))
    p.add_argument('--devices', nargs='+', choices=DEVICES, default=list(DEVICES))
    args = p.parse_args()
    if GAME_PKG not in adb('shell', 'pm', 'list', 'packages', GAME_PKG):
        raise SystemExit(f'{GAME_PKG} is not installed on the emulator; see the setup notes at the top of this file')
    original_locales = app_locales()
    try:
        for lang in args.langs:
            print(lang)
            shooter = Shooter(lang)
            adb('shell', 'wm', 'size', DEVICES['phone'][0])
            adb('shell', 'wm', 'density', str(DEVICES['phone'][1]))
            adb('shell', 'svc', 'wifi', 'enable')
            adb('shell', 'cmd', 'locale', 'set-app-locales', PKG, '--locales', shooter.app_locale)
            time.sleep(4)
            restart_app()
            shooter.convert_data_language()
            for device in args.devices:
                shooter.capture(device)
    finally:
        restore(original_locales)


if __name__ == '__main__':
    main()
