"""Render one lineup of every creature part (assets/export/cpart_*.glb) at true scale, for the look review.

The parts stand on a ground plane at their pivot, in rows by what they do, each with its id under it, under
the section 6 review lighting. Writes docs/art/renders/production/cpart_lineup.jpg.

Run: python tools/blender/render_part_lineup.py
"""
import glob
import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

OUT = os.path.join(ld.RENDER_DIR, "production", "cpart_lineup.jpg")
RECORDS = os.path.join(ld.ROOT, "assets", "records")
EXPORT = os.path.join(ld.ROOT, "assets", "export")
# Rows by role; anything unlisted lands in a last row.
ROWS = [
    ["cpart_beak", "cpart_mandibles", "cpart_maw", "cpart_proboscis", "cpart_jaw", "cpart_bill", "cpart_barbels"],
    ["cpart_eye", "cpart_eye_slit", "cpart_eye_round", "cpart_eye_cluster", "cpart_eye_stalk", "cpart_compound_eye", "cpart_antenna", "cpart_lure", "cpart_gill_fan"],
    ["cpart_foot", "cpart_foot_webbed", "cpart_foot_paw", "cpart_foot_talon", "cpart_foot_frog", "cpart_foot_primate", "cpart_hoof", "cpart_flipper"],
    ["cpart_hand", "cpart_hand_paw", "cpart_hand_pincer", "cpart_hand_tentacle", "cpart_hand_primate"],
    ["cpart_claw", "cpart_claw_scythe", "cpart_claw_rake", "cpart_horn", "cpart_horn_ram", "cpart_horn_nose", "cpart_spike", "cpart_tusk", "cpart_horn_swept"],
    ["cpart_fin", "cpart_crest", "cpart_frill", "cpart_wing", "cpart_tail_fluke", "cpart_tail_spikes", "cpart_club_tail", "cpart_quills", "cpart_ear_round", "cpart_muzzle_primate", "cpart_wing_dragon", "cpart_dorsal_spine"],
]
SPACING_X = 0.42
SPACING_Y = 0.5


def part_ids():
    return sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(RECORDS, "cpart_*.json")))


def layout(ids):
    rows = [[i for i in row if i in ids] for row in ROWS]
    rest = [i for i in ids if not any(i in row for row in ROWS)]
    if rest:
        rows.append(rest)
    return [row for row in rows if row]


def import_part(asset_id, location):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(EXPORT, f"{asset_id}.glb"))
    roots = [o for o in bpy.data.objects if o not in before and o.parent is None]
    for root in roots:
        root.location = location
    return roots


def label(text, location, size=0.035):
    curve = bpy.data.curves.new(f"L_{text}", "FONT")
    curve.body = text
    curve.size = size
    curve.align_x = "CENTER"
    obj = bpy.data.objects.new(f"L_{text}", curve)
    obj.location = location
    # The camera sits on +Y looking back at the parts' faces, so the text turns round (Z) and tips toward it (X,
    # applied first: it leans the face of the text toward -Y before the turn brings that toward the camera).
    obj.rotation_euler = (math.radians(40.0), 0.0, math.pi)
    obj.data.materials.append(ld.principled("M_Label", ld.color("#E8EEF2"), 0.9))
    bpy.context.scene.collection.objects.link(obj)
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rows = layout(part_ids())
    rows.reverse()                                            # the first row lands nearest the camera, at the bottom
    width = max(len(r) for r in rows) * SPACING_X
    depth = len(rows) * SPACING_Y
    for r, row in enumerate(rows):
        y = (len(rows) - 1) / 2 * SPACING_Y - r * SPACING_Y
        for c, asset_id in enumerate(row):
            x = -(c - (len(row) - 1) / 2) * SPACING_X       # +X is the camera's left, so the row reads left to right
            import_part(asset_id, (x, y, 0.0))
            label(asset_id[len("cpart_"):], (x, y - 0.22, 0.0))
    ld.setup_render(resolution=640, samples=40)
    scene = bpy.context.scene
    scene.render.resolution_x = 2000
    scene.render.resolution_y = int(2000 * (depth + 0.3) / (width + 0.3) * 0.78)
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 88
    ld.review_lighting()
    for obj in scene.objects:
        if obj.type == "LIGHT":                      # the review rig is set for a 1 m creature; back it off
            obj.location = Vector(obj.location) * 2.6
            obj.data.energy *= 7.0
            obj.data.size *= 2.0
    ld.ground_disc(radius=20.0, z=-0.002)
    cam = ld.camera(lens=50.0)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = width + 0.3
    ld.aim(cam, (0.0, -0.05, 0.05), 8.0, 0.0, 52.0)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    scene.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    print(f"lineup: {sum(len(r) for r in rows)} parts in {len(rows)} rows -> {OUT}")


if __name__ == "__main__":
    main()
