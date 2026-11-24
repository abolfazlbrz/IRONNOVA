#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import argparse

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"

def make_icon(size, transparent=False):
    scale = 3
    n = size * scale
    bg = (0, 0, 0, 0) if transparent else (7, 16, 9, 255)
    image = Image.new("RGBA", (n, n), bg)
    if not transparent:
        halo = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        hd = ImageDraw.Draw(halo)
        hd.ellipse((n*.13, n*.13, n*.87, n*.87), fill=(76, 255, 38, 42))
        halo = halo.filter(ImageFilter.GaussianBlur(n*.10))
        image = Image.alpha_composite(image, halo)
    draw = ImageDraw.Draw(image)
    if not transparent:
        pad = n*.035
        draw.rounded_rectangle((pad, pad, n-pad, n-pad), radius=n*.22,
                               fill=(7, 16, 9, 255), outline=(88, 255, 45, 255),
                               width=max(2, int(n*.018)))
    draw.ellipse((n*.18, n*.18, n*.82, n*.82),
                 outline=(50, 155, 42, 210), width=max(2, int(n*.012)))
    triangle = [(n*.50, n*.25), (n*.235, n*.72), (n*.765, n*.72)]
    draw.line(triangle + [triangle[0]], fill=(88, 255, 45, 255),
              width=max(4, int(n*.034)), joint="curve")
    y = n*.50
    draw.rounded_rectangle((n*.29, y-n*.035, n*.71, y+n*.035),
                           radius=n*.025, fill=(239, 247, 239, 255))
    for x0, x1 in ((n*.225, n*.325), (n*.675, n*.775)):
        draw.rounded_rectangle((x0, y-n*.105, x1, y+n*.105),
                               radius=n*.025, fill=(239, 247, 239, 255))
    draw.rounded_rectangle((n*.46, y-n*.055, n*.54, y+n*.055),
                           radius=n*.018, fill=(88, 255, 45, 255))
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
    print("IRONNOVA neon-green icons generated.")

if __name__ == "__main__":
    main()
