"""Gate renders for the Aquatic stage's Blender assets (aquatic-r2; finish gates 1 to 3 of the asset gates): neutral
grey (clay) front, side, three-quarter and top views, the same views in the exported materials, and close-ups of
what each asset is about, all from the exported GLB under one neutral review rig scaled to the asset's size.

Run: python tools/blender/render_aquatic_review.py <asset_id> --out=DIR [--res=900] [--samples=32] [--source=PATH]
  <asset_id>  aquatic_nest or aquatic_plinth (the GLB in assets/export/ unless --source names a .glb or .blend)
Writes DIR/<asset_id>/{clay,mat}_{front,side,threequarter,top}.png and close_<name>.png.

Yaw 0 looks at the asset's front (Blender +Y, Godot -Z); a ground disc at the pivot's height (z = 0) stands in for
the sea floor, as the asset meets it in the game.
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import lookdev as ld  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VIEWS = {"front": (0.0, 12.0), "side": (90.0, 12.0), "threequarter": (35.0, 28.0), "top": (0.0, 88.0)}
# Close-ups: name -> (target: a node name or a point, distance m, yaw, pitch).
CLOSE = {
    "aquatic_nest": {"clutch": ("Clutch_1", 1.3, 200.0, 38.0), "clutches": ((0.0, 0.0, 0.3), 5.2, 200.0, 52.0),
                     "beacon": ("Beacon", 6.5, 20.0, 12.0), "rim": ((2.6, 2.8, 0.55), 2.2, 40.0, 30.0),
                     "gameplay": ((0.0, 1.5, 1.0), 9.0, 180.0, 24.0), "far": ((0.0, 0.0, 1.5), 26.0, 0.0, 9.0)},
    "aquatic_plinth": {"rim": ((0.0, 0.7, 0.0), 1.1, 0.0, 35.0), "editor": ((0.0, 0.0, 0.0), 2.9, 180.0, 22.0)},
}


def _load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.endswith(".blend"):
        with bpy.data.libraries.load(path) as (src, dst):
            dst.objects = [n for n in src.objects]
        for obj in dst.objects:
            if obj is not None and obj.type == "MESH" and not obj.name.endswith("_high"):
                bpy.context.scene.collection.objects.link(obj)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def _rig(size):
    """lookdev.review_lighting's three area lights (warm key front-left above, cool fill right, teal rim behind),
    moved out and strengthened with the asset's size so a 9 m nest is lit as a 3 m creature is."""
    k = max(1.0, size / 3.0)
    world = bpy.data.worlds.new("W_Review")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = ld.color("#5C7486")
    bg.inputs["Strength"].default_value = 0.55
    bpy.context.scene.world = world
    for name, loc, energy, rgb, area in (("Key", (-2.6, 2.4, 3.2), 260, (1.0, 0.9, 0.78), 2.0),
                                         ("Fill", (3.2, 0.6, 1.0), 70, (0.7, 0.85, 1.0), 3.0),
                                         ("Rim", (0.6, -3.2, 2.0), 180, (0.55, 1.0, 0.9), 1.5)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy * k * k
        light.color = rgb
        light.size = area * k
        obj = bpy.data.objects.new(name, light)
        obj.location = Vector(loc) * k
        obj.rotation_euler = (Vector((0.0, 0.0, 0.1 * k)) - obj.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.collection.objects.link(obj)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("asset_id")
    parser.add_argument("--out", required=True)
    parser.add_argument("--res", type=int, default=900)
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--source", default="")
    parser.add_argument("--only", default="", help="comma-separated view names (default: all)")
    args = parser.parse_args(argv)
    source = args.source or os.path.join(ROOT, "assets", "export", f"{args.asset_id}.glb")
    objs = _load(os.path.abspath(source))
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = (hi - lo).length
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, max(0.0, (lo.z + hi.z) / 2)))
    ld.setup_render(args.res, args.samples)
    _rig(size)
    ground = ld.ground_disc(size * 4.0, 0.0 if lo.z < -0.05 and args.asset_id == "aquatic_nest" else lo.z)
    cam = ld.camera(lens=50.0)
    out = os.path.join(os.path.abspath(args.out), args.asset_id)
    only = set(v for v in args.only.split(",") if v)
    names = {o.name: o for o in objs}

    def want(name):
        return not only or name in only

    for name, (target, distance, yaw, pitch) in CLOSE.get(args.asset_id, {}).items():
        if not want("close_" + name):
            continue
        point = names[target].matrix_world.translation + Vector((0.0, 0.0, 0.15 if target.startswith("Clutch") else 2.2)) \
            if isinstance(target, str) else Vector(target)
        ld.aim(cam, point, distance, yaw, pitch)
        ld.render_to(os.path.join(out, f"close_{name}.png"))
    for prefix in ("mat", "clay"):
        if prefix == "clay":
            ld.override_materials(objs, ld.clay_material())
        for name, (yaw, pitch) in VIEWS.items():
            if want(f"{prefix}_{name}"):
                ld.aim(cam, centre, size * 1.35, yaw, pitch)
                ld.render_to(os.path.join(out, f"{prefix}_{name}.png"))
    print("render_aquatic_review: wrote", out, "ground", ground.name)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
