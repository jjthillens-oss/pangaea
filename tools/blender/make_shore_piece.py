"""The shore piece (asset id shore_piece, docs/art/shore_piece.md): the sandbar at the pool's mouth, where the
cell swims out of the pool into the open sea (ShoreLink's first link, the sea edge), in Blender. All of it is
PROPOSED design, awaiting the owner's look review.

Four nodes, the pivot on the shore point on the swim plane (Blender z = 0), front +Y = north:

- ShoreBank: a sand landing wholly below the swim band (no vertex above SAND_TOP_M, -1.6 m), seen
  from above at cell size 4 (1 m = 1 tm at the size shown). A lobed shelf with a spit to the south-east
  and a notch in the west rises gently north to its crest, breaks at a rounded brink, and falls away in
  a gentle south ramp (toward the camera and the approaching cell), steeper flanks and a steep north
  face, steepening into a skirt that ends deep in the fog. Giant sand grains (0.3 to 1.0 m, the size-4
  cell is about one grain across) lie half sunk along the south brink and spill down the ramp, with
  two broken glass valve fragments for the micro world. One baked material, M_ShorePiece (albedo,
  ORM, normal at 1024 px), from a procedural shader: a wet-to-dry ramp by height, ripple marks
  along the contours, mineral flecks, frosted grains and glassy fragments.
- Shaft: an open cone of light standing on the landing, its foot seated on the sand, up to +4.5 m (the
  toast says "Swim into its light"). UV v runs 0 at the bottom to 1 at the top.
- Glow: the pool of light the shaft lays on the sand, a disc that follows the shelf a few cm above it,
  so the inside of the shaft's foot reads lit rather than as a dark hole. UV v runs 0 at the centre to 1
  at the rim.
- Reach: a flat annulus on the swim plane (z -0.05) centred on ShoreLink.REACH_TM (4 m), where the
  offer opens. UV v runs 0 inside to 1 outside.

Shaft, Reach and Glow are engine-drawn: their material M_ShoreLight maps (in the .glb.import, with
--import) to assets/export/M_ShoreLight.tres, an additive, unshaded, fog-free shader. COLOR_0 (the
LightWeight attribute, stored as raw values) tells the parts apart: red is the part's strength,
green 0 for the shaft (brightest on the sand, fading upward and toward its silhouette) and 1 for the
ring (a soft band across v), blue 1 for the glow (brightest in the middle, soft at the rim). glTF
flips v; the shader flips it back.

Run (with the bpy module, or blender --background --python):
  python tools/blender/make_shore_piece.py              build, bake, write the .blend, GLB, record and M_ShoreLight.tres
  python tools/blender/make_shore_piece.py --rough      geometry and procedural shader only, saved to --out (default
                                                        builds/shore_piece/, which Git ignores; no tracked writes)
  python tools/blender/make_shore_piece.py --root=DIR   as the default, but every output goes under DIR instead of the repo
  python tools/blender/make_shore_piece.py --import     after `godot --headless --import`: map M_ShoreLight in the .glb.import
  python tools/blender/make_shore_piece.py --light      rewrite only M_ShoreLight.tres (light tuning; no bake, no export)
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
import make_s1_kit as k  # noqa: E402
import make_s1_production as p1  # noqa: E402
import surfacing as sf  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

ASSET_ID = "shore_piece"
GENERATOR = "tools/blender/make_shore_piece.py"
REVIEW_STATE = p1.REVIEW_STATE
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_shore_piece.py; no external or generated meshes. "
              "Textures baked in Blender from procedural shaders. No outside sources.")
BUDGET = 6000
TEXTURE_PX = 1024
SEED = 4248
ROUGH_OUT = os.path.join(bc.ROOT, "builds", "shore_piece", "shore_piece_rough.blend")   # builds/ is gitignored

# --- Contract numbers (the record carries them; tests/test_shore_piece.gd reads the record) -----------------
SAND_TOP_M = -1.6          # the landing's top: under the ambience contract's decor-free band (-1.5 to +0.5)
SOLID_MAX_M = -1.55        # build-time assert: no bank, grain or fragment vertex above this
REACH_M = 4.0              # ShoreLink.REACH_TM: the reach ring's mid radius
REACH_HALF_WIDTH = 0.3     # the ring spans 3.7 to 4.3 m
REACH_Z = -0.05
SHAFT_TOP_M = 4.5
SHAFT_R_TOP, SHAFT_R_BOTTOM = 1.8, 2.8
LIGHT_LIFT_M = 0.04        # the shaft's foot and the glow sit this far above the sand (they follow ground())
GLOW_R = SHAFT_R_BOTTOM    # the glow fills the shaft's foot
SKIRT_BOTTOM_M = -20.0
SHAFT_WEIGHT = 0.45        # LightWeight red: the shaft draws dimmer than the ring
RING_WEIGHT = 1.0
GLOW_WEIGHT = 1.0
LIGHT_TINT = "#FFD486"     # warm sunlight through shallow water: LAB h 82.9, 31.5 degrees from the food green
# M_ShoreLight's look in Forward+ (the shipped renderer). ShoreView scales the two gains for Compatibility, which
# tonemaps each additive layer before it blends (docs/TOOLCHAIN.md), so dim and bright layers drift apart there.
SHAFT_GAIN = 0.85          # the shaft's strength (times LightWeight red)
RING_GAIN = 0.35           # the ring's strength (times LightWeight red): it peaks under L* 80 at the pulse's top
SHAFT_FADE = 0.4           # the shaft fades from this share of its height (from the sand) to its top
SHAFT_EDGE = 1.5           # the shaft fades toward its silhouette as facing^SHAFT_EDGE
NEAR_TOP = 0.6             # the wall toward the camera is gone above this share of the shaft's height (it would
                           # light the cell standing in the shaft); the far wall carries the column
GLOW_GAIN = 0.10           # the glow's strength (times LightWeight red, and the shaft's renderer gain)
GLOW_CORE = 0.45           # the glow is even out to this share of its radius, then falls softly to 0 at the rim
# The pool's sun and ambient light the sand at about 1.9 times its albedo on screen (Gate 4, docs/art/shore_piece.md):
# the baked albedo is scaled once so the shelf reads L* 36 to 48 behind the cell, under the coral cell.
ALBEDO_GAIN = 0.27

# --- The landing's shape (Blender metres) -------------------------------------------------------------------
CENTRE = (0.25, 0.9)       # the shelf's centre, a little north of the pivot (the crest lies north)
CREST_Y = 1.8              # the shelf top is flat at SAND_TOP from here north; south of it, it falls gently
TILT = 0.085               # m of fall per m south of CREST_Y
SEGMENTS = 56
INNER_T = [0.13, 0.27, 0.41, 0.55, 0.68, 0.79, 0.88, 0.95, 1.0]        # fractions of the brink radius
# The outer rings are contours: metres below the brink. The last reaches SKIRT_BOTTOM_M everywhere.
OUTER_DEPTH = [0.06, 0.18, 0.38, 0.68, 1.1, 1.65, 2.35, 3.25, 4.4, 5.9, 8.4, 12.0, None]
PLANAR_RINGS = 9           # the first outer rings (to about -6.5 m) keep the planar top-down UV; the rest share the skirt strip
# UV atlas regions (u0, v0, u1, v1)
UV_PLANAR = (0.004, 0.164, 0.996, 0.996)
UV_SKIRT = (0.504, 0.004, 0.996, 0.156)
UV_GRAINS = (0.004, 0.004, 0.496, 0.156)


def _bump(th, centre, width):
    d = (th - centre + math.pi) % math.tau - math.pi
    return math.exp(-(d / width) ** 2)


def brink_radius(th):
    """The brink's distance from CENTRE in direction th (radians from +X, counter-clockwise; north is +pi/2)."""
    s = math.sin(th)
    r = 6.3 - 0.95 * max(0.0, s) ** 1.5 + 0.45 * max(0.0, -s)
    r += 0.22 * math.cos(3 * th + 0.7) + 0.14 * math.sin(5 * th + 1.9) + 0.07 * math.cos(9 * th + 0.4)
    r += 2.7 * _bump(th, -0.72, 0.21)          # the spit, curling south-east
    r -= 1.2 * _bump(th, math.pi * 1.06, 0.2)  # the notch, cutting the west (the brink stays 4.8 m from the pivot)
    return r


