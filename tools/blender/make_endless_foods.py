"""The endless world's new plant foods (docs/endless-cell-plan.md, table "What each size brings"), in
finished art: size 2's algae ball, size 3's glass flake and size 4's bead cluster.

Each is a food item like M1's plankton (tools/blender/make_m1_production.py build_plankton): one mesh
named after the item, its pivot at the item's centre, its horizontal radius within 20% of the item
radius, built at the plankton's item radius (0.18 m) so the world scales it like plankton, and
drawn many times with one MultiMesh. Every one carries the food glow (#CFE86A) so it reads as food at
the gameplay camera, with a baked albedo, ORM, normal and emission set.
- algae_ball: a ball colony of tiny green cells on a clear jelly, three daughter colonies glowing inside.
- glass_flake: a broken silica flake, pale and glassy, with a glowing green chloroplast band in it.
- bead_cluster: a short coiled chain of glowing green-gold beads, like a filament colony.

Run: python tools/blender/make_endless_foods.py [--only <id>[,<id>...]]
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_m1_blockouts as mb  # noqa: E402
import make_m1_production as mp  # noqa: E402
import surfacing as sf  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

GENERATOR = "tools/blender/make_endless_foods.py"
REVIEW_STATE = mp.REVIEW_STATE
PROVENANCE = "Authored procedurally in Blender by tools/blender/make_endless_foods.py; no external or generated meshes. Textures baked in Blender from procedural shaders."
ITEM_RADIUS = mb.PLANKTON_ITEM_RADIUS


def _fit(pts, radius):
    widest = mb._horizontal_radius(pts)
    for p in pts:
        p.x *= radius / widest
        p.y *= radius / widest
        p.z *= radius / widest


def _sphere(center, radius, subdivisions=2, squash=1.0, wobble=0.0, seed=Vector()):
    unit, faces = bc.icosphere(subdivisions)
    verts = []
    for co in unit:
        n = Vector(co).normalized()
        k = 1.0 + wobble * noise.noise(n * 2.0 + seed)
        verts.append(center + Vector((n.x, n.y, n.z * squash)) * radius * k)
    return verts, faces


def _finish(name, verts, faces, shader, texture=256):
    obj = bc.mesh_object(name, verts, faces, [shader])
    reduced = mp._reduce_and_bake([obj], mp.FOOD_TOLERANCE, name, texture, normal=True, emission=True)
    radius = mb._horizontal_radius([obj.matrix_world @ v.co for v in obj.data.vertices])
    mp._check(abs(radius - ITEM_RADIUS) <= 0.2 * ITEM_RADIUS, f"{name}: mesh radius {radius:.3f} fits the item radius")
    return radius, reduced


DAUGHTERS = (Vector((0.45, 0.3, 0.55)), Vector((-0.5, 0.35, -0.3)), Vector((0.1, -0.6, 0.2)))


def build_algae_ball():
    sh = sf.Shader("M_AlgaeBallProc")
    r = sh.vmath("LENGTH", sh.pos)
    cells = sh.remap(sh.voronoi(28.0, 0.5), 0.3, 0.12)                       # 1 on a cell
    jelly = sh.ramp(sh.noise(12.0, 3.0), [(0.3, "#4E8E52"), (0.7, "#6DAA5E")])
    base = sh.mix(sh.math("MULTIPLY", cells, 0.8), jelly, "#B8DC6A")
    # Three daughter colonies seen through the jelly: glowing discs where they press out.
    unit = sh.vmath("NORMALIZE", sh.pos)
    daughters = 0.0
    for d in DAUGHTERS:
        daughters = sh.math("MAXIMUM", daughters, sh.remap(sh.vmath("DOT_PRODUCT", unit, tuple(d.normalized())), 0.86, 0.95))
    base = sh.mix(daughters, base, "food_glow")
    sh.bump(sh.math("ADD", cells, daughters), 0.35, 0.002)
    glow = sh.math("ADD", sh.math("MULTIPLY", cells, 0.35), daughters, clamp=True)
    proc = sh.out(base, 0.35, sh.mix(glow, (0, 0, 0, 1), "food_glow"), 0.7)
    verts, faces = _sphere(Vector(), 1.0, 3, wobble=0.04, seed=Vector((3.1, -2.2, 7.7)))
    # Daughter colonies show as soft swellings on the surface, where they press out from inside.
    for d in DAUGHTERS:
        dn = d.normalized()
        for v in verts:
            v += v.normalized() * 0.06 * max(0.0, v.normalized().dot(dn) - 0.8) / 0.2
    _fit(verts, mb.PLANKTON_MESH_RADIUS)
    radius, reduced = _finish("AlgaeBall", verts, faces, proc)
    return _fields("algae_ball", "S2 algae ball food item (size 2's plant food): a ball colony of tiny glowing green cells on clear jelly, with daughter colonies pressing out from inside.", radius, reduced)


def build_glass_flake():
    sh = sf.Shader("M_GlassFlakeProc")
    pores = sh.remap(sh.voronoi(70.0, 0.3), 0.16, 0.08)
    glass = sh.ramp(sh.noise(9.0, 3.0), [(0.3, "#C9DCE4"), (0.7, "#E4EEF0")])
    band = sh.remap(sh.math("ABSOLUTE", sh.math("ADD", sh.axis("X"), sh.math("MULTIPLY", sh.axis("Y"), 0.4))), 0.06, 0.02)
    base = sh.mix(sh.math("MULTIPLY", pores, 0.4), glass, "#8AA6B8")
    base = sh.mix(band, base, "food_glow")
    sh.bump(sh.math("SUBTRACT", 0.0, pores), 0.3, 0.002)
    proc = sh.out(base, sh.remap(band, 0.0, 1.0, 0.15, 0.35), sh.mix(band, (0, 0, 0, 1), "food_glow"), 0.8)
    # A broken pentagonal flake: an irregular outline, thin, with a slight curve like a shell piece.
    outline = [(1.0, 0.1), (0.55, 0.85), (-0.35, 0.9), (-0.95, 0.15), (-0.6, -0.8), (0.3, -0.95), (0.8, -0.5)]
    pts, faces = [], []
    thickness = 0.12
    n = len(outline)
    for z in (thickness, -thickness):
        for x, y in outline:
            pts.append(Vector((x, y, z - 0.18 * (x * x + y * y) * 0.5)))
    top = list(range(n))
    faces.append(tuple(top))
    faces.append(tuple(reversed(range(n, 2 * n))))
    faces += [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
    _fit(pts, mb.PLANKTON_MESH_RADIUS)
    obj_pts = pts
    radius, reduced = _finish("GlassFlake", obj_pts, faces, proc)
    return _fields("glass_flake", "S3 glass flake food item (size 3's plant food): a broken, thin silica flake, pale and glassy with fine pores, a glowing green chloroplast band running through it.", radius, reduced)


def build_bead_cluster():
    sh = sf.Shader("M_BeadClusterProc")
    r = sh.vmath("LENGTH", sh.vmath("SUBTRACT", sh.pos, (0.0, 0.0, 0.0)))
    speck = sh.noise(80.0, 2.0)
    base = sh.ramp(speck, [(0.3, "#9CC24E"), (0.6, "food_glow"), (0.9, "#E8E07A")])
    sh.bump(speck, 0.2, 0.001)
    proc = sh.out(base, 0.3, sh.mix(sh.remap(speck, 0.3, 0.7), (0, 0, 0, 1), "food_glow"), 0.9)
    verts, faces = [], []
    beads = 7
    for i in range(beads):
        t = i / (beads - 1)
        a = t * 1.6 * math.pi
        c = Vector((0.65 * math.cos(a) * (1.0 - 0.35 * t), 0.65 * math.sin(a) * (1.0 - 0.35 * t), 0.15 * math.sin(3.0 * a)))
        size = 0.26 if i % 3 else 0.34    # every third bead is a larger resting cell
        bv, bf = _sphere(c, size, 2, squash=0.9, wobble=0.05, seed=Vector((i * 1.7, 2.0, -i)))
        bc.append(verts, faces, bv, bf)
    _fit(verts, mb.PLANKTON_MESH_RADIUS)
    radius, reduced = _finish("BeadCluster", verts, faces, proc)
    return _fields("bead_cluster", "S3 bead cluster food item (size 4's plant food): a short coiled chain of glowing green-gold beads, every third a larger resting cell, like a filament colony.", radius, reduced)


def _fields(asset_id, purpose, radius, reduced):
    return {
        "purpose": purpose,
        "category": "food",
        "food_kind": "plant",
        "revision": 1,
        "pivot": "centre of the item",
        "item_radius_m": ITEM_RADIUS,
        "mesh_radius_m": round(radius, 3),
        "scale_note": "Built at the plankton's item radius; the world draws it at its size's item radius.",
        **reduced,
    }


ASSETS = {
    "algae_ball": (build_algae_ball, 400),
    "glass_flake": (build_glass_flake, 400),
    "bead_cluster": (build_bead_cluster, 600),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the endless world's new foods.")
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
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR, provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
