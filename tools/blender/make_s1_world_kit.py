"""Rough versions of the endless world's step S1 art (/mnt/project-files/pangaea/docs/endless-cell-plan.md,
section I): the band-0 shell kit, six landmarks, two rare set pieces and the two wayfinding markers.

These are blockouts in flat colours, sized and placed so engineering can wire the world in early.
Each will be swapped for a finished piece with the same id, node names and footprint. The landmark
and set-piece shapes come from the concept sheet (tools/blender/render_landmark_concepts.py). Ids,
footprint classes and record fields are PROPOSED until engineering's S1 build plan pins them.

Units: 1 m = 1 band unit at band 0. Blender +Z is up, +Y is forward (Godot -Z). Every piece is
centred on its anchor or footprint on the swim plane (z = 0). Colours keep clear of the food green
and the threat pink.

For every asset id this writes assets/source/blender/<id>.blend, assets/export/<id>.glb and
assets/records/<id>.json.
Run: python tools/blender/make_s1_world_kit.py [--only <id>[,<id>...]]
"""
import argparse
import math
import os
import random
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_m1_blockouts as mb  # noqa: E402
import render_landmark_concepts as lc  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

GENERATOR = "tools/blender/make_s1_world_kit.py"
REVIEW_STATE = "rough - endless world S1, not visually approved"
ANCHOR_RADIUS = 3.0          # every landmark fits this circle on the swim plane (plan A.2)
BAND = 0.5                   # the swim band checked against footprints, m either side of the plane
SHELL_OUTLINE = (0.85, 1.15)  # the rock contract: the band outline stays this close to the footprint
LANDMARK_BUDGET = 9000
SET_PIECE_BUDGET = 14000
SHELL_BUDGET = 1300
MARKER_BUDGET = 600

# Flat stand-ins for the concept materials (linear RGB).
FLAT = {
    "silica": ((0.62, 0.76, 0.88), 0.25), "silica_frost": ((0.50, 0.64, 0.82), 0.4),
    "core": ((0.80, 0.56, 0.25), 0.4), "cream": ((0.81, 0.72, 0.52), 0.5),
    "lavender": ((0.40, 0.33, 0.68), 0.45), "husk": ((0.60, 0.55, 0.68), 0.5),
    "husk_dark": ((0.22, 0.20, 0.30), 0.6), "amber": ((0.69, 0.38, 0.10), 0.45),
    "bone": ((0.70, 0.65, 0.56), 0.45),
}


def _flat_mats():
    return {k: bc.material(f"M_{k.title().replace('_', '')}", c, r) for k, (c, r) in FLAT.items()}


def _bake_to_one(name):
    """Applies every modifier and joins every mesh into one object called `name`."""
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for obj in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.name = name
    obj.data.name = f"{name}_mesh"
    return obj


def _fit_budget(obj, budget):
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    if tris > budget * 0.95:
        mod = obj.modifiers.new("Budget", "DECIMATE")
        mod.ratio = budget * 0.9 / tris
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)


def _band_radius(obj):
    """Widest horizontal reach of the mesh within the swim band (a section at every 0.1 m)."""
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    obj.data.calc_loop_triangles()
    tris = [tuple(t.vertices) for t in obj.data.loop_triangles]
    heights = [-BAND + 0.1 * i for i in range(int(2 * BAND / 0.1) + 1)]
    return max(mb.band_outline(pts, tris, heights)), pts, tris


def _check(condition, message):
    if not condition:
        raise RuntimeError(message)


# --- Landmarks and set pieces -------------------------------------------------------------------

LANDMARKS = {
    "landmark_great_shell": ("great_shell", "A giant radiolarian dome over a glowing amber heart, with a crown of spines."),
    "landmark_arch": ("arch", "A curved silica rib springing from two ribbed feet, the last bone of a long-dead colony."),
    "landmark_giant_carcass": ("giant_carcass", "The collapsed, ribbed husk of a giant protist, greyed lavender, never carrion red."),
    "landmark_spire": ("spire", "A twisted sponge-spicule tower with whorls of hooks and an amber tip."),
    "landmark_ring": ("ring", "A giant diatom girdle band standing on edge in two cradles."),
    "landmark_fan": ("fan", "A fan colony of cream stalks holding amber bell-shaped cells."),
}
SET_PIECES = {
    "setpiece_giant_bones": ("giant_bones", "Picked-clean remains: hollow vertebral rings and bare ribs, no soft tissue and no food rim."),
    "setpiece_shell_cathedral": ("shell_cathedral", "A ring of tall glass drums with lattice spires round a lit nave."),
}
# Each landmark's three dressings (plan A.2): a tint shift, an attached growth node or none, and a
# uniform scale inside the recorded range. PROPOSED until the S1 build plan pins the record fields.
DRESSINGS = [
    {"id": "plain", "tint": "#FFFFFF", "growth": None, "scale": 1.0},
    {"id": "frosted", "tint": "#C9D4EE", "growth": None, "scale": 0.92},
    {"id": "amber_bloom", "tint": "#F2E2C2", "growth": None, "scale": 1.05},
]
SCALE_RANGE = [0.9, 1.06]


