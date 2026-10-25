"""Gray shape and material review views of one exported creature part GLB (finish gates 1 and 2).

Run: python tools/blender/render_part_review.py <glb> <out dir>
Writes mat_<view>.png (the exported materials) and gray_<view>.png (clay override) for front, side, 3/4, top.
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

VIEWS = {"front": (0, 12), "side": (90, 12), "threequarter": (35, 30), "top": (0, 85)}


def main(glb, out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
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
    main(os.path.abspath(sys.argv[-2]), os.path.abspath(sys.argv[-1]))
