"""The Aquatic stage's sea floor (PROPOSED, docs/stages/aquatic-plan.md section 8).

- aquatic_seafloor: one strip of sea floor from the sunlit shore down the reef slope into the deep, 112 m across and
  440 m long. Its centre line follows the floor profile in game/data/aquatic/aquatic_rules.json ("world.floor"), the
  one source the sim's floor_y() also reads, so the fish never swims into the ground; the sides rise into rock walls
  past |x| = 36 m (AquaticSim.wall_rise, the same formula), and the shore end rises out of the water as a beach.
  Relief inside the swim lane stays under RELIEF_M, inside the sim's floor margin. Drawn with the external
  M_AquaticSeafloor.tres (assets/export/shaders/aquatic_seafloor.gdshader): sand ripples on the flats, dark rock on
  the slopes, both shaded deeper with depth, in world space, with a baked seamless sand tile and its normal map (TILE_M across).

- aquatic_nest (aquatic-r2): the spawning nest, the stage's home landmark (Bible section 6: "nests or spawning sites
  create recognizable locations"). A raised mound of shell gravel with a scooped dish, a ring of rounded reef stones
  crusted with coral polyps, six clutches of cartilage egg capsules (Clutch_1..Clutch_6, separate nodes the world shows
  one per generation hatched) and a Beacon: a stacked reef-stone pillar with amber ribbon fronds, its own node with
  its pivot at its foot, so the world can stand it upright when it tilts the nest to the slope.
- aquatic_plinth (aquatic-r2): the fin and tail editor's reef-stone plinth, a unit-radius pad (the pivot at the
  centre of its top face) the editor scales uniformly, so the polyps on its rim keep their shape.

Axes: Blender +Y forward is Godot -Z, so the shore (Godot z = +34) is at Blender y = -34 and the deep at +380.

Run: python tools/blender/make_aquatic_world.py --only <id>[,<id>...]   (bpy 5.2.2; never without --only once the sea
floor is committed, so its binaries are not regenerated)
The sea floor: then godot --headless --import, python tools/blender/make_aquatic_world.py --import, and --import again.
The nest and the plinth carry baked textures and need only godot --headless --import.
"""
import argparse
import json
import math
import os
import random
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import make_creature_parts as cp  # noqa: E402  (read-only helpers: _tube, _up)
import make_m1_production as mp  # noqa: E402  (read-only helpers: _check)
import make_membranes as mm  # noqa: E402
import numpy as np  # noqa: E402
import surfacing as sf  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

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


# --- Shared pieces for the nest and the plinth (aquatic-r2) ---------------------------------------------------------

PROVENANCE_BAKED = ("Authored procedurally in Blender by tools/blender/make_aquatic_world.py; no external or generated "
                    "meshes. Textures baked in Blender from procedural shaders (no image sources).")


