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


# What each part is for, so the editor can group its palette and the stats can count eyes and mouths without a
# list of types (PROPOSED; contract section 1.3): eye, mouth, hand (graspers), foot, weapon or detail.
ROLE = {
    "eye": "eye", "eye_stalk": "eye", "compound_eye": "eye", "eye_slit": "eye", "eye_round": "eye", "eye_cluster": "eye",
    "beak": "mouth", "mandibles": "mouth", "maw": "mouth", "proboscis": "mouth", "jaw": "mouth", "bill": "mouth",
    "hand": "hand", "hand_paw": "hand", "hand_pincer": "hand", "hand_tentacle": "hand",
    "foot": "foot", "hoof": "foot", "flipper": "foot", "foot_webbed": "foot", "foot_paw": "foot", "foot_talon": "foot",
    "claw": "weapon", "horn": "weapon", "tusk": "weapon", "tail_spikes": "weapon", "club_tail": "weapon", "quills": "weapon",
    "claw_scythe": "weapon", "claw_rake": "weapon", "horn_ram": "weapon", "horn_nose": "weapon", "spike": "weapon",
    "fin": "detail", "crest": "detail", "tail_fluke": "detail", "wing": "detail", "antenna": "detail", "frill": "detail",
    "gill_fan": "detail", "lure": "detail", "barbels": "detail",
}


def _rules(part_type, footprint, sink, orientation, hosts, turn, tilt, centerline="allowed", chiral=False):
    return {"type": part_type, "footprint_radius_m": footprint, "sink_depth_m": sink, "chiral": chiral,
            "orientation": orientation, "turn_limit_deg": turn, "tilt_limit_deg": tilt,
            "centerline": centerline, "hosts": hosts, "role": ROLE[part_type]}


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


# --- Shared: a double-sided membrane patch ---------------------------------------------------------

def _membrane(verts, fcs, point, cols, rows, thickness=0.0015, facing=Vector((1.0, 0.0, 0.0))):
    """Two thin layers of a patch point(s, c) (s, c in [0, 1]), offset along `facing` (the patch normal)
    by +-thickness, each wound to face away from the other. Returns the face indices added."""
    grid = [[point(r / rows, c / cols) for c in range(cols + 1)] for r in range(rows + 1)]
    added = []
    for sign in (1.0, -1.0):
        base = len(verts)
        for row in grid:
            for p in row:
                verts.append(tuple(p + facing * (sign * thickness)))
        w = cols + 1
        for r in range(rows):
            for c in range(cols):
                a, b, d, e = base + r * w + c, base + r * w + c + 1, base + (r + 1) * w + c, base + (r + 1) * w + c + 1
                quad = (a, b, e, d)
                n = (Vector(verts[b]) - Vector(verts[a])).cross(Vector(verts[d]) - Vector(verts[a]))
                if n.length > 1e-12 and n.dot(facing) * sign < 0:
                    quad = (a, d, e, b)
                fcs.append(quad)
                added.append(len(fcs) - 1)
    return added


# --- Wing -------------------------------------------------------------------------------------------

WING_SPAN = 0.34
WING_SINK = 0.015


