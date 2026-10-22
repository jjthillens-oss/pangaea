"""Render review turntables for the quality-ladder rungs (docs/art/quality_ladder.md).

For each rung it opens the rung's .blend, adds the section 6 review lighting and writes to
docs/art/renders/:
  <rung>_clay_NN.png and (from rung 2) <rung>_beauty_NN.png   eight-view turntable frames
  <rung>_silhouette.png                                        gameplay-camera readability check
  <rung>_sheet.jpg                                             contact sheet of the above
  <rung>_swim.gif                                              swim clip, for rigged rungs
Contact sheets need ImageMagick's `montage` and the GIF needs ffmpeg (a review tool only, not a game dependency).

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
                    "-background", "#22303A", "-quality", "88", f"{prefix}_sheet.jpg"], check=True)


def swim_gif(rung, clip="swim"):
    """Animated review of a clip from the hero angle (needs ffmpeg; review tool only)."""
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    action = bpy.data.actions.get(clip)
    if arm is None or action is None or not shutil.which("ffmpeg"):
        return
    scene = bpy.context.scene
    arm.animation_data.action = action
    scene.render.resolution_x = scene.render.resolution_y = 360
    scene.cycles.samples = 24
    ld.aim(scene.camera, TARGET, 3.4, 40, 30)
    frames_dir = os.path.join(ld.RENDER_DIR, f"_{clip}_frames")
    end = int(action.frame_range[1])
    for f in range(0, end):
        scene.frame_set(f)
        ld.render_to(os.path.join(frames_dir, f"{f:03d}.png"))
    out = os.path.join(ld.RENDER_DIR, f"{cl.asset_id(rung)}_{clip}.gif")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(scene.render.fps), "-i",
                    os.path.join(frames_dir, "%03d.png"), "-vf",
                    "split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse", out], check=True)
    shutil.rmtree(frames_dir)


def render(rung):
    beauty = rung >= "2"
    prepare(rung)
    prefix = cl.asset_id(rung)
    ld.turntable(prefix, target=TARGET, distance=3.4, frames=8, pitch=20, clay=True, beauty=beauty)
    ld.silhouette(prefix, target=TARGET)
    sheet(rung, beauty)
    swim_gif(rung)


def main(argv):
    for rung in cl.RUNGS:
        if not argv or rung in argv or rung[0] in argv:
            blend = os.path.join(cl.ROOT, "assets", "source", "blender", f"{cl.asset_id(rung)}.blend")
            if os.path.exists(blend):
                render(rung)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
