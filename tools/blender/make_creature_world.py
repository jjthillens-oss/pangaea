"""The creature stage's world dressing (PROPOSED): the field ground, the nest ring, the fruit bush and the meat
chunk that replace the placeholders in game/scenes/creature/creature_world.gd (creature-stage-plan.md section 5),
and the creature editor's floor pad that replaces the editor scene's cylinder.

Contract from the Creature stage thread: 1 m = 1 unit, the pivot on the ground (Blender z = 0, Godot y = 0),
Blender +Y forward (Godot -Z). The field is flat and walkable (relief under 0.12 m inside the walls at +-80 m,
a berm past them); the nest ring sits at the origin, outer radius about 6 m, with a clear flat inside; the fruit
bush is about 0.5 m across and the meat chunk 0.3 m; fruit and meat draw as MultiMesh instances with a colour
per instance, so their materials take an instance tint (vertex_color_use_as_albedo in the external .tres).

- creature_field_ground: a 172 x 172 m grid with gentle relief and a berm, ringed by coarse hills out to 200 m
  (CreatureFieldHills) so the horizon is land. Drawn with the external M_CreatureField.tres
  (assets/export/shaders/creature_field.gdshader): two seamless 2.5 m tiles (a 1024 px meadow turf of grass blades
  and a 512 px bare earth) blended by a 37 m patch mask and a bare clearing round the nest.
- creature_nest_ring: a mound of packed earth and straw with twigs across it, revolved round the origin.
- creature_fruit_bush: two root meshes, Bush (a hidden clump core under crossed leaf cards that cut out a leafy
  silhouette; two surfaces of one mesh) and Fruit (nine amber fruit on it), so the stage can draw the fruit only
  while the bush is ripe. The cards sample T_BushLeafCards, a numpy atlas of four leaf clusters.
- creature_meat_chunk: a torn haunch with a bone end, lying on the ground.
- the kit (tools/blender/creature_flora.py, listed in ASSETS below): creature_grass_tuft, creature_fern_clump and
  creature_flower_clump (walk-through cover of cut-out cards sharing T_MeadowCards and M_MeadowCards.tres),
  creature_pebble_cluster, and creature_boulder_a, _b and _c (rocks for outside the walls only).
- creature_editor_room: the creature editor's floor, a unit-radius pedestal pad (the pivot at the centre of its
  top face) with a raised steel-blue rim, a rounded edge and faintly lit concentric grooves. The editor places it
  at y = -0.01 and scales it (s, 1, s) to the body, so the rings are geometry that scales with the pad.

Colours keep 25 degrees of LAB hue from the food green (114) and the threat pink (11), as every asset does; the turf
is a blue-leaning meadow green (hue 141 to 154) rather than a yellow grass green for that reason.

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
import creature_flora as cf  # noqa: E402  (the flora and rock kit: meadow cards, pebbles, boulders)
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
TILE_M = 2.5
TURF_PX = 1024           # the turf tile: 2.4 mm a pixel, so single blades hold up at the close-up camera
PATCH_M = 37.0
TURF_DRY = (0.467, 0.561, 0.465)   # #778F77, CIELAB L 57, C 17, h 143: the dry meadow's grey sage (sRGB)
TURF_LUSH = (0.78, 0.92, 0.92)     # the lush meadow's linear multiplier: deeper, toward h 150
HILLS_HALF = 200.0       # the outer hills reach this far, so the horizon is land, not the sky's ground colour
HILLS_IN = 84.0          # their inner edge starts under the berm (field edge at 86 m), so no seam shows from inside
HILLS_NEAR = (1.5, 4.0)  # low rolling hills just past the berm (metres above the berm's crest)
HILLS_FAR = (2.0, 14.0)  # an uneven far ridge from about 120 m out, with gaps and peaks, so the skyline is not a wall
NEST_R = 6.0
FRUIT_COUNT = 9
NEST_TOL = 0.012         # the nest's decimation tolerance: 1.2 cm on a 13 m ring
GROUND_TOL = 0.004       # collapse decimation may move a flattened underside this far (as cp._check_pivot allows)
BUSH_CENTRE = Vector((0.0, 0.0, 0.32))   # low enough that the core's underside sinks into its flat base at z = 0.02
BUSH_R = 0.38            # the core; the cards reach about 0.56 m from the pivot
BUSH_SQUASH = 0.85       # the clump is a little flatter than it is wide
FRUIT_LIFT = 0.07        # the fruit's centre stands this far off the core, among the cards, its underside at the core
BUSH_TOL = 0.06          # the core's decimation tolerance: it is mostly hidden under the cards
BUSH_BASE_MAX = 0.03     # the reduced core's lowest point stays this close to the ground (it is built at 0.02)
FRUIT_TOL = 0.005        # the fruit stay round: they are the bush's focal point
CARD_DIR = os.path.join(bc.ROOT, "assets", "export", "creature_fruit_bush")
CARD_ATLAS = "T_BushLeafCards"
CARD_TINT = "#3C8A6C"    # the leaf colour (LAB hue 164): 50 degrees from the food green, 150 from the threat pink
CORE_TINT = "#245442"    # the core: the leaf hue at LAB L 32 (the leaf is 52), so a gap between cards reads as shade
CARD_PAIRS = 120         # crossed pairs of quads, 4 triangles a pair
CARD_SIZE = (0.16, 0.22)   # a pair's length and width, metres
CARD_LEAN = (0.6, 1.3)     # how much of world up is added to the surface normal to give each pair's axis
CARD_SINK = 0.035        # the base of each pair sits this far under the core's surface
CARD_Z_MIN = -0.8        # cards cover the clump above this unit-sphere height; lower ones lean up, clear of the ground
CARD_Z_FLOOR = 0.06      # a pair whose lowest corner would come under this is lifted to it, so the bare skirt stays covered
PAD_R = 1.0              # the editor pad: unit radius, the scene scales it (s, 1, s) to the body
PAD_T = 0.035            # thickness under the top face (the scene never scales y, so this stays 3.5 cm)
PAD_RIM_H = 0.012        # the rim stands this far above the top face
PAD_RIM_IN = 0.86        # the rim's foot groove; its outer wall is the rim's shoulder, up to the rim top at 0.90
PAD_RIM_TOP = 0.90
PAD_EDGE_R = 0.035       # the quarter-round edge, from the rim top at r 0.965 down to the widest ring at r 1.0
PAD_GROOVES_R = (0.33, 0.60)   # the free grooves on the top face; the third groove is the rim's foot
PAD_GROOVE_W = 0.014
PAD_GROOVE_D = 0.006
PAD_SEGMENTS = 48        # 12 profile rings and two poles at 48 segments (7.5 degrees): 1152 triangles, under the 1200 budget
PAD_TOL = 0.0005         # the pad is authored at its budget, so decimation may only drop what does not move the surface
PAD_GLOW = 0.15          # the grooves' emission strength: a faint line, no brighter than the lit face, not a neon tube


def _lin(hex_color):
    return mp._lin(hex_color)


# --- Field tiles (numpy, seamless) --------------------------------------------------------------------------

def _save_tile(name, rgb, colorspace):
    """rgb: (n, n, 3) in display order, row 0 at the top; Blender stores rows bottom-up."""
    size = rgb.shape[0]
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


def _pnoise(rng, n, freqs, amps):
    """mm._periodic_noise at any size: a sum of random-phase sines with whole-number frequencies, seamless."""
    v, u = np.mgrid[0:n, 0:n].astype(np.float64) / n
    h = np.zeros((n, n))
    for f, a in zip(freqs, amps):
        for _ in range(6):
            kx, ky = rng.integers(-f, f + 1, 2)
            if kx == 0 and ky == 0:
                continue
            h += a * np.sin(2.0 * np.pi * (kx * u + ky * v) + rng.uniform(0.0, 2.0 * np.pi))
    return h


def _wrap_blur(a, r):
    """A wrapped box blur of radius r, run twice (seamless)."""
    for _ in range(2):
        for axis in (0, 1):
            a = sum(np.roll(a, d, axis=axis) for d in range(-r, r + 1)) / (2 * r + 1)
    return a


def _normal_tile(h, strength):
    """mm._normal_map at any size: tangent-space normal (OpenGL, +Y up) from a height field, wrapped differences."""
    k = 0.5 * strength * h.shape[0] / 64.0
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * k
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * k
    n = np.stack([-dx, -dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def _lch_srgb(L, C, h):
    """CIE LCh (D65) to display sRGB in [0, 1], so the turf is authored in the hue band it has to keep."""
    a, b = C * np.cos(np.radians(h)), C * np.sin(np.radians(h))
    fy = (L + 16.0) / 116.0
    d = 6.0 / 29.0
    finv = lambda f: np.where(f > d, f ** 3, 3.0 * d * d * (f - 4.0 / 29.0))   # noqa: E731
    xyz = np.stack([finv(fy + a / 500.0) * 0.95047, finv(fy), finv(fy - b / 200.0) * 1.08883], -1)
    m = np.array([[3.2404542, -1.5371385, -0.4985314], [-0.9692660, 1.8760108, 0.0415560], [0.0556434, -0.2040259, 1.0572252]])
    lin = np.clip(xyz @ m.T, 0.0, 1.0)
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1.0 / 2.4) - 0.055)


def turf_tile(rng):
    """Meadow turf seen from above (rev 2): a carpet of short grass blades, strokes 1.2 to 4 cm long and about 5 mm
    wide laid with a z-order so each pixel shows its top blade, which crowd into irregular clumps with dark thatch
    in the gaps between them. No round crowns: rev 1's lighter Voronoi domes read as puddles from the game camera.
    Authored in CIE LCh: blades at hue 141 to 154 and chroma 27 to 36 (the tile's mean is about L 45, C 26, h 147),
    so the turf keeps 25 degrees of hue from the food green (114) and still has the chroma to read as grass under
    the sky's blue ambient. The base of each blade is darker than its tip. TURF_PX square."""
    n = TURF_PX
    clump = mm._norm(_pnoise(rng, n, [3, 5, 8, 13], [1.0, 0.7, 0.45, 0.25]))     # where the blades crowd
    tone = mm._norm(_pnoise(rng, n, [3, 5, 9], [1.0, 0.6, 0.35]))                # mid-scale light and dark
    count = int(n * n * 0.085)
    cx, cy = rng.uniform(0, n, count), rng.uniform(0, n, count)
    keep = rng.uniform(0, 1, count) < 0.35 + 0.65 * clump[cy.astype(int) % n, cx.astype(int) % n]
    cx, cy = cx[keep], cy[keep]
    m = cx.size
    c = clump[cy.astype(int) % n, cx.astype(int) % n]
    ang = rng.uniform(0.0, 2.0 * np.pi, m)
    length = rng.uniform(5.0, 13.0, m) * (0.7 + 0.6 * c)          # pixels; longer blades in the clumps
    bend = rng.normal(0.0, 0.18, m) * length
    lay = rng.uniform(0.0, 1.0, m) * (0.6 + 0.4 * c)              # how high the blade lies: the clumps stand taller
    shade = rng.uniform(0.0, 1.0, m)
    hue = rng.uniform(0.0, 1.0, m)
    t = np.linspace(0.0, 1.0, 12)[None, :]
    dx, dy = np.cos(ang)[:, None], np.sin(ang)[:, None]
    xs = (cx[:, None] + dx * length[:, None] * t - dy * bend[:, None] * t * t).ravel()
    ys = (cy[:, None] + dy * length[:, None] * t + dx * bend[:, None] * t * t).ravel()
    val = (lay[:, None] * (0.55 + 0.45 * t)).ravel()             # the tip lies over the base
    bri = (shade[:, None] * 0.6 + 0.4 * t).ravel()               # and catches more light
    sid = np.repeat(np.arange(m), t.size)
    top = np.full(n * n, -1.0)
    lit = np.zeros(n * n)
    who = np.zeros(n * n, dtype=np.int64)
    offsets = ((0, 0), (1, 0), (0, 1))                            # about 2 px (5 mm) wide
    for ox, oy in offsets:
        np.maximum.at(top, ((ys.astype(int) + oy) % n) * n + (xs.astype(int) + ox) % n, val)
    for ox, oy in offsets:
        idx = ((ys.astype(int) + oy) % n) * n + (xs.astype(int) + ox) % n
        win = val >= top[idx]
        lit[idx[win]] = bri[win]
        who[idx[win]] = sid[win]
    top, lit, who = top.reshape(n, n), lit.reshape(n, n), who.reshape(n, n)
    blade = top >= 0.0
    L = np.where(blade, 36.0 + 28.0 * lit + 6.0 * (tone - 0.5) + 6.0 * (top.clip(0.0) - 0.5), 25.0 + 6.0 * tone)
    C = np.where(blade, 27.0 + 9.0 * lit + 4.0 * (tone - 0.5), 11.0)
    H = np.where(blade, 141.0 + 13.0 * hue[who], 142.0)
    h = np.where(blade, 0.35 + 0.65 * top.clip(0.0), 0.0)
    h = 0.6 * _wrap_blur(h, 1) + 0.4 * clump
    return h, _lch_srgb(L, C, H), 0.9


def earth_tile(rng):
    """Bare earth: scattered rounded pebbles of mixed sizes (wrapped Voronoi domes in about half the cells) half
    sunk in dust and grit, so the ground reads as trodden earth rather than a pebble bed up close."""
    cells = 90
    d1, _, idx = mm._voronoi(rng, cells)
    present = (rng.uniform(0.0, 1.0, cells) < 0.55).astype(np.float64)[idx]
    sizes = rng.uniform(0.3, 1.0, cells)[idx]
    dome = np.sqrt(np.clip(1.0 - (d1 / (0.03 * sizes)) ** 2, 0.0, 1.0)) * present
    grit = mm._norm(mm._periodic_noise(rng, [48, 80, 120], [0.6, 0.4, 0.3]))
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
        out.append(_save_tile(f"{name}_Normal", _normal_tile(h, strength), "Non-Color"))
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


def _hills_z(x, y):
    """The outer hills: from under the berm at HILLS_IN, low rolling hills (HILLS_NEAR) and, from about 120 m out,
    an uneven far ridge (HILLS_FAR) whose peaks and saddles come from a broad noise raised to a power, so a creature
    at the wall sees a slope and the skyline is a broken line of land rather than a wall."""
    d = max(abs(x), abs(y))
    join = 1.4 + 1.3 * bc.smoothstep((d - HILLS_IN) / 3.0)          # meets the berm's crest at the field's edge
    roll = 0.5 + 0.5 * noise.noise(Vector((x / 37.0 + 1.7, y / 37.0 - 4.2, 3.3)))
    peak = 0.5 + 0.5 * noise.noise(Vector((x / 71.0 - 2.3, y / 71.0 + 5.1, 7.7)))
    near = bc.smoothstep((d - HILLS_IN - 2.0) / 30.0) * (HILLS_NEAR[0] + (HILLS_NEAR[1] - HILLS_NEAR[0]) * roll)
    far = bc.smoothstep((d - 120.0) / 60.0) * (HILLS_FAR[0] + (HILLS_FAR[1] - HILLS_FAR[0]) * peak ** 1.6)
    return join + near + far


def build_field_hills(mat):
    """A square ring of hills from HILLS_IN to HILLS_HALF round the field, coarse (spacing 4 to 15 m outward,
    10.5 m along the ring), drawn with the field's own material. Outside the walls, so nothing walks on it."""
    outer = [HILLS_IN + (HILLS_HALF - HILLS_IN) * (k / 12.0) ** 1.35 for k in range(1, 13)]
    inner = [-HILLS_IN + 2 * HILLS_IN * k / 16.0 for k in range(17)]
    coords = [-c for c in reversed(outer)] + inner + outer
    n = len(coords)
    verts = [(x, y, _hills_z(x, y)) for y in coords for x in coords]
    faces = []
    for j in range(n - 1):
        for i in range(n - 1):
            x0, x1, y0, y1 = coords[i], coords[i + 1], coords[j], coords[j + 1]
            if max(abs(x0), abs(x1)) <= HILLS_IN + 1e-6 and max(abs(y0), abs(y1)) <= HILLS_IN + 1e-6:
                continue                                              # the field itself
            a = j * n + i
            faces.append((a, a + 1, a + n + 1, a + n))
    bc.mesh_object("CreatureFieldHills", verts, faces, [mat], fix_normals=False, uv=lambda co: (co.x / TILE_M, co.y / TILE_M))
    edge = [z for (x, y, z) in verts if abs(max(abs(x), abs(y)) - HILLS_IN) < 1e-6]
    mp._check(max(edge) < BERM_M * 0.85 * 0.98, "hills: the inner edge stays under the berm's crest")
    return max(z for (_, _, z) in verts)


def build_field_ground():
    """A square of ground 172 m across: gentle relief inside the walls at +-80 m and a berm past them, so the
    edge reads as a bank rather than a cliff, ringed by hills out to 200 m (CreatureFieldHills) so the horizon
    is land. UV = metres / TILE_M, one turf tile per 2.5 m. Drawn with the external M_CreatureField.tres (mapped in
    its .glb.import), which blends the turf and earth tiles in world space."""
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
    mat = bc.material("M_CreatureField", _lin("#4F7A55"), 0.95)
    bc.mesh_object("CreatureField", verts, faces, [mat], fix_normals=False, uv=lambda co: (co.x / TILE_M, co.y / TILE_M))
    inside = [z for (x, y, z) in verts if max(abs(x), abs(y)) <= WALL_M - 1.0]
    mp._check(max(abs(z) for z in inside) <= RELIEF_M + 1e-6, "field: relief inside the walls stays under %.2f m" % RELIEF_M)
    mp._check(max(z for (x, y, z) in verts) >= BERM_M * 0.8, "field: the berm rises past the walls")
    hills_top = build_field_hills(mat)
    return {"purpose": "Creature stage field (PROPOSED): the walkable ground, flat to within 0.12 m inside the walls at +-80 m, with a berm past them and a ring of hills out to 200 m (low near the berm, an uneven ridge farther out); meadow turf and bare earth tiles blended in world space by M_CreatureField.tres.",
            "category": "environment", "kind": "ground", "pivot": "the field's centre on the ground (Godot y = 0); the nest sits at the origin",
            "engine_material": "res://assets/export/M_CreatureField.tres",
            "walkable": {"wall_m": WALL_M, "relief_max_m": RELIEF_M, "berm_m": BERM_M, "clearing_r_m": NEST_R + 1.5},
            "hills": {"node": "CreatureFieldHills", "inner_m": HILLS_IN, "outer_m": HILLS_HALF, "near_m": list(HILLS_NEAR),
                      "far_ridge_m": list(HILLS_FAR), "top_m": round(hills_top, 2), "cast_shadow": False},
            "textures": build_field_tiles(), "revision": 2}


def _bake_mixed(objs_tol, texture, tints, size=512, accepts=None, normal=False):
    """cp._bake with a tolerance per object: (obj, tolerance_m) pairs, so small pieces keep their shape while a
    big soft one reduces hard. `accepts` maps an object's name to an extra test for its reduced mesh (sf.reduce).
    bake_set bakes a normal map only when some piece was reduced; `normal` asks for one anyway, for a mesh
    authored at its budget whose detail lives in the shader's bump."""
    before = after = 0
    highs = {}
    for obj, tol in objs_tol:
        b, a, high = sf.reduce(obj, tol, accept=(accepts or {}).get(obj.name))
        before, after = before + b, after + a
        if a == b:
            sf.drop_highs([high])
            high = None
        highs[obj.name] = high
    objs = [o for o, _ in objs_tol]
    sf.unwrap(objs)
    textures = sf.bake_set(objs, texture, size, normal=normal, highs=highs, tints=tints)
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
    return max(0.0, 0.44 - 1.6 * (r - 5.85) ** 2) if 5.35 < r < 6.45 else 0.0


def build_nest_ring():
    """A mound of packed earth and straw round the nest, outer radius about 6.45 m, inner 5.35 m, up to 0.44 m
    high and heaped unevenly, with twigs and a few stones lying across it. The inside stays clear and
    flat; the creature stands there."""
    profile = [(0.0, 5.35), (0.1, 5.47), (0.24, 5.6), (0.36, 5.72), (0.44, 5.85), (0.4, 5.98), (0.3, 6.1), (0.16, 6.22), (0.05, 6.33), (0.0, 6.45)]
    rv, rf, _ = bc.revolve(profile, 112)
    verts = []
    for x, y, z in cp._up(rv):
        r = math.hypot(x, y)
        a = math.atan2(y, x)
        z *= _nest_rise(a)
        k = min(1.0, (r - 5.35) / 0.3, (6.45 - r) / 0.3) if r > 5.35 else 0.0        # the feet stay on the ground
        bump = noise.noise(Vector((x / 0.9, y / 0.9, 1.5))) * 0.07 * k + noise.noise(Vector((a * 4.0, z * 3.0, 4.0))) * 0.03 * k
        verts.append((x + x / r * bump * 0.5, y + y / r * bump * 0.5, max(0.0, z + bump)))
    fcs = list(rf)
    face_mats = [0] * len(fcs)
    rng = random.Random(7)
    for _ in range(30):
        a = rng.uniform(0.0, math.tau)
        r = rng.uniform(5.55, 6.2)
        c = Vector((r * math.cos(a), r * math.sin(a), 0.0))
        d = Vector((-math.sin(a), math.cos(a), 0.0)).normalized()
        d = (d * math.cos(rng.uniform(-0.6, 0.6)) + Vector((math.cos(a), math.sin(a), 0.0)) * math.sin(rng.uniform(-0.6, 0.6))).normalized()
        length = rng.uniform(0.8, 1.7)
        path = []
        for t in (-0.5, -0.25, 0.0, 0.25, 0.5):
            p = c + d * (length * t)
            if p.length < 5.45:                                                    # never pokes into the clear floor
                p = p.normalized() * 5.45
            h = _nest_crown(p.length) * _nest_rise(math.atan2(p.y, p.x))          # lies on the mound's crown
            path.append(Vector((p.x, p.y, max(0.02, h) + 0.02 + 0.02 * math.sin(t * 5.0))))
        v, f, _ = cp._tube(path, lambda i, ang, s=rng.uniform(0.02, 0.04): s * (1.0 + 0.15 * math.cos(3 * ang)) if i < 4 else s * 0.7, 6)
        bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
    unit, ufaces = bc.icosphere(2)
    for _ in range(14):
        a = rng.uniform(0.0, math.tau)
        size = rng.uniform(0.1, 0.22)
        r = max(rng.uniform(5.6, 6.15), 5.4 + size * 1.3)                          # stays off the clear floor
        c = Vector((r * math.cos(a), r * math.sin(a), 0.0))
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
    mp._check(min(math.hypot(p.x, p.y) for p in pts) >= 5.3, "nest: the inside stays clear")
    return {"purpose": "Creature stage nest (PROPOSED): a ring mound of packed earth and straw, heaped unevenly, with twigs and stones across it, round a clear flat floor where the creature stands.",
            "category": "environment", "kind": "nest", "pivot": "the nest's centre on the ground (Godot y = 0)",
            "ring_m": {"inner": 5.35, "crown": 5.85, "outer": 6.45, "height": 0.44}, "revision": 1, **baked}


# --- The fruit bush ----------------------------------------------------------------------------------------

def _save_atlas(name, rgba, packing):
    """rgba: (ATLAS, ATLAS, 4) in display order, row 0 at the top; RGB sRGB-encoded, A straight alpha."""
    size = rgba.shape[0]
    px = np.ascontiguousarray(np.clip(rgba[::-1], 0.0, 1.0).astype(np.float32))
    img = bpy.data.images.new(name, size, size, alpha=True)
    img.colorspace_settings.name = "Non-Color"     # values are written as-is; sRGB data is already encoded
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(px.ravel())
    os.makedirs(CARD_DIR, exist_ok=True)
    img.filepath_raw = os.path.join(CARD_DIR, f"{name}.png")
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return {"name": name, "path": f"assets/export/creature_fruit_bush/{name}.png", "size": [size, size], "colorspace": "sRGB", "packing": packing}


def leaf_card_atlas(rng):
    """The leaf cards' atlas: four leaf-cluster variants in a 2 x 2 grid. Each is a sprig of three to six
    overlapping leaves fanning up from the cell's bottom centre (the card's base), with a mid-vein, soft shading
    toward the leaf edges and a shadow band where a leaf lies over another. RGB is greyscale detail with a mild
    bias (lit crowns warmer, shadows cooler) that the engine multiplies by M_BushCards' leaf colour, as the baked
    albedos are; alpha is the anti-aliased cut-out mask. Between the leaves the RGB holds a mid tone, so the
    half-covered edge pixels blend toward the leaf family, never toward black."""
    size = mm.SIZE
    cell = size // 2
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)       # display order: row 0 at the top
    rgb = np.empty((size, size, 3))
    rgb[...] = (0.42, 0.46, 0.5)
    alpha = np.zeros((size, size))
    grain = mm._norm(mm._periodic_noise(rng, [24, 48, 96], [0.5, 0.3, 0.2]))
    soft = 1.4                                                  # px of edge anti-aliasing
    profile = lambda u: u ** 0.5 * (1.0 - u) ** 0.75            # rounded base to a soft point
    peak = profile(0.5 / 1.25)
    warm, cool = np.array([1.0, 1.0, 0.86]), np.array([0.9, 0.96, 1.0])
    for variant in range(4):
        cx, cy = (variant % 2) * cell, (variant // 2) * cell
        # The alpha is zero within 4 px of the cell's edge and fades in over the next 6 px, so a bilinear tap or a near
        # mip never pulls in the next variant.
        edge = np.minimum(np.minimum(xx - cx, cx + cell - 1 - xx), np.minimum(yy - cy, cy + cell - 1 - yy))
        margin = np.clip((edge - 4.0) / 6.0, 0.0, 1.0)
        root = (cx + cell * 0.5, cy + cell * 0.95)
        count = (3, 4, 5, 6)[variant]                             # three to six leaves, one count per variant
        leaves = []
        for i in range(count):
            spread = -1.0 + 2.0 * (i + 0.5) / count            # fanned left to right
            ang = spread * (0.8 + 0.06 * count) + rng.uniform(-0.1, 0.1)   # radians from straight up
            stem = cell * rng.uniform(0.0, 0.12)
            ratio = rng.uniform(0.24, 0.32)
            length = cell * rng.uniform(0.66, 0.86) * (1.0 - 0.1 * abs(spread))
            # Shrink a leaf until its tip and its widest part stay about 12 px inside the cell (the curl may take it
            # a little further; the edge fade above catches that).
            reach_x = lambda n: (stem + n) * abs(math.sin(ang)) + 0.5 * ratio * n * abs(math.cos(ang))
            reach_y = lambda n: (stem + n) * math.cos(ang) + 0.5 * ratio * n * abs(math.sin(ang))
            while reach_x(length) > 0.5 * cell - 12 or reach_y(length) > 0.95 * cell - 12:
                length *= 0.96
            leaves.append((ang, length, length * ratio, stem, rng.uniform(-0.25, 0.25), rng.uniform(0.62, 1.0)))
        leaves.sort(key=lambda leaf: leaf[5])                    # darker leaves underneath, the lit crowns on top
        for ang, length, width, stem, bend, tone in leaves:
            dx, dy = xx - root[0], root[1] - yy
            along = dx * math.sin(ang) + dy * math.cos(ang) - stem
            across = dx * math.cos(ang) - dy * math.sin(ang)
            u = np.clip(along / length, 0.0, 1.0)
            across = across - bend * length * u * u             # a sideways curl
            half = width * profile(u) / peak
            inside = np.minimum(half - np.abs(across), np.minimum(along, length - along))   # px inside the leaf (negative outside)
            a = np.clip(inside / soft + 0.5, 0.0, 1.0) * margin
            rim = np.clip(np.abs(across) / np.maximum(half, 1e-6), 0.0, 1.0)
            vein = np.exp(-(across / (0.9 + 0.012 * length)) ** 2) * np.clip((u - 0.04) / 0.08, 0.0, 1.0) * np.clip((0.92 - u) / 0.1, 0.0, 1.0)
            side = 0.5 + 0.5 * np.cos((u * 9.0 + np.abs(across) / (0.35 * length)) * math.tau)   # faint side veins
            light = tone * (1.0 - 0.38 * rim * rim) * (0.9 + 0.2 * u) + 0.14 * tone * vein + 0.03 * side * (1.0 - rim) + 0.06 * (grain - 0.5)
            light = np.clip(light, 0.2, 1.0)
            colour = light[..., None] * (cool + (warm - cool) * np.clip((light - 0.4) / 0.5, 0.0, 1.0)[..., None])
            band = np.clip((inside + 7.0) / 5.0, 0.0, 1.0) * (1.0 - a) * alpha   # the shadow this leaf throws on those under it
            rgb = np.maximum(rgb * (1.0 - 0.3 * band)[..., None], 0.2)
            rgb = rgb * (1.0 - a)[..., None] + colour * a[..., None]
            alpha = np.maximum(alpha, a)
    rgba = np.concatenate([rgb, alpha[..., None]], axis=-1)
    mp._check(0.25 < float((alpha > 0.5).mean()) < 0.7, "bush atlas: the leaves fill a good share of each card")
    return rgba


def _clump_profile(rng):
    """Where the core bulges: sixteen soft lobes spread over the sphere."""
    golden = math.pi * (3.0 - math.sqrt(5.0))
    clumps = []
    for k in range(16):
        z = 1.0 - 2.0 * (k + 0.5) / 16
        rr = math.sqrt(1.0 - z * z)
        clumps.append((Vector((rr * math.cos(golden * k), rr * math.sin(golden * k), z)), rng.uniform(0.09, 0.16), rng.uniform(0.6, 1.0)))
    return clumps


def _clump_point(n, clumps):
    """The core's surface in unit direction `n`: a lumpy, slightly squashed ball standing on the ground."""
    bump = sum(w * math.exp(-((1.0 - n.dot(d)) / width) ** 2) for d, width, w in clumps)
    leaf = noise.noise(n * 9.0) * 0.025 + noise.noise(n * 20.0 + Vector((3.0, 0.0, 0.0))) * 0.005
    r = BUSH_R * (0.74 + 0.26 * min(1.0, bump)) + leaf
    p = BUSH_CENTRE + Vector((n.x * r, n.y * r, n.z * r * BUSH_SQUASH))
    return Vector((p.x, p.y, max(p.z, 0.02)))


def _leaf_cards(clumps, rng):
    """CARD_PAIRS crossed pairs of quads over the core's upper two thirds. Each pair stands on the surface with
    its base sunk under it and its axis the local normal leaned toward up (so side cards reach up and out, top
    ones stand up). Its first quad is rolled to face out across the surface, give or take 0.6 rad, so it covers
    the core seen from outside; the second stands at right angles, radially, and breaks the silhouette. Each
    pair samples one of the atlas's four variants, each quad mirrored at random. Returns (verts, faces, uv per vertex)."""
    golden = math.pi * (3.0 - math.sqrt(5.0))
    up = Vector((0.0, 0.0, 1.0))
    verts, faces, uvs = [], [], []
    for k in range(CARD_PAIRS):
        z = CARD_Z_MIN + (1.0 - CARD_Z_MIN) * (k + 0.5) / CARD_PAIRS
        rr = math.sqrt(1.0 - z * z)
        a = golden * k + rng.uniform(-0.3, 0.3)
        n = Vector((rr * math.cos(a), rr * math.sin(a), z + rng.uniform(-0.04, 0.04))).normalized()
        normal = Vector((n.x, n.y, n.z / BUSH_SQUASH)).normalized()
        axis = (normal + up * rng.uniform(*CARD_LEAN)).normalized()
        base = _clump_point(n, clumps) - normal * CARD_SINK
        side = axis.cross(normal)                                  # along the surface, across the lean
        if side.length < 1e-3:                                     # at the crown the lean has no direction
            side = Vector((math.cos(a), math.sin(a), 0.0))
        side = (side - axis * side.dot(axis)).normalized()
        roll = rng.uniform(-0.6, 0.6)
        w1 = (side * math.cos(roll) + axis.cross(side) * math.sin(roll)).normalized()
        size = rng.uniform(*CARD_SIZE)
        variant = rng.randrange(4)
        u0, v0 = (variant % 2) * 0.5, 0.5 - (variant // 2) * 0.5     # the atlas's top row is the high v half
        pair = []
        for w in (w1, axis.cross(w1).normalized()):
            half = w * (size * 0.5)
            tip = base + axis * size
            pair.append([base - half, base + half, tip + half, tip - half])
            ua, ub = (u0, u0 + 0.5) if rng.random() < 0.5 else (u0 + 0.5, u0)
            uvs.extend([(ua, v0), (ub, v0), (ub, v0 + 0.5), (ua, v0 + 0.5)])
        lift = max(0.0, CARD_Z_FLOOR - min(v.z for quad in pair for v in quad))   # the lowest pairs ride up a little
        for quad in pair:
            i = len(verts)
            verts.extend([(v.x, v.y, v.z + lift) for v in quad])
            faces.append((i, i + 1, i + 2, i + 3))
    return verts, faces, uvs


def _card_material(path, tint):
    """The cards' Blender material: the atlas's detail times the leaf colour, cut out by its alpha. The Round
    node on the alpha is what the glTF exporter reads as alphaMode MASK (cutoff 0.5), so the GLB's own material
    is a cut-out too; the engine draws the external M_BushCards.tres instead."""
    mat = bpy.data.materials.new("M_BushCards")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    img = bpy.data.images.load(path, check_existing=True)
    img.name = CARD_ATLAS
    img.colorspace_settings.name = "sRGB"
    img.alpha_mode = "STRAIGHT"
    img.pack()
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    mul = nodes.new("ShaderNodeMix")
    mul.data_type, mul.blend_type = "RGBA", "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    links.new(tex.outputs["Color"], mul.inputs["A"])
    mul.inputs["B"].default_value = (*tint, 1.0)
    links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    clip = nodes.new("ShaderNodeMath")
    clip.operation = "ROUND"
    links.new(tex.outputs["Alpha"], clip.inputs[0])
    links.new(clip.outputs[0], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Metallic"].default_value = 0.0
    mat.blend_method = "CLIP"
    mat.alpha_threshold = 0.5
    mat.use_backface_culling = False       # glTF doubleSided: the cards are seen from both sides
    return mat


def build_fruit_bush():
    """A leafy shrub about 0.6 m across (Bush) with amber fruit on its upper surface (Fruit), as two root meshes
    so the stage draws the fruit only while the bush is ripe. Bush is one mesh with two surfaces: a lumpy core
    (M_BushLeaf, baked, reduced hard because it is mostly hidden) under crossed leaf cards (M_BushCards, the
    T_BushLeafCards atlas cut out by its alpha) that give it a leafy silhouette. All three materials take an
    instance tint."""
    unit, ufaces = bc.icosphere(5)
    golden = math.pi * (3.0 - math.sqrt(5.0))
    rng = random.Random(11)
    clumps = _clump_profile(rng)
    bush = [tuple(_clump_point(Vector(co).normalized(), clumps)) for co in unit]
    fruit_v, fruit_f = [], []
    unit2, ufaces2 = bc.icosphere(2)          # 80 triangles a fruit before its own, tighter reduction
    spots = []
    for k in range(FRUIT_COUNT):
        z = 0.25 + 0.7 * (k + 0.5) / FRUIT_COUNT
        rr = math.sqrt(1.0 - z * z)
        d = Vector((rr * math.cos(golden * k * 2.0 + 1.0), rr * math.sin(golden * k * 2.0 + 1.0), z))
        spots.append(_clump_point(d, clumps) + Vector((d.x, d.y, d.z / BUSH_SQUASH)).normalized() * FRUIT_LIFT)
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
    leaf_mat = leaf_sh.out(leaf_base, 0.95)          # dull: the core is seen only in the gaps, as shade
    bush_obj = bc.mesh_object("Bush", bush, ufaces, [leaf_mat])
    leaf_mat.name = "M_BushLeaf"
    fruit_mat = fruit_sh.out(fruit_base, 0.35)
    fruit_obj = bc.mesh_object("Fruit", fruit_v, fruit_f, [fruit_mat])
    fruit_mat.name = "M_BushFruit"
    # The hard reduction may neither lift the core's flattened base off the ground (the bush would hover) nor
    # push it under.
    grounded = lambda mesh: -GROUND_TOL <= min(v.co.z for v in mesh.vertices) <= BUSH_BASE_MAX
    baked = _bake_mixed([(bush_obj, BUSH_TOL), (fruit_obj, FRUIT_TOL)], "CreatureFruitBush",
                        {"M_BushLeaf": sf.tint(_lin(CORE_TINT)), "M_BushFruit": sf.tint(_lin("#E8A040"))}, accepts={"Bush": grounded})
    # The leaf cards go on after the bake, so the core's baked UVs and the cards' atlas UVs both survive: built
    # as their own object with the atlas material, then joined into Bush as its second surface.
    atlas = _save_atlas(CARD_ATLAS, leaf_card_atlas(np.random.default_rng(5103)),
                        "RGB greyscale leaf-cluster detail (four variants in a 2 x 2 grid) times M_BushCards' base colour; A the cut-out mask (alpha scissor at 0.5)")
    card_v, card_f, card_uv = _leaf_cards(clumps, rng)
    cards_obj = bc.mesh_object("BushCards", card_v, card_f, [_card_material(os.path.join(bc.ROOT, atlas["path"]), _lin(CARD_TINT))], fix_normals=False)
    layer = cards_obj.data.uv_layers["UVMap"]
    for loop in cards_obj.data.loops:
        layer.data[loop.index].uv = card_uv[loop.vertex_index]
    sf.select([bush_obj, cards_obj])
    bpy.ops.object.join()
    mp._check([s.material.name for s in bush_obj.material_slots] == ["M_BushLeaf", "M_BushCards"], "bush: the core and the cards are two surfaces of one mesh")
    mp._check(min(v[2] for v in card_v) >= 0.05, "bush: no card reaches the ground")
    pts = bc.world_vertices()
    low = min(p.z for p in pts)
    mp._check(-GROUND_TOL <= low <= BUSH_BASE_MAX, "bush: sits on the ground (lowest point z %.4f)" % low)
    mp._check(max(math.hypot(p.x, p.y) for p in pts) <= 0.6, "bush: within 0.6 m of its pivot")
    baked["textures"].append(atlas)
    return {"purpose": "Creature stage food (PROPOSED): a blue-green leafy shrub (a lumpy core under crossed leaf cards cut out by the T_BushLeafCards atlas) with amber fruit; the Fruit mesh is drawn only while ripe. All three materials take a MultiMesh instance colour.",
            "category": "environment", "kind": "food", "pivot": "under the bush on the ground (Godot y = 0)",
            "instance_tint": "M_BushLeaf.tres, M_BushCards.tres and M_BushFruit.tres (mapped in the .glb.import) set vertex_color_use_as_albedo, so a MultiMesh instance colour tints the core, the cards and the fruit alike; white draws them as baked.",
            "states": {"ripe": "draw Bush (core and cards) and Fruit", "bare": "draw Bush (core and cards) only"}, "fruit_count": FRUIT_COUNT,
            "cards": {"pairs": CARD_PAIRS, "triangles": CARD_PAIRS * 4, "size_m": list(CARD_SIZE), "surface": "Bush surface 1, M_BushCards", "atlas": atlas["path"]},
            "revision": 2, **baked}


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


# --- The creature editor's floor pad -----------------------------------------------------------------------

def _sharpen_rings(obj, rings):
    """Marks the edges round each profile ring in `rings` ((z, r) pairs) sharp, so smooth shading keeps the
    grooves and the rim's foot crisp while the rounded edge, whose segments meet at up to 45 degrees, stays
    round (Blender splits normals at sharp edges, and the glTF export keeps the split)."""
    import bmesh
    keys = {(round(z, 4), round(r, 4)) for z, r in rings}
    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def key(v):
        return round(v.co.z, 4), round(math.hypot(v.co.x, v.co.y), 4)

    for e in bm.edges:
        a, b = key(e.verts[0]), key(e.verts[1])
        if a == b and a in keys:
            e.smooth = False
    bm.to_mesh(obj.data)
    bm.free()


def _pad_profile():
    """The pad's profile as (z, r) from the centre of the top face out and round to the centre of the bottom:
    two V grooves on the face, the rim's foot groove (its outer wall is the rim's shoulder), the rim's flat top,
    a quarter-round edge down to the widest ring at r = 1, and the underside, rising 12 mm from the centre to the
    edge (the camera never sees it). Returns the profile, the material of each profile segment (0 pad, 1 rim,
    2 groove) and the rings to keep sharp."""
    profile, mats, sharp = [(0.0, 0.0)], [], []
    for g in PAD_GROOVES_R:
        groove = [(0.0, g - PAD_GROOVE_W / 2), (-PAD_GROOVE_D, g), (0.0, g + PAD_GROOVE_W / 2)]
        profile += groove
        sharp += groove
        mats += [0, 2, 2]
    foot = [(0.0, PAD_RIM_IN - PAD_GROOVE_W / 2), (-PAD_GROOVE_D, PAD_RIM_IN)]
    profile += foot + [(PAD_RIM_H, PAD_RIM_TOP)]
    sharp += foot
    mats += [0, 2, 1]
    arc_r, arc_z = PAD_R - PAD_EDGE_R, PAD_RIM_H - PAD_EDGE_R
    for deg in (90, 45, 0):
        profile.append((arc_z + PAD_EDGE_R * math.sin(math.radians(deg)), arc_r + PAD_EDGE_R * math.cos(math.radians(deg))))
        mats.append(1)
    sharp.append(profile[-1])
    profile.append((-PAD_T, 0.0))
    mats.append(0)
    return profile, mats, sharp


def build_editor_room():
    """The creature editor's floor: a unit-radius pedestal pad, 3.5 cm thick, dark blue with a raised steel-blue
    rim, a rounded edge and three faintly lit concentric grooves (two on the face and one at the rim's foot).
    The pivot is the centre of the top face, so the editor's y = -0.01 placement and its (s, 1, s) scaling keep
    working: the rings are geometry, so they scale with the pad in plan while the thickness stays."""
    profile, seg_mats, sharp = _pad_profile()
    rv, rf, bands = bc.revolve(profile, PAD_SEGMENTS)
    verts = cp._up(rv)
    face_mats = [seg_mats[b] for b in bands]
    pad = sf.Shader("M_EditorPadProc")
    radial = pad.vmath("LENGTH", pad.vmath("MULTIPLY", pad.pos, (1.0, 1.0, 0.0)))        # radius in the face plane
    spin = pad.noise(1.0, 2.0, vector=pad.vmath("MULTIPLY", radial, (70.0, 70.0, 70.0)))   # concentric brushed streaks, about 1.5 cm
    grain = pad.noise(40.0, 2.0)
    pad.bump(pad.math("ADD", pad.math("MULTIPLY", spin, 0.7), pad.math("MULTIPLY", grain, 0.3)), 0.2, 0.006)
    pad_fac = pad.math("ADD", pad.math("MULTIPLY", pad.remap(spin, 0.3, 0.7), 0.65), pad.math("MULTIPLY", grain, 0.35), clamp=True)
    rim = sf.Shader("M_EditorRimProc")
    rim_r = rim.vmath("LENGTH", rim.vmath("MULTIPLY", rim.pos, (1.0, 1.0, 0.0)))
    brush = rim.noise(1.0, 2.0, vector=rim.vmath("MULTIPLY", rim_r, (150.0, 150.0, 150.0)))
    rim.bump(brush, 0.3, 0.004)
    groove = sf.Shader("M_EditorGrooveProc")
    dust = groove.noise(60.0, 2.0)
    mats = [pad.out(cp._grey(pad, pad_fac, 0.8), pad.remap(grain, 0.0, 1.0, 0.47, 0.56)),
            rim.out(cp._grey(rim, rim.remap(brush, 0.3, 0.7), 0.78), rim.remap(brush, 0.0, 1.0, 0.4, 0.5)),
            groove.out(cp._grey(groove, groove.remap(dust, 0.3, 0.7), 0.9), 0.55)]
    obj = bc.mesh_object("CreatureEditorRoom", verts, rf, mats, face_mats)
    _sharpen_rings(obj, sharp)
    mats[0].name, mats[1].name, mats[2].name = "M_EditorPad", "M_EditorRim", "M_EditorGroove"
    baked = _bake_mixed([(obj, PAD_TOL)], "CreatureEditorRoom",
                        {"M_EditorPad": sf.tint(_lin("#14305C")), "M_EditorRim": sf.tint(_lin("#5A7FA8")),
                         "M_EditorGroove": sf.tint(_lin("#0E2246"), emission=_lin("#5FB3FF"), emission_strength=PAD_GLOW)},
                        size=1024, normal=True)
    pts = bc.world_vertices()
    mp._check(abs(max(math.hypot(p.x, p.y) for p in pts) - PAD_R) < 1e-4, "room: the pad's radius is 1.0")
    mp._check(abs(min(p.z for p in pts) + PAD_T) < 1e-4, "room: the pad is 3.5 cm thick under the face's centre")
    mp._check(abs(max(p.z for p in pts) - PAD_RIM_H) < 1e-4, "room: the rim stands 12 mm above the face")
    # Decimation folds the coplanar pole fans into the first ring, so the face is read at the first groove's inner edge.
    face = [p.z for p in pts if math.hypot(p.x, p.y) <= PAD_GROOVES_R[0] - PAD_GROOVE_W / 2 + 1e-4 and p.z > -PAD_T / 2]
    mp._check(len(face) >= PAD_SEGMENTS and max(abs(z) for z in face) < 1e-4, "room: the top face is at z = 0, the pivot")
    return {"purpose": "Creature editor floor (PROPOSED): a unit-radius pedestal pad for the Spore-style editor room, dark blue with a raised steel-blue rim, a rounded edge and three faintly lit concentric grooves; replaces the creature_editor_floor placeholder cylinder.",
            "category": "environment", "kind": "editor_floor",
            "pivot": "the centre of the top face (Blender z = 0, Godot y = 0); the rim stands 12 mm above it and the underside's centre 35 mm below",
            "usage": "Place it where the cylinder was, at y = -0.01 (the face 1 cm under the feet, the rim's top 2 mm over them; y = 0 stands the body on the face), and scale it Vector3(s, 1, s), s = max(1.2, 1.4 x the body's longest axis): the rim and grooves are concentric geometry, so they scale with the pad in plan while the thickness stays 35 mm. Move it with the camera focus as the body walks; the camera never looks under it.",
            "pad_m": {"radius": PAD_R, "thickness": PAD_T, "rim_height": PAD_RIM_H, "rim_top_r": [PAD_RIM_TOP, PAD_R - PAD_EDGE_R],
                      "edge_radius": PAD_EDGE_R, "grooves_r": [*PAD_GROOVES_R, PAD_RIM_IN], "groove_width": PAD_GROOVE_W, "groove_depth": PAD_GROOVE_D,
                      "segments": PAD_SEGMENTS},
            "emission": f"M_EditorGroove emits a flat #5FB3FF at strength {PAD_GLOW}, a faint line under the editor's glow", "revision": 1, **baked}


# --- Engine materials (--import, after Godot has imported the GLBs) -----------------------------------------

FIELD_TRES = """[gd_resource type="ShaderMaterial" load_steps=7 format=3]

; The creature stage field's material (assets/records/creature_field_ground.json): assets/export/shaders/creature_field.gdshader
; blends the seamless turf and earth tiles in world space (one tile per 2.5 m, at two scales against repetition) by a 37 m patch mask, with a bare
; clearing round the nest. dry_color (sRGB) and lush_tint (a linear multiplier) are the meadow's two macro variations; both keep the turf's hue
; at 139 or more (tests/test_creature_world_art.gd). creature_field_ground.glb.import points the imported M_CreatureField here. Written by
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
shader_parameter/patch_low = 0.56
shader_parameter/patch_high = 0.7
shader_parameter/dry_color = Color({dry[0]}, {dry[1]}, {dry[2]}, 1)
shader_parameter/lush_tint = Vector3({lush[0]}, {lush[1]}, {lush[2]})
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
{extra}"""

CARDS_TRES = """[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

; The fruit bush's leaf cards (assets/records/creature_fruit_bush.json): the T_BushLeafCards atlas's greyscale
; leaf-cluster detail times the flat leaf colour {hex}, times the MultiMesh instance colour
; (vertex_color_use_as_albedo; instance colours are read as sRGB like albedo_color, and a white instance draws
; the cards as authored), cut out by the atlas's alpha (scissor at 0.5) and drawn from both sides (no culling).
; The texture is the copy Godot extracts from the GLB (the authored file is assets/export/creature_fruit_bush/):
; the scene importer gives it mipmaps and fixed alpha borders. creature_fruit_bush.glb.import points the
; imported M_BushCards here. Written by tools/blender/make_creature_world.py --import.

[ext_resource type="Texture2D" path="res://assets/export/creature_fruit_bush_{atlas}.png" id="1_albedo"]

[resource]
resource_name = "M_BushCards"
transparency = 1
alpha_scissor_threshold = 0.5
cull_mode = 2
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
albedo_color = Color({r}, {g}, {b}, 1)
albedo_texture = ExtResource("1_albedo")
roughness = 0.8
"""

# asset id -> {imported material name: .tres name}
EXTERNAL = {
    "creature_field_ground": {"M_CreatureField": "M_CreatureField"},
    "creature_fruit_bush": {"M_BushLeaf": "M_BushLeaf", "M_BushCards": "M_BushCards", "M_BushFruit": "M_BushFruit"},
    "creature_meat_chunk": {"M_MeatFlesh": "M_MeatFlesh"},
    **cf.EXTERNAL,
}
# asset id -> per-mesh and per-node import options, written into the same `_subresources` block as the materials:
#   "meshes": {"<asset id>_<glTF mesh name>": {"generate/lods": 2}}   (e.g. for card meshes, whose LODs eat the cards)
#   "nodes": {"PATH:<node path below the scene root>": {"mesh_instance/cast_shadow": 0,
#                                                      "mesh_instance/visibility_range_end": 55.0}}
# Checked on Godot 4.7.2 with a reimported probe copy of the meat chunk: "PATH:MeatChunk" set the node's cast_shadow
# to 0 and visibility_range_end to 55; the mesh key is the GLB's file name, "_", then the glTF mesh name
# ("<id>_MeatChunk_mesh"), and "generate/lods" is an enum (0 project default, 1 enable, 2 disable): 2 took the
# mesh from 3 LOD levels to none, while a bare "MeatChunk_mesh" key or the value false did nothing.
IMPORT_OPTIONS = {
    # The outer hills stand beyond the sun's 80 m shadow distance almost everywhere: they need not cast.
    "creature_field_ground": {"nodes": {"PATH:CreatureFieldHills": {"mesh_instance/cast_shadow": 0}}},
    **cf.IMPORT_OPTIONS,
}
# Godot writes these back into every mesh entry it matches; writing them too keeps a rerun byte for byte the same.
MESH_IMPORT_DEFAULTS = {"generate/lightmap_uv": 0, "generate/shadow_meshes": 0, "lods/normal_merge_angle": 20.0,
                        "save_to_file/enabled": False, "save_to_file/fallback_path": "", "save_to_file/path": ""}
MESH_ENUM_OPTIONS = ("generate/lightmap_uv", "generate/lods", "generate/shadow_meshes")
TINTED = {
    "M_BushLeaf": ("The fruit bush's leaf core under its leaf cards", "creature_fruit_bush", "CreatureFruitBush", CORE_TINT),
    "M_BushFruit": ("The fruit bush's fruit material", "creature_fruit_bush", "CreatureFruitBush", "#E8A040"),
    "M_MeatFlesh": ("The meat chunk's flesh material", "creature_meat_chunk", "CreatureMeatChunk", "#8E4C34"),
}

# Extra lines for a tinted material. The bush core is dark and seen only through gaps in the leaf cards; at the
# default specular a sunlit gap shines pale like plastic, so it reflects a little less.
TINT_EXTRA = {"M_BushLeaf": "metallic_specular = 0.2\n"}


def _set_import_param(path, key, value):
    with open(path) as f:
        text = f.read()
    new = re.sub(rf"^{re.escape(key)}=.*$", f"{key}={value}", text, flags=re.M)
    if new == text and f"{key}=" not in text:
        raise RuntimeError(f"{os.path.basename(path)}: no {key} parameter to set")
    with open(path, "w") as f:
        f.write(new)


def _import_value(value):
    """A Python value in the .import file's Variant text: true/false, ints, floats with a point, quoted strings."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        text = repr(value)
        return text if any(c in text for c in ".en") else text + ".0"
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    raise TypeError(f"no .import text for {value!r}")


def _subresources_block(materials, options):
    """The whole `_subresources={...}` value for one asset, keys sorted as Godot writes them back, so a second run
    over a file Godot has since rewritten leaves it unchanged."""
    groups = {}
    if materials:
        groups["materials"] = {m: {"use_external/enabled": True,
                                   "use_external/fallback_path": f"res://assets/export/{t}.tres",
                                   "use_external/path": f"res://assets/export/{t}.tres"} for m, t in materials.items()}
    if options.get("meshes"):
        groups["meshes"] = {}
        for mesh, opts in options["meshes"].items():
            for key in MESH_ENUM_OPTIONS:
                if key in opts and (isinstance(opts[key], bool) or opts[key] not in (0, 1, 2)):
                    raise ValueError(f"{mesh}: {key} is an enum (0 project default, 1 enable, 2 disable), not {opts[key]!r}")
            groups["meshes"][mesh] = {**MESH_IMPORT_DEFAULTS, **opts}
    if options.get("nodes"):
        groups["nodes"] = options["nodes"]
    if not groups:
        return "_subresources={}"
    parts = []
    for group in sorted(groups):
        entries = []
        for name in sorted(groups[group]):
            fields = ",\n".join(f'"{k}": {_import_value(v)}' for k, v in sorted(groups[group][name].items()))
            entries.append(f'"{name}": {{\n{fields}\n}}')
        parts.append(f'"{group}": {{\n' + ",\n".join(entries) + "\n}")
    return "_subresources={\n" + ",\n".join(parts) + "\n}"


def _replace_subresources(text, block):
    """`text` (a .glb.import) with its whole `_subresources={...}` value replaced by `block`. Scans for the brace that
    closes the opening one, skipping braces inside quoted strings, so an already-mapped file (nested braces) is
    replaced whole; the regex this replaces stopped at the first inner brace and left two stray `}` lines."""
    key = "_subresources="
    start = text.find(key)
    if start < 0:
        raise RuntimeError("no _subresources line; run godot --headless --import first")
    i = start + len(key)
    if text[i] != "{":
        raise RuntimeError(f"_subresources is not a dictionary at offset {i}")
    depth, in_string, escaped = 0, False, False
    for j in range(i, len(text)):
        c = text[j]
        if in_string:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[:start] + block + text[j + 1:]
    raise RuntimeError("unbalanced braces in _subresources")


def map_materials():
    """Writes the engine materials and points each .glb.import at them; marks the field's normal tiles as normal
    maps. Run after `godot --headless --import` has written the .import files (then import once more)."""
    export = os.path.join(bc.ROOT, "assets", "export")
    with open(os.path.join(export, "M_CreatureField.tres"), "w") as f:
        f.write(FIELD_TRES.format(tile=TILE_M, patch=PATCH_M, clearing=NEST_R + 1.5, dry=TURF_DRY, lush=TURF_LUSH))
    for mat, (what, asset_id, tex, hex_color) in TINTED.items():
        r, g, b = (round(int(hex_color.lstrip("#")[i:i + 2], 16) / 255.0, 3) for i in (0, 2, 4))
        with open(os.path.join(export, f"{mat}.tres"), "w") as f:
            f.write(TINT_TRES.format(what=what, id=asset_id, tex=tex, mat=mat, hex=hex_color, r=r, g=g, b=b, extra=TINT_EXTRA.get(mat, "")))
    r, g, b = (round(int(CARD_TINT.lstrip("#")[i:i + 2], 16) / 255.0, 3) for i in (0, 2, 4))
    with open(os.path.join(export, "M_BushCards.tres"), "w") as f:
        f.write(CARDS_TRES.format(hex=CARD_TINT, atlas=CARD_ATLAS, r=r, g=g, b=b))
    for asset_id in sorted(set(EXTERNAL) | set(IMPORT_OPTIONS)):
        mats = EXTERNAL.get(asset_id, {})
        options = IMPORT_OPTIONS.get(asset_id, {})
        path = os.path.join(export, f"{asset_id}.glb.import")
        with open(path) as f:
            text = f.read()
        with open(path, "w") as f:
            f.write(_replace_subresources(text, _subresources_block(mats, options)))
        counts = "".join(f"; {len(options[g])} {g}" for g in ("meshes", "nodes") if options.get(g))
        print("mapped", (", ".join(f"{m} -> {t}" for m, t in mats.items()) or "no materials") + counts, "in", os.path.basename(path))
    for name in ("T_CreatureField_Turf_Normal", "T_CreatureField_Earth_Normal"):
        _set_import_param(os.path.join(TILE_DIR, f"{name}.png.import"), "compress/normal_map", 1)
        print("normal map:", name)
    _set_import_param(os.path.join(CARD_DIR, f"{CARD_ATLAS}.png.import"), "mipmaps/generate", "true")   # as the extracted copy has
    print("mipmaps:", CARD_ATLAS)
    cf.map_materials(export, _set_import_param)


# asset id -> (builder, triangle budget)
ASSETS = {
    "creature_field_ground": (build_field_ground, 16000),
    "creature_nest_ring": (build_nest_ring, 4000),
    "creature_fruit_bush": (build_fruit_bush, 1200),
    "creature_meat_chunk": (build_meat_chunk, 1200),
    "creature_editor_room": (build_editor_room, 1200),
    **cf.ASSETS,
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
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR,
                           provenance=fields.pop("provenance", PROVENANCE))
        if asset_id in cf.CARD_ASSETS:
            cf.link_atlas(bc.paths(asset_id)[1])
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