def slope_params(th):
    """(tan of the straight slope past the brink, the brink's rounding length, the depth below the brink
    where the slope ends and the skirt plunges into the fog)."""
    s = math.sin(th)
    deg = 36.0 + 12.0 * max(0.0, s) + 10.0 * min(0.0, s) - 4.0 * _bump(th, -0.72, 0.25)   # S 26, E/W 36, N 48
    rounding = 0.3 - 0.15 * max(0.0, s)                    # a tight brink on the ramp, a sharp crest edge north
    ramp_depth = 6.0 + 2.0 * max(0.0, -s) - 2.0 * max(0.0, s)  # the south ramp runs deepest, to about -10 m
    return math.tan(math.radians(deg)), rounding, ramp_depth


def plateau(x, y):
    """The shelf top: flat at SAND_TOP_M north of CREST_Y, falling gently south, with broad low swells."""
    fall = TILT * max(0.0, CREST_Y - y)
    swell = 0.035 * (1.0 + math.sin(math.tau * (y + 0.5 * math.sin(0.31 * x + 0.6)) / 3.1))
    return SAND_TOP_M - fall - swell


def _drop(s, th):
    """How far the bank has fallen at s metres past the brink: a rounded brink, a straight slope, then a
    skirt plunging steeply once the slope has fallen ramp_depth metres."""
    t, b, ramp_depth = slope_params(th)
    if s <= 0.0:
        return 0.0
    s1 = ramp_depth / t + b
    return t * (math.sqrt(s * s + b * b) - b) + 0.4 * max(0.0, s - s1) ** 2


def _relief(x, y, s):
    """Low gullies and lumps on the slopes (none on the shelf top)."""
    w = bc.smoothstep((s - 0.6) / 2.5)
    return w * 0.22 * noise.noise(Vector((x / 3.2 + 4.1, y / 3.2 + 1.7, 0.3)))


def _brink_point(th):
    r = brink_radius(th)
    return CENTRE[0] + r * math.cos(th), CENTRE[1] + r * math.sin(th)


BERM_M = 0.09             # a low lip along the brink that catches the light
BERM_W = 0.55


def height_polar(th, s):
    """Height at signed distance s from the brink along the ray th from CENTRE (s < 0 inside)."""
    r = brink_radius(th)
    d = r + s
    x, y = CENTRE[0] + d * math.cos(th), CENTRE[1] + d * math.sin(th)
    berm = BERM_M * math.exp(-((s + 0.35) / BERM_W) ** 2)
    if s <= 0.0:
        return min(plateau(x, y) + berm, SAND_TOP_M)
    bx, by = _brink_point(th)
    return min(plateau(bx, by) + berm - _drop(s, th) + _relief(x, y, s), SAND_TOP_M)


def ground(x, y):
    """The bank's height under (x, y)."""
    dx, dy = x - CENTRE[0], y - CENTRE[1]
    th = math.atan2(dy, dx)
    return height_polar(th, math.hypot(dx, dy) - brink_radius(th))


def run_to_depth(th, depth):
    """How far past the brink the bank falls `depth` metres below the brink along th."""
    target = height_polar(th, 0.0) - depth
    lo, hi = 0.0, 60.0
    for _ in range(40):
        mid = (lo + hi) / 2.0
        if height_polar(th, mid) > target:
            lo = mid
        else:
            hi = mid
    return hi


def ripple_phase(x, y, th, s):
    """Horizontal distance (m) that ripple marks count along: southward from the crest, so the crests run
    east-west, parallel to the shore in the north. On the south half they bend to follow the brink
    (constant phase along it), fading back to east-west toward the flanks; the north half stays
    east-west (no fold, so no closed loops on the crest)."""
    def inner(px, py):
        return (CREST_Y + 4.0 - py) + 0.35 * math.sin(0.42 * px + 0.9) + 0.2 * math.sin(0.9 * px - 0.3 * py)
    bx, by = _brink_point(th)
    along = inner(bx, by) - s * math.sin(th)
    if s >= 0.0:
        wt = 1.0
    else:
        wt = bc.smoothstep((1.0 + s / brink_radius(th) - 0.7) / 0.3)
    w = wt * max(0.0, -math.sin(th)) ** 2
    here = inner(x, y)
    return here + w * (along - here)


