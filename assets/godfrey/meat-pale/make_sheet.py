"""Pair the verified CC0 reference with final inspected review renders."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parent


def panel(path, caption, size=(600, 450), crop=False):
    source = Image.open(path).convert("RGB")
    bounds = (size[0] - 24, size[1] - 58)
    fitted = ImageOps.fit(source, bounds) if crop else ImageOps.contain(source, bounds)
    output = Image.new("RGB", size, "#D7D9D6")
    output.paste(fitted, ((size[0] - fitted.width) // 2,
                          42 + (bounds[1] - fitted.height) // 2))
    ImageDraw.Draw(output).text((12, 13), caption, fill="#253139")
    return output


def main():
    rows = [
        [
            panel(ROOT / "reference_cc0.jpg", "CC0 reference: kakyusei; shape only"),
            panel(ROOT / "gray_three_quarter.png", "Original gray shape"),
            panel(ROOT / "material_three_quarter.png", "Original material, neutral light"),
        ],
        [
            panel(ROOT / "reference_cc0.jpg", "Reference central overlap crop", crop=True),
            panel(ROOT / "material_gameplay.png", "Original gameplay-distance view"),
            panel(ROOT / "godot_review.png", "Godot isolated import/render"),
        ],
    ]
    sheet = Image.new("RGB", (1800, 900), "white")
    for y, row in enumerate(rows):
        for x, item in enumerate(row):
            sheet.paste(item, (x * 600, y * 450))
    sheet.save(ROOT / "reference_result_sheet.png", optimize=True)


if __name__ == "__main__":
    main()
