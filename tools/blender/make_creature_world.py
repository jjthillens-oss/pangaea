"""The creature stage's world dressing (PROPOSED): the field ground, the nest ring, the fruit bush and the meat
chunk that replace the placeholders in game/scenes/creature/creature_world.gd (creature-stage-plan.md section 5).

Contract from the Creature stage thread: 1 m = 1 unit, the pivot on the ground (Blender z = 0, Godot y = 0),
Blender +Y forward (Godot -Z). The field is flat and walkable (relief under 0.12 m inside the walls at +-80 m,
a berm past them); the nest ring sits at the origin, outer radius about 6 m, with a clear flat inside; the fruit
bush is about 0.5 m across and the meat chunk 0.3 m; fruit and meat draw as MultiMesh instances with a colour
per instance, so their materials take an instance tint (vertex_color_use_as_albedo in the external .tres).

- creature_field_ground: a 172 x 172 m grid with gentle relief and a berm. Drawn with the external
  M_CreatureField.tres (assets/export/shaders/creature_field.gdshader): two seamless 2 m tiles (blue-green turf
  and bare earth) blended by a 37 m patch mask and a bare clearing round the nest.
- creature_nest_ring: a mound of packed earth and straw with twigs across it, revolved round the origin.
- creature_fruit_bush: two root meshes, Bush (the leafy clump) and Fruit (ten amber fruit on it), so the stage can
  draw the fruit only while the bush is ripe.
- creature_meat_chunk: a torn haunch with a bone end, lying on the ground.

Colours keep 25 degrees of LAB hue from the food green (114) and the threat pink (11), as every asset does; the turf
is blue-green rather than grass green for that reason, and it keeps the deep-blue world's family.

Run: python tools/blender/make_creature_world.py [--only <id>[,<id>...]]   (bpy 5.2.2 venv)
Then godot --headless --import, python tools/blender/make_creature_world.py --import, and --import again.
"""
import argparse
import math
import os
import random
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import make_creature_parts as cp  # noqa: E402
import make_m1_production as mp  # noqa: E402
import make_membranes as mm  # noqa: E402
import numpy as np  # noqa: E402
import surfacing as sf  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

GENERATOR = "tools/blender/make_creature_world.py"
REVIEW_STATE = mp.REVIEW_STATE
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_creature_world.py; no external or generated meshes. "
              "Textures baked in Blender from procedural shaders; the field tiles are periodic sine sums and wrapped "
              "Voronoi in numpy, so they repeat without seams.")
FIELD_HALF = 86.0        # the mesh reaches past the walls at 80 m, so the berm hides the edge
FIELD_STEP = 2.15        # grid spacing: 81 x 81 vertices
WALL_M = 80.0
RELIEF_M = 0.12
BERM_M = 2.5
TILE_DIR = os.path.join(bc.ROOT, "assets", "export", "creature_field")
TILE_M = 2.0
PATCH_M = 37.0
NEST_R = 6.0
FRUIT_COUNT = 9
NEST_TOL = 0.012         # the nest's decimation tolerance: 1.2 cm on a 13 m ring
GROUND_TOL = 0.004       # collapse decimation may move a flattened underside this far (as cp._check_pivot allows)


def _lin(hex_color):
    return mp._lin(hex_color)


# --- Field tiles (numpy, seamless) --------------------------------------------------------------------------

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
    return {"name": name, "path": f"assets/export/creature_field/{name}.png", "size": [size, size], "colorspace": colorspace}


def _srgb(hex_color):
    h = hex_color.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def _lerp_rgb(a, b, t):
    return a[None, None, :] + (b - a)[None, None, :] * t[..., None]


