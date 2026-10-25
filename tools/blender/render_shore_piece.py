"""Gate renders for the shore piece (docs/art/shore_piece.md), in Blender, into a scratch folder.

Opens a shore_piece .blend (the repo's by default, or a --rough build from make_shore_piece.py),
scales it down so the review rig (lookdev.review_lighting, sized for a 1 m creature) lights it the
same way it lights every other asset, and writes to --out:

  gray_front, gray_side, gray_three_quarter, gray_south   neutral clay, no normal map (Gate 1 shape)
  gray_top                                                orthographic plan: the outline is not a disc
  gray_game, gray_game_approach                           clay at the gameplay camera (55 deg, 45 deg, 14 m)
                                                          at the shore point and 10 m south of it
  grazing                                                 clay with the asset's normal map (or its procedural
                                                          bump) under a low sun: the ripples
  beauty_game, beauty_game_approach, beauty_three_quarter neutral review lighting, the asset's materials
  close_crest, close_grains                               material close-ups (Gate 2)
  light_layout                                            the shaft and reach ring drawn as soft light
  sheet_gray.jpg, sheet_beauty.jpg                        contact sheets (ImageMagick montage, if installed)

With --audit it also writes the baked albedo as albedo.png and prints its LAB statistics against the
pool's rules (linear luminance at most 0.40; at most 2% of texels with chroma 12 or more within 25
degrees of LAB hue of the food #CFE86A or the threat #D9466B).

Run: python tools/blender/render_shore_piece.py [--blend PATH] [--out DIR] [--only a,b] [--samples N] [--audit]
"""
import argparse
import glob
import math
import os
import shutil
import subprocess
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

DEFAULT_BLEND = os.path.join(ld.ROOT, "assets", "source", "blender", "shore_piece.blend")
DEFAULT_OUT = "/home/user/xdg/shore/scratch/gates"
SCALE = 0.04                    # about 33 m of landing becomes 1.3 units under the 1 m review rig
LIGHT_NODES = ("Shaft", "Reach")
FOOD, THREAT = "#CFE86A", "#D9466B"


def _scale_scene():
    for obj in bpy.context.scene.objects:
        if obj.parent is None:
            obj.location = [o * SCALE for o in obj.location]
            obj.scale = [s * SCALE for s in obj.scale]
    bpy.context.view_layer.update()


def _meshes(include_light=False):
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and (include_light or o.name not in LIGHT_NODES)]


def _show_light(show):
    for name in LIGHT_NODES:
        obj = bpy.data.objects.get(name)
        if obj is not None:
            obj.hide_render = not show


def _clay_with_normals():
    """Clay that keeps the asset's relief: the baked normal map if there is one, else the procedural bump."""
    mat = bpy.data.materials.new("M_ClayRelief")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = ld.color("clay")
    bsdf.inputs["Roughness"].default_value = 0.6
    img = bpy.data.images.get("T_ShorePiece_Normal")
    if img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        return mat
    src = bpy.data.materials.get("M_ShoreSand")
    if src is None:
        return mat
    copy = src.copy()
    copy.name = "M_ClayRelief"
    b = copy.node_tree.nodes["Principled BSDF"]
    for name in ("Base Color", "Roughness"):
        for link in list(b.inputs[name].links):
            copy.node_tree.links.remove(link)
    b.inputs["Base Color"].default_value = ld.color("clay")
    b.inputs["Roughness"].default_value = 0.6
    bpy.data.materials.remove(mat)
    return copy


def _light_preview():
    """A soft additive look for the engine-drawn parts: emission through transparency."""
    mat = bpy.data.materials.new("M_LightPreview")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    add = nt.nodes.new("ShaderNodeAddShader")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = ld.color("#FFD486")
    emit.inputs["Strength"].default_value = 0.35
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    nt.links.new(emit.outputs["Emission"], add.inputs[0])
    nt.links.new(clear.outputs["BSDF"], add.inputs[1])
    nt.links.new(add.outputs["Shader"], out.inputs["Surface"])
    return mat


def _game_camera(cam, focus, aspect=(1280, 720)):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = aspect
    cam.data.type = "PERSP"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(ld.GAME_CAMERA["fov_deg"])
    ld.aim(cam, Vector(focus) * SCALE, ld.GAME_CAMERA["distance"] * SCALE, 180.0, ld.GAME_CAMERA["pitch_deg"])