# --- Mesh assembly ------------------------------------------------------------------------------------------


class Mesh:
    """Vertices, faces with per-corner UVs, and per-vertex attributes for the shader."""

    def __init__(self):
        self.verts, self.faces, self.face_uvs = [], [], []
        self.ripple, self.mask, self.local = [], [], []

    def vert(self, co, ripple=0.0, mask=(0.0, 0.0, 0.0), local=(0.0, 0.0)):
        self.verts.append(tuple(co))
        self.ripple.append(ripple)
        self.mask.append(mask)
        self.local.append(local)
        return len(self.verts) - 1

    def face(self, idx, uvs):
        self.faces.append(tuple(idx))
        self.face_uvs.append(list(uvs))


def _region(rect, u, v):
    return rect[0] + u * (rect[2] - rect[0]), rect[1] + v * (rect[3] - rect[1])


def build_bank(m):
    """The landing: a polar grid around CENTRE whose rings follow the lobed brink outline."""
    seg = SEGMENTS
    rows = []   # per ring: (vertex ids, positions)
    pole = m.vert((CENTRE[0], CENTRE[1], plateau(*CENTRE)), ripple_phase(CENTRE[0], CENTRE[1], 0.0, -brink_radius(0.0)))
    rings = [("in", t) for t in INNER_T] + [("out", dep) for dep in OUTER_DEPTH]
    for kind, f in rings:
        ids = []
        for j in range(seg):
            th = math.tau * j / seg
            r = brink_radius(th)
            if kind == "in":
                s = (f - 1.0) * r
            else:
                s = run_to_depth(th, f if f is not None else height_polar(th, 0.0) - SKIRT_BOTTOM_M)
            d = r + s
            x, y = CENTRE[0] + d * math.cos(th), CENTRE[1] + d * math.sin(th)
            z = height_polar(th, s)
            ids.append(m.vert((x, y, z), ripple_phase(x, y, th, s)))
        rows.append(ids)
    # Planar UV over the pole, the inner rings and the first PLANAR_RINGS outer rings.
    last_planar = len(INNER_T) + PLANAR_RINGS - 1
    pts = [m.verts[pole]] + [m.verts[i] for row in rows[:last_planar + 1] for i in row]
    lo_x, hi_x = min(p[0] for p in pts), max(p[0] for p in pts)
    lo_y, hi_y = min(p[1] for p in pts), max(p[1] for p in pts)
    w, h = UV_PLANAR[2] - UV_PLANAR[0], UV_PLANAR[3] - UV_PLANAR[1]
    scale = min(w / (hi_x - lo_x), h / (hi_y - lo_y))
    ox = UV_PLANAR[0] + (w - scale * (hi_x - lo_x)) / 2.0
    oy = UV_PLANAR[1] + (h - scale * (hi_y - lo_y)) / 2.0

    def planar(i):
        p = m.verts[i]
        return ox + (p[0] - lo_x) * scale, oy + (p[1] - lo_y) * scale

    skirt_rows = len(rows) - last_planar - 1

    def skirt(ring, j):
        return _region(UV_SKIRT, j / seg, (ring - last_planar) / skirt_rows)

    for j in range(seg):
        n = (j + 1) % seg
        a, b = rows[0][j], rows[0][n]
        m.face((pole, a, b), [planar(pole), planar(a), planar(b)])
    for i in range(len(rows) - 1):
        for j in range(seg):
            n = (j + 1) % seg
            q = (rows[i][j], rows[i + 1][j], rows[i + 1][n], rows[i][n])
            if i < last_planar:
                uvs = [planar(v) for v in q]
            else:
                uvs = [skirt(i, j), skirt(i + 1, j), skirt(i + 1, j + 1), skirt(i, j + 1)]
            m.face(q, uvs)
    return {"texel_px_per_m": round(scale * TEXTURE_PX, 1), "planar_depth_m": round(min(m.verts[i][2] for i in rows[last_planar]), 2)}


def _tile(index, count_cols=11, rows=4):
    """The square UV tile (u0, v0, size) for piece `index` in the grains region."""
    size = min((UV_GRAINS[2] - UV_GRAINS[0]) / count_cols, (UV_GRAINS[3] - UV_GRAINS[1]) / rows)
    col, row = index % count_cols, index // count_cols
    if row >= rows:
        raise RuntimeError(f"shore_piece: no UV tile left for piece {index}")
    return UV_GRAINS[0] + col * size, UV_GRAINS[1] + row * size, size


def _in_tile(tile, u, v, pad=0.1):
    u0, v0, size = tile
    return u0 + size * (pad + (1.0 - 2.0 * pad) * u), v0 + size * (pad + (1.0 - 2.0 * pad) * v)


def _footprint_floor(x, y, radius):
    """The lowest ground under a circle of `radius` round (x, y)."""
    pts = [(x, y)] + [(x + radius * math.cos(a), y + radius * math.sin(a)) for a in (i * math.tau / 10 for i in range(10))]
    return min(ground(px, py) for px, py in pts)


def place_grains(rng):
    """Grain specs (x, y, a, b, c, yaw, tone): half sunk along the south brink, spilling down the ramp,
    a few by the spit and along the shelf's east and west edges. None within 1.3 m of the pivot."""
    specs = []
    zones = [  # (count, angle range deg, s range m, diameter range m)
        (11, (-160, -25), (-0.9, 1.4), (0.5, 1.0)),
        (9, (-150, -40), (1.4, 6.5), (0.3, 0.75)),
        (4, (-55, -30), (-1.5, 2.5), (0.35, 0.8)),
        (4, (150, 210), (-1.6, 1.0), (0.3, 0.6)),
    ]
    for count, (a0, a1), (s0, s1), (d0, d1) in zones:
        placed, tries = 0, 0
        while placed < count and tries < 4000:
            tries += 1
            th = math.radians(rng.uniform(a0, a1))
            s = rng.uniform(s0, s1)
            d = brink_radius(th) + s
            x, y = CENTRE[0] + d * math.cos(th), CENTRE[1] + d * math.sin(th)
            diameter = rng.uniform(d0, d1)
            a = diameter / 2.0
            if math.hypot(x, y) < 1.3 + a:
                continue
            if any(math.hypot(x - g[0], y - g[1]) < 0.95 * (a + g[2]) + 0.1 for g in specs):
                continue
            b = a * rng.uniform(0.75, 1.0)
            c = a * rng.uniform(0.55, 0.8)
            floor = _footprint_floor(x, y, 0.9 * a)
            bottom = floor - 0.06 - 2.0 * c * rng.uniform(0.25, 0.5)   # half sunk, deeper on the uphill side
            if bottom + 2.0 * c > SOLID_MAX_M - 0.03:   # would stand into the swim band: sink it deeper
                bottom = SOLID_MAX_M - 0.03 - 2.0 * c
            if bottom + 2.0 * c < ground(x, y) + 0.12:  # sunk out of sight: skip
                continue
            tone = rng.random()
            specs.append((x, y, a, b, c, rng.uniform(0.0, math.tau), tone, bottom + c))
            placed += 1
    return specs