def turf_tile(rng):
    """Blue-green turf: soft tuft crowns of mixed sizes (wrapped Voronoi domes, each its own shade) over a
    mottled ground, with fine blade streaks that gather on the crowns. Lighter on the crowns, darker between."""
    cells = 110
    d1, _, idx = mm._voronoi(rng, cells)
    shade = rng.uniform(0.0, 1.0, cells)[idx]                  # per-tuft, seamless because the cells wrap
    radius = (0.028 + 0.022 * rng.uniform(0.0, 1.0, cells))[idx]   # inside its cell, so no cell edge shows
    crown = np.clip(1.0 - (d1 / radius) ** 2, 0.0, 1.0)
    crown = crown * crown * (3.0 - 2.0 * crown)
    ground = mm._norm(mm._periodic_noise(rng, [3, 6, 12], [1.0, 0.6, 0.35]))
    blades = mm._norm(mm._periodic_noise(rng, [36, 64, 90], [0.5, 0.35, 0.25]))
    h = 0.5 * crown + 0.3 * ground + 0.2 * blades * (0.5 + 0.5 * crown)
    light = np.clip(0.4 * crown * (0.7 + 0.3 * shade) + 0.33 * ground + 0.27 * blades, 0.0, 1.0)
    rgb = _lerp_rgb(_srgb("#2A5A4F"), _srgb("#5A9B80"), light)
    rgb = rgb * (1.0 + 0.18 * (shade - 0.5) * crown)[..., None]
    return h, rgb, 1.1


def earth_tile(rng):
    """Bare earth: rounded pebbles of mixed sizes (wrapped Voronoi domes) half sunk in dust and grit."""
    cells = 160
    d1, _, idx = mm._voronoi(rng, cells)
    sizes = rng.uniform(0.3, 1.0, cells)[idx]
    dome = np.sqrt(np.clip(1.0 - (d1 / (0.034 * sizes)) ** 2, 0.0, 1.0))
    grit = mm._norm(mm._periodic_noise(rng, [48, 80], [0.6, 0.4]))
    dust = mm._norm(mm._periodic_noise(rng, [3, 6, 12, 24], [1.0, 0.55, 0.3, 0.15]))
    h = 0.5 * dome * sizes + 0.3 * dust + 0.2 * grit
    light = np.clip(0.55 * dust + 0.1 * dome + 0.35 * grit, 0.0, 1.0)
    rgb = _lerp_rgb(_srgb("#5E4630"), _srgb("#A58666"), light)
    stone = _lerp_rgb(_srgb("#5F554B"), _srgb("#8F8276"), light)
    rgb = rgb + (stone - rgb) * (0.5 * dome)[..., None]        # the pebbles read greyer than the dust, not lighter
    return h, rgb, 1.0


def patch_tile(rng):
    """A low-frequency mask (one tile = PATCH_M across) that says where the turf gives way to earth."""
    m = mm._norm(mm._periodic_noise(rng, [1, 2, 4], [1.0, 0.5, 0.2]))
    return np.repeat(m[..., None], 3, axis=-1)


def build_field_tiles():
    """Writes the three tiles and returns their record entries."""
    out = []
    for name, fn, seed in (("T_CreatureField_Turf", turf_tile, 5100), ("T_CreatureField_Earth", earth_tile, 5101)):
        h, rgb, strength = fn(np.random.default_rng(seed))
        h = mm._norm(h)
        out.append(_save_tile(f"{name}_Albedo", rgb, "sRGB"))
        out.append(_save_tile(f"{name}_Normal", mm._normal_map(h, strength), "Non-Color"))
    out.append(_save_tile("T_CreatureField_Patch", patch_tile(np.random.default_rng(5102)), "Non-Color"))
    return out


# --- The field ---------------------------------------------------------------------------------------------

def _relief(x, y):
    r = math.hypot(x, y)
    flat = bc.smoothstep(min(1.0, max(0.0, (r - NEST_R - 1.0) / 8.0)))      # the nest's clearing stays flat
    n = noise.noise(Vector((x / 11.0 + 3.1, y / 11.0 + 7.4, 0.0))) * 0.7 + noise.noise(Vector((x / 4.0, y / 4.0, 2.5))) * 0.3
    z = RELIEF_M * n * flat
    d = max(abs(x), abs(y))
    berm = bc.smoothstep(min(1.0, max(0.0, (d - WALL_M + 1.0) / 5.0)))
    z += BERM_M * berm * (0.85 + 0.15 * noise.noise(Vector((x / 6.0, y / 6.0, 9.0))))
    return z