def build_wing():
    """A bat-like membrane wing in the skin's YZ plane: an arm bone out along +Z to the wrist, three finger
    struts fanning back toward the tail, and a scalloped membrane between them and the body. Chiral: the
    right-hand piece cups toward -X. H1_Fold furls the fingers back, H2_Flap bends the outer wing toward -X."""
    root, body_trail = Vector((0.0, 0.03, -WING_SINK)), Vector((0.0, -0.11, -WING_SINK))
    wrist = Vector((0.0, 0.0, 0.16))
    tips = [Vector((0.0, -0.03, WING_SPAN)), Vector((0.0, -0.15, 0.29)), Vector((0.0, -0.22, 0.17))]
    verts, fcs = [], []
    face_mats = []

    def cup(p):
        # A gentle camber toward -X, deepest mid-membrane.
        d = (p - wrist).length
        return p + Vector((-0.02 * math.sin(min(1.0, d / 0.2) * math.pi), 0.0, 0.0))

    # Bones: the arm (root to wrist) and the three fingers (wrist to tip).
    def bone(a, b, r0, r1, bend):
        path = []
        for k in range(9):
            t = k / 8
            p = a.lerp(b, t)
            path.append(cup(p) + Vector((0.0, 0.0, 0.0)) + (b - a).cross(Vector((1.0, 0.0, 0.0))).normalized() * bend * math.sin(math.pi * t))
        v, f, _ = _tube(path, lambda i, ang: 0.0 if i == 8 else r0 + (r1 - r0) * i / 8 * (1.0 + 0.15 * math.exp(-((i - 4) / 1.2) ** 2)), 10)
        added = bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
        return path

    bone(root, wrist, 0.011, 0.008, 0.0)
    for tip in tips:
        bone(wrist, tip, 0.007, 0.003, 0.008)
    # Membrane: three fans from the wrist between neighbouring struts, plus the inner panel from the arm to
    # the last finger and back along the body. Free edges scallop in toward the bones.
    edges = [tips[0], tips[1], tips[2]]
    for k in range(2):
        a, b = edges[k], edges[k + 1]

        def fan(s, c, a=a, b=b):
            q = a.lerp(b, c)
            return cup(wrist + (q - wrist) * s * (1.0 - 0.2 * math.sin(math.pi * c) * s ** 2))
        _membrane(verts, fcs, fan, 8, 8)
    def inner(s, c):
        c = c * (1.0 - 0.22 * math.sin(math.pi * s) * c ** 2)    # the trailing edge scallops in
        top = wrist.lerp(tips[2], c)          # s = 1: from the wrist along the last finger
        bottom = root.lerp(body_trail, c)     # s = 0: along the body
        return cup(bottom.lerp(top, s))
    _membrane(verts, fcs, inner, 10, 10)
    face_mats.extend([0] * (len(fcs) - len(face_mats)))
    mem = sf.Shader("M_WingMembraneProc")
    veins = mem.remap(mem.voronoi(70.0, 0.9, feature="DISTANCE_TO_EDGE"), 0.0, 0.04)
    mem.bump(mem.math("SUBTRACT", 1.0, veins), 0.3, 0.0008)
    bonesh = sf.Shader("M_WingBoneProc")
    knob = bonesh.noise(120.0, 3.0)
    bonesh.bump(knob, 0.25, 0.0008)
    mats = [mem.out(_grey(mem, mem.math("ADD", 0.75, mem.math("MULTIPLY", veins, 0.25)), 0.7), 0.5),
            bonesh.out(_grey(bonesh, bonesh.remap(knob, 0.3, 0.7), 0.75), 0.5)]
    wing = bc.mesh_object("Wing", verts, fcs, mats, face_mats, fix_normals=False)
    mats[0].name, mats[1].name = "M_WingMembrane", "M_WingBone"
    baked = _bake([wing], "PartWing", {"M_WingMembrane": sf.tint(_lin("#B8A6C4")), "M_WingBone": sf.tint(_lin("#A08C84"))},
                  tolerance=0.00005)
    pts = _check_pivot("wing", WING_SINK + 0.012)
    foot = max(abs(p.y) for p in pts if p.z <= 0.01)
    mp._check(sum(p.x for p in pts) < 0, "wing: cups toward -X (the right-hand piece ships)")

    def fold(co):
        if co.z > 0.02:
            k = min(1.0, (co.z - 0.02) / 0.3)
            co.y -= 0.12 * k
            co.z -= 0.1 * k * k
        return co

    def flap(co):
        k = max(0.0, co.z) / WING_SPAN
        co.x -= 0.12 * k * k
        return co

    handles = _shape_keys(wing, [("H1_Fold", fold, "fingers furled back toward the tail"),
                                 ("H2_Flap", flap, "the outer wing bent toward -X for the downstroke")])
    rules = _rules("wing", round(foot, 3), WING_SINK + 0.012, "normal", ["spine", "limb"], 30, 40, centerline="forbidden", chiral=True)
    rules["handles"] = handles
    return {"purpose": "Creature wing part (PROPOSED): a membrane wing on an arm and three finger struts, right-hand piece (mirrored for the left).",
            "category": "part", "part_type": "wing", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_WingMembrane": 0.85, "M_WingBone": 0.5}, "revision": 1, **baked}


# --- Antenna ----------------------------------------------------------------------------------------

ANT_LEN = 0.24


def build_antenna():
    """A beaded feeler that rises from a socket, arcs forward (+Y) and out (+X), and ends in a sensory club.
    Chiral. H1_Length lengthens it, H2_Droop lets the tip sag toward the tail."""
    steps = 40
    path = []
    for i in range(steps + 1):
        t = i / steps
        a = 1.0 * t
        path.append(Vector((0.03 * t * t, 0.11 * (1 - math.cos(a)) / (1 - math.cos(1.0)), -0.012 + (ANT_LEN + 0.012) * math.sin(a) / math.sin(1.0))))

    def radius(i, a):
        t = i / steps
        if i == steps:
            return 0.0
        r = 0.0065 * (1.0 - 0.45 * t)
        r *= 1.0 + 0.18 * max(0.0, math.cos(t * 18 * math.pi)) ** 4      # beaded segments
        if t < 0.08:
            r *= 1.0 + 1.4 * (1.0 - t / 0.08)                             # the socket bulb
        if t > 0.82:
            r = 0.012 * math.sqrt(max(0.0, 1.0 - ((t - 0.91) / 0.09) ** 2))   # the club
        return r

    verts, faces, face_ring = _tube(path, radius, 12)
    face_mats = [1 if r >= int(0.82 * steps) else 0 for r in face_ring]
    stalk = sf.Shader("M_AntennaProc")
    rings = stalk.math("SINE", stalk.math("MULTIPLY", stalk.axis("Z"), 700.0))
    stalk.bump(rings, 0.2, 0.0006)
    club = sf.Shader("M_AntennaClubProc")
    pits = club.remap(club.voronoi(400.0, 0.8), 0.0, 0.4)
    club.bump(pits, 0.3, 0.0005)
    mats = [stalk.out(_grey(stalk, stalk.remap(rings, -1.0, 1.0), 0.8), 0.45),
            club.out(_grey(club, pits, 0.7), 0.4)]
    ant = bc.mesh_object("Antenna", verts, faces, mats, face_mats)
    mats[0].name, mats[1].name = "M_Antenna", "M_AntennaClub"
    baked = _bake([ant], "PartAntenna", {"M_Antenna": sf.tint(_lin("#8E7A6A")), "M_AntennaClub": sf.tint(_lin("#D7B56A"))},
                  tolerance=0.0002)
    pts = _check_pivot("antenna", 0.015)
    foot = _footprint(pts)
    mp._check(sum(p.x for p in pts) > 0, "antenna: arcs out toward +X (the right-hand piece ships)")

    def length(co):
        if co.z > 0:
            co.z *= 1.4
            co.y *= 1.3
        return co

    def droop(co):
        k = max(0.0, co.z) / ANT_LEN
        co.y -= 0.06 * k ** 3
        co.z -= 0.07 * k ** 3
        return co

    handles = _shape_keys(ant, [("H1_Length", length, "the feeler 40% longer"), ("H2_Droop", droop, "the tip sagged toward the tail")])
    rules = _rules("antenna", round(foot, 3), 0.015, "normal", ["spine"], 60, 50, centerline="forbidden", chiral=True)
    rules["handles"] = handles
    return {"purpose": "Creature antenna part (PROPOSED): a beaded feeler ending in a pitted sensory club, right-hand piece (mirrored for the left).",
            "category": "part", "part_type": "antenna", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_Antenna": 0.6, "M_AntennaClub": 0.1}, "revision": 1, **baked}


# --- Tail spikes ------------------------------------------------------------------------------------

def build_tail_spikes():
    """Four bony spikes splayed in two pairs from a horny pad, for the tail cap (+Z out along the spine).
    H1_Length lengthens them, H2_Splay spreads them wider."""
    unit, ufaces = bc.icosphere(3)
    pad = [(n.x * 0.05, n.y * 0.045, -0.02 + max(n.z, -0.2) * 0.035) for n in (Vector(co).normalized() for co in unit)]
    verts, fcs = list(pad), list(ufaces)
    face_mats = [0] * len(fcs)
    spikes = [(0.035, 0.0, 0.004, 55.0, 0.13), (-0.035, 0.0, 0.004, -55.0, 0.13),
              (0.02, 0.0, 0.03, 30.0, 0.1), (-0.02, 0.0, 0.03, -30.0, 0.1)]
    for sx, sy, sz, ang, length in spikes:
        d = Vector((math.sin(math.radians(ang)), 0.0, math.cos(math.radians(ang))))
        base = Vector((sx, sy, sz)) - d * 0.015
        path = [base + d * (length * t) + Vector((0.0, -0.02 * t * t, 0.01 * t * t)) for t in (0.0, 0.15, 0.3, 0.5, 0.7, 0.85, 1.0)]
        v, f, _ = _tube(path, lambda i, a: 0.0 if i == 6 else 0.016 * (1.0 - i / 6) ** 0.9 * (1.0 + 0.05 * math.cos(4 * a)), 14)
        bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
    pad_sh = sf.Shader("M_SpikePadProc")
    scutes = pad_sh.remap(pad_sh.voronoi(160.0, 0.8, feature="DISTANCE_TO_EDGE"), 0.0, 0.06)
    pad_sh.bump(scutes, 0.35, 0.0008)
    bone = sf.Shader("M_TailSpikeProc")
    streak = bone.noise(70.0, 3.0, vector=mp._stretched(bone, (5.0, 5.0, 0.3)))
    bone.bump(streak, 0.3, 0.001)
    mats = [pad_sh.out(_grey(pad_sh, pad_sh.math("ADD", 0.7, pad_sh.math("MULTIPLY", scutes, 0.3)), 0.75), 0.55),
            bone.out(_grey(bone, bone.remap(streak, 0.25, 0.75), 0.7), 0.3)]
    obj = bc.mesh_object("TailSpikes", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name = "M_SpikePad", "M_TailSpike"
    baked = _bake([obj], "PartTailSpikes", {"M_SpikePad": sf.tint(_lin("#9C8A7A")), "M_TailSpike": sf.tint(_lin("#E0D2B0"))})
    pts = _check_pivot("tail_spikes", 0.03)
    foot = _footprint(pts)

    def length(co):
        if co.z > 0.03 or abs(co.x) > 0.05:
            co.x *= 1.35
            co.z = 0.03 + (co.z - 0.03) * 1.35 if co.z > 0.03 else co.z
        return co

    def splay(co):
        if co.z > 0.0:
            k = co.z / 0.12
            co.x += 0.06 * k * (1 if co.x > 0 else -1)
            co.z -= 0.02 * k
        return co

    handles = _shape_keys(obj, [("H1_Length", length, "spikes 35% longer"), ("H2_Splay", splay, "spikes spread wider")])
    rules = _rules("tail_spikes", round(foot, 3), 0.03, "normal", ["spine"], 15, 20, centerline="required")
    rules["handles"] = handles
    rules["placement_note"] = "Meant for the tail cap (spine_u = 1); the pairs splay across the body's x."
    return {"purpose": "Creature tail weapon part (PROPOSED): two pairs of bony spikes splayed from a horny pad on the tail tip.",
            "category": "part", "part_type": "tail_spikes", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_SpikePad": 0.7, "M_TailSpike": 0.0}, "revision": 1, **baked}


# --- Mandibles (mouth) --------------------------------------------------------------------------------

MAND_LEN = 0.12


def build_mandibles():
    """A pincer mouth: a fleshy mouth collar with two curved horn jaws that meet at their tips across x,
    each with three inner teeth. H1_Open swings the jaws apart 28 degrees each, H2_Length lengthens them."""
    unit, ufaces = bc.icosphere(3)
    collar = [(n.x * 0.045, n.y * 0.04, -0.015 + max(n.z, -0.3) * 0.03) for n in (Vector(co).normalized() for co in unit)]
    verts, fcs = list(collar), list(ufaces)
    face_mats = [0] * len(fcs)
    for side in (1.0, -1.0):
        path = []
        for k in range(15):
            t = k / 14
            a = 1.3 * t
            path.append(Vector((side * (0.03 + 0.03 * math.sin(a) - 0.07 * t ** 2.2), 0.0, 0.0 + MAND_LEN * math.sin(a * 0.95) / math.sin(1.3 * 0.95))))
        v, f, _ = _tube(path, lambda i, a: 0.0 if i == 14 else 0.013 * (1.0 - i / 14) ** 0.7 * math.sqrt((1.0 * math.cos(a)) ** 2 + (0.7 * math.sin(a)) ** 2), 14)
        bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
        for t in (0.35, 0.55, 0.75):
            k = t * 14
            p = path[int(k)].lerp(path[min(14, int(k) + 1)], k - int(k))
            inward = Vector((-side, 0.0, 0.25)).normalized()
            tooth = [p + inward * (0.004 + 0.016 * u) for u in (0.0, 0.5, 1.0)]
            v, f, _ = _tube(tooth, lambda i, a: 0.0 if i == 2 else 0.005 * (1.0 - i / 2.0), 8)
            bc.append(verts, fcs, v, f)
            face_mats.extend([1] * (len(fcs) - len(face_mats)))
    flesh = sf.Shader("M_MandibleCollarProc")
    wr = flesh.noise(150.0, 3.0)
    flesh.bump(wr, 0.3, 0.0008)
    horn = sf.Shader("M_MandibleProc")
    streak = horn.noise(80.0, 3.0, vector=mp._stretched(horn, (5.0, 5.0, 0.3)))
    horn.bump(streak, 0.25, 0.001)
    mats = [flesh.out(_grey(flesh, flesh.remap(wr, 0.3, 0.7), 0.8), 0.6),
            horn.out(_grey(horn, horn.remap(streak, 0.25, 0.75), 0.6), 0.25)]
    obj = bc.mesh_object("Mandibles", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name = "M_MandibleCollar", "M_Mandible"
    baked = _bake([obj], "PartMandibles", {"M_MandibleCollar": sf.tint(_lin("#B98476")), "M_Mandible": sf.tint(_lin("#5A4438"))})
    pts = _check_pivot("mandibles", 0.03)
    foot = _footprint(pts)

    def open_(co):
        if co.z <= 0.005 or abs(co.x) < 0.01 and co.z < 0.02:
            return co
        side = 1.0 if co.x > 0 else -1.0
        hinge = Vector((side * 0.03, 0.0, 0.0))
        rot = Matrix.Rotation(math.radians(28.0) * side, 3, "Y") @ (co - hinge)
        return hinge + rot

    def length(co):
        if co.z > 0.01:
            co.z = 0.01 + (co.z - 0.01) * 1.4
        return co

    handles = _shape_keys(obj, [("H1_Open", open_, "jaws swung apart 28 degrees each about their roots"),
                                ("H2_Length", length, "jaws 40% longer")])
    rules = _rules("mandibles", round(foot, 3), 0.03, "forward_cone", ["spine"], 40, 30, centerline="required")
    rules["handles"] = handles
    return {"purpose": "Creature mouth part (PROPOSED): a pincer mouth of two toothed horn jaws on a fleshy collar, opening on a shape key.",
            "category": "part", "part_type": "mandibles", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_MandibleCollar": 0.8, "M_Mandible": 0.0}, "revision": 1, **baked}


# --- Eye stalk ----------------------------------------------------------------------------------

STALK_LEN = 0.11
STALK_EYE_R = 0.028
STALK_SINK = 0.02


def _eye_ball_material(name, centre, look):
    """The cpart_eye iris shader, with the pupil turned to look along `look` instead of +Z."""
    eye = sf.Shader(name)
    n = eye.vmath("NORMALIZE", eye.vmath("SUBTRACT", eye.pos, tuple(centre)))
    facing = eye.vmath("DOT_PRODUCT", n, tuple(look.normalized()))
    pupil = eye.remap(facing, 0.88, 0.9)
    iris = eye.remap(facing, 0.55, 0.59)
    fibres = eye.noise(160.0, 2.0, vector=mp._stretched(eye, (8.0, 8.0, 0.5)))
    base = eye.mix(iris, (0.92, 0.92, 0.9, 1.0), eye.mix(fibres, (0.55, 0.55, 0.55, 1.0), (0.8, 0.8, 0.8, 1.0)))
    base = eye.mix(pupil, base, (0.04, 0.04, 0.04, 1.0))
    eye.bump(eye.math("MULTIPLY", iris, fibres), 0.1, 0.0005)
    return eye.out(base, 0.08)


def build_eye_stalk():
    """An eyeball held up on a soft stalk that bows forward, cupped in a fleshy socket at the tip.
    H1_Length raises the eye on a longer stalk, H2_Droop bends the stalk forward and down."""
    cup_z = STALK_LEN - STALK_EYE_R * 0.9          # where the stalk opens into the socket
    centre = Vector((0.0, 0.018, STALK_LEN))
    path, radii = [], []
    for k in range(13):
        t = k / 12
        z = -STALK_SINK * 0.95 + (cup_z + STALK_SINK * 0.95) * t
        path.append(Vector((0.0, 0.018 * t * t, z)))      # starts square to the skin, bows forward
        flare = 0.012 * max(0.0, 1.0 - t / 0.22) ** 2             # a soft root where it meets the skin
        radii.append(0.0095 - 0.002 * t + flare)
    # The socket: rings that flare from the stalk out round the lower half of the ball and lip over its equator.
    for a in (-0.75, -0.45, -0.15, 0.1, 0.22):
        r = STALK_EYE_R * (math.cos(a * math.pi / 2) * 1.06 + 0.04)
        path.append(centre + Vector((0.0, 0.0, STALK_EYE_R * math.sin(a * math.pi / 2) * 1.02)))
        radii.append(r if a < 0.2 else STALK_EYE_R * 0.98)
    sverts, sfaces, _ = _tube(path, lambda i, a: radii[i] * (1.0 + 0.04 * math.cos(5 * a) * (i < 13)), 16)
    flesh = sf.Shader("M_EyeStalkProc")
    wr = flesh.noise(220.0, 3.0, vector=mp._stretched(flesh, (1.0, 1.0, 0.25)))
    pores = flesh.remap(flesh.voronoi(300.0, 0.6), 0.2, 0.05)
    flesh.bump(flesh.math("SUBTRACT", wr, flesh.math("MULTIPLY", pores, 0.5)), 0.3, 0.0008)
    stalk_mat = flesh.out(_grey(flesh, flesh.remap(wr, 0.25, 0.75), 0.75), 0.55)
    stalk = bc.mesh_object("EyeStalk", sverts, sfaces, [stalk_mat], fix_normals=False)
    stalk_mat.name = "M_EyeStalk"
    unit, faces = bc.icosphere(3)
    ball_mat = _eye_ball_material("M_EyeStalkBallProc", centre, Vector((0.0, 1.0, 0.35)))
    ball = bc.mesh_object("Eye", [tuple(centre + Vector(co).normalized() * STALK_EYE_R) for co in unit], faces, [ball_mat], parent=stalk)
    ball_mat.name = "M_EyeBall"
    baked = _bake([stalk, ball], "PartEyeStalk", {"M_EyeStalk": sf.tint(_lin("#B88E7E")), "M_EyeBall": sf.tint(_lin("#E8D7A0"))}, size=256)
    pts = _check_pivot("eye_stalk", STALK_SINK)
    foot = _footprint(pts)
    mp._check(max(p.z for p in pts) > STALK_LEN + STALK_EYE_R * 0.9, "eye_stalk: the ball crowns the stalk")

    def _k(co):
        return min(1.0, max(0.0, co.z - 0.01) / (cup_z - 0.01))

    def length(co):
        return Vector((co.x, co.y, co.z + 0.05 * _k(co)))

    def droop(co):
        return Matrix.Rotation(math.radians(-40.0) * _k(co), 3, "X") @ co

    handles = _shape_keys(stalk, [("H1_Length", length, "the eye raised 0.05 m on a longer stalk"),
                                  ("H2_Droop", droop, "the stalk bent 40 degrees forward and down")])
    _shape_keys(ball, [("H1_Length", length, ""), ("H2_Droop", droop, "")])
    rules = _rules("eye_stalk", round(foot, 3), STALK_SINK, "normal", ["spine", "part"], 60, 45)
    rules["handles"] = handles
    rules["handles_note"] = "Both keys are on EyeStalk and Eye with the same names; the runtime sets them together. Above the socket the ball moves rigidly."
    return {"purpose": "Creature eye part (PROPOSED): an eyeball on a soft stalk that bows forward, in a fleshy socket; the pupil looks forward.",
            "category": "part", "part_type": "eye_stalk", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_EyeStalk": 0.9, "M_EyeBall": 0.0}, "revision": 1, **baked}


# --- Compound eye -------------------------------------------------------------------------------

CEYE_R = 0.042
CEYE_H = 0.034
CEYE_SINK = 0.015


def build_compound_eye():
    """A faceted insect eye: a domed lens of near-hexagonal ommatidia in a fleshy rim.
    H1_Bulge raises the dome, H2_Wide spreads it across the head."""
    steps = 14
    profile = [(-CEYE_SINK * 0.95, CEYE_R * 0.96)]
    for i in range(steps + 1):
        a = 0.5 * math.pi * i / steps
        profile.append((CEYE_H * math.sin(a), CEYE_R * math.cos(a) if i < steps else 0.0))
    dv, df, _ = bc.revolve(profile, 40)
    lens = sf.Shader("M_CompoundLensProc")
    facets = lens.voronoi(400.0, 0.6, feature="DISTANCE_TO_EDGE")
    domes = lens.remap(facets, 0.0, 0.2)
    lens.bump(domes, 0.45, 0.0006)
    sheen = lens.noise(18.0, 2.0)
    base = lens.mix(lens.remap(facets, 0.0, 0.05), (0.35, 0.35, 0.35, 1.0), _grey(lens, lens.remap(sheen, 0.3, 0.7, 0.75, 1.0), 0.75))
    lens_mat = lens.out(base, 0.12)
    dome = bc.mesh_object("CompoundEye", _up(dv), df, [lens_mat])
    lens_mat.name = "M_CompoundLens"
    rim_profile = []
    for i in range(13):
        a = math.pi * i / 12
        rim_profile.append((-CEYE_SINK * 0.95 + (CEYE_SINK * 0.95 + 0.006) * (1 - math.cos(a)) / 2, CEYE_R * 1.0 + 0.006 + 0.007 * math.sin(a) - 0.005 * (i / 12) ** 2))
    rv, rf, _ = bc.revolve(rim_profile, 40)
    rim_sh = sf.Shader("M_CompoundRimProc")
    wr = rim_sh.noise(200.0, 3.0)
    rim_sh.bump(wr, 0.3, 0.0008)
    rim_mat = rim_sh.out(_grey(rim_sh, rim_sh.remap(wr, 0.3, 0.7), 0.75), 0.5)
    rim = bc.mesh_object("Rim", _up(rv), rf, [rim_mat], parent=dome, fix_normals=False)
    rim_mat.name = "M_CompoundRim"
    baked = _bake([dome, rim], "PartCompoundEye", {"M_CompoundLens": sf.tint(_lin("#4B3F63")), "M_CompoundRim": sf.tint(_lin("#7C6A5C"))}, size=512)
    pts = _check_pivot("compound_eye", CEYE_SINK)
    foot = _footprint(pts)

    def bulge(co):
        return Vector((co.x, co.y, co.z * 1.45 if co.z > 0 else co.z))

    def wide(co):
        k = 1.0 + 0.3 * min(1.0, max(0.0, co.z + CEYE_SINK) / CEYE_SINK)
        return Vector((co.x * k, co.y * k, co.z))

    handles = _shape_keys(dome, [("H1_Bulge", bulge, "the dome 45% taller"), ("H2_Wide", wide, "the eye 30% wider")])
    _shape_keys(rim, [("H1_Bulge", bulge, ""), ("H2_Wide", wide, "")])
    rules = _rules("compound_eye", round(foot, 3), CEYE_SINK, "forward_cone", ["spine", "part"], 70, 50)
    rules["handles"] = handles
    rules["handles_note"] = "Both keys are on CompoundEye and Rim with the same names; the runtime sets them together."
    return {"purpose": "Creature eye part (PROPOSED): a domed compound eye of near-hexagonal facets in a fleshy rim; dark violet lens.",
            "category": "part", "part_type": "compound_eye", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_CompoundLens": 0.0, "M_CompoundRim": 0.85}, "revision": 1, **baked}


# --- Maw (mouth) ----------------------------------------------------------------------------------

MAW_RX = 0.05
MAW_RY = 0.034
MAW_LIP = 0.012
MAW_SINK = 0.03
MAW_TEETH = 14


def build_maw():
    """A round toothed maw: thick rolled lips round a dark throat, ringed with inward-raking fangs.
    H1_Gape opens it 30% wider, H2_Fangs lengthens the teeth."""
    # Lips and throat: one sweep of rings round the mouth's oval, from the outer skin over the lip and down the throat.
    rings = []
    lip_steps = 12
    for i in range(lip_steps + 1):
        a = math.pi * i / lip_steps
        rings.append((1.0 + (MAW_LIP / MAW_RX) * math.cos(a) + 0.35 * (i == 0), 0.004 + MAW_LIP * math.sin(a) - MAW_SINK * 0.3 * (i == 0)))
    for i in range(1, 6):
        t = i / 5
        rings.append(((1.0 - MAW_LIP / MAW_RX) * (1.0 - 0.75 * t), 0.004 - (MAW_SINK - 0.002) * math.sin(t * math.pi / 2)))
    seg = 48
    verts, faces, face_mats = [], [], []
    ring_ix = []
    for scale, z in rings:
        ring_ix.append(list(range(len(verts), len(verts) + seg)))
        for j in range(seg):
            a = 2.0 * math.pi * j / seg
            verts.append((MAW_RX * scale * math.cos(a), MAW_RY * scale * math.sin(a) * (1.0 + 0.0 * scale), z))
    bottom = len(verts)
    verts.append((0.0, 0.0, -MAW_SINK + 0.002))
    for i in range(len(rings) - 1):
        for j in range(seg):
            k = (j + 1) % seg
            faces.append((ring_ix[i][j], ring_ix[i][k], ring_ix[i + 1][k], ring_ix[i + 1][j]))
            face_mats.append(0 if i < lip_steps else 1)
    for j in range(seg):
        faces.append((ring_ix[-1][j], ring_ix[-1][(j + 1) % seg], bottom))
        face_mats.append(1)
    lip_sh = sf.Shader("M_MawLipProc")
    wr = lip_sh.noise(180.0, 3.0, vector=mp._stretched(lip_sh, (1.0, 1.0, 3.0)))
    lip_sh.bump(wr, 0.35, 0.0008)
    throat = sf.Shader("M_MawThroatProc")
    folds = throat.noise(90.0, 2.0)
    throat.bump(folds, 0.4, 0.001)
    mats = [lip_sh.out(_grey(lip_sh, lip_sh.remap(wr, 0.3, 0.7), 0.75), 0.4),
            throat.out(_grey(throat, throat.remap(folds, 0.3, 0.7), 0.6), 0.3)]
    maw = bc.mesh_object("Maw", verts, faces, mats, face_mats, fix_normals=False)
    mats[0].name, mats[1].name = "M_MawLip", "M_MawThroat"
    # Teeth: cones rooted on the inner face of the lip, raking in toward the throat; long and short alternate.
    tverts, tfaces, roots = [], [], []
    for n in range(MAW_TEETH):
        a = 2.0 * math.pi * (n + 0.5) / MAW_TEETH
        rim = Vector((MAW_RX * math.cos(a), MAW_RY * math.sin(a), 0.0))
        inward = -Vector((rim.x / MAW_RX ** 2, rim.y / MAW_RY ** 2, 0.0)).normalized()
        root = rim * (1.0 - 0.75 * MAW_LIP / MAW_RX) + Vector((0.0, 0.0, 0.006))
        length = 0.024 if n % 2 == 0 else 0.015
        d = (inward + Vector((0.0, 0.0, 0.55))).normalized()
        path = [root - d * 0.004 + (inward * 0.25 * length * t * t) + d * (length * t) for t in (0.0, 0.35, 0.7, 1.0)]
        v, f, _ = _tube(path, lambda i, a, L=length: 0.0 if i == 3 else (0.0042 + 0.0016 * (L > 0.02)) * (1.0 - i / 3) ** 0.8, 8)
        bc.append(tverts, tfaces, v, f)
        roots.append(root)
    tooth_sh = sf.Shader("M_MawToothProc")
    streak = tooth_sh.noise(120.0, 3.0, vector=mp._stretched(tooth_sh, (4.0, 4.0, 0.4)))
    tooth_sh.bump(streak, 0.15, 0.0005)
    tooth_mat = tooth_sh.out(_grey(tooth_sh, tooth_sh.remap(streak, 0.2, 0.8, 0.8, 1.0), 0.8), 0.2)
    teeth = bc.mesh_object("Teeth", tverts, tfaces, [tooth_mat], parent=maw)
    tooth_mat.name = "M_MawTooth"
    baked = _bake([maw, teeth], "PartMaw", {"M_MawLip": sf.tint(_lin("#B07A72")), "M_MawThroat": sf.tint(_lin("#3A2834")),
                                            "M_MawTooth": sf.tint(_lin("#EDE3C8"))})
    pts = _check_pivot("maw", MAW_SINK)
    foot = _footprint(pts)

    def gape_k(co):
        return min(1.0, max(0.0, (co.z + MAW_SINK * 0.5) / (MAW_SINK * 0.5)))

    def gape(co):
        k = 1.0 + 0.3 * gape_k(co)
        return Vector((co.x * k, co.y * k, co.z))

    def nearest_root(co):
        return min(roots, key=lambda r: (r - co).length)

    def gape_tooth(co):
        r = nearest_root(co)
        return co + Vector((r.x, r.y, 0.0)) * 0.3

    def fangs(co):
        r = nearest_root(co)
        return r + (co - r) * 1.6

    handles = _shape_keys(maw, [("H1_Gape", gape, "the mouth 30% wider round its rim")])
    _shape_keys(teeth, [("H1_Gape", gape_tooth, ""), ("H2_Fangs", fangs, "the teeth 60% longer")])
    handles.append({"key": "H2_Fangs", "meaning": "the teeth 60% longer", "default_permille": 0})
    rules = _rules("maw", round(foot, 3), MAW_SINK, "forward_cone", ["spine"], 40, 30, centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = "H1 is on Maw and Teeth (the teeth ride the rim out); H2 is on Teeth only."
    return {"purpose": "Creature mouth part (PROPOSED): a round maw of rolled lips round a dark throat, ringed with fourteen inward-raking teeth.",
            "category": "part", "part_type": "maw", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_MawLip": 0.85, "M_MawThroat": 0.0, "M_MawTooth": 0.0}, "revision": 1, **baked}


# --- Quills -------------------------------------------------------------------------------------

QUILL_LEN = 0.17
QUILL_SINK = 0.02


def build_quills():
    """A patch of banded quills raked back from a bristled pad, like a porcupine's.
    H1_Raise stands them up, H2_Length lengthens them."""
    unit, ufaces = bc.icosphere(2)
    pad = [(n.x * 0.05, n.y * 0.06, -0.014 + max(n.z, -0.2) * 0.026) for n in (Vector(co).normalized() for co in unit)]
    verts, fcs = list(pad), list(ufaces)
    face_mats = [0] * len(fcs)
    spots = [(0.0, 0.03, 1.0), (-0.024, 0.012, 0.85), (0.024, 0.012, 0.85), (0.0, 0.0, 1.0), (-0.032, -0.014, 0.75),
             (0.032, -0.014, 0.75), (-0.012, -0.022, 0.95), (0.012, -0.022, 0.95), (0.0, -0.04, 0.8), (-0.02, 0.035, 0.7),
             (0.02, 0.035, 0.7)]
    for n, (sx, sy, size) in enumerate(spots):
        rake = math.radians(58.0 + 7.0 * math.sin(n * 2.3))
        fan = math.atan2(sx, 0.06) * 0.8
        d = Vector((math.sin(fan) * math.sin(rake), -math.cos(fan) * math.sin(rake), math.cos(rake)))
        length = QUILL_LEN * size
        base = Vector((sx, sy, -0.008))
        path = [base + d * (length * t) + Vector((0.0, -0.018 * t * t, -0.012 * t * t)) for t in (0.0, 0.25, 0.55, 0.8, 1.0)]
        v, f, _ = _tube(path, lambda i, a: 0.0 if i == 4 else 0.0042 * (1.0 - 0.15 * i) * (1.0 - (i / 4) ** 3), 6)
        bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
    pad_sh = sf.Shader("M_QuillPadProc")
    bristle = pad_sh.noise(260.0, 3.0, vector=mp._stretched(pad_sh, (1.0, 4.0, 1.0)))
    pad_sh.bump(bristle, 0.35, 0.0008)
    quill = sf.Shader("M_QuillProc")
    dist = quill.vmath("LENGTH", quill.pos)
    bands = quill.remap(quill.math("SINE", quill.math("MULTIPLY", dist, 95.0)), -0.2, 0.2)
    grain = quill.noise(140.0, 2.0, vector=mp._stretched(quill, (5.0, 5.0, 0.3)))
    quill.bump(grain, 0.15, 0.0004)
    qbase = quill.mix(bands, (0.32, 0.32, 0.32, 1.0), (0.95, 0.95, 0.93, 1.0))
    qbase = quill.mix(quill.remap(dist, 0.03, 0.06), (0.95, 0.95, 0.93, 1.0), qbase)
    mats = [pad_sh.out(_grey(pad_sh, pad_sh.remap(bristle, 0.3, 0.7), 0.7), 0.6), quill.out(qbase, 0.3)]
    obj = bc.mesh_object("Quills", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name = "M_QuillPad", "M_Quill"
    baked = _bake([obj], "PartQuills", {"M_QuillPad": sf.tint(_lin("#8A7868")), "M_Quill": sf.tint(_lin("#E6DCC4"))})
    pts = _check_pivot("quills", QUILL_SINK)
    foot = _footprint(pts)
    mp._check(sum(p.y for p in pts if p.z > 0.05) < 0, "quills: rake back toward the tail (-Y)")

    def raise_(co):
        if co.z <= 0.0:
            return co
        k = min(1.0, co.z / 0.03)
        return Matrix.Rotation(math.radians(38.0) * k, 3, "X") @ co

    def length(co):
        if co.z > 0.0:
            return Vector((co.x * 1.4, co.y * 1.4, co.z * 1.4))
        return co

    handles = _shape_keys(obj, [("H1_Raise", raise_, "the quills stood up 38 degrees"), ("H2_Length", length, "the quills 40% longer")])
    rules = _rules("quills", round(foot, 3), QUILL_SINK, "normal", ["spine"], 30, 20)
    rules["handles"] = handles
    rules["placement_note"] = "Rakes toward the tail (-Y); several patches along the back read as a coat."
    return {"purpose": "Creature defence part (PROPOSED): eleven banded quills raked back from a bristled pad.",
            "category": "part", "part_type": "quills", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_QuillPad": 0.8, "M_Quill": 0.25}, "revision": 1, **baked}


# --- Frill ------------------------------------------------------------------------------------------

FRILL_SPAN = 0.3
FRILL_H = 0.16
FRILL_LEAN = 25.0
FRILL_SINK = 0.02
FRILL_RIBS = 7


def build_frill():
    """A neck frill: seven knobbed horn ribs fanning from a fleshy pad in a semicircle across X and up,
    the fan leaning back toward the tail, with a scalloped double-sided web (the FrillWeb child) between
    the ribs. H1_Fold lays the fan down flat along the body toward the tail, H2_Span spreads it 35% wider."""
    lean = Matrix.Rotation(math.radians(FRILL_LEAN), 3, "X")       # +Z tilted toward -Y
    fwd = lean @ Vector((0.0, 1.0, 0.0))                            # the fan plane's normal, toward the head
    angles = [math.radians(15.0 + 150.0 * k / (FRILL_RIBS - 1)) for k in range(FRILL_RIBS)]
    tip_x = FRILL_SPAN / 2 / math.cos(angles[0])
    tip_z = FRILL_H / math.cos(math.radians(FRILL_LEAN))

    def fan_point(phi, t):
        """Angle phi round the fan (0 = +X, pi/2 = up) at fraction t of the rib length there; the rim
        cups a little toward the head."""
        length = tip_x + (tip_z - tip_x) * math.sin(phi) ** 2
        return lean @ (Vector((math.cos(phi), 0.0, math.sin(phi))) * (length * t)) + fwd * (0.01 * t * t)

    # The pad: a low flesh cushion over the pivot, flat underneath, that the rib roots and the web's inner
    # edge are buried in.
    unit, ufaces = bc.icosphere(2)
    verts = [(n.x * 0.06, n.y * 0.028 - 0.004, -0.009 + max(n.z, -0.42) * 0.0235) for n in (Vector(co).normalized() for co in unit)]
    fcs = list(ufaces)
    face_mats = [0] * len(fcs)
    # The ribs: knobbed tubes, thick at the root and pointed, every other ring swollen.
    rings = 13
    for phi in angles:
        path = [fan_point(phi, 0.04 + 0.96 * i / (rings - 1)) for i in range(rings)]
        v, f, _ = _tube(path, lambda i, a: 0.0 if i == rings - 1 else 0.0075 * (1.0 - 0.62 * i / (rings - 1)) * (1.0 + 0.15 * (i % 2)), 7)
        bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
    # The web: one double-sided panel between each pair of ribs, its free edge dipping between the tips
    # and the skin sagging back a little between the ribs.
    wverts, wfcs = [], []
    for k in range(FRILL_RIBS - 1):
        a, b = angles[k], angles[k + 1]

        def panel(s, c, a=a, b=b):
            top = 0.92 - 0.17 * math.sin(math.pi * c)
            return fan_point(a + (b - a) * c, 0.07 + (top - 0.07) * s) - fwd * (0.004 * math.sin(math.pi * c) * s)
        _membrane(wverts, wfcs, panel, 6, 5, facing=fwd)
    pad_sh = sf.Shader("M_FrillPadProc")
    wr = pad_sh.noise(200.0, 3.0, vector=mp._stretched(pad_sh, (1.0, 1.0, 0.3)))
    pores = pad_sh.remap(pad_sh.voronoi(320.0, 0.6), 0.2, 0.05)
    pad_sh.bump(pad_sh.math("SUBTRACT", wr, pad_sh.math("MULTIPLY", pores, 0.5)), 0.3, 0.0008)
    rib_sh = sf.Shader("M_FrillRibProc")
    knob = rib_sh.noise(120.0, 3.0)
    grain = rib_sh.noise(420.0, 2.0)
    rib_sh.bump(rib_sh.math("ADD", rib_sh.math("MULTIPLY", knob, 0.7), rib_sh.math("MULTIPLY", grain, 0.3)), 0.25, 0.0008)
    tipward = rib_sh.remap(rib_sh.vmath("LENGTH", rib_sh.pos), 0.1, 0.17)      # the horn darkens toward the points
    rib_base = rib_sh.mix(rib_sh.math("MULTIPLY", tipward, 0.35), _grey(rib_sh, rib_sh.remap(knob, 0.3, 0.7), 0.72), (0.45, 0.45, 0.45, 1.0))
    web_sh = sf.Shader("M_FrillWebProc")
    up = web_sh.math("ADD", web_sh.math("MULTIPLY", web_sh.axis("Z"), math.cos(math.radians(FRILL_LEAN))),
                     web_sh.math("MULTIPLY", web_sh.axis("Y"), -math.sin(math.radians(FRILL_LEAN))))
    veins = web_sh.remap(web_sh.math("ABSOLUTE", web_sh.math("SINE", web_sh.math("MULTIPLY", web_sh.math("ARCTAN2", web_sh.axis("X"), up), 36.0))), 0.92, 1.0)
    skin = web_sh.noise(180.0, 3.0)
    web_sh.bump(web_sh.math("ADD", web_sh.math("MULTIPLY", skin, 0.6), web_sh.math("MULTIPLY", veins, 0.4)), 0.3, 0.0008)
    web_base = _grey(web_sh, web_sh.math("SUBTRACT", web_sh.remap(skin, 0.25, 0.75), web_sh.math("MULTIPLY", veins, 0.35), clamp=True), 0.7)
    mats = [pad_sh.out(_grey(pad_sh, pad_sh.remap(wr, 0.25, 0.75), 0.75), 0.55), rib_sh.out(rib_base, 0.45)]
    frill = bc.mesh_object("Frill", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name = "M_FrillPad", "M_FrillRib"
    web_mat = web_sh.out(web_base, 0.5)
    web = bc.mesh_object("FrillWeb", wverts, wfcs, [web_mat], fix_normals=False, parent=frill)
    web_mat.name = "M_FrillWeb"
    baked = _bake([frill, web], "PartFrill", {"M_FrillPad": sf.tint(_lin("#9E7560")), "M_FrillRib": sf.tint(_lin("#CDB893")),
                                              "M_FrillWeb": sf.tint(_lin("#C8865E"))}, tolerance=0.0002)
    pts = _check_pivot("frill", FRILL_SINK)
    foot = _footprint(pts)
    mp._check(sum(p.y for p in pts if p.z > 0.05) < 0, "frill: leans back toward the tail (-Y)")
    mp._check(max(p.x for p in pts) > 0.14 and min(p.x for p in pts) < -0.14, "frill: spans the fan across X")

    def _k(co):
        return min(1.0, max(0.0, (co.z - 0.016) / 0.03))      # the pad stays; the fan hinges just above it

    def fold(co):
        return Matrix.Rotation(math.radians(60.0) * _k(co), 3, "X") @ co

    def span_(co):
        co.x *= 1.35
        return co

    handles = _shape_keys(frill, [("H1_Fold", fold, "the fan laid down flat along the body toward the tail"),
                                  ("H2_Span", span_, "the fan 35% wider")])
    _shape_keys(web, [("H1_Fold", fold, ""), ("H2_Span", span_, "")])
    rules = _rules("frill", round(foot, 3), FRILL_SINK, "normal", ["spine"], 20, 30, centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = "Both keys are on Frill and FrillWeb with the same names; the runtime sets them together."
    rules["placement_note"] = "Meant for the neck, just behind the head; the fan leans back toward the tail and folds flat along it."
    return {"purpose": "Creature display part (PROPOSED): a seven-ribbed neck frill with a scalloped fleshy web, folding on a shape key.",
            "category": "part", "part_type": "frill", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_FrillRib": 0.2, "M_FrillWeb": 0.95, "M_FrillPad": 0.9}, "revision": 1, **baked}


# --- Proboscis ------------------------------------------------------------------------------------

PROB_LEN = 0.2          # along the trunk's centreline, from the skin to the sucker's rim
PROB_SINK = 0.03
PROB_R = 0.02           # the trunk's radius where it leaves the collar
PROB_PAD_R = 0.022      # the sucker disc's rim radius


def build_proboscis():
    """A ringed trunk-like snout: a soft tube rises from a low fleshy collar, sways back a little, then
    hooks forward (+Y) and down to a flared sucker disc whose face is a darker concave pad with a central
    pore (the `ProboscisTip` child). H1_Length stretches the trunk along its path, H2_Curl curls the
    outer half further down and under toward the body."""
    steps, sides = 96, 16
    ds = (PROB_LEN + PROB_SINK * 0.95) / steps

    def heading(u):
        # The tangent's angle from +Z toward +Y: square to the skin in the root, a slight backward sway,
        # then a hook that tightens toward the tip.
        return min(1.0, u / 0.13) ** 2 * (-0.05 - 2.0 * u * (1.0 - u) ** 3 + 2.5 * u ** 1.9)

    def trace(stretch):
        # The centreline integrated from the heading; stretch(k) lengthens step k (for H1_Length).
        p, out = Vector((0.0, 0.0, -PROB_SINK * 0.95)), []
        for k in range(steps):
            out.append(p.copy())
            th = heading((k + 0.5) / steps)
            p = p + Vector((0.0, math.sin(th), math.cos(th))) * (ds * stretch(k))
        out.append(p.copy())
        t = (out[-1] - out[-2]).normalized()
        out.append(out[-1] + t * 0.0025)      # the lip rolls over the rim ...
        out.append(out[-1] + t * 0.001)       # ... and into the pad, where the tube stays open
        return out

    path = trace(lambda k: 1.0)
    skin = next(i for i, p in enumerate(path) if p.z >= 0.0)
    neck = int(0.93 * steps)
    annuli, phase = [], 0.0
    for i in range(steps + 1):
        annuli.append(phase)
        phase += 2.0 * math.pi * ds / (0.017 - 0.006 * i / steps)     # the rings tighten toward the tip

    def radius(i, a):
        if i > steps:
            return PROB_PAD_R * (0.93 if i == steps + 1 else 0.75)
        u = i / steps
        v = min(1.0, max(0.0, (u - 0.13) / 0.8))
        r = PROB_R - (PROB_R - 0.0105) * v ** 0.9
        r += 0.008 * max(0.0, 1.0 - (max(0.0, u - 0.13) / 0.09) ** 2) ** 2           # a low collar at the skin
        ring = (0.5 + 0.5 * math.cos(annuli[i])) ** 0.8                                 # soft annuli, narrow troughs ...
        ring *= min(1.0, max(0.0, (u - 0.16) / 0.1)) * min(1.0, max(0.0, (0.93 - u) / 0.08))   # ... above the collar
        r *= 0.95 + 0.11 * ring
        if u > 0.93:
            r += (PROB_PAD_R - 0.0105) * ((u - 0.93) / 0.07) ** 1.6                     # the sucker's flare
        return r

    verts, faces, _ = _tube(path, radius, sides)
    flesh = sf.Shader("M_ProboscisProc")
    wr = flesh.noise(240.0, 3.0)
    pores = flesh.remap(flesh.voronoi(380.0, 0.7), 0.18, 0.04)
    flesh.bump(flesh.math("SUBTRACT", wr, flesh.math("MULTIPLY", pores, 0.5)), 0.3, 0.0008)
    trunk_mat = flesh.out(_grey(flesh, flesh.remap(wr, 0.3, 0.7), 0.8), 0.55)
    trunk = bc.mesh_object("Proboscis", verts, faces, [trunk_mat])
    trunk_mat.name = "M_Proboscis"
    # The sucker pad: a closed revolve about the tube's end tangent whose front edge is the tube's open end
    # ring, dished back toward the trunk and dropping into a pore at the centre; its back sits inside the cup.
    tip, t = path[-1], (path[-1] - path[-2]).normalized()
    frame = Matrix((t.cross(Vector((1.0, 0.0, 0.0))), t, Vector((1.0, 0.0, 0.0)))).transposed()
    rp = PROB_PAD_R
    profile = [(-0.0085, 0.0), (-0.006, 0.72 * rp), (0.0, 0.75 * rp), (-0.0006, 0.6 * rp), (-0.002, 0.42 * rp),
               (-0.0032, 0.25 * rp), (-0.0038, 0.12 * rp), (-0.004, 0.08 * rp), (-0.0055, 0.045 * rp), (-0.0062, 0.0)]
    pverts, pfaces, _ = bc.revolve(profile, sides)
    pad_sh = sf.Shader("M_ProboscisTipProc")
    dist = pad_sh.vmath("LENGTH", pad_sh.vmath("SUBTRACT", pad_sh.pos, tuple(tip - t * 0.004)))
    ridges = pad_sh.math("SINE", pad_sh.math("MULTIPLY", dist, 2.0 * math.pi / 0.0028))
    grain = pad_sh.noise(300.0, 2.0)
    pad_sh.bump(pad_sh.math("ADD", ridges, pad_sh.math("MULTIPLY", grain, 0.6)), 0.35, 0.0005)
    shade = pad_sh.math("MULTIPLY", pad_sh.remap(dist, 0.003, 0.015), pad_sh.remap(ridges, -1.0, 1.0, 0.75, 1.0))
    pad_mat = pad_sh.out(_grey(pad_sh, shade, 0.45), 0.35)
    pad = bc.mesh_object("ProboscisTip", [tuple(tip + frame @ Vector(co)) for co in pverts], pfaces, [pad_mat], parent=trunk)
    pad_mat.name = "M_ProboscisTip"
    baked = _bake([trunk, pad], "PartProboscis", {"M_Proboscis": sf.tint(_lin("#B98A7A")), "M_ProboscisTip": sf.tint(_lin("#5A4238"))})
    pts = _check_pivot("proboscis", PROB_SINK)
    foot = _footprint(pts)
    mp._check(tip.y > 0.06 and t.z < 0, "proboscis: hooks forward (+Y) and turns down at the tip")

    long_path = trace(lambda k: 1.4 if skin <= k < neck else 1.0)
    hinge = skin + (neck - skin) // 2

    def ring_of(co):
        return min(range(len(path)), key=lambda i: (co - path[i]).length_squared)

    def length(co):
        i = ring_of(co)
        return co + (long_path[i] - path[i])      # beyond the neck every ring shifts alike: the sucker stays rigid

    def curl(co):
        k = min(1.0, max(0.0, (ring_of(co) - hinge) / (neck - hinge)))
        if k <= 0.0:
            return co
        return path[hinge] + Matrix.Rotation(math.radians(-55.0) * k, 3, "X") @ (co - path[hinge])

    handles = _shape_keys(trunk, [("H1_Length", length, "the trunk 40% longer along its path"),
                                  ("H2_Curl", curl, "the outer half curled 55 degrees down and under")])
    _shape_keys(pad, [("H1_Length", length, ""), ("H2_Curl", curl, "")])
    rules = _rules("proboscis", round(foot, 3), PROB_SINK, "forward_cone", ["spine"], 40, 30, centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = "Both keys are on Proboscis and ProboscisTip with the same names; the runtime sets them together. The sucker moves rigidly with the trunk's tip."
    return {"purpose": "Creature mouth part (PROPOSED): a ringed trunk-like snout curving forward and down to a flared sucker pad; lengthens and curls on shape keys.",
            "category": "part", "part_type": "proboscis", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_Proboscis": 0.9, "M_ProboscisTip": 0.2}, "revision": 1, **baked}


# --- Tusk -------------------------------------------------------------------------------------

TUSK_LEN = 0.185
TUSK_RX = 0.029       # root half-width in the sweep plane (the oval's long axis, along +Y at the root)
TUSK_RY = 0.021       # root half-thickness across it (+X at the root)
TUSK_SINK = 0.025
TUSK_ROOT = -0.0135   # the root cap's centre, under the skin


def build_tusk():
    """A thick grooved ivory tusk rooted in a rolled gum collar, sweeping forward (+Y), out to the right (+X)
    and a little up with a flattened oval section, a slight twist and a blunt tip: chiral, so the runtime
    mirrors it for the left. H1_Length lengthens it, H2_Curve curls the tip further out and up."""
    steps = 26
    e0, e1 = math.radians(20.0), math.radians(88.0)      # the tangent's angle from the skin normal, root to tip
    az0, az1 = math.radians(22.0), math.radians(58.0)    # its azimuth from +Y toward +X
    path = [Vector((0.0, 0.0, TUSK_ROOT))]
    for i in range(1, steps + 1):
        t = (i - 0.5) / steps
        e = e0 + (e1 - e0) * (1.0 - (1.0 - t) ** 1.5)    # turns a little harder near the gum
        az = az0 + (az1 - az0) * t ** 1.5
        path.append(path[-1] + Vector((math.sin(e) * math.sin(az), math.sin(e) * math.cos(az), math.cos(e))) * (TUSK_LEN / steps))
    tip_r = TUSK_RX * 0.28 ** 1.25
    d = (path[-1] - path[-2]).normalized()
    for b in (40.0, 70.0, 90.0):     # a rounded blunt tip
        path.append(path[steps] + d * (tip_r * math.sin(math.radians(b))))

    def radius_at(i, a):
        if i > steps + 2:
            return 0.0
        t = min(i, steps) / steps
        a -= math.radians(50.0) * t      # the slight twist
        oval = math.sqrt(math.cos(a) ** 2 + (TUSK_RY / TUSK_RX * math.sin(a)) ** 2)
        base = TUSK_RX * (1.0 - 0.72 * t) ** 1.25 if i <= steps else tip_r * math.cos(math.radians((40.0, 70.0)[i - steps - 1]))
        return base * oval * (1.0 + 0.045 * (1.0 - 0.5 * t) * math.cos(8.0 * a))     # eight lengthwise grooves, worn toward the tip

    verts, faces, _ = _tube(path, radius_at, 40)
    face_mats = [1] * len(faces)

    # Gum: a low rolled lip of flesh round the root, each ring horizontal and centred on the tusk's axis at its height.
    def axis_at(h):
        for a, b in zip(path, path[1:]):
            if b.z >= h:
                return a.lerp(b, (h - a.z) / (b.z - a.z))
        return path[-1]

    profile = [(-0.003, -0.006), (-0.001, 0.002), (0.0, 0.006)]
    profile += [(0.0045 + 0.0045 * math.cos(math.radians(b)), 0.004 + 0.0045 * math.sin(math.radians(b))) for b in range(105, -46, -25)]
    profile += [(0.0095, -0.001), (0.0125, -0.005), (0.013, -0.011), (0.011, -0.017), (0.007, -0.022)]
    seg = 40
    rings = []
    for o, h in profile:
        c = axis_at(max(h, 0.0))
        rings.append(list(range(len(verts), len(verts) + seg)))
        for j in range(seg):
            u = 2.0 * math.pi * j / seg
            verts.append((c.x + (TUSK_RY + 0.0015 + o) * math.sin(u), c.y + (TUSK_RX + 0.0035 + o) * math.cos(u), h))
    top, bottom = len(verts), len(verts) + 1
    verts.append(tuple(axis_at(0.0) + Vector((0.0, 0.0, -0.006))))
    verts.append(tuple(axis_at(0.0) + Vector((0.0, 0.0, -0.022))))
    for j in range(seg):
        k = (j + 1) % seg
        faces.append((top, rings[0][k], rings[0][j]))
        faces.append((rings[-1][j], rings[-1][k], bottom))
        for i in range(len(profile) - 1):
            faces.append((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
    face_mats.extend([0] * (len(faces) - len(face_mats)))
    gum = sf.Shader("M_TuskGumProc")
    pores = gum.noise(170.0, 3.0)
    gum.bump(pores, 0.3, 0.0008)
    ivory = sf.Shader("M_TuskProc")
    along = ivory.vmath("DOT_PRODUCT", ivory.pos, tuple(Vector((0.45, 0.65, 0.5)).normalized()))
    growth = ivory.remap(ivory.math("SINE", ivory.math("MULTIPLY", along, 700.0)), -1.0, 1.0)
    mottle = ivory.noise(45.0, 2.0)
    grain = ivory.noise(220.0, 2.0)
    h = ivory.math("ADD", ivory.math("ADD", ivory.math("MULTIPLY", mottle, 0.6), ivory.math("MULTIPLY", grain, 0.32)), ivory.math("MULTIPLY", growth, 0.08))
    ivory.bump(h, 0.2, 0.0005)
    stain = ivory.remap(ivory.axis("Z"), 0.0, 0.045, 0.78, 1.0)      # ivory stained toward the gum
    mats = [gum.out(_grey(gum, gum.remap(pores, 0.3, 0.7), 0.75), 0.55),
            ivory.out(ivory.mix(1.0, _grey(ivory, ivory.remap(h, 0.25, 0.75), 0.72), stain, "MULTIPLY"), 0.3)]
    tusk = bc.mesh_object("Tusk", verts, faces, mats, face_mats)
    mats[0].name, mats[1].name = "M_TuskGum", "M_Tusk"
    baked = _bake([tusk], "PartTusk", {"M_TuskGum": sf.tint(_lin("#B6877A")), "M_Tusk": sf.tint(_lin("#EDDCC2"))})
    pts = _check_pivot("tusk", TUSK_SINK)
    foot = _footprint(pts)
    mp._check(sum(p.x for p in pts) > 0, "tusk: sweeps toward +X (the right-hand side ships)")
    root = Vector((0.0, 0.0, TUSK_ROOT))
    tip_z = path[steps].z

    def length(co):
        k = min(1.0, max(0.0, (co.z - 0.012) / 0.03))      # the gum and the root stay
        return co + (co - root) * (0.4 * k)

    def curve(co):
        k = min(1.0, max(0.0, (co.z - 0.02) / (tip_z - 0.02))) ** 2.5
        co.x += 0.05 * k
        co.z += 0.03 * k
        return co

    handles = _shape_keys(tusk, [("H1_Length", length, "the tusk 40% longer"),
                                 ("H2_Curve", curve, "the tip curled further out and up")])
    rules = _rules("tusk", round(foot, 3), TUSK_SINK, "forward_cone", ["spine", "part"], 40, 30, centerline="forbidden", chiral=True)
    rules["handles"] = handles
    return {"purpose": "Creature tusk part (PROPOSED): a grooved ivory tusk sweeping forward and out from a fleshy gum, right-hand side (mirrored at bake for the left).",
            "category": "part", "part_type": "tusk", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_TuskGum": 0.85, "M_Tusk": 0.0}, "revision": 1, **baked}


# --- Gill fan -----------------------------------------------------------------------------------

GILL_SINK = 0.015
GILL_PLUMES = 5


def build_gill_fan():
    """External gills for the right side of the neck: five feathery plumes (the GillPlumes child, double-sided
    blades with scalloped edges on a thin rachis) fanning up and out to +X from a fleshy ridge along the
    neck: chiral, so the runtime mirrors it for the left. H1_Spread fans the plumes apart, H2_Length
    lengthens them."""
    unit, ufaces = bc.icosphere(2)
    verts = [(n.x * 0.017, n.y * 0.044, -0.01 + max(n.z, -0.2) * 0.022) for n in (Vector(co).normalized() for co in unit)]
    fcs = list(ufaces)
    face_mats = [0] * len(fcs)
    pverts, pfcs = [], []
    roots, axes = [], []
    for k in range(GILL_PLUMES):
        off = k - (GILL_PLUMES - 1) / 2                       # -2 .. 2 along the ridge
        root = Vector((0.004, 0.0145 * off, 0.0))
        tilt = 0.32 * off                                      # the outer plumes lean toward head and tail
        d = Vector((math.sin(0.6), math.sin(tilt), math.cos(0.6) * math.cos(tilt))).normalized()
        w = (Vector((0.0, 1.0, 0.0)) - d * d.y).normalized()  # across the blade, along the ridge
        facing = d.cross(w).normalized()                       # the blade faces out from the flank
        length = 0.13 - 0.015 * abs(off)
        roots.append(root)
        axes.append((d, length))

        def centre(s, root=root, d=d, length=length):
            return root + d * (length * s) + Vector((0.035 * s * s, 0.0, -0.02 * s * s))      # bows out and over

        def blade(s, c, centre=centre, w=w, length=length):
            width = 0.022 * math.sin(math.pi * min(1.0, s ** 0.75)) ** 0.8
            scallop = 1.0 - 0.24 * abs(math.sin(s * math.pi * 8.0)) * (abs(c - 0.5) > 0.25)
            return centre(s) + w * ((c - 0.5) * width * scallop)

        _membrane(pverts, pfcs, blade, 4, 12, thickness=0.0012, facing=facing)
        path = [centre(s) for s in (-0.05, 0.1, 0.3, 0.5, 0.7, 0.88, 1.0)]
        v, f, _ = _tube(path, lambda i, a: 0.0 if i == 6 else 0.0032 * (1.0 - 0.75 * i / 6), 6)
        bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
    base_sh = sf.Shader("M_GillBaseProc")
    wr = base_sh.noise(200.0, 3.0, vector=mp._stretched(base_sh, (1.0, 0.4, 1.0)))
    base_sh.bump(wr, 0.3, 0.0008)
    plume = sf.Shader("M_GillPlumeProc")
    fil = plume.remap(plume.math("SINE", plume.math("MULTIPLY", plume.axis("Y"), 1100.0)), -0.4, 1.0)
    soft = plume.noise(160.0, 2.0)
    plume.bump(plume.math("ADD", plume.math("MULTIPLY", fil, 0.5), plume.math("MULTIPLY", soft, 0.5)), 0.25, 0.0006)
    plume_base = _grey(plume, plume.math("SUBTRACT", plume.remap(soft, 0.3, 0.7), plume.math("MULTIPLY", fil, 0.2), clamp=True), 0.72)
    rachis = sf.Shader("M_GillRachisProc")
    grain = rachis.noise(260.0, 2.0, vector=mp._stretched(rachis, (0.3, 1.0, 0.3)))
    rachis.bump(grain, 0.2, 0.0005)
    mats = [base_sh.out(_grey(base_sh, base_sh.remap(wr, 0.3, 0.7), 0.75), 0.55),
            rachis.out(_grey(rachis, rachis.remap(grain, 0.3, 0.7), 0.75), 0.45)]
    fan = bc.mesh_object("GillFan", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name = "M_GillBase", "M_GillRachis"
    plume_mat = plume.out(plume_base, 0.45)
    plumes = bc.mesh_object("GillPlumes", pverts, pfcs, [plume_mat], fix_normals=False, parent=fan)
    plume_mat.name = "M_GillPlume"
    baked = _bake([fan, plumes], "PartGillFan", {"M_GillBase": sf.tint(_lin("#B98A7A")), "M_GillRachis": sf.tint(_lin("#D9916E")),
                                                 "M_GillPlume": sf.tint(_lin("#E0997A"))}, tolerance=0.0003)
    pts = _check_pivot("gill_fan", GILL_SINK)
    foot = _footprint(pts)
    mp._check(sum(p.x for p in pts if p.z > 0.02) > 0, "gill_fan: plumes lean toward +X (the right-hand side ships)")

    def _plume(co):
        """The plume a vertex belongs to: nearest root by the ridge coordinate, after undoing the lean."""
        best, best_d = 0, 1e9
        for k, (root, (d, length)) in enumerate(zip(roots, axes)):
            s = min(1.0, max(0.0, (co - root).dot(d) / length))
            dist = (co - (root + d * (length * s) + Vector((0.035 * s * s, 0.0, -0.02 * s * s)))).length
            if dist < best_d:
                best, best_d = k, dist
        return best

    def spread(co):
        if co.z <= 0.003:
            return co
        k = _plume(co)
        root = roots[k]
        rot = Matrix.Rotation(math.radians(-14.0 * (k - (GILL_PLUMES - 1) / 2)), 3, "X")
        return root + rot @ (co - root)

    def length_(co):
        if co.z <= 0.003:
            return co
        root = roots[_plume(co)]
        return root + (co - root) * 1.35

    handles = _shape_keys(fan, [("H1_Spread", spread, "the plumes fanned 14 degrees further apart per step"),
                                ("H2_Length", length_, "the plumes 35% longer")])
    _shape_keys(plumes, [("H1_Spread", spread, ""), ("H2_Length", length_, "")])
    rules = _rules("gill_fan", round(foot, 3), GILL_SINK, "normal", ["spine"], 30, 30, centerline="forbidden", chiral=True)
    rules["handles"] = handles
    rules["handles_note"] = "Both keys are on GillFan and GillPlumes with the same names; the runtime sets them together."
    rules["placement_note"] = "Meant for the sides of the neck; the ridge runs along the body (y) and the plumes lean out to +X."
    return {"purpose": "Creature breathing part (PROPOSED): five feathery external gill plumes on a fleshy ridge, right-hand side (mirrored at bake for the left).",
            "category": "part", "part_type": "gill_fan", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_GillBase": 0.9, "M_GillRachis": 0.5, "M_GillPlume": 0.5}, "revision": 1, **baked}


# --- Flipper ----------------------------------------------------------------------------------

FLIPPER_LEN = 0.2
FLIPPER_W = 0.055      # half-width at the broadest, across X
FLIPPER_T = 0.009      # half-thickness at the root, along Y
FLIPPER_SINK = 0.015


def build_flipper():
    """A swimmer's paddle for a limb tip: a flattened blade out along +Z (the limb's axis), broad across X and
    thin along Y, waisted at the root, with lengthwise stiffening ridges in the skin and a rounded tip, cupped
    a little toward the head. H1_Length lengthens it, H2_Width widens it."""
    steps = 18
    path = [Vector((0.0, 0.03 * (i / steps) ** 2, -FLIPPER_SINK * 0.9 + (FLIPPER_LEN + FLIPPER_SINK * 0.9) * i / steps)) for i in range(steps + 1)]

    def radius_at(i, a):
        if i == steps:
            return 0.0
        t = i / steps
        w = FLIPPER_W * (0.55 + 0.45 * math.sin(math.pi * min(1.0, 0.15 + 0.85 * t)))
        th = FLIPPER_T * (1.0 - 0.75 * t) + 0.0025
        # A true ellipse; _tube's ring angle 0 lies along +Y for a path up +Z, so the breadth goes on sin.
        return w * th / math.sqrt((th * math.sin(a)) ** 2 + (w * math.cos(a)) ** 2)

    verts, faces, _ = _tube(path, radius_at, 22)
    sh = sf.Shader("M_FlipperSkinProc")
    pebble = sh.remap(sh.voronoi(240.0, 0.8), 0.2, 0.04)
    grain = sh.noise(60.0, 2.0, vector=mp._stretched(sh, (3.0, 1.0, 0.4)))
    ridges = sh.math("SINE", sh.math("MULTIPLY", sh.axis("X"), 230.0))                 # lengthwise stiffening ridges
    sh.bump(sh.math("ADD", sh.math("MULTIPLY", ridges, 0.5), sh.math("SUBTRACT", sh.math("MULTIPLY", grain, 0.4), sh.math("MULTIPLY", pebble, 0.4))), 0.4, 0.001)
    mat = sh.out(_grey(sh, sh.math("SUBTRACT", sh.remap(grain, 0.3, 0.7), sh.math("MULTIPLY", pebble, 0.3), clamp=True), 0.75), 0.5)
    flipper = bc.mesh_object("Flipper", verts, faces, [mat])
    mat.name = "M_FlipperSkin"
    baked = _bake([flipper], "PartFlipper", {"M_FlipperSkin": sf.tint(_lin("#7F8FA0"))}, tolerance=0.0004)
    pts = _check_pivot("flipper", FLIPPER_SINK)
    foot = _footprint(pts)
    mp._check(max(p.z for p in pts) > FLIPPER_LEN * 0.95, "flipper: reaches its length along +Z")

    def length(co):
        if co.z > 0.0:
            co.z *= 1.4
            co.y *= 1.4
        return co

    def width(co):
        if co.z > 0.0:
            co.x *= 1.35
        return co

    handles = _shape_keys(flipper, [("H1_Length", length, "the blade 40% longer"), ("H2_Width", width, "the blade 35% broader")])
    rules = _rules("flipper", round(foot, 3), FLIPPER_SINK, "normal", ["limb_end"], 30, 30)
    rules["handles"] = handles
    rules["placement_note"] = "A limb end: +Z runs on along the limb and the blade's broad faces look fore and aft."
    return {"purpose": "Creature limb end part (PROPOSED): a flattened swimming paddle with stiffening ridges, broad across x and thin fore-aft.",
            "category": "part", "part_type": "flipper", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_FlipperSkin": 0.9}, "revision": 1, **baked}


# --- Hoof -------------------------------------------------------------------------------------

HOOF_H = 0.043
HOOF_ANKLE = 0.075


def build_hoof():
    """A cloven hoof standing on its sole (orientation "ground": +Z body up, the cleft toward the head, the
    sole on the pivot): a horn capsule split by a front cleft, with a short skin pastern rising to the limb.
    H1_Wide widens the hoof, H2_Tall raises its wall."""
    # Rings from the sole up: (z, half-width x, half-length y, cleft depth, material); horn 1, skin 0.
    rows = [(0.0, 0.040, 0.0425, 0.28, 1), (0.004, 0.041, 0.0435, 0.28, 1), (0.016, 0.040, 0.042, 0.26, 1),
            (0.030, 0.037, 0.039, 0.2, 1), (HOOF_H, 0.032, 0.034, 0.12, 1), (HOOF_H + 0.004, 0.027, 0.028, 0.0, 0),
            (0.06, 0.023, 0.024, 0.0, 0), (HOOF_ANKLE, 0.021, 0.022, 0.0, 0)]
    seg = 36
    verts, faces, face_mats, rings = [], [], [], []
    for z, rx, ry, depth, _m in rows:
        ring = []
        for j in range(seg):
            a = 2.0 * math.pi * j / seg
            d = math.atan2(math.sin(a - math.pi / 2), math.cos(a - math.pi / 2))      # angle from the front (+Y)
            cleft = 1.0 - depth * math.exp(-(d / 0.3) ** 2)
            heel = 1.0 - 0.06 * math.exp(-((abs(d) - math.pi) / 0.5) ** 2)             # a little flat at the back
            ring.append(len(verts))
            verts.append((rx * math.cos(a) * cleft * heel, ry * math.sin(a) * cleft * heel - 0.004, z))
        rings.append(ring)
    sole, top = len(verts), len(verts) + 1
    verts.append((0.0, -0.004, 0.0))
    verts.append((0.0, -0.004, HOOF_ANKLE))
    for j in range(seg):
        k = (j + 1) % seg
        faces.append((sole, rings[0][k], rings[0][j]))
        face_mats.append(1)
        for i in range(len(rows) - 1):
            faces.append((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
            face_mats.append(rows[i][4])
        faces.append((rings[-1][j], rings[-1][k], top))
        face_mats.append(0)
    skin = sf.Shader("M_HoofSkinProc")
    hair = skin.noise(220.0, 3.0, vector=mp._stretched(skin, (1.0, 1.0, 0.25)))
    skin.bump(hair, 0.3, 0.0008)
    horn = sf.Shader("M_HoofHornProc")
    growth = horn.math("SINE", horn.math("MULTIPLY", horn.axis("Z"), 500.0))
    streak = horn.noise(90.0, 3.0, vector=mp._stretched(horn, (4.0, 4.0, 0.3)))
    h = horn.math("ADD", horn.math("MULTIPLY", growth, 0.25), streak)
    horn.bump(h, 0.3, 0.001)
    mats = [skin.out(_grey(skin, skin.remap(hair, 0.3, 0.7), 0.75), 0.6),
            horn.out(_grey(horn, horn.remap(h, -0.1, 0.9), 0.65), 0.35)]
    hoof = bc.mesh_object("Hoof", verts, faces, mats, face_mats)
    mats[0].name, mats[1].name = "M_HoofSkin", "M_HoofHorn"
    baked = _bake([hoof], "PartHoof", {"M_HoofSkin": sf.tint(_lin("#A88870")), "M_HoofHorn": sf.tint(_lin("#4F4238"))})
    pts = _check_pivot("hoof", 0.0, ground=True)
    reach = max(math.hypot(p.x, p.y) for p in pts)

    def wide(co):
        k = 1.0 + 0.3 * max(0.0, 1.0 - co.z / (HOOF_H + 0.01))
        co.x *= k
        return co

    def tall(co):
        co.z = co.z * 1.3 if co.z <= HOOF_H else co.z + 0.3 * HOOF_H
        return co

    handles = _shape_keys(hoof, [("H1_Wide", wide, "the hoof 30% wider"), ("H2_Tall", tall, "the hoof wall 30% taller")])
    rules = _rules("hoof", round(reach, 3), 0.0, "ground", ["limb_end"], 20, 15)
    rules["handles"] = handles
    rules["pivot_note"] = "Ground part: the sole sits on the pivot; the pastern top (z %.3f m) meets the limb tip." % HOOF_ANKLE
    return {"purpose": "Creature foot part (PROPOSED): a cloven horn hoof on a short skin pastern, standing on its sole.",
            "category": "part", "part_type": "hoof", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_HoofSkin": 0.85, "M_HoofHorn": 0.0}, "revision": 1, **baked}


# --- Club tail --------------------------------------------------------------------------------

CLUB_R = 0.055
CLUB_STALK = 0.07
CLUB_SINK = 0.03


def build_club_tail():
    """A bony club for the tail cap (+Z out along the spine): a thick waisted stalk ending in a ball of fused
    bony knobs (a score of them, spread evenly). H1_Length lengthens the stalk, H2_Size swells the club 30%."""
    centre = Vector((0.0, 0.0, CLUB_STALK + CLUB_R * 0.6))
    path = [Vector((0.0, 0.0, -CLUB_SINK * 0.9 + (CLUB_STALK + CLUB_SINK * 0.9) * t)) for t in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0)]
    verts, fcs, _ = _tube(path, lambda i, a: 0.03 * (1.0 - 0.25 * math.sin(math.pi * i / 5)) * (1.0 + 0.04 * math.cos(5 * a)), 18)
    face_mats = [0] * len(fcs)
    # The club: a sphere pushed out into knobs around twenty fixed directions (a Fibonacci spread).
    knobs = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for k in range(20):
        z = 1.0 - 2.0 * (k + 0.5) / 20
        r = math.sqrt(1.0 - z * z)
        knobs.append(Vector((r * math.cos(golden * k), r * math.sin(golden * k), z)))
    unit, ufaces = bc.icosphere(4)
    club = []
    for co in unit:
        n = Vector(co).normalized()
        bump = sum(math.exp(-((1.0 - n.dot(d)) / 0.03) ** 2) for d in knobs)
        club.append(tuple(centre + n * (CLUB_R * (0.85 + 0.25 * min(1.0, bump)))))
    bc.append(verts, fcs, club, ufaces)
    face_mats.extend([1] * (len(fcs) - len(face_mats)))
    flesh = sf.Shader("M_ClubStalkProc")
    wr = flesh.noise(160.0, 3.0, vector=mp._stretched(flesh, (1.0, 1.0, 0.3)))
    flesh.bump(wr, 0.3, 0.0008)
    bone = sf.Shader("M_ClubBoneProc")
    pits = bone.remap(bone.voronoi(140.0, 0.9), 0.3, 0.08)
    grain = bone.noise(70.0, 3.0)
    bone.bump(bone.math("SUBTRACT", bone.math("MULTIPLY", grain, 0.6), bone.math("MULTIPLY", pits, 0.6)), 0.35, 0.001)
    mats = [flesh.out(_grey(flesh, flesh.remap(wr, 0.3, 0.7), 0.75), 0.55),
            bone.out(_grey(bone, bone.math("SUBTRACT", bone.remap(grain, 0.25, 0.75), bone.math("MULTIPLY", pits, 0.35), clamp=True), 0.65), 0.4)]
    obj = bc.mesh_object("ClubTail", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name = "M_ClubStalk", "M_ClubBone"
    baked = _bake([obj], "PartClubTail", {"M_ClubStalk": sf.tint(_lin("#A8826E")), "M_ClubBone": sf.tint(_lin("#D8CBB0"))}, tolerance=0.0006)
    pts = _check_pivot("club_tail", CLUB_SINK)
    foot = _footprint(pts)

    def length(co):
        if co.z > 0.01:
            co.z += 0.05 * min(1.0, (co.z - 0.01) / 0.04)
        return co

    def size(co):
        if (co - centre).length < CLUB_R * 1.25:
            return centre + (co - centre) * 1.3
        return co

    handles = _shape_keys(obj, [("H1_Length", length, "the stalk 0.05 m longer"), ("H2_Size", size, "the club 30% bigger")])
    rules = _rules("club_tail", round(foot, 3), CLUB_SINK, "normal", ["spine"], 15, 20, centerline="required")
    rules["handles"] = handles
    rules["placement_note"] = "Meant for the tail cap (spine_u = 1)."
    return {"purpose": "Creature tail weapon part (PROPOSED): a knobbed bony club on a thick fleshy stalk for the tail tip.",
            "category": "part", "part_type": "club_tail", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_ClubStalk": 0.85, "M_ClubBone": 0.1}, "revision": 1, **baked}


# --- Lure -------------------------------------------------------------------------------------

LURE_LEN = 0.22
LURE_SINK = 0.02


def build_lure():
    """An angler's lure: a slender stalk rising from a small pad and arching forward (+Y) over the head to a
    glowing bulb hanging from its tip. H1_Length lengthens the stalk, H2_Droop lowers the bulb."""
    unit, ufaces = bc.icosphere(2)
    verts = [(n.x * 0.02, n.y * 0.02, -0.012 + max(n.z, -0.2) * 0.03) for n in (Vector(co).normalized() for co in unit)]
    fcs = list(ufaces)
    face_mats = [0] * len(fcs)
    steps = 16
    path = [Vector((0.0, 0.0, -LURE_SINK * 0.9))]
    for i in range(steps):
        t = (i + 0.5) / steps
        theta = math.radians(112.0) * t ** 1.3                 # from straight up to forward and down
        path.append(path[-1] + Vector((0.0, math.sin(theta), math.cos(theta))) * (LURE_LEN / steps))
    v, f, _ = _tube(path, lambda i, a: 0.0065 * (1.0 - 0.45 * i / steps) * (1.0 + 0.05 * math.cos(4 * a)), 10)
    bc.append(verts, fcs, v, f)
    face_mats.extend([1] * (len(fcs) - len(face_mats)))
    tip = path[-1] + (path[-1] - path[-2]).normalized() * 0.012
    unit3, ufaces3 = bc.icosphere(3)
    bulb = [tuple(tip + Vector(co).normalized() * 0.021 * Vector((1.0, 1.0, 1.15))) for co in unit3]
    bc.append(verts, fcs, bulb, ufaces3)
    face_mats.extend([2] * (len(fcs) - len(face_mats)))
    pad_sh = sf.Shader("M_LurePadProc")
    wr = pad_sh.noise(220.0, 3.0)
    pad_sh.bump(wr, 0.3, 0.0008)
    stalk = sf.Shader("M_LureStalkProc")
    rings = stalk.math("SINE", stalk.math("MULTIPLY", stalk.vmath("LENGTH", stalk.pos), 900.0))
    stalk.bump(rings, 0.2, 0.0005)
    glow = sf.Shader("M_LureBulbProc")
    veins = glow.remap(glow.voronoi(90.0, 0.7, feature="DISTANCE_TO_EDGE"), 0.0, 0.05)
    glow.bump(veins, 0.15, 0.0004)
    mats = [pad_sh.out(_grey(pad_sh, pad_sh.remap(wr, 0.3, 0.7), 0.75), 0.55),
            stalk.out(_grey(stalk, stalk.remap(rings, -1.0, 1.0), 0.78), 0.5),
            glow.out(_grey(glow, veins, 0.85), 0.2)]
    obj = bc.mesh_object("Lure", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name, mats[2].name = "M_LurePad", "M_LureStalk", "M_LureBulb"
    baked = _bake([obj], "PartLure", {"M_LurePad": sf.tint(_lin("#B98A7A")), "M_LureStalk": sf.tint(_lin("#8C6A5E")),
                                      "M_LureBulb": sf.tint(_lin("#BFE9F2"), emission=_lin("#7FD8F0"), emission_strength=2.0)}, size=256, tolerance=0.0004)
    pts = _check_pivot("lure", LURE_SINK)
    foot = _footprint(pts)
    mp._check(max(p.y for p in pts) > 0.1, "lure: the bulb hangs forward over the head (+Y)")

    def length(co):
        k = min(1.0, max(0.0, (co.z - 0.01) / 0.03))
        return co + Vector((0.0, 0.0, 0.01)) * 0.0 + (co - Vector((0.0, 0.0, 0.01))) * (0.4 * k)

    def droop(co):
        k = min(1.0, max(0.0, (co.z - 0.015) / 0.04))
        hinge = Vector((0.0, 0.0, 0.015))
        return hinge + Matrix.Rotation(math.radians(-45.0) * k, 3, "X") @ (co - hinge)

    handles = _shape_keys(obj, [("H1_Length", length, "the stalk and bulb carried 40% further from the pad"),
                                ("H2_Droop", droop, "the stalk bent 45 degrees forward and down from its root")])
    rules = _rules("lure", round(foot, 3), LURE_SINK, "normal", ["spine", "part"], 45, 40)
    rules["handles"] = handles
    rules["placement_note"] = "Meant for the brow: the stalk arches forward over the head and the bulb's emission is baked flat, so it glows the same in every light."
    return {"purpose": "Creature lure part (PROPOSED): a slender stalk arching forward over the head to a glowing pale-cyan bulb.",
            "category": "part", "part_type": "lure", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_LurePad": 0.9, "M_LureStalk": 0.7, "M_LureBulb": 0.0}, "revision": 1, **baked}


# --- Barbels ----------------------------------------------------------------------------------

BARBEL_SINK = 0.015


def build_barbels():
    """Chin barbels: a small fleshy pad with two long and two short tapering whiskers sweeping forward (+Y)
    and out, rising then settling back to skin level, like a catfish's. H1_Length lengthens them, H2_Lift
    raises them."""
    unit, ufaces = bc.icosphere(2)
    verts = [(n.x * 0.034, n.y * 0.024, -0.01 + max(n.z, -0.2) * 0.022) for n in (Vector(co).normalized() for co in unit)]
    fcs = list(ufaces)
    face_mats = [0] * len(fcs)
    whiskers = [(-0.02, 0.0, 32.0, 0.16), (0.02, 0.0, -32.0, 0.16), (-0.009, 0.012, 58.0, 0.09), (0.009, 0.012, -58.0, 0.09)]
    bases = []
    for sx, sy, yaw, length in whiskers:
        base = Vector((sx, sy, 0.0))
        bases.append((base, math.radians(yaw)))
        yaw = math.radians(yaw)
        path = []
        for t in (0.0, 0.12, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0):
            path.append(base + Vector((math.sin(yaw) * length * t * (1.0 + 0.3 * t), math.cos(yaw) * length * t,
                                       -0.008 + 0.045 * (length / 0.16) ** 2 * math.sin(math.pi * t ** 0.8) + 0.008 * t)))
        v, f, _ = _tube(path, lambda i, a, L=length: 0.0 if i == 7 else 0.0045 * (L / 0.16) ** 0.5 * (1.0 - i / 7) ** 0.8, 8)
        bc.append(verts, fcs, v, f)
        face_mats.extend([1] * (len(fcs) - len(face_mats)))
    pad_sh = sf.Shader("M_BarbelPadProc")
    wr = pad_sh.noise(220.0, 3.0)
    pad_sh.bump(wr, 0.3, 0.0008)
    whisker = sf.Shader("M_BarbelProc")
    rings = whisker.math("SINE", whisker.math("MULTIPLY", whisker.vmath("LENGTH", whisker.pos), 1100.0))
    grain = whisker.noise(200.0, 2.0)
    whisker.bump(whisker.math("ADD", whisker.math("MULTIPLY", rings, 0.4), whisker.math("MULTIPLY", grain, 0.6)), 0.25, 0.0005)
    mats = [pad_sh.out(_grey(pad_sh, pad_sh.remap(wr, 0.3, 0.7), 0.75), 0.55),
            whisker.out(_grey(whisker, whisker.remap(grain, 0.3, 0.7), 0.7), 0.5)]
    obj = bc.mesh_object("Barbels", verts, fcs, mats, face_mats)
    mats[0].name, mats[1].name = "M_BarbelPad", "M_Barbel"
    baked = _bake([obj], "PartBarbels", {"M_BarbelPad": sf.tint(_lin("#B98A7A")), "M_Barbel": sf.tint(_lin("#9A6E62"))}, size=256)
    pts = _check_pivot("barbels", BARBEL_SINK)
    foot = _footprint(pts)
    mp._check(max(p.y for p in pts) > 0.12, "barbels: the long pair reaches forward (+Y)")

    def _base(co):
        return min(bases, key=lambda b: abs(math.atan2(co.x - b[0].x, co.y - b[0].y) - b[1]))[0]

    def _k(co):
        return bc.smoothstep(min(1.0, max(0.0, (co.y - 0.01) / 0.04)))

    def length(co):
        base = _base(co)
        return base + (co - base) * (1.0 + 0.4 * _k(co))

    def lift(co):
        base = _base(co)
        return base + Matrix.Rotation(math.radians(25.0) * _k(co), 3, "X") @ (co - base)

    handles = _shape_keys(obj, [("H1_Length", length, "the whiskers 40% longer"), ("H2_Lift", lift, "the whiskers lifted 25 degrees")])
    rules = _rules("barbels", round(foot, 3), BARBEL_SINK, "forward_cone", ["spine"], 40, 30, centerline="required")
    rules["handles"] = handles
    rules["placement_note"] = "Meant for the chin or snout; the long pair sweeps out and forward, the short pair forward."
    return {"purpose": "Creature sensory part (PROPOSED): two long and two short tapering whisker barbels on a fleshy chin pad.",
            "category": "part", "part_type": "barbels", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_BarbelPad": 0.9, "M_Barbel": 0.7}, "revision": 1, **baked}


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
    "cpart_wing": (build_wing, 2500),
    "cpart_antenna": (build_antenna, 1200),
    "cpart_tail_spikes": (build_tail_spikes, 1200),
    "cpart_mandibles": (build_mandibles, 1200),
    "cpart_eye_stalk": (build_eye_stalk, 1200),
    "cpart_compound_eye": (build_compound_eye, 1200),
    "cpart_maw": (build_maw, 1200),
    "cpart_quills": (build_quills, 1200),
    "cpart_frill": (build_frill, 2500),
    "cpart_proboscis": (build_proboscis, 1200),
    "cpart_tusk": (build_tusk, 1200),
    "cpart_gill_fan": (build_gill_fan, 1200),
    "cpart_flipper": (build_flipper, 1200),
    "cpart_hoof": (build_hoof, 1200),
    "cpart_club_tail": (build_club_tail, 1200),
    "cpart_lure": (build_lure, 1200),
    "cpart_barbels": (build_barbels, 1200),
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
