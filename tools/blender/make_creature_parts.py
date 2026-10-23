"""The first creature parts in the creature art contract's convention (docs/art/creature_art_contract.md, section 1).
PROPOSED: for the creature lab (prototypes/creature-lab) and the look review; no game code reads them yet.

Convention (unlike the M1 cell parts, whose outward axis is Blender +Y):
- Blender +Z (Godot +Y) is the skin normal at the anchor, Blender +Y (Godot -Z) points toward the head.
- The pivot is where the part meets the skin; geometry below it, down to sink_depth, is the root.
  Ground parts (feet) instead stand on the pivot: +Z is body up at rest, the sole on z = 0.
- Authored at the part's nominal size for a body about 1 m long (scale 1000 per mille).
- Up to four shape keys H1_..H4_ are the handles, 0 to 1000 per mille; the runtime sets them as blend shapes.
- One root mesh named after the part type, no bones; chiral parts ship the right-hand (+X) side only.
- record["part_rules"] holds the PartRules values (footprint, sink, chirality, orientation, limits, hosts, handles).

Every part is finished like the M1 parts: procedural greyscale detail baked to one texture set (albedo detail
with AO, ORM, normal), each material keeping its name and flat colour, and paint_mix saying how much of the
creature's paint replaces that colour.

Run: python tools/blender/make_creature_parts.py [--only <id>[,<id>...]]
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_m1_production as mp  # noqa: E402
import surfacing as sf  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

GENERATOR = "tools/blender/make_creature_parts.py"
REVIEW_STATE = mp.REVIEW_STATE
PROVENANCE = "Authored procedurally in Blender by tools/blender/make_creature_parts.py; no external or generated meshes. Textures baked in Blender from procedural shaders."
TOLERANCE = 0.0008
UP = Matrix.Rotation(math.radians(90.0), 4, "X")     # a revolve's +Y axis turned to +Z (the skin normal)


def _lin(hex_color):
    return mp._lin(hex_color)


def _up(verts):
    """Revolve output (along +Y) turned so its axis is the skin normal (+Z)."""
    return [tuple(UP @ Vector(v)) for v in verts]


def _tube(path, radius_at, sides):
    """Like mp._sweep, but the ring frame is carried along the path by parallel transport, so a
    curving path never flips its frame (mp._sweep switches its reference axis and twists the rings).
    Returns verts, faces and each face's ring index (0 = the capped start)."""
    verts, faces, rings, face_ring = [], [], [], []
    n = len(path)
    t0 = (path[1] - path[0]).normalized()
    side = t0.cross(Vector((0.0, 0.0, 1.0)) if abs(t0.z) < 0.9 else Vector((1.0, 0.0, 0.0))).normalized()
    for i, p in enumerate(path):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        side = (side - t * side.dot(t)).normalized() if i else side
        up = side.cross(t).normalized()
        if radius_at(i, 0.0) <= 0.0:
            rings.append([len(verts)])
            verts.append(tuple(p))
            continue
        ring = []
        for j in range(sides):
            a = 2.0 * math.pi * j / sides
            r = radius_at(i, a)
            ring.append(len(verts))
            verts.append(tuple(p + side * (r * math.cos(a)) + up * (r * math.sin(a))))
        rings.append(ring)
    cap = len(verts)
    verts.append(tuple(path[0]))
    for j in range(sides):
        faces.append((cap, rings[0][(j + 1) % sides], rings[0][j]))
        face_ring.append(0)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((a[j], a[k], b[0]) if len(b) == 1 else (a[j], a[k], b[k], b[j]))
            face_ring.append(i)
    return verts, faces, face_ring


def _shape_keys(obj, handles):
    """handles: [(name, fn(co) -> new co, meaning)]. Added after the bake (decimation cannot run on shape keys)."""
    obj.shape_key_add(name="Basis", from_mix=False)
    out = []
    for name, fn, meaning in handles:
        key = obj.shape_key_add(name=name, from_mix=False)
        key.value = 0.0     # Blender adds keys at 1; the handles rest at 0 per mille
        for i, v in enumerate(obj.data.vertices):
            key.data[i].co = fn(v.co.copy())
        out.append({"key": name, "meaning": meaning, "default_permille": 0})
    return out


def _bake(objs, texture, tints, size=512, tolerance=TOLERANCE):
    before = after = 0
    highs = {}
    for obj in objs:
        b, a, high = sf.reduce(obj, tolerance)
        before, after = before + b, after + a
        if a == b:
            sf.drop_highs([high])
            high = None
        highs[obj.name] = high
    sf.unwrap(objs)
    textures = sf.bake_set(objs, texture, size, highs=highs, tints=tints)
    sf.drop_highs(highs.values())
    return {"textures": textures,
            "reduction": {"method": "Blender collapse decimation within a surface tolerance; full-detail shading baked to the normal map",
                          "tolerance_m": tolerance, "triangles_before": before, "triangles_after": after}}


def _grey(sh, fac, lo):
    return mp._grey(sh, fac, lo)


def _rules(part_type, footprint, sink, orientation, hosts, turn, tilt, centerline="allowed", chiral=False):
    return {"type": part_type, "footprint_radius_m": footprint, "sink_depth_m": sink, "chiral": chiral,
            "orientation": orientation, "turn_limit_deg": turn, "tilt_limit_deg": tilt,
            "centerline": centerline, "hosts": hosts}


