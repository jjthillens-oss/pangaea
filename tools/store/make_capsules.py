"""Steam capsule concepts (PROPOSED, docs/store/CAPSULES.md): crops the two text-free key art masters
from tools/blender/render_store_keyart.py to every Steam store and library size and lays a placeholder
wordmark over them. Nothing here ships with the game; it is marketing tooling.

The wordmark is a placeholder until the owner settles the player-facing name (docs/DECISIONS.md,
"Product name"). It is set in Inter Display Black (SIL OFL 1.1), looked up on the system.

Needs Pillow (tooling only, not a game dependency). Run: python tools/store/make_capsules.py [--name TEXT]
Reads docs/store/keyart/keyart_{wide,tall}.png and writes docs/store/capsules/*.png plus a contact sheet.
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEYART = os.path.join(ROOT, "docs", "store", "keyart")
OUT = os.path.join(ROOT, "docs", "store", "capsules")
FONT_PATHS = [
    "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf",
    "/usr/share/fonts/opentype/inter/Inter-Black.otf",
    "C:/Windows/Fonts/Inter-Black.ttf",
]
CREAM = (246, 238, 220)
INK = (8, 28, 66)

# name: (size, master, logo placement or None, crop focus x, crop focus y, zoom)
# Focus is the point of the master the crop centres on, clamped so the crop stays inside the image. Zoom
# crops tighter than "cover". The library hero zooms so the cell sits in its central 860x380 safe area.
CAPSULES = {
    "header_capsule": ((920, 430), "wide", "left", 0.5, 0.55, 1.0),
    "small_capsule": ((462, 174), "wide", "fill", 0.5, 0.55, 1.0),
    "main_capsule": ((1232, 706), "wide", "left", 0.62, 0.55, 1.0),
    "vertical_capsule": ((748, 896), "tall", "top", 0.5, 0.62, 1.25),
    "page_background": ((1438, 810), "wide", None, 0.5, 0.5, 1.0),
    "library_capsule": ((600, 900), "tall", "top", 0.5, 0.6, 1.2),
    "library_header": ((920, 430), "wide", "left", 0.5, 0.55, 1.0),
    "library_hero": ((3840, 1240), "wide", None, 0.66, 0.55, 1.25),
}


def font(px):
    for path in FONT_PATHS:
        if os.path.exists(path):
            return ImageFont.truetype(path, px)
    raise SystemExit("Inter Black not found; install Inter (SIL OFL) or add its path to FONT_PATHS")


def cover_crop(img, size, fx, fy, zoom):
    """Scale the master to cover `size` (as CSS background-size: cover) times `zoom`, centred on (fx, fy)."""
    tw, th = size
    scale = max(tw / img.width, th / img.height) * zoom
    w, h = round(img.width * scale), round(img.height * scale)
    big = img.resize((w, h), Image.LANCZOS)
    left = min(max(round(fx * w - tw / 2), 0), w - tw)
    top = min(max(round(fy * h - th / 2), 0), h - th)
    return big.crop((left, top, left + tw, top + th))


def wordmark(text, height):
    """The placeholder logotype: tracked cream capitals with a soft deep-blue shadow, on transparency."""
    f = font(height)
    tracking = round(height * 0.08)
    widths = [f.getbbox(c)[2] - f.getbbox(c)[0] for c in text]
    width = sum(widths) + tracking * (len(text) - 1)
    pad = round(height * 0.5)
    layer = Image.new("RGBA", (width + pad * 2, height * 2 + pad), (0, 0, 0, 0))
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    draw_t, draw_s = ImageDraw.Draw(layer), ImageDraw.Draw(shadow)
    x = pad
    for c, w in zip(text, widths):
        ox = -f.getbbox(c)[0]
        draw_s.text((x + ox, pad + round(height * 0.06)), c, font=f, fill=INK + (200,))
        draw_t.text((x + ox, pad), c, font=f, fill=CREAM + (255,))
        x += w + tracking
    shadow = shadow.filter(ImageFilter.GaussianBlur(height * 0.12))
    out = Image.alpha_composite(shadow, layer)
    return out.crop(out.getbbox())


def place_logo(img, text, mode):
    w, h = img.size
    if mode == "fill":
        target_w = round(w * 0.86)
    elif mode == "left":
        target_w = round(w * 0.42)
    else:
        target_w = round(w * 0.78)
    probe = wordmark(text, 200)
    logo = wordmark(text, max(8, round(200 * target_w / probe.width)))
    # Darken behind the logo so it reads on any part of the art.
    shade = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(shade)
    if mode == "left":
        x, y = round(w * 0.06), round(h * 0.5 - logo.height / 2)
        d.ellipse((-w * 0.2, h * 0.05, w * 0.62, h * 0.95), fill=120)
    elif mode == "top":
        x, y = round((w - logo.width) / 2), round(h * 0.09)
        d.ellipse((-w * 0.2, -h * 0.15, w * 1.2, h * 0.36), fill=120)
    else:
        x, y = round((w - logo.width) / 2), round((h - logo.height) / 2)
        d.rectangle((0, 0, w, h), fill=110)
    shade = shade.filter(ImageFilter.GaussianBlur(min(w, h) * 0.12))
    dark = Image.new("RGBA", img.size, INK + (255,))
    img = Image.composite(dark, img, shade)
    img.alpha_composite(logo, (x, y))
    return img


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", default="PANGAEA", help="placeholder title until the name is settled")
    args = parser.parse_args()
    masters = {k: Image.open(os.path.join(KEYART, f"keyart_{k}.png")).convert("RGBA") for k in ("wide", "tall")}
    os.makedirs(OUT, exist_ok=True)
    made = []
    for name, (size, master, logo, fx, fy, zoom) in CAPSULES.items():
        img = cover_crop(masters[master], size, fx, fy, zoom)
        if name == "page_background":
            # Ambient: soft and dark so it never competes with the page.
            img = img.filter(ImageFilter.GaussianBlur(10))
            img = Image.blend(img, Image.new("RGBA", size, INK + (255,)), 0.45)
        if logo:
            img = place_logo(img, args.name, logo)
        path = os.path.join(OUT, f"{name}.png")
        img.convert("RGB").save(path, optimize=True)
        made.append((name, img))
        print("saved", path, size)
    logo = wordmark(args.name, 400)
    scale = min(1280 / logo.width, 720 / logo.height)
    logo = logo.resize((round(logo.width * scale), round(logo.height * scale)), Image.LANCZOS)
    logo.save(os.path.join(OUT, "library_logo.png"), optimize=True)
    print("saved library_logo.png", logo.size)
    contact_sheet(made)


def contact_sheet(made):
    """Every capsule at a common height, labelled, for review."""
    label_font = font(22)
    rows = [["header_capsule", "main_capsule", "small_capsule"],
            ["vertical_capsule", "library_capsule", "page_background"],
            ["library_hero"]]
    lookup = dict(made)
    gap = 80
    row_imgs = []
    for row in rows:
        target_h = 360 if row[0] != "library_hero" else 300
        tiles = []
        for n in row:
            im = lookup[n]
            th = target_h if n != "small_capsule" else round(target_h * 0.5)
            tiles.append((n, im.resize((round(im.width * th / im.height), th), Image.LANCZOS)))
        width = sum(t.width for _, t in tiles) + gap * (len(tiles) + 1)
        canvas = Image.new("RGB", (width, target_h + 60), (18, 22, 30))
        x = gap
        d = ImageDraw.Draw(canvas)
        for n, t in tiles:
            canvas.paste(t.convert("RGB"), (x, 10))
            d.text((x, t.height + 18), f"{n}  {lookup[n].width}x{lookup[n].height}", font=label_font, fill=(220, 225, 235))
            x += t.width + gap
        row_imgs.append(canvas)
    sheet = Image.new("RGB", (max(r.width for r in row_imgs), sum(r.height for r in row_imgs)), (18, 22, 30))
    y = 0
    for r in row_imgs:
        sheet.paste(r, (0, y))
        y += r.height
    path = os.path.join(OUT, "contact_sheet.jpg")
    sheet.save(path, quality=88)
    print("saved", path)


if __name__ == "__main__":
    main()
