"""Pre-blurred backdrop organisms for the pool's ambience (game/scenes/pool/ambience/): huge,
slow microorganisms seen far below the swim plane, out of focus. They are drawn as flat quads,
so each one is rendered from above in Blender on a clear background and blurred here; the game
needs no depth of field (it does not run in the Compatibility renderer).

The designs are original and follow the micro-world mood frame (tools/blender/render_micro_mood.py,
docs/DECISIONS.md "The cell stage reads as a microscopic world"). Colours stay clear of the food
green and the threat pink.

Writes:
  assets/source/blender/ambience_backdrops.blend   every organism, editable, side by side
  assets/export/ambience/T_Backdrop_<name>.png     512 px, sRGB, straight alpha, pre-blurred
Run: python tools/blender/make_ambience_backdrops.py [--sigma PX]
"""
import argparse
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402
import render_micro_mood as mm  # noqa: E402

OUT = os.path.join(ld.ROOT, "assets", "export", "ambience")
BLEND = os.path.join(ld.ROOT, "assets", "source", "blender", "ambience_backdrops.blend")
SIZE = 512


def ciliate(rng):
    body = mm.soft("M_GiantCiliate", "#B8C0E8", 0.4, sss=0.5, emit="#C8D0F0", emit_strength=0.25)
    hairs = mm.soft("M_GiantCiliaHair", "#D0D8F2", 0.5)
    objs = mm.giant_ciliate((0.0, 0.0, 0.0), 8.0, body, hairs, rng)
    for o in objs:
        o.rotation_euler = (0.0, 0.0, 0.5)
    # A dark gullet groove and a few food vacuoles inside, seen through the skin.
    vac = mm.soft("M_Vacuole", "#9AA6D8", 0.3)
    for i in range(7):
        mm.uv_sphere(f"Vacuole{i}", 0.18 + 0.12 * rng.random(), (rng.uniform(-0.6, 0.6), rng.uniform(-1.8, 1.8), 0.4), vac, 16, 8)
    return 9.0


def colony(rng):
    mat = mm.soft("M_Colony", "#E0B088", 0.4, sss=0.6, emit="#E8BC94", emit_strength=0.15)
    beads = []
    for i in range(30):
        a = i / 30 * math.tau
        r = 3.0 + 0.25 * math.sin(i * 1.7)
        beads.append(mm.uv_sphere(f"Bead{i}", 0.55 + 0.15 * math.sin(i * 2.3), (r * math.cos(a), r * math.sin(a), 0.0), mat, 20, 10))
    return 8.4


def radiolarian(rng):
    shell = mm.glass("M_RadShell", "#D6E8F4", 0.15, rim=1.6)
    core = mm.soft("M_RadCore", "#E7C68B", 0.3, sss=0.4, emit="#F2C26B", emit_strength=0.3)
    mm.radiolarian("Radiolarian", 2.5, (0.0, 0.0, 0.0), rng, shell, core)
    return 9.0


def diatom(rng):
    shell = mm.glass("M_DiatomShell", "#CFE0F0", 0.18, rim=1.4)
    mm.diatom("Diatom", 3.6, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), shell)
    return 8.0


def filament(rng):
    """A long coiled filament of cells, lavender, like a spiral chain drifting."""
    mat = mm.soft("M_Filament", "#B9A6E0", 0.4, sss=0.5, emit="#C8B8EA", emit_strength=0.15)
    for i in range(48):
        t = i / 47
        a = t * math.tau * 2.2
        r = 0.6 + 3.0 * t
        mm.uv_sphere(f"Link{i}", 0.32, (r * math.cos(a), r * math.sin(a), 0.0), mat, 16, 8, (1.0, 1.0, 0.8))
    return 8.4


ORGANISMS = {"ciliate": ciliate, "colony": colony, "radiolarian": radiolarian, "diatom": diatom, "filament": filament}


def _stage(extent):
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Below")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = ld.color("#4C8FD0")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 20), rotation=(math.radians(20), math.radians(-15), 0))
    bpy.context.object.data.energy = 3.0
    cam_data = bpy.data.cameras.new("Top")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = extent
    cam = bpy.data.objects.new("Top", cam_data)
    cam.location = (0.0, 0.0, 30.0)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"


def _blur(rgba, sigma):
    """Gaussian blur of straight-alpha RGBA (premultiplied while blurring, so edges stay clean)."""
    radius = int(3 * sigma)
    x = np.arange(-radius, radius + 1)
    kernel = np.exp(-(x * x) / (2.0 * sigma * sigma))
    kernel /= kernel.sum()
    pre = rgba.copy()
    pre[..., :3] *= pre[..., 3:4]
    for axis in (0, 1):
        pad = [(0, 0)] * 3
        pad[axis] = (radius, radius)
        padded = np.pad(pre, pad)
        out = np.zeros_like(pre)
        for i, k in enumerate(kernel):
            out += k * np.take(padded, range(i, i + pre.shape[axis]), axis=axis)
        pre = out
    alpha = pre[..., 3:4]
    pre[..., :3] = np.where(alpha > 1e-4, pre[..., :3] / np.maximum(alpha, 1e-4), 0.0)
    return pre


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--sigma", type=float, default=7.0, help="blur, in pixels of the 512 px texture")
    args = parser.parse_args(argv)
    os.makedirs(OUT, exist_ok=True)
    tmp = os.path.join(OUT, "_render.png")
    keep = []
    for name, build in ORGANISMS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        extent = build(random.Random(name))
        _stage(extent * 1.15)
        bpy.context.scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)
        blurred = _blur(px, args.sigma)
        out = bpy.data.images.new(f"T_Backdrop_{name}", SIZE, SIZE, alpha=True)
        out.pixels.foreach_set(blurred.ravel())
        out.filepath_raw = os.path.join(OUT, f"T_Backdrop_{name}.png")
        out.file_format = "PNG"
        out.save()
        print("saved", out.filepath_raw)
        # Keep the organism's source for the .blend (moved aside so they sit in a row).
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, f"_{name}.blend"))
        keep.append(name)
    os.remove(tmp)
    # One editable source: every organism's scene in a single .blend.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name in keep:
        path = os.path.join(OUT, f"_{name}.blend")
        with bpy.data.libraries.load(path, link=False) as (src, dst):
            dst.objects = [n for n in src.objects if n not in ("Top",)]
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
        for obj in dst.objects:
            if obj is not None and obj.type == "MESH":
                col.objects.link(obj)
                obj.location.x += 12.0 * keep.index(name)
        os.remove(path)
    for lib in list(bpy.data.libraries):
        bpy.data.libraries.remove(lib)
    if os.path.exists(BLEND):
        os.remove(BLEND)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