def _cells(sh, scale, vector=None):
    """Voronoi cells: (distance to the nearest cell edge, a random 0..1 value per cell), the two sharing their cells."""
    vec = vector if vector is not None else sh.pos
    edge = sh.node("ShaderNodeTexVoronoi", feature="DISTANCE_TO_EDGE")
    tone = sh.node("ShaderNodeTexVoronoi", feature="F1")
    for n in (edge, tone):
        sh.link(vec, n.inputs["Vector"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = 0.9
    sep = sh.node("ShaderNodeSeparateColor")
    sh.link(tone.outputs["Color"], sep.inputs["Color"])
    return edge.outputs["Distance"], sep.outputs["Red"]


def _warped(sh, scale, amount):
    """Object position pushed about by a noise's colour (+-amount/2 m), so Voronoi cells lose their straight edges."""
    n = sh.node("ShaderNodeTexNoise")
    sh.link(sh.pos, n.inputs["Vector"])
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = 2.0
    shift = sh.vmath("MULTIPLY", sh.vmath("SUBTRACT", n.outputs["Color"], (0.5, 0.5, 0.5)), (amount, amount, amount))
    return sh.vmath("ADD", sh.pos, shift)


def _up_facing(sh):
    """The object-space normal's Z: 1 on a top, 0 on a side, -1 underneath."""
    sep = sh.node("ShaderNodeSeparateXYZ")
    sh.link(sh._coords.outputs["Normal"], sep.inputs["Vector"])
    return sep.outputs["Z"]


def _radial(sh):
    return sh.vmath("LENGTH", sh.vmath("MULTIPLY", sh.pos, (1.0, 1.0, 0.0)))


def _rock(radii, seed, subdivisions=3, flat_below=-0.35, rough=0.16):
    """A rounded reef stone: an icosphere pushed out and in by two octaves of noise (seeded), its underside flattened
    below `flat_below` (it is buried), scaled to `radii`. Returns verts (about its centre), faces, and the surface
    point function (a unit direction -> the displaced surface point) for placing polyps on it."""
    unit, faces = bc.icosphere(subdivisions)
    off = Vector((seed * 3.17, seed * 1.91, seed * 2.53))

    def surface(d):
        d = Vector(d).normalized()
        k = 1.0 + rough * noise.noise(d * 1.3 + off) + 0.06 * noise.noise(d * 3.4 + off * 1.7)
        p = d * k
        if p.z < flat_below:
            p.z = flat_below + (p.z - flat_below) * 0.25
        return Vector((p.x * radii[0], p.y * radii[1], p.z * radii[2]))

    return [tuple(surface(co)) for co in unit], faces, surface


def _polyp(base, normal, height, radius, sides=6):
    """A coral polyp: a short domed knob standing on `base` along `normal`, sunk a little into the surface."""
    n = Vector(normal).normalized()
    path = [base - n * radius * 0.6, base + n * height * 0.45, base + n * height * 0.85, base + n * height]
    radii = [radius, radius * 0.95, radius * 0.7, 0.0]
    v, f, _ = cp._tube(path, lambda i, a: radii[i], sides)
    return v, f


def _place(verts, rot, at):
    """verts rotated by the matrix `rot` and moved to `at`."""
    return [tuple(rot @ Vector(v) + at) for v in verts]


def _unwrap_weighted(objs_weights, margin=0.008, angle=60.0):
    """sf.unwrap, with a texel-density weight per object: small pieces seen close (the eggs, the polyps) get more of
    the shared texture than the big mound, whose gravel reads at a lower density."""
    objs = [o for o, _ in objs_weights]
    sf.select(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj, weight in objs_weights:
        if weight != 1.0:
            data = obj.data.uv_layers.active.data
            uv = np.empty(len(data) * 2, dtype=np.float32)
            data.foreach_get("uv", uv)
            data.foreach_set("uv", uv * weight)
    sf.select(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=margin, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


ISOLATE_LIFT = 400.0    # metres an isolated piece is moved up while the set bakes, out of every other piece's AO


def _bake_pieces(pieces, texture, size, isolate=()):
    """Like cp._bake for several objects: each (obj, tolerance m, texel weight) is reduced within its own tolerance
    (collapse decimation), unwrapped into one shared layout with its texel weight, and every piece's procedural
    shading is baked in full colour into one texture set and one glTF-safe material M_<texture>. Pieces in `isolate`
    (with their full-detail copies) bake away from the rest, so a piece the game may hide (a clutch of eggs) leaves no
    baked occlusion on what it lies on. Returns the record's textures and reduction."""
    before = after = 0
    highs = {}
    for obj, tol, _ in pieces:
        b, a, high = sf.reduce(obj, tol)
        before, after = before + b, after + a
        if a == b:
            sf.drop_highs([high])
            high = None
        highs[obj.name] = high
    _unwrap_weighted([(o, w) for o, _, w in pieces])
    lifted = [o for o in isolate] + [highs[o.name] for o in isolate if highs.get(o.name) is not None]
    for o in lifted:
        o.location.z += ISOLATE_LIFT
    bpy.context.view_layer.update()
    textures = sf.bake_set([o for o, _, _ in pieces], texture, size, normal=True, highs=highs)
    for o in lifted:
        o.location.z -= ISOLATE_LIFT
    bpy.context.view_layer.update()
    sf.drop_highs(highs.values())
    return {"textures": textures,
            "reduction": {"method": "Blender collapse decimation within a surface tolerance per piece; full-detail shading baked to the normal map",
                          "tolerance_m": {o.name: t for o, t, _ in pieces}, "triangles_before": before, "triangles_after": after}}


# --- The nest (aquatic-r2) ------------------------------------------------------------------------------------------

NEST_R = 4.6            # footprint radius (rules.world.nest.radius is 5)
NEST_SKIRT = 0.55       # the skirt reaches this far under the pivot: the world tilts the nest to the 0.2 m/m slope, and
                        # the sea floor's own relief there is within 0.11 m of the profile (measured on aquatic_seafloor)
# The mound's top as (r, z) from the centre out: a dish raised 0.27 m over the pivot (so the floor's relief never
# shows through where the eggs lie), a crest at r 3.5, and the foot meeting the floor at r 4.5.
NEST_PROFILE = [(0.0, 0.27), (0.7, 0.272), (1.3, 0.28), (1.9, 0.302), (2.4, 0.345), (2.8, 0.405), (3.15, 0.46),
                (3.5, 0.5), (3.85, 0.48), (4.1, 0.39), (4.32, 0.23), (4.48, 0.06), (4.56, -0.12), (NEST_R, -NEST_SKIRT)]
NEST_SEGMENTS = 72
RIM_MIN_R = 3.6         # rim stones stand at r >= 3.6 ...
RIM_MAX_Z = 0.9         # ... and at most 0.9 m over the pivot, so the spawn (r 3, 2 m up) and the kin stay clear
RIM_STONES = 16
BEACON_DEG = 125.0      # the beacon on the rim, front-left (-x, +y in Blender; -x, -z in Godot): in the spawn frame
BEACON_R = 3.75
BEACON_MAX_Z = 6.0
# The six clutches: (angle deg, r) on the dish. Clutch_1 lies in front of the spawn, in its first frame.
CLUTCHES = [(78.0, 1.55), (28.0, 1.95), (140.0, 1.75), (205.0, 2.05), (262.0, 1.45), (322.0, 1.85)]
EGG = (0.135, 0.225, 0.055)  # a capsule's half width, half length and half thickness (m)


def _nest_relief(x, y):
    return 0.045 * noise.noise(Vector((x / 1.3 + 3.3, y / 1.3 - 1.1, 0.4))) + 0.018 * noise.noise(Vector((x / 0.45, y / 0.45, 2.2)))


def _nest_profile_z(r):
    pts = NEST_PROFILE
    if r <= pts[0][0]:
        return pts[0][1]
    for (r0, z0), (r1, z1) in zip(pts, pts[1:]):
        if r <= r1:
            return z0 + (z1 - z0) * (r - r0) / (r1 - r0)
    return pts[-1][1]


def _nest_fade(r):
    """How much relief the mound takes at r: a little in the dish, full on the bank, none at the foot."""
    if r >= 4.42:
        return 0.0
    if r >= 4.2:
        return (4.42 - r) / 0.22
    return 0.35 + 0.65 * bc.smoothstep(min(1.0, max(0.0, (r - 2.2) / 1.0)))


def nest_z(x, y):
    """The mound's top at (x, y): the profile plus its relief (the surface the stones, beacon and eggs stand on)."""
    r = math.hypot(x, y)
    return _nest_profile_z(r) + _nest_relief(x, y) * _nest_fade(r)


def _nest_normal(x, y, h=0.05):
    dzdx = (nest_z(x + h, y) - nest_z(x - h, y)) / (2 * h)
    dzdy = (nest_z(x, y + h) - nest_z(x, y - h)) / (2 * h)
    return Vector((-dzdx, -dzdy, 1.0)).normalized()


def _frame(normal, yaw):
    """A rotation whose Z is `normal` and whose Y is yawed by `yaw` (rad) round it."""
    z = Vector(normal).normalized()
    y = Vector((-math.sin(yaw), math.cos(yaw), 0.0))
    x = y.cross(z).normalized()
    y = z.cross(x).normalized()
    return Matrix((x, y, z)).transposed()


def _mound():
    profile = [(z, r) for r, z in NEST_PROFILE]
    rv, rf, _ = bc.revolve(profile, NEST_SEGMENTS)
    verts = []
    for x, y, z in cp._up(rv):
        r = math.hypot(x, y)
        verts.append((x, y, z + _nest_relief(x, y) * _nest_fade(r) if r < NEST_R - 0.05 else z))
    gravel = sf.Shader("M_NestGravelProc")
    # Shell gravel: rounded pebbles of two sizes (a noise mask picks which), each its own shade, a few pale shell
    # fragments, shallow gaps; the dish is scooped clean to fine sand.
    warp = _warped(gravel, 2.5, 0.05)
    edge_big, tone_big = _cells(gravel, 11.0, vector=warp)
    edge_small, tone_small = _cells(gravel, 26.0, vector=warp)
    small = gravel.remap(gravel.noise(1.8, 2.0), 0.45, 0.6)
    edge = gravel.mix(small, edge_big, edge_small)
    tone = gravel.mix(small, tone_big, tone_small)
    radial = _radial(gravel)
    dish = gravel.remap(radial, 2.9, 2.2)
    blotch = gravel.noise(0.7, 2.0)
    base = gravel.mix(tone, "#6E6352", "#A99C85")
    base = gravel.mix(gravel.remap(tone, 0.88, 0.94), base, "#D8CDB3")       # a pale shell fragment among the pebbles
    base = gravel.mix(gravel.math("MULTIPLY", gravel.remap(edge, 0.05, 0.0), 0.35), base, "#4A4238")   # the gaps
    grain = gravel.noise(45.0, 3.0)
    sand = gravel.mix(gravel.remap(grain, 0.3, 0.7), "#7C705C", "#918470")      # damp, darker than the eggs
    base = gravel.mix(dish, base, sand)
    base = gravel.mix(gravel.math("MULTIPLY", gravel.remap(blotch, 0.55, 0.75), 0.3), base, "#61584A")   # damp patches
    dome = gravel.remap(edge, 0.0, 0.3)                    # each pebble rounded up from its gap
    gravel.bump(gravel.math("ADD", gravel.math("MULTIPLY", dome, gravel.math("SUBTRACT", 1.0, dish)),
                            gravel.math("MULTIPLY", grain, 0.3)), 0.6, 0.025)
    mat = gravel.out(base, 0.92)
    obj = bc.mesh_object("NestMound", verts, rf, [mat], fix_normals=False)
    bpy.context.view_layer.update()
    if sum(1 for p in obj.data.polygons if p.normal.z > 0) < len(obj.data.polygons) * 0.5:
        obj.data.flip_normals()
    return obj


def _stone_shader(name):
    st = sf.Shader(name)
    pits = st.voronoi(9.0, 0.9)
    mott = st.noise(2.5, 4.0)
    crust = st.math("MULTIPLY", st.remap(_up_facing(st), 0.25, 0.85), st.remap(st.noise(3.5, 3.0), 0.38, 0.62))
    base = st.mix(st.remap(mott, 0.35, 0.65), "#5B544A", "#847B6D")
    base = st.mix(crust, base, "#A99F8B")                      # a pale encrusting crust on the tops
    base = st.mix(st.math("MULTIPLY", st.remap(pits, 0.1, 0.02), 0.85), base, "#37322C")   # bored pits
    st.bump(st.math("ADD", st.math("MULTIPLY", st.remap(pits, 0.0, 0.12), 0.6), st.math("MULTIPLY", st.noise(28.0, 2.0), 0.4)), 0.45, 0.012)
    return st.out(base, st.remap(crust, 0.0, 1.0, 0.78, 0.9))


def _coral_shader(name):
    co = sf.Shader(name)
    spot = co.noise(22.0, 2.0)
    base = co.mix(co.remap(co.noise(4.0, 2.0), 0.3, 0.7), "#7E6A9A", "#9C86B4")
    base = co.mix(co.remap(spot, 0.6, 0.72), base, "#CDBEDC")       # pale polyp mouths
    co.bump(spot, 0.3, 0.004)
    return co.out(base, 0.55)


def _rim(stone, coral):
    """The rim's reef stones (NestRim) and the coral polyps crusting their tops (NestPolyps, their own piece so the
    stones' decimation leaves the small polyps round)."""
    rng = random.Random(4721)
    verts, faces, mats = [], [], []
    pverts, pfaces = [], []
    skip = math.radians(BEACON_DEG)
    placed = 0
    for i in range(RIM_STONES + 2):
        a = math.radians(i * 360.0 / (RIM_STONES + 2) + rng.uniform(-4.0, 4.0))
        if abs(math.atan2(math.sin(a - skip), math.cos(a - skip))) < math.radians(15.0):
            continue                                        # the beacon stands here
        if placed == RIM_STONES:
            break
        placed += 1
        r = rng.uniform(RIM_MIN_R + 0.05, 3.85)
        c = Vector((r * math.cos(a), r * math.sin(a), 0.0))
        # Long along the ring, so the stones close up into a rim; flattened boulders.
        radii = (rng.uniform(0.55, 0.8), rng.uniform(0.38, 0.48), rng.uniform(0.28, 0.35))
        v, f, surface = _rock(radii, i + 1, flat_below=-0.5, rough=0.2)
        rot = Matrix.Rotation(a + math.pi * 0.5 + rng.uniform(-0.35, 0.35), 3, "Z")
        top = max(co[2] for co in v)
        # Seated on the lowest point of the bank under it (sampled round its outline), so no side floats; its top,
        # polyps included, stays under RIM_MAX_Z.
        under = [nest_z(c.x, c.y)] + [nest_z(*(c + rot @ Vector((0.9 * radii[0] * math.cos(t), 0.9 * radii[1] * math.sin(t), 0.0))).xy)
                                      for t in (k * math.tau / 12 for k in range(12))]
        c.z = min(min(under) + radii[2] * 0.22, RIM_MAX_Z - 0.11 - top)
        bc.append(verts, faces, _place(v, rot, c), f)
        mats.extend([0] * (len(faces) - len(mats)))
        for _ in range(rng.randint(2, 3)):                  # polyps crust the stone's top
            d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0.45, 1.0)))
            p = rot @ surface(d) + c
            n = (rot @ Vector((d.x / radii[0] ** 2, d.y / radii[1] ** 2, d.z / radii[2] ** 2))).normalized()
            pv, pf = _polyp(p, n, rng.uniform(0.06, 0.1), rng.uniform(0.035, 0.055))
            bc.append(pverts, pfaces, pv, pf)
    return bc.mesh_object("NestRim", verts, faces, [stone], mats), bc.mesh_object("NestPolyps", pverts, pfaces, [coral])


def _ribbon(root, length, width, lean, seed, segments=12):
    """An amber ribbon frond rising from `root`, bending over toward `lean` (a horizontal vector) with the current,
    widening from its stipe and tapering to a tip, twisting a little. One surface, drawn from both sides."""
    up = Vector((0.0, 0.0, 1.0))
    lean = Vector(lean).normalized()
    side0 = up.cross(lean).normalized()
    verts, faces = [], []
    pts = []
    for k in range(segments + 1):
        t = k / segments
        wave = 0.06 * length * math.sin(t * 7.0 + seed)
        pts.append(root + up * (length * (0.9 * t - 0.25 * t * t)) + lean * (length * 0.55 * t * t) + side0 * wave)
    for k, p in enumerate(pts):
        t = k / segments
        tan = (pts[min(k + 1, segments)] - pts[max(k - 1, 0)]).normalized()
        twist = 0.9 * t + 0.3 * math.sin(seed)
        side = (side0 * math.cos(twist) + side0.cross(tan) * math.sin(twist)).normalized()
        w = width * (0.25 + 0.75 * math.sin(math.pi * min(1.0, 0.12 + 0.95 * t)) ** 0.8) * (1.0 - 0.85 * t ** 3)
        verts.append(tuple(p - side * w * 0.5))
        verts.append(tuple(p + side * w * 0.5))
    for k in range(segments):
        a = 2 * k
        faces.append((a, a + 1, a + 3, a + 2))
    return verts, faces


def _beacon(stone, coral, frond):
    """The stacked reef-stone pillar with ribbon fronds. Its origin is its foot on the mound; the base stone reaches
    0.3 m under it, so the pillar still meets the mound when the world stands it upright on the tilted nest."""
    rng = random.Random(9133)
    a = math.radians(BEACON_DEG)
    foot = Vector((BEACON_R * math.cos(a), BEACON_R * math.sin(a), 0.0))
    foot.z = nest_z(foot.x, foot.y)
    # Weathered slabs, each flatter than it is wide and set off its neighbour, narrowing up the pillar.
    stack = [((0.82, 0.72, 0.5), 0.0, (0.0, 0.0)), ((0.7, 0.58, 0.34), 0.68, (0.12, -0.06)),
             ((0.6, 0.5, 0.32), 1.18, (-0.06, 0.08)), ((0.52, 0.46, 0.3), 1.66, (0.08, 0.03)),
             ((0.46, 0.38, 0.27), 2.12, (-0.04, -0.07)), ((0.36, 0.32, 0.24), 2.54, (0.05, 0.02)),
             ((0.27, 0.25, 0.22), 2.9, (0.0, -0.02))]
    verts, faces, mats = [], [], []
    dverts, dfaces, dmats = [], [], []                      # the polyps and fronds: BeaconDetail, a child piece
    tops = []
    for i, (radii, z, (dx, dy)) in enumerate(stack):
        v, f, surface = _rock(radii, 40 + i, flat_below=-0.55, rough=0.24)
        rot = Matrix.Rotation(rng.uniform(0.0, math.tau), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.08, 0.08), 3, "X")
        c = Vector((dx, dy, z))
        bc.append(verts, faces, _place(v, rot, c), f)
        mats.extend([0] * (len(faces) - len(mats)))
        tops.append((c, radii))
        for _ in range(5 if i < 5 else 2):
            d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 0.9)))
            p = rot @ surface(d) + c
            n = (rot @ Vector((d.x / radii[0] ** 2, d.y / radii[1] ** 2, d.z / radii[2] ** 2))).normalized()
            pv, pf = _polyp(p, n, rng.uniform(0.05, 0.1), rng.uniform(0.03, 0.05))
            bc.append(dverts, dfaces, pv, pf)
            dmats.extend([0] * (len(dfaces) - len(dmats)))
    # Fronds: four from the cap, three from the joints lower down, all bending over with the current, along the rim
    # (round the nest, so they stay over the footprint): toward -X and -Y, across the spawn camera's view.
    current = Vector((-math.sin(a), math.cos(a), 0.0))
    cap, cap_r = tops[-1]
    fronds = [(cap + Vector((0.08, 0.05, cap_r[2] * 0.7)), 2.9, 0.4), (cap + Vector((-0.1, 0.0, cap_r[2] * 0.6)), 2.6, 0.36),
              (cap + Vector((0.0, -0.1, cap_r[2] * 0.6)), 2.75, 0.34), (cap + Vector((0.02, 0.12, cap_r[2] * 0.5)), 2.3, 0.32),
              (cap + Vector((-0.06, -0.06, cap_r[2] * 0.5)), 2.1, 0.3)]
    for i in (4, 3, 2, 5):
        c, radii = tops[i]
        ang = rng.uniform(0.0, math.tau)
        fronds.append((c + Vector((math.cos(ang) * radii[0] * 0.8, math.sin(ang) * radii[1] * 0.8, radii[2] * 0.75)), rng.uniform(1.5, 2.0), 0.26))
    for k, (root, length, width) in enumerate(fronds):
        lean = current + Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 0.0))
        v, f = _ribbon(root, length, width, lean, seed=k * 1.7 + 0.4)
        bc.append(dverts, dfaces, v, f)
        dmats.extend([1] * (len(dfaces) - len(dmats)))
    obj = bc.mesh_object("Beacon", verts, faces, [stone], mats, location=tuple(foot))
    detail = bc.mesh_object("BeaconDetail", dverts, dfaces, [coral, frond], dmats, parent=obj, fix_normals=False)
    # The polyps are closed, so their faces are made to point out; the fronds are open strips, drawn from both sides.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(detail.data)
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f.material_index == 0])
    bm.to_mesh(detail.data)
    bm.free()
    return obj, detail, foot