def _orbit(cam, target, distance, yaw, pitch, lens=50.0, res=640):
    scene = bpy.context.scene
    scene.render.resolution_x = scene.render.resolution_y = res
    cam.data.type = "PERSP"
    cam.data.sensor_fit = "AUTO"
    cam.data.lens = lens
    ld.aim(cam, Vector(target) * SCALE, distance * SCALE, yaw, pitch)


def _top(cam, res=720):
    scene = bpy.context.scene
    scene.render.resolution_x = scene.render.resolution_y = res
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 54.0 * SCALE
    cam.location = (0.0, -6.0 * SCALE, 30.0 * SCALE)
    cam.rotation_euler = (0.0, 0.0, 0.0)


def _grazing_sun():
    sun = bpy.data.lights.new("Grazing", "SUN")
    sun.energy = 3.0
    sun.angle = math.radians(2.0)
    obj = bpy.data.objects.new("Grazing", sun)
    # Low from the west-north-west, 9 degrees above the horizon, raking across the ripple crests.
    direction = Vector((math.cos(math.radians(9)) * math.cos(math.radians(160)),
                        math.cos(math.radians(9)) * math.sin(math.radians(160)), math.sin(math.radians(9))))
    obj.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_render = True
    return obj


VIEWS = {
    # name: (material mode, light parts shown, camera setup)
    "gray_front": ("clay", False, lambda c: _orbit(c, (0, -4, -8), 95, 0, 18)),
    "gray_side": ("clay", False, lambda c: _orbit(c, (0, -4, -8), 95, 90, 18)),
    "gray_three_quarter": ("clay", False, lambda c: _orbit(c, (0, -4, -8), 95, 35, 30)),
    "gray_south": ("clay", False, lambda c: _orbit(c, (0, -4, -8), 95, 215, 30)),
    "gray_top": ("clay", False, _top),
    "gray_game": ("clay", False, lambda c: _game_camera(c, (0, 0, 0))),
    "gray_game_approach": ("clay", False, lambda c: _game_camera(c, (0, -10, 0))),
    "grazing": ("relief", False, lambda c: _game_camera(c, (0, -2, 0))),
    "beauty_game": ("beauty", False, lambda c: _game_camera(c, (0, 0, 0))),
    "beauty_game_approach": ("beauty", False, lambda c: _game_camera(c, (0, -10, 0))),
    "beauty_three_quarter": ("beauty", False, lambda c: _orbit(c, (0, 0, -8), 80, 215, 30)),
    "close_crest": ("beauty", False, lambda c: _orbit(c, (1.5, -2.5, -2.0), 6.5, 200, 38, lens=50.0)),
    "close_grains": ("beauty", False, lambda c: _orbit(c, (2.6, -6.4, -2.6), 5.0, 205, 34, lens=50.0)),
    "light_layout": ("beauty", True, lambda c: _orbit(c, (0, 0, -2), 40, 205, 30)),
}


