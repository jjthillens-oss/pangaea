"""Render review turntables for the quality-ladder rungs (docs/art/quality_ladder.md).

For each rung it opens the rung's .blend, adds the section 6 review lighting and writes to
docs/art/renders/:
  <rung>_clay_NN.png and (from rung 2) <rung>_beauty_NN.png   eight-view turntable frames
  <rung>_silhouette.png                                        gameplay-camera readability check
  <rung>_sheet.png                                             contact sheet of the above
Contact sheets need ImageMagick's `montage` (a review tool only, not a game dependency).

Run: python tools/blender/render_ladder.py [rung ...]   (after tools/blender/cell_ladder.py)
"""
import glob
import os
import shutil
import subprocess
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import cell_ladder as cl  # noqa: E402
import lookdev as ld  # noqa: E402

TARGET = (0, -0.38, 0.0)


def prepare(rung, pose_frame=None):
    blend = os.path.join(cl.ROOT, "assets", "source", "blender", f"{cl.asset_id(rung)}.blend")
    bpy.ops.wm.open_mainfile(filepath=blend)
    scene = bpy.context.scene
    if pose_frame is not None:
        scene.frame_set(pose_frame)
    ld.setup_render(resolution=560, samples=48)
    ld.review_lighting()
    ld.ground_disc(radius=200, z=-0.42)
    ld.camera(lens=55)


def sheet(rung, beauty):
    prefix = os.path.join(ld.RENDER_DIR, cl.asset_id(rung))
    if not shutil.which("montage"):
        print("montage not found; skipping contact sheet")
        return
    rows = [sorted(glob.glob(f"{prefix}_clay_*.png"))]
    if beauty:
        rows.append(sorted(glob.glob(f"{prefix}_beauty_*.png")))
    tiles = [p for row in rows for p in row[:4]] + [p for row in rows for p in row[4:8]]
    subprocess.run(["montage", *tiles, "-tile", f"4x{len(tiles) // 4}", "-geometry", "280x280+2+2",
                    "-background", "#22303A", f"{prefix}_sheet.png"], check=True)


def render(rung):
    beauty = rung >= "2"
    # Animated rungs are posed mid-swim so the turntable shows the rig at work.
    prepare(rung, pose_frame=None)
    prefix = cl.asset_id(rung)
    ld.turntable(prefix, target=TARGET, distance=3.4, frames=8, pitch=20, clay=True, beauty=beauty)
    ld.silhouette(prefix, target=TARGET)
    sheet(rung, beauty)


def main(argv):
    for rung in cl.RUNGS:
        if not argv or rung in argv or rung[0] in argv:
            blend = os.path.join(cl.ROOT, "assets", "source", "blender", f"{cl.asset_id(rung)}.blend")
            if os.path.exists(blend):
                render(rung)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