def build_grains(m, specs, first_tile):
    """Squashed, slightly irregular icosphere pebbles; faces wholly buried are dropped."""
    culled = 0
    for n, (x, y, a, b, c, yaw, tone, zc) in enumerate(specs):
        verts, faces = bc.icosphere(3 if a > 0.42 else 2)    # the biggest grains get the finer sphere
        tile = _tile(first_tile + n)
        ids, uvs = [], []
        cy, sy = math.cos(yaw), math.sin(yaw)
        for vx, vy, vz in verts:
            bumpy = 1.0 + 0.07 * noise.noise(Vector((vx * 1.7 + n * 3.1, vy * 1.7, vz * 1.7)))
            lx, ly, lz = vx * a * bumpy, vy * b * bumpy, vz * c * bumpy
            wx, wy = x + lx * cy - ly * sy, y + lx * sy + ly * cy
            ids.append((wx, wy, zc + lz))
            # Lambert azimuthal equal-area about the top pole: no overlap, the buried bottom at the rim.
            pol = math.acos(max(-1.0, min(1.0, vz)))
            az = math.atan2(vy, vx)
            rho = math.sin(pol / 2.0)
            uvs.append(_in_tile(tile, 0.5 + 0.5 * rho * math.cos(az), 0.5 + 0.5 * rho * math.sin(az)))
        keep = []
        for f in faces:
            if all(ids[i][2] < ground(ids[i][0], ids[i][1]) - 0.04 for i in f):
                culled += 1
                continue
            keep.append(f)
        used = sorted({i for f in keep for i in f})
        remap = {}
        for i in used:
            remap[i] = m.vert(ids[i], 0.0, (1.0, 0.0, tone))
        for f in keep:
            m.face([remap[i] for i in f], [uvs[i] for i in f])
    return culled


def build_fragment(m, x, y, radius, yaw, tilt, tiles, rng):
    """A broken diatom valve: half a shallow glass lens with a jagged break, tilted and half sunk."""
    nu, nv = 10, 4
    thick = 0.07 * radius
    dome = 0.16 * radius
    breaks = [0.06 * radius * (1 if i % 2 else -1) * rng.uniform(0.4, 1.0) for i in range(nu + 1)]

    def local_point(i, j, top):
        u = -1.0 + 2.0 * i / nu
        edge_y = breaks[i]
        arc_y = math.sqrt(max(0.0, 1.0 - u * u)) * radius
        v = j / nv
        lx = u * radius * (1.0 - 0.02 * v)
        ly = edge_y + v * (max(arc_y, edge_y + 0.02) - edge_y)
        rr = min(1.0, (lx * lx + ly * ly) / (radius * radius))
        lz = dome * (1.0 - rr) + (thick / 2.0 if top else -thick / 2.0 - 0.25 * dome * (1.0 - rr))
        return lx, ly, lz

    cy, sy = math.cos(yaw), math.sin(yaw)
    ct, st = math.cos(tilt), math.sin(tilt)

    def world(p):
        lx, ly, lz = p
        ly, lz = ly * ct - lz * st, ly * st + lz * ct          # tilt about the break edge (local x axis)
        return x + lx * cy - ly * sy, y + lx * sy + ly * cy, lz

    pts = {}
    for top in (True, False):
        for i in range(nu + 1):
            for j in range(nv + 1):
                pts[(top, i, j)] = local_point(i, j, top)
    # Sink it: the lowest corner well under the sand, the top under the swim band.
    worlds = {key: world(p) for key, p in pts.items()}
    lift = min(ground(wx, wy) - wz for wx, wy, wz in worlds.values()) + 0.12 * radius
    top_z = max(wz for _, _, wz in worlds.values()) + lift
    if top_z > SOLID_MAX_M - 0.03:
        lift -= top_z - (SOLID_MAX_M - 0.03)
    ids = {}
    for key, (wx, wy, wz) in worlds.items():
        lx, ly, _ = pts[key]
        ids[key] = m.vert((wx, wy, wz + lift), 0.0, (0.0, 1.0, 0.0), (lx / radius, ly / radius))

    def uv(key):
        top, i, j = key
        lx, ly, _ = pts[key]
        tile = tiles[0] if top else tiles[1]
        return _in_tile(tile, 0.5 + 0.5 * lx / radius, 0.5 + 0.5 * (ly / radius - 0.5) * 1.6 + 0.0)

    for i in range(nu):
        for j in range(nv):
            q = [(True, i, j), (True, i + 1, j), (True, i + 1, j + 1), (True, i, j + 1)]
            m.face([ids[p] for p in q], [uv(p) for p in q])
            q = [(False, i, j + 1), (False, i + 1, j + 1), (False, i + 1, j), (False, i, j)]
            m.face([ids[p] for p in q], [uv(p) for p in q])
    # The rim round the arc and the jagged break, top to bottom (bottom tile carries the sides).
    loop = [(i, 0) for i in range(nu + 1)] + [(nu, j) for j in range(1, nv + 1)] + \
           [(i, nv) for i in range(nu - 1, -1, -1)] + [(0, j) for j in range(nv - 1, 0, -1)]
    for n in range(len(loop)):
        (i0, j0), (i1, j1) = loop[n], loop[(n + 1) % len(loop)]
        q = [(True, i1, j1), (True, i0, j0), (False, i0, j0), (False, i1, j1)]
        m.face([ids[p] for p in q], [uv((False, i0, j0)), uv((False, i1, j1)), uv((False, i1, j1)), uv((False, i0, j0))])