def build_landmark(design, purpose, budget, anchor):
    lc.DESIGNS[design](_flat_mats(), random.Random(design))
    obj = _bake_to_one("Landmark")
    _fit_budget(obj, budget)
    reach, pts, _ = _band_radius(obj)
    if anchor is not None:
        _check(reach * SCALE_RANGE[1] <= anchor + 1e-3, f"{design}: swim band reach {reach:.2f} m at the top scale is outside the {anchor} m anchor")
    return {
        "purpose": f"Endless world S1 rough: {purpose} Swapped for the finished piece under the same id.",
        "category": "landmark" if anchor is not None else "set_piece",
        "pivot": "centre of the anchor on the swim plane (Godot y = 0)",
        "anchor_radius_m": anchor,
        "swim_band_reach_m": round(reach, 3),
        "scale_range": SCALE_RANGE,
        "dressings": DRESSINGS if anchor is not None else [],
        "top_m": round(max(p.z for p in pts), 3),
        "bottom_m": round(min(p.z for p in pts), 3),
    }


# --- Shell kit ----------------------------------------------------------------------------------

# Footprint classes PROPOSED: small 0.6 m and large 1.5 m here; the medium 1.0 m class is the three
# pool shells (rock_a, rock_b, rock_c). Two assets per class so the seed can vary each slot.
SHELLS = {
    "shell_small_lens": {"footprint": 0.6, "wall": 0.2, "dome": 0.3, "lobes": (12, 0.03), "color": "silica",
                         "purpose": "a small radiolarian lens: a low dome with a scalloped rim"},
    "shell_small_pill": {"footprint": 0.6, "wall": 0.25, "dome": 0.12, "lobes": (24, 0.01), "color": "silica_frost",
                         "purpose": "a small pennate pillbox, flat-topped with a crisp rim"},
    "shell_large_tower": {"footprint": 1.5, "wall": 0.9, "dome": 0.25, "lobes": (18, 0.02), "color": "silica",
                          "purpose": "a tall glass drum with a fluted wall and a low dome"},
    "shell_large_bell": {"footprint": 1.5, "wall": 0.35, "dome": 0.7, "lobes": (10, 0.035), "color": "silica_frost",
                         "purpose": "a broad bell-shaped shell, wide at the plane and rounded on top"},
}
SHELL_SCALE_RANGE = [0.92, 1.08]


def build_shell(spec):
    r = spec["footprint"]
    top = 0.15 + spec["wall"] + spec["dome"]
    bottom = -1.6 - 0.6 * r
    shoulder = top - spec["dome"]
    profile = [(0.0, bottom)]
    for i in range(1, 6):
        a = i / 5 * math.pi / 2
        profile.append((r * math.sin(a), -0.6 + (bottom + 0.6) * math.cos(a)))
    for z in (-0.3, 0.0, 0.3):
        if z < shoulder:
            profile.append((r, z))
    for i in range(0, 7):
        a = i / 6 * math.pi / 2
        profile.append((r * math.cos(a) ** 0.8, shoulder + spec["dome"] * math.sin(a)))
    profile.append((0.0, top))
    profile = [(rr, z) for rr, z in profile if rr > 1e-4 or z in (bottom, top)]
    mats = _flat_mats()
    lc.revolve("Rock", profile, mats[spec["color"]], 40, lobes=spec["lobes"])
    obj = _bake_to_one("Rock")
    reach, pts, tris = _band_radius(obj)
    outline = mb.band_outline(pts, tris, mb.ROCK_OUTLINE_HEIGHTS)
    lo, hi = (k * r for k in SHELL_OUTLINE)
    _check(lo <= min(outline) and max(outline) <= hi, f"shell outline {min(outline):.2f}-{max(outline):.2f} for footprint {r}")
    return {
        "purpose": f"Endless world S1 rough band-0 shell: {spec['purpose']}. An obstacle the cell slides around.",
        "category": "shell",
        "pivot": "centre of the footprint on the swim plane (Godot y = 0)",
        "footprint_radius_m": r,
        "footprint_class": "small" if r < 0.8 else "large",
        "scale_range": SHELL_SCALE_RANGE,
        "swim_band_min_radius_m": round(min(outline), 3),
        "swim_band_radius_m": round(max(outline), 3),
        "top_m": round(max(p.z for p in pts), 3),
        "bottom_m": round(min(p.z for p in pts), 3),
    }