def _capsule(seg=12):
    """A cartilage egg capsule (a "mermaid's purse"): a pillow with a rounded-rectangle outline (a superellipsoid),
    lying flat, its length along Y; returns verts, faces and the four corner points the horns grow from."""
    ax, ay, az = EGG
    verts = [(0.0, 0.0, -az)]
    for lat in (-45.0, 0.0, 45.0):
        t = math.radians(lat)
        ct, st = math.cos(t), math.sin(t)
        for j in range(seg):
            p = 2.0 * math.pi * j / seg
            cp_, sp = math.cos(p), math.sin(p)
            e = 0.45
            x = ax * math.copysign(abs(cp_) ** e, cp_) * abs(ct) ** 0.7
            y = ay * math.copysign(abs(sp) ** e, sp) * abs(ct) ** 0.7
            verts.append((x, y, az * math.copysign(abs(st) ** 0.8, st)))
    verts.append((0.0, 0.0, az))
    faces = []
    for j in range(seg):
        k = (j + 1) % seg
        faces.append((0, 1 + k, 1 + j))
        for ring in range(2):
            a, b = 1 + ring * seg, 1 + (ring + 1) * seg
            faces.append((a + j, a + k, b + k, b + j))
        top = 1 + 2 * seg
        faces.append((top + j, top + k, len(verts) - 1))
    corners = [Vector((sx * ax * 0.78, sy * ay * 0.86, 0.0)) for sx in (-1, 1) for sy in (-1, 1)]
    return verts, faces, corners