def _object(name, m, mats, smooth=True):
    obj = bc.mesh_object(name, m.verts, m.faces, mats, smooth=smooth, fix_normals=False)
    mesh = obj.data
    layer = mesh.uv_layers["UVMap"]
    for poly in mesh.polygons:
        for corner, li in enumerate(poly.loop_indices):
            layer.data[li].uv = m.face_uvs[poly.index][corner]
    return obj


def _set_attributes(obj, m):
    mesh = obj.data
    rip = mesh.attributes.new("Ripple", "FLOAT", "POINT")
    rip.data.foreach_set("value", m.ripple)
    mask = mesh.color_attributes.new("Mask", "FLOAT_COLOR", "POINT")
    mask.data.foreach_set("color", [c for rgb in m.mask for c in (*rgb, 1.0)])
    local = mesh.color_attributes.new("Local", "FLOAT_COLOR", "POINT")
    local.data.foreach_set("color", [c for uv in m.local for c in (uv[0], uv[1], 0.0, 1.0)])


def _strip_attributes(obj):
    """The shader's helper attributes stay out of the export once the bake has used them."""
    mesh = obj.data
    for name in ("Ripple", "Mask", "Local"):
        attr = mesh.attributes.get(name)
        if attr is not None:
            mesh.attributes.remove(attr)


def build_light(mat):
    """The Shaft (open cone, its foot on the sand), the Reach ring and the Glow on the sand, with LightWeight
    as raw COLOR_0 values."""
    seg = 24
    rows = 5
    verts, faces, uvs = [], [], []
    for i in range(rows):
        f = i / (rows - 1)
        r = SHAFT_R_BOTTOM + (SHAFT_R_TOP - SHAFT_R_BOTTOM) * f
        for j in range(seg + 1):                       # a duplicated seam column so u runs 0 to 1
            a = math.tau * j / seg
            x, y = r * math.cos(a), r * math.sin(a)
            bottom = ground(SHAFT_R_BOTTOM * math.cos(a), SHAFT_R_BOTTOM * math.sin(a)) + LIGHT_LIFT_M
            verts.append((x, y, bottom + (SHAFT_TOP_M - bottom) * f))
            uvs.append((j / seg, f))
    cols = seg + 1
    for i in range(rows - 1):
        for j in range(seg):
            faces.append((i * cols + j, i * cols + j + 1, (i + 1) * cols + j + 1, (i + 1) * cols + j))
    shaft = bc.mesh_object("Shaft", verts, faces, [mat], fix_normals=False)
    _per_vertex_uv(shaft, uvs)
    _weight(shaft, (SHAFT_WEIGHT, 0.0, 0.0))

    seg = 64
    radii = [REACH_M - REACH_HALF_WIDTH, REACH_M, REACH_M + REACH_HALF_WIDTH]
    verts, faces, uvs = [], [], []
    for i, r in enumerate(radii):
        for j in range(seg + 1):
            a = math.tau * j / seg
            verts.append((r * math.cos(a), r * math.sin(a), REACH_Z))
            uvs.append((j / seg, i / (len(radii) - 1)))
    cols = seg + 1
    for i in range(len(radii) - 1):
        for j in range(seg):
            faces.append((i * cols + j, (i + 1) * cols + j, (i + 1) * cols + j + 1, i * cols + j + 1))
    reach = bc.mesh_object("Reach", verts, faces, [mat], fix_normals=False)
    _per_vertex_uv(reach, uvs)
    _weight(reach, (RING_WEIGHT, 1.0, 0.0))

    # The glow: a fan of rings out to the shaft's foot, each vertex on the sand plus the lift.
    seg = 32
    fracs = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
    verts, faces, uvs = [(0.0, 0.0, ground(0.0, 0.0) + LIGHT_LIFT_M)], [], [(0.5, 0.0)]
    for i, t in enumerate(fracs[1:]):
        for j in range(seg + 1):
            a = math.tau * j / seg
            x, y = GLOW_R * t * math.cos(a), GLOW_R * t * math.sin(a)
            verts.append((x, y, ground(x, y) + LIGHT_LIFT_M))
            uvs.append((j / seg, t))
    cols = seg + 1
    for j in range(seg):
        faces.append((0, 1 + j, 1 + j + 1))
    for i in range(len(fracs) - 2):
        for j in range(seg):
            a0, b0 = 1 + i * cols + j, 1 + (i + 1) * cols + j
            faces.append((a0, b0, b0 + 1, a0 + 1))
    glow = bc.mesh_object("Glow", verts, faces, [mat], fix_normals=False)
    _per_vertex_uv(glow, uvs)
    _weight(glow, (GLOW_WEIGHT, 0.0, 1.0))
    return shaft, reach, glow


def _per_vertex_uv(obj, uvs):
    layer = obj.data.uv_layers["UVMap"]
    for loop in obj.data.loops:
        layer.data[loop.index].uv = uvs[loop.vertex_index]


def _weight(obj, rgb):
    col = obj.data.color_attributes.new("LightWeight", "FLOAT_COLOR", "POINT")
    for d in col.data:
        d.color = (*rgb, 1.0)


# --- The procedural sand shader (baked) ---------------------------------------------------------------------


