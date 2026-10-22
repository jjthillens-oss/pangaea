"""Render review sheets for the M1 production assets (tools/blender/make_m1_production.py).

For each asset it opens the asset's .blend, adds the section 6 review lighting and writes to
docs/art/renders/production/:
  <id>_beauty_NN.png and <id>_clay_NN.png   four-view turntable frames (not kept in git)
  <id>_sheet.jpg                            contact sheet: beauty row over clay row
Contact sheets need ImageMagick's `montage` (a review tool only, not a game dependency).

Run: python tools/blender/render_production.py [id ...]   (default: every production asset)
"""
import glob
import os
import shutil
import subprocess
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

OUT = os.path.join(ld.RENDER_DIR, "production")
IDS = ["part_flagellum", "part_eye_spot", "part_mouth_filter", "part_mouth_jaw", "plankton", "carrion",
       "rock_a", "rock_b", "rock_c", "sample_cell"]


def bounds():
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ __import__("mathutils").Vector(corner)
            lo = [min(a, b) for a, b in zip(lo, w)]
            hi = [max(a, b) for a, b in zip(hi, w)]
    return lo, hi


def render(asset_id):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ld.ROOT, "assets", "source", "blender", f"{asset_id}.blend"))
    lo, hi = bounds()
    centre = [(a + b) / 2 for a, b in zip(lo, hi)]
    size = max(b - a for a, b in zip(lo, hi))
    if asset_id.startswith("rock"):
        centre[2] = 0.0   # the part under the floor is never seen
        size = 2.2
    # Review lights are placed for a 1 m creature; scale the scene so every asset fills the frame.
    scale = 1.4 / size
    for obj in bpy.context.scene.objects:
        if obj.parent is None:
            obj.location = [(o - c) * scale for o, c in zip(obj.location, centre)]
            obj.scale = [s * scale for s in obj.scale]
    ld.setup_render(resolution=480, samples=40)
    ld.review_lighting()
    floor = (lo[2] - centre[2]) * scale - 0.01 if not asset_id.startswith("rock") else -0.35
    ld.ground_disc(radius=200, z=floor)
    ld.camera(lens=55)
    os.makedirs(OUT, exist_ok=True)
    keep = ld.RENDER_DIR
    ld.RENDER_DIR = OUT
    try:
        ld.turntable(asset_id, target=(0, 0, 0.05), distance=2.4, frames=4, pitch=28, clay=True, beauty=True)
    finally:
        ld.RENDER_DIR = keep
    prefix = os.path.join(OUT, asset_id)
    if shutil.which("montage"):
        tiles = sorted(glob.glob(f"{prefix}_beauty_*.png")) + sorted(glob.glob(f"{prefix}_clay_*.png"))
        subprocess.run(["montage", *tiles, "-tile", "4x2", "-geometry", "300x300+2+2", "-background", "#22303A",
                        "-quality", "88", f"{prefix}_sheet.jpg"], check=True)


def main(argv):
    for asset_id in argv or IDS:
        render(asset_id)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
