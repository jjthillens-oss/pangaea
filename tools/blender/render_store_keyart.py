"""Key art for the Steam store capsules (PROPOSED, docs/store/CAPSULES.md). A marketing render, not game
content: it reuses the approved microscopic-world mood scene (render_micro_mood.build: the production
player cell, the step 3 threats, food and the glassy shells) and frames it as a cinematic hero shot.

Two framings, both text-free so the logotype can be laid over them later:
  wide: 16:9 master, cropped for the header, main and small capsules, the page background and the
        library hero. The cell sits right of centre; the left third stays calm for the logo.
  tall: 2:3 master, cropped for the vertical and library capsules. The cell sits low; the top
        third stays calm for the logo.

Writes docs/store/keyart/keyart_<framing>.png.
Run: python tools/blender/render_store_keyart.py [--framing wide|tall|both] [--samples N] [--scale PERCENT]
"""
import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402
import render_micro_mood as mood  # noqa: E402

OUT = os.path.join(ld.ROOT, "docs", "store", "keyart")

# Per framing: resolution, where the camera looks, its pitch and distance, the vertical field of
# view, and an offset that slides the cell off centre to leave room for the logo.
FRAMINGS = {
    "wide": {"res": (3840, 2160), "pitch": 34.0, "distance": 5.0, "fov": 34.0, "shift": (-0.24, 0.04)},
    "tall": {"res": (2160, 3240), "pitch": 38.0, "distance": 5.6, "fov": 44.0, "shift": (0.0, 0.2)},
}


HERO_YAW = 192.0   # degrees: a three-quarter view of the cell's face, looking a little past the camera


def hero_camera(spec, fstop):
    """Look down at the player cell from a lower, closer angle than play, with shallow focus on it."""
    cam_data = bpy.data.cameras.new("KeyCam")
    cam = bpy.data.objects.new("KeyCam", cam_data)
    bpy.context.collection.objects.link(cam)
    pitch = math.radians(spec["pitch"])
    # Orbit a little to the left so the hero cell turns its face toward the camera.
    yaw = math.radians(-18.0)
    target = Vector((0.0, 0.0, 0.1))
    offset = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam.location = target + offset * spec["distance"]
    cam.rotation_euler = (math.pi / 2 - pitch, 0.0, yaw)
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(spec["fov"])
    cam_data.shift_x, cam_data.shift_y = spec["shift"]
    cam_data.dof.use_dof = True
    cam_data.dof.focus_distance = spec["distance"]
    cam_data.dof.aperture_fstop = fstop
    bpy.context.scene.camera = cam
    return cam


def render(framing, samples, scale, fstop):
    rng = random.Random(7)
    cell = mood.build(rng)
    for root in cell:
        # Turn the cell to face the camera (Blender front is +Y; the camera sits on the -Y side).
        root.rotation_euler = (0.0, 0.0, math.radians(HERO_YAW))
    spec = FRAMINGS[framing]
    hero_camera(spec, fstop)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.volume_step_rate = 4.0
    scene.cycles.max_bounces = 6
    scene.cycles.transmission_bounces = 6
    scene.render.resolution_x, scene.render.resolution_y = spec["res"]
    scene.render.resolution_percentage = scale
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.55
    scene.render.image_settings.file_format = "PNG"
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"keyart_{framing}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("saved", path)


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--framing", choices=["wide", "tall", "both"], default="both")
    parser.add_argument("--samples", type=int, default=64)
    parser.add_argument("--scale", type=int, default=100)
    parser.add_argument("--fstop", type=float, default=0.2)
    args = parser.parse_args(argv)
    for framing in (["wide", "tall"] if args.framing == "both" else [args.framing]):
        render(framing, args.samples, args.scale, args.fstop)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
