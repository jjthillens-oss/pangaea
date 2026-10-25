"""Gate 1-3 review renders of one exported creature part (finish-hunyuan-assets gates; docs/art/creature_parts_more.md).

Run: python3 tools/blender/render_more_parts_gates.py <asset_id> <out_dir> [--res N] [--samples N] [--no-handles]

It imports what ships (assets/export/<asset_id>.glb) into a factory-empty scene and renders, under one repeatable
neutral rig (a grey environment for reflections, a broad white key, a white fill and a low white grazing light
across the part):
- Gate 1, shape: gray_front, gray_side, gray_back, gray_threequarter and gray_top in a neutral clay, and
  handle_<key> (the three-quarter view with that shape key at 1000 per mille) for each handle;
- Gates 2 and 3, materials under neutral light: mat_threequarter, mat_side and mat_close (closer, on the part's
  upper half);
- the art look for comparison: art_threequarter under lookdev.review_lighting (warm key, cool fill, teal rim).
Views follow lookdev.aim: yaw 0 looks at the part's head-facing (+Y) side, yaw 90 from +X (the right), pitch up.
Then it writes a labelled contact sheet, <asset_id>_gates.jpg, with every view and the part's size and triangles.
"""
import argparse
import json
import os
import sys

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GRAY_VIEWS = {"front": (0, 12), "side": (90, 12), "back": (180, 12), "threequarter": (35, 30), "top": (0, 85)}
MAT_VIEWS = {"threequarter": (35, 30), "side": (90, 12)}
DISTANCE = 2.2      # x the bounding box diagonal (render_part_review.py's framing)
CLOSE = 0.55        # the close-up's share of that distance


def neutral_lighting(centre, size):
    """White lights only, so colour stays the albedo's: key high front-left, fill right, and a grazing light low
    from the left side that rakes across broad surfaces to show planes, bevels and normal detail."""
    scene = bpy.context.scene
    world = bpy.data.worlds.new("W_Neutral")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = ld.color("#80868C")
    bg.inputs["Strength"].default_value = 0.6
    scene.world = world
    c = Vector(centre)

    def area(name, offset, energy, light_size):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.color = (1.0, 1.0, 1.0)
        light.size = light_size
        obj = bpy.data.objects.new(name, light)
        obj.location = c + Vector(offset)
        obj.rotation_euler = (c - obj.location).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)
        return obj

    area("NeutralKey", (-2.2, 2.4, 3.0), 240, 2.5)
    area("NeutralFill", (3.0, 1.0, 1.2), 70, 3.0)
    area("NeutralGraze", (-3.0, -0.6, 0.35 + 0.2 * size), 160, 0.6)


def handle_keys(objs):
    """[(object, key name)] for every H<n>_ shape key on the imported meshes."""
    out = []
    for obj in objs:
        keys = obj.data.shape_keys
        if keys is None:
            continue
        for kb in keys.key_blocks:
            if kb.name.startswith("H") and "_" in kb.name:
                out.append((obj, kb.name))
    return out


def contact_sheet(asset_id, out, frames, info):
    from PIL import Image, ImageDraw, ImageFont
    tiles = [(label, Image.open(path).convert("RGB")) for label, path in frames if os.path.exists(path)]
    if not tiles:
        return None
    w, h = tiles[0][1].size
    tile = 400
    cols = 5
    rows = (len(tiles) + cols - 1) // cols
    header = 44
    sheet = Image.new("RGB", (cols * tile, header + rows * (tile + 22)), (34, 38, 44))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 18)
        small = ImageFont.truetype("DejaVuSans.ttf", 15)
    except OSError:
        font = small = ImageFont.load_default()
    draw.text((10, 10), f"{asset_id}   {info}", fill=(235, 235, 235), font=font)
    for i, (label, img) in enumerate(tiles):
        x, y = (i % cols) * tile, header + (i // cols) * (tile + 22)
        sheet.paste(img.resize((tile, tile * h // w)), (x, y))
        draw.text((x + 6, y + tile + 2), label, fill=(210, 210, 210), font=small)
    path = os.path.join(out, f"{asset_id}_gates.jpg")
    sheet.save(path, quality=88)
    return path


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Gate 1-3 renders of one exported creature part.")
    parser.add_argument("asset_id")
    parser.add_argument("out_dir")
    parser.add_argument("--res", type=int, default=640)
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--no-handles", action="store_true")
    args = parser.parse_args(argv)
    glb = os.path.join(ROOT, "assets", "export", f"{args.asset_id}.glb")
    out = os.path.abspath(args.out_dir)
    os.makedirs(out, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre, size = (lo + hi) / 2, (hi - lo).length
    dims = hi - lo
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    record_path = os.path.join(ROOT, "assets", "records", f"{args.asset_id}.json")
    budget = json.load(open(record_path)).get("triangle_budget", "?") if os.path.exists(record_path) else "?"
    info = (f"{dims.x:.3f} x {dims.y:.3f} (fwd) x {dims.z:.3f} (up) m   {tris} / {budget} tris   "
            f"{len(objs)} mesh(es)   z {lo.z:.3f}..{hi.z:.3f}")
    print(args.asset_id, info)

    ld.setup_render(args.res, args.samples)
    neutral_lighting(centre, size)
    ld.ground_disc(max(size * 14, 2.0), lo.z)
    cam = ld.camera()
    frames = []

    def shot(name, target, distance, yaw, pitch):
        path = os.path.join(out, f"{name}.png")
        ld.aim(cam, target, distance, yaw, pitch)
        ld.render_to(path)
        frames.append((name, path))

    # Gates 2 and 3: the shipped materials under the neutral rig.
    for name, (yaw, pitch) in MAT_VIEWS.items():
        shot(f"mat_{name}", centre, size * DISTANCE, yaw, pitch)
    upper = Vector((centre.x, centre.y, centre.z + 0.25 * dims.z))
    shot("mat_close", upper, size * DISTANCE * CLOSE, 30, 22)

    # Gate 1: clay, every side, then each handle at full.
    ld.override_materials(objs, ld.clay_material())
    for name, (yaw, pitch) in GRAY_VIEWS.items():
        shot(f"gray_{name}", centre, size * DISTANCE, yaw, pitch)
    if not args.no_handles:
        for obj, key in handle_keys(objs):
            kb = obj.data.shape_keys.key_blocks[key]
            kb.value = 1.0
            shot(f"handle_{key}", centre, size * DISTANCE * 1.15, 35, 30)
            kb.value = 0.0

    # The art look, for comparison with the other parts' review sheets: a fresh import with its own materials.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    ld.setup_render(args.res, args.samples)
    ld.review_lighting()
    ld.ground_disc(max(size * 14, 2.0), lo.z)
    cam = ld.camera()
    shot("art_threequarter", centre, size * DISTANCE, 35, 30)

    sheet = contact_sheet(args.asset_id, out, frames, info)
    print("sheet", sheet)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