def _horn(corner, length, curl):
    """A capsule's horn: a thin tendril from a corner, out along the capsule's length, curling sideways and down into
    the sand."""
    out = Vector((0.0, math.copysign(1.0, corner.y), 0.0))
    side = Vector((math.copysign(1.0, corner.x), 0.0, 0.0))
    path = [corner - out * 0.02]
    for k in range(1, 4):
        t = k / 3
        path.append(corner + out * (length * t) + side * (curl * length * t * t) + Vector((0.0, 0.0, -0.04 * t * t)))
    return cp._tube(path, lambda i, ang: (0.019, 0.015, 0.01, 0.0)[i], 3)[:2]


def _egg_shaders():
    egg = sf.Shader("M_NestEggProc")
    streak = egg.noise(9.0, 3.0, vector=egg.vmath("MULTIPLY", egg.pos, (1.0, 4.0, 1.0)))
    base = egg.mix(egg.remap(streak, 0.4, 0.75), "#EFE3C6", "#DDB57A")          # cream, streaked with amber
    base = egg.mix(egg.remap(egg.noise(3.0, 2.0), 0.6, 0.8), base, "#D4A35E")
    egg.bump(streak, 0.25, 0.003)
    horn = sf.Shader("M_NestEggHornProc")
    hbase = horn.mix(horn.remap(horn.noise(30.0, 2.0), 0.3, 0.7), "#B07A3C", "#C99550")
    return egg.out(base, 0.35), horn.out(hbase, 0.45)


