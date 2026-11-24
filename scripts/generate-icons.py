#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import argparse

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"

def make_icon(size, transparent=False):
    scale = 3
    n = size * scale
    image = Image.new("RGBA", (n, n), (0, 0, 0, 0) if transparent else (255, 255, 255, 255))
    draw = ImageDraw.Draw(image)
    # Clean white app tile with the original-style blue dumbbell mark.
    blue = (35, 126, 224, 255)
    dark_blue = (24, 91, 177, 255)
    y = n * 0.50
    bar_h = n * 0.085
    bar_x1, bar_x2 = n * 0.29, n * 0.71
    draw.rounded_rectangle((bar_x1, y-bar_h/2, bar_x2, y+bar_h/2),
                           radius=n*0.035, fill=blue)
    # Weighted end plates, with a subtle darker inner edge for depth.
    for cx, direction in ((n*0.25, -1), (n*0.75, 1)):
        w, h = n*0.105, n*0.34
        draw.rounded_rectangle((cx-w/2, y-h/2, cx+w/2, y+h/2),
                               radius=n*0.035, fill=blue)
        inner_x = cx + direction*n*0.025
        draw.rounded_rectangle((inner_x-n*0.012, y-h*0.34,
                                inner_x+n*0.012, y+h*0.34),
                               radius=n*0.01, fill=dark_blue)
    # Slightly wider collars where the bar meets the plates.
    for cx in (n*0.34, n*0.66):
        draw.rounded_rectangle((cx-n*0.025, y-n*0.105, cx+n*0.025, y+n*0.105),
                               radius=n*0.012, fill=dark_blue)
    return image.resize((size, size), Image.Resampling.LANCZOS)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--android-res", default=None)
    args = parser.parse_args()
    ASSETS.mkdir(parents=True, exist_ok=True)
    make_icon(192).save(ASSETS / "icon-192.png", optimize=True)
    make_icon(512).save(ASSETS / "icon-512.png", optimize=True)
    make_icon(512).save(ASSETS / "icon-maskable-512.png", optimize=True)
    if args.android_res:
        res = Path(args.android_res)
        for density, size in {"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}.items():
            folder = res / f"mipmap-{density}"
            folder.mkdir(parents=True, exist_ok=True)
            make_icon(size).save(folder / "ic_launcher.png", optimize=True)
            make_icon(size).save(folder / "ic_launcher_round.png", optimize=True)
            make_icon(size, transparent=True).save(folder / "ic_launcher_foreground.png", optimize=True)
        adaptive = res / "mipmap-anydpi-v26"
        adaptive.mkdir(parents=True, exist_ok=True)
        xml = ('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
               '<background android:drawable="@color/ic_launcher_background"/>'
               '<foreground android:drawable="@mipmap/ic_launcher_foreground"/>'
               '</adaptive-icon>')
        (adaptive / "ic_launcher.xml").write_text(xml, encoding="utf-8")
        (adaptive / "ic_launcher_round.xml").write_text(xml, encoding="utf-8")
        values = res / "values"
        values.mkdir(parents=True, exist_ok=True)
        (values / "ic_launcher_background.xml").write_text(
            '<resources><color name="ic_launcher_background">#071009</color></resources>',
            encoding="utf-8")
    print("IRONNOVA blue dumbbell icons generated.")

if __name__ == "__main__":
    main()
