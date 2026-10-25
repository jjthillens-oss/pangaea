"""The Aquatic stage's sea floor (PROPOSED, docs/stages/aquatic-plan.md section 8).

- aquatic_seafloor: one strip of sea floor from the sunlit shore down the reef slope into the deep, 112 m across and
  440 m long. Its centre line follows the floor profile in game/data/aquatic/aquatic_rules.json ("world.floor"), the
  one source the sim's floor_y() also reads, so the fish never swims into the ground; the sides rise into rock walls
  past |x| = 36 m (AquaticSim.wall_rise, the same formula), and the shore end rises out of the water as a beach.
  Relief inside the swim lane stays under RELIEF_M, inside the sim's floor margin. Drawn with the external
  M_AquaticSeafloor.tres (assets/export/shaders/aquatic_seafloor.gdshader): sand ripples on the flats, dark rock on
  the slopes, both shaded deeper with depth, in world space, with a baked seamless sand tile and its normal map (TILE_M across).

Axes: Blender +Y forward is Godot -Z, so the shore (Godot z = +34) is at Blender y = -34 and the deep at +380.

Run: python tools/blender/make_aquatic_world.py   (bpy 5.2.2)
Then godot --headless --import, python tools/blender/make_aquatic_world.py --import, and --import again.
"""
import argparse
import json
import math
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import make_membranes as mm  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

GENERATOR = "tools/blender/make_aquatic_world.py"
REVIEW_STATE = "production rev 1 - M1, awaiting owner look review"
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_aquatic_world.py from the floor profile in "
              "game/data/aquatic/aquatic_rules.json; no external or generated meshes. The sand tile is periodic noise in numpy, so it repeats without seams.")
RULES = os.path.join(bc.ROOT, "game", "data", "aquatic", "aquatic_rules.json")
HALF_X = 56.0
STEP_X = 2.0
STEP_Z = 2.5
BEYOND_Z = 6.0          # past the sim's ends, so the edges are out of the lane
RELIEF_M = 0.35
WALL_START = 36.0       # AquaticSim.WALL_START
WALL_SPAN = 16.0        # AquaticSim.WALL_SPAN
WALL_HEIGHT = 16.0      # AquaticSim.WALL_HEIGHT
BEACH_RISE = 3.0        # the shore end climbs this far above the water past the sim's shore


def _rules():
    with open(RULES) as f:
        return json.load(f)


def floor_y(points, z):
    """AquaticSim.floor_y: the profile's points joined by straight lines (Godot z, Godot y)."""
    if z >= points[0][0]:
        return points[0][1]
    for a, b in zip(points, points[1:]):
        if z >= b[0]:
            return a[1] + (b[1] - a[1]) * (z - a[0]) / (b[0] - a[0])
    return points[-1][1]


def wall_rise(x):
    """AquaticSim.wall_rise: the side walls, smoothstep from WALL_START over WALL_SPAN."""
    t = min(1.0, max(0.0, (abs(x) - WALL_START) / WALL_SPAN))
    return WALL_HEIGHT * bc.smoothstep(t)


TILE_DIR = os.path.join(bc.ROOT, "assets", "export", "aquatic_seafloor")
TILE_M = 3.0            # one sand tile per 3 m, sampled in world space by the shader