def build_field_ground():
    """A square of ground 172 m across: gentle relief inside the walls at +-80 m and a berm past them, so the
    edge reads as a bank rather than a cliff. UV = metres / 2, one turf tile per 2 m. Drawn with the external
    M_CreatureField.tres (mapped in its .glb.import), which blends the turf and earth tiles in world space."""
    n = int(round(2 * FIELD_HALF / FIELD_STEP)) + 1
    verts, faces = [], []
    for j in range(n):
        for i in range(n):
            x = -FIELD_HALF + 2 * FIELD_HALF * i / (n - 1)
            y = -FIELD_HALF + 2 * FIELD_HALF * j / (n - 1)
            verts.append((x, y, _relief(x, y)))
    for j in range(n - 1):
        for i in range(n - 1):
            a = j * n + i
            faces.append((a, a + 1, a + n + 1, a + n))
    mat = bc.material("M_CreatureField", _lin("#3F7E68"), 0.92)
    bc.mesh_object("CreatureField", verts, faces, [mat], fix_normals=False, uv=lambda co: (co.x / TILE_M, co.y / TILE_M))
    inside = [z for (x, y, z) in verts if max(abs(x), abs(y)) <= WALL_M - 1.0]
    mp._check(max(abs(z) for z in inside) <= RELIEF_M + 1e-6, "field: relief inside the walls stays under %.2f m" % RELIEF_M)
    mp._check(max(z for (x, y, z) in verts) >= BERM_M * 0.8, "field: the berm rises past the walls")
    return {"purpose": "Creature stage field (PROPOSED): the walkable ground, flat to within 0.12 m inside the walls at +-80 m, with a berm past them; blue-green turf and bare earth tiles blended in world space by M_CreatureField.tres.",
            "category": "environment", "kind": "ground", "pivot": "the field's centre on the ground (Godot y = 0); the nest sits at the origin",
            "engine_material": "res://assets/export/M_CreatureField.tres",
            "walkable": {"wall_m": WALL_M, "relief_max_m": RELIEF_M, "berm_m": BERM_M, "clearing_r_m": NEST_R + 1.5},
            "textures": build_field_tiles(), "revision": 1}


def _bake_mixed(objs_tol, texture, tints, size=512):
    """cp._bake with a tolerance per object: (obj, tolerance_m) pairs, so small pieces keep their shape while a
    big soft one reduces hard."""
    before = after = 0
    highs = {}
    for obj, tol in objs_tol:
        b, a, high = sf.reduce(obj, tol)
        before, after = before + b, after + a
        if a == b:
            sf.drop_highs([high])
            high = None
        highs[obj.name] = high
    objs = [o for o, _ in objs_tol]
    sf.unwrap(objs)
    textures = sf.bake_set(objs, texture, size, highs=highs, tints=tints)
    sf.drop_highs(highs.values())
    return {"textures": textures,
            "reduction": {"method": "Blender collapse decimation within a surface tolerance per piece; full-detail shading baked to the normal map",
                          "tolerance_m": {o.name: t for o, t in objs_tol}, "triangles_before": before, "triangles_after": after}}


# --- The nest ring -----------------------------------------------------------------------------------------

def _nest_rise(a):
    """How high the mound stands at angle `a` round the ring, as a share of the profile's height: it is heaped
    unevenly, higher on some sides."""
    return 0.82 + 0.3 * noise.noise(Vector((math.cos(a) * 1.3 + 5.0, math.sin(a) * 1.3 + 5.0, 0.7)))


def _nest_crown(r):
    """The mound's height at radius r before the rise, a parabola over the crown at 5.8 m."""
    return max(0.0, 0.5 - 1.6 * (r - 5.8) ** 2) if 5.2 < r < 6.55 else 0.0


