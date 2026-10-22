"""Build the M1 production assets that replace the step 2 blockouts: four cell parts, two foods and
three rocks, in the approved art direction (docs/art/ART_DIRECTION.md, "Soft life hardens").

Each asset keeps its blockout's id, node names, origin, scale and gameplay contract, so it drops in
without code changes; tests/test_assets.gd checks the contract after import. What changes is the
form (pebble, petal and bead shape language), the surfacing (procedural shaders baked to an albedo,
ORM and, where it helps, normal and emission textures in the palette) and the triangle use.

For every asset id this writes (Bible section 16):
  assets/source/blender/<id>.blend   (editable source, textures packed)
  assets/export/<id>.glb             (engine export, textures embedded)
  assets/records/<id>.json           (asset record: PROPOSED until Joshua reviews the look)

Run with the pinned Blender (see docs/TOOLCHAIN.md):
  python tools/blender/make_m1_production.py [--only <id>[,<id>...]]      (bpy 5.2.2 module)
  blender --background --python tools/blender/make_m1_production.py -- [--only ...]

Rocks take surface detail from a CC0 Poly Haven scan kept in assets/source/textures/cc0/ and
listed in each rock's record. Everything else is procedural. Baking uses Cycles, so textures can
differ by a few noise values between runs; geometry and contract values are deterministic.
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first, which provides mathutils)
import make_m1_blockouts as mb  # noqa: E402
import make_m1_threats as mt  # noqa: E402
import surfacing as sf  # noqa: E402
import cell_ladder as cl  # noqa: E402
import lookdev as ld  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

GENERATOR = "tools/blender/make_m1_production.py"
REVIEW_STATE = "production rev 1 - M1, awaiting owner look review"
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_m1_production.py; no external or "
              "generated meshes. Textures baked in Blender from procedural shaders{}.")
PART_TEXTURE = 512    # microscopic creature budget (art direction section 4)
FOOD_TEXTURE = 256    # tiny, drawn hundreds of times
ROCK_TEXTURE = 512    # a 2 m prop is about 150 px tall at the gameplay camera
# Triangle reduction (Joshua, 2026-10-22: as few triangles as possible without losing quality).
# Each mesh is decimated while its surface stays within this distance of the full-detail model,
# and the full model's shading is baked into the normal map. At the gameplay camera one pixel is
# about 11 mm; in an editor close-up about 1 mm.
PART_TOLERANCE = 0.0006
FOOD_TOLERANCE = 0.0015
ROCK_TOLERANCE = 0.01

CC0_ROCK = {
    "path": "assets/source/textures/cc0/polyhaven_rock_boulder_dry",
    "asset": "Rock Boulder Dry",
    "source_url": "https://polyhaven.com/a/rock_boulder_dry",
    "files": ["rock_boulder_dry_diff_1k.jpg", "rock_boulder_dry_disp_1k.jpg"],
    "license": "CC0 1.0 (https://polyhaven.com/license)",
    "authors": "Dimitrios Savva (photography), Rico Cilliers (processing)",
    "retrieved": "2026-10-22",
    "use": "box-projected luminance and height detail under the palette tint; baked, never shown raw",
}


def _check(condition, message):
    if not condition:
        raise RuntimeError(message)


def _reduce_and_bake(objs, tolerance, texture, size, **bake):
    """Reduces every object, bakes one texture set (normals from the full-detail copies), then
    removes the copies. Returns the record fields for textures and reduction."""
    before = after = 0
    highs = {}
    for obj in objs:
        b, a, high = sf.reduce(obj, tolerance)
        before, after = before + b, after + a
        highs[obj.name] = high if a < b else None
        if a == b:
            sf.drop_highs([high])
    sf.unwrap(objs)
    textures = sf.bake_set(objs, texture, size, highs=highs, **bake)
    sf.drop_highs(highs.values())
    return {"textures": textures,
            "reduction": {"method": "Blender collapse decimation within a surface tolerance; full-detail shading baked to the normal map",
                          "tolerance_m": tolerance, "triangles_before": before, "triangles_after": after}}


def _part(asset_id_type, purpose, objs, extra=None):
    """Reduce and bake the part to one texture set, then the blockout's attachment checks."""
    reduced = _reduce_and_bake(objs, PART_TOLERANCE, asset_id_type["texture"], PART_TEXTURE, **(extra or {}))
    fields = mb._part_fields(asset_id_type["type"], purpose)
    fields.update(reduced)
    fields["revision"] = 2
    return fields


