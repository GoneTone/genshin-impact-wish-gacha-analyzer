"""產生 Android 啟動畫面底部的品牌圖（英文 App 名稱，淺色／深色各一張）。

用法：python tool/generate_splash_branding.py <Flutter SDK 根目錄>
字型用 Flutter SDK 內附的 Roboto（Apache 2.0），與 App 在 Android 上的預設字型一致。
尺寸 800x320 是 Android 12 以上品牌圖的規定（以 4x 顯示為 200x80dp）。
產生後要再跑 `dart run flutter_native_splash:create`。
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 800, 320
LINES = (("Genshin Impact", "roboto-medium.ttf", 68), ("Wish Gacha Analyzer", "roboto-regular.ttf", 54))
# (標題色, 副標色)：對應 lib/theme/tokens.dart 的 textSecondary／textMuted。
THEMES = {
    "assets/splash/branding.png": ("#2C3245", "#6A7080"),
    "assets/splash/branding_dark.png": ("#DDE3EE", "#8A92A6"),
}
LINE_GAP = 14


def main() -> None:
    fonts_dir = pathlib.Path(sys.argv[1]) / "bin/cache/artifacts/material_fonts"
    fonts = [ImageFont.truetype(str(fonts_dir / name), size) for _, name, size in LINES]
    boxes = [font.getbbox(text) for (text, _, _), font in zip(LINES, fonts)]
    heights = [b[3] - b[1] for b in boxes]
    top = (HEIGHT - sum(heights) - LINE_GAP) / 2
    for path, colors in THEMES.items():
        image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        y = top
        for (text, _, _), font, box, height, color in zip(LINES, fonts, boxes, heights, colors):
            width = box[2] - box[0]
            assert width <= WIDTH, f"{text!r} is wider than {WIDTH}px"
            draw.text(((WIDTH - width) / 2 - box[0], y - box[1]), text, font=font, fill=color)
            y += height + LINE_GAP
        image.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
