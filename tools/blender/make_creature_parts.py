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


def _bake(objs, texture, tints, size=512, tolerance=TOLERANCE, keep=()):
    """`keep` names objects authored at their final density, which decimation would spoil (an iris edge that is
    a material boundary): they get a tolerance so small nothing collapses."""
    before = after = 0
    highs = {}
    for obj in objs:
        b, a, high = sf.reduce(obj, 1e-7 if obj.name in keep else tolerance)
        before, after = before + b, after + a
        if a == b:
            sf.drop_highs([high])
            high = None
        highs[obj.name] = high
    sf.unwrap(objs)
    # bake_set bakes a normal map only when some piece was reduced; a kept piece's bump still needs one.
    textures = sf.bake_set(objs, texture, size, normal=bool(keep), highs=highs, tints=tints)
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


# --- Set 7: more eyes and mouths ------------------------------------------------------------------------

def _eye_ball(name, centre, radius, iris_half, sclera, iris, segs=28):
    """An eyeball revolved round +Z with a ring of its own exactly at the iris edge, so the iris is a second
    material on the same mesh with a true circular edge (a separate iris shell made the bake ray-cast hit the
    ball underneath). Faces inside `iris_half` (radians from +Z) take `iris`, the rest `sclera`."""
    thetas = sorted(set([iris_half * k / 4 for k in range(5)] + [iris_half + (math.pi - iris_half) * k / 6 for k in range(7)]))
    prof = [(radius * math.cos(t), radius * math.sin(t) if 0.0 < t < math.pi - 1e-9 else 0.0) for t in thetas]
    rv, rf, bands = bc.revolve(prof, segs)
    verts = [tuple(centre + Vector(v)) for v in _up(rv)]
    face_mats = [1 if b < 4 else 0 for b in bands]
    obj = bc.mesh_object(name, verts, rf, [sclera, iris], face_mats)
    return obj


def _iris_material(name, centre, axis, half_angle, pupil, slit=0.0):
    """Greyscale iris detail for a cap: radial fibres, a dark limbal ring at the edge and a dark pupil, round
    (`pupil` its half-angle in radians) or, with `slit` > 0, a slit that narrow (in the ball's unit units) across y."""
    sh = sf.Shader(name)
    n = sh.vmath("NORMALIZE", sh.vmath("SUBTRACT", sh.pos, tuple(centre)))
    facing = sh.vmath("DOT_PRODUCT", n, tuple(axis.normalized()))
    edge = math.cos(half_angle)
    limbal = sh.remap(facing, edge + 0.01, edge + 0.08)                     # 0 at the rim, 1 inside
    fibres = sh.noise(140.0, 2.0, vector=mp._stretched(sh, (9.0, 9.0, 0.4)))
    flecks = sh.remap(sh.voronoi(220.0, 0.9), 0.0, 0.15)
    detail = sh.math("ADD", sh.remap(fibres, 0.3, 0.7, 0.55, 0.95), sh.math("MULTIPLY", flecks, -0.1))
    base = sh.mix(limbal, (0.22, 0.22, 0.22, 1.0), sh.mix(detail, (0.5, 0.5, 0.5, 1.0), (0.95, 0.95, 0.95, 1.0)))
    if slit > 0.0:
        across = sh.math("ABSOLUTE", sh.vmath("DOT_PRODUCT", n, (0.0, 1.0, 0.0)))
        hole = sh.math("MULTIPLY", sh.remap(across, slit + 0.015, slit), sh.remap(facing, math.cos(pupil) - 0.02, math.cos(pupil)))
    else:
        hole = sh.remap(facing, math.cos(pupil) - 0.004, math.cos(pupil) + 0.004)
    base = sh.mix(hole, base, (0.03, 0.03, 0.03, 1.0))
    sh.bump(sh.math("MULTIPLY", fibres, limbal), 0.08, 0.0004)
    return sh.out(base, 0.06)


def _sclera_material(name):
    sh = sf.Shader(name)
    veins = sh.remap(sh.noise(70.0, 4.0, vector=mp._stretched(sh, (1.0, 1.0, 3.0))), 0.62, 0.7)
    sh.bump(veins, 0.03, 0.0002)
    return sh.out(_grey(sh, sh.math("SUBTRACT", 0.95, sh.math("MULTIPLY", veins, 0.12)), 0.8), 0.08)


def _lid_material(name, scales=False):
    sh = sf.Shader(name)
    if scales:
        cells = sh.voronoi(330.0, 0.5, feature="DISTANCE_TO_EDGE")
        groove = sh.remap(cells, 0.0, 0.08)
        sh.bump(groove, 0.4, 0.0008)
        return sh.out(_grey(sh, sh.math("ADD", 0.62, sh.math("MULTIPLY", groove, 0.33)), 0.6), 0.5)
    pores = sh.remap(sh.voronoi(260.0, 0.6), 0.2, 0.05)
    sh.bump(sh.math("SUBTRACT", 0.0, pores), 0.25, 0.0008)
    return sh.out(_grey(sh, sh.math("SUBTRACT", 1.0, sh.math("MULTIPLY", pores, 0.3)), 0.8), 0.55)


def _lid_ring(radius, sink, top, segs=40):
    """The rolled fleshy lid round an eyeball of `radius`, from `sink` under the skin to `top` over it (cpart_eye's)."""
    prof = []
    steps = 16
    for i in range(steps + 1):
        a = math.pi * i / steps
        r = radius * 1.02 + 0.012 * (radius / EYE_R) * math.sin(a) + 0.006 * (radius / EYE_R)
        y = -(sink - 0.0012) + (top + sink - 0.0012) * (1 - math.cos(a)) / 2       # 1.2 mm of room for the decimation
        prof.append((y, r - 0.01 * (radius / EYE_R) * (i / steps) ** 2))
    lv, lf, _ = bc.revolve(prof, segs)
    return _up(lv), lf


def _blink_fn(radius, top):
    def blink(co):
        if co.z > 0.0:
            r = math.hypot(co.x, co.y)
            k = min(1.0, max(0.0, co.z / top))
            scale = max(0.05, 1.0 - 0.95 * k)
            return Vector((co.x * scale if r > 0 else co.x, co.y * scale if r > 0 else co.y, co.z + radius * 1.05 * k))
        return co
    return blink


SLIT_R = 0.04
SLIT_SINK = 0.03