def _save_tile(name, rgb, colorspace):
    """rgb: (SIZE, SIZE, 3) in display order, row 0 at the top; Blender stores rows bottom-up."""
    size = mm.SIZE
    px = np.ones((size, size, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb[::-1], 0.0, 1.0)
    img = bpy.data.images.new(name, size, size, alpha=False)
    img.colorspace_settings.name = "Non-Color"     # values are written as-is; sRGB data is already encoded
    img.pixels.foreach_set(px.ravel())
    os.makedirs(TILE_DIR, exist_ok=True)
    img.filepath_raw = os.path.join(TILE_DIR, f"{name}.png")
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return {"name": name, "path": f"assets/export/aquatic_seafloor/{name}.png", "size": [size, size], "colorspace": colorspace}


def sand_tiles():
    """A seamless sand tile: wind-free ripple crests (periodic, so they wrap) over fine grain, and its normal map.
    The albedo is a light neutral detail the shader multiplies into its depth-shaded sand and rock colours."""
    rng = np.random.default_rng(7301)
    size = mm.SIZE
    yy, xx = np.mgrid[0:size, 0:size] / float(size)
    warp = mm._norm(mm._periodic_noise(rng, [2, 4], [1.0, 0.5]))
    ripple = 0.5 + 0.5 * np.sin(2.0 * np.pi * (5.0 * xx + 1.0 * yy) + 2.5 * warp * 2.0 * np.pi / 6.0)
    grain = mm._norm(mm._periodic_noise(rng, [48, 96, 160], [0.6, 0.4, 0.3]))
    blotch = mm._norm(mm._periodic_noise(rng, [3, 6], [1.0, 0.5]))
    h = 0.6 * ripple + 0.25 * grain + 0.15 * blotch
    light = np.clip(0.72 + 0.16 * ripple + 0.12 * grain - 0.1 * blotch, 0.0, 1.0)
    rgb = np.repeat(light[..., None], 3, axis=-1)
    return [_save_tile("T_AquaticSeafloor_Sand", rgb, "sRGB"),
            _save_tile("T_AquaticSeafloor_Normal", mm._normal_map(mm._norm(h), 1.2), "Non-Color")]


def build_seafloor():
    rules = _rules()
    w = rules["world"]
    points = [(float(p[0]), float(p[1])) for p in w["floor"]]
    z_hi = float(w["shore_z"]) + BEYOND_Z
    z_lo = float(w["end_z"]) - BEYOND_Z
    nx = int(round(2 * HALF_X / STEP_X)) + 1
    nz = int(round((z_hi - z_lo) / STEP_Z)) + 1
    verts, faces = [], []
    lane = []
    for j in range(nz):
        gz = z_hi - (z_hi - z_lo) * j / (nz - 1)
        for i in range(nx):
            x = -HALF_X + 2 * HALF_X * i / (nx - 1)
            y = floor_y(points, gz) + wall_rise(x)
            if gz > float(w["shore_z"]):
                y += BEACH_RISE * bc.smoothstep(min(1.0, (gz - float(w["shore_z"])) / BEYOND_Z))
            n = noise.noise(Vector((x / 9.0 + 1.7, gz / 9.0 - 4.2, 0.3))) * 0.7 + noise.noise(Vector((x / 3.0, gz / 3.0, 5.1))) * 0.3
            walled = wall_rise(x) / WALL_HEIGHT
            # On the walls the rock only dips under the sim's wall line, so a fish never swims inside it.
            y += RELIEF_M * n * (1.0 - walled) - 2.2 * walled * abs(noise.noise(Vector((x / 5.0, gz / 5.0, 8.8))))
            if abs(x) <= WALL_START and float(w["end_z"]) <= gz <= float(w["shore_z"]):
                lane.append(y - floor_y(points, gz) - wall_rise(x))
            verts.append((x, -gz, y))   # Blender (x, y forward, z up) from Godot (x, z, y)
    for j in range(nz - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + 1, a + nx + 1, a + nx))
    mat = bc.material("M_AquaticSeafloor", (0.42, 0.38, 0.30), 0.95)
    bc.mesh_object("AquaticSeafloor", verts, faces, [mat], fix_normals=False, uv=lambda co: (co.x / 4.0, co.y / 4.0))
    bc.bpy.context.view_layer.update()
    obj = bc.bpy.data.objects["AquaticSeafloor"]
    # Faces must point up (+Z): the strip is built row by row towards +Y.
    up = sum(1 for p in obj.data.polygons if p.normal.z > 0)
    if up < len(obj.data.polygons) * 0.95:
        obj.data.flip_normals()
    if max(abs(v) for v in lane) > RELIEF_M + 1e-6:
        raise RuntimeError("seafloor: relief inside the lane is over %.2f m" % RELIEF_M)
    return {"purpose": "Aquatic stage sea floor (PROPOSED): the reef-to-deep route's ground, its centre line on the floor profile in aquatic_rules.json, rock walls past |x| = 36 m and a beach at the shore; sand and rock shaded in world space by M_AquaticSeafloor.tres.",
            "category": "environment", "kind": "ground",
            "pivot": "the world origin (Godot y = 0 is the water's surface); the nest sits at z = +8",
            "engine_material": "res://assets/export/M_AquaticSeafloor.tres",
            "swim_lane": {"half_width_m": float(w["half_width"]), "relief_max_m": RELIEF_M, "wall_start_m": WALL_START,
                          "wall_span_m": WALL_SPAN, "wall_height_m": WALL_HEIGHT},
            "textures": sand_tiles(), "revision": 1}