def sand_shader():
    """Sand by height (wet and darker down the slope, palest on the crest), ripple marks along the
    contours, heavy-mineral flecks in the troughs; smooth grains in quartz, feldspar and umber; and
    glassy valve fragments with radial ribs and pores. Albedo stays at or under 0.40 linear luminance."""
    sh = sf.Shader("M_ShoreSand")

    def attr(name, out):
        n = sh.node("ShaderNodeAttribute", attribute_name=name)
        return n.outputs[out]

    def channel(color_socket, name):
        n = sh.node("ShaderNodeSeparateColor")
        sh.link(color_socket, n.inputs["Color"])
        return n.outputs[name]

    mask = attr("Mask", "Color")
    is_grain = channel(mask, "Red")
    is_glass = channel(mask, "Green")
    tone = channel(mask, "Blue")
    local = attr("Local", "Color")
    lx, ly = channel(local, "Red"), channel(local, "Green")

    z = sh.axis("Z")
    dry = sh.remap(z, -6.0, -1.65)                                    # 0 wet deep slope, 1 dry crest
    warp = sh.math("MULTIPLY", sh.math("SUBTRACT", sh.noise(0.35, 2.0, 0.5), 0.5), 0.9)
    phase = sh.math("ADD", attr("Ripple", "Fac"), warp)
    # Wave ripples: sharp crests, broad troughs, wavelength 0.72 m; broad swells 2.6 m.
    crest = sh.math("SUBTRACT", 1.0, sh.math("ABSOLUTE", sh.math("SINE", sh.math("MULTIPLY", phase, math.pi / 0.72))))
    swell = sh.math("SINE", sh.math("MULTIPLY", phase, math.tau / 2.6))
    # Ripples fade in the skirt and on faces steeper than about 30 degrees (the north slip face, the flanks).
    up = sh.vmath("DOT_PRODUCT", sh.node("ShaderNodeNewGeometry").outputs["Normal"], (0.0, 0.0, 1.0))
    rip_fade = sh.math("MULTIPLY", sh.remap(z, -7.5, -3.0), sh.remap(up, 0.8, 0.9))
    crest_f = sh.math("MULTIPLY", crest, rip_fade)
    mottle = sh.noise(1.2, 3.0, 0.55)
    fine = sh.noise(22.0, 2.0, 0.6)
    tone_sand = sh.math("ADD", sh.math("MULTIPLY", dry, 0.88),
                        sh.math("ADD", sh.math("MULTIPLY", sh.math("SUBTRACT", crest_f, 0.5), 0.14),
                                sh.math("MULTIPLY", sh.math("SUBTRACT", mottle, 0.5), 0.2)))
    tone_sand = sh.math("ADD", tone_sand, sh.math("MULTIPLY", sh.math("SUBTRACT", fine, 0.5), 0.08))
    sand = sh.ramp(tone_sand, [(0.0, "#5C4A36"), (0.35, "#7A6549"), (0.62, "#937A57"), (0.85, "#A88F6B"), (1.0, "#B39A76")])
    # Heavy minerals gather in the ripple troughs; a few amber feldspar flecks.
    specks = sh.remap(sh.voronoi(9.0, 1.0), 0.12, 0.05)                # 1 in a speck
    trough = sh.math("POWER", sh.math("SUBTRACT", 1.0, crest_f), 2.0)
    dark = sh.math("MULTIPLY", specks, sh.math("ADD", 0.25, sh.math("MULTIPLY", trough, 0.75)))
    dark = sh.math("MULTIPLY", dark, sh.remap(sh.noise(3.0, 1.0), 0.45, 0.6))
    sand = sh.mix(sh.math("MULTIPLY", dark, 0.75), sand, "#3F3529")
    amber = sh.math("MULTIPLY", sh.remap(sh.voronoi(5.0, 1.0, vector=sh.vmath("ADD", sh.pos, (7.3, 1.1, 0.0))), 0.07, 0.03),
                    sh.remap(sh.noise(2.0, 1.0, vector=sh.vmath("ADD", sh.pos, (3.0, 9.0, 0.0))), 0.55, 0.7))
    sand = sh.mix(sh.math("MULTIPLY", amber, 0.8), sand, "#9A7444")

    # Grains: matte, frosted quartz cream (most), amber feldspar, a few umber; faint frosting and inclusions.
    g_mottle = sh.noise(3.5, 3.0, 0.6)
    grain = sh.ramp(tone, [(0.0, "#ADA089"), (0.6, "#B2A48B"), (0.62, "#9E7A4F"), (0.9, "#A27D51"), (0.92, "#5D4A3A"), (1.0, "#625040")])
    grain = sh.mix(sh.math("MULTIPLY", sh.math("SUBTRACT", g_mottle, 0.5), 0.5), grain, "#FFFFFF", "OVERLAY")
    # Glass: a pale grey-green silica with radial ribs and rings of pores from the valve's centre.
    angle = sh.math("ARCTAN2", ly, lx)
    radius = sh.math("SQRT", sh.math("ADD", sh.math("MULTIPLY", lx, lx), sh.math("MULTIPLY", ly, ly)))
    ribs = sh.remap(sh.math("SINE", sh.math("MULTIPLY", angle, 28.0)), 0.3, 0.95)
    pores = sh.math("MULTIPLY", sh.remap(sh.math("SINE", sh.math("MULTIPLY", radius, 40.0)), 0.6, 0.95),
                    sh.math("SUBTRACT", 1.0, ribs))
    glass = sh.mix(sh.math("MULTIPLY", pores, 0.6), "#8E9A97", "#5E6966")
    glass = sh.mix(sh.math("MULTIPLY", ribs, 0.35), glass, "#9DA8A5")

    base = sh.mix(is_grain, sand, grain)
    base = sh.mix(is_glass, base, glass)
    base = sh.mix(1.0, base, (ALBEDO_GAIN, ALBEDO_GAIN, ALBEDO_GAIN, 1.0), "MULTIPLY")   # the pool's exposure

    rough_sand = sh.remap(dry, 0.0, 1.0, 0.6, 0.9)
    rough = sh.math("ADD", sh.math("MULTIPLY", sh.math("SUBTRACT", 1.0, sh.math("MAXIMUM", is_grain, is_glass)), rough_sand),
                    sh.math("ADD", sh.math("MULTIPLY", is_grain, 0.58), sh.math("MULTIPLY", is_glass, 0.16)))

    # Relief: ripples (about 0.04 m), swells (about 0.05 m), sand texture; smooth grains; glass ribs.
    h_sand = sh.math("ADD", sh.math("MULTIPLY", crest_f, 1.0), sh.math("MULTIPLY", swell, sh.math("MULTIPLY", rip_fade, 0.6)))
    h_sand = sh.math("ADD", h_sand, sh.math("MULTIPLY", fine, 0.15))
    h_sand = sh.math("SUBTRACT", h_sand, sh.math("MULTIPLY", specks, 0.1))
    h_grain = sh.math("MULTIPLY", g_mottle, 0.25)
    h_glass = sh.math("SUBTRACT", sh.math("MULTIPLY", ribs, 0.5), sh.math("MULTIPLY", pores, 0.5))
    height = sh.math("ADD", sh.math("MULTIPLY", sh.math("SUBTRACT", 1.0, sh.math("MAXIMUM", is_grain, is_glass)), h_sand),
                     sh.math("ADD", sh.math("MULTIPLY", is_grain, h_grain), sh.math("MULTIPLY", is_glass, h_glass)))
    sh.bump(height, 1.0, 0.035)
    return sh.out(base, rough)


