"""Gray shape and material review views of one exported creature part GLB (finish gates 1 and 2).

Run: python tools/blender/render_part_review.py [--shape=H1_Fold:1000 ...] [--stand] [--views=front,side,...]
     [--dist=2.2] [--size=720] <glb> <out dir>
Writes mat_<view>.png (the exported materials) and gray_<view>.png (clay override) for front, side, 3/4, top.
--shape sets a handle's shape key (per mille) on every mesh that has it, to review a handle's pose.
--stand stands a skin-mounted face part up as it sits on a head (its +Z, out of the face, toward the front camera;
its +Y, toward the brow, up), so the side view shows its profile. --views picks views from VIEWS (also low34, a
three-quarter from below, and back); --dist is the camera distance in bounding-box diagonals (closer than 2.2 for a
small part); --size is the square frame size in pixels.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

VIEWS = {"front": (0, 12), "side": (90, 12), "threequarter": (35, 30), "top": (0, 85), "low34": (35, -12), "back": (180, 10)}
STAND_VIEWS = {"front": (180, 5), "side": (270, 3), "threequarter": (140, 18), "low34": (145, -12), "back": (0, 10), "top": (180, 80)}


def main(glb, out, shapes, stand=False, views=("front", "side", "threequarter", "top"), dist=2.2, size=720):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        keys = o.data.shape_keys.key_blocks if o.data.shape_keys else {}
        for name, value in shapes.items():
            if name in keys:
                keys[name].value = value
    if stand:
        turn = Matrix.Rotation(math.radians(90.0), 4, "X")      # +Z (out of the face) to -Y, +Y (brow) to +Z
        for o in bpy.context.scene.objects:
            if o.parent is None:
                o.matrix_world = turn @ o.matrix_world
        bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre, extent = (lo + hi) / 2, (hi - lo).length
    ld.setup_render(size, 32)
    ld.review_lighting()
    ld.ground_disc(extent * 4, lo.z)
    cam = ld.camera()
    table = STAND_VIEWS if stand else VIEWS
    for prefix in ("mat", "gray"):
        if prefix == "gray":
            ld.override_materials(objs, ld.clay_material())
        for name in views:
            yaw, pitch = table[name]
            ld.aim(cam, centre, extent * dist, yaw, pitch)
            ld.render_to(os.path.join(out, f"{prefix}_{name}.png"))


if __name__ == "__main__":
    args = sys.argv[1:-2]
    flags = {a.split("=", 1)[0]: a.split("=", 1)[1] for a in args if "=" in a and not a.startswith("--shape=")}
    shape_flags = [a for a in args if a.startswith("--shape=")]
    main(os.path.abspath(sys.argv[-2]), os.path.abspath(sys.argv[-1]),
         {f[8:].split(":")[0]: float(f[8:].split(":")[1]) / 1000.0 for f in shape_flags},
         stand="--stand" in args,
         views=tuple(flags.get("--views", "front,side,threequarter,top").split(",")),
         dist=float(flags.get("--dist", "2.2")), size=int(flags.get("--size", "720")))