def _clutches(egg, horn):
    rng = random.Random(2617)
    cap_v, cap_f, corners = _capsule()
    objs = []
    for i, (deg, r) in enumerate(CLUTCHES):
        a = math.radians(deg)
        centre = Vector((r * math.cos(a), r * math.sin(a), 0.0))
        centre.z = nest_z(centre.x, centre.y)
        spin = rng.uniform(0.0, math.tau)
        verts, faces, mats = [], [], []
        for dx, dy, yaw in ((-0.21, 0.04, 0.35), (0.2, 0.11, -0.6), (0.01, -0.26, 1.4)):
            off = Matrix.Rotation(spin, 3, "Z") @ Vector((dx, dy, 0.0))
            p = Vector((centre.x + off.x, centre.y + off.y, 0.0))
            n = _nest_normal(p.x, p.y)
            p.z = nest_z(p.x, p.y) + EGG[2] * 0.62                        # sunk a third of its thickness
            rot = _frame(n, spin + yaw + rng.uniform(-0.2, 0.2))
            bc.append(verts, faces, _place(cap_v, rot, p - centre), cap_f)
            mats.extend([0] * (len(faces) - len(mats)))
            for c in corners:
                hv, hf = _horn(c, rng.uniform(0.11, 0.16), rng.uniform(0.3, 0.7))
                bc.append(verts, faces, _place(hv, rot, p - centre), hf)
                mats.extend([1] * (len(faces) - len(mats)))
        objs.append(bc.mesh_object(f"Clutch_{i + 1}", verts, faces, [egg, horn], mats, location=tuple(centre)))
    return objs