# --- Build, bake, export --------------------------------------------------------------------------------------


def build():
    """The landing: ShoreBank with the procedural sand shader. Returns (bank, stats)."""
    rng = random.Random(SEED)
    m = Mesh()
    stats = build_bank(m)
    specs = place_grains(rng)
    first = 0
    stats["grain_faces_culled"] = build_grains(m, specs, first)
    frag_tiles = [(_tile(len(specs)), _tile(len(specs) + 1)), (_tile(len(specs) + 2), _tile(len(specs) + 3))]
    # Two broken valves: one by the spit on the brink, one down the south-west ramp.
    for (th_deg, s, radius, yaw, tilt), tiles in zip([(-58.0, 0.6, 0.85, 0.5, 0.42), (-128.0, 2.8, 0.6, 2.2, 0.55)], frag_tiles):
        th = math.radians(th_deg)
        d = brink_radius(th) + s
        build_fragment(m, CENTRE[0] + d * math.cos(th), CENTRE[1] + d * math.sin(th), radius, yaw, tilt, tiles, rng)
    stats["grains"] = len(specs)
    stats["fragments"] = 2
    bank = _object("ShoreBank", m, [sand_shader()])
    _set_attributes(bank, m)
    return bank, stats


def add_light():
    """The engine-drawn parts, added after the bake so the sand's baked occlusion never sees them."""
    light = bc.material("M_ShoreLight", (1.0, 0.83, 0.53), 0.5, emission=(1.0, 0.83, 0.53), emission_strength=1.5)
    build_light(light)


