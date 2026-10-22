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
import surfacing as sf  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

GENERATOR = "tools/blender/make_m1_production.py"
REVIEW_STATE = "production rev 1 - M1, awaiting owner look review"
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_m1_production.py; no external or "
              "generated meshes. Textures baked in Blender from procedural shaders{}.")
PART_TEXTURE = 512    # microscopic creature budget (art direction section 4)
FOOD_TEXTURE = 256    # tiny, drawn hundreds of times
ROCK_TEXTURE = 512    # a 2 m prop is about 150 px tall at the gameplay camera

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


def _part(asset_id_type, purpose, objs, extra=None):
    """Bake the part's shaders to one texture set, then the blockout's attachment checks."""
    sf.unwrap(objs)
    textures = sf.bake_set(objs, asset_id_type["texture"], PART_TEXTURE, **(extra or {}))
    fields = mb._part_fields(asset_id_type["type"], purpose)
    fields["textures"] = textures
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
        pitch = math.radians(-8.0 + 88.0 * i / rows)          # from the brow (front) over the top
        for j in range(cols + 1):
            yaw = math.radians(-80.0 + 160.0 * j / cols)
            edge = 1.0 - 0.18 * (abs(j / cols - 0.5) * 2.0) ** 2
            r = (EYE_BALL_R + 0.009) * edge
            d = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
            # A soft point at the front middle: the petal tip.
            tip = 0.012 * math.exp(-((j / cols - 0.5) / 0.18) ** 2) * (1.0 - i / rows)
            hood.append(Vector((0.0, EYE_CENTRE_Y, 0.0)) + d * (r + tip * 0.3) + Vector((0.0, tip, 0.0)) * 0.6)
    hood_faces = [(i * (cols + 1) + j, i * (cols + 1) + j + 1, (i + 1) * (cols + 1) + j + 1, (i + 1) * (cols + 1) + j)
                  for i in range(rows) for j in range(cols)]
    lid = bc.mesh_object("EyeSpotLid", hood, hood_faces, [lid_proc], fix_normals=False, parent=eye)
    solid = lid.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.008
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
    profile = [(-mb.PART_EMBED, 0.0), (-mb.PART_EMBED, 0.068), (0.0, 0.07), (0.025, 0.074), (0.055, 0.085),
               (0.085, 0.099), (0.108, 0.111), (0.122, rim), (0.131, rim - 0.006), (0.128, rim - 0.018),
               (0.112, 0.094), (0.09, 0.078), (0.065, 0.058), (0.045, 0.034), (0.036, 0.0)]
    segments = 32
    verts, faces, _ = bc.revolve(profile, segments)
    # Scallop the rim into eight petals: the lip rings swell and rise at each petal's middle and
    # pinch between petals (pebble, petal, bead).
    lip_rings = range(6, 10)
    for ring in lip_rings:
        weight = {6: 0.35, 7: 0.75, 8: 1.0, 9: 0.8}[ring]
        for j in range(segments):
            a = 2.0 * math.pi * j / segments
            petal = math.cos(PETALS * a)                      # +1 mid-petal, -1 between petals
            k = 1 + (ring - 1) * segments + j                 # ring 0 is the pole at the base
            v = Vector(verts[k])
            scale = 1.0 + weight * 0.07 * petal
            verts[k] = (v.x * scale, v.y + weight * 0.008 * petal, v.z * scale)
    # The fringe: sixteen tapered cilia leaning out between the petals.
    lean = math.radians(40.0)
    for k in range(16):
        a = 2.0 * math.pi * (k + 0.5) / 16
        radial_dir = Vector((math.cos(a), 0.0, math.sin(a)))
        out = Vector((0.0, math.cos(lean), 0.0)) + radial_dir * math.sin(lean)
        base_pt = Vector((0.0, 0.124, 0.0)) + radial_dir * (rim * 0.97)
        length = 0.048 + 0.012 * math.cos(3.0 * a)
        path = [base_pt + out * (length * i / 3) + radial_dir * (0.008 * (i / 3) ** 2) for i in range(4)]
        tv, tf = bc.tube(path, [0.009, 0.007, 0.0045, 0.0], 5)
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
            tooth = [c + inner * (r * 0.4), c + inner * (r * 0.4 + 0.016) - tangent * 0.006]
            ttv, ttf = bc.tube(tooth, [0.007, 0.0], 5)
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
    sf.unwrap([obj])
    textures = sf.bake_set([obj], "Plankton", FOOD_TEXTURE, normal=True, emission=True)
    radius = mb._horizontal_radius(pts)
    _check(abs(radius - mb.PLANKTON_ITEM_RADIUS) <= 0.2 * mb.PLANKTON_ITEM_RADIUS, "plankton: mesh radius fits the item radius")
    return {
        "purpose": "M1 plankton food item: a glowing centric diatom (radial ribs, pore rings, a food-glow core), drawn many times with one MultiMesh.",
        "category": "food",
        "food_kind": "plant",
        "revision": 2,
        "pivot": "centre of the item",
        "item_radius_m": mb.PLANKTON_ITEM_RADIUS,
        "mesh_radius_m": round(radius, 3),
        "textures": textures,
    }