def _frond_shader():
    fr = sf.Shader("M_NestFrondProc")
    veins = fr.noise(3.0, 2.0, vector=fr.vmath("MULTIPLY", fr.pos, (6.0, 6.0, 0.6)))
    base = fr.mix(fr.remap(veins, 0.45, 0.7), "#B06A2C", "#CF8E42")
    base = fr.mix(fr.math("MULTIPLY", fr.remap(fr.noise(14.0, 2.0), 0.62, 0.75), 0.6), base, "#7A4A22")   # spots
    fr.bump(veins, 0.2, 0.004)
    return fr.out(base, 0.55)


def build_nest():
    """The spawning nest (aquatic-r2, PROPOSED look): see the module docstring. Pivot: the nest's centre on the floor."""
    mound = _mound()
    stone, coral = _stone_shader("M_NestStoneProc"), _coral_shader("M_NestCoralProc")
    rim, polyps = _rim(stone, coral)
    beacon, detail, foot = _beacon(stone, coral, _frond_shader())
    egg, horn = _egg_shaders()
    clutches = _clutches(egg, horn)
    bpy.context.view_layer.update()
    # Contract checks before the bake (the bake only reduces within millimetres).
    pts = bc.world_vertices()
    mp._check(max(math.hypot(p.x, p.y) for p in pts) <= NEST_R + 1e-4, "nest: within its %.1f m footprint" % NEST_R)
    rim_pts = [rim.matrix_world @ v.co for v in rim.data.vertices]
    mp._check(max(p.z for p in rim_pts) <= RIM_MAX_Z, "nest: rim stones stand at most %.1f m" % RIM_MAX_Z)
    mp._check(min(math.hypot(p.x, p.y) for p in rim_pts) >= RIM_MIN_R - 0.6, "nest: rim stones stay on the rim")
    b_pts = [o.matrix_world @ v.co for o in (beacon, detail) for v in o.data.vertices]
    mp._check(max(p.z for p in b_pts) <= BEACON_MAX_Z, "nest: the beacon is at most %.0f m tall (%.2f)" % (BEACON_MAX_Z, max(p.z for p in b_pts)))
    mp._check(min(p.z for p in b_pts) <= foot.z - 0.25, "nest: the beacon's base reaches under its foot")
    for obj, (deg, r) in zip(clutches, CLUTCHES):
        mp._check(1.0 <= math.hypot(obj.location.x, obj.location.y) <= 2.2, f"nest: {obj.name} lies on the dish")
    pieces = [(mound, 0.008, 1.0), (rim, 0.007, 1.15), (polyps, 0.0015, 1.6), (beacon, 0.006, 1.3), (detail, 0.0015, 1.5)] \
        + [(c, 0.003, 2.2) for c in clutches]
    baked = _bake_pieces(pieces, "AquaticNest", 1024, isolate=clutches)
    pts = bc.world_vertices()
    mp._check(min(p.z for p in pts) >= -NEST_SKIRT - 0.01, "nest: the skirt ends %.2f m under the pivot" % NEST_SKIRT)
    return {"purpose": "Aquatic stage spawning nest (PROPOSED): the stage's home landmark: a raised shell-gravel mound with a scooped dish, a ring of rounded reef stones crusted with lilac coral polyps, six clutches of cream cartilage egg capsules (one shown per generation hatched) and a stacked reef-stone beacon with amber ribbon fronds that reads from about 25 m.",
            "category": "environment", "kind": "nest",
            "pivot": "the nest's centre on the floor (Blender z = 0, Godot y = 0); the dish lies 0.27 m above it and a 0.55 m skirt below it",
            "usage": "game/scenes/aquatic/aquatic_world.gd places it at rules.world.nest (x, z) on the floor profile at scale 1, tilts it to the slope there (about X, the profile's rise over 4 m) and sinks it NEST_SINK; the Beacon node is then stood upright on its foot; Clutch_i is shown while i <= the generations hatched this stage (history + 1, at most 6).",
            "nest_m": {"footprint_r": NEST_R, "dish_z": NEST_PROFILE[0][1], "crest_r": 3.5, "crest_z": 0.5, "skirt": NEST_SKIRT,
                       "rim_min_r": RIM_MIN_R, "rim_max_z": RIM_MAX_Z, "beacon_at": [round(foot.x, 3), round(foot.y, 3), round(foot.z, 3)],
                       "beacon_max_z": BEACON_MAX_Z},
            "clutches": [{"node": c.name, "at": [round(c.location.x, 3), round(c.location.y, 3), round(c.location.z, 3)]} for c in clutches],
            "palette": {"gravel": ["#6E6352", "#A99C85", "#D8CDB3"], "dish": ["#7C705C", "#918470"], "stone": ["#5B544A", "#847B6D", "#A99F8B"], "coral": ["#7E6A9A", "#9C86B4", "#CDBEDC"],
                        "egg": ["#EFE3C6", "#DDB57A"], "horn": ["#B07A3C", "#C99550"], "frond": ["#B06A2C", "#CF8E42"]},
            "gate_report": "docs/evidence/credit-aquatic-r2/aquatic_asset_gates.md", "revision": 1, **baked}