SEAFLOOR_TRES = """[gd_resource type="ShaderMaterial" load_steps=4 format=3]

[ext_resource type="Shader" path="res://assets/export/shaders/aquatic_seafloor.gdshader" id="1"]
[ext_resource type="Texture2D" path="res://assets/export/aquatic_seafloor/T_AquaticSeafloor_Sand.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/export/aquatic_seafloor/T_AquaticSeafloor_Normal.png" id="3"]

[resource]
resource_name = "M_AquaticSeafloor"
shader = ExtResource("1")
shader_parameter/sand_tex = ExtResource("2")
shader_parameter/sand_normal = ExtResource("3")
shader_parameter/tile_m = {tile}
"""

EXTERNAL = {"aquatic_seafloor": {"M_AquaticSeafloor": "M_AquaticSeafloor"}}


def map_materials():
    export = os.path.join(bc.ROOT, "assets", "export")
    with open(os.path.join(export, "M_AquaticSeafloor.tres"), "w") as f:
        f.write(SEAFLOOR_TRES.format(tile=TILE_M))
    for asset_id, mats in EXTERNAL.items():
        path = os.path.join(export, f"{asset_id}.glb.import")
        with open(path) as f:
            text = f.read()
        entries = ",\n".join('"{m}": {{\n"use_external/enabled": true,\n"use_external/fallback_path": "res://assets/export/{t}.tres",\n'
                              '"use_external/path": "res://assets/export/{t}.tres"\n}}'.format(m=m, t=t) for m, t in mats.items())
        mapping = "_subresources={\n\"materials\": {\n" + entries + "\n}\n}"
        text = re.sub(r"_subresources=\{.*?\n\}(?=\n|$)", mapping, text, flags=re.S) if "_subresources={\n" in text \
            else text.replace("_subresources={}", mapping)
        with open(path, "w") as f:
            f.write(text)
        print("mapped", ", ".join(f"{m} -> {t}" for m, t in mats.items()), "in", os.path.basename(path))
    path = os.path.join(TILE_DIR, "T_AquaticSeafloor_Normal.png.import")
    with open(path) as f:
        text = f.read()
    with open(path, "w") as f:
        f.write(re.sub(r"^compress/normal_map=.*$", "compress/normal_map=1", text, flags=re.M))


ASSETS = {"aquatic_seafloor": (build_seafloor, 24000)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the Aquatic stage's sea floor.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    parser.add_argument("--import", dest="map_only", action="store_true", help="only write the engine material and the .import mapping")
    args = parser.parse_args(argv)
    if args.map_only:
        map_materials()
        return
    ids = [i for i in args.only.split(",") if i] or list(ASSETS)
    for asset_id in ids:
        builder, budget = ASSETS[asset_id]
        bc.reset_scene()
        fields = builder()
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR, provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