def _check_pivot(name, sink, ground=False):
    pts = bc.world_vertices()
    z_min = min(p.z for p in pts)
    if ground:
        mp._check(abs(z_min) < 0.004, f"{name}: the sole sits on the pivot (z min {z_min:.4f})")
    else:
        mp._check(z_min >= -sink - 1e-4, f"{name}: sinks at most {sink} m below the skin (z min {z_min:.4f})")
    return pts


def _footprint(pts, z_max=0.01):
    return max(math.hypot(p.x, p.y) for p in pts if p.z <= z_max)


# --- Beak (mouth) -------------------------------------------------------------------------------

BEAK_LEN = 0.16
BEAK_BASE = 0.055
BEAK_SINK = 0.02


def build_beak():
    """A two-part horn beak with a fleshy gape at its root: upper and lower mandibles meeting on a
    seam, keeled on top, hooked a little at the tip. H2_Open parts them about the gape hinge."""
    # Swept along a path rising from below the skin and hooking toward +Y at the tip; the cross-section is an
    # ellipse, narrower side to side, with a keel on the +Y side (the upper mandible when the beak faces forward).
    steps, sides = 22, 32
    path, radii = [], []
    for i in range(steps + 1):
        t = i / steps
        path.append(Vector((0.0, 0.03 * t ** 3, -BEAK_SINK + (BEAK_LEN + BEAK_SINK) * t)))
        radii.append(BEAK_BASE * 1.1 if t < 0.12 else BEAK_BASE * (1.0 - (t - 0.12) / 0.88) ** 0.85)

    def radius_at(i, a):
        if i == steps:
            return 0.0
        keel = 1.0 + 0.22 * max(0.0, math.sin(a)) ** 4
        return radii[i] * math.sqrt((0.78 * math.cos(a)) ** 2 + (keel * math.sin(a)) ** 2)

    verts, faces = mp._sweep(path, radius_at, sides)
    face_materials = []
    for f in faces:
        z = sum(verts[k][2] for k in f) / len(f)
        face_materials.append(0 if z < 0.012 else 1)
    gape = sf.Shader("M_BeakGapeProc")
    wr = gape.noise(140.0, 3.0)
    gape.bump(wr, 0.3, 0.001)
    horn = sf.Shader("M_BeakHornProc")
    streak = horn.noise(60.0, 3.0, vector=mp._stretched(horn, (6.0, 6.0, 0.4)))
    seam = horn.remap(horn.math("ABSOLUTE", horn.axis("Y")), 0.004, 0.0)   # the bill's closing seam
    growth = horn.math("SINE", horn.math("MULTIPLY", horn.axis("Z"), 220.0))
    h = horn.math("ADD", streak, horn.math("MULTIPLY", growth, 0.15))
    horn.bump(horn.math("SUBTRACT", h, seam), 0.35, 0.0015)
    mats = [gape.out(_grey(gape, gape.remap(wr, 0.3, 0.7), 0.82), 0.6),
            horn.out(_grey(horn, horn.math("SUBTRACT", horn.remap(h, -0.1, 0.9), horn.math("MULTIPLY", seam, 0.5)), 0.7), 0.35)]
    beak = bc.mesh_object("Beak", verts, faces, mats, face_materials)
    for mat, name in zip(mats, ("M_BeakGape", "M_BeakHorn")):
        mat.name = name
    baked = _bake([beak], "PartBeak", {"M_BeakGape": sf.tint(_lin("#C98A7A")), "M_BeakHorn": sf.tint(_lin("#D8C08A"))})
    pts = _check_pivot("beak", BEAK_SINK)
    foot = _footprint(pts)

    def length(co):
        if co.z > 0.012:
            co.z = 0.012 + (co.z - 0.012) * 1.6
        return co

    def open_(co):
        # Mandibles part about a hinge at the gape: the head-side half (+Y) lifts toward the head, the other
        # half drops away, by 18 degrees each.
        if co.z <= 0.005:
            return co
        a = math.radians(18.0) * (1 if co.y >= 0 else -1)
        rel = Vector((0.0, co.y, co.z - 0.005))
        rot = Matrix.Rotation(a, 3, "X") @ rel
        return Vector((co.x, rot.y, rot.z + 0.005))

    def hook(co):
        t = max(0.0, co.z) / BEAK_LEN
        co.y -= 0.035 * t ** 2.5
        return co

    handles = _shape_keys(beak, [("H1_Length", length, "the bill 60% longer"),
                                 ("H2_Open", open_, "mandibles parted 18 degrees each about the gape"),
                                 ("H3_Hook", hook, "the tip hooked further toward the tail")])
    rules = _rules("beak", round(foot, 3), BEAK_SINK, "forward_cone", ["spine"], 40, 30, centerline="required")
    rules["handles"] = handles
    return {"purpose": "Creature mouth part (PROPOSED): a keeled two-part horn beak with a fleshy gape, opening on a shape key.",
            "category": "part", "part_type": "beak", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_BeakGape": 0.8, "M_BeakHorn": 0.1}, "revision": 1, **baked}


# --- Eye --------------------------------------------------------------------------------------

EYE_R = 0.045
EYE_SINK = 0.03


def build_eye():
    """A glossy eyeball in a fleshy lid ring: a dark pupil in a ringed amber iris under a clear cornea.
    H1_Blink closes the lids over the ball; H2_Bulge pushes the ball out."""
    objs = []
    # Ball: centre a little below the skin so the lid ring hides the seam.
    unit, faces = bc.icosphere(4)
    centre = Vector((0.0, 0.0, EYE_R * 0.35))
    ball_v = [tuple(centre + Vector(co).normalized() * EYE_R) for co in unit]
    eye = sf.Shader("M_EyeIrisProc")
    n = eye.vmath("NORMALIZE", eye.vmath("SUBTRACT", eye.pos, tuple(centre)))
    facing = eye.vmath("DOT_PRODUCT", n, (0.0, 0.0, 1.0))
    pupil = eye.remap(facing, 0.88, 0.9)
    iris = eye.remap(facing, 0.55, 0.59)
    fibres = eye.noise(120.0, 2.0, vector=mp._stretched(eye, (8.0, 8.0, 0.5)))
    base = eye.mix(iris, (0.92, 0.92, 0.9, 1.0), eye.mix(fibres, (0.55, 0.55, 0.55, 1.0), (0.8, 0.8, 0.8, 1.0)))
    base = eye.mix(pupil, base, (0.04, 0.04, 0.04, 1.0))
    eye.bump(eye.math("MULTIPLY", iris, fibres), 0.1, 0.0005)
    ball_mat = eye.out(base, 0.08)
    ball = bc.mesh_object("Eye", ball_v, faces, [ball_mat])
    ball_mat.name = "M_EyeBall"
    objs.append(ball)
    # Lid ring: a torus-like rolled lip around the ball, from below the skin up over its rim.
    lid_profile = []
    steps = 16
    for i in range(steps + 1):
        a = math.pi * i / steps                      # 0 below the skin, pi over the top of the lip
        r = EYE_R * 1.02 + 0.012 * math.sin(a) + 0.006
        y = -EYE_SINK + (EYE_R * 0.55 + EYE_SINK) * (1 - math.cos(a)) / 2
        lid_profile.append((y, r - 0.01 * (i / steps) ** 2))
    lv, lf, _ = bc.revolve(lid_profile, 40)
    lid_sh = sf.Shader("M_EyeLidProc")
    pores = lid_sh.remap(lid_sh.voronoi(260.0, 0.6), 0.2, 0.05)
    lid_sh.bump(lid_sh.math("SUBTRACT", 0.0, pores), 0.25, 0.0008)
    lid_mat = lid_sh.out(_grey(lid_sh, lid_sh.math("SUBTRACT", 1.0, lid_sh.math("MULTIPLY", pores, 0.3)), 0.8), 0.55)
    lid = bc.mesh_object("Lid", _up(lv), lf, [lid_mat], parent=ball, fix_normals=False)
    lid_mat.name = "M_EyeLid"
    objs.append(lid)
    baked = _bake(objs, "PartEye", {"M_EyeBall": sf.tint(_lin("#E8D7A0")), "M_EyeLid": sf.tint(_lin("#B88E7E"))}, size=256)
    pts = _check_pivot("eye", EYE_SINK)
    foot = _footprint(pts, z_max=0.02)

    def blink(co):
        # Lids: the rim rolls up and over the ball's crown, closing to a slit.
        if co.z > 0.0:
            r = math.hypot(co.x, co.y)
            k = min(1.0, max(0.0, (co.z) / (EYE_R * 0.55)))
            lift = EYE_R * 1.05 * k
            scale = max(0.05, 1.0 - 0.95 * k)
            return Vector((co.x * scale if r > 0 else co.x, co.y * scale if r > 0 else co.y, co.z + lift))
        return co

    def bulge(co):
        return Vector((co.x, co.y, co.z + 0.25 * EYE_R * max(0.0, co.z) / (EYE_R * 1.35)))

    handles = _shape_keys(lid, [("H1_Blink", blink, "the lid ring rolls over the ball to a slit")])
    handles += _shape_keys(ball, [("H2_Bulge", bulge, "the ball pushed 25% further out")])
    rules = _rules("eye", round(foot, 3), EYE_SINK, "forward_cone", ["spine", "part"], 60, 45)
    rules["handles"] = handles
    rules["handles_note"] = "H1 is on Lid, H2 on Eye; both are 0 to 1000 per mille."
    return {"purpose": "Creature eye part (PROPOSED): a glossy eyeball with a ringed amber iris in a rolled fleshy lid; blinks on a shape key.",
            "category": "part", "part_type": "eye", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_EyeBall": 0.0, "M_EyeLid": 0.9}, "revision": 1, **baked}


# --- Fin --------------------------------------------------------------------------------------

FIN_H = 0.2
FIN_BASE = 0.22
FIN_SINK = 0.015
FIN_T = 0.006


def build_fin():
    """A thin membrane fin standing on the skin, swept toward the tail, stiffened by rays that thicken it
    into a ridged edge. H1_Height raises it, H2_Sweep rakes it back, H3_Ripple waves its trailing edge."""
    cols, rows = 18, 10
    verts, faces = [], []
    grid = []
    for r in range(rows + 1):
        v = r / rows
        z = -FIN_SINK + (FIN_H + FIN_SINK) * v
        half = FIN_BASE * 0.5 * (1.0 - 0.75 * v ** 1.3)
        shift = -0.09 * v ** 1.5                 # swept toward the tail (-Y)
        row = []
        for c in range(cols + 1):
            u = c / cols
            y = shift + (u * 2.0 - 1.0) * half
            for side in (1, -1):
                ray = 0.5 + 0.5 * math.cos(u * cols * math.pi / 3.0)
                t = FIN_T * (1.0 - 0.7 * v) * (0.6 + 0.4 * ray) * math.sin(math.pi * min(max(u, 0.02), 0.98))
                row.append(len(verts))
                verts.append((side * t, y, z))
        grid.append(row)
    w = 2 * (cols + 1)
    for r in range(rows):
        a, b = grid[r], grid[r + 1]
        for c in range(cols):
            for s in (0, 1):
                i0, i1 = a[2 * c + s], a[2 * (c + 1) + s]
                j0, j1 = b[2 * c + s], b[2 * (c + 1) + s]
                faces.append((i0, i1, j1, j0) if s == 0 else (i0, j0, j1, i1))
        # close the leading and trailing edges
        faces.append((a[0], b[0], b[1], a[1]))
        faces.append((a[w - 2], a[w - 1], b[w - 1], b[w - 2]))
    top = grid[rows]
    for c in range(cols):
        faces.append((top[2 * c], top[2 * (c + 1)], top[2 * (c + 1) + 1], top[2 * c + 1]))
    bottom = grid[0]
    for c in range(cols):
        faces.append((bottom[2 * c], bottom[2 * c + 1], bottom[2 * (c + 1) + 1], bottom[2 * (c + 1)]))
    sh = sf.Shader("M_FinMembraneProc")
    rays = sh.math("ABSOLUTE", sh.math("SINE", sh.math("MULTIPLY", sh.axis("Y"), 95.0)))
    vein = sh.noise(180.0, 2.0, vector=mp._stretched(sh, (1.0, 6.0, 0.6)))
    hgt = sh.math("ADD", sh.math("MULTIPLY", sh.remap(rays, 0.85, 1.0), 0.8), sh.math("MULTIPLY", vein, 0.2))
    sh.bump(hgt, 0.4, 0.001)
    mat = sh.out(_grey(sh, sh.math("SUBTRACT", 1.0, sh.math("MULTIPLY", hgt, 0.25)), 0.75), 0.45)
    fin = bc.mesh_object("Fin", verts, faces, [mat], fix_normals=True)
    mat.name = "M_FinMembrane"
    # A light reduction only: the fin is flat, so a normal tolerance collapses it, and H3_Ripple needs its rows.
    baked = _bake([fin], "PartFin", {"M_FinMembrane": sf.tint(_lin("#C8B8D8"))}, tolerance=0.00005)
    pts = _check_pivot("fin", FIN_SINK)
    foot = _footprint(pts)

    def height(co):
        if co.z > 0:
            co.z *= 1.5
            co.y -= 0.04 * (co.z / (FIN_H * 1.5)) ** 1.5
        return co

    def sweep(co):
        if co.z > 0:
            co.y -= 0.12 * (co.z / FIN_H) ** 1.2
        return co

    def ripple(co):
        if co.z > 0:
            k = (co.z / FIN_H)
            co.x += 0.025 * k * math.sin(co.y * 60.0)
        return co

    handles = _shape_keys(fin, [("H1_Height", height, "the fin 50% taller"),
                                ("H2_Sweep", sweep, "the fin raked a further 0.12 m toward the tail at its tip"),
                                ("H3_Ripple", ripple, "a wave along the fin, for swimming")])
    rules = _rules("fin", round(foot, 3), FIN_SINK, "normal", ["spine", "limb"], 30, 50)
    rules["handles"] = handles
    return {"purpose": "Creature fin part (PROPOSED): a ray-stiffened membrane fin swept toward the tail, taking the creature's paint.",
            "category": "part", "part_type": "fin", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_FinMembrane": 0.9}, "revision": 1, **baked}


# --- Foot -------------------------------------------------------------------------------------

FOOT_LEN = 0.13
FOOT_W = 0.08
ANKLE_H = 0.07


def build_foot():
    """A padded three-toed foot standing on its sole (orientation "ground": +Z body up, toes toward the head,
    the sole on the pivot). Toes end in blunt horn nails; the ankle rises to meet the limb.
    H1_Spread splays the toes, H2_Long lengthens them."""
    objs = []
    # Palm: a squashed sphere, flat on the sole.
    unit, faces = bc.icosphere(3)
    palm_c = Vector((0.0, 0.0, 0.03))
    palm_v = []
    for co in unit:
        n = Vector(co).normalized()
        p = palm_c + Vector((n.x * FOOT_W * 0.5, n.y * FOOT_LEN * 0.32, n.z * 0.035))
        p.z = max(p.z, 0.002 + 0.004 * (n.x * n.x))
        palm_v.append(tuple(p))
    # Ankle: a tapered column from the palm up to the limb.
    # Swept from the top down, so the sweep's capped start closes the ankle where it meets the limb.
    ankle_v, ankle_f = mp._sweep([Vector((0.0, -0.01, 0.02 + ANKLE_H * t)) for t in (1.0, 0.66, 0.33, 0.0)],
                                 lambda i, a: 0.018 + 0.004 * i, 20)
    verts, fcs = list(palm_v), list(faces)
    bc.append(verts, fcs, ankle_v, ankle_f)
    toes = []
    for k, ang in enumerate((-28.0, 0.0, 28.0)):
        d = Vector((math.sin(math.radians(ang)), math.cos(math.radians(ang)), 0.0))
        start = palm_c + d * FOOT_LEN * 0.22
        path = [start + d * (FOOT_LEN * 0.4 * t) + Vector((0, 0, -0.012 * t)) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
        tv, tf = mp._sweep(path, lambda i, a: 0.017 * (1.0 - 0.18 * i) if i < 4 else 0.0, 16)
        bc.append(verts, fcs, tv, tf)
        toes.append((path[-1], d))
    for p in verts:
        pass
    verts = [(x, y, max(z, 0.0)) for x, y, z in verts]
    skin_sh = sf.Shader("M_FootSkinProc")
    pebble = skin_sh.remap(skin_sh.voronoi(220.0, 0.8), 0.25, 0.05)
    skin_sh.bump(skin_sh.math("SUBTRACT", 0.0, pebble), 0.35, 0.001)
    skin_mat = skin_sh.out(_grey(skin_sh, skin_sh.math("SUBTRACT", 1.0, skin_sh.math("MULTIPLY", pebble, 0.35)), 0.75), 0.7)
    foot = bc.mesh_object("Foot", verts, fcs, [skin_mat])
    skin_mat.name = "M_FootSkin"
    objs.append(foot)
    nail_sh = sf.Shader("M_FootNailProc")
    ns = nail_sh.noise(90.0, 3.0, vector=mp._stretched(nail_sh, (0.4, 5.0, 5.0)))
    nail_sh.bump(ns, 0.2, 0.001)
    nail_mat = nail_sh.out(_grey(nail_sh, nail_sh.remap(ns, 0.3, 0.7), 0.8), 0.3)
    nail_mat.name = "M_FootNail"
    for i, (tip, d) in enumerate(toes):
        prof = [(0.0, 0.0), (0.004, 0.012), (0.014, 0.011), (0.026, 0.0)]
        nv, nf, _ = bc.revolve(prof, 14)
        rot = Vector((0.0, 1.0, 0.0)).rotation_difference(d)
        nv = [tuple(tip - d * 0.004 + Vector((0.0, 0.0, 0.004)) + rot @ Vector(v)) for v in nv]
        nv = [(x, y, max(z, 0.0)) for x, y, z in nv]
        objs.append(bc.mesh_object(f"Nail{i}", nv, nf, [nail_mat], parent=foot))
    baked = _bake(objs, "PartFoot", {"M_FootSkin": sf.tint(_lin("#B89A80")), "M_FootNail": sf.tint(_lin("#5A4A3C"))})
    pts = _check_pivot("foot", 0.0, ground=True)
    reach = max(math.hypot(p.x, p.y) for p in pts)

    def spread(co, nail_dir=None):
        if co.y > 0.02:
            a = math.radians(14.0) * (co.x / max(abs(co.x), 1e-6)) * min(1.0, abs(co.x) / 0.02)
            return Matrix.Rotation(-a, 3, "Z") @ co
        return co

    def longer(co):
        if co.y > 0.02:
            co.y = 0.02 + (co.y - 0.02) * 1.35
        return co

    handles = []
    for o in objs:
        handles = _shape_keys(o, [("H1_Spread", spread, "toes splayed a further 14 degrees"),
                                  ("H2_Long", longer, "toes 35% longer")])
    rules = _rules("foot", round(reach, 3), 0.0, "ground", ["limb_end"], 25, 15)
    rules["handles"] = handles
    rules["pivot_note"] = "Ground part: the sole sits on the pivot; the ankle top (z %.2f m) meets the limb tip." % (ANKLE_H + 0.02)
    return {"purpose": "Creature foot part (PROPOSED): a padded three-toed foot with blunt horn nails, standing on its sole.",
            "category": "part", "part_type": "foot", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_FootSkin": 0.85, "M_FootNail": 0.0}, "revision": 1, **baked}


# --- Horn -------------------------------------------------------------------------------------

HORN_LEN = 0.17
HORN_R = 0.03
HORN_SINK = 0.02


def build_horn():
    """A ridged horn curving out to the right (+X) and back: chiral, so the runtime mirrors it for the left.
    H1_Length lengthens it, H2_Curl curls it further."""
    steps = 20
    path = []
    for i in range(steps + 1):
        t = i / steps
        a = 0.9 * t
        path.append(Vector((0.05 * (1 - math.cos(a)) * 1.6, -0.06 * t ** 2, -0.015 + (HORN_LEN + 0.015) * math.sin(a) / math.sin(0.9))))
    verts, faces = mp._sweep(path, lambda i, a: HORN_R * (1.0 - i / steps) ** 0.9 * (1.0 + 0.06 * math.cos(3 * a)) if i < steps else 0.0, 24)
    sh = sf.Shader("M_HornProc")
    rings = sh.math("SINE", sh.math("MULTIPLY", sh.axis("Z"), 300.0))
    streak = sh.noise(80.0, 3.0, vector=mp._stretched(sh, (5.0, 5.0, 0.3)))
    h = sh.math("ADD", sh.math("MULTIPLY", rings, 0.3), streak)
    sh.bump(h, 0.35, 0.0015)
    mat = sh.out(_grey(sh, sh.remap(h, -0.1, 0.9), 0.7), 0.35)
    horn = bc.mesh_object("Horn", verts, faces, [mat])
    mat.name = "M_Horn"
    baked = _bake([horn], "PartHorn", {"M_Horn": sf.tint(_lin("#D9C9A3"))})
    pts = _check_pivot("horn", HORN_SINK)
    foot = _footprint(pts)
    mp._check(sum(p.x for p in pts) > 0, "horn: curls toward +X (the right-hand side ships)")

    def length(co):
        if co.z > 0:
            co = co * 1.0
            co.z *= 1.4
            co.x *= 1.25
        return co

    def curl(co):
        if co.z > 0:
            k = co.z / HORN_LEN
            co.x += 0.05 * k ** 2
            co.z -= 0.03 * k ** 3
        return co

    handles = _shape_keys(horn, [("H1_Length", length, "the horn 40% longer"),
                                 ("H2_Curl", curl, "the tip curled further out and down")])
    rules = _rules("horn", round(foot, 3), HORN_SINK, "normal", ["spine", "part"], 60, 40, centerline="forbidden", chiral=True)
    rules["handles"] = handles
    return {"purpose": "Creature horn part (PROPOSED): a ridged horn curving out and back, right-hand side (mirrored at bake for the left).",
            "category": "part", "part_type": "horn", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_Horn": 0.15}, "revision": 1, **baked}


# --- Claw -------------------------------------------------------------------------------------

CLAW_LEN = 0.12
CLAW_R = 0.022


def build_claw():
    """A hooked sickle claw on a padded sheath, curving forward (+Y) and in toward the body's midline
    (-X): chiral, so the runtime mirrors it for the left. H1_Length lengthens it, H2_Hook curls the tip."""
    steps = 18
    path = []
    for i in range(steps + 1):
        t = i / steps
        a = 1.1 * t
        path.append(Vector((-0.012 * t * t, 0.06 * (1 - math.cos(a)) / (1 - math.cos(1.1)), -0.015 + (CLAW_LEN + 0.015) * math.sin(a) / math.sin(1.1))))
    verts, faces, face_ring = _tube(path, lambda i, a: 0.0 if i == steps else CLAW_R * (1.0 - i / steps) ** 0.8 * (1.0 + 0.25 * max(0.0, -math.sin(a)) ** 2), 18)
    face_materials = [0 if r < 2 else 1 for r in face_ring]     # the sheath is the first two rings
    sheath = sf.Shader("M_ClawSheathProc")
    wr = sheath.noise(160.0, 3.0)
    sheath.bump(wr, 0.3, 0.0008)
    horn = sf.Shader("M_ClawProc")
    streak = horn.noise(70.0, 3.0, vector=mp._stretched(horn, (5.0, 5.0, 0.3)))
    horn.bump(streak, 0.25, 0.001)
    mats = [sheath.out(_grey(sheath, sheath.remap(wr, 0.3, 0.7), 0.8), 0.6),
            horn.out(_grey(horn, horn.remap(streak, 0.25, 0.75), 0.65), 0.25)]
    claw = bc.mesh_object("Claw", verts, faces, mats, face_materials)
    mats[0].name, mats[1].name = "M_ClawSheath", "M_Claw"
    baked = _bake([claw], "PartClaw", {"M_ClawSheath": sf.tint(_lin("#B48E78")), "M_Claw": sf.tint(_lin("#4A3C34"))})
    pts = _check_pivot("claw", 0.02)
    foot = _footprint(pts)
    mp._check(sum(p.x for p in pts) < 0, "claw: curls in toward the midline (-X on the right-hand piece)")

    def length(co):
        if co.z > 0.01:
            co.z = 0.01 + (co.z - 0.01) * 1.4
            co.y *= 1.3
        return co

    def hook(co):
        k = max(0.0, co.z) / CLAW_LEN
        co.y += 0.04 * k ** 3
        co.z -= 0.02 * k ** 3
        return co

    handles = _shape_keys(claw, [("H1_Length", length, "the claw 40% longer"), ("H2_Hook", hook, "the tip hooked further forward and down")])
    rules = _rules("claw", round(foot, 3), 0.02, "normal", ["limb_end", "limb"], 30, 30, centerline="forbidden", chiral=True)
    rules["handles"] = handles
    return {"purpose": "Creature claw part (PROPOSED): a dark hooked sickle claw on a padded sheath, right-hand piece (mirrored at bake for the left).",
            "category": "part", "part_type": "claw", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_ClawSheath": 0.8, "M_Claw": 0.0}, "revision": 1, **baked}


# --- Hand -------------------------------------------------------------------------------------

FINGER_T = (0.0, 0.2, 0.4, 0.55, 0.7, 0.82, 0.91, 0.97, 1.0)


def _finger_r(t, r0):
    """A finger's radius along its length: two knuckle swells, then a rounded (not pointed) pad at the tip."""
    r = r0 * (1.0 - 0.25 * t) * (1.0 + 0.12 * math.exp(-((t - 0.45) / 0.07) ** 2) + 0.1 * math.exp(-((t - 0.72) / 0.06) ** 2))
    if t > 0.8:
        r *= math.sqrt(max(0.0, 1.0 - ((t - 0.8) / 0.2) ** 2))
    return r


def build_hand():
    """A three-fingered grasping hand with an opposed thumb, palm on the pivot along the limb axis (+Z out).
    H1_Grip curls the fingers and thumb closed; H2_Spread fans them."""
    unit, faces = bc.icosphere(3)
    palm = [tuple(Vector((n.x * 0.04, n.y * 0.025, 0.035 + n.z * 0.038))) for n in (Vector(co).normalized() for co in unit)]
    verts, fcs = list(palm), list(faces)
    wv, wf = mp._sweep([Vector((0, 0, z)) for z in (0.0, -0.01, -0.02)], lambda i, a: 0.026 + 0.003 * i, 16)
    bc.append(verts, fcs, wv, wf)
    fingers = [(-0.024, 0.0, 0.06), (0.0, 0.0, 0.065), (0.024, 0.0, 0.06)]
    for fx, fy, fz in fingers:
        base = Vector((fx, fy, fz))
        path = [base + Vector((fx * 0.3 * t, 0.012 * t * t, 0.07 * t)) for t in FINGER_T]
        v, f, _ = _tube(path, lambda i, a: _finger_r(FINGER_T[i], 0.011), 12)
        bc.append(verts, fcs, v, f)
    tpath = [Vector((0.035, 0.012, 0.03)) + Vector((0.035 * t, 0.02 * t, 0.025 * t)) for t in FINGER_T]
    v, f, _ = _tube(tpath, lambda i, a: _finger_r(FINGER_T[i], 0.012), 12)
    bc.append(verts, fcs, v, f)
    sh = sf.Shader("M_HandSkinProc")
    creases = sh.remap(sh.voronoi(140.0, 0.7, feature="DISTANCE_TO_EDGE"), 0.0, 0.05)
    sh.bump(creases, 0.3, 0.0008)
    mat = sh.out(_grey(sh, sh.math("ADD", 0.7, sh.math("MULTIPLY", creases, 0.3)), 0.8), 0.6)
    hand = bc.mesh_object("Hand", verts, fcs, [mat])
    mat.name = "M_HandSkin"
    baked = _bake([hand], "PartHand", {"M_HandSkin": sf.tint(_lin("#C4A088"))})
    pts = _check_pivot("hand", 0.025)
    foot = _footprint(pts, z_max=0.02)

    def grip(co):
        if co.z > 0.06:
            k = (co.z - 0.06) / 0.07
            ang = math.radians(80.0) * k
            dz = co.z - 0.06
            return Vector((co.x, co.y + dz * math.sin(ang), 0.06 + dz * math.cos(ang)))
        if co.x > 0.035:      # the thumb folds across
            return Vector((co.x - 0.02 * (co.x - 0.035) / 0.035, co.y + 0.01, co.z))
        return co

    def spread(co):
        if co.z > 0.06:
            co.x *= 1.0 + 0.6 * (co.z - 0.06) / 0.07
        return co

    handles = _shape_keys(hand, [("H1_Grip", grip, "fingers curl 80 degrees closed, the thumb folds across"),
                                 ("H2_Spread", spread, "fingers fan 60% wider at the tips")])
    rules = _rules("hand", round(foot, 3), 0.025, "normal", ["limb_end"], 40, 40)
    rules["handles"] = handles
    rules["capabilities"] = ["grasper"]
    return {"purpose": "Creature hand part (PROPOSED): a three-fingered grasping hand with an opposed thumb; grips on a shape key.",
            "category": "part", "part_type": "hand", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_HandSkin": 0.85}, "revision": 1, **baked}


# --- Crest ------------------------------------------------------------------------------------

CREST_LEN = 0.3
CREST_H = 0.12


def build_crest():
    """A dorsal crest of five webbed spines along the spine (Y), on the midline. H1_Raise lifts it,
    H2_Fold lays the spines back toward the tail."""
    verts, fcs = [], []
    spines = 5
    tips = []
    for k in range(spines):
        t = k / (spines - 1)
        y = CREST_LEN * (0.5 - t)
        h = CREST_H * (0.55 + 0.45 * math.sin(math.pi * (0.25 + 0.6 * t)))
        path = [Vector((0.0, y - 0.03 * u * u, -0.015 + (h + 0.015) * u)) for u in (0.0, 0.25, 0.5, 0.75, 1.0)]
        v, f = mp._sweep(path, lambda i, a: 0.0 if i == 4 else 0.009 * (1.0 - 0.2 * i), 10)
        bc.append(verts, fcs, v, f)
        tips.append(path)
    # The web: a thin double-sided membrane between neighbouring spines, scalloped down between the tips.
    cols, rows = 6, 6
    for k in range(spines - 1):
        grid = []
        for c in range(cols + 1):
            sc = c / cols
            top = 0.82 - 0.32 * math.sin(math.pi * sc)
            col = []
            for r in range(rows + 1):
                u = r / rows * top
                pa = tips[k][0].lerp(tips[k][-1], u)
                pb = tips[k + 1][0].lerp(tips[k + 1][-1], u)
                p = pa.lerp(pb, sc)
                p.y -= 0.03 * u * u
                col.append((len(verts), len(verts) + 1))
                verts.append((0.0025, p.y, p.z))
                verts.append((-0.0025, p.y, p.z))
            grid.append(col)
        for c in range(cols):
            for r in range(rows):
                a, b, d, e = grid[c][r], grid[c + 1][r], grid[c][r + 1], grid[c + 1][r + 1]
                fcs.append((a[0], d[0], e[0], b[0]))     # +X side, facing +X (columns run toward -Y, rows up +Z)
                fcs.append((a[1], b[1], e[1], d[1]))     # -X side, facing -X
    sh = sf.Shader("M_CrestProc")
    veins = sh.noise(60.0, 3.0, vector=mp._stretched(sh, (1.0, 0.6, 5.0)))
    sh.bump(veins, 0.25, 0.0008)
    mat = sh.out(_grey(sh, sh.remap(veins, 0.2, 0.8), 0.75), 0.45)
    crest = bc.mesh_object("Crest", verts, fcs, [mat], fix_normals=False)
    mat.name = "M_Crest"
    baked = _bake([crest], "PartCrest", {"M_Crest": sf.tint(_lin("#C77F5A"))}, tolerance=0.0002)
    pts = _check_pivot("crest", 0.02)
    foot = max(abs(p.y) for p in pts if p.z <= 0.01)

    def raise_(co):
        if co.z > 0:
            co.z *= 1.45
        return co

    def fold(co):
        if co.z > 0:
            k = co.z / CREST_H
            co.y -= 0.08 * k
            co.z *= 1.0 - 0.45 * k
        return co

    handles = _shape_keys(crest, [("H1_Raise", raise_, "spines 45% taller"), ("H2_Fold", fold, "spines laid back toward the tail")])
    rules = _rules("crest", round(foot, 3), 0.02, "normal", ["spine"], 10, 15, centerline="required")
    rules["handles"] = handles
    return {"purpose": "Creature crest part (PROPOSED): a dorsal crest of five webbed spines on the midline that raises or folds on shape keys; takes the creature's paint.",
            "category": "part", "part_type": "crest", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_Crest": 0.75}, "revision": 1, **baked}


# --- Tail fluke --------------------------------------------------------------------------------

def build_tail_fluke():
    """A crescent tail fluke for the spine's tail cap: +Z out along the spine (the cap's normal), the blade
    spreading across X. H1_Span widens it, H2_Beat bends it for the swim stroke."""
    cols, rows = 24, 6
    span = 0.17
    verts, fcs, grid = [], [], []
    for r in range(rows + 1):
        v = r / rows
        row = []
        for c in range(cols + 1):
            u = c / cols * 2.0 - 1.0
            x = span * u
            lead = -0.015 + 0.12 * abs(u) ** 1.8                       # the leading edge sweeps out to the tips
            trail = 0.07 + 0.05 * u * u - 0.012 * math.exp(-(u / 0.08) ** 2)   # crescent, notched at the middle
            z = lead + v * (trail - lead)
            t = 0.012 * (1.0 - abs(u) ** 2) * math.sin(math.pi * max(0.05, min(0.95, v)))
            for side in (t, -t):
                row.append(len(verts))
                verts.append((x, side, z))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            for s in (0, 1):
                a, b = grid[r][2 * c + s], grid[r][2 * (c + 1) + s]
                d, e = grid[r + 1][2 * c + s], grid[r + 1][2 * (c + 1) + s]
                fcs.append((a, b, e, d) if s == 0 else (a, d, e, b))
    sh = sf.Shader("M_FlukeProc")
    rays = sh.math("ABSOLUTE", sh.math("SINE", sh.math("MULTIPLY", sh.axis("X"), 120.0)))
    sh.bump(sh.remap(rays, 0.85, 1.0), 0.3, 0.0008)
    mat = sh.out(_grey(sh, sh.math("SUBTRACT", 1.0, sh.math("MULTIPLY", sh.remap(rays, 0.85, 1.0), 0.2)), 0.8), 0.4)
    fluke = bc.mesh_object("TailFluke", verts, fcs, [mat], fix_normals=True)
    mat.name = "M_Fluke"
    baked = _bake([fluke], "PartTailFluke", {"M_Fluke": sf.tint(_lin("#9FB4CC"))}, tolerance=0.0002)
    pts = _check_pivot("tail_fluke", 0.015)
    foot = max(abs(p.x) for p in pts if p.z <= 0.01)

    def span_(co):
        co.x *= 1.35
        return co

    def beat(co):
        k = max(0.0, co.z) / 0.15
        co.y += 0.05 * k * k
        return co

    handles = _shape_keys(fluke, [("H1_Span", span_, "the blade 35% wider"), ("H2_Beat", beat, "the blade bent for the swim stroke")])
    rules = _rules("tail_fluke", round(foot, 3), 0.015, "normal", ["spine"], 15, 20, centerline="required")
    rules["handles"] = handles
    rules["placement_note"] = "Meant for the tail cap (spine_u = 1); the blade spreads across the body's x."
    return {"purpose": "Creature tail fluke part (PROPOSED): a ray-stiffened crescent fluke for the tail cap that beats on a shape key.",
            "category": "part", "part_type": "tail_fluke", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_Fluke": 0.9}, "revision": 1, **baked}


# asset id -> (builder, triangle budget): contract section 1.4 (small 400, medium 1200, large 2500).
ASSETS = {
    "cpart_beak": (build_beak, 1200),
    "cpart_eye": (build_eye, 1200),
    "cpart_fin": (build_fin, 1200),
    "cpart_foot": (build_foot, 2500),
    "cpart_horn": (build_horn, 1200),
    "cpart_claw": (build_claw, 1200),
    "cpart_hand": (build_hand, 2500),
    "cpart_crest": (build_crest, 1200),
    "cpart_tail_fluke": (build_tail_fluke, 1200),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the creature parts.")
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