# --- The editor's plinth (aquatic-r2) -------------------------------------------------------------------------------

PLINTH_R = 1.0
# The plinth's profile as (z, r) from the centre of the top face out, over a stepped rock edge (two ledges of layered
# reef rock) and under to the centre of the bottom. The edge is then bitten in by noise, never past r = 1.
PLINTH_PROFILE = [(0.0, 0.0), (0.0, 0.35), (0.0, 0.65), (0.0, 0.84), (-0.004, 0.9), (-0.014, 0.935), (-0.035, 0.955),
                  (-0.062, 0.962), (-0.078, 0.982), (-0.12, 0.994), (-0.17, 1.0), (-0.212, 0.99), (-0.245, 0.972),
                  (-0.262, 0.985), (-0.3, 0.965), (-0.335, 0.91), (-0.35, 0.0)]
PLINTH_TOP_R = 0.9      # the flat top face reaches this far before the edge falls away
PLINTH_SEGMENTS = 96
# Polyp colonies on the rim: (angle deg, polyps); most on the far side (Blender +Y, Godot -Z), which the editor's
# camera sees against the water above the rim.
PLINTH_COLONIES = [(28.0, 5), (64.0, 4), (97.0, 6), (131.0, 4), (158.0, 5), (205.0, 3), (300.0, 3)]
PLINTH_SPONGES = [(80.0, 0.11), (114.0, 0.08)]


def _plinth_bite(x, y, z):
    """How far (m) the rock edge is bitten in at a point: blocky at two scales, never negative."""
    big = 0.5 + 0.5 * noise.noise(Vector((x * 4.5 + 7.0, y * 4.5, z * 6.0)))
    fine = noise.noise(Vector((x * 13.0, y * 13.0, z * 13.0 + 3.0)))
    return max(0.0, 0.05 * big + 0.012 * fine)


def _plinth_top(r):
    pts = [(rr, z) for z, rr in PLINTH_PROFILE[:11]]
    for (r0, z0), (r1, z1) in zip(pts, pts[1:]):
        if r <= r1:
            return z0 + (z1 - z0) * (r - r0) / (r1 - r0)
    return pts[-1][1]


