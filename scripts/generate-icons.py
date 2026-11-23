#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ASSETS.mkdir(exist_ok=True)

def font(size):
    for candidate in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                      "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf"]:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()

def make_icon(size, transparent=False):
    scale = size / 512
    canvas = Image.new("RGBA", (size, size), (0,0,0,0) if transparent else "#0b1424")
    draw = ImageDraw.Draw(canvas)
    inset = int(18*scale)
    if not transparent:
        draw.rounded_rectangle((0,0,size-1,size-1), radius=int(116*scale), fill="#0b1424")
    draw.ellipse((int(68*scale),int(68*scale),int(444*scale),int(444*scale)),
                 outline="#287be0", width=max(2,int(22*scale)))
    # A bold, geometric N monogram with a subtle cyan diagonal.
    f = font(int(300*scale))
    bbox = draw.textbbox((0,0),"N",font=f,stroke_width=max(1,int(2*scale)))
    tw,th=bbox[2]-bbox[0],bbox[3]-bbox[1]
    x=(size-tw)//2-bbox[0]
    y=(size-th)//2-bbox[1]-int(3*scale)
    draw.text((x,y),"N",font=f,fill="#f7fbff",stroke_width=max(1,int(1*scale)),stroke_fill="#f7fbff")
    draw.line((int(148*scale),int(356*scale),int(364*scale),int(148*scale)),
              fill="#63c7ff",width=max(2,int(10*scale)))
    draw.line((int(103*scale),int(256*scale),int(139*scale),int(256*scale)),
              fill="#63c7ff",width=max(2,int(12*scale)))
    draw.line((int(373*scale),int(256*scale),int(409*scale),int(256*scale)),
              fill="#63c7ff",width=max(2,int(12*scale)))
    return canvas

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--android-res", default=None)
    args=parser.parse_args()
    for size,name in [(192,"icon-192.png"),(512,"icon-512.png"),(512,"icon-maskable-512.png")]:
        make_icon(size).save(ASSETS/name,optimize=True)
    if args.android_res:
        res=Path(args.android_res)
        sizes={"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}
        for density,size in sizes.items():
            folder=res/f"mipmap-{density}"
            folder.mkdir(parents=True,exist_ok=True)
            img=make_icon(size)
            img.save(folder/"ic_launcher.png",optimize=True)
            img.save(folder/"ic_launcher_round.png",optimize=True)
            make_icon(size,transparent=True).save(folder/"ic_launcher_foreground.png",optimize=True)
        anydpi=res/"mipmap-anydpi-v26"
        anydpi.mkdir(parents=True,exist_ok=True)
        (anydpi/"ic_launcher.xml").write_text(
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
            '<background android:drawable="@color/ic_launcher_background"/>'
            '<foreground android:drawable="@mipmap/ic_launcher_foreground"/>'
            '</adaptive-icon>',encoding="utf-8")
        (anydpi/"ic_launcher_round.xml").write_text(
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
            '<background android:drawable="@color/ic_launcher_background"/>'
            '<foreground android:drawable="@mipmap/ic_launcher_foreground"/>'
            '</adaptive-icon>',encoding="utf-8")
        values=res/"values"
        values.mkdir(parents=True,exist_ok=True)
        (values/"ic_launcher_background.xml").write_text(
            '<resources><color name="ic_launcher_background">#0b1424</color></resources>',encoding="utf-8")
    print("IRONNOVA icons generated.")

if __name__=="__main__":
    main()
