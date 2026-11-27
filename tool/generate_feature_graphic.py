"""產生 Google Play 的主題圖片（1024×500，24 位元 PNG），四種商店語言各一張。

左邊是 Play 商店圖示，右邊是 App 名稱、「for 遊戲名」與一句標語。圖示的底色是中間暗、四角亮的漸層，
柔邊遮罩接不自然，所以圖示原樣貼上、外圍沿用圖示最外圈的像素延伸，右側再漸漸過渡到較暗的純色。

用法（先用 `dart run tool/generate_app_icons.dart` 產生 Play 商店圖示）：
  python tool/generate_feature_graphic.py

輸出到 `docs/images/play-store/feature-graphic-<語言>.png`。字型用 Windows 內建字型，所以要在 Windows 上執行。
App 名稱與標語要和 `private/play-store/listing.md` 的商店文字一致。
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / 'docs' / 'images' / 'play-store'
FONTS = Path('C:/Windows/Fonts')
# 語言：(名稱, for 遊戲名, 標語, 名稱字型, 標語字型)
VARIANTS = {
    'en': ('Wish Analyzer', 'for Genshin', 'Wish stats · Pity tracking · 5★ timeline', 'segoeuib.ttf', 'msjhbd.ttc'),
    'zh-TW': ('祈願卡池分析', 'for 原神', '祈願記錄統計・保底進度・5★ 時間軸', 'msjhbd.ttc', 'msjhbd.ttc'),
    'ja': ('祈願分析', 'for 原神', '祈願履歴の統計・天井の進捗・★5 タイムライン', 'YuGothB.ttc', 'YuGothB.ttc'),
    'zh-CN': ('祈愿卡池分析', 'for 原神', '祈愿记录统计・保底进度・5★ 时间轴', 'msyhbd.ttc', 'msyhbd.ttc'),
}
W, H = 1024, 500
ICON_SIZE, ICON_X, ICON_Y = 400, 40, 50
TEXT_X, TEXT_RIGHT_MARGIN = 470, 48
REPO = 'github.com/GoneTone/genshin-impact-wish-gacha-analyzer'
GOLD = (0xD6, 0xA2, 0x68)
MUTED = (0xB8, 0xBF, 0xCF)
FAINT = (0x8A, 0x92, 0xA6)


def background(icon: Image.Image) -> Image.Image:
    """圖示原樣放在左側，外圍以邊緣像素延伸，圖示右側 260px 內漸變到較暗的純色。"""
    rgb = icon.convert('RGB')
    edge = np.array(rgb.getpixel((2, rgb.height // 2)), dtype=np.float32)
    scaled = np.asarray(rgb.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS), dtype=np.float32)
    a = np.pad(
        scaled,
        ((ICON_Y, H - ICON_Y - ICON_SIZE), (ICON_X, W - ICON_X - ICON_SIZE), (0, 0)),
        mode='edge',
    )
    t = np.clip((np.arange(W) - (ICON_X + ICON_SIZE)) / 260.0, 0, 1)[None, :, None]
    a = a * (1 - t) + edge * 0.78 * t
    return Image.fromarray(a.astype(np.uint8))


def fit_font(draw: ImageDraw.ImageDraw, text: str, font: str, size: int, min_size: int, max_w: int):
    """從 `size` 往下縮，直到 `text` 寬度不超過 `max_w`（最小 `min_size`）。"""
    while True:
        f = ImageFont.truetype(str(FONTS / font), size)
        if draw.textlength(text, font=f) <= max_w or size <= min_size:
            return f, size
        size -= 1


def render(base: Image.Image, title: str, sub: str, tagline: str, title_font: str, tagline_font: str) -> Image.Image:
    """在背景右側畫出垂直置中的名稱、「for 遊戲名」、金色短線、標語與 GitHub 網址。"""
    img = base.copy()
    d = ImageDraw.Draw(img)
    max_w = W - TEXT_X - TEXT_RIGHT_MARGIN
    ft, ts = fit_font(d, title, title_font, 72, 40, max_w)
    fs = ImageFont.truetype(str(FONTS / title_font), int(ts * 0.6))
    fg, _ = fit_font(d, tagline, tagline_font, 26, 16, max_w)
    fr, _ = fit_font(d, REPO, 'seguisb.ttf', 18, 12, max_w)
    tb, sb, gb, rb = (
        d.textbbox((0, 0), s, font=f) for s, f in ((title, ft), (sub, fs), (tagline, fg), (REPO, fr))
    )
    gap1, gap2, gap3 = 14, 34, 18
    y = (
        H
        - ((tb[3] - tb[1]) + gap1 + (sb[3] - sb[1]) + gap2 + (gb[3] - gb[1]) + gap3 + (rb[3] - rb[1]))
    ) // 2
    d.text((TEXT_X, y - tb[1]), title, font=ft, fill=(255, 255, 255))
    y += tb[3] - tb[1] + gap1
    d.text((TEXT_X, y - sb[1]), sub, font=fs, fill=GOLD)
    y += sb[3] - sb[1] + gap2
    d.line((TEXT_X, y - gap2 // 2, TEXT_X + 64, y - gap2 // 2), fill=GOLD, width=3)
    d.text((TEXT_X, y - gb[1]), tagline, font=fg, fill=MUTED)
    y += gb[3] - gb[1] + gap3
    d.text((TEXT_X, y - rb[1]), REPO, font=fr, fill=FAINT)
    return img


def main():
    """產生所有語言的主題圖片。"""
    base = background(Image.open(OUT / 'icon-512.png'))
    for lang, args in VARIANTS.items():
        img = render(base, *args)
        assert img.size == (W, H) and img.mode == 'RGB'
        path = OUT / f'feature-graphic-{lang}.png'
        img.save(path)
        print(f'wrote {path.relative_to(OUT.parent.parent.parent).as_posix()}  {W}x{H}')


if __name__ == '__main__':
    main()
