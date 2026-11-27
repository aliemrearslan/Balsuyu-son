import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.dirname(os.path.abspath(__file__))

def create_icon():
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Rounded Navy App Tile with Gold Border
    pad = 44
    r = 210
    d.rounded_rectangle([pad, pad, size - pad, size - pad], radius=r, fill=(8, 22, 46, 255), outline=(212, 175, 55, 255), width=22)

    # Subtle Emerald Inner Accent Ring
    d.rounded_rectangle([pad + 34, pad + 34, size - pad - 34, size - pad - 34], radius=r - 24, outline=(20, 184, 166, 170), width=10)

    # Top MEB Red Circle Crest
    cx = size // 2
    d.ellipse([cx - 92, 128, cx + 92, 312], fill=(227, 10, 23, 255), outline=(255, 255, 255, 255), width=12)

    # Draw School Bus Silhouette in Center
    bx0, by0, bx1, by1 = 216, 370, 808, 678
    # Bus body
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=52, fill=(248, 250, 252, 255), outline=(15, 23, 42, 255), width=10)
    # Amber school roof stripe
    d.rounded_rectangle([bx0 + 6, by0 + 6, bx1 - 6, by0 + 82], radius=44, fill=(245, 158, 11, 255))
    # Emerald bottom stripe
    d.rectangle([bx0 + 6, by1 - 88, bx1 - 6, by1 - 44], fill=(15, 118, 110, 255))
    # Windows
    for wx in (260, 384, 508):
        d.rounded_rectangle([wx, by0 + 104, wx + 98, by0 + 196], radius=16, fill=(30, 41, 59, 255))
    # Front windshield
    d.rounded_rectangle([634, by0 + 104, 774, by0 + 196], radius=18, fill=(14, 165, 233, 255))
    # Headlight
    d.rounded_rectangle([774, by1 - 102, 804, by1 - 64], radius=8, fill=(253, 224, 71, 255))
    # Wheels
    for wcx in (348, 676):
        d.ellipse([wcx - 58, by1 - 52, wcx + 58, by1 + 64], fill=(15, 23, 42, 255), outline=(212, 175, 55, 255), width=14)
        d.ellipse([wcx - 22, by1 - 16, wcx + 22, by1 + 28], fill=(203, 213, 225, 255))

    # Bottom Gold Brand Pill
    d.rounded_rectangle([186, 772, 838, 884], radius=56, fill=(15, 118, 110, 255), outline=(212, 175, 55, 255), width=10)

    # Load system bold font cleanly across macOS / Linux / Windows
    font_candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
    ]
    def load_f(sz):
        for fp in font_candidates:
            if os.path.exists(fp):
                try:
                    return ImageFont.truetype(fp, sz)
                except Exception:
                    pass
        return ImageFont.load_default()

    f_meb = load_f(62)
    f_bot = load_f(58)
    d.text((cx, 220), "MEB", fill=(255, 255, 255, 255), font=f_meb, anchor="mm")
    d.text((cx, 828), "BALSUYU MTAL", fill=(253, 230, 138, 255), font=f_bot, anchor="mm")

    png_path = os.path.join(OUT, "app_icon.png")
    ico_path = os.path.join(OUT, "app_icon.ico")
    icns_path = os.path.join(OUT, "app_icon.icns")
    img.save(png_path, "PNG")
    img.save(ico_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    img.save(icns_path, format="ICNS")
    iconset = os.path.join(OUT, "app_icon.iconset")
    if os.path.isdir(iconset):
        for fn in os.listdir(iconset):
            os.remove(os.path.join(iconset, fn))
        os.rmdir(iconset)
    print("CREATED:", png_path, ico_path, icns_path)

if __name__ == "__main__":
    create_icon()