def build_eye_slit():
    """A reptile's eye: a gold ball with a vertical slit pupil (narrow across +Y, so it stands upright on a
    side-set eye) in an almond opening of scaly lids that close in from +-X. H1_Blink shuts the lids,
    H2_Bulge pushes the ball out."""
    centre = Vector((0.0, 0.0, SLIT_R * 0.4))
    axis = Vector((0.0, 0.0, 1.0))
    sclera = _sclera_material("M_EyeSlitBallProc")
    iris_mat = _iris_material("M_EyeSlitIrisProc", centre, axis, math.radians(62.0), math.radians(52.0), slit=0.075)
    ball = _eye_ball("EyeSlit", centre, SLIT_R, math.radians(62.0), sclera, iris_mat)
    sclera.name, iris_mat.name = "M_EyeSlitBall", "M_EyeSlitIris"
    top = SLIT_R * 0.55
    lv, lf = _lid_ring(SLIT_R, SLIT_SINK, top)
    almond = []
    for p in lv:
        p = Vector(p)
        d = p - centre
        r = math.hypot(p.x, p.y)
        k = min(1.0, max(0.0, p.z / top)) ** 1.5
        f = (p.x / r) ** 2 if r > 1e-6 else 0.0             # 1 at +-X (the lids), 0 at +-Y (the corners)
        turn = d.cross(axis)
        if turn.length > 1e-6 and k > 0.0:
            d = Matrix.Rotation(math.radians(13.0) * f * k, 3, turn.normalized()) @ d
        almond.append(tuple(centre + d))
    lid_mat = _lid_material("M_EyeSlitLidProc", scales=True)
    lid = bc.mesh_object("Lid", almond, lf, [lid_mat], parent=ball, fix_normals=False)
    lid_mat.name = "M_EyeSlitLid"
    baked = _bake([ball, lid], "PartEyeSlit", keep=("EyeSlit",), tints={"M_EyeSlitBall": sf.tint(_lin("#E2CDA0")), "M_EyeSlitIris": sf.tint(_lin("#D8923A")),
                                                      "M_EyeSlitLid": sf.tint(_lin("#7E8A5C"))}, size=256)
    pts = _check_pivot("eye_slit", SLIT_SINK)
    foot = _footprint(pts, z_max=0.02)

    def bulge(co):
        return Vector((co.x, co.y, co.z + 0.25 * SLIT_R * max(0.0, co.z) / (SLIT_R * 1.3)))

    handles = _shape_keys(lid, [("H1_Blink", _blink_fn(SLIT_R, top), "the scaly lids close over the ball to a slit")])
    handles += _shape_keys(ball, [("H2_Bulge", bulge, "the ball pushed 25% further out")])
    rules = _rules("eye_slit", round(foot + 0.001, 3), SLIT_SINK, "forward_cone", ["spine", "part"], 60, 45)
    rules["handles"] = handles
    rules["handles_note"] = "H1 is on Lid, H2 on EyeSlit; both are 0 to 1000 per mille."
    return {"purpose": "Creature eye part (PROPOSED): a reptile's gold eye with a slit pupil in an almond of scaly lids; blinks on a shape key.",
            "category": "part", "part_type": "eye_slit", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_EyeSlitBall": 0.0, "M_EyeSlitIris": 0.0, "M_EyeSlitLid": 0.9}, "revision": 1, **baked}


ROUND_R = 0.058
ROUND_SINK = 0.035


def build_eye_round():
    """A big round eye: a white ball standing well proud of the skin, a wide blue iris and a large round pupil,
    in a thin rolled lid. H1_Blink shuts the lid, H2_Bulge pushes the ball out."""
    centre = Vector((0.0, 0.0, ROUND_R * 0.45))
    axis = Vector((0.0, 0.0, 1.0))
    sclera = _sclera_material("M_EyeRoundBallProc")
    iris_mat = _iris_material("M_EyeRoundIrisProc", centre, axis, math.radians(42.0), math.radians(21.0))
    ball = _eye_ball("EyeRound", centre, ROUND_R, math.radians(42.0), sclera, iris_mat)
    sclera.name, iris_mat.name = "M_EyeRoundBall", "M_EyeRoundIris"
    top = ROUND_R * 0.5
    lv, lf = _lid_ring(ROUND_R, ROUND_SINK, top)
    lid_mat = _lid_material("M_EyeRoundLidProc")
    lid = bc.mesh_object("Lid", lv, lf, [lid_mat], parent=ball, fix_normals=False)
    lid_mat.name = "M_EyeRoundLid"
    baked = _bake([ball, lid], "PartEyeRound", keep=("EyeRound",), tints={"M_EyeRoundBall": sf.tint(_lin("#EEEAE2")), "M_EyeRoundIris": sf.tint(_lin("#4F72C8")),
                                                        "M_EyeRoundLid": sf.tint(_lin("#B88E7E"))}, size=256)
    pts = _check_pivot("eye_round", ROUND_SINK)
    foot = _footprint(pts, z_max=0.02)

    def bulge(co):
        return Vector((co.x, co.y, co.z + 0.25 * ROUND_R * max(0.0, co.z) / (ROUND_R * 1.45)))

    handles = _shape_keys(lid, [("H1_Blink", _blink_fn(ROUND_R, top), "the lid rolls over the ball to a slit")])
    handles += _shape_keys(ball, [("H2_Bulge", bulge, "the ball pushed 25% further out")])
    rules = _rules("eye_round", round(foot + 0.001, 3), ROUND_SINK, "forward_cone", ["spine", "part"], 60, 45)
    rules["handles"] = handles
    rules["handles_note"] = "H1 is on Lid, H2 on EyeRound; both are 0 to 1000 per mille."
    return {"purpose": "Creature eye part (PROPOSED): a big round eye, white with a wide blue iris and a large pupil, in a thin rolled lid; blinks on a shape key.",
            "category": "part", "part_type": "eye_round", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_EyeRoundBall": 0.0, "M_EyeRoundIris": 0.0, "M_EyeRoundLid": 0.9}, "revision": 1, **baked}


CLUSTER_SINK = 0.015
CLUSTER_EYES = ((0.017, 0.012, 0.016), (-0.017, 0.012, 0.016), (0.03, -0.014, 0.01), (-0.03, -0.014, 0.01))   # x, y, radius


def build_eye_cluster():
    """Four glossy black eyes, two big ones toward the head and two small ones behind, set in a low fleshy pad,
    like a spider's. H1_Bulge raises the eyes, H2_Spread moves them apart."""
    unit, faces = bc.icosphere(3)
    pad_v = []
    for co in unit:
        n = Vector(co).normalized()
        pad_v.append((n.x * 0.05, n.y * 0.042, max(-CLUSTER_SINK, n.z * 0.016)))
    pad_mat = _lid_material("M_EyeClusterPadProc")
    pad = bc.mesh_object("EyeCluster", pad_v, faces, [pad_mat])
    pad_mat.name = "M_EyeClusterPad"
    unit2, faces2 = bc.icosphere(3)
    ev, ef, centres = [], [], []
    for x, y, r in CLUSTER_EYES:
        c = Vector((x, y, 0.012 + r * 0.25))
        centres.append(c)
        bc.append(ev, ef, [tuple(c + Vector(co).normalized() * r) for co in unit2], faces2)
    sh = sf.Shader("M_EyeClusterLensProc")
    glint = sh.remap(sh.noise(40.0, 2.0), 0.45, 0.6)
    sh.bump(glint, 0.02, 0.0002)
    lens = sh.out(_grey(sh, sh.math("ADD", 0.7, sh.math("MULTIPLY", glint, 0.25)), 0.6), 0.05)
    eyes = bc.mesh_object("Eyes", ev, ef, [lens], parent=pad)
    lens.name = "M_EyeClusterLens"
    baked = _bake([pad, eyes], "PartEyeCluster", {"M_EyeClusterPad": sf.tint(_lin("#A88478")), "M_EyeClusterLens": sf.tint(_lin("#2A2436"))},
                  size=256, tolerance=0.0004)      # the small lenses stay round
    pts = _check_pivot("eye_cluster", CLUSTER_SINK)
    foot = _footprint(pts)

    def nearest(co):
        return min(centres, key=lambda c: (c - co).length)

    def bulge(co):
        c = nearest(co)
        return co + Vector((0.0, 0.0, 0.006))

    def spread(co):
        c = nearest(co)
        return co + Vector((c.x * 0.25, c.y * 0.15, 0.0))

    handles = _shape_keys(eyes, [("H1_Bulge", bulge, "the eyes stand 6 mm prouder of the pad"),
                                 ("H2_Spread", spread, "the eyes 25% further apart across, 15% along")])
    rules = _rules("eye_cluster", round(foot + 0.001, 3), CLUSTER_SINK, "forward_cone", ["spine", "part"], 60, 45)
    rules["handles"] = handles
    rules["handles_note"] = "Both handles are on Eyes; the pad stays put."
    return {"purpose": "Creature eye part (PROPOSED): four glossy black eyes, two big and two small, in a low fleshy pad.",
            "category": "part", "part_type": "eye_cluster", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_EyeClusterPad": 0.9, "M_EyeClusterLens": 0.0}, "revision": 1, **baked}


JAW_LEN = 0.15
JAW_SINK = 0.025
JAW_W = 0.034           # half-width across x at the root
JAW_H = 0.012           # each jaw's half-depth along y
JAW_GAP = 0.004         # between the closed jaws
JAW_TEETH = 7           # per side of each jaw


def build_jaw():
    """A long toothy snout: an upper jaw (+Y) and a lower jaw (-Y) running out along +Z from a fleshy collar,
    rows of pointed teeth along their edges and pink gums between. H1_Open drops the lower jaw, H2_Length
    lengthens both."""
    steps, sides = 14, 24
    verts, fcs, mats_ix = [], [], []
    hinge_z = 0.008
    for sign in (1.0, -1.0):
        path = [Vector((0.0, sign * (JAW_GAP / 2 + JAW_H) * (1.0 - 0.35 * t), hinge_z + (JAW_LEN - hinge_z) * t)) for t in (i / steps for i in range(steps + 1))]

        def radius_at(i, a, sign=sign):
            if i == steps:
                return 0.0
            t = i / steps
            w = JAW_W * (1.0 - 0.55 * t ** 1.4) * (1.0 if t < 0.9 else math.sqrt(max(0.0, 1.0 - ((t - 0.9) / 0.1) ** 2)))
            h = JAW_H * (1.0 - 0.4 * t) * (1.0 if t < 0.86 else math.sqrt(max(0.05, 1.0 - ((t - 0.86) / 0.14) ** 2)))
            # _tube's ring runs cos(a) along y and sin(a) along x (its frame for a path up +Z); the side facing the
            # other jaw is flattened so the closed jaws meet flat.
            cy, sx = math.cos(a), math.sin(a)
            hy = h * (0.55 if cy * sign < 0 else 1.0)
            return 1.0 / math.sqrt((cy / hy) ** 2 + (sx / w) ** 2)

        v, f, _ = _tube(path, radius_at, sides)
        base = len(verts)
        bc.append(verts, fcs, v, f)
        for face in f:
            ys = sum(v[k][1] for k in face) / len(face)
            cy = sum(path[min(steps, max(0, int(round((v[k][2] - hinge_z) / (JAW_LEN - hinge_z) * steps))))].y for k in face) / len(face)
            mats_ix.append(1 if (ys - cy) * sign < -0.004 else 0)
    cv, cf = mp._sweep([Vector((0.0, 0.0, z)) for z in (0.02, 0.006, -0.01, -JAW_SINK)], lambda i, a: (JAW_W * 1.05) * (1.0 + 0.12 * i) * math.sqrt((0.8 * math.cos(a)) ** 2 + math.sin(a) ** 2), 24)
    bc.append(verts, fcs, cv, cf)
    mats_ix.extend([0] * len(cf))
    skin = sf.Shader("M_JawSkinProc")
    scales = skin.remap(skin.voronoi(260.0, 0.6, feature="DISTANCE_TO_EDGE"), 0.0, 0.07)
    skin.bump(scales, 0.35, 0.0008)
    gum = sf.Shader("M_JawGumProc")
    wr = gum.noise(160.0, 3.0)
    gum.bump(wr, 0.3, 0.0008)
    mats = [skin.out(_grey(skin, skin.math("ADD", 0.66, skin.math("MULTIPLY", scales, 0.3)), 0.6), 0.55),
            gum.out(_grey(gum, gum.remap(wr, 0.3, 0.7), 0.75), 0.35)]
    jaw = bc.mesh_object("Jaw", verts, fcs, mats, mats_ix)
    mats[0].name, mats[1].name = "M_JawSkin", "M_JawGum"
    tverts, tfaces, roots = [], [], []
    for sign in (1.0, -1.0):
        for side in (1.0, -1.0):
            for n in range(JAW_TEETH):
                t = 0.12 + 0.78 * n / (JAW_TEETH - 1)
                w = JAW_W * (1.0 - 0.55 * t ** 1.4) * 0.82
                z = hinge_z + (JAW_LEN - hinge_z) * t
                yc = sign * (JAW_GAP / 2 + JAW_H * (1.0 - 0.35 * t) * 0.45)
                root = Vector((side * w, yc, z))
                length = (0.012 if n % 3 == 1 else 0.008) * (1.0 - 0.3 * t)
                d = Vector((-side * 0.15, -sign, 0.1)).normalized()
                path = [root + d * (length * k) for k in (0.0, 0.5, 1.0)]
                v, f, _ = _tube(path, lambda i, a, L=length: 0.0 if i == 2 else 0.0032 * (1.0 - i / 2) ** 0.7 * (1.3 if L > 0.01 else 1.0), 6)
                bc.append(tverts, tfaces, v, f)
                roots.append(root)
    tooth_sh = sf.Shader("M_JawToothProc")
    streak = tooth_sh.noise(120.0, 3.0, vector=mp._stretched(tooth_sh, (4.0, 4.0, 0.4)))
    tooth_sh.bump(streak, 0.15, 0.0005)
    tooth_mat = tooth_sh.out(_grey(tooth_sh, tooth_sh.remap(streak, 0.2, 0.8, 0.8, 1.0), 0.8), 0.2)
    teeth = bc.mesh_object("Teeth", tverts, tfaces, [tooth_mat], parent=jaw)
    tooth_mat.name = "M_JawTooth"
    baked = _bake([jaw, teeth], "PartJaw", {"M_JawSkin": sf.tint(_lin("#8C8A62")), "M_JawGum": sf.tint(_lin("#B86A70")),
                                           "M_JawTooth": sf.tint(_lin("#EDE3C8"))})
    pts = _check_pivot("jaw", JAW_SINK)
    foot = _footprint(pts)

    def upper(co, tooth=False):
        if tooth:
            return min(roots, key=lambda r: (r - co).length).y > 0
        return co.y > 0

    def open_fn(tooth):
        def open_(co):
            if co.z <= hinge_z:
                return co
            a = math.radians(-6.0) if upper(co, tooth) else math.radians(26.0)
            rel = Vector((0.0, co.y, co.z - hinge_z))
            rot = Matrix.Rotation(-a, 3, "X") @ rel
            return Vector((co.x, rot.y, rot.z + hinge_z))
        return open_

    def length(co):
        if co.z > 0.02:
            co.z = 0.02 + (co.z - 0.02) * 1.35
        return co

    handles = _shape_keys(jaw, [("H1_Open", open_fn(False), "the lower jaw drops 26 degrees about the hinge, the upper lifts 6"),
                                ("H2_Length", length, "both jaws 35% longer")])
    _shape_keys(teeth, [("H1_Open", open_fn(True), ""), ("H2_Length", length, "")])
    rules = _rules("jaw", round(foot + 0.001, 3), JAW_SINK, "forward_cone", ["spine"], 40, 30, centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = "Both handles are on Jaw and Teeth (the teeth ride their jaw)."
    return {"purpose": "Creature mouth part (PROPOSED): a long toothy snout, scaly upper and lower jaws with rows of pointed teeth and pink gums, opening on a shape key.",
            "category": "part", "part_type": "jaw", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_JawSkin": 0.85, "M_JawGum": 0.0, "M_JawTooth": 0.0}, "revision": 1, **baked}


BILL_LEN = 0.14
BILL_SINK = 0.02
BILL_W = 0.036          # half-width across x where the bill is broadest
BILL_H = 0.014          # half-depth along y at the root


def build_bill():
    """A broad flat bill like a platypus's or a duck's: wide across x, thin along y, a rounded spoon tip, two
    nostril dents near the root and a seam where the halves meet, on a fleshy gape. H1_Open parts the halves,
    H2_Width broadens the bill."""
    # Authored at its budget and kept whole, so the gape's edge stays a clean ring; the rings crowd toward the
    # rounded tip. Ring 3 (t 0.1875) is z 0.01, where the gape meets the bill.
    ts = [k / 16 for k in range(13)] + [0.8, 0.85, 0.89, 0.93, 0.96, 0.985, 1.0]
    steps, sides = len(ts) - 1, 24
    path, half_w, half_h = [], [], []
    for t in ts:
        path.append(Vector((0.0, -0.008 * t ** 3, -BILL_SINK + (BILL_LEN + BILL_SINK) * t)))
        w = BILL_W * (0.7 + 0.42 * math.sin(min(1.0, t / 0.78) * math.pi / 2))
        if t > 0.82:
            w *= math.sqrt(max(0.0, 1.0 - ((t - 0.82) / 0.18) ** 2))
        half_w.append(w)
        half_h.append(BILL_H * (1.15 if t < 0.12 else (1.0 - 0.6 * t)) * (1.0 if t <= 0.82 else math.sqrt(max(0.0, 1.0 - ((t - 0.82) / 0.18) ** 2))))

    def radius_at(i, a):
        if i == steps:
            return 0.0
        c, s_ = math.cos(a), math.sin(a)
        # a superellipse: flat top and bottom, rounded edges
        e = 2.5
        rx, ry = half_w[i], half_h[i]
        denom = (abs(s_) / rx) ** e + (abs(c) / ry) ** e      # the sweep's ring: cos(a) along y, sin(a) along x
        return denom ** (-1.0 / e)

    verts, faces = mp._sweep(path, radius_at, sides)
    face_materials = [0 if sum(verts[k][2] for k in f) / len(f) < 0.0095 else 1 for f in faces]
    gape = sf.Shader("M_BillGapeProc")
    wr = gape.noise(140.0, 3.0)
    gape.bump(wr, 0.3, 0.001)
    horn = sf.Shader("M_BillProc")
    seam = horn.remap(horn.math("ABSOLUTE", horn.axis("Y")), 0.0025, 0.0)
    nostrils = horn.math("MULTIPLY", horn.remap(horn.vmath("LENGTH", horn.vmath("SUBTRACT", horn.vmath("MULTIPLY", horn.vmath("ABSOLUTE", horn.pos), (1.0, 0.0, 1.0)), (0.011, 0.0, 0.045))), 0.0045, 0.0025),
                         horn.remap(horn.axis("Y"), 0.0, 0.004))          # on the upper half only
    nail = horn.remap(horn.axis("Z"), 0.118, 0.13)                   # a darker horny nail at the tip
    pits = horn.remap(horn.voronoi(240.0, 0.8), 0.15, 0.0)
    h = horn.math("SUBTRACT", horn.math("MULTIPLY", pits, 0.25), horn.math("ADD", seam, horn.math("MULTIPLY", nostrils, 0.8)))
    horn.bump(h, 0.35, 0.0012)
    mats = [gape.out(_grey(gape, gape.remap(wr, 0.3, 0.7), 0.8), 0.6),
            horn.out(_grey(horn, horn.math("SUBTRACT", 0.85, horn.math("ADD", horn.math("ADD", horn.math("MULTIPLY", seam, 0.4), horn.math("MULTIPLY", nostrils, 0.5)),
                                                                         horn.math("MULTIPLY", nail, 0.35))), 0.4), 0.45)]
    bill = bc.mesh_object("Bill", verts, faces, mats, face_materials)
    mats[0].name, mats[1].name = "M_BillGape", "M_Bill"
    baked = _bake([bill], "PartBill", keep=("Bill",), tints={"M_BillGape": sf.tint(_lin("#C98A7A")), "M_Bill": sf.tint(_lin("#D9A14A"))})
    pts = _check_pivot("bill", BILL_SINK)
    foot = _footprint(pts)

    def open_(co):
        if co.z <= 0.006:
            return co
        t = min(1.0, max(0.0, (co.z + BILL_SINK) / (BILL_LEN + BILL_SINK)))
        a = math.radians(16.0) * (1 if co.y >= -0.008 * t ** 3 else -1)          # above or below the bill's centreline
        rel = Vector((0.0, co.y, co.z - 0.006))
        rot = Matrix.Rotation(a, 3, "X") @ rel
        return Vector((co.x, rot.y, rot.z + 0.006))

    def width(co):
        if co.z > 0.012:
            co.x *= 1.0 + 0.3 * min(1.0, (co.z - 0.012) / 0.04)
        return co

    handles = _shape_keys(bill, [("H1_Open", open_, "the halves parted 16 degrees each about the gape"),
                                 ("H2_Width", width, "the bill 30% broader past its root")])
    rules = _rules("bill", round(foot + 0.001, 3), BILL_SINK, "forward_cone", ["spine"], 40, 30, centerline="required")
    rules["handles"] = handles
    return {"purpose": "Creature mouth part (PROPOSED): a broad flat spoon-tipped bill with nostril dents and a closing seam, on a fleshy gape; opens on a shape key.",
            "category": "part", "part_type": "bill", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_BillGape": 0.8, "M_Bill": 0.1}, "revision": 1, **baked}


# --- Set 7: more feet and hands ------------------------------------------------------------------------

def _skin_material(name, scale=220.0, lo=0.75, rough=0.7):
    sh = sf.Shader(name)
    pebble = sh.remap(sh.voronoi(scale, 0.8), 0.25, 0.05)
    sh.bump(sh.math("SUBTRACT", 0.0, pebble), 0.35, 0.001)
    return sh.out(_grey(sh, sh.math("SUBTRACT", 1.0, sh.math("MULTIPLY", pebble, 0.35)), lo), rough)


def _scale_material(name, scale=300.0):
    sh = sf.Shader(name)
    groove = sh.remap(sh.voronoi(scale, 0.45, feature="DISTANCE_TO_EDGE"), 0.0, 0.09)
    sh.bump(groove, 0.4, 0.0008)
    return sh.out(_grey(sh, sh.math("ADD", 0.6, sh.math("MULTIPLY", groove, 0.35)), 0.6), 0.55)


def _nail_material(name):
    sh = sf.Shader(name)
    ns = sh.noise(90.0, 3.0, vector=mp._stretched(sh, (0.4, 5.0, 5.0)))
    sh.bump(ns, 0.2, 0.001)
    return sh.out(_grey(sh, sh.remap(ns, 0.3, 0.7), 0.8), 0.3)


def _nail(tip, d, length=0.026, width=0.011, down=0.0):
    """A small horn nail cone at a toe tip, pointing along d (and `down` toward -Z), its base sunk in the toe."""
    d = (d + Vector((0.0, 0.0, -down))).normalized()
    prof = [(0.0, 0.0), (0.004, width), (length * 0.55, width * 0.85), (length, 0.0)]
    nv, nf, _ = bc.revolve(prof, 12)
    rot = Vector((0.0, 1.0, 0.0)).rotation_difference(d)
    return [tuple(tip - d * 0.006 + rot @ Vector(v)) for v in nv], nf


def _ground(verts):
    return [(x, y, max(z, 0.0)) for x, y, z in verts]


def _foot_handles(objs, spread_deg, from_y, longer):
    def spread(co):
        if co.y > from_y:
            a = math.radians(spread_deg) * (co.x / max(abs(co.x), 1e-6)) * min(1.0, abs(co.x) / 0.02)
            return Matrix.Rotation(-a, 3, "Z") @ co
        return co

    def long_(co):
        if co.y > from_y:
            co.y = from_y + (co.y - from_y) * (1.0 + longer)
        return co

    handles = []
    for o in objs:
        handles = _shape_keys(o, [("H1_Spread", spread, f"toes splayed a further {spread_deg:.0f} degrees"),
                                  ("H2_Long", long_, f"toes {longer * 100:.0f}% longer")])
    return handles


def _ankle(top=0.09, r0=0.018, y=-0.01):
    # Swept from the top down, so the sweep's capped start closes the ankle where it meets the limb.
    return mp._sweep([Vector((0.0, y, 0.02 + (top - 0.02) * t)) for t in (1.0, 0.66, 0.33, 0.0)], lambda i, a: r0 + 0.004 * i, 20)


def build_foot_webbed():
    """A webbed swimmer's foot standing on its sole: three long slender toes fanned wide with a thin scalloped web
    between them and small claws at the tips. H1_Spread fans the toes and web, H2_Long lengthens them."""
    unit, faces = bc.icosphere(3)
    palm_c = Vector((0.0, 0.0, 0.026))
    verts, fcs = [], []
    for co in unit:
        n = Vector(co).normalized()
        verts.append(tuple(palm_c + Vector((n.x * 0.036, n.y * 0.036, n.z * 0.026))))
    fcs = list(faces)
    av, af = _ankle(0.09, 0.016)
    bc.append(verts, fcs, av, af)
    toes, paths = [], []
    for ang in (-34.0, 0.0, 34.0):
        d = Vector((math.sin(math.radians(ang)), math.cos(math.radians(ang)), 0.0))
        start = palm_c + d * 0.02 + Vector((0.0, 0.0, -0.008))
        path = [start + d * (0.1 * t) + Vector((0.0, 0.0, -0.012 * t + 0.004 * math.sin(math.pi * t))) for t in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0)]
        tv, tf, _ = _tube(path, lambda i, a: 0.0 if i == 5 else 0.0105 * (1.0 - 0.13 * i), 12)
        bc.append(verts, fcs, tv, tf)
        toes.append((path[-1], d))
        paths.append(path)
    skin = _skin_material("M_FootWebbedSkinProc")
    foot = bc.mesh_object("FootWebbed", _ground(verts), fcs, [skin])
    skin.name = "M_FootWebbedSkin"
    wv, wf = [], []
    for left, right in ((paths[0], paths[1]), (paths[1], paths[2])):
        def point(s_, c, left=left, right=right):
            # s_ runs root (0) to tip (1) along the toes, c across from one toe to the next; the free edge scallops in.
            i = s_ * 4.0
            k = min(3, int(i))
            f = i - k
            a = left[k].lerp(left[k + 1], f)
            b = right[k].lerp(right[k + 1], f)
            p = a.lerp(b, c)
            sag = 0.012 * s_ ** 2 * math.sin(math.pi * c)       # the web's edge bows back toward the palm
            p = p - (a.lerp(b, 0.5) - palm_c).normalized() * sag
            return Vector((p.x, p.y, max(0.004, p.z + 0.002)))
        _membrane(wv, wf, point, 6, 6, thickness=0.0012, facing=Vector((0.0, 0.0, 1.0)))
    web_sh = sf.Shader("M_FootWebbedWebProc")
    veins = web_sh.noise(160.0, 2.0, vector=mp._stretched(web_sh, (2.0, 0.3, 1.0)))
    web_sh.bump(veins, 0.2, 0.0005)
    web_mat = web_sh.out(_grey(web_sh, web_sh.remap(veins, 0.3, 0.7), 0.7), 0.5)
    web = bc.mesh_object("Web", wv, wf, [web_mat], parent=foot, fix_normals=False)
    web_mat.name = "M_FootWebbedWeb"
    nail_mat = _nail_material("M_FootWebbedNailProc")
    nv, nf = [], []
    for tip, d in toes:
        v, f = _nail(tip, d, 0.02, 0.0075, down=0.3)
        bc.append(nv, nf, _ground(v), f)
    nails = bc.mesh_object("Nails", nv, nf, [nail_mat], parent=foot)
    nail_mat.name = "M_FootWebbedNail"
    objs = [foot, web, nails]
    baked = _bake(objs, "PartFootWebbed", {"M_FootWebbedSkin": sf.tint(_lin("#9CA27E")), "M_FootWebbedWeb": sf.tint(_lin("#B4AE86")),
                                           "M_FootWebbedNail": sf.tint(_lin("#4E4438"))})
    pts = _check_pivot("foot_webbed", 0.0, ground=True)
    reach = max(math.hypot(p.x, p.y) for p in pts)
    handles = _foot_handles(objs, 12.0, 0.02, 0.3)
    rules = _rules("foot_webbed", round(reach + 0.001, 3), 0.0, "ground", ["limb_end"], 25, 15)
    rules["handles"] = handles
    rules["pivot_note"] = "Ground part: the sole sits on the pivot; the ankle top (z 0.09 m) meets the limb tip."
    return {"purpose": "Creature foot part (PROPOSED): a webbed swimmer's foot, three long toes fanned wide with a scalloped web and small claws.",
            "category": "part", "part_type": "foot_webbed", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_FootWebbedSkin": 0.85, "M_FootWebbedWeb": 0.9, "M_FootWebbedNail": 0.0}, "revision": 1, **baked}


def build_foot_paw():
    """A round padded paw standing on its sole: a broad palm and four plump toes in an arc toward the head, each
    with a short dark claw. H1_Spread splays the toes, H2_Long lengthens them."""
    unit, faces = bc.icosphere(3)
    palm_c = Vector((0.0, -0.008, 0.03))
    verts, fcs = [], []
    for co in unit:
        n = Vector(co).normalized()
        verts.append(tuple(palm_c + Vector((n.x * 0.05, n.y * 0.045, n.z * 0.03))))
    fcs = list(faces)
    av, af = _ankle(0.095, 0.024, -0.015)
    bc.append(verts, fcs, av, af)
    toe_unit, toe_faces = bc.icosphere(2)
    toes = []
    for ang in (-48.0, -16.0, 16.0, 48.0):
        d = Vector((math.sin(math.radians(ang)), math.cos(math.radians(ang)), 0.0))
        c = palm_c + d * 0.05 + Vector((0.0, 0.0, -0.008))
        r = 0.019 if abs(ang) < 30 else 0.016
        bc.append(verts, fcs, [tuple(c + Vector((n.x * r, n.y * r * 1.15, n.z * r * 0.95))) for n in (Vector(co).normalized() for co in toe_unit)], toe_faces)
        toes.append((c + d * r * 1.0 + Vector((0.0, 0.0, 0.002)), d))
    skin = _skin_material("M_FootPawSkinProc", scale=260.0, lo=0.78, rough=0.75)
    paw = bc.mesh_object("FootPaw", _ground(verts), fcs, [skin])
    skin.name = "M_FootPawSkin"
    nail_mat = _nail_material("M_FootPawClawProc")
    nv, nf = [], []
    for tip, d in toes:
        v, f = _nail(tip, d, 0.018, 0.006, down=0.5)
        bc.append(nv, nf, _ground(v), f)
    claws = bc.mesh_object("Claws", nv, nf, [nail_mat], parent=paw)
    nail_mat.name = "M_FootPawClaw"
    objs = [paw, claws]
    baked = _bake(objs, "PartFootPaw", {"M_FootPawSkin": sf.tint(_lin("#B8977C")), "M_FootPawClaw": sf.tint(_lin("#3E3630"))})
    pts = _check_pivot("foot_paw", 0.0, ground=True)
    reach = max(math.hypot(p.x, p.y) for p in pts)
    handles = _foot_handles(objs, 10.0, 0.02, 0.25)
    rules = _rules("foot_paw", round(reach + 0.001, 3), 0.0, "ground", ["limb_end"], 25, 15)
    rules["handles"] = handles
    rules["pivot_note"] = "Ground part: the sole sits on the pivot; the ankle top (z 0.095 m) meets the limb tip."
    return {"purpose": "Creature foot part (PROPOSED): a round padded paw with four plump toes in an arc and short dark claws.",
            "category": "part", "part_type": "foot_paw", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_FootPawSkin": 0.85, "M_FootPawClaw": 0.0}, "revision": 1, **baked}


def build_foot_talon():
    """A bird's scaly foot standing on its toes: a thin scaled shank, three long knuckled toes forward and one
    back, each ending in a hooked talon. H1_Spread splays the toes, H2_Long lengthens them."""
    verts, fcs = [], []
    sv, sf_ = mp._sweep([Vector((0.0, -0.004, 0.02 + 0.08 * t)) for t in (1.0, 0.75, 0.5, 0.25, 0.0)],
                        lambda i, a: 0.011 + 0.0015 * i, 14)
    bc.append(verts, fcs, sv, sf_)
    unit, faces = bc.icosphere(2)
    heel = Vector((0.0, -0.004, 0.016))
    bc.append(verts, fcs, [tuple(heel + Vector(co).normalized() * 0.017) for co in unit], faces)
    talons = []
    for ang, length in ((-26.0, 0.1), (0.0, 0.115), (26.0, 0.1), (180.0, 0.055)):
        d = Vector((math.sin(math.radians(ang)), math.cos(math.radians(ang)), 0.0))
        start = heel + d * 0.006 + Vector((0.0, 0.0, -0.004))
        ts = (0.0, 0.2, 0.4, 0.55, 0.7, 0.85, 1.0)
        path = [start + d * (length * t) + Vector((0.0, 0.0, -0.006 * t)) for t in ts]

        def radius_at(i, a, ts=ts):
            if i == len(ts) - 1:
                return 0.0
            t = ts[i]
            return 0.0072 * (1.0 - 0.3 * t) * (1.0 + 0.16 * math.exp(-((t - 0.4) / 0.06) ** 2) + 0.14 * math.exp(-((t - 0.7) / 0.06) ** 2))

        tv, tf, _ = _tube(path, radius_at, 10)
        bc.append(verts, fcs, tv, tf)
        talons.append((path[-1], d))
    scale = _scale_material("M_FootTalonScaleProc", 280.0)
    foot = bc.mesh_object("FootTalon", _ground(verts), fcs, [scale])
    scale.name = "M_FootTalonScale"
    nail_mat = _nail_material("M_FootTalonClawProc")
    nv, nf = [], []
    for tip, d in talons:
        steps = 8
        base = tip - d * 0.004 + Vector((0.0, 0.0, 0.004))
        path = [base + d * (0.02 * math.sin(1.3 * k / steps) / math.sin(1.3)) + Vector((0.0, 0.0, -0.016 * (1 - math.cos(1.3 * k / steps)) / (1 - math.cos(1.3)) + 0.0)) for k in range(steps + 1)]
        v, f, _ = _tube(path, lambda i, a: 0.0 if i == steps else 0.0055 * (1.0 - i / steps) ** 0.8, 8)
        bc.append(nv, nf, _ground(v), f)
    claws = bc.mesh_object("Talons", nv, nf, [nail_mat], parent=foot)
    nail_mat.name = "M_FootTalonClaw"
    objs = [foot, claws]
    baked = _bake(objs, "PartFootTalon", {"M_FootTalonScale": sf.tint(_lin("#C8A24E")), "M_FootTalonClaw": sf.tint(_lin("#2E2A28"))})
    pts = _check_pivot("foot_talon", 0.0, ground=True)
    reach = max(math.hypot(p.x, p.y) for p in pts)
    handles = _foot_handles(objs, 12.0, 0.01, 0.25)
    rules = _rules("foot_talon", round(reach + 0.001, 3), 0.0, "ground", ["limb_end"], 25, 15)
    rules["handles"] = handles
    rules["pivot_note"] = "Ground part: the toes sit on the pivot; the shank top (z 0.1 m) meets the limb tip."
    return {"purpose": "Creature foot part (PROPOSED): a bird's scaly foot, three knuckled toes forward and one back, each with a hooked talon.",
            "category": "part", "part_type": "foot_talon", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_FootTalonScale": 0.4, "M_FootTalonClaw": 0.0}, "revision": 1, **baked}


def _hand_rules(part_type, foot):
    rules = _rules(part_type, round(foot + 0.001, 3), 0.025, "normal", ["limb_end"], 40, 40)
    rules["capabilities"] = ["grasper"]
    return rules


def build_hand_paw():
    """A soft mitten paw on the end of the limb (+Z out along it): a rounded palm, four short fat fingers fused
    side by side and a stubby thumb, with small nails. H1_Grip curls the fingers in, H2_Spread fans them."""
    unit, faces = bc.icosphere(3)
    verts, fcs = [], []
    bc.append(verts, fcs, [tuple(Vector((n.x * 0.042, n.y * 0.03, 0.035 + n.z * 0.036))) for n in (Vector(co).normalized() for co in unit)], faces)
    wv, wf = mp._sweep([Vector((0, 0, z)) for z in (0.0, -0.012, -0.024)], lambda i, a: 0.026 + 0.003 * i, 16)
    bc.append(verts, fcs, wv, wf)
    tips = []
    for fx in (-0.027, -0.009, 0.009, 0.027):
        base = Vector((fx, 0.002, 0.058))
        path = [base + Vector((fx * 0.15 * t, 0.006 * t * t, 0.032 * t)) for t in FINGER_T]
        v, f, _ = _tube(path, lambda i, a: _finger_r(FINGER_T[i], 0.0115), 12)
        bc.append(verts, fcs, v, f)
        tips.append((path[-2], Vector((0.0, 0.25, 1.0)).normalized()))
    tpath = [Vector((0.036, 0.012, 0.03)) + Vector((0.022 * t, 0.014 * t, 0.018 * t)) for t in FINGER_T]
    v, f, _ = _tube(tpath, lambda i, a: _finger_r(FINGER_T[i], 0.012), 12)
    bc.append(verts, fcs, v, f)
    skin = _skin_material("M_HandPawSkinProc", 240.0, 0.78, 0.75)
    paw = bc.mesh_object("HandPaw", verts, fcs, [skin])
    skin.name = "M_HandPawSkin"
    nail_mat = _nail_material("M_HandPawNailProc")
    nv, nf = [], []
    for tip, d in tips:
        v, f = _nail(tip + Vector((0.0, 0.004, 0.0)), d, 0.012, 0.0055)
        bc.append(nv, nf, v, f)
    nails = bc.mesh_object("Nails", nv, nf, [nail_mat], parent=paw)
    nail_mat.name = "M_HandPawNail"
    baked = _bake([paw, nails], "PartHandPaw", {"M_HandPawSkin": sf.tint(_lin("#BE9A82")), "M_HandPawNail": sf.tint(_lin("#4A4038"))})
    pts = _check_pivot("hand_paw", 0.025)
    foot = _footprint(pts, z_max=0.02)

    def grip(co):
        if co.z > 0.055:
            k = min(1.0, (co.z - 0.055) / 0.04)
            ang = math.radians(75.0) * k
            dz = co.z - 0.055
            return Vector((co.x, co.y + dz * math.sin(ang), 0.055 + dz * math.cos(ang)))
        if co.x > 0.036:
            return Vector((co.x - 0.015 * (co.x - 0.036) / 0.022, co.y + 0.008, co.z))
        return co

    def spread(co):
        if co.z > 0.055:
            co.x *= 1.0 + 0.5 * min(1.0, (co.z - 0.055) / 0.04)
        return co

    handles = _shape_keys(paw, [("H1_Grip", grip, "fingers curl 75 degrees in, the thumb folds across"),
                                ("H2_Spread", spread, "fingers fan 50% wider at the tips")])
    _shape_keys(nails, [("H1_Grip", grip, ""), ("H2_Spread", spread, "")])
    rules = _hand_rules("hand_paw", foot)
    rules["handles"] = handles
    return {"purpose": "Creature hand part (PROPOSED): a soft mitten paw, four short fat fingers and a stubby thumb with small nails; grips on a shape key.",
            "category": "part", "part_type": "hand_paw", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_HandPawSkin": 0.85, "M_HandPawNail": 0.0}, "revision": 1, **baked}


PINCER_HINGE = 0.075


def build_hand_pincer():
    """A crab's pincer on the end of the limb (+Z out along it): a swollen shell palm, a fixed finger on -Y and
    a hinged finger on +Y closing on it, both with knobbly teeth along the bite and dark tips. Symmetric across
    x, so one piece serves both sides. H1_Open swings the hinged finger open, H2_Size swells the palm."""
    verts, fcs = [], []
    pv, pf = mp._sweep([Vector((0.0, 0.0, z)) for z in (-0.025, 0.0, 0.02, 0.045, 0.065, PINCER_HINGE + 0.008)],
                       lambda i, a: (0.026, 0.03, 0.042, 0.045, 0.038, 0.024)[i] * math.sqrt((1.0 * math.cos(a)) ** 2 + (0.72 * math.sin(a)) ** 2), 20)
    bc.append(verts, fcs, pv, pf)
    fingers = []
    for sign, length, curve in ((-1.0, 0.07, 0.016), (1.0, 0.075, 0.02)):
        ts = (0.0, 0.2, 0.4, 0.6, 0.75, 0.88, 1.0)
        root = Vector((0.0, sign * 0.016, PINCER_HINGE))
        path = [root + Vector((0.0, -sign * curve * t * t + sign * 0.008 * math.sin(math.pi * t), length * t)) for t in ts]
        v, f, _ = _tube(path, lambda i, a, ts=ts: 0.0 if i == len(ts) - 1 else 0.016 * (1.0 - 0.75 * ts[i]) * (1.0 + 0.12 * math.cos(2 * a)), 12)
        bc.append(verts, fcs, v, f)
        fingers.append((sign, path))
    teeth = []
    for sign, path in fingers:
        for k in (1, 2, 3, 4):
            p = path[k] + Vector((0.0, -sign * 0.0105 * (1.0 - 0.18 * k), 0.0))
            teeth.append(p)
            bc.append(verts, fcs, [tuple(p + Vector(co).normalized() * 0.0048) for co in bc.icosphere(1)[0]], bc.icosphere(1)[1])
    shell = sf.Shader("M_HandPincerShellProc")
    pits = shell.remap(shell.voronoi(180.0, 0.9), 0.12, 0.0)
    bumps = shell.noise(60.0, 3.0)
    shell.bump(shell.math("ADD", shell.math("MULTIPLY", pits, 0.5), shell.math("MULTIPLY", bumps, 0.3)), 0.35, 0.001)
    tips = shell.remap(shell.axis("Z"), PINCER_HINGE + 0.035, PINCER_HINGE + 0.055)
    shell_mat = shell.out(_grey(shell, shell.math("SUBTRACT", shell.math("SUBTRACT", 0.82, shell.math("MULTIPLY", pits, 0.2)), shell.math("MULTIPLY", tips, 0.6)), 0.15), 0.35)
    pincer = bc.mesh_object("HandPincer", verts, fcs, [shell_mat])
    shell_mat.name = "M_HandPincerShell"
    baked = _bake([pincer], "PartHandPincer", {"M_HandPincerShell": sf.tint(_lin("#C27A4E"))}, tolerance=0.0003)   # a smooth shell silhouette
    pts = _check_pivot("hand_pincer", 0.025)
    foot = _footprint(pts, z_max=0.02)

    def open_(co):
        if co.z > PINCER_HINGE - 0.004 and co.y > 0.004:
            rel = Vector((0.0, co.y - 0.016, co.z - PINCER_HINGE))
            rot = Matrix.Rotation(math.radians(-32.0), 3, "X") @ rel
            return Vector((co.x, rot.y + 0.016, rot.z + PINCER_HINGE))
        return co

    def size(co):
        if co.z < PINCER_HINGE + 0.004:
            k = max(0.0, min(1.0, co.z / 0.03))
            return Vector((co.x * (1.0 + 0.25 * k), co.y * (1.0 + 0.25 * k), co.z))
        return co

    handles = _shape_keys(pincer, [("H1_Open", open_, "the hinged finger swings 32 degrees open"),
                                   ("H2_Size", size, "the shell palm 25% stouter")])
    rules = _hand_rules("hand_pincer", foot)
    rules["handles"] = handles
    return {"purpose": "Creature hand part (PROPOSED): a crab's pincer, a pitted shell palm with a fixed and a hinged finger, knobbly teeth and dark tips; opens on a shape key.",
            "category": "part", "part_type": "hand_pincer", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_HandPincerShell": 0.35}, "revision": 1, **baked}


def build_hand_tentacle():
    """Three soft tentacle fingers curling out from a fleshy palm on the end of the limb (+Z out along it), with
    rows of pale suckers on their inner sides. H1_Curl rolls the tips in, H2_Spread fans the fingers."""
    unit, faces = bc.icosphere(3)
    verts, fcs = [], []
    bc.append(verts, fcs, [tuple(Vector((n.x * 0.034, n.y * 0.03, 0.022 + n.z * 0.03))) for n in (Vector(co).normalized() for co in unit)], faces)
    wv, wf = mp._sweep([Vector((0, 0, z)) for z in (0.0, -0.012, -0.024)], lambda i, a: 0.024 + 0.003 * i, 16)
    bc.append(verts, fcs, wv, wf)
    steps = 14
    for k in range(3):
        a0 = 2.0 * math.pi * k / 3 + math.pi / 2
        out = Vector((math.cos(a0), math.sin(a0), 0.0))
        base = Vector((0.0, 0.0, 0.035)) + out * 0.014
        path = []
        for i in range(steps + 1):
            t = i / steps
            # A C-shaped reach: out and up, then the tip curls back in toward the axis, so the three cup a grip.
            r_out = 0.045 * math.sin(math.pi * t) - 0.022 * t * t
            path.append(base + out * r_out + Vector((0.0, 0.0, 0.12 * t - 0.012 * t ** 3)))
        v, f, _ = _tube(path, lambda i, a: 0.0 if i == steps else 0.0135 * (1.0 - i / steps) ** 0.7 + 0.0012, 10)
        bc.append(verts, fcs, v, f)
    sh = sf.Shader("M_HandTentacleSkinProc")
    cells = sh.voronoi(120.0, 0.25)
    suckers = sh.remap(cells, 0.22, 0.12)                          # discs
    rims = sh.math("MULTIPLY", sh.remap(cells, 0.26, 0.2), sh.remap(cells, 0.1, 0.16))   # their raised rims
    sh.bump(sh.math("SUBTRACT", rims, sh.math("MULTIPLY", suckers, 0.6)), 0.6, 0.0015)
    mat = sh.out(_grey(sh, sh.math("ADD", 0.6, sh.math("ADD", sh.math("MULTIPLY", suckers, 0.25), sh.math("MULTIPLY", rims, 0.15))), 0.7), 0.4)
    tent = bc.mesh_object("HandTentacle", verts, fcs, [mat])
    mat.name = "M_HandTentacleSkin"
    baked = _bake([tent], "PartHandTentacle", {"M_HandTentacleSkin": sf.tint(_lin("#B98C9C"))})
    pts = _check_pivot("hand_tentacle", 0.025)
    foot = _footprint(pts, z_max=0.02)

    def curl(co):
        if co.z > 0.05:
            k = min(1.0, (co.z - 0.05) / 0.1)
            r = math.hypot(co.x, co.y)
            if r > 1e-6:
                s_ = max(0.4, 1.0 - 0.55 * k)
                return Vector((co.x * s_, co.y * s_, co.z - 0.02 * k ** 2))
        return co

    def spread(co):
        if co.z > 0.04:
            k = min(1.0, (co.z - 0.04) / 0.07)
            return Vector((co.x * (1.0 + 0.5 * k), co.y * (1.0 + 0.5 * k), co.z - 0.01 * k))
        return co

    handles = _shape_keys(tent, [("H1_Curl", curl, "the tips curl in toward the axis"),
                                 ("H2_Spread", spread, "the fingers fan 50% wider")])
    rules = _hand_rules("hand_tentacle", foot)
    rules["handles"] = handles
    return {"purpose": "Creature hand part (PROPOSED): three soft tentacle fingers with sucker rows curling from a fleshy palm; curls on a shape key.",
            "category": "part", "part_type": "hand_tentacle", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_HandTentacleSkin": 0.85}, "revision": 1, **baked}


# --- Set 7: more claws, horns and spikes ----------------------------------------------------------------

def _horn_material(name, ring_freq=300.0, lo=0.7):
    sh = sf.Shader(name)
    rings = sh.math("SINE", sh.math("MULTIPLY", sh.axis("Z"), ring_freq))
    streak = sh.noise(80.0, 3.0, vector=mp._stretched(sh, (5.0, 5.0, 0.3)))
    h = sh.math("ADD", sh.math("MULTIPLY", rings, 0.3), streak)
    sh.bump(h, 0.35, 0.0015)
    return sh.out(_grey(sh, sh.remap(h, -0.1, 0.9), lo), 0.35)


def _sheath_material(name):
    sh = sf.Shader(name)
    wr = sh.noise(160.0, 3.0)
    sh.bump(wr, 0.3, 0.0008)
    return sh.out(_grey(sh, sh.remap(wr, 0.3, 0.7), 0.8), 0.6)


def build_claw_scythe():
    """A mantis-like scythe: a long flat blade rising from a padded sheath and arcing forward (+Y) and down to a
    hooked point, with a row of small spines along its inner edge. Leans in toward the midline (-X): chiral.
    H1_Length lengthens the blade, H2_Hook curls the point further down."""
    steps = 20
    path = []
    for i in range(steps + 1):
        t = i / steps
        a = 2.5 * t                                     # sweeps up, over, forward and down to the hook
        path.append(Vector((-0.014 * t * t, 0.07 * (1 - math.cos(a)) / (1 - math.cos(2.2)) * 1.25, -0.015 + 0.1 * math.sin(a) / math.sin(1.57) + 0.012 * t)))

    def radius_at(i, a):
        if i == steps:
            return 0.0
        t = i / steps
        deep = 0.022 * (1.0 - t) ** 0.7 * (1.0 - 0.3 * t) + 0.0006     # across the blade, in the arc's plane
        thin = 0.0075 * (1.0 - t) ** 0.6 + 0.0005                      # its thickness across x: a thin blade
        if t < 0.12:
            deep = thin = 0.024                            # the round padded sheath
        return 1.0 / math.sqrt((math.cos(a) / deep) ** 2 + (math.sin(a) / thin) ** 2)

    verts, faces, ring = _tube(path, radius_at, 16)
    face_mats = [0 if r < 2 else 1 for r in ring]
    spines = []
    for k in range(4, steps - 3):
        curv = (path[k + 1] - 2 * path[k] + path[k - 1])
        inner = curv.normalized() if curv.length > 1e-9 else Vector((0.0, 0.0, -1.0))
        t = k / steps
        root = path[k] + inner * (0.022 * (1.0 - t) ** 0.7 * (1.0 - 0.3 * t) - 0.0015)
        tang = (path[k + 1] - path[k - 1]).normalized()
        d = (inner * 0.75 - tang * 0.66).normalized()
        size = 1.0 - 0.5 * t
        sv, sf_, _ = _tube([root, root + d * 0.008 * size, root + d * 0.016 * size], lambda i, a: 0.0 if i == 2 else 0.0034 * size * (1.0 - i / 2), 6)
        bc.append(verts, faces, sv, sf_)
        face_mats.extend([1] * len(sf_))
        spines.append(root)
    mats = [_sheath_material("M_ClawScytheSheathProc"), _horn_material("M_ClawScytheProc", 0.0, 0.6)]
    claw = bc.mesh_object("ClawScythe", verts, faces, mats, face_mats)
    mats[0].name, mats[1].name = "M_ClawScytheSheath", "M_ClawScythe"
    baked = _bake([claw], "PartClawScythe", {"M_ClawScytheSheath": sf.tint(_lin("#A88A6E")), "M_ClawScythe": sf.tint(_lin("#5A4E3E"))}, tolerance=0.0005)
    pts = _check_pivot("claw_scythe", 0.02)
    foot = _footprint(pts)
    mp._check(sum(p.x for p in pts) < 0, "claw_scythe: leans in toward the midline (-X on the right-hand piece)")

    def length(co):
        if co.z > 0.012:
            co.z = 0.012 + (co.z - 0.012) * 1.3
            co.y *= 1.3
        return co

    def hook(co):
        k = max(0.0, co.y) / 0.09
        co.z -= 0.025 * k ** 3
        return co

    handles = _shape_keys(claw, [("H1_Length", length, "the blade 30% longer"), ("H2_Hook", hook, "the point hooked further down")])
    rules = _rules("claw_scythe", round(foot + 0.001, 3), 0.02, "normal", ["limb_end", "limb"], 30, 30, centerline="forbidden", chiral=True)
    rules["handles"] = handles
    return {"purpose": "Creature claw part (PROPOSED): a mantis-like scythe, a long flat blade arcing forward to a hooked point with spines on its inner edge, right-hand piece (mirrored at bake).",
            "category": "part", "part_type": "claw_scythe", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_ClawScytheSheath": 0.8, "M_ClawScythe": 0.0}, "revision": 1, **baked}


def build_claw_rake():
    """Three parallel hooked claws in a row across x on a padded base, curving forward (+Y) like a raking hand.
    Symmetric across x. H1_Length lengthens them, H2_Hook curls the tips."""
    unit, faces = bc.icosphere(3)
    verts, fcs, mats_ix = [], [], []
    bc.append(verts, fcs, [tuple(Vector((n.x * 0.042, n.y * 0.026, max(-0.02, 0.006 + n.z * 0.02)))) for n in (Vector(co).normalized() for co in unit)], faces)
    mats_ix.extend([0] * len(faces))
    steps = 14
    for x0, length in ((-0.026, 0.085), (0.0, 0.1), (0.026, 0.085)):
        path = []
        for i in range(steps + 1):
            t = i / steps
            a = 1.15 * t
            path.append(Vector((x0 * (1.0 + 0.15 * t), 0.06 * (1 - math.cos(a)) / (1 - math.cos(1.15)) * length / 0.1, 0.012 + length * math.sin(a) / math.sin(1.15))))
        v, f, ring = _tube(path, lambda i, a: 0.0 if i == steps else 0.0115 * (1.0 - i / steps) ** 0.8 * (1.0 + 0.2 * max(0.0, -math.cos(a)) ** 2), 12)
        bc.append(verts, fcs, v, f)
        mats_ix.extend([0 if r < 1 else 1 for r in ring])
    mats = [_sheath_material("M_ClawRakePadProc"), _horn_material("M_ClawRakeProc", 0.0, 0.6)]
    rake = bc.mesh_object("ClawRake", verts, fcs, mats, mats_ix)
    mats[0].name, mats[1].name = "M_ClawRakePad", "M_ClawRake"
    baked = _bake([rake], "PartClawRake", {"M_ClawRakePad": sf.tint(_lin("#B08C74")), "M_ClawRake": sf.tint(_lin("#3E3630"))}, tolerance=0.0005)
    pts = _check_pivot("claw_rake", 0.02)
    foot = _footprint(pts)

    def length(co):
        if co.z > 0.02:
            co.z = 0.02 + (co.z - 0.02) * 1.35
            co.y *= 1.35
        return co

    def hook(co):
        k = max(0.0, co.z - 0.02) / 0.08
        co.y += 0.03 * k ** 3
        co.z -= 0.02 * k ** 3
        return co

    handles = _shape_keys(rake, [("H1_Length", length, "the claws 35% longer"), ("H2_Hook", hook, "the tips hooked further forward and down")])
    rules = _rules("claw_rake", round(foot + 0.001, 3), 0.02, "normal", ["limb_end", "limb"], 30, 30)
    rules["handles"] = handles
    return {"purpose": "Creature claw part (PROPOSED): three parallel hooked claws on a padded base, curving forward like a rake.",
            "category": "part", "part_type": "claw_rake", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_ClawRakePad": 0.85, "M_ClawRake": 0.0}, "revision": 1, **baked}


RAM_R = 0.056
RAM_TURN = 1.75 * math.pi


def build_horn_ram():
    """A ram's horn: thick and ridged, it rises from the skin, curls back over itself and round in a shrinking
    spiral that drifts out to the right (+X), so the coil clears itself, and ends in a point: chiral.
    H1_Length winds it further, H2_Thick thickens it."""
    h = 0.047                                           # the coil's underside stays clear of the skin
    centre = Vector((0.0, -RAM_R, h))
    path = [Vector((0.0, 0.0, -0.0185)), Vector((0.0, 0.0, h * 0.5))]
    n = 60
    for i in range(n + 1):
        f = i / n
        phi = RAM_TURN * f
        r = RAM_R * (1.0 - 0.6 * f)
        path.append(Vector((0.06 * f ** 1.3, centre.y + r * math.cos(phi), centre.z + r * math.sin(phi))))
    total = len(path) - 1

    def radius_at(i, a):
        if i == total:
            return 0.0
        t = max(0.0, (i - 1) / (total - 1))
        ridge = 1.0 + 0.11 * math.cos(2.0 * math.pi * 10.0 * t) * (1.0 - t)      # growth ridges, fading to the tip
        flat = 1.0 if math.cos(a) >= 0.0 else 1.0 - 0.18 * math.cos(a) ** 2       # the inner face flatter
        return (0.024 * (1.0 - t) ** 0.85 + 0.0006) * ridge * flat * (1.0 - 0.15 * math.sin(a) ** 2)

    verts, faces, _ = _tube(path, radius_at, 16)
    mat = _horn_material("M_HornRamProc", 0.0, 0.72)
    horn = bc.mesh_object("HornRam", verts, faces, [mat])
    mat.name = "M_HornRam"
    baked = _bake([horn], "PartHornRam", {"M_HornRam": sf.tint(_lin("#CDB894"))})
    pts = _check_pivot("horn_ram", 0.02)
    foot = _footprint(pts)
    mp._check(sum(p.x for p in pts) > 0, "horn_ram: drifts out to +X (the right-hand side ships)")

    def length(co):
        k = min(1.0, max(0.0, -co.y / 0.03))                  # eases in behind the root column
        co.x *= 1.0 + 0.25 * k
        co.y *= 1.0 + 0.15 * k
        return co

    def thick(co):
        # push each point away from the nearest point of the horn's centre line, more toward the root
        i = min(range(1, total), key=lambda j: (path[j] - co).length_squared)
        t = (i - 1) / (total - 1)
        return path[i] + (co - path[i]) * (1.0 + 0.3 * (1.0 - t)) if co.z > 0.0 else co

    handles = _shape_keys(horn, [("H1_Length", length, "the spiral drawn 15 to 25% wider"), ("H2_Thick", thick, "the horn up to 30% thicker, most at its root")])
    rules = _rules("horn_ram", round(foot + 0.001, 3), 0.02, "normal", ["spine", "part"], 60, 40, centerline="forbidden", chiral=True)
    rules["handles"] = handles
    return {"purpose": "Creature horn part (PROPOSED): a thick ridged ram's horn curling back in a spiral that drifts out to the right and ends in a point (mirrored at bake for the left).",
            "category": "part", "part_type": "horn_ram", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_HornRam": 0.1}, "revision": 1, **baked}


def build_horn_nose():
    """A stout conical horn on a broad base, sweeping up and forward (+Y) to a blunt point, with growth rings;
    meant for the snout or brow. H1_Length lengthens it, H2_Sweep tips it further forward."""
    steps = 16
    path = [Vector((0.0, 0.06 * (i / steps) ** 2.2, -0.0185 + 0.1585 * (i / steps))) for i in range(steps + 1)]

    def radius_at(i, a):
        if i == steps:
            return 0.0
        t = i / steps
        return (0.036 * (1.0 - t) ** 1.1 + 0.002) * (1.0 + 0.04 * math.cos(2.0 * math.pi * 6.0 * t))     # six growth rings

    verts, faces, _ = _tube(path, radius_at, 20)
    mat = _horn_material("M_HornNoseProc", 260.0, 0.65)
    horn = bc.mesh_object("HornNose", verts, faces, [mat])
    mat.name = "M_HornNose"
    baked = _bake([horn], "PartHornNose", {"M_HornNose": sf.tint(_lin("#B9AC92"))})
    pts = _check_pivot("horn_nose", 0.02)
    foot = _footprint(pts)

    def length(co):
        if co.z > 0.0:
            co.z *= 1.4
            co.y *= 1.4
        return co

    def sweep(co):
        k = max(0.0, co.z) / 0.14
        co.y += 0.04 * k ** 2
        co.z -= 0.012 * k ** 2
        return co

    handles = _shape_keys(horn, [("H1_Length", length, "the horn 40% longer"), ("H2_Sweep", sweep, "the point tipped further forward")])
    rules = _rules("horn_nose", round(foot + 0.001, 3), 0.02, "normal", ["spine", "part"], 60, 40)
    rules["handles"] = handles
    return {"purpose": "Creature horn part (PROPOSED): a stout ringed conical horn sweeping up and forward to a blunt point, for the snout or brow.",
            "category": "part", "part_type": "horn_nose", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_HornNose": 0.1}, "revision": 1, **baked}


def build_spike():
    """A single bony thorn with concave flanks and three keeled edges, raked a little back (-Y), flaring into a
    low oval scaly scute; for the back, shoulders, limbs or tail. H1_Length lengthens it, H2_Lean rakes it
    further back toward the tail."""
    steps = 16
    ts = [(i / steps) ** 1.35 for i in range(steps + 1)]             # rings packed toward the flared base
    path = [Vector((0.0, -0.014 * t * t, -0.012 + 0.135 * t)) for t in ts]

    def radius_at(i, a):
        if i == steps:
            return 0.0
        t, z = ts[i], path[i].z
        flare = 0.009 * (1.0 - min(1.0, max(0.0, z) / 0.014)) ** 2
        keel = 0.86 + 0.14 * abs(math.cos(1.5 * a)) ** 0.6       # three keels, fluted between
        return (0.019 * (1.0 - t) ** 1.5 + 0.0007 + flare) * keel

    verts, faces, _ = _tube(path, radius_at, 24)
    unit, ufaces = bc.icosphere(3)
    plate = [tuple(Vector((n.x * 0.034, n.y * 0.04, max(-0.015, n.z * 0.0075)))) for n in (Vector(co).normalized() for co in unit)]
    face_mats = [1] * len(faces)
    bc.append(verts, faces, plate, ufaces)
    face_mats.extend([0] * len(ufaces))
    mats = [_scale_material("M_SpikePlateProc", 260.0), _horn_material("M_SpikeProc", 0.0, 0.75)]
    spike = bc.mesh_object("Spike", verts, faces, mats, face_mats)
    mats[0].name, mats[1].name = "M_SpikePlate", "M_Spike"
    baked = _bake([spike], "PartSpike", {"M_SpikePlate": sf.tint(_lin("#8E8468")), "M_Spike": sf.tint(_lin("#DCCFB0"))})
    pts = _check_pivot("spike", 0.015)
    foot = _footprint(pts)

    def length(co):
        if co.z > 0.01:
            co.z = 0.01 + (co.z - 0.01) * 1.5
        return co

    def lean(co):
        k = max(0.0, co.z) / 0.12
        co.y -= 0.045 * k
        co.z -= 0.008 * k * k
        return co

    handles = _shape_keys(spike, [("H1_Length", length, "the spike 50% longer"), ("H2_Lean", lean, "the spike raked back toward the tail")])
    rules = _rules("spike", round(foot + 0.001, 3), 0.015, "normal", ["spine", "limb", "part"], 60, 45)
    rules["handles"] = handles
    return {"purpose": "Creature spike part (PROPOSED): a single bony thorn with three keeled edges, raked a little back and flaring into a low scaly scute, for the back, shoulders, limbs or tail.",
            "category": "part", "part_type": "spike", "convention": "creature_art_contract v1", "part_rules": rules,
            "paint_mix": {"M_SpikePlate": 0.7, "M_Spike": 0.05}, "revision": 1, **baked}


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
    "cpart_eye_slit": (build_eye_slit, 1200),
    "cpart_eye_round": (build_eye_round, 1200),
    "cpart_eye_cluster": (build_eye_cluster, 1200),
    "cpart_jaw": (build_jaw, 1200),
    "cpart_bill": (build_bill, 1200),
    "cpart_foot_webbed": (build_foot_webbed, 2500),
    "cpart_foot_paw": (build_foot_paw, 2500),
    "cpart_foot_talon": (build_foot_talon, 2500),
    "cpart_hand_paw": (build_hand_paw, 2500),
    "cpart_hand_pincer": (build_hand_pincer, 2500),
    "cpart_hand_tentacle": (build_hand_tentacle, 2500),
    "cpart_claw_scythe": (build_claw_scythe, 1200),
    "cpart_claw_rake": (build_claw_rake, 1200),
    "cpart_horn_ram": (build_horn_ram, 1200),
    "cpart_horn_nose": (build_horn_nose, 1200),
    "cpart_spike": (build_spike, 1200),
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