def build_plinth():
    """The fin and tail editor's plinth: a unit-radius slab of layered reef rock, its flat top stone with sand settled
    in patches, its stepped edge bitten and pitted, lilac coral crusting the edge in patches with colonies of polyps
    on the rim, and two small amber sponges on the far rim. Pivot: the centre of the top face."""
    rv, rf, _ = bc.revolve(PLINTH_PROFILE, PLINTH_SEGMENTS)
    verts = []
    for x, y, z in cp._up(rv):
        r = math.hypot(x, y)
        if r >= PLINTH_TOP_R - 1e-6 and r > 0.0:
            bite = _plinth_bite(x, y, z) * min(1.0, (r - PLINTH_TOP_R + 0.06) / 0.06)
            s = (r - bite) / r
            x, y = x * s, y * s
            if z < -0.006:
                z += 0.012 * noise.noise(Vector((x * 7.0, y * 7.0, 1.3)))
        verts.append((x, y, z))
    rng = random.Random(5521)
    faces = list(rf)
    mats = [0] * len(faces)
    for deg, count in PLINTH_COLONIES:
        for _ in range(count):
            a = math.radians(deg + rng.uniform(-7.0, 7.0))
            r = rng.uniform(0.84, 0.91)
            base = Vector((r * math.cos(a), r * math.sin(a), _plinth_top(r)))
            n = Vector((math.cos(a) * 0.35, math.sin(a) * 0.35, 1.0)).normalized()
            pv, pf = _polyp(base, n, rng.uniform(0.035, 0.06), rng.uniform(0.02, 0.032), sides=8)
            bc.append(verts, faces, pv, pf)
            mats.extend([1] * (len(faces) - len(mats)))
    for deg, h in PLINTH_SPONGES:
        a = math.radians(deg)
        r = 0.87
        base = Vector((r * math.cos(a), r * math.sin(a), _plinth_top(r) - 0.01))
        path = [base + Vector((0.0, 0.0, h * t)) for t in (0.0, 0.35, 0.7, 1.0, 1.04)]
        sv, sf_, _ = cp._tube(path, lambda i, ang: (0.035, 0.03, 0.036, 0.04, 0.0)[i], 8)
        bc.append(verts, faces, sv, sf_)
        mats.extend([2] * (len(faces) - len(mats)))
    st = sf.Shader("M_PlinthStoneProc")
    pits = st.voronoi(16.0, 0.9)
    radial = _radial(st)
    up = _up_facing(st)
    side = st.math("SUBTRACT", 1.0, st.remap(up, 0.7, 0.95))              # 1 on the edge, 0 on the top
    strata = st.noise(1.2, 2.0, vector=st.vmath("MULTIPLY", st.pos, (0.6, 0.6, 30.0)))
    rock = st.mix(st.remap(st.noise(3.0, 4.0), 0.35, 0.65), "#554E45", "#746B5F")
    rock = st.mix(st.math("MULTIPLY", st.remap(strata, 0.48, 0.62), 0.6), rock, "#3E3933")   # layer lines
    top = st.mix(st.remap(st.noise(5.0, 4.0), 0.3, 0.7), "#5C554B", "#776E62")
    top = st.mix(st.math("MULTIPLY", st.remap(st.noise(2.2, 3.0), 0.55, 0.7), 0.7), top, "#454039")   # weathered patches
    top = st.mix(st.math("MULTIPLY", st.remap(st.voronoi(7.0, 1.0), 0.12, 0.04), 0.5), top, "#3C3732")  # shallow pocks
    base = st.mix(side, top, rock)
    sand = st.math("MULTIPLY", st.math("SUBTRACT", 1.0, side), st.remap(st.noise(1.3, 3.0), 0.55, 0.68))
    base = st.mix(sand, base, st.mix(st.remap(st.noise(30.0, 2.0), 0.3, 0.7), "#887E6B", "#9C927E"))   # sand pools
    crust = st.math("MULTIPLY", st.remap(radial, 0.86, 0.92), st.remap(st.noise(4.0, 3.0), 0.5, 0.6))
    base = st.mix(crust, base, st.mix(st.remap(st.noise(25.0, 2.0), 0.4, 0.7), "#7A6894", "#988AB0"))   # lilac crust
    base = st.mix(st.math("MULTIPLY", st.remap(pits, 0.1, 0.02), 0.85), base, "#2F2B26")
    st.bump(st.math("ADD", st.math("MULTIPLY", st.remap(pits, 0.0, 0.12), 0.6),
                    st.math("ADD", st.math("MULTIPLY", st.noise(40.0, 2.0), 0.3), st.math("MULTIPLY", crust, 0.5))), 0.4, 0.008)
    sp = sf.Shader("M_PlinthSpongeProc")
    holes = sp.voronoi(60.0, 0.9)
    sp.bump(sp.remap(holes, 0.0, 0.15), 0.5, 0.003)
    osculum = sp.remap(_up_facing(sp), 0.82, 0.95)                    # the dark opening on top
    sponge = sp.out(sp.mix(osculum, sp.mix(sp.remap(holes, 0.12, 0.02), "#B98146", "#6E4524"), "#3E2814"), 0.7)
    obj = bc.mesh_object("AquaticPlinth", verts, faces, [st.out(base, 0.86), _coral_shader("M_PlinthCoralProc"), sponge], mats)
    baked = _bake_pieces([(obj, 0.0015, 1.0)], "AquaticPlinth", 1024)
    pts = bc.world_vertices()
    widest = max(math.hypot(p.x, p.y) for p in pts)
    mp._check(0.98 <= widest <= PLINTH_R + 1e-6, "plinth: its radius is 1.0 (%.3f)" % widest)
    # Decimation folds the flat face's inner rings away, so the face is probed from above instead of read at vertices.
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())
    probes = [(0.0, 0.0)] + [(0.7 * math.cos(k * math.tau / 8), 0.7 * math.sin(k * math.tau / 8)) for k in range(8)]
    face = [tree.ray_cast(Vector((x, y, 1.0)), Vector((0.0, 0.0, -1.0)))[0] for x, y in probes]
    mp._check(all(h is not None and abs(h.z) < 0.006 for h in face), "plinth: the top face is at z = 0, the pivot")
    return {"purpose": "Aquatic editor plinth (PROPOSED): the fin and tail editor's reef-stone plinth, a unit-radius slab of layered reef rock with sand settled on its flat top, a stepped, bitten and pitted edge crusted with lilac coral, polyp colonies and two small amber sponges on its rim; replaces the creature editor's pad in the aquatic editor (aquatic plan section 2).",
            "category": "environment", "kind": "editor_floor",
            "pivot": "the centre of the top face (Blender z = 0, Godot y = 0); the slab is 0.35 m deep under it",
            "usage": "game/ui/aquatic_editor.gd places it at y = -0.01 and scales it uniformly (PLINTH_SCALE), so the polyps and sponges keep their shape; the camera sees the top face and the far rim against the water.",
            "plinth_m": {"radius": PLINTH_R, "top_face_r": PLINTH_TOP_R, "depth": 0.35,
                         "polyps": sum(c for _, c in PLINTH_COLONIES), "sponges": len(PLINTH_SPONGES)},
            "palette": {"rock": ["#554E45", "#746B5F", "#3E3933"], "top": ["#5C554B", "#776E62", "#454039"], "sand": ["#887E6B", "#9C927E"],
                        "crust": ["#7A6894", "#988AB0"], "coral": ["#7E6A9A", "#9C86B4", "#CDBEDC"], "sponge": ["#B98146", "#6E4524"]},
            "gate_report": "docs/evidence/credit-aquatic-r2/aquatic_asset_gates.md", "revision": 1, **baked}

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


ASSETS = {"aquatic_seafloor": (build_seafloor, 24000),
          "aquatic_nest": (build_nest, 12000),
          "aquatic_plinth": (build_plinth, 4000)}
PROVENANCES = {"aquatic_nest": PROVENANCE_BAKED, "aquatic_plinth": PROVENANCE_BAKED}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the Aquatic stage's sea floor, nest and editor plinth.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    parser.add_argument("--import", dest="map_only", action="store_true", help="only write the engine material and the .import mapping")
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
                           provenance=PROVENANCES.get(asset_id, PROVENANCE))
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
