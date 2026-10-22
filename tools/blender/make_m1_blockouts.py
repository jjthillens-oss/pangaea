"""Build the M1 step 2 blockout assets: the pool floor, three rocks, two foods and four cell parts.

For every asset id this writes (Bible section 16):
  assets/source/blender/<id>.blend   (editable source)
  assets/export/<id>.glb             (engine export)
  assets/records/<id>.json           (asset record: PROPOSED, a blockout, not visually approved)

Run with the pinned Blender (see docs/TOOLCHAIN.md):
  blender --background --python tools/blender/make_m1_blockouts.py -- [--only <id>[,<id>...]]
or with the bpy module:
  python tools/blender/make_m1_blockouts.py [--only <id>[,<id>...]]

Conventions (verified by tests/test_assets.gd after import):
  * 1 Blender meter = 1 Godot unit. Blender +Y becomes Godot -Z, Blender +Z becomes Godot +Y.
  * The swim plane is Blender z = 0 (Godot y = 0). The floor and the rocks have their pivot on it.
  * Parts have their origin at the attachment point and extend outward along Blender +Y.
  * Foods are one mesh object each, centred on the origin, so the pool can draw them with a MultiMesh.
The output is deterministic: fixed formulas and mathutils.noise at fixed offsets, no random numbers.
GLBs and records come out byte-identical on every run. A .blend also holds a few values that
Blender takes from the clock, a random seed or memory addresses and that scripts cannot set (each
mesh's face-set colour seed, material node identifiers and UI screen pointers), so it differs from
run to run in those bytes only; its geometry, objects and materials are the same.
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first, which provides mathutils)
from mathutils import Vector, noise  # noqa: E402

# Gameplay values the meshes are built to fit. They must match game/data/pool_m1.json
# (plankton.item_radius, carrion.item_radius, rock_footprint_radius_m). tests/test_assets.gd
# checks each export against its record and the food radii against the layout;
# tests/test_pool_layout.gd checks the rock footprint against the layout.
PLANKTON_ITEM_RADIUS = 0.18
CARRION_ITEM_RADIUS = 0.3
ROCK_FOOTPRINT_RADIUS = 1.0

# Pool floor. The cell's centre never passes r = 39 (hard limit 39.5 minus its 0.5 m radius) and
# the cell reaches 0.39 m below the swim plane, so the floor stays at or below -0.46 inside r = 39.
# The shelf runs past what the widest zoom (20 m) shows from a cell at the wall with full
# look-ahead: the top screen corners reach about r 64.7 on the shelf at 16:9.
FLOOR_SEGMENTS = 128
FLOOR_RINGS = ([float(r) for r in range(1, 37)]            # bowl, every metre
               + [36.5 + 0.5 * i for i in range(6)]        # 36.5 .. 39.0, approaching the wall
               + [39.25 + 0.25 * i for i in range(12)]     # 39.25 .. 42.0, the rim lip
               + [42.5 + 0.5 * i for i in range(6)]        # 42.5 .. 45.0, lip down to the shelf
               + [46.0, 47.0, 48.0, 50.0, 52.0, 55.0, 58.0, 62.0, 66.0])  # shelf past the edge of the view
FLOOR_BOWL = [(0.0, -1.6), (30.0, -1.0), (36.0, -0.6), (39.0, -0.46)]  # (radius, height), smooth
FLOOR_LIP = (42.0, 1.2)
FLOOR_SHELF = (45.0, 1.0)
FLOOR_BOWL_NOISE = 0.12   # gentle undulation, faded out between r = 26 and 33
FLOOR_RIM_NOISE = 0.10    # rocky rim, faded in from r = 40
# Floor colours (linear RGB, as in the other blockout materials), blended per vertex so silt patches and the stone band fade in over
# a metre or two instead of switching at a face edge of the radial grid.
FLOOR_SAND = (0.46, 0.40, 0.28)
FLOOR_SILT = (0.24, 0.22, 0.15)
FLOOR_STONE = (0.70, 0.68, 0.62)
FLOOR_SILT_EDGE = (0.12, 0.28)   # patch noise over which the sand turns to silt
FLOOR_STONE_EDGE_M = 0.6         # width of the fade at each side of the stone band
FLOOR_MOTTLE = 0.05              # gentle light and dark mottling of the sand, as a share of its colour

# Rocks: a squared-off, displaced icosphere, buried in the floor, top above the swim plane.
ROCK_TOP = 0.58
ROCK_BOTTOM = -2.0
ROCK_MAX_RADIUS = 1.05    # widest point of the swim band outline; collisions use ROCK_FOOTPRINT_RADIUS
ROCK_EQUATOR = -0.2       # height of the rock's widest ring, just under the swim plane
# The swim band is the cell's height around the swim plane (|z| <= 0.45). There the outline must
# stay within ROCK_OUTLINE of the collision circle at every azimuth, so the cell never stops short
# of a narrow side. Only ROCK_BAND_KEEP of the stretch, lobes and bumps shows in the band (as a
# power, so 0 is a round band); the full shape returns over ROCK_BAND_EASE above and below it.
ROCK_BAND = 0.45
ROCK_BAND_EASE = 0.35
ROCK_BAND_KEEP = 0.35
ROCK_OUTLINE = (0.85, 1.15)
ROCK_OUTLINE_HEIGHTS = [ROCK_BAND * (i / 4.0 - 1.0) for i in range(9)]  # -0.45 .. 0.45
ROCK_VARIANTS = {
    "rock_a": {"squareness": 0.6, "stretch": (1.0, 0.92), "lobes": (0.04, 0.0), "tilt": (0.06, 0.03),
               "bumps": 0.09, "offset": (3.1, -7.4, 1.7), "turn_deg": 0.0},
    "rock_b": {"squareness": 0.5, "stretch": (1.0, 0.86), "lobes": (0.0, 0.05), "tilt": (-0.04, 0.08),
               "bumps": 0.07, "offset": (-12.6, 4.2, 9.9), "turn_deg": 35.0},
    "rock_c": {"squareness": 0.7, "stretch": (1.0, 0.95), "lobes": (0.07, 0.03), "tilt": (0.1, -0.05),
               "bumps": 0.12, "offset": (21.3, 15.8, -6.5), "turn_deg": -20.0},
}

# Foods: the widest horizontal radius of each mesh (the item radius is the gameplay contact size).
PLANKTON_MESH_RADIUS = 0.185
PLANKTON_HALF_HEIGHT = 0.1
CARRION_MESH_RADIUS = 0.31

# Parts. PART_EMBED is how far each part sinks into the body behind its attachment point.
PART_EMBED = 0.03
FILTER_RIM_RADIUS = 0.12
JAW_HINGE = (0.075, 0.035)
FLAGELLUM_LENGTH = 0.75
EYE_DOME_RADIUS = 0.06

PART_ATTACHMENT = {
    "origin": "attachment point on the body surface",
    "outward_axis": "Blender +Y (Godot -Z)",
    "embed_m": PART_EMBED,
}


def _check(condition, message):
    if not condition:
        raise RuntimeError(message)


def _horizontal_radius(points):
    return max(math.hypot(p.x, p.y) for p in points)


# --- Pool floor -------------------------------------------------------------------------------


def _bowl_tangents(points):
    """Monotone cubic (Fritsch-Carlson) tangents, flat at both ends."""
    m = [0.0] * len(points)
    for i in range(1, len(points) - 1):
        h0 = points[i][0] - points[i - 1][0]
        h1 = points[i + 1][0] - points[i][0]
        d0 = (points[i][1] - points[i - 1][1]) / h0
        d1 = (points[i + 1][1] - points[i][1]) / h1
        if d0 * d1 > 0.0:
            w1, w2 = 2.0 * h1 + h0, h1 + 2.0 * h0
            m[i] = (w1 + w2) / (w1 / d0 + w2 / d1)
    return m


_BOWL_M = _bowl_tangents(FLOOR_BOWL)


def floor_profile(r):
    """Height of the floor at radius r before undulation."""
    if r <= FLOOR_BOWL[-1][0]:
        for i in range(len(FLOOR_BOWL) - 1):
            (r0, h0), (r1, h1) = FLOOR_BOWL[i], FLOOR_BOWL[i + 1]
            if r <= r1:
                dx = r1 - r0
                t = (r - r0) / dx
                t2, t3 = t * t, t * t * t
                return ((2 * t3 - 3 * t2 + 1) * h0 + (t3 - 2 * t2 + t) * dx * _BOWL_M[i]
                        + (-2 * t3 + 3 * t2) * h1 + (t3 - t2) * dx * _BOWL_M[i + 1])
    r_wall, h_wall = FLOOR_BOWL[-1]
    if r <= FLOOR_LIP[0]:
        return h_wall + (FLOOR_LIP[1] - h_wall) * bc.smoothstep((r - r_wall) / (FLOOR_LIP[0] - r_wall))
    if r <= FLOOR_SHELF[0]:
        return FLOOR_LIP[1] + (FLOOR_SHELF[1] - FLOOR_LIP[1]) * bc.smoothstep((r - FLOOR_LIP[0]) / (FLOOR_SHELF[0] - FLOOR_LIP[0]))
    return FLOOR_SHELF[1]


def floor_height(x, y):
    r = math.hypot(x, y)
    bowl = 1.0 - bc.smoothstep((r - 26.0) / 7.0)
    rim = bc.smoothstep((r - 40.0) / 1.5)
    h = floor_profile(r)
    h += FLOOR_BOWL_NOISE * bowl * noise.noise(Vector((x * 0.08, y * 0.08, 0.37)))
    h += 0.03 * bowl * noise.noise(Vector((x * 0.25 + 11.3, y * 0.25 - 4.1, 2.9)))
    h += FLOOR_RIM_NOISE * rim * noise.noise(Vector((x * 0.15 + 5.7, y * 0.15 + 3.3, 8.1)))
    return h


def _mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def floor_color(x, y):
    """Linear RGB of the floor at (x, y): sand, soft silt patches and a silty centre, the stone band."""
    r = math.hypot(x, y)
    a = math.atan2(y, x)
    around = Vector((math.cos(a) * 3.0, math.sin(a) * 3.0, 0.0))
    # The patch field: broad noise for where the patches are, finer noise to make their edges organic.
    # Every noise here changes slowly next to the grid spacing (1 m rings, up to 1.8 m apart around
    # the bowl), so the blend never shows the triangles.
    patch = (noise.noise(Vector((x * 0.06 - 7.7, y * 0.06 + 1.9, 4.4)))
             + 0.08 * noise.noise(Vector((x * 0.2 + 2.1, y * 0.2 - 5.3, 7.9))))
    silt = bc.smoothstep((patch - FLOOR_SILT_EDGE[0]) / (FLOOR_SILT_EDGE[1] - FLOOR_SILT_EDGE[0]))
    centre = 7.0 + 2.0 * noise.noise(around + Vector((0.0, 9.0, 3.0)))
    silt = max(silt, 1.0 - bc.smoothstep((r - centre + 1.5) / 3.0))
    mottle = 1.0 + FLOOR_MOTTLE * noise.noise(Vector((x * 0.16 + 3.3, y * 0.16 + 8.8, 1.7)))
    color = tuple(c * mottle for c in _mix(FLOOR_SAND, FLOOR_SILT, silt))
    stone_in = 38.9 + 0.35 * noise.noise(around + Vector((1.3, 0.0, 6.2)))
    stone_out = 45.5 + 1.2 * noise.noise(around + Vector((-4.0, 2.2, 1.1)))
    edge = FLOOR_STONE_EDGE_M
    stone = bc.smoothstep((r - stone_in + edge / 2.0) / edge) * (1.0 - bc.smoothstep((r - stone_out + edge / 2.0) / edge))
    return _mix(color, FLOOR_STONE, stone)


def build_pool_floor():
    floor_mat = bc.material("M_PoolFloor", (1.0, 1.0, 1.0), 0.9, vertex_colors="FloorColor")
    verts = [(0.0, 0.0, floor_height(0.0, 0.0))]
    for r in FLOOR_RINGS:
        for j in range(FLOOR_SEGMENTS):
            a = 2.0 * math.pi * j / FLOOR_SEGMENTS
            x, y = r * math.cos(a), r * math.sin(a)
            verts.append((x, y, floor_height(x, y)))
    # Winding is counter-clockwise seen from above, so every face points up (+Z).
    faces = []
    ring = lambda i, j: 1 + i * FLOOR_SEGMENTS + j % FLOOR_SEGMENTS  # noqa: E731
    for j in range(FLOOR_SEGMENTS):
        faces.append((0, ring(0, j), ring(0, j + 1)))
    for i in range(len(FLOOR_RINGS) - 1):
        for j in range(FLOOR_SEGMENTS):
            faces.append((ring(i, j), ring(i + 1, j), ring(i + 1, j + 1), ring(i, j + 1)))
    # Colours per vertex: pale stone on the lip, silt patches and a silty deep centre, sand elsewhere.
    colors = [floor_color(v[0], v[1]) for v in verts]
    edge = FLOOR_RINGS[-1]
    floor = bc.mesh_object("PoolFloor", verts, faces, [floor_mat], fix_normals=False,
                           uv=lambda co: (0.5 + co.x / (2.0 * edge), 0.5 + co.y / (2.0 * edge)),
                           vertex_colors=("FloorColor", colors))
    _check(all(p.normal.z > 0.0 for p in floor.data.polygons), "pool_floor: every face points up")
    inner = [v for v in verts if math.hypot(v[0], v[1]) <= 39.0 + 1e-6]
    rim = [v for v in verts if 41.5 <= math.hypot(v[0], v[1]) <= 43.0]
    _check(max(v[2] for v in inner) <= -0.45, "pool_floor: at or below -0.45 m inside r = 39")
    _check(min(v[2] for v in rim) > 0.8, "pool_floor: rim above +0.8 m over r 41.5-43")
    return {
        "purpose": "M1 step 2 tide pool floor: a bowl under the swim plane, a pale stone rim lip and a shelf out past the edge of the camera view.",
        "category": "floor",
        "revision": 2,
        "dependencies": ["assets/export/M_PoolFloor.tres"],
        "vertex_colors_attribute": "FloorColor",
        "pivot": "pool centre on the swim plane (Godot y = 0)",
        "radius_m": FLOOR_RINGS[-1],
        "vertex_colors": {
            "attribute": "FloorColor",
            "encoding": "sRGB-encoded in COLOR_0; the engine material sets vertex_color_is_srgb (assets/export/M_PoolFloor.tres)",
            "note": "Sand with soft silt patches and a silty centre, and a pale stone band on the rim lip, blended per vertex.",
            "sand": list(FLOOR_SAND),
            "silt": list(FLOOR_SILT),
            "stone": list(FLOOR_STONE),
        },
        "profile_m": {
            "bowl": [list(p) for p in FLOOR_BOWL],
            "lip": list(FLOOR_LIP),
            "shelf": list(FLOOR_SHELF),
            "max_height_inside_r39": round(max(v[2] for v in inner), 3),
            "min_height_r41_5_to_43": round(min(v[2] for v in rim), 3),
        },
    }


# --- Rocks ------------------------------------------------------------------------------------


def band_outline(pts, faces, heights, bins=360):
    """The rock's outline seen from above over a height band: for each azimuth bin (1 degree),
    the farthest point of any horizontal section of the triangles at `heights`. 0 where no section
    reaches that azimuth. Sections are sampled densely along each cut, not just at vertices."""
    best = [0.0] * bins
    for f in faces:
        for h in heights:
            cut = []
            for a, b in ((f[0], f[1]), (f[1], f[2]), (f[2], f[0])):
                pa, pb = pts[a], pts[b]
                if (pa.z - h) * (pb.z - h) <= 0.0 and pa.z != pb.z:
                    cut.append(pa.lerp(pb, (h - pa.z) / (pb.z - pa.z)))
            if len(cut) < 2:
                continue
            p, q = cut[0], cut[1]
            span = abs(math.degrees(math.atan2(p.x * q.y - p.y * q.x, p.x * q.x + p.y * q.y)))
            steps = int(span * 4.0) + 1
            for k in range(steps + 1):
                c = p.lerp(q, k / steps)
                i = int(math.degrees(math.atan2(c.y, c.x)) % 360.0 * bins / 360.0) % bins
                best[i] = max(best[i], math.hypot(c.x, c.y))
    return best


def build_rock(asset_id):
    v = ROCK_VARIANTS[asset_id]
    stone = bc.material("M_RockStone", (0.30, 0.25, 0.20), 0.9)
    unit, faces = bc.icosphere(4)
    e = v["squareness"]
    offset = Vector(v["offset"])
    turn = math.radians(v["turn_deg"])
    pts, profile, shape = [], [], []
    for co in unit:
        n = Vector(co).normalized()
        az = math.atan2(n.y, n.x)
        # Squared-off profile: a rounded cylinder rather than a ball, so the rock is about as wide
        # at the swim plane as its widest point.
        rh = math.sqrt(max(0.0, 1.0 - n.z * n.z)) ** e
        sz = math.copysign(abs(n.z) ** e, n.z)
        lobe = 1.0 + v["lobes"][0] * math.cos(2.0 * az + 0.7) + v["lobes"][1] * math.cos(3.0 * az - 1.3)
        bump = 1.0 + v["bumps"] * noise.noise(n * 1.6 + offset) + 0.035 * noise.noise(n * 4.5 + offset * 0.5)
        x = rh * v["stretch"][0] * math.cos(az) * lobe * bump
        y = rh * v["stretch"][1] * math.sin(az) * lobe * bump
        z = sz * bump
        if z > 0.0:
            z += z * (v["tilt"][0] * x + v["tilt"][1] * y)
        pts.append(Vector((x * math.cos(turn) - y * math.sin(turn), x * math.sin(turn) + y * math.cos(turn), z)))
        profile.append(rh)
        shape.append(math.hypot(x, y) / rh if rh > 1e-6 else 1.0)
    # Fit the height exactly: top at ROCK_TOP, bottom at ROCK_BOTTOM, widest ring at ROCK_EQUATOR.
    z_top = max(p.z for p in pts)
    z_bottom = min(p.z for p in pts)
    mid = ROCK_EQUATOR
    for p in pts:
        p.z = mid + (p.z / z_top) * (ROCK_TOP - mid) if p.z > 0.0 else mid + (p.z / -z_bottom) * (mid - ROCK_BOTTOM)
    # Calm the horizontal shape in the swim band: keep its direction, compress its variation.
    for p, rh, h in zip(pts, profile, shape):
        band = 1.0 - bc.smoothstep((abs(p.z) - ROCK_BAND) / ROCK_BAND_EASE)
        r = rh * h ** (1.0 - band * (1.0 - ROCK_BAND_KEEP))
        if p.x != 0.0 or p.y != 0.0:
            p.xy = Vector((p.x, p.y)).normalized() * r
    # Fit the width: the swim band outline's widest point at ROCK_MAX_RADIUS.
    widest = max(band_outline(pts, faces, ROCK_OUTLINE_HEIGHTS))
    for p in pts:
        p.x *= ROCK_MAX_RADIUS / widest
        p.y *= ROCK_MAX_RADIUS / widest
    bc.mesh_object("Rock", pts, faces, [stone],
                   uv=lambda co: (0.5 + 0.5 * math.atan2(co.y, co.x) / math.pi, (co.z - ROCK_BOTTOM) / (ROCK_TOP - ROCK_BOTTOM)))
    outline = band_outline(pts, faces, ROCK_OUTLINE_HEIGHTS)
    at_plane = band_outline(pts, faces, [0.0])
    lo, hi = (k * ROCK_FOOTPRINT_RADIUS for k in ROCK_OUTLINE)
    _check(abs(_horizontal_radius(pts) - ROCK_FOOTPRINT_RADIUS) <= 0.15 * ROCK_FOOTPRINT_RADIUS, f"{asset_id}: footprint")
    _check(lo <= min(outline) and max(outline) <= hi,
           f"{asset_id}: swim band outline {min(outline):.3f}-{max(outline):.3f} m, within {lo}-{hi} m at every azimuth")
    _check(lo <= min(at_plane) and max(at_plane) <= hi,
           f"{asset_id}: swim plane section {min(at_plane):.3f}-{max(at_plane):.3f} m, within {lo}-{hi} m at every azimuth")
    return {
        "purpose": "M1 step 2 pool rock, an obstacle the cell slides around. Placed by game/data/pool_m1.json with yaw and uniform scale.",
        "category": "rock",
        "revision": 2,
        "pivot": "centre of the footprint on the swim plane (Godot y = 0)",
        "footprint_radius_m": ROCK_FOOTPRINT_RADIUS,
        "max_radius_m": round(_horizontal_radius(pts), 3),
        "swim_band_radius_m": round(max(outline), 3),
        "swim_band_min_radius_m": round(min(outline), 3),
        "swim_plane_radius_m": [round(min(at_plane), 3), round(max(at_plane), 3)],
        "top_m": ROCK_TOP,
        "bottom_m": ROCK_BOTTOM,
    }


# --- Foods ------------------------------------------------------------------------------------


def build_plankton():
    glob = bc.material("M_Plankton", (0.32, 0.72, 0.26), 0.4, emission=(0.35, 0.85, 0.3), emission_strength=0.35)
    segments = 32
    lats = [60.0, 38.0, 14.0, -14.0, -38.0, -60.0]
    offset = Vector((-2.7, 8.3, 5.1))
    pts = [Vector((0.0, 0.0, 1.0))]
    for lat in lats:
        c, s = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        for j in range(segments):
            a = 2.0 * math.pi * j / segments
            n = Vector((c * math.cos(a), c * math.sin(a), s))
            # A centric diatom: a soft pillbox with eight shallow radial lobes, slightly lumpy.
            rib = 1.0 + 0.04 * math.cos(8.0 * a) * c * c
            lump = 1.0 + 0.05 * noise.noise(n * 2.2 + offset)
            h = c ** 0.75 * rib * lump
            pts.append(Vector((h * math.cos(a), h * math.sin(a), math.copysign(abs(s) ** 0.85, s) * lump)))
    pts.append(Vector((0.0, 0.0, -1.0)))
    widest = _horizontal_radius(pts)
    for p in pts:
        p.x *= PLANKTON_MESH_RADIUS / widest
        p.y *= PLANKTON_MESH_RADIUS / widest
        p.z *= PLANKTON_HALF_HEIGHT
    faces = []
    ring = lambda i, j: 1 + i * segments + j % segments  # noqa: E731
    for j in range(segments):
        faces.append((0, ring(0, j), ring(0, j + 1)))
    for i in range(len(lats) - 1):
        for j in range(segments):
            faces.append((ring(i, j), ring(i + 1, j), ring(i + 1, j + 1), ring(i, j + 1)))
    bottom = len(pts) - 1
    for j in range(segments):
        faces.append((bottom, ring(len(lats) - 1, j + 1), ring(len(lats) - 1, j)))
    bc.mesh_object("Plankton", pts, faces, [glob])
    radius = _horizontal_radius(pts)
    _check(abs(radius - PLANKTON_ITEM_RADIUS) <= 0.2 * PLANKTON_ITEM_RADIUS, "plankton: mesh radius fits the item radius")
    return {
        "purpose": "M1 step 2 plankton food item, drawn many times with one MultiMesh.",
        "category": "food",
        "food_kind": "plant",
        "pivot": "centre of the item",
        "item_radius_m": PLANKTON_ITEM_RADIUS,
        "mesh_radius_m": round(radius, 3),
    }


def build_carrion():
    flesh = bc.material("M_CarrionFlesh", (0.25, 0.07, 0.05), 0.75)
    streak = bc.material("M_CarrionStreak", (0.86, 0.78, 0.66), 0.6)
    unit, faces = bc.icosphere(3)
    offset = Vector((4.4, -9.1, 13.7))
    pts = []
    for co in unit:
        n = Vector(co).normalized()
        chunk = 1.0 + 0.22 * noise.noise(n * 1.8 + offset) + 0.08 * noise.noise(n * 4.2 - offset)
        p = Vector((n.x * 0.30, n.y * 0.24, n.z * 0.17)) * chunk
        p.z = max(p.z, -0.11)  # flat underside where it rests
        pts.append(p)
    widest = _horizontal_radius(pts)
    for p in pts:
        p.x *= CARRION_MESH_RADIUS / widest
        p.y *= CARRION_MESH_RADIUS / widest
    # A pale streak of sinew across the top, so the chunk reads by shape and marking, not colour alone.
    face_materials = []
    for f in faces:
        c = sum((pts[k] for k in f), Vector()) / len(f)
        across = 0.6 * c.x - 0.8 * c.y + 0.03 * noise.noise(c * 9.0 + offset)
        face_materials.append(1 if abs(across - 0.02) < 0.04 and c.z > 0.0 else 0)
    bc.mesh_object("Carrion", pts, faces, [flesh, streak], face_materials, smooth=False)
    radius = _horizontal_radius(pts)
    _check(abs(radius - CARRION_ITEM_RADIUS) <= 0.2 * CARRION_ITEM_RADIUS, "carrion: mesh radius fits the item radius")
    _check(0 < sum(face_materials) < len(faces) // 4, "carrion: has a streak")
    return {
        "purpose": "M1 step 2 carrion food item (static, sinks, no drift), drawn with one MultiMesh.",
        "category": "food",
        "food_kind": "meat",
        "pivot": "centre of the item",
        "item_radius_m": CARRION_ITEM_RADIUS,
        "mesh_radius_m": round(radius, 3),
    }


# --- Parts ------------------------------------------------------------------------------------


def _part_fields(part_type, purpose):
    pts = bc.world_vertices()
    y_min = min(p.y for p in pts)
    y_max = max(p.y for p in pts)
    _check(y_min >= -0.05, f"{part_type}: sinks at most 0.05 m behind its attachment point")
    _check((y_min + y_max) / 2.0 > 0.05, f"{part_type}: extends outward along +Y")
    return {"purpose": purpose, "category": "part", "part_type": part_type, "attachment": dict(PART_ATTACHMENT)}


def build_mouth_filter():
    lip = bc.material("M_FilterLip", (0.78, 0.86, 0.52), 0.45)
    throat = bc.material("M_FilterThroat", (0.10, 0.16, 0.10), 0.6)
    rim = FILTER_RIM_RADIUS
    # A thick-walled funnel: outside from the base to the rim, then the inside down to the throat.
    profile = [(-PART_EMBED, 0.0), (-PART_EMBED, 0.07), (0.02, 0.075), (0.06, 0.088), (0.095, 0.104),
               (0.118, rim), (0.13, rim - 0.004), (0.127, rim - 0.016), (0.10, 0.096), (0.065, 0.068),
               (0.04, 0.038), (0.032, 0.0)]
    verts, faces, bands = bc.revolve(profile, 28)
    face_materials = [1 if b >= 7 else 0 for b in bands]
    # The fringe: fourteen short tapered cilia leaning out from the rim.
    lean = math.radians(42.0)
    for k in range(14):
        a = 2.0 * math.pi * (k + 0.5) / 14
        radial = Vector((math.cos(a), 0.0, math.sin(a)))
        out = Vector((0.0, math.cos(lean), 0.0)) + radial * math.sin(lean)
        base = Vector((0.0, 0.122, 0.0)) + radial * (rim - 0.002)
        path = [base + out * (0.05 * i / 3) + radial * (0.006 * (i / 3) ** 2) for i in range(4)]
        tv, tf = bc.tube(path, [0.012, 0.009, 0.005, 0.0], 5)
        added = bc.append(verts, faces, tv, tf)
        face_materials.extend(0 for _ in added)
    bc.mesh_object("MouthFilter", verts, faces, [lip, throat], face_materials)
    return _part_fields("mouth_filter", "M1 step 2 filter mouth part (eats plankton): a fringed funnel.")


def _bezier(p0, p1, p2, t):
    return p0 * ((1 - t) ** 2) + p1 * (2 * (1 - t) * t) + p2 * (t * t)


def build_mouth_jaw():
    collar = bc.material("M_JawCollar", (0.30, 0.12, 0.09), 0.55)
    chitin = bc.material("M_JawMandible", (0.06, 0.045, 0.04), 0.3)
    profile = [(-PART_EMBED, 0.0), (-PART_EMBED, 0.095), (0.0, 0.1), (0.03, 0.09), (0.05, 0.065),
               (0.058, 0.035), (0.06, 0.0)]
    verts, faces, bands = bc.revolve(profile, 20)
    base = bc.mesh_object("JawBase", verts, faces, [collar, chitin], [1 if b >= 4 else 0 for b in bands])
    # Two curved mandibles, each with its origin on its hinge so a bite can be animated later.
    for side, sx in (("L", -1.0), ("R", 1.0)):
        p0 = Vector((0.0, 0.0, 0.0))
        p1 = Vector((sx * 0.13, 0.10, -0.005))
        p2 = Vector((-sx * 0.035, 0.20, 0.0))
        steps = 11
        path = [_bezier(p0, p1, p2, i / steps) for i in range(steps + 1)]
        radii = [0.03 * (1.0 - i / steps) ** 0.8 for i in range(steps + 1)]
        tv, tf = bc.tube(path, radii, 7, squash=0.65)
        bc.mesh_object(f"Mandible_{side}", tv, tf, [chitin], parent=base,
                       location=(sx * JAW_HINGE[0], JAW_HINGE[1], 0.0))
    return _part_fields("mouth_jaw", "M1 step 2 jaw mouth part (eats carrion): twin dark mandibles on a collar.")


def build_flagellum():
    whip = bc.material("M_PartFlagellum", (0.55, 0.85, 0.72), 0.4)
    steps = 24
    total = FLAGELLUM_LENGTH + PART_EMBED
    path, radii = [], []
    for i in range(steps + 1):
        u = i / steps
        y = -PART_EMBED + total * u
        # One full S: the sway grows toward the tip, like a whip.
        x = 0.075 * math.sin(2.0 * math.pi * u) * (0.35 + 0.65 * u)
        path.append(Vector((x, y, 0.0)))
        radii.append(0.006 + 0.04 * (1.0 - u) ** 1.1 + 0.012 * (1.0 - bc.smoothstep(u / 0.08)))
    radii[-1] = 0.0
    verts, faces = bc.tube(path, radii, 8)
    bc.mesh_object("Flagellum", verts, faces, [whip])
    return _part_fields("flagellum", "M1 step 2 flagellum part (propulsion): a tapered S-curve whip.")


def build_eye_spot():
    stalk = bc.material("M_EyeSpotStalk", (0.18, 0.62, 0.52), 0.35)
    pigment = bc.material("M_EyeSpotPigment", (0.95, 0.45, 0.08), 0.35, emission=(0.9, 0.35, 0.05), emission_strength=0.3)
    lens = bc.material("M_EyeSpotLens", (0.04, 0.03, 0.03), 0.15)
    centre, depth = 0.085, 0.065
    dome = [(centre + depth * math.sin(math.radians(t)), EYE_DOME_RADIUS * math.cos(math.radians(t)))
            for t in (-35.0, -10.0, 15.0, 40.0, 62.0, 78.0)]
    profile = [(-PART_EMBED, 0.0), (-PART_EMBED, 0.034), (0.0, 0.03), (0.025, 0.031)] + dome + [(centre + depth, 0.0)]
    verts, faces, bands = bc.revolve(profile, 16)
    # Stalk in membrane green, the dome in orange pigment, a dark lens at the front.
    face_materials = [0 if b <= 2 else (2 if b >= 8 else 1) for b in bands]
    bc.mesh_object("EyeSpot", verts, faces, [stalk, pigment, lens], face_materials)
    return _part_fields("eye_spot", "M1 step 2 eye spot part (sight): an orange pigment dome with a dark lens on a short stalk.")


# --- Driver -----------------------------------------------------------------------------------

# asset id -> (builder, triangle budget)
ASSETS = {
    "pool_floor": (build_pool_floor, 20000),
    "rock_a": (lambda: build_rock("rock_a"), 1300),
    "rock_b": (lambda: build_rock("rock_b"), 1300),
    "rock_c": (lambda: build_rock("rock_c"), 1300),
    "plankton": (build_plankton, 400),
    "carrion": (build_carrion, 400),
    "part_mouth_filter": (build_mouth_filter, 1500),
    "part_mouth_jaw": (build_mouth_jaw, 1500),
    "part_flagellum": (build_flagellum, 1500),
    "part_eye_spot": (build_eye_spot, 1500),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the M1 step 2 blockout assets.")
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
        record = bc.export(asset_id, budget, fields)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