def audit(out):
    img = bpy.data.images.get("T_ShorePiece_Albedo")
    if img is None:
        print("audit: no baked albedo in this .blend (a --rough build?)")
        return
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[..., :3]
    # Blender hands sRGB images back as sRGB-encoded floats.
    srgb = np.clip(px, 0.0, 1.0)
    lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
    luma = lin @ np.array([0.2126, 0.7152, 0.0722])
    xyz = lin @ np.array([[0.4124, 0.2126, 0.0193], [0.3576, 0.7152, 0.1192], [0.1805, 0.0722, 0.9505]])
    xyz = xyz / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    C = np.hypot(a, b)
    hue = (np.degrees(np.arctan2(b, a)) + 360.0) % 360.0

    def lab_hue(hexstr):
        c = np.array([int(hexstr[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])
        c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
        x = c @ np.array([[0.4124, 0.2126, 0.0193], [0.3576, 0.7152, 0.1192], [0.1805, 0.0722, 0.9505]]) / np.array([0.95047, 1.0, 1.08883])
        ff = np.where(x > 216 / 24389, np.cbrt(x), (24389 / 27 * x + 16) / 116)
        return (math.degrees(math.atan2(200 * (ff[1] - ff[2]), 500 * (ff[0] - ff[1]))) + 360.0) % 360.0

    def near(h0):
        d = np.abs((hue - h0 + 180.0) % 360.0 - 180.0)
        return (C >= 12.0) & (d < 25.0)

    food, threat = lab_hue(FOOD), lab_hue(THREAT)
    chroma = C >= 12.0
    print(f"audit: {w}x{h} albedo; linear luminance max {luma.max():.3f}, p99 {np.percentile(luma, 99):.3f}, median {np.median(luma):.3f}")
    print(f"audit: L* median {np.median(L):.1f} (p5 {np.percentile(L, 5):.1f}, p95 {np.percentile(L, 95):.1f}); "
          f"chroma median {np.median(C):.1f}, p95 {np.percentile(C, 95):.1f}")
    print(f"audit: hue of chroma-12+ texels ({chroma.mean() * 100:.1f}% of all): p5 {np.percentile(hue[chroma], 5):.1f}, "
          f"median {np.median(hue[chroma]):.1f}, p95 {np.percentile(hue[chroma], 95):.1f} deg")
    print(f"audit: within 25 deg of food (h {food:.1f}): {near(food).mean() * 100:.2f}%; "
          f"of threat (h {threat:.1f}): {near(threat).mean() * 100:.2f}% (limit 2% each)")
    copy = img.copy()
    copy.filepath_raw = os.path.join(out, "albedo.png")
    copy.file_format = "PNG"
    copy.save()
    print("audit: wrote", copy.filepath_raw)


def main(argv):
    parser = argparse.ArgumentParser(description="Gate renders for the shore piece.")
    parser.add_argument("--blend", default=DEFAULT_BLEND)
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--only", default="")
    parser.add_argument("--samples", type=int, default=40)
    parser.add_argument("--audit", action="store_true")
    args = parser.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.blend))
    os.makedirs(args.out, exist_ok=True)
    if args.audit:
        audit(args.out)
    _scale_scene()
    ld.setup_render(640, args.samples)
    ld.review_lighting()
    cam = ld.camera(lens=50.0)
    cam.data.clip_start = 0.01
    cam.data.clip_end = 100.0
    grazing = _grazing_sun()
    review = [o for o in bpy.context.scene.objects if o.type == "LIGHT" and o.name != "Grazing"]
    clay = ld.clay_material()
    relief = _clay_with_normals()
    preview = _light_preview()
    light_objs = [bpy.data.objects[n] for n in LIGHT_NODES if n in bpy.data.objects]
    saved_light = {o.name: o.material_slots[0].material for o in light_objs if o.material_slots}
    for o in light_objs:
        o.material_slots[0].material = preview
    only = [v for v in args.only.split(",") if v]
    for name, (mode, show_light, setup) in VIEWS.items():
        if only and name not in only:
            continue
        _show_light(show_light)
        setup(cam)
        restore = None
        if mode in ("clay", "relief"):
            restore = ld.override_materials(_meshes(), clay if mode == "clay" else relief)
        is_grazing = name == "grazing"
        grazing.hide_render = not is_grazing
        for light in review:
            light.hide_render = is_grazing
        world_strength = bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"]
        keep = world_strength.default_value
        if is_grazing:
            world_strength.default_value = 0.12
        ld.render_to(os.path.join(args.out, f"{name}.png"))
        world_strength.default_value = keep
        if restore:
            restore()
        print("rendered", name)
    for o in light_objs:
        if o.name in saved_light:
            o.material_slots[0].material = saved_light[o.name]
    if shutil.which("montage"):
        for label, names in (("gray", ["gray_front", "gray_side", "gray_three_quarter", "gray_south", "gray_top", "gray_game", "gray_game_approach", "grazing"]),
                             ("beauty", ["beauty_game", "beauty_game_approach", "beauty_three_quarter", "close_crest", "close_grains", "light_layout"])):
            tiles = [os.path.join(args.out, f"{n}.png") for n in names if os.path.exists(os.path.join(args.out, f"{n}.png"))]
            if tiles:
                subprocess.run(["montage", *tiles, "-tile", "4x", "-geometry", "480x360+3+3", "-background", "#22303A",
                                "-quality", "88", os.path.join(args.out, f"sheet_{label}.jpg")], check=True)
    print("done:", sorted(os.path.basename(p) for p in glob.glob(os.path.join(args.out, "*.png"))))


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
