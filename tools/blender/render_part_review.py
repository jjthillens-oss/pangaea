"""Gray shape and material review views of one exported creature part GLB (finish gates 1 and 2).

Run: python tools/blender/render_part_review.py [--shape=H1_Fold:1000 ...] <glb> <out dir>
Writes mat_<view>.png (the exported materials) and gray_<view>.png (clay override) for front, side, 3/4, top.
--shape sets a handle's shape key (per mille) on every mesh that has it, to review a handle's pose.
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

VIEWS = {"front": (0, 12), "side": (90, 12), "threequarter": (35, 30), "top": (0, 85)}


def main(glb, out, shapes):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        keys = o.data.shape_keys.key_blocks if o.data.shape_keys else {}
        for name, value in shapes.items():
            if name in keys:
                keys[name].value = value
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre, size = (lo + hi) / 2, (hi - lo).length
    ld.setup_render(720, 32)
    ld.review_lighting()
    ld.ground_disc(size * 4, lo.z)
    cam = ld.camera()
    for prefix in ("mat", "gray"):
        if prefix == "gray":
            ld.override_materials(objs, ld.clay_material())
        for name, (yaw, pitch) in VIEWS.items():
            ld.aim(cam, centre, size * 2.2, yaw, pitch)
            ld.render_to(os.path.join(out, f"{prefix}_{name}.png"))


if __name__ == "__main__":
    flags = [a for a in sys.argv[1:-2] if a.startswith("--shape=")]
    main(os.path.abspath(sys.argv[-2]), os.path.abspath(sys.argv[-1]),
         {f[8:].split(":")[0]: float(f[8:].split(":")[1]) / 1000.0 for f in flags})