def _sweep(path, radius_at, sides, twist=0.0):
    """A tube along `path` (Vectors) whose radius may vary around the ring:
    radius_at(i, angle) -> radius. A radius of 0 at the end makes a pointed tip; the start is capped."""
    verts, faces, rings = [], [], []
    n = len(path)
    for i, p in enumerate(path):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        ref = Vector((0.0, 0.0, 1.0)) if abs(t.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        side = t.cross(ref).normalized()
        up = side.cross(t).normalized()
        if radius_at(i, 0.0) <= 0.0:
            rings.append([len(verts)])
            verts.append(tuple(p))
            continue
        ring = []
        for j in range(sides):
            a = 2.0 * math.pi * j / sides + twist * i
            r = radius_at(i, a)
            ring.append(len(verts))
            verts.append(tuple(p + side * (r * math.cos(a)) + up * (r * math.sin(a))))
        rings.append(ring)
    cap = len(verts)
    verts.append(tuple(path[0]))
    for j in range(sides):
        faces.append((cap, rings[0][(j + 1) % sides], rings[0][j]))
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((a[j], a[k], b[0]) if len(b) == 1 else (a[j], a[k], b[k], b[j]))
    return verts, faces


# --- Flagellum --------------------------------------------------------------------------------


def build_flagellum():
    sh = sf.Shader("M_FlagellumProc")
    along = sh.remap(sh.axis("Y"), 0.0, mb.FLAGELLUM_LENGTH, smooth=False)
    # Cilia and flagella (section 4): thin, lighter tip, albedo gradient root to tip.
    base = sh.ramp(along, [(0.0, "rust"), (0.18, "coral"), (0.7, "#F2B48E"), (1.0, "cream")])
    # Faint travelling bands along the whip, like the fibres inside it, and a darker collar bead.
    bands = sh.math("SINE", sh.math("MULTIPLY", sh.axis("Y"), 70.0))
    base = sh.mix(sh.math("MULTIPLY", sh.remap(bands, -1.0, 1.0), 0.12), base, "rust")
    collar = sh.remap(sh.axis("Y"), 0.05, 0.02)
    base = sh.mix(sh.math("MULTIPLY", collar, 0.6), base, "rust")
    sh.bump(sh.remap(bands, -1.0, 1.0), 0.15, 0.004)
    proc = sh.out(base, sh.remap(along, 0.0, 1.0, 0.55, 0.4))

    steps, sides = 44, 12
    total = mb.FLAGELLUM_LENGTH + mb.PART_EMBED
    path, radii = [], []
    for i in range(steps + 1):
        u = i / steps
        y = -mb.PART_EMBED + total * u
        # The blockout's S-curve, eased in at the root, plus a gentle lift so it reads in 3/4 view.
        x = 0.075 * math.sin(2.0 * math.pi * u) * (0.35 + 0.65 * u)
        z = 0.025 * math.sin(math.pi * u) * u
        path.append(Vector((x, y, z)))
        radii.append(0.005 + 0.036 * (1.0 - u) ** 1.25)
    radii[-1] = 0.0

    def radius(i, a):
        u = i / steps
        # Collar bead around the root, then a soft spiral fluting that fades toward the tip.
        bead = 0.022 * math.exp(-((u - 0.07) / 0.035) ** 2)
        flute = 1.0 + 0.09 * (1.0 - u) * math.cos(3.0 * a - 18.0 * u)
        return (radii[i] + bead) * flute if radii[i] > 0.0 else 0.0

    verts, faces = _sweep(path, radius, sides)
    obj = bc.mesh_object("Flagellum", verts, faces, [proc])
    return _part({"type": "flagellum", "texture": "PartFlagellum"},
                 "M1 flagellum part (propulsion): a tapered, spiral-fluted whip, rust at the collar bead to cream at the tip.",
                 [obj])


# --- Eye spot ---------------------------------------------------------------------------------


EYE_CENTRE_Y = 0.105
EYE_BALL_R = 0.052


def build_eye_spot():
    sh = sf.Shader("M_EyeSpotProc")
    rel = sh.vmath("SUBTRACT", sh.pos, (0.0, EYE_CENTRE_Y, 0.0))
    dist = sh.vmath("LENGTH", rel)
    front = sh.math("DIVIDE", sh.axis("Y"), 1.0)
    # The ball: a cream ring around an amber pigment iris and a deep glossy lens (wet cornea).
    on_ball = sh.remap(dist, EYE_BALL_R + 0.006, EYE_BALL_R - 0.002)
    facing = sh.remap(sh.math("DIVIDE", sh.math("SUBTRACT", front, EYE_CENTRE_Y), EYE_BALL_R), 0.35, 0.95, smooth=False)
    eye = sh.ramp(facing, [(0.0, "cream"), (0.32, "mineral_amber"), (0.62, "#C2571F"), (0.78, "#0E1A26"), (1.0, "#0E1A26")])
    # The stalk and the hood: membrane coral, darker underneath, a matte rust lid (section 4).
    stalk = sh.ramp(sh.remap(sh.axis("Z"), -0.04, 0.05), [(0.0, "rust"), (0.6, "coral"), (1.0, "#F2A27E")])
    mottle = sh.noise(60.0, 2.0)
    stalk = sh.mix(sh.math("MULTIPLY", sh.remap(mottle, 0.4, 0.7), 0.2), stalk, "rust")
    base = sh.mix(on_ball, stalk, eye)
    rough = sh.math("ADD", sh.math("MULTIPLY", on_ball, -0.5), 0.6)
    rough = sh.math("SUBTRACT", rough, sh.math("MULTIPLY", sh.math("MULTIPLY", on_ball, facing), 0.08), clamp=True)
    glow = sh.math("MULTIPLY", sh.math("MULTIPLY", on_ball, sh.remap(facing, 0.3, 0.6)), sh.remap(facing, 0.75, 0.6))
    proc = sh.out(base, rough, sh.mix(glow, (0, 0, 0, 1), "mineral_amber"), 0.35)
    lid_sh = sf.Shader("M_EyeSpotLidProc")
    lid_base = lid_sh.ramp(lid_sh.remap(lid_sh.axis("Y"), 0.06, 0.15), [(0.0, "rust"), (1.0, "#C9603F")])
    lid_proc = lid_sh.out(lid_base, 0.65)

    # Stalk and eye cup as one surface of revolution along +Y, then the eyeball.
    profile = [(-mb.PART_EMBED, 0.0), (-mb.PART_EMBED, 0.04), (-0.005, 0.038), (0.02, 0.030), (0.045, 0.031),
               (0.065, 0.042), (0.08, 0.055), (0.095, 0.059), (0.108, 0.057), (0.118, 0.05)]
    verts, faces, _ = bc.revolve(profile, 24)
    # The cup's open front is closed by the eyeball, which sinks into it.
    ball_v, ball_f = bc.icosphere(3)
    ball = [Vector(v) * EYE_BALL_R + Vector((0.0, EYE_CENTRE_Y, 0.0)) for v in ball_v]
    bc.append(verts, faces, ball, ball_f)
    eye = bc.mesh_object("EyeSpot", verts, faces, [proc])
    # A petal hood over the top of the eye: emotion comes from lids (section 2), and it gives the
    # eye a clear front at gameplay distance. Its own object, so a rig can blink it later.
    hood = []
    rows, cols = 6, 18
    for i in range(rows + 1):
        row = i / rows
        for j in range(cols + 1):
            yaw = math.radians(-78.0 + 156.0 * j / cols)
            # From the lid's front edge, which dips to a soft petal point at the middle, over the
            # top and a little behind it. The eye's front stays open.
            mid = math.exp(-((j / cols - 0.5) / 0.2) ** 2)
            pitch = math.radians((30.0 - 14.0 * mid) + (84.0 - (30.0 - 14.0 * mid)) * row)
            edge = 1.0 - 0.18 * (abs(j / cols - 0.5) * 2.0) ** 2
            r = (EYE_BALL_R + 0.009) * edge
            d = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
            # A soft point at the front middle: the petal tip.
            hood.append(Vector((0.0, EYE_CENTRE_Y, 0.0)) + d * r)
    hood_faces = [(i * (cols + 1) + j, i * (cols + 1) + j + 1, (i + 1) * (cols + 1) + j + 1, (i + 1) * (cols + 1) + j)
                  for i in range(rows) for j in range(cols)]
    lid = bc.mesh_object("EyeSpotLid", hood, hood_faces, [lid_proc], fix_normals=False, parent=eye)
    solid = lid.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.01
    solid.offset = 1.0
    sf.select([lid])
    bpy.ops.object.modifier_apply(modifier="Solidify")
    return _part({"type": "eye_spot", "texture": "PartEyeSpot"},
                 "M1 eye spot part (sight): a glossy amber eye with a dark lens in a coral cup on a short stalk, under a rust petal lid.",
                 [eye, lid])


# --- Filter mouth -----------------------------------------------------------------------------


PETALS = 8


def build_mouth_filter():
    sh = sf.Shader("M_FilterProc")
    geo = sh.node("ShaderNodeNewGeometry")
    radial = sh.vmath("NORMALIZE", sh.vmath("MULTIPLY", sh.pos, (1.0, 0.0, 1.0)))
    inward = sh.remap(sh.vmath("DOT_PRODUCT", geo.outputs["Normal"], radial), 0.1, -0.4)
    depth = sh.remap(sh.axis("Y"), 0.13, 0.03)
    # Outside: coral petals with cream rims. Inside: the throat darkens toward the gullet.
    outside = sh.ramp(sh.remap(sh.axis("Y"), 0.0, 0.135), [(0.0, "rust"), (0.45, "coral"), (0.85, "#F4C29A"), (1.0, "cream")])
    throat = sh.ramp(depth, [(0.0, "#C9603F"), (0.5, "#6A2632"), (1.0, "#240E16")])
    base = sh.mix(sh.math("MULTIPLY", inward, sh.remap(sh.axis("Y"), 0.135, 0.11)), outside, throat)
    cilia = sh.remap(sh.axis("Y"), 0.13, 0.15)
    base = sh.mix(cilia, base, sh.ramp(sh.remap(sh.axis("Y"), 0.14, 0.19), [(0.0, "#F4C29A"), (1.0, "cream")]))
    mottle = sh.noise(45.0, 2.0)
    base = sh.mix(sh.math("MULTIPLY", sh.remap(mottle, 0.45, 0.7), 0.15), base, "rust")
    proc = sh.out(base, sh.math("ADD", 0.5, sh.math("MULTIPLY", inward, -0.12)))

    rim = mb.FILTER_RIM_RADIUS
    profile = [(-mb.PART_EMBED, 0.0), (-mb.PART_EMBED, 0.068), (0.0, 0.07), (0.055, 0.085),
               (0.085, 0.099), (0.108, 0.111), (0.122, rim), (0.131, rim - 0.006), (0.128, rim - 0.018),
               (0.112, 0.094), (0.09, 0.078), (0.045, 0.034), (0.036, 0.0)]
    segments = 32
    verts, faces, _ = bc.revolve(profile, segments)
    # Scallop the rim into eight petals: the lip rings swell and rise at each petal's middle and
    # pinch between petals (pebble, petal, bead).
    for ring, weight in ((5, 0.35), (6, 0.75), (7, 1.0), (8, 0.8)):
        for j in range(segments):
            a = 2.0 * math.pi * j / segments
            petal = math.cos(PETALS * a)                      # +1 mid-petal, -1 between petals
            k = 1 + (ring - 1) * segments + j                 # ring 0 is the pole at the base
            v = Vector(verts[k])
            scale = 1.0 + weight * 0.1 * petal
            verts[k] = (v.x * scale, v.y + weight * 0.014 * petal, v.z * scale)
    # The fringe: soft cilia curling out from between the petals, each ending in a round bead. They
    # stay soft and curved: in this era a sharp point means danger (art direction section 2).
    lean = math.radians(35.0)
    for k in range(PETALS * 2):
        a = 2.0 * math.pi * (k + 0.5) / (PETALS * 2)
        radial_dir = Vector((math.cos(a), 0.0, math.sin(a)))
        out = Vector((0.0, math.cos(lean), 0.0)) + radial_dir * math.sin(lean)
        base_pt = Vector((0.0, 0.122, 0.0)) + radial_dir * (rim * 0.93)
        length = 0.05 + 0.01 * math.cos(3.0 * a)
        path = [base_pt + out * (length * t) + radial_dir * (0.022 * t * t) for t in (0.0, 0.3, 0.6, 0.85, 0.95, 1.0)]
        widths = [0.0055, 0.0042, 0.0034, 0.0046, 0.0038, 0.0]
        tv, tf = _sweep(path, lambda i, _a, widths=widths: widths[i], 4)
        bc.append(verts, faces, tv, tf)
    obj = bc.mesh_object("MouthFilter", verts, faces, [proc])
    return _part({"type": "mouth_filter", "texture": "PartMouthFilter"},
                 "M1 filter mouth part (eats plankton): an eight-petal coral funnel with cream rims, a dark throat and a cilia fringe.",
                 [obj])


# --- Jaw mouth --------------------------------------------------------------------------------


def build_mouth_jaw():
    sh = sf.Shader("M_JawCollarProc")
    collar = sh.ramp(sh.remap(sh.axis("Y"), -0.03, 0.06), [(0.0, "rust"), (0.55, "coral"), (0.8, "#8E3A33"), (1.0, "#3A1820")])
    mottle = sh.noise(50.0, 2.0)
    collar = sh.mix(sh.math("MULTIPLY", sh.remap(mottle, 0.45, 0.7), 0.2), collar, "rust")
    collar_proc = sh.out(collar, 0.55)
    ch = sf.Shader("M_MandibleProc")
    # Chitin: near-black brown with a threat-pink gum at the hinge (threat colour always rides on
    # a sharp shape, section 3) and a worn amber edge toward the tip. Growth bands across it.
    reach = ch.remap(ch.vmath("LENGTH", ch.pos), 0.0, 0.2, smooth=False)
    chitin = ch.ramp(reach, [(0.0, "threat"), (0.16, "#5A2230"), (0.3, "#2A1A16"), (0.85, "#3B2A20"), (1.0, "#C9894A")])
    bands = ch.remap(ch.math("SINE", ch.math("MULTIPLY", ch.vmath("LENGTH", ch.pos), 160.0)), 0.6, 1.0)
    chitin = ch.mix(ch.math("MULTIPLY", bands, 0.25), chitin, "#120A08")
    ch.bump(bands, 0.2, 0.003)
    mandible_proc = ch.out(chitin, ch.remap(reach, 0.0, 1.0, 0.45, 0.25))

    profile = [(-mb.PART_EMBED, 0.0), (-mb.PART_EMBED, 0.094), (-0.005, 0.1), (0.015, 0.1), (0.032, 0.091),
               (0.048, 0.072), (0.056, 0.05), (0.06, 0.03), (0.058, 0.012), (0.05, 0.0)]
    verts, faces, _ = bc.revolve(profile, 28)
    base = bc.mesh_object("JawBase", verts, faces, [collar_proc])
    mandibles = []
    for side, sx in (("L", -1.0), ("R", 1.0)):
        p0 = Vector((0.0, 0.0, 0.0))
        p1 = Vector((sx * 0.135, 0.105, -0.005))
        p2 = Vector((-sx * 0.04, 0.205, 0.0))
        steps = 16
        path = [mb._bezier(p0, p1, p2, i / steps) for i in range(steps + 1)]

        def radius(i, a, steps=steps):
            u = i / steps
            r = 0.031 * (1.0 - u) ** 0.75
            if r <= 0.0005:
                return 0.0
            # Flattened crescent with a keel on the outer edge and a sharp inner cutting edge.
            return r * (0.62 + 0.38 * abs(math.cos(a))) * (1.0 + 0.12 * math.cos(a) * sx)

        tv, tf = _sweep(path, radius, 9)
        # Three serrations on the inner edge, pointing back toward the mouth's centre line.
        for t in (0.42, 0.58, 0.73):
            c = mb._bezier(p0, p1, p2, t)
            tangent = (mb._bezier(p0, p1, p2, t + 0.01) - c).normalized()
            inner = Vector((-sx, 0.0, 0.0))
            inner = (inner - tangent * inner.dot(tangent)).normalized()
            r = 0.031 * (1.0 - t) ** 0.75
            tooth = [c + inner * (r * 0.3), c + inner * (r * 0.3 + 0.024) - tangent * 0.008]
            ttv, ttf = bc.tube(tooth, [0.0085, 0.0], 6)
            bc.append(tv, tf, ttv, ttf)
        m = bc.mesh_object(f"Mandible_{side}", tv, tf, [mandible_proc], parent=base,
                           location=(sx * mb.JAW_HINGE[0], mb.JAW_HINGE[1], 0.0))
        mandibles.append(m)
    return _part({"type": "mouth_jaw", "texture": "PartMouthJaw"},
                 "M1 jaw mouth part (eats carrion): twin serrated chitin mandibles on hinges, threat-pink at the gum, on a coral collar.",
                 [base] + mandibles)


# --- Foods ------------------------------------------------------------------------------------


def build_plankton():
    sh = sf.Shader("M_PlanktonProc")
    xy = sh.vmath("MULTIPLY", sh.pos, (1.0, 1.0, 0.0))
    r = sh.math("DIVIDE", sh.vmath("LENGTH", xy), mb.PLANKTON_MESH_RADIUS)
    angle = sh.math("ARCTAN2", sh.axis("Y"), sh.axis("X"))
    valve = sh.remap(sh.math("ABSOLUTE", sh.axis("Z")), 0.045, 0.075)   # the two flat faces
    # A centric diatom: sixteen radial ribs, rings of tiny pores, a glowing chloroplast core.
    ribs = sh.remap(sh.math("COSINE", sh.math("MULTIPLY", angle, 16.0)), 0.55, 1.0)
    rings = sh.remap(sh.math("COSINE", sh.math("MULTIPLY", r, 34.0)), 0.3, 1.0)
    pores = sh.remap(sh.voronoi(140.0, 0.4), 0.09, 0.03)
    core = sh.remap(r, 0.62, 0.18)
    shell = sh.ramp(r, [(0.0, "food_glow"), (0.45, "#9CCB5A"), (0.85, "algae_green"), (1.0, "#D8E8B0")])
    girdle = sh.ramp(sh.remap(sh.math("ABSOLUTE", sh.axis("Z")), 0.0, 0.05), [(0.0, "#E3EFC0"), (0.6, "#A8CF6A"), (1.0, "algae_green")])
    base = sh.mix(valve, girdle, shell)
    base = sh.mix(sh.math("MULTIPLY", sh.math("MULTIPLY", ribs, valve), 0.35), base, "#E8F4B8")
    base = sh.mix(sh.math("MULTIPLY", sh.math("MULTIPLY", pores, valve), 0.45), base, "moss_deep")
    base = sh.mix(sh.math("MULTIPLY", rings, 0.12), base, "#5E8E3E")
    sh.bump(sh.math("ADD", ribs, sh.math("MULTIPLY", pores, -0.6)), 0.25, 0.002)
    glow = sh.math("ADD", core, sh.math("MULTIPLY", sh.math("MULTIPLY", ribs, valve), 0.25), clamp=True)
    emission = sh.mix(glow, (0, 0, 0, 1), "food_glow")
    proc = sh.out(base, sh.remap(valve, 0.0, 1.0, 0.45, 0.3), emission, 0.6)

    segments = 32
    # Flat valve faces, a soft shoulder and a girdle groove at the equator.
    lats = [72.0, 48.0, 22.0, -22.0, -48.0, -72.0]
    offset = Vector((-2.7, 8.3, 5.1))
    pts = [Vector((0.0, 0.0, 1.0))]
    for lat in lats:
        c, s = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        groove = 0.94 if abs(lat) < 30.0 else 1.0
        for j in range(segments):
            a = 2.0 * math.pi * j / segments
            n = Vector((c * math.cos(a), c * math.sin(a), s))
            rib = 1.0 + 0.035 * math.cos(16.0 * a) * c * c
            lump = 1.0 + 0.035 * noise.noise(n * 2.2 + offset)
            h = c ** 0.55 * rib * lump * groove
            pts.append(Vector((h * math.cos(a), h * math.sin(a), math.copysign(abs(s) ** 0.7, s) * lump)))
    pts.append(Vector((0.0, 0.0, -1.0)))
    widest = mb._horizontal_radius(pts)
    for p in pts:
        p.x *= mb.PLANKTON_MESH_RADIUS / widest
        p.y *= mb.PLANKTON_MESH_RADIUS / widest
        p.z *= mb.PLANKTON_HALF_HEIGHT
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
    obj = bc.mesh_object("Plankton", pts, faces, [proc])
    reduced = _reduce_and_bake([obj], FOOD_TOLERANCE, "Plankton", FOOD_TEXTURE, normal=True, emission=True)
    radius = mb._horizontal_radius([obj.matrix_world @ v.co for v in obj.data.vertices])
    _check(abs(radius - mb.PLANKTON_ITEM_RADIUS) <= 0.2 * mb.PLANKTON_ITEM_RADIUS, "plankton: mesh radius fits the item radius")
    return {
        "purpose": "M1 plankton food item: a glowing centric diatom (radial ribs, pore rings, a food-glow core), drawn many times with one MultiMesh.",
        "category": "food",
        "food_kind": "plant",
        "revision": 2,
        "pivot": "centre of the item",
        "item_radius_m": mb.PLANKTON_ITEM_RADIUS,
        "mesh_radius_m": round(radius, 3),
        **reduced,
    }


def build_carrion():
    sh = sf.Shader("M_CarrionProc")
    marble = sh.noise(14.0, 4.0, 0.6)
    flesh = sh.ramp(marble, [(0.3, "#6E2430"), (0.48, "#9A3A36"), (0.6, "rust"), (0.72, "#D27C62")])
    # Torn muscle fibres run along one direction; a pale sinew band and fat beads sit on top, so
    # the chunk reads as meat by shape and marking, not colour alone (section 3).
    fibres = sh.noise(3.0, 2.0, 0.5, vector=sh.vmath("MULTIPLY", sh.pos, (60.0, 6.0, 60.0)))
    flesh = sh.mix(sh.math("MULTIPLY", sh.remap(fibres, 0.35, 0.65), 0.3), flesh, "#5A1A24")
    across = sh.math("ADD", sh.vmath("DOT_PRODUCT", sh.pos, (0.6, -0.8, 0.0)), sh.math("MULTIPLY", sh.noise(18.0, 2.0), 0.03))
    across = sh.math("ADD", across, sh.math("MULTIPLY", sh.noise(7.0, 2.0), 0.05))
    sinew = sh.math("MULTIPLY", sh.remap(sh.math("ABSOLUTE", sh.math("SUBTRACT", across, 0.06)), 0.024, 0.008),
                    sh.remap(sh.axis("Z"), -0.02, 0.04))
    fat = sh.math("MULTIPLY", sh.remap(sh.voronoi(8.0, 1.0), 0.2, 0.08), sh.remap(sh.axis("Z"), 0.02, 0.1))
    base = sh.mix(sh.math("MULTIPLY", sinew, 0.85), flesh, sh.ramp(sh.noise(30.0, 2.0), [(0.3, "#D9A89A"), (0.7, "#EED8C8")]))
    base = sh.mix(sh.math("MULTIPLY", fat, 0.55), base, "#E9C49A")
    underside = sh.remap(sh.axis("Z"), -0.03, -0.09)
    base = sh.mix(sh.math("MULTIPLY", underside, 0.6), base, "#4A1620")
    sh.bump(sh.math("ADD", sh.math("MULTIPLY", fibres, 0.6), sh.math("ADD", sinew, fat)), 0.35, 0.004)
    wet = sh.math("ADD", 0.32, sh.math("MULTIPLY", sh.math("ADD", sinew, fat, clamp=True), 0.2))
    proc = sh.out(base, wet)

    unit, faces = bc.icosphere(3)
    offset = Vector((4.4, -9.1, 13.7))
    pts = []
    for co in unit:
        n = Vector(co).normalized()
        chunk = 1.0 + 0.2 * noise.noise(n * 1.8 + offset) + 0.07 * noise.noise(n * 4.2 - offset)
        p = Vector((n.x * 0.30, n.y * 0.23, n.z * 0.16)) * chunk
        # A torn face on one end: flattened and ridged, so the chunk reads as torn off something.
        torn = max(0.0, p.x - 0.13)
        if torn > 0.0:
            p.x = 0.13 + torn * 0.35 + 0.012 * noise.noise(Vector((0.0, p.y * 30.0, p.z * 30.0)))
        p.z = max(p.z, -0.1 + 0.008 * noise.noise(p * 20.0))  # rests on a flat-ish underside
        pts.append(p)
    widest = mb._horizontal_radius(pts)
    for p in pts:
        p.x *= mb.CARRION_MESH_RADIUS / widest
        p.y *= mb.CARRION_MESH_RADIUS / widest
    obj = bc.mesh_object("Carrion", pts, faces, [proc])
    reduced = _reduce_and_bake([obj], FOOD_TOLERANCE, "Carrion", FOOD_TEXTURE, normal=True)
    radius = mb._horizontal_radius([obj.matrix_world @ v.co for v in obj.data.vertices])
    _check(abs(radius - mb.CARRION_ITEM_RADIUS) <= 0.2 * mb.CARRION_ITEM_RADIUS, "carrion: mesh radius fits the item radius")
    return {
        "purpose": "M1 carrion food item (static, sinks, no drift): a torn, marbled flesh chunk with a pale sinew band and fat beads, drawn with one MultiMesh.",
        "category": "food",
        "food_kind": "meat",
        "revision": 2,
        "pivot": "centre of the item",
        "item_radius_m": mb.CARRION_ITEM_RADIUS,
        "mesh_radius_m": round(radius, 3),
        **reduced,
    }


# --- Rocks ------------------------------------------------------------------------------------


ROCK_TINTS = {   # (stone base, stone light, accent) per variant, cool and below about 55% saturation
    "rock_a": ("#646660", "#ABA79A", "mineral_amber"),
    "rock_b": ("#5E6264", "#A2A39E", "#C99A5B"),
    "rock_c": ("#6A665C", "#B4AC9A", "mineral_amber"),
}


def build_rock(asset_id):
    fields = mb.build_rock(asset_id)       # the blockout's geometry and swim-band contract, unchanged
    obj = bpy.data.objects["Rock"]
    dark, light, accent = ROCK_TINTS[asset_id]
    seed = {"rock_a": 0.0, "rock_b": 3.7, "rock_c": 7.9}[asset_id]
    folder = os.path.join(bc.ROOT, CC0_ROCK["path"])
    sh = sf.Shader("M_RockProc")
    scan = sh.image(os.path.join(folder, CC0_ROCK["files"][0]), "sRGB", scale=0.45)
    height = sh.image(os.path.join(folder, CC0_ROCK["files"][1]), "Non-Color", scale=0.45)
    lum = sh.node("ShaderNodeRGBToBW")
    sh.link(scan, lum.inputs["Color"])
    # The scan gives value and grain only; the palette gives the colour (habitat stays cool).
    stone = sh.ramp(lum.outputs["Val"], [(0.12, "#2F3638"), (0.35, dark), (0.75, light), (1.0, "#D8D2C2")])
    geo = sh.node("ShaderNodeNewGeometry")
    up = sh.vmath("DOT_PRODUCT", geo.outputs["Normal"], (0.0, 0.0, 1.0))
    # Algae and moss settle on the lit, upward faces above the water line (pebble top reads green
    # from the gameplay camera), patchy by noise.
    patch = sh.noise(2.2, 4.0, 0.6, w=seed)
    moss_mask = sh.math("MULTIPLY", sh.remap(up, 0.35, 0.8), sh.remap(patch, 0.42, 0.58))
    moss = sh.ramp(sh.noise(18.0, 3.0, w=seed), [(0.3, "moss_deep"), (0.65, "#5E9455"), (1.0, "#93B07A")])
    base = sh.mix(sh.math("MULTIPLY", moss_mask, 0.8), stone, moss)
    # A darker, slightly wet band where the rock sits in water, fading under the swim plane.
    wet = sh.remap(sh.axis("Z"), 0.1, -0.5)
    base = sh.mix(sh.math("MULTIPLY", wet, 0.3), base, "#2B3A3E")
    # Mineral flecks: small warm beads in the stone, the habitat's one warm accent.
    flecks = sh.math("MULTIPLY", sh.remap(sh.voronoi(9.0, 1.0, vector=sh.vmath("ADD", sh.pos, (seed, seed, 0.0))), 0.07, 0.035),
                     sh.math("SUBTRACT", 1.0, moss_mask, clamp=True))
    base = sh.mix(sh.math("MULTIPLY", flecks, 0.7), base, accent)
    hgt = sh.node("ShaderNodeRGBToBW")
    sh.link(height, hgt.inputs["Color"])
    sh.bump(sh.math("ADD", hgt.outputs["Val"], sh.math("MULTIPLY", moss_mask, 0.25)), 0.55, 0.05)
    rough = sh.math("SUBTRACT", sh.remap(moss_mask, 0.0, 1.0, 0.88, 0.75), sh.math("MULTIPLY", wet, 0.25))
    proc = sh.out(base, rough)
    obj.data.materials.clear()
    obj.data.materials.append(proc)
    reduced = _reduce_and_bake([obj], ROCK_TOLERANCE, f"Rock{asset_id[-1].upper()}", ROCK_TEXTURE, normal=True)
    # The reduced rock must still meet the blockout's swim-band contract (tests/test_assets.gd).
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    tris = [tuple(t.vertices) for t in _triangles(obj)]
    outline = mb.band_outline(pts, tris, mb.ROCK_OUTLINE_HEIGHTS)
    at_plane = mb.band_outline(pts, tris, [0.0])
    lo, hi = (k * mb.ROCK_FOOTPRINT_RADIUS for k in mb.ROCK_OUTLINE)
    _check(lo <= min(outline) and max(outline) <= hi, f"{asset_id}: reduced swim band outline {min(outline):.3f}-{max(outline):.3f}")
    _check(lo <= min(at_plane) and max(at_plane) <= hi, f"{asset_id}: reduced swim plane section {min(at_plane):.3f}-{max(at_plane):.3f}")
    fields.update({
        "max_radius_m": round(mb._horizontal_radius(pts), 3),
        "swim_band_radius_m": round(max(outline), 3),
        "swim_band_min_radius_m": round(min(outline), 3),
        "swim_plane_radius_range_m": [round(min(at_plane), 3), round(max(at_plane), 3)],
        "purpose": "M1 pool rock, an obstacle the cell slides around: cool stone with algae on its lit top, a wet band at the water line and warm mineral flecks. Placed by game/data/pool_m1.json with yaw and uniform scale.",
        "revision": 3,
        **reduced,
        "dependencies": [dict(CC0_ROCK)],
        "provenance_extra": "; surface detail from the CC0 Poly Haven scan in dependencies",
    })
    return fields


# --- Player cell -----------------------------------------------------------------------------

# The M1 body, in the approved quality-ladder look (cell_ladder rung 2), fitted to the gameplay
# contract: PartPlacement's ellipsoid (0.46 wide, 0.5 long, 0.39 tall), the five sockets on it,
# the eyes where the sample's were (their tops at 0.26, under the eye spot's 0.30), and the nodes
# the pool view hides (Body/Mouth, Body/Flagellum) and keeps (Body/Eye_*, Body/Pupil_*).
CELL_RADII = (0.46, 0.5, 0.39)
CELL_EYES = {"L": Vector((-0.17, 0.335, 0.145)), "R": Vector((0.17, 0.335, 0.145))}
CELL_EYE_R = 0.095
CELL_TEXTURE = 1024   # the player's own body is the most-seen asset and is shown close up in the editor
CELL_TOLERANCE = 0.0015
CELL_SOCKETS = {"socket_mouth": (0, 0.5, 0), "socket_tail": (0, -0.5, 0), "socket_top": (0, 0, 0.39),
                "socket_side_L": (-0.46, 0, 0), "socket_side_R": (0.46, 0, 0)}


def _uv_sphere(name, radius, location, segments, rings, parent, scale=(1, 1, 1), rotation=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location)
    obj = cl.name_obj(bpy.context.active_object, name)
    obj.scale = scale
    if rotation is not None:
        obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    obj.parent = parent
    return obj


def _cell_eye(side, body, mats):
    """Eyeball, iris and pupil caps, and upper and lower lids that pivot on the eye centre."""
    centre = CELL_EYES[side]
    gaze = Vector((centre.x * 1.6, 1.0, 0.1)).normalized()
    rot = gaze.to_track_quat("Z", "Y").to_euler()
    eye = _uv_sphere(f"Eye_{side}", CELL_EYE_R, centre, 24, 12, body)
    eye.data.materials.append(mats["sclera"])
    for name, radius, depth, flat, mat in (("Iris", 0.06, CELL_EYE_R - 0.016, 0.4, "iris"),
                                           ("Pupil", 0.032, CELL_EYE_R + 0.002, 0.35, "pupil")):
        cap = _uv_sphere(f"{name}_{side}", radius, centre + gaze * depth, 18, 8, body, rotation=rot)
        cap.scale = (1, 1, flat)
        sf.select([cap])
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        cap.data.materials.append(mats[mat])
    yaw = math.atan2(-gaze.x, gaze.y)
    for lid, keep_upper, tilt in (("LidUpper", True, 48.0), ("LidLower", False, -62.0)):
        bm = cl.bmesh.new()
        cl.bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=CELL_EYE_R + 0.005)
        doomed = [v for v in bm.verts if (v.co.z < -0.004 if keep_upper else v.co.z > 0.004)]
        cl.bmesh.ops.delete(bm, geom=doomed, context="VERTS")
        mesh = bpy.data.meshes.new(f"{lid}_{side}_mesh")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(f"{lid}_{side}", mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = centre
        obj.rotation_euler = (math.radians(tilt), 0, yaw)
        solid = obj.modifiers.new("Solidify", "SOLIDIFY")
        solid.thickness = 0.009
        solid.offset = 1.0
        sf.select([obj])
        bpy.ops.object.modifier_apply(modifier="Solidify")
        bpy.ops.object.shade_smooth()
        obj.data.materials.append(mats["lid"])
        obj.parent = body


def build_sample_cell():
    cl.BODY_RADII = CELL_RADII
    cl.EYE_DIR = {side: c.normalized() for side, c in CELL_EYES.items()}
    body = cl.build_body_mesh(level=4)
    beads = cl.add_organelles(body)
    membrane = cl.body_membrane()
    organelle = ld.principled("M_OrganelleProc", ld.color("mineral_amber"), 0.4, ld.color("mineral_amber"), 0.5)
    body.data.materials.append(membrane)
    for bead in beads:
        bead.data.materials.append(organelle)
    cl.join_into(body, beads)
    mats = {
        "sclera": ld.principled("M_ScleraProc", ld.color("cream"), 0.08),
        "iris": ld.principled("M_IrisProc", ld.color("pool_teal"), 0.25),
        "pupil": ld.principled("M_PupilProc", ld.color("#0E1A26"), 0.05),
        "lid": ld.principled("M_LidProc", ld.color("rust"), 0.62),
    }
    for side in CELL_EYES:
        _cell_eye(side, body, mats)
    mouth = cl.name_obj(cl.add_lips(body), "Mouth")
    mouth.data.materials.append(ld.principled("M_LipsProc", ld.color("#8E3A33"), 0.55))
    flagellum, collar = cl.add_flagellum(body)
    flagellum.data.materials.append(membrane)
    collar.data.materials.append(membrane)
    cl.join_into(flagellum, [collar])
    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        sf.select([obj])
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for name, loc in CELL_SOCKETS.items():
        cl.add_socket(name, loc, body)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    reduced = _reduce_and_bake(meshes, CELL_TOLERANCE, "PlayerCell", CELL_TEXTURE)
    for side, c in CELL_EYES.items():
        eye = bpy.data.objects[f"Eye_{side}"]
        for part in (f"Eye_{side}", f"LidUpper_{side}"):
            obj = bpy.data.objects[part]
            top = max((obj.matrix_world @ v.co).z for v in obj.data.vertices)
            _check(top <= 0.26, f"sample_cell: {part} top {top:.3f} stays under the eye spot (0.30)")
    return {
        "purpose": "M1 player cell body in the approved art direction (quality-ladder look): a coral pebble body with lidded eyes, organelle beads, lips and a flagellum. The pool hides Body/Mouth and Body/Flagellum (genome parts replace them).",
        "category": "creature",
        "revision": 2,
        **reduced,
    }


def _triangles(obj):
    obj.data.calc_loop_triangles()
    return obj.data.loop_triangles


# --- Step 3 threats --------------------------------------------------------------------------
# Production passes over engineering's step 3 blockouts (tools/blender/make_m1_threats.py, plan
# section 17). The blockout's forms, node names, pivots, frame and colours are the contract, so
# each asset is built by the blockout's own code, surfaced, reduced and baked. A body's normal map
# comes from the same body built at a finer tessellation, so the shipped body is smooth with the
# blockout's vertex count, which its vertex-colour patterns need. Every material keeps its name and flat colour (the creature
# view and the tests look them up) and gains a shared greyscale detail albedo, an ORM and a normal
# map; the bodies keep their vertex colours, which their engine materials multiply by the detail.

THREAT_TEXTURE = 1024        # creature bodies are the pool's largest living things and its focal threats
THREAT_TOLERANCE = 0.0015    # bodies, as the sample cell
THREAT_COLOUR_ERROR = 0.04   # per channel, sRGB-encoded: the patterns stay crisp after reduction
FINE = {"AMBUSH_SEGMENTS": 96, "AMBUSH_RINGS": (20, 12), "RAMMER_SEGMENTS": 64, "RAMMER_RINGS": 34}


def _fine_body(builder):
    """The Body mesh of a blockout builder run at the finer tessellation, kept as a lone mesh
    datablock; everything else that run made is removed, so the shipped build can take the names."""
    keep = {k: getattr(mt, k) for k in FINE}
    for k, v in FINE.items():
        setattr(mt, k, v)
    try:
        builder()
    finally:
        for k, v in keep.items():
            setattr(mt, k, v)
    mesh = bpy.data.objects["Body"].data.copy()
    mesh.name = "Body_fine"
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    return mesh


def _gaze_facing(sh, gaze):
    """How squarely a point on an eye (object space, origin at its centre) faces `gaze`, mirrored
    across x so one material serves both eyes."""
    xyz = sh.node("ShaderNodeSeparateXYZ")
    sh.link(sh.pos, xyz.inputs["Vector"])
    comb = sh.node("ShaderNodeCombineXYZ")
    sh.link(sh.math("ABSOLUTE", xyz.outputs["X"]), comb.inputs["X"])
    sh.link(xyz.outputs["Y"], comb.inputs["Y"])
    sh.link(xyz.outputs["Z"], comb.inputs["Z"])
    unit = sh.vmath("NORMALIZE", comb.outputs["Vector"])
    return sh.vmath("DOT_PRODUCT", unit, tuple(Vector(gaze).normalized()))


def _stretched(sh, scale):
    return sh.vmath("MULTIPLY", sh.pos, scale)


def _grey(sh, fac, lo, hi=1.0):
    """A greyscale detail value from `fac` (0..1): lo where it is 0, hi where it is 1."""
    return sh.ramp(fac, [(0.0, (lo, lo, lo, 1.0)), (1.0, (hi, hi, hi, 1.0))])


def _eye_shader(name, gaze, lo):
    """A wet eye: fine radial grain over the front, darker toward a ring round the iris."""
    sh = sf.Shader(name)
    facing = _gaze_facing(sh, gaze)
    grain = sh.noise(260.0, 2.0, vector=_stretched(sh, (1.0, 1.0, 3.0)))
    ring = sh.math("MULTIPLY", sh.remap(facing, 0.3, 0.5), sh.remap(facing, 0.75, 0.55))
    base = sh.ramp(facing, [(0.0, (lo, lo, lo, 1.0)), (0.45, (1.0, 1.0, 1.0, 1.0)), (1.0, (0.94, 0.94, 0.94, 1.0))])
    base = sh.mix(sh.math("MULTIPLY", sh.remap(grain, 0.35, 0.7), 0.2), base, (0.7, 0.7, 0.7, 1.0))
    base = sh.mix(sh.math("MULTIPLY", ring, 0.25), base, (0.6, 0.6, 0.6, 1.0))
    sh.bump(sh.math("MULTIPLY", grain, 0.3), 0.15, 0.002)
    return sh.out(base, 0.06)


def _plain_shader(name, rough, grain_scale=120.0, lo=0.85):
    sh = sf.Shader(name)
    grain = sh.noise(grain_scale, 3.0)
    sh.bump(grain, 0.2, 0.002)
    return sh.out(_grey(sh, sh.remap(grain, 0.3, 0.7), lo), rough)


def _swap_materials(objs, shaders):
    """Puts each procedural shader in place of the blockout material of the same name, which it
    then takes (the name is the contract)."""
    olds = {slot.material for obj in objs for slot in obj.material_slots}
    for obj in objs:
        for slot in obj.material_slots:
            slot.material = shaders[slot.material.name]
    for old in olds:
        name = old.name
        bpy.data.materials.remove(old)
        shaders[name].name = name


def _threat_bake(objs, body, tints, accept, texture, fine=None):
    """Reduces the body (patterns and contracts kept by `accept`) and the small meshes, then bakes
    one tinted texture set, with the body's normals from `fine` (its finer mesh) when given.
    Returns the record's textures and reduction."""
    before = after = 0
    highs = {}
    for obj in objs:
        tolerance, check = (THREAT_TOLERANCE, accept) if obj is body else (PART_TOLERANCE, None)
        b, a, high = sf.reduce(obj, tolerance, accept=check)
        before, after = before + b, after + a
        if obj is body and fine is not None:
            for mat in obj.data.materials:
                fine.materials.append(mat)
            high.data = fine
        elif a == b:
            sf.drop_highs([high])
            high = None
        highs[obj.name] = high
    sf.unwrap(objs)
    textures = sf.bake_set(objs, texture, THREAT_TEXTURE if body is not None else PART_TEXTURE, highs=highs, tints=tints)
    sf.drop_highs(highs.values())
    return {"textures": textures,
            "reduction": {"method": "Blender collapse decimation within a surface tolerance; body vertex colours kept within "
                                    f"{THREAT_COLOUR_ERROR} per channel; full-detail shading (a body built at a finer "
                                    "tessellation) baked to the normal map",
                          "tolerance_m": {"body": THREAT_TOLERANCE, "eyes_and_small_meshes": PART_TOLERANCE},
                          "triangles_before": before, "triangles_after": after}}


def _colours_and(obj, attribute, contract=None):
    fidelity = sf.color_fidelity(obj, attribute, THREAT_COLOUR_ERROR)
    return lambda mesh: (contract is None or contract(mesh)) and fidelity(mesh)


def _lin(hex_color):
    return tuple(mt.linear(hex_color))


def build_creature_ambush_body():
    fine = _fine_body(mt.build_ambush_body)
    fields = mt.build_ambush_body()
    body = bpy.data.objects["Body"]
    # Hide: a pebbled, warty back (raised cells, glossier on their crowns) and fine scales on the belly.
    sh = sf.Shader("M_AmbushBodyProc")
    back = sh.remap(sh.axis("Z"), -0.03, 0.03)
    warts = sh.remap(sh.voronoi(34.0, 0.85), 0.42, 0.05)
    small = sh.remap(sh.voronoi(85.0, 0.9), 0.4, 0.05)
    scales = sh.remap(sh.voronoi(70.0, 0.6, feature="DISTANCE_TO_EDGE"), 0.0, 0.08)
    pores = sh.noise(240.0, 2.0)
    height = sh.math("ADD", sh.math("MULTIPLY", sh.math("ADD", warts, sh.math("MULTIPLY", small, 0.35)), back),
                     sh.math("MULTIPLY", sh.math("MULTIPLY", scales, 0.35), sh.math("SUBTRACT", 1.0, back)))
    height = sh.math("ADD", height, sh.math("MULTIPLY", pores, 0.12))
    sh.bump(height, 0.55, 0.004)
    detail = _grey(sh, sh.remap(height, 0.05, 0.9, smooth=False), 0.62)
    rough = sh.math("SUBTRACT", 0.62, sh.math("MULTIPLY", warts, 0.22))
    shaders = {
        "M_AmbushBody": sh.out(detail, rough),
        "M_AmbushEye": _eye_shader("M_AmbushEyeProc", (0.35, 1.0, 0.45), 0.55),
        "M_AmbushPupil": _plain_shader("M_AmbushPupilProc", 0.12, lo=0.95),
    }
    bsh = sf.Shader("M_AmbushBrowProc")
    folds = bsh.noise(70.0, 3.0, vector=_stretched(bsh, (0.4, 1.0, 2.5)))
    knobs = bsh.remap(bsh.voronoi(60.0, 0.8), 0.4, 0.05)
    bheight = bsh.math("ADD", folds, bsh.math("MULTIPLY", knobs, 0.6))
    bsh.bump(bheight, 0.6, 0.004)
    shaders["M_AmbushBrow"] = bsh.out(_grey(bsh, bsh.remap(bheight, 0.3, 1.2), 0.6), 0.7)
    objs = [body] + [bpy.data.objects[n] for n in ("Eye_L", "Eye_R", "Pupil_L", "Pupil_R", "Brow")]
    _swap_materials(objs, shaders)
    amber = _lin(mt.MINERAL_AMBER)
    tints = {
        "M_AmbushBody": sf.tint(vertex_colors="AmbushColor"),
        "M_AmbushEye": sf.tint(amber, emission=amber, emission_strength=mt.AMBUSH_EYE_GLOW),
        "M_AmbushPupil": sf.tint(_lin(mt.DEEP_SHADOW)),
        "M_AmbushBrow": sf.tint(_lin(mt.AMBUSH_BROW)),
    }
    fields.update(_threat_bake(objs, body, tints, _colours_and(body, "AmbushColor"), "AmbushHunter", fine))
    _threat_frame_check(body, "creature_ambush_body")
    fields.update({
        "purpose": "M1 step 3 ambush hunter body (role: ambush): a big, flat, dark mottled pebble with a warty hide and wet amber eyes glowing under a heavy wrinkled brow. Body only; its parts come from the part GLBs.",
        "revision": 2,
        "dependencies": ["assets/export/M_AmbushBody.tres"],
    })
    return fields


def _rammer_contract(mesh):
    """The tests' midline bands: vertices along the top of the back, crossed by three dark bands."""
    attr = mesh.color_attributes["RammerColor"].data
    line = []
    for v in mesh.vertices:
        if abs(v.co.x) < 0.001 and v.co.z > 0.05:
            r, g, b = (ld.srgb_to_linear(c) for c in attr[v.index].color[:3])
            line.append((v.co.y, 0.2126 * r + 0.7152 * g + 0.0722 * b))
    line.sort()
    bands, inside = 0, False
    for _, lum in line:
        if lum < 0.1 and not inside:
            bands += 1
        inside = lum < 0.1
    return len(line) > 24 and bands == 3


def build_creature_rammer_body():
    fine = _fine_body(mt.build_rammer_body)
    fields = mt.build_rammer_body()
    body = bpy.data.objects["Body"]
    # Hide: leathery plates (fine grooves between scutes), pores, and a matte sheen.
    sh = sf.Shader("M_RammerBodyProc")
    plates = sh.remap(sh.voronoi(18.0, 0.7, feature="DISTANCE_TO_EDGE"), 0.0, 0.07)
    creases = sh.remap(sh.noise(55.0, 4.0, vector=_stretched(sh, (1.0, 0.35, 1.0))), 0.45, 0.6)
    pores = sh.noise(260.0, 2.0)
    height = sh.math("ADD", sh.math("MULTIPLY", plates, 0.8), sh.math("ADD", sh.math("MULTIPLY", creases, 0.2), sh.math("MULTIPLY", pores, 0.1)))
    sh.bump(height, 0.45, 0.004)
    detail = _grey(sh, sh.remap(height, 0.1, 0.95, smooth=False), 0.72)
    rough = sh.math("ADD", 0.48, sh.math("MULTIPLY", sh.math("SUBTRACT", 1.0, plates), 0.18))
    shaders = {
        "M_RammerBody": sh.out(detail, rough),
        "M_RammerEye": _eye_shader("M_RammerEyeProc", (0.45, 1.0, 0.2), 0.8),
        "M_RammerPupil": _plain_shader("M_RammerPupilProc", 0.1, lo=0.95),
    }
    lsh = sf.Shader("M_RammerLidProc")
    wrinkles = lsh.noise(90.0, 3.0, vector=_stretched(lsh, (3.0, 3.0, 0.5)))
    lsh.bump(wrinkles, 0.4, 0.002)
    shaders["M_RammerLid"] = lsh.out(_grey(lsh, lsh.remap(wrinkles, 0.35, 0.7), 0.78), 0.62)
    # The crest: a veined membrane, and keratin streaks running up the points.
    hsh = sf.Shader("M_RammerHoodProc")
    veins = hsh.remap(hsh.voronoi(26.0, 0.9, vector=_stretched(hsh, (0.2, 1.0, 0.6)), feature="DISTANCE_TO_EDGE"), 0.0, 0.05)
    hsh.bump(hsh.math("MULTIPLY", veins, 0.5), 0.35, 0.003)
    shaders["M_RammerHood"] = hsh.out(_grey(hsh, veins, 0.7), 0.55)
    tsh = sf.Shader("M_ThreatProc")
    streaks = tsh.noise(80.0, 3.0, vector=_stretched(tsh, (6.0, 2.0, 0.4)))
    tsh.bump(streaks, 0.25, 0.002)
    shaders["M_Threat"] = tsh.out(_grey(tsh, tsh.remap(streaks, 0.3, 0.7), 0.8), 0.4)
    names = ("Eye_L", "Eye_R", "Pupil_L", "Pupil_R", "Lid_L", "Lid_R", "Hood")
    objs = [body] + [bpy.data.objects[n] for n in names]
    _swap_materials(objs, shaders)
    tints = {
        "M_RammerBody": sf.tint(vertex_colors="RammerColor"),
        "M_RammerEye": sf.tint(_lin(mt.CREAM)),
        "M_RammerPupil": sf.tint(_lin(mt.DEEP_SHADOW)),
        "M_RammerLid": sf.tint(_lin(mt.RAMMER_LID)),
        "M_RammerHood": sf.tint(_lin(mt.RAMMER_BAND)),
        "M_Threat": sf.tint(_lin(mt.THREAT)),
    }
    fields.update(_threat_bake(objs, body, tints, _colours_and(body, "RammerColor", _rammer_contract), "Rammer", fine))
    _threat_frame_check(body, "creature_rammer_body")
    fields.update({
        "purpose": "M1 step 3 territorial rammer body (role: territorial): a pale, leathery domed pebble with three dark bands, a veined dorsal crest with threat-coloured points and frowning lids. Body only; its spikes and other parts come from the part GLBs.",
        "revision": 2,
        "dependencies": ["assets/export/M_RammerBody.tres"],
    })
    return fields


def _threat_frame_check(body, asset_id):
    """The reduced body still meets the swim plane on PartPlacement's ellipse (the tests allow 1 cm)."""
    tris = [tuple(body.matrix_world @ body.data.vertices[i].co for i in t.vertices) for t in _triangles(body)]
    worst = 0.0
    for a, b, c in tris:
        for p, q in ((a, b), (b, c), (c, a)):
            if (p.z > 0.0) != (q.z > 0.0):
                t = p.z / (p.z - q.z)
                x, y = p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t
                worst = max(worst, abs(math.hypot(x, y) - mt.frame_radius(math.atan2(x, y))))
    _check(worst <= 0.006, f"{asset_id}: reduced swim plane section off the frame ellipse by {worst:.4f} m")


SPIKE_SIDES = 24
SPIKE_STEPS = 18


def build_part_spike():
    """The blockout's thorn (length, collar, colours and attachment) with a finer profile: a bone
    collar, the threat colour along a shaft ringed with growth lines, darkening to a glossy point."""
    end = mt.SPIKE_LENGTH - mt.PART_EMBED
    r0 = mt.SPIKE_RADIUS
    profile = [(-mt.PART_EMBED, 0.0), (-mt.PART_EMBED, r0), (-0.012, r0 * 1.03), (0.0, r0 * 1.05), (0.01, r0 * 1.02), (0.018, r0 * 0.96)]
    for i in range(1, SPIKE_STEPS):
        t = i / SPIKE_STEPS
        profile.append((0.018 + (end - 0.018) * t, r0 * 0.9 * (1.0 - t) ** 1.15))
    profile.append((end, 0.0))
    verts, faces, bands = bc.revolve(profile, SPIKE_SIDES)
    tip_from = end - 0.075
    face_materials = []
    for b in bands:
        y = (profile[b][0] + profile[b + 1][0]) / 2.0
        face_materials.append(0 if y < 0.012 else (2 if y > tip_from else 1))
    root = sf.Shader("M_SpikeRootProc")
    knurl = root.noise(150.0, 3.0)
    root.bump(knurl, 0.3, 0.002)
    shaft = sf.Shader("M_SpikeShaftProc")
    rings = shaft.math("SINE", shaft.math("MULTIPLY", shaft.axis("Y"), 260.0))
    streak = shaft.noise(70.0, 3.0, vector=_stretched(shaft, (4.0, 0.3, 4.0)))
    shaft_h = shaft.math("ADD", shaft.math("MULTIPLY", rings, 0.25), streak)
    shaft.bump(shaft_h, 0.3, 0.002)
    tip = sf.Shader("M_SpikeTipProc")
    tstreak = tip.noise(90.0, 3.0, vector=_stretched(tip, (5.0, 0.3, 5.0)))
    tip.bump(tstreak, 0.15, 0.002)
    mats = [root.out(_grey(root, root.remap(knurl, 0.3, 0.7), 0.8), 0.6),
            shaft.out(_grey(shaft, shaft.remap(shaft_h, -0.1, 0.9), 0.78), 0.4),
            tip.out(_grey(tip, tip.remap(tstreak, 0.3, 0.7), 0.82), 0.25)]
    spike = bc.mesh_object("Spike", verts, faces, mats, face_materials)
    for mat, name in zip(mats, ("M_SpikeRoot", "M_SpikeShaft", "M_SpikeTip")):
        mat.name = name
    tints = {"M_SpikeRoot": sf.tint(_lin(mt.SPIKE_ROOT)), "M_SpikeShaft": sf.tint(_lin(mt.THREAT)),
             "M_SpikeTip": sf.tint(_lin(mt.SPIKE_TIP))}
    baked = _threat_bake([spike], None, tints, None, "PartSpike")
    pts = bc.world_vertices()
    y_max = max(p.y for p in pts)
    _check(min(p.y for p in pts) >= -0.05, "spike: sinks at most 0.05 m behind its attachment point")
    _check(abs(y_max - end) < 1e-4, "spike: the point is SPIKE_LENGTH - PART_EMBED out")
    return {
        "purpose": "M1 step 3 spike part (rams): a tapered thorn in the threat colour ringed with growth lines, with a bone collar, darkening to a glossy point.",
        "category": "part",
        "part_type": "spike",
        "attachment": dict(mt.PART_ATTACHMENT),
        "length_m": mt.SPIKE_LENGTH,
        "tip_m": round(y_max, 3),
        "revision": 2,
        **baked,
    }


# --- Driver -----------------------------------------------------------------------------------

# asset id -> (builder, triangle budget). Budgets are the M1 step 2 and step 3 plans', also in tests/test_assets.gd.
ASSETS = {
    "part_flagellum": (build_flagellum, 1500),
    "part_eye_spot": (build_eye_spot, 1500),
    "part_mouth_filter": (build_mouth_filter, 1500),
    "part_mouth_jaw": (build_mouth_jaw, 1500),
    "plankton": (build_plankton, 400),
    "carrion": (build_carrion, 400),
    "rock_a": (lambda: build_rock("rock_a"), 1300),
    "rock_b": (lambda: build_rock("rock_b"), 1300),
    "rock_c": (lambda: build_rock("rock_c"), 1300),
    "sample_cell": (build_sample_cell, 8000),
    "creature_ambush_body": (build_creature_ambush_body, 4000),
    "creature_rammer_body": (build_creature_rammer_body, 4000),
    "part_spike": (build_part_spike, 600),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the M1 production assets.")
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
        provenance = PROVENANCE.format(fields.pop("provenance_extra", ""))
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR, provenance=provenance)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