def build_nest_ring():
    """A mound of packed earth and straw round the nest, outer radius about 6.5 m, inner 5.2 m, up to half a
    metre high and heaped unevenly, with twigs and a few stones lying across it. The inside stays clear and
    flat; the creature stands there."""
    profile = [(0.0, 5.2), (0.12, 5.35), (0.28, 5.5), (0.42, 5.65), (0.5, 5.8), (0.46, 5.95), (0.34, 6.1), (0.18, 6.25), (0.06, 6.4), (0.0, 6.55)]
    rv, rf, _ = bc.revolve(profile, 112)
    verts = []
    for x, y, z in cp._up(rv):
        r = math.hypot(x, y)
        a = math.atan2(y, x)
        z *= _nest_rise(a)
        k = min(1.0, (r - 5.2) / 0.3, (6.55 - r) / 0.3) if r > 5.2 else 0.0          # the feet stay on the ground
        bump = noise.noise(Vector((x / 0.9, y / 0.9, 1.5))) * 0.07 * k + noise.noise(Vector((a * 4.0, z * 3.0, 4.0))) * 0.03 * k
        verts.append((x + x / r * bump * 0.5, y + y / r * bump * 0.5, max(0.0, z + bump)))
    fcs = list(rf)
    face_mats = [0] * len(fcs)
    rng = random.Random(7)
    for _ in range(30):
        a = rng.uniform(0.0, math.tau)
        r = rng.uniform(5.45, 6.25)
        c = Vector((r * math.cos(a), r * math.sin(a), 0.0))
        d = Vector((-math.sin(a), math.cos(a), 0.0)).normalized()
        d = (d * math.cos(rng.uniform(-0.6, 0.6)) + Vector((math.cos(a), math.sin(a), 0.0)) * math.sin(rng.uniform(-0.6, 0.6))).normalized()
        length = rng.uniform(0.8, 1.7)
        path = []
        for t in (-0.5, -0.25, 0.0, 0.25, 0.5):
            p = c + d * (length * t)
            h = _nest_crown(p.length) * _nest_rise(math.atan2(p.y, p.x))          # lies on the mound's crown
            path.append(Vector((p.x, p.y, max(0.02, h) + 0.02 + 0.02 * math.sin(t * 5.0))))
        v, f, _ = cp._tube(path, lambda i, ang, s=rng.uniform(0.02, 0.04): s * (1.0 + 0.15 * math.cos(3 * ang)) if i < 4 else s * 0.7, 6)
        bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
    unit, ufaces = bc.icosphere(2)
    for _ in range(14):
        a = rng.uniform(0.0, math.tau)
        r = rng.uniform(5.5, 6.2)
        c = Vector((r * math.cos(a), r * math.sin(a), 0.0))
        size = rng.uniform(0.1, 0.22)
        h = _nest_crown(r) * _nest_rise(a)
        stretch = Vector((rng.uniform(0.8, 1.3), rng.uniform(0.8, 1.3), 0.6))
        bc.append(verts, fcs, [tuple(c + Vector((0.0, 0.0, h + size * 0.25)) + Vector(co).normalized() * size * stretch) for co in unit], ufaces)
        face_mats.extend([2] * (len(fcs) - len(face_mats)))
    earth = sf.Shader("M_NestEarthProc")
    grit = earth.remap(earth.voronoi(9.0, 0.8), 0.3, 0.05)
    straw = earth.noise(3.0, 3.0, vector=mp._stretched(earth, (0.15, 1.0, 1.0)))
    earth.bump(earth.math("ADD", earth.math("MULTIPLY", straw, 0.6), earth.math("MULTIPLY", grit, 0.5)), 0.35, 0.02)
    twig = sf.Shader("M_NestTwigProc")
    bark = twig.noise(12.0, 3.0, vector=mp._stretched(twig, (0.3, 0.3, 2.0)))
    twig.bump(bark, 0.3, 0.004)
    stone = sf.Shader("M_NestStoneProc")
    pits = stone.remap(stone.voronoi(30.0, 0.9), 0.05, 0.25)
    stone.bump(stone.math("ADD", pits, stone.math("MULTIPLY", stone.noise(60.0, 2.0), 0.4)), 0.3, 0.004)
    mats = [earth.out(cp._grey(earth, earth.math("ADD", earth.remap(straw, 0.3, 0.7), earth.math("MULTIPLY", grit, 0.25)), 0.72), 0.85),
            twig.out(cp._grey(twig, twig.remap(bark, 0.3, 0.7), 0.7), 0.7),
            stone.out(cp._grey(stone, stone.remap(pits, 0.2, 0.9), 0.75), 0.6)]
    obj = bc.mesh_object("CreatureNestRing", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name, mats[2].name = "M_NestEarth", "M_NestTwig", "M_NestStone"
    baked = cp._bake([obj], "CreatureNestRing", {"M_NestEarth": sf.tint(_lin("#8A6C46")), "M_NestTwig": sf.tint(_lin("#5E4730")),
                                                 "M_NestStone": sf.tint(_lin("#8A8178"))}, size=1024, tolerance=NEST_TOL)
    pts = bc.world_vertices()
    mp._check(min(p.z for p in pts) >= -NEST_TOL, "nest: sits on the ground (within its decimation tolerance)")
    mp._check(min(math.hypot(p.x, p.y) for p in pts) >= 5.1, "nest: the inside stays clear")
    return {"purpose": "Creature stage nest (PROPOSED): a ring mound of packed earth and straw, heaped unevenly, with twigs and stones across it, round a clear flat floor where the creature stands.",
            "category": "environment", "kind": "nest", "pivot": "the nest's centre on the ground (Godot y = 0)",
            "ring_m": {"inner": 5.2, "crown": 5.8, "outer": 6.55, "height": 0.5}, "revision": 1, **baked}


# --- The fruit bush ----------------------------------------------------------------------------------------

def build_fruit_bush():
    """A leafy clump half a metre across (Bush) with amber fruit on its upper surface (Fruit), as two root
    meshes so the stage draws the fruit only while the bush is ripe. Both materials take an instance tint."""
    unit, ufaces = bc.icosphere(5)
    golden = math.pi * (3.0 - math.sqrt(5.0))
    rng = random.Random(11)
    clumps = []
    for k in range(16):
        z = 1.0 - 2.0 * (k + 0.5) / 16
        rr = math.sqrt(1.0 - z * z)
        clumps.append((Vector((rr * math.cos(golden * k), rr * math.sin(golden * k), z)), rng.uniform(0.09, 0.16), rng.uniform(0.6, 1.0)))
    centre = Vector((0.0, 0.0, 0.38))
    bush = []
    for co in unit:
        n = Vector(co).normalized()
        bump = sum(w * math.exp(-((1.0 - n.dot(d)) / width) ** 2) for d, width, w in clumps)
        leaf = noise.noise(n * 9.0) * 0.025 + noise.noise(n * 20.0 + Vector((3.0, 0.0, 0.0))) * 0.005
        r = 0.44 * (0.74 + 0.26 * min(1.0, bump)) + leaf
        p = centre + Vector((n.x * r, n.y * r, n.z * r * 0.85))
        bush.append((p.x, p.y, max(p.z, 0.02)))
    fruit_v, fruit_f = [], []
    unit2, ufaces2 = bc.icosphere(2)          # 80 triangles a fruit before its own, tighter reduction
    spots = []
    for k in range(FRUIT_COUNT):
        z = 0.25 + 0.7 * (k + 0.5) / FRUIT_COUNT
        rr = math.sqrt(1.0 - z * z)
        d = Vector((rr * math.cos(golden * k * 2.0 + 1.0), rr * math.sin(golden * k * 2.0 + 1.0), z))
        spots.append(centre + Vector((d.x * 0.4, d.y * 0.4, d.z * 0.4 * 0.85)))
    for sp in spots:
        bc.append(fruit_v, fruit_f, [tuple(sp + Vector(co).normalized() * 0.062 * Vector((1.0, 1.0, 1.08))) for co in unit2], ufaces2)
    leaf_sh = sf.Shader("M_BushLeafProc")
    leaves = leaf_sh.remap(leaf_sh.voronoi(16.0, 0.9, feature="DISTANCE_TO_EDGE"), 0.0, 0.03)
    veins = leaf_sh.noise(40.0, 2.0)
    leaf_sh.bump(leaf_sh.math("ADD", leaf_sh.math("MULTIPLY", leaves, 0.7), leaf_sh.math("MULTIPLY", veins, 0.3)), 0.6, 0.008)
    leaf_base = cp._grey(leaf_sh, leaf_sh.math("SUBTRACT", leaf_sh.remap(veins, 0.2, 0.8), leaf_sh.math("MULTIPLY", leaf_sh.math("SUBTRACT", 1.0, leaves), 0.45), clamp=True), 0.5)
    fruit_sh = sf.Shader("M_BushFruitProc")
    skin = fruit_sh.noise(90.0, 2.0)
    fruit_sh.bump(skin, 0.12, 0.001)
    fruit_base = cp._grey(fruit_sh, fruit_sh.remap(skin, 0.3, 0.7), 0.85)
    leaf_mat = leaf_sh.out(leaf_base, 0.75)
    bush_obj = bc.mesh_object("Bush", bush, ufaces, [leaf_mat])
    leaf_mat.name = "M_BushLeaf"
    fruit_mat = fruit_sh.out(fruit_base, 0.35)
    fruit_obj = bc.mesh_object("Fruit", fruit_v, fruit_f, [fruit_mat])
    fruit_mat.name = "M_BushFruit"
    baked = _bake_mixed([(bush_obj, 0.025), (fruit_obj, 0.006)], "CreatureFruitBush",
                        {"M_BushLeaf": sf.tint(_lin("#3C8A6C")), "M_BushFruit": sf.tint(_lin("#E8A040"))})
    pts = bc.world_vertices()
    mp._check(min(p.z for p in pts) >= -GROUND_TOL, "bush: sits on the ground")
    mp._check(max(math.hypot(p.x, p.y) for p in pts) <= 0.6, "bush: about 0.5 m across")
    return {"purpose": "Creature stage food (PROPOSED): a lumpy blue-green leaf clump with amber fruit; the Fruit mesh is drawn only while ripe. Both materials take a MultiMesh instance colour.",
            "category": "environment", "kind": "food", "pivot": "under the bush on the ground (Godot y = 0)",
            "instance_tint": "M_BushLeaf.tres and M_BushFruit.tres (mapped in the .glb.import) set vertex_color_use_as_albedo, so a MultiMesh instance colour tints them; white draws them as baked.",
            "states": {"ripe": "draw Bush and Fruit", "bare": "draw Bush only"}, "fruit_count": FRUIT_COUNT, "revision": 1, **baked}


# --- The meat chunk ----------------------------------------------------------------------------------------

def build_meat_chunk():
    """A torn haunch 0.5 m long lying on the ground, the flesh ragged at one end and a bone standing out of the
    other. The material takes an instance tint."""
    unit, ufaces = bc.icosphere(4)
    centre = Vector((0.0, 0.0, 0.13))
    verts = []
    for co in unit:
        n = Vector(co).normalized()
        torn = max(0.0, -n.y) ** 2
        rag = noise.noise(n * 5.0 + Vector((0.0, 3.0, 0.0))) * 0.12 * torn + noise.noise(n * 14.0) * 0.05 * torn + noise.noise(n * 9.0) * 0.012
        p = centre + Vector((n.x * 0.16, n.y * 0.25, n.z * 0.14)) * (1.0 + rag)
        verts.append((p.x, p.y, max(p.z, 0.0)))
    fcs = list(ufaces)
    face_mats = [0] * len(fcs)
    path = [Vector((0.0, 0.05 + 0.21 * t, 0.13 + 0.03 * t)) for t in (0.0, 0.35, 0.7, 1.0)]
    v, f, _ = cp._tube(path, lambda i, a: 0.03 * (1.0 + 0.08 * math.cos(2 * a)) if i < 3 else 0.028, 12)
    bc.append(verts, fcs, v, f)
    face_mats.extend([1] * (len(fcs) - len(face_mats)))
    unit2, ufaces2 = bc.icosphere(3)
    knob = path[-1] + Vector((0.0, 0.02, 0.0))
    bc.append(verts, fcs, [tuple(knob + Vector(co).normalized() * 0.05 * Vector((1.15, 0.9, 1.0))) for co in unit2], ufaces2)
    face_mats.extend([1] * (len(fcs) - len(face_mats)))
    flesh = sf.Shader("M_MeatFleshProc")
    fibres = flesh.noise(40.0, 3.0, vector=mp._stretched(flesh, (1.0, 0.2, 1.0)))
    marbling = flesh.remap(flesh.voronoi(18.0, 0.8, feature="DISTANCE_TO_EDGE"), 0.0, 0.03)
    flesh.bump(flesh.math("ADD", flesh.math("MULTIPLY", fibres, 0.6), flesh.math("MULTIPLY", marbling, 0.4)), 0.35, 0.003)
    fat = flesh.math("SUBTRACT", 1.0, marbling)                                   # pale fat along the cell seams
    cut = flesh.remap(flesh.axis("Y"), -0.1, -0.22)                               # the torn end shows paler flesh
    flesh_base = cp._grey(flesh, flesh.math("ADD", flesh.math("ADD", flesh.remap(fibres, 0.2, 0.7), flesh.math("MULTIPLY", fat, 0.5)),
                                            flesh.math("MULTIPLY", cut, 0.3), clamp=True), 0.45)
    bone = sf.Shader("M_MeatBoneProc")
    grain = bone.noise(30.0, 2.0, vector=mp._stretched(bone, (1.0, 0.3, 1.0)))
    bone.bump(grain, 0.2, 0.001)
    mats = [flesh.out(flesh_base, 0.55), bone.out(cp._grey(bone, bone.remap(grain, 0.3, 0.7), 0.8), 0.4)]
    obj = bc.mesh_object("MeatChunk", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name = "M_MeatFlesh", "M_MeatBone"
    baked = cp._bake([obj], "CreatureMeatChunk", {"M_MeatFlesh": sf.tint(_lin("#8E4C34")), "M_MeatBone": sf.tint(_lin("#E6DCC6"))}, tolerance=0.003)
    pts = bc.world_vertices()
    mp._check(min(p.z for p in pts) >= -GROUND_TOL, "meat: lies on the ground")
    mp._check(max(math.hypot(p.x, p.y) for p in pts) <= 0.36, "meat: about 0.3 m in reach")
    return {"purpose": "Creature stage food (PROPOSED): a torn haunch with a bone end, lying on the ground where a kill fell. The flesh material takes a MultiMesh instance colour.",
            "category": "environment", "kind": "food", "pivot": "under the chunk on the ground (Godot y = 0)",
            "instance_tint": "M_MeatFlesh.tres (mapped in the .glb.import) sets vertex_color_use_as_albedo, so a MultiMesh instance colour tints it; white draws it as baked.",
            "revision": 1, **baked}


# --- Engine materials (--import, after Godot has imported the GLBs) -----------------------------------------

FIELD_TRES = """[gd_resource type="ShaderMaterial" load_steps=7 format=3]

; The creature stage field's material (assets/records/creature_field_ground.json): assets/export/shaders/creature_field.gdshader
; blends the seamless turf and earth tiles in world space (one tile per 2 m) by a 37 m patch mask, with a bare
; clearing round the nest. creature_field_ground.glb.import points the imported M_CreatureField here. Written by
; tools/blender/make_creature_world.py --import.

[ext_resource type="Shader" path="res://assets/export/shaders/creature_field.gdshader" id="1_shader"]
[ext_resource type="Texture2D" path="res://assets/export/creature_field/T_CreatureField_Turf_Albedo.png" id="2_turf_albedo"]
[ext_resource type="Texture2D" path="res://assets/export/creature_field/T_CreatureField_Turf_Normal.png" id="3_turf_normal"]
[ext_resource type="Texture2D" path="res://assets/export/creature_field/T_CreatureField_Earth_Albedo.png" id="4_earth_albedo"]
[ext_resource type="Texture2D" path="res://assets/export/creature_field/T_CreatureField_Earth_Normal.png" id="5_earth_normal"]
[ext_resource type="Texture2D" path="res://assets/export/creature_field/T_CreatureField_Patch.png" id="6_patch"]

[resource]
resource_name = "M_CreatureField"
shader = ExtResource("1_shader")
shader_parameter/turf_albedo = ExtResource("2_turf_albedo")
shader_parameter/turf_normal = ExtResource("3_turf_normal")
shader_parameter/earth_albedo = ExtResource("4_earth_albedo")
shader_parameter/earth_normal = ExtResource("5_earth_normal")
shader_parameter/patch_mask = ExtResource("6_patch")
shader_parameter/tile_m = {tile}
shader_parameter/patch_m = {patch}
shader_parameter/clearing_r = {clearing}
"""

TINT_TRES = """[gd_resource type="StandardMaterial3D" load_steps=4 format=3]

; {what} (assets/records/{id}.json): the GLB's baked greyscale detail times the flat colour {hex}, times the
; MultiMesh instance colour (vertex_color_use_as_albedo; instance colours are read as sRGB like albedo_color, and
; a white instance draws the asset as baked), with the baked ORM's roughness and normal map.
; {id}.glb.import points the imported {mat} here. Written by tools/blender/make_creature_world.py --import.

[ext_resource type="Texture2D" path="res://assets/export/{id}_T_{tex}_Albedo.png" id="1_albedo"]
[ext_resource type="Texture2D" path="res://assets/export/{id}_T_{tex}_ORM.png" id="2_orm"]
[ext_resource type="Texture2D" path="res://assets/export/{id}_T_{tex}_Normal.png" id="3_normal"]

[resource]
resource_name = "{mat}"
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
albedo_color = Color({r}, {g}, {b}, 1)
albedo_texture = ExtResource("1_albedo")
roughness_texture = ExtResource("2_orm")
roughness_texture_channel = 1
normal_enabled = true
normal_texture = ExtResource("3_normal")
"""

# asset id -> {imported material name: .tres name}
EXTERNAL = {
    "creature_field_ground": {"M_CreatureField": "M_CreatureField"},
    "creature_fruit_bush": {"M_BushLeaf": "M_BushLeaf", "M_BushFruit": "M_BushFruit"},
    "creature_meat_chunk": {"M_MeatFlesh": "M_MeatFlesh"},
}
TINTED = {
    "M_BushLeaf": ("The fruit bush's leaf material", "creature_fruit_bush", "CreatureFruitBush", "#3C8A6C"),
    "M_BushFruit": ("The fruit bush's fruit material", "creature_fruit_bush", "CreatureFruitBush", "#E8A040"),
    "M_MeatFlesh": ("The meat chunk's flesh material", "creature_meat_chunk", "CreatureMeatChunk", "#8E4C34"),
}


def _set_import_param(path, key, value):
    with open(path) as f:
        text = f.read()
    new = re.sub(rf"^{re.escape(key)}=.*$", f"{key}={value}", text, flags=re.M)
    if new == text and f"{key}=" not in text:
        raise RuntimeError(f"{os.path.basename(path)}: no {key} parameter to set")
    with open(path, "w") as f:
        f.write(new)


def map_materials():
    """Writes the engine materials and points each .glb.import at them; marks the field's normal tiles as normal
    maps. Run after `godot --headless --import` has written the .import files (then import once more)."""
    export = os.path.join(bc.ROOT, "assets", "export")
    with open(os.path.join(export, "M_CreatureField.tres"), "w") as f:
        f.write(FIELD_TRES.format(tile=TILE_M, patch=PATCH_M, clearing=NEST_R + 1.5))
    for mat, (what, asset_id, tex, hex_color) in TINTED.items():
        r, g, b = (round(int(hex_color.lstrip("#")[i:i + 2], 16) / 255.0, 3) for i in (0, 2, 4))
        with open(os.path.join(export, f"{mat}.tres"), "w") as f:
            f.write(TINT_TRES.format(what=what, id=asset_id, tex=tex, mat=mat, hex=hex_color, r=r, g=g, b=b))
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
    for name in ("T_CreatureField_Turf_Normal", "T_CreatureField_Earth_Normal"):
        _set_import_param(os.path.join(TILE_DIR, f"{name}.png.import"), "compress/normal_map", 1)
        print("normal map:", name)


# asset id -> (builder, triangle budget)
ASSETS = {
    "creature_field_ground": (build_field_ground, 16000),
    "creature_nest_ring": (build_nest_ring, 4000),
    "creature_fruit_bush": (build_fruit_bush, 1200),
    "creature_meat_chunk": (build_meat_chunk, 1200),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the creature stage's world dressing.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    parser.add_argument("--import", dest="map_only", action="store_true", help="only write the engine materials and the .import mappings")
    args = parser.parse_args(argv)
    if args.map_only:
        map_materials()
        return
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