def _checks(bank, stats):
    top = max(v.co.z for v in bank.data.vertices)
    k._check(top <= SOLID_MAX_M, f"shore_piece: the bank reaches {top:.3f} m, above {SOLID_MAX_M} (the swim band)")
    stats["sand_top_m"] = round(top, 3)
    near = min(math.hypot(*_brink_point(math.tau * i / 360)) for i in range(360))
    k._check(near >= REACH_M + REACH_HALF_WIDTH + 0.4, f"shore_piece: the brink comes within {near:.2f} m of the pivot")
    for i in range(72):
        a = math.tau * i / 72
        g = ground(REACH_M * math.cos(a), REACH_M * math.sin(a))
        k._check(-2.6 <= g <= SAND_TOP_M, f"shore_piece: the shelf under the reach ring at {math.degrees(a):.0f} deg is {g:.2f} m")
    reach = bpy.data.objects["Reach"]
    radii = sorted({round(math.hypot(v.co.x, v.co.y), 4) for v in reach.data.vertices})
    mid = radii[len(radii) // 2]
    k._check(abs(mid - REACH_M) <= 0.01, f"shore_piece: reach mid radius {mid}")
    k._check(all(abs(v.co.z - REACH_Z) < 1e-5 for v in reach.data.vertices), "shore_piece: the reach ring is not flat at -0.05")
    for name in ("Glow", "Shaft"):
        for v in bpy.data.objects[name].data.vertices:
            if name == "Shaft" and math.hypot(v.co.x, v.co.y) < SHAFT_R_BOTTOM - 1e-4:
                continue                                 # only the shaft's foot sits on the sand
            lift = v.co.z - ground(v.co.x, v.co.y)
            k._check(abs(lift - LIGHT_LIFT_M) < 1e-4, f"shore_piece: {name} sits {lift:.3f} m above the sand at "
                     f"({v.co.x:.2f}, {v.co.y:.2f}), not {LIGHT_LIFT_M}")
    k._check(max(v.co.z for v in bpy.data.objects["Glow"].data.vertices) <= SOLID_MAX_M,
             "shore_piece: the glow rises into the swim band")
    tris = bc.triangle_count()
    k._check(tris <= BUDGET, f"shore_piece: {tris} triangles is over {BUDGET}")


def fields(stats, textures):
    return {
        "purpose": ("The pool's sea edge (ShoreLink, microscopic to aquatic): the sandbar at the pool's mouth that the "
                    "cell swims over into the open sea, seen from above at cell size 4, rising out of the deep toward its "
                    "crest in the north, with giant sand grains half sunk along its south brink, a shaft of shallow-water "
                    "light that pools on the sand where the cell swims out, and a light ring on the swim plane at the "
                    "reach. No collision: everything solid lies below the swim band."),
        "category": "landmark", "kind": "shore",
        "pivot": "the shore point on the swim plane (Godot y = 0); the shelf's crest lies about 1.8 m north (-Z)",
        "reach_radius_m": REACH_M,
        "sand_top_m": stats["sand_top_m"],
        "bottom_m": SKIRT_BOTTOM_M,
        "top_m": SHAFT_TOP_M,
        "engine_material": "res://assets/export/M_ShoreLight.tres",
        "light_nodes": ["Shaft", "Reach", "Glow"],
        "yaw_rule": "fixed",
        "authored_at_size": 4,
        "units": "1 m = 1 tm at the size shown",
        "dressings": [], "scale_range": [1.0, 1.0],
        "vertex_colors_attribute": "LightWeight",
        "light_weight": {"Shaft": [SHAFT_WEIGHT, 0.0, 0.0], "Reach": [RING_WEIGHT, 1.0, 0.0], "Glow": [GLOW_WEIGHT, 0.0, 1.0],
                         "meaning": "COLOR_0 raw: red the part's strength, green 1 the ring, blue 1 the glow (else the shaft)"},
        "grains": stats["grains"], "fragments": stats["fragments"],
        "texel_px_per_m": stats["texel_px_per_m"],
        "dependencies": [],
        "textures": textures,
    }


SHORE_LIGHT_TRES = """[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[sub_resource type="Shader" id="Shader_shore_light"]
code = "// The shore's light (shore_piece: the Shaft, the Reach ring and the Glow on the sand), additive and
// unlit, no fog. Written by tools/blender/make_shore_piece.py. COLOR_0 (LightWeight, raw) tells the
// parts apart: red is the part's strength, green 1 for the ring, blue 1 for the glow, else the shaft.
// glTF flips UV v, so v below runs as authored in Blender: up the shaft from the sand (0) to its top
// (1), across the ring from inside (0) to outside (1), out across the glow from its centre (0) to its
// rim (1). The shaft is brightest where it stands on the sand and fades upward and toward its
// silhouette; the ring is a soft band; the glow is even in the middle and soft at the rim. The gains
// are the Forward+ look; the view scales them for Compatibility (renderer_gain: x the shaft and the
// glow, y the ring) and pulses a duplicate's strength, never this file.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4({r}, {g}, {b}, 1.0);
uniform float shaft_gain = {shaft_gain};
uniform float ring_gain = {ring_gain};
uniform float shaft_fade = {shaft_fade};
uniform float shaft_edge = {shaft_edge};
uniform float near_top = {near_top};
uniform float glow_gain = {glow_gain};
uniform float glow_core = {glow_core};
uniform vec2 renderer_gain = vec2(1.0, 1.0);
uniform float strength = 1.0;

varying float near_side;

void vertex() {{
	// 1 on the shaft's side toward the camera, 0 on the far side: the near wall stands between the
	// camera and whatever is in the light, so it fades out from the sand up to near_top (v) and the
	// far wall carries the column.
	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec2 out_dir = VERTEX.xz;
	near_side = length(out_dir) > 0.0001 && length(eye.xz) > 0.0001
		? smoothstep(-0.2, 0.4, dot(normalize(out_dir), normalize(eye.xz))) : 0.0;
}}

void fragment() {{
	float v = 1.0 - UV.y;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rise = 1.0 - smoothstep(shaft_fade, 1.0, v);
	float near_cut = mix(1.0, 1.0 - smoothstep(0.0, near_top, v), near_side);
	float shaft = smoothstep(0.0, 0.05, v) * rise * near_cut * pow(facing, shaft_edge);
	float band = 1.0 - smoothstep(0.0, 1.0, abs(v * 2.0 - 1.0));
	float glow = 1.0 - smoothstep(glow_core, 1.0, v);
	vec2 g = vec2(shaft_gain, ring_gain) * renderer_gain;
	float part = mix(mix(shaft * g.x, band * g.y, COLOR.g), glow * glow_gain * renderer_gain.x, COLOR.b);
	ALBEDO = tint.rgb * (strength * COLOR.r * part);
}}
"

[resource]
resource_name = "M_ShoreLight"
render_priority = 0
shader = SubResource("Shader_shore_light")
shader_parameter/tint = Color({r}, {g}, {b}, 1)
shader_parameter/shaft_gain = {shaft_gain}
shader_parameter/ring_gain = {ring_gain}
shader_parameter/shaft_fade = {shaft_fade}
shader_parameter/shaft_edge = {shaft_edge}
shader_parameter/near_top = {near_top}
shader_parameter/glow_gain = {glow_gain}
shader_parameter/glow_core = {glow_core}
shader_parameter/renderer_gain = Vector2(1, 1)
shader_parameter/strength = 1.0
"""


def write_light_material():
    r, g, b = (round(int(LIGHT_TINT.lstrip("#")[i:i + 2], 16) / 255.0, 3) for i in (0, 2, 4))
    path = os.path.join(bc.ROOT, "assets", "export", "M_ShoreLight.tres")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(SHORE_LIGHT_TRES.format(r=r, g=g, b=b, shaft_gain=SHAFT_GAIN, ring_gain=RING_GAIN, shaft_fade=SHAFT_FADE,
                                        shaft_edge=SHAFT_EDGE, near_top=NEAR_TOP, glow_gain=GLOW_GAIN,
                                        glow_core=GLOW_CORE))
    print("wrote", path)


def map_light_material():
    """Points M_ShoreLight in the GLB's .import at the engine material (run after a Godot import)."""
    path = os.path.join(bc.ROOT, "assets", "export", f"{ASSET_ID}.glb.import")
    with open(path) as f:
        text = f.read()
    mapping = ('_subresources={\n"materials": {\n"M_ShoreLight": {\n"use_external/enabled": true,\n'
               '"use_external/fallback_path": "res://assets/export/M_ShoreLight.tres",\n'
               '"use_external/path": "res://assets/export/M_ShoreLight.tres"\n}\n}\n}')
    if "_subresources={\n" in text:
        text = re.sub(r"_subresources=\{.*?\n\}(?=\n|$)", mapping, text, flags=re.S)
    elif "_subresources={}" in text:
        text = text.replace("_subresources={}", mapping)
    else:
        raise RuntimeError(f"{path}: no _subresources line; run godot --headless --import first")
    with open(path, "w") as f:
        f.write(text)
    print("mapped M_ShoreLight -> res://assets/export/M_ShoreLight.tres in", os.path.basename(path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the shore piece (the sandbar, its light shaft and glow, the reach ring).")
    parser.add_argument("--rough", action="store_true", help="geometry and procedural shader only, saved to --out")
    parser.add_argument("--out", default=ROUGH_OUT, help="the rough .blend path")
    parser.add_argument("--root", default="", help="write the outputs under this folder instead of the repository")
    parser.add_argument("--import", dest="map_import", action="store_true", help="map M_ShoreLight in the .glb.import")
    parser.add_argument("--light", action="store_true", help="rewrite only M_ShoreLight.tres (light tuning, no bake)")
    args = parser.parse_args(argv)
    if args.root:
        bc.ROOT = os.path.abspath(args.root)
    if args.map_import:
        map_light_material()
        return
    if args.light:
        write_light_material()
        return
    bc.reset_scene()
    bank, stats = build()
    if args.rough:
        add_light()
        _checks(bank, stats)
        print("stats:", stats, "triangles:", bc.triangle_count())
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        if os.path.exists(args.out):
            os.remove(args.out)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.out), compress=True)
        print("saved rough", args.out)
        return
    textures = sf.bake_set([bank], "ShorePiece", TEXTURE_PX, normal=True)
    _strip_attributes(bank)
    add_light()
    _checks(bank, stats)
    print("stats:", stats, "triangles:", bc.triangle_count())
    write_light_material()
    record = bc.export(ASSET_ID, BUDGET, fields(stats, textures), review_state=REVIEW_STATE, generator=GENERATOR,
                       provenance=PROVENANCE)
    dims = record["dimensions_m"]
    print(f"{ASSET_ID}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