# --- Wayfinding markers -------------------------------------------------------------------------


def build_light_column():
    """Where you come back: a tall, open, slightly flared tube of light. UV v runs 0 at the bottom
    to 1 at the top, so the engine's additive shader can fade both ends."""
    mat = bc.material("M_LightColumn", (0.89, 0.80, 0.58), 0.5, emission=(0.89, 0.80, 0.58), emission_strength=2.0)
    verts, faces, rings, seg = [], [], [], 32
    heights = [-6.0 + i * 3.0 for i in range(7)]
    for z in heights:
        rr = 0.9 + 0.25 * (z + 6.0) / 18.0
        ring = []
        for j in range(seg):
            a = math.tau * j / seg
            ring.append(len(verts))
            verts.append((rr * math.cos(a), rr * math.sin(a), z))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(seg):
            k = (j + 1) % seg
            faces.append((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
    bc.mesh_object("LightColumn", verts, faces, [mat], fix_normals=False,
                   uv=lambda co: ((math.atan2(co.y, co.x) / math.tau) % 1.0, (co.z + 6.0) / 18.0))
    return {
        "purpose": "Endless world S1 rough: the cream light column at the current checkpoint, 'where you come back'. Drawn additive and unshaded by the engine; UV v fades the ends.",
        "category": "marker",
        "pivot": "the checkpoint on the swim plane (Godot y = 0)",
    }


def build_origin_arrow():
    """Where you began: a flat cream chevron, pointing +Y in Blender (Godot -Z), 1 m long."""
    mat = bc.material("M_OriginArrow", (0.89, 0.80, 0.58), 0.5, emission=(0.89, 0.80, 0.58), emission_strength=1.0)
    outline = [(0.0, 0.5), (0.42, -0.08), (0.2, -0.08), (0.2, -0.5), (-0.2, -0.5), (-0.2, -0.08), (-0.42, -0.08)]
    t = 0.04
    verts = [(x, y, t) for x, y in outline] + [(x, y, -t) for x, y in outline]
    n = len(outline)
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    bc.mesh_object("OriginArrow", verts, faces, [mat], smooth=False)
    return {
        "purpose": "Endless world S1 rough: the cream arrow toward the origin, 'where you began'. A different shape from the light column, and neither food nor threat colour.",
        "category": "marker",
        "pivot": "centre of the arrow; it points Godot -Z",
    }


ASSETS = {
    **{i: ((lambda d=d, p=p: build_landmark(d, p, LANDMARK_BUDGET, ANCHOR_RADIUS)), LANDMARK_BUDGET) for i, (d, p) in LANDMARKS.items()},
    **{i: ((lambda d=d, p=p: build_landmark(d, p, SET_PIECE_BUDGET, None)), SET_PIECE_BUDGET) for i, (d, p) in SET_PIECES.items()},
    **{i: ((lambda s=s: build_shell(s)), SHELL_BUDGET) for i, s in SHELLS.items()},
    "marker_light_column": (build_light_column, MARKER_BUDGET),
    "marker_origin_arrow": (build_origin_arrow, MARKER_BUDGET),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the endless world's S1 rough art.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    args = parser.parse_args(argv)
    ids = [i for i in args.only.split(",") if i] or list(ASSETS)
    unknown = [i for i in ids if i not in ASSETS]
    if unknown:
        parser.error(f"unknown asset id(s): {', '.join(unknown)}; known: {', '.join(ASSETS)}")
    for asset_id in ids:
        builder, budget = ASSETS[asset_id]
        bc.reset_scene()
        fields = builder()
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
