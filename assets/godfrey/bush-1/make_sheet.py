"""Assemble review images only after the Blender views have been inspected."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parent
VIEWS = ROOT / "views"
SHEETS = ROOT / "sheets"
SHEETS.mkdir(exist_ok=True)


def tile(path, title, width=640, height=520):
    source = Image.open(path).convert("RGB")
    image = Image.new("RGB", (width, height), "#d8dcdd")
    draw = ImageDraw.Draw(image)
    draw.text((16, 14), title, fill="#1e2927")
    fitted = ImageOps.contain(source, (width - 32, height - 62))
    image.paste(fitted, ((width - fitted.width) // 2, 48 + (height - 62 - fitted.height) // 2))
    return image


rows = [
    [
        tile(ROOT / "reference_salvia_cc0.jpg", "CC0 reference — Cecelia Alexander"),
        tile(VIEWS / "gray-three_quarter.png", "Original model — gray shape"),
        tile(VIEWS / "material-three_quarter.png", "Original model — material"),
    ],
    [
        tile(VIEWS / "gray-front.png", "Gray — front"),
        tile(VIEWS / "gray-side.png", "Gray — side"),
        tile(VIEWS / "material-side.png", "Material — side"),
    ],
]
sheet = Image.new("RGB", (640 * 3, 520 * 2), "white")
for y, row in enumerate(rows):
    for x, image in enumerate(row):
        sheet.paste(image, (x * 640, y * 520))
sheet.save(SHEETS / "reference-result.png", optimize=True)