def build_carrion():
    sh = sf.Shader("M_CarrionProc")
    marble = sh.noise(14.0, 4.0, 0.6)
    flesh = sh.ramp(marble, [(0.3, "#4A1622"), (0.5, "#7E2A2C"), (0.62, "rust"), (0.75, "#C8705A")])
    # Torn muscle fibres run along one direction; a pale sinew band and fat beads sit on top, so
    # the chunk reads as meat by shape and marking, not colour alone (section 3).
    fibres = sh.noise(3.0, 2.0, 0.5, vector=sh.vmath("MULTIPLY", sh.pos, (60.0, 6.0, 60.0)))
    flesh = sh.mix(sh.math("MULTIPLY", sh.remap(fibres, 0.35, 0.65), 0.35), flesh, "#3A1018")
    across = sh.math("ADD", sh.vmath("DOT_PRODUCT", sh.pos, (0.6, -0.8, 0.0)), sh.math("MULTIPLY", sh.noise(18.0, 2.0), 0.03))
    sinew = sh.math("MULTIPLY", sh.remap(sh.math("ABSOLUTE", sh.math("SUBTRACT", across, 0.035)), 0.045, 0.02),
                    sh.remap(sh.axis("Z"), -0.02, 0.04))
    fat = sh.math("MULTIPLY", sh.remap(sh.voronoi(16.0, 1.0), 0.17, 0.11), sh.remap(sh.axis("Z"), 0.0, 0.08))
    base = sh.mix(sinew, flesh, sh.ramp(sh.noise(30.0, 2.0), [(0.3, "#E8D6C0"), (0.7, "cream")]))
    base = sh.mix(sh.math("MULTIPLY", fat, 0.9), base, "#EFC98F")
    underside = sh.remap(sh.axis("Z"), -0.09, -0.03)
    base = sh.mix(underside, base, "#2E0E14")
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
    sf.unwrap([obj])
    textures = sf.bake_set([obj], "Carrion", FOOD_TEXTURE, normal=True)
    radius = mb._horizontal_radius(pts)
    _check(abs(radius - mb.CARRION_ITEM_RADIUS) <= 0.2 * mb.CARRION_ITEM_RADIUS, "carrion: mesh radius fits the item radius")
    return {
        "purpose": "M1 carrion food item (static, sinks, no drift): a torn, marbled flesh chunk with a pale sinew band and fat beads, drawn with one MultiMesh.",
        "category": "food",
        "food_kind": "meat",
        "revision": 2,
        "pivot": "centre of the item",
        "item_radius_m": mb.CARRION_ITEM_RADIUS,
        "mesh_radius_m": round(radius, 3),
        "textures": textures,
    }


# --- Rocks ------------------------------------------------------------------------------------


ROCK_TINTS = {   # (stone base, stone light, accent) per variant, cool and below about 55% saturation
    "rock_a": ("#5E6A6C", "#A9ABA0", "mineral_amber"),
    "rock_b": ("#5A5F66", "#9EA3A6", "#C99A5B"),
    "rock_c": ("#66665E", "#B2AC9C", "mineral_amber"),
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
    stone = sh.ramp(lum.outputs["Val"], [(0.15, "deep_shadow"), (0.35, dark), (0.75, light), (1.0, "#D8D2C2")])
    geo = sh.node("ShaderNodeNewGeometry")
    up = sh.vmath("DOT_PRODUCT", geo.outputs["Normal"], (0.0, 0.0, 1.0))
    # Algae and moss settle on the lit, upward faces above the water line (pebble top reads green
    # from the gameplay camera), patchy by noise.
    patch = sh.noise(2.2, 4.0, 0.6, w=seed)
    moss_mask = sh.math("MULTIPLY", sh.remap(up, 0.35, 0.8), sh.remap(patch, 0.42, 0.58))
    moss = sh.ramp(sh.noise(18.0, 3.0, w=seed), [(0.3, "moss_deep"), (0.65, "algae_green"), (1.0, "#9CC27A")])
    base = sh.mix(sh.math("MULTIPLY", moss_mask, 0.92), stone, moss)
    # A darker, slightly wet band where the rock sits in water, fading under the swim plane.
    wet = sh.remap(sh.axis("Z"), 0.1, -0.5)
    base = sh.mix(sh.math("MULTIPLY", wet, 0.45), base, "#24364A")
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
    sf.unwrap([obj], margin=0.004)
    textures = sf.bake_set([obj], f"Rock{asset_id[-1].upper()}", ROCK_TEXTURE, normal=True)
    fields.update({
        "purpose": "M1 pool rock, an obstacle the cell slides around: cool stone with algae on its lit top, a wet band at the water line and warm mineral flecks. Placed by game/data/pool_m1.json with yaw and uniform scale.",
        "revision": 3,
        "textures": textures,
        "dependencies": [dict(CC0_ROCK)],
        "provenance_extra": "; surface detail from the CC0 Poly Haven scan in dependencies",
    })
    return fields


# --- Driver -----------------------------------------------------------------------------------

# asset id -> (builder, triangle budget). Budgets are the M1 step 2 plan's, also in tests/test_assets.gd.
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
