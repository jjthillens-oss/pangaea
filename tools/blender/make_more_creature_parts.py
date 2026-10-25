"""Twenty more creature parts (PROPOSED; owner request "more-parts", docs/art/creature_parts_more.md): beaks,
trunks, more mouths and eyes, webbed and padded feet, antlers, tails of four kinds, shells, a mane ridge and a
feather crest, so players can build many more animal types.

Same convention as tools/blender/make_creature_parts.py (docs/art/creature_art_contract.md, section 1), whose
helpers this script imports and never edits:
- Blender +Z (Godot +Y) is the skin normal at the anchor, Blender +Y (Godot -Z) points toward the head.
- The pivot is where the part meets the skin; geometry below it, down to sink_depth, is the root.
  Ground parts (feet) instead stand on the pivot: +Z is body up at rest, the sole on z = 0, the ankle top at about
  z = 0.09 (anchor_resolver.gd GROUND_ANKLE_M).
- Mouths and eyes are authored like the existing ones (their outward axis along Blender +Z, the upper side on +Y),
  so every mouth and every eye is placed by the same forward_cone frame.
- Authored at the part's nominal size for a body about 1 m long (scale 1000 per mille).
- Up to four shape keys H1_..H4_ are the handles, 0 to 1000 per mille; the runtime sets them as blend shapes.
- One root mesh named after the part type, no bones; chiral parts ship the right-hand (+X) side only.
- record["part_rules"] holds the PartRules values; tools/make_part_rules.py copies them into
  game/data/creature/part_rules.json, which is how a part reaches the editor's palette (data only).

Each part is finished like the others: procedural greyscale detail baked to one texture set (albedo detail with AO,
ORM, normal), each material keeping its name and flat colour, and paint_mix saying how much of the creature's paint
replaces that colour. Each record carries review_notes: the finish-hunyuan-assets Gates 1 to 4 as pass, needs
revision or unverified, with the observation behind it (tools/blender/render_more_parts_gates.py renders Gates 1-3,
tools/godot/more_parts_shots.gd Gate 4).

Helpers that make_creature_parts.py defines twice (_smooth, _pad_material, _fur_material) are copied here under an
_mp prefix rather than called through the module, so a rename there cannot change these parts.

Run: python3 tools/blender/make_more_creature_parts.py [--only <id>[,<id>...]]   (bpy 5.2.2)
Then godot --headless --path . --import, and python3 tools/make_part_rules.py.
"""
import argparse
import json
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_creature_parts as cp  # noqa: E402,F401  (the shared part helpers: _tube, _bake, _shape_keys, ...)
import make_m1_production as mp  # noqa: E402
import surfacing as sf  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402,F401

GENERATOR = "tools/blender/make_more_creature_parts.py"
REVIEW_STATE = mp.REVIEW_STATE
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_more_creature_parts.py, with helpers from "
              "tools/blender/make_creature_parts.py; no external or generated meshes. Textures baked in Blender from "
              "procedural shaders.")

# What each part does in play (PROPOSED), chosen from the roles the creature code already reads
# (game/domain/creature/creature_stats.gd; Bible section 12, Anatomy and evolution model):
# - mouth: "mouth and feeding apparatus" (bite and reach). The trunks are feeding apparatus with reach.
# - eye: "eyes and sensory organs" (sight).
# - foot: "legs and feet" (no stat today).
# - weapon: the antlers and the stinger strike; the codebase's stand-in for "armor and spines" (attack).
# - detail: display parts (charm), and the parts whose own effect has no role yet: the shells (there is no
#   defensive role, and weapon would add attack), the paddle tail (no swim role) and the curling tail (no grasp
#   effect; it carries the grasper capability instead). The per-kind effects are proposed in a GitHub issue.
ROLE = {
    "beak_hooked": "mouth", "beak_long": "mouth", "trunk": "mouth", "trunk_short": "mouth",
    "mouth_sucker": "mouth", "mouth_fangs": "mouth",
    "eye_turret": "eye", "eye_lashed": "eye",
    "foot_otter": "foot", "foot_pillar": "foot",
    "antler_branched": "weapon", "antler_palmate": "weapon", "tail_stinger": "weapon",
    "tail_feather": "detail", "tail_paddle": "detail", "tail_curl": "detail",
    "shell_dome": "detail", "shell_spiral": "detail", "mane_ridge": "detail", "crest_feather": "detail",
}

# part_rules "capabilities" (optional; the hand records set the precedent and no game code reads it yet):
# Bible section 12, grasping structures.
CAPABILITIES = {"trunk": ["grasper"], "tail_curl": ["grasper"]}

GATES = ("gate1_shape", "gate2_materials", "gate3_neutral_light", "gate4_godot")
# asset id -> {gate: "pass: ..." | "needs revision: ..." | "unverified: ..."}, filled in as each part is reviewed
# (Gates 1-3 from tools/blender/render_more_parts_gates.py sheets; Gate 4 from tools/godot/more_parts_shots.gd).
# `--notes-only` copies these into the existing records without rebuilding the meshes.
G4_PENDING = "unverified: not yet seen in the creature editor (more_parts_shots.gd)"
REVIEW = {
    "cpart_beak_hooked": {
        "gate1_shape": "pass: side view reads as a raptor's beak - a deep keeled upper mandible arcing into a pointed "
                       "hook that overhangs the shorter lower mandible, the two closed along a seam with the upper's "
                       "edges flanking the lower; the cere stands proud as a clean ring band; handles render as named "
                       "(H1_Open drops the lower mandible, H2_Hook curls the hook under, H3_Length draws it out).",
        "gate2_materials": "pass: two distinct finishes - slate-blue horn darkening to a near-black hook with fine "
                           "lengthwise grain, and a saturated yellow waxy cere with one round dark nostril each side; "
                           "the material borders are clean rings (the lower mandible is kept undecimated for that).",
        "gate3_neutral_light": "pass: under the neutral white rig the horn's soft highlight runs along the keel and "
                               "the hook, nothing clips and the underside of the hook stays readable.",
        "gate4_godot": "needs revision: orientation only, from the shared forward_cone frame (every existing mouth and eye points the same way; not this art). In the creature editor on the tortoise (beak swapped in memory, docs/evidence/credit-more-parts/after_tortoise_beak_hooked.jpg) it loads, seats on the snout tip without floating or deep clipping, is in scale with the head and keeps its slate horn and yellow cere, but it points up out of the snout. With the frame fix previewed (more_parts_shots.gd --cone-fix-preview, conefix_tortoise_beak_hooked.jpg) it points forward with the hook curving down and reads as a raptor's beak at the world camera's distance."},
    "cpart_beak_long": {
        "gate1_shape": "pass: a slender gently decurved bill about 0.23 m out of the skin with a rounded probe tip and "
                       "a fleshy gape bulge at the root; the upper mandible overhangs the lower by about 1 cm and the "
                       "seam reads as a crease; handles move both mandibles together (H1_Length, H2_Curve) or the "
                       "lower alone (H3_Open) without tearing.",
        "gate2_materials": "pass: a saturated orange horn with lengthwise streaks, a darker probe tip, the closing "
                           "seam and the nostril groove painted as two dark lines along each side; a separate pink "
                           "fleshy gape at the root.",
        "gate3_neutral_light": "pass: even neutral light, a narrow highlight along the culmen, no clipping; the "
                               "groove and seam lines stay visible in the side and close views.",
        "gate4_godot": "needs revision: orientation only, from the shared forward_cone frame (not this art). On the strider (after_strider_beak_long.jpg) it loads, seats on the snout tip and keeps its orange horn, but stands up like a horn. With the frame fix previewed (conefix_strider_beak_long.jpg) it reaches forward and curves down, reading as an ibis-like probing bill at the world camera's distance."},
    "cpart_trunk": {
        "gate1_shape": "pass: a thick root tapering over about 0.38 m, hanging down and turning forward at the end in "
                       "an S, flatter underneath; the grip pad shows two finger-like lips (the upper larger) round a "
                       "dished face; H1_Curl coils the outer half into a grasping hook, H2_Raise lifts it forward "
                       "and up, H3_Length lengthens it, the pad riding rigidly on the end.",
        "gate2_materials": "pass: cool grey wrinkled skin whose ring folds and crackle read in the normal map and "
                           "albedo, against a darker warm-brown pebbled grip pad with two dark nostrils.",
        "gate3_neutral_light": "pass: neutral white light shows the ring wrinkles by grazing light along the whole "
                               "length; no clipped highlights, the pad stays readable in shadow.",
        "gate4_godot": "needs revision: orientation only, from the shared forward_cone frame (not this art). On the longneck (after_longneck_trunk.jpg) it loads and seats on the snout tip, but rises and arcs back over the head. With the frame fix previewed (conefix_longneck_trunk.jpg) it comes forward and hangs down from the snout, reading as a trunk; on this 3 m body it is slim at its default scale, which the editor's scale handle covers."},
    "cpart_trunk_short": {
        "gate1_shape": "pass: a broad, slightly flattened snout about 0.11 m out of the skin, tapering and drooping "
                       "over a soft lower lip tucked under its root, so the mouth reads as a crease beneath an "
                       "overhang; a domed oval nose pad with two flared nostril lobes closes the end cleanly; H1_Curl "
                       "turns the end down over the lip, H2_Length draws it out, the pad riding rigidly.",
        "gate2_materials": "pass: fine-grained grey skin with soft transverse folds, against a near-black glossy "
                           "pebbled nose pad with two dark nostril openings.",
        "gate3_neutral_light": "pass: neutral light shows the folds and the pad's gloss without clipping; the "
                               "mouth crease reads as a shadowed line.",
        "gate4_godot": "needs revision: orientation only, from the shared forward_cone frame (not this art). On the boar (after_boar_trunk_short.jpg) it loads, seats on the snout between the tusks and keeps its dark nose pad, but points up and forward. With the frame fix previewed (conefix_boar_trunk_short.jpg) it juts forward and droops, reading as a tapir's snout."},
    "cpart_mouth_sucker": {
        "gate1_shape": "pass: a short trumpet-shaped funnel about 5.5 cm out of the skin flaring to a fleshy bead "
                       "of lip scalloped into ten soft ruffled lobes (about 11 cm across); inside it a dished disc "
                       "with three distinct concentric rings of small cones (16, 12, 8) all hooking in toward a "
                       "round throat. It reads apart from the maw (flat rolled ring, fourteen long fangs) by the "
                       "standing funnel, the scalloped rim and the many small teeth. H1_Gape opens the throat and "
                       "spreads the inner rings; H2_Flare spreads the rim wide and flat, the teeth riding with the "
                       "disc. Iterated: the first rim was a sharp zigzag crown on a thin cup wall.",
        "gate2_materials": "pass: three finishes - wet sea-green lip skin with ring wrinkles and small round "
                           "papillae on the bead, a low-chroma plum disc darkening to near black down the throat, "
                           "and amber horn teeth; the lip-to-disc border is a clean line (the disc is its own mesh "
                           "tucked under the bead; the first build's single mesh decimated it into a sawtooth).",
        "gate3_neutral_light": "pass: under the neutral white rig the bead's highlight reads its roll, the teeth "
                               "stand out against the dark disc, the throat stays dark without crushing the disc; "
                               "no clipping.",
        "gate4_godot": G4_PENDING},
    "cpart_mouth_fangs": {
        "gate1_shape": "pass: a short, wide, low snout of lips (13.1 cm across, 6.5 cm deep, standing 7.5 cm out of "
                       "the skin) resting a little open over a shorter lower jaw; face-on (gray_top, the in-game "
                       "front) it reads as a wide lens of a mouth with two long fangs hanging from the upper jaw's "
                       "front in front of the chin and curving back, and the forked tongue between the lips; from "
                       "the side the mouth line is a dark slot with the fangs crossing it at the tip. H1_Open drops "
                       "the lower jaw about 34 degrees and swings the fangs forward to strike; H2_Tongue flicks the "
                       "tongue about 4 cm out and spreads its fork. Iterated: the first icosphere jaws were 1518 "
                       "triangles, so the jaws are lathed domes with rings crowded at the lip edge (909 now).",
        "gate2_materials": "pass: three finishes - teal skin of domed snake scales with crisp grooves (larger plates "
                           "and a slightly paler tone along the mouth line, which reads only faintly in the gap's "
                           "shade), ivory fangs with fine lengthwise streaks, and a dark plum wet mouth and tongue "
                           "(low chroma, LAB hue 334, clear of the threat pink). Iterated: the first scale shader "
                           "read as cracked mud.",
        "gate3_neutral_light": "pass: under the neutral white rig the scales' domes catch soft highlights, the fangs "
                               "stay bright without clipping and the tongue's fork reads against the sky; the mouth "
                               "slot is dark but not crushed.",
        "gate4_godot": G4_PENDING},
    "cpart_eye_turret": {
        "gate1_shape": "pass: a smooth, slightly convex cone 8.4 cm across and 6 cm out of the skin with a round "
                       "aperture at its tip (gray_top), the ball sitting just inside it. H1_Blink puckers the "
                       "aperture shut, H2_Reach stretches the turret about 2.2 cm taller with the ball riding up "
                       "inside. Iterated: the first turret read as a beehive dome whose geometric ridges decimated "
                       "into irregular terraces and whose aperture was a hexagon; the ridges are now in the normal "
                       "map and the cone is decimated at a tighter 0.3 mm tolerance (668 triangles).",
        "gate2_materials": "pass: two finishes - turquoise skin of small domed granular tubercles in concentric ring "
                           "bands, and through the aperture a glossy gold iris ring round a black pupil (the crop of "
                           "mat_threequarter shows both). Iterated: the first scale shader read as cracked mud.",
        "gate3_neutral_light": "pass: under the neutral rig the ring bands and tubercles read by soft grazing light, "
                               "the gold ring is visible inside the shadowed aperture; no clipping.",
        "gate4_godot": G4_PENDING},
}


def _rules(part_type, footprint, sink, orientation, hosts, turn, tilt, centerline="allowed", chiral=False):
    """The PartRules block, in the same keys and order as make_creature_parts._rules, from this script's ROLE."""
    rules = {"type": part_type, "footprint_radius_m": footprint, "sink_depth_m": sink, "chiral": chiral,
             "orientation": orientation, "turn_limit_deg": turn, "tilt_limit_deg": tilt,
             "centerline": centerline, "hosts": hosts, "role": ROLE[part_type]}
    if part_type in CAPABILITIES:
        rules["capabilities"] = list(CAPABILITIES[part_type])
    return rules


def _review_notes(asset_id):
    notes = {gate: "unverified: not reviewed yet" for gate in GATES}
    notes.update(REVIEW.get(asset_id, {}))
    return notes


# --- Helpers copied from make_creature_parts.py (defined there twice; see the module docstring) ------------------


def _mp_smooth(x, a, b):
    """Smoothstep of x from a to b."""
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _mp_pad_material(name, rough=0.4):
    """A soft pad or nose leather: a fine tight pebble, smoother than the skin around it."""
    sh = sf.Shader(name)
    pebble = sh.remap(sh.voronoi(900.0, 0.9), 0.3, 0.05)
    sh.bump(sh.math("SUBTRACT", 0.0, pebble), 0.18, 0.0003)
    return sh.out(cp._grey(sh, sh.math("SUBTRACT", 1.0, sh.math("MULTIPLY", pebble, 0.2)), 0.8), rough)


def _mp_fur_material(name, lo=0.55, along=(7.0, 7.0, 0.35), rough=0.88):
    """Matte fur: fine streaks stretched along the strands (the low-frequency axis of `along`), clumped breakup."""
    sh = sf.Shader(name)
    strands = sh.noise(260.0, 2.0, vector=mp._stretched(sh, along))
    clumps = sh.remap(sh.noise(45.0, 2.0), 0.35, 0.65)
    sh.bump(strands, 0.35, 0.0007)
    fac = sh.math("ADD", sh.math("MULTIPLY", sh.remap(strands, 0.3, 0.7), 0.6), sh.math("MULTIPLY", clumps, 0.4))
    return sh.out(cp._grey(sh, fac, lo), rough)


# --- Shared construction helpers (this script's own) --------------------------------------------------------------


def _mp_arc(start, heading, length, steps, stretch=None):
    """A centreline in the y-z plane from `start`, integrated from heading(u) (radians from +Z toward -Y, so a
    positive heading bends toward the underside). stretch(k) lengthens step k (for length handles)."""
    ds = length / steps
    p, out = Vector(start), []
    for k in range(steps):
        out.append(p.copy())
        th = heading((k + 0.5) / steps)
        p = p + Vector((0.0, -math.sin(th), math.cos(th))) * (ds * (stretch(k) if stretch else 1.0))
    out.append(p.copy())
    return out


def _mp_loft(path, section, ring_points):
    """A closed tube along `path` whose cross-section at station i is section(i) -> [(s, x)] (ring_points
    pairs; s along the in-plane normal, which starts as +Y, x across): the frame is parallel-transported like
    cp._tube's, so a path bending in the y-z plane keeps x as the side axis. The start is capped; a station
    whose section is a single point closes the tip. Returns verts, faces, and each face's station index and
    ring slot (j, the section point it starts from)."""
    verts, faces, rings, face_station, face_slot = [], [], [], [], []
    n = len(path)
    t0 = (path[1] - path[0]).normalized()
    side = t0.cross(Vector((0.0, 0.0, 1.0)) if abs(t0.z) < 0.9 else Vector((1.0, 0.0, 0.0))).normalized()
    for i, p in enumerate(path):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        side = (side - t * side.dot(t)).normalized() if i else side
        across = side.cross(t).normalized()
        pts = section(i)
        if len(pts) == 1:
            rings.append([len(verts)])
            s, x = pts[0]
            verts.append(tuple(p + side * s + across * x))
            continue
        ring = []
        for s, x in pts:
            ring.append(len(verts))
            verts.append(tuple(p + side * s + across * x))
        rings.append(ring)
    cap = len(verts)
    verts.append(tuple(path[0]))
    m = ring_points
    for j in range(m):
        faces.append((cap, rings[0][(j + 1) % m], rings[0][j]))
        face_station.append(0)
        face_slot.append(j)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(m):
            k = (j + 1) % m
            faces.append((a[j], a[k], b[0]) if len(b) == 1 else (a[j], a[k], b[k], b[j]))
            face_station.append(i)
            face_slot.append(j)
    return verts, faces, face_station, face_slot


def _mp_superellipse(top, bottom, half_w, e_top, e_bottom, m, x_scale_bottom=1.0):
    """m points round a section: s (the in-plane normal) up to `top` and down to `bottom`, x to +-half_w; the
    upper half is a superellipse of exponent e_top (under 2 is pointed, a keel) and the lower one e_bottom (over
    2 is flat). Point 0 is the top (s = top, x = 0)."""
    pts = []
    for j in range(m):
        a = 2.0 * math.pi * j / m
        c, s_ = math.cos(a), math.sin(a)
        e = e_top if c >= 0 else e_bottom
        h = top if c >= 0 else bottom
        w = half_w * (1.0 if c >= 0 else x_scale_bottom)
        pts.append((h * math.copysign(abs(c) ** (2.0 / e), c), w * math.copysign(abs(s_) ** (2.0 / e), s_)))
    return pts


def _mp_nearest(path, co):
    return min(range(len(path)), key=lambda i: (co - path[i]).length_squared)


def _mp_bend(co, pivot, angle):
    """co rotated about the X axis through `pivot` by `angle` (positive turns +Z toward -Y, the underside)."""
    return pivot + Matrix.Rotation(angle, 3, "X") @ (co - pivot)


# --- Parts --------------------------------------------------------------------------------------------------------
# Builders return {purpose, category: "part", part_type, convention, part_rules, paint_mix, revision, **baked}, as
# make_creature_parts.py's do. They are added batch by batch (docs/art/creature_parts_more.md).

# --- Batch A: beaks (mouth) ---------------------------------------------------------------------------------------

HOOK_SINK = 0.02
HOOK_LEN = 0.145       # the upper mandible's arc, root cap to hook point


def _hook_heading(u):
    # Out of the skin almost level, then the outer half arcs over into a hook that ends pointing down.
    return 0.06 * _mp_smooth(u, 0.1, 0.5) + 2.15 * _mp_smooth(u, 0.48, 1.0) ** 1.15


CERE_PUFF = 1.085
HOOK_CERE = 8          # the cere covers the first 8 of the upper mandible's 30 stations (to about 2 cm above the skin)


def build_beak_hooked():
    """A raptor's beak: a deep keeled upper mandible arcing over into a sharp hook, overlapping a shorter lower
    mandible (the BeakHookedLower child), with a waxy cere band and a round nostril each side at the root.
    H1_Open drops the lower mandible, H2_Hook curls the hook further under, H3_Length draws the beak out past
    the cere."""
    steps, m = 30, 28
    start = (0.0, 0.012, -HOOK_SINK)
    path = _mp_arc(start, _hook_heading, HOOK_LEN, steps)

    def upper_dims(u):
        return (0.021 * (1.0 - u) ** 0.45 * (1.0 - 0.6 * _mp_smooth(u, 0.78, 1.0)) + 0.0008, 0.017 * (1.0 - _mp_smooth(u, 0.5, 1.0)) ** 0.65 + 0.001,
                0.021 * (1.0 - u) ** 0.8 + 0.0012)

    def upper_section(i):
        u = i / steps
        if i == steps:
            return [(0.0, 0.0)]
        top, bottom, half_w = upper_dims(u)
        puff = CERE_PUFF if i < HOOK_CERE else 1.0          # the cere stands proud of the horn, a clean step
        return [(s_ * puff, x * puff) for s_, x in _mp_superellipse(top, bottom, half_w, 1.55, 3.2, m, 1.1)]

    verts, faces, station, _ = _mp_loft(path, upper_section, m)
    face_mat = [0 if station[f] < HOOK_CERE else 1 for f in range(len(faces))]
    # The lower mandible: shallower and shorter, rising a little at its tip to tuck in under the hook; its top
    # sits inside the upper mandible's flared edges, as a raptor's does.
    lsteps, lm = 18, 20
    lpath = _mp_arc((0.0, -0.016, -HOOK_SINK), lambda u: -0.3 * _mp_smooth(u, 0.3, 1.0), 0.095, lsteps)

    def lower_section(i):
        u = i / lsteps
        if i == lsteps:
            return [(0.0, 0.0)]
        return _mp_superellipse(0.013 * (1.0 - u) ** 0.6 + 0.001, 0.015 * (1.0 - u) ** 0.75 + 0.001,
                                0.018 * (1.0 - u) ** 0.85 + 0.001, 3.0, 2.0, lm)

    lverts, lfaces, lstation, _ = _mp_loft(lpath, lower_section, lm)
    lface_mat = [0 if lpath[lstation[f]].z < 0.006 else 1 for f in range(len(lfaces))]

    # A round nostril each side in the cere, high on the flank about 1.5 cm above the skin.
    ni = HOOK_CERE - 2
    _, s_n = _mp_frames(path)[ni]
    top_n, _, w_n = upper_dims(ni / steps)
    c_n = 0.5 ** (1.55 / 2.0)                      # where the keel's superellipse is at half its height
    nostril = path[ni] + s_n * (0.5 * top_n * CERE_PUFF)
    nx = CERE_PUFF * w_n * math.sqrt(1.0 - c_n * c_n) ** (2.0 / 1.55)
    cere = sf.Shader("M_BeakHookedCereProc")
    wax = cere.noise(160.0, 3.0)
    mirrored = cere.vmath("ADD", cere.vmath("MULTIPLY", cere.vmath("ABSOLUTE", cere.pos), (1.0, 0.0, 0.0)),
                          cere.vmath("MULTIPLY", cere.pos, (0.0, 1.0, 1.0)))     # x mirrored, y and z as they are
    slit_pos = cere.vmath("MULTIPLY", cere.vmath("SUBTRACT", mirrored, (nx, nostril.y, nostril.z)), (0.6, 1.0, 1.0))
    slit = cere.remap(cere.vmath("LENGTH", slit_pos), 0.0042, 0.0024)
    cere.bump(cere.math("SUBTRACT", cere.math("MULTIPLY", wax, 0.4), cere.math("MULTIPLY", slit, 1.2)), 0.4, 0.0012)
    cere_mat = cere.out(_grey(cere, cere.math("SUBTRACT", cere.remap(wax, 0.3, 0.7, 0.8, 1.0),
                                              cere.math("MULTIPLY", slit, 0.75)), 0.2), 0.45)
    horn = sf.Shader("M_BeakHookedHornProc")
    streak = horn.noise(70.0, 3.0, vector=mp._stretched(horn, (5.0, 1.2, 1.2)))
    reach = horn.vmath("LENGTH", horn.vmath("SUBTRACT", horn.pos, (0.0, 0.0, -HOOK_SINK)))
    growth = horn.math("SINE", horn.math("MULTIPLY", reach, 260.0))
    h = horn.math("ADD", streak, horn.math("MULTIPLY", growth, 0.12))
    horn.bump(h, 0.3, 0.0012)
    tip_dark = horn.remap(reach, 0.04, 0.105, 1.0, 0.24)          # pale at the cere, near-black at the hook
    horn_mat = horn.out(_grey(horn, horn.math("MULTIPLY", tip_dark, horn.remap(h, 0.2, 0.8, 0.85, 1.0)), 0.0), 0.32)
    mats = [cere_mat, horn_mat]
    upper = bc.mesh_object("BeakHooked", verts, faces, mats, face_mat)
    lower = bc.mesh_object("BeakHookedLower", lverts, lfaces, mats, lface_mat, parent=upper)
    cere_mat.name, horn_mat.name = "M_BeakHookedCere", "M_BeakHookedHorn"
    baked = _bake_parts([upper, lower], "PartBeakHooked", {"M_BeakHookedCere": sf.tint(cp._lin("#F2B630")),
                                                           "M_BeakHookedHorn": sf.tint(cp._lin("#8C96A8"))},
                        tolerance=0.0003, keep=("BeakHookedLower",))     # kept whole: a clean gape ring
    pts = cp._check_pivot("beak_hooked", HOOK_SINK)
    foot = cp._footprint(pts, z_max=0.005)
    tip = path[-1]
    mp._check(tip.y < lpath[-1].y and max(p.z for p in path) > lpath[-1].z + 0.01,
              "beak_hooked: the hook overhangs the lower mandible's tip")

    hinge = Vector((0.0, -0.007, 0.002))

    def open_upper(co):
        return co

    def open_lower(co):
        return _mp_bend(co, hinge, math.radians(26.0) * _mp_smooth(co.z, -0.006, 0.018))

    hook_from = int(0.5 * steps)

    def hook(co):
        k = _mp_smooth(_mp_nearest(path, co), hook_from, steps)
        return _mp_bend(co, path[hook_from], math.radians(22.0) * k)

    long_path = _mp_arc(start, _hook_heading, HOOK_LEN, steps, stretch=lambda k: 1.3 if k >= HOOK_CERE else 1.0)

    def length_upper(co):
        i = _mp_nearest(path, co)
        return co + (long_path[i] - path[i])

    def length_lower(co):
        if co.z > 0.012:
            co.z = 0.012 + (co.z - 0.012) * 1.3
        return co

    handles = cp._shape_keys(upper, [("H1_Open", open_upper, "the lower mandible dropped 26 degrees at the gape"),
                                     ("H2_Hook", hook, "the hook's outer half curled 22 degrees further under"),
                                     ("H3_Length", length_upper, "the beak 30% longer past the cere")])
    cp._shape_keys(lower, [("H1_Open", open_lower, ""), ("H2_Hook", lambda co: co, ""),
                           ("H3_Length", length_lower, "")])
    rules = _rules("beak_hooked", round(foot + 0.001, 3), HOOK_SINK, "forward_cone", ["spine"], 40, 30,
                   centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = ("All three keys are on BeakHooked and BeakHookedLower with the same names; the runtime "
                             "sets them together. H1_Open moves only the lower mandible, H2_Hook only the upper.")
    return {"purpose": "Creature mouth part (PROPOSED): a raptor's hooked beak, a deep keeled upper mandible arcing "
                       "into a sharp hook over a shorter lower mandible, with a yellow cere and nostril slits; opens, "
                       "hooks and lengthens on shape keys.",
            "category": "part", "part_type": "beak_hooked", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_BeakHookedCere": 0.6, "M_BeakHookedHorn": 0.05}, "revision": 1,
            **baked}


def _mp_frames(path):
    """Per station of a y-z plane path: (tangent, in-plane normal). The normal is +Y where the tangent is +Z."""
    out, n = [], len(path)
    for i in range(n):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        out.append((t, Vector((0.0, t.z, -t.y))))
    return out


def _mp_follow(path, new_path, fixed=None):
    """A shape-key function that carries each vertex from its nearest station on `path` to the same place in the
    frame of that station on `new_path` (a bend that keeps the cross-sections square to the centreline). With
    `fixed` every vertex rides on that one station instead, rigidly (a tip piece at the end of a tube)."""
    old_f, new_f = _mp_frames(path), _mp_frames(new_path)

    def fn(co):
        i = _mp_nearest(path, co) if fixed is None else fixed
        (t, s), (t2, s2) = old_f[i], new_f[i]
        d = co - path[i]
        return new_path[i] + t2 * d.dot(t) + s2 * d.dot(s) + Vector((d.x, 0.0, 0.0))
    return fn


LONG_SINK = 0.02
LONG_LEN = 0.26        # the centreline from the root cap to the tip (0.24 m above the skin)
LONG_ROOT_R = 0.022


def _long_heading(u, more=0.0):
    # Gently decurved: the bend grows toward the tip (about 35 degrees at the tip; H2_Curve adds `more`).
    return (0.6 + more) * u ** 1.6


def build_beak_long():
    """A long probing bill like an ibis's or a kiwi's: slender, decurved, a rounded probe tip, a nostril groove
    along each side of the upper mandible, and a fleshy gape at the root. The upper mandible (BeakLong) is a
    little longer than the lower (the BeakLongLower child); they meet on a flat seam. H1_Length draws it out,
    H2_Curve bends it further down, H3_Open drops the lower mandible."""
    steps, mu, ml = 48, 30, 22
    path = _mp_arc((0.0, 0.0, -LONG_SINK), _long_heading, LONG_LEN, steps)
    lsteps = steps - 2                    # the lower mandible stops two stations (about 1 cm) short

    def env(u, end):
        # Taper toward the tip, a bulge at the gape, and a rounded cap over the last 8% of the length.
        r = 1.0 - 0.72 * u ** 0.8 + 0.16 * (1.0 - _mp_smooth(u, 0.05, 0.13))
        cap = 1.0 if u < end - 0.08 else math.sqrt(max(0.0, 1.0 - ((u - (end - 0.08)) / 0.08) ** 2))
        return r * max(cap, 0.0)

    groove_a, groove_w = 1.05, 0.15      # the nostril groove's angle from the culmen and its half-width

    def upper_section(i):
        u = i / steps
        k = env(u, 1.0)
        if k <= 1e-4:
            return [(0.0, 0.0)]
        top, half_w = LONG_ROOT_R * 0.95 * k, LONG_ROOT_R * k
        pts = []
        groove = 0.22 * _mp_smooth(u, 0.08, 0.16) * (1.0 - _mp_smooth(u, 0.72, 0.86))     # deep enough to survive
        for j, (s, x) in enumerate(_mp_superellipse(top, 0.0006, half_w, 2.3, 6.0, mu)):
            a = 2.0 * math.pi * j / mu
            d = min(abs(a - groove_a), abs(a - (2.0 * math.pi - groove_a)))
            f = 1.0 - groove * math.exp(-(d / groove_w) ** 2) if s > 0 else 1.0
            pts.append((s * f, x * f))
        return pts

    def lower_section(i):
        u = i / steps
        k = env(u, lsteps / steps)
        if k <= 1e-4 or i == lsteps:
            return [(-0.0004, 0.0)]
        return _mp_superellipse(0.0006, LONG_ROOT_R * 0.8 * k, LONG_ROOT_R * 0.97 * k, 6.0, 2.3, ml)

    verts, faces, station, _ = _mp_loft(path, upper_section, mu)
    lverts, lfaces, lstation, _ = _mp_loft(path[:lsteps + 1], lower_section, ml)
    gape_end = next(i for i, p in enumerate(path) if p.z >= 0.012)
    face_mat = [0 if station[f] < gape_end else 1 for f in range(len(faces))]
    lface_mat = [0 if lstation[f] < gape_end else 1 for f in range(len(lfaces))]

    gape = sf.Shader("M_BeakLongGapeProc")
    wr = gape.noise(150.0, 3.0)
    gape.bump(wr, 0.3, 0.001)
    gape_mat = gape.out(_grey(gape, gape.remap(wr, 0.3, 0.7), 0.78), 0.6)
    horn = sf.Shader("M_BeakLongHornProc")
    streak = horn.noise(55.0, 3.0, vector=mp._stretched(horn, (4.0, 1.5, 0.5)))
    seam = horn.remap(horn.math("ABSOLUTE", horn.math("SUBTRACT", horn.axis("Y"),
                                                       horn.math("MULTIPLY", horn.math("MULTIPLY", horn.axis("Z"),
                                                                                       horn.axis("Z")), -0.9))),
                      0.0025, 0.0)        # the closing seam, following the decurve roughly (y ~ -0.9 z^2)
    pits = horn.remap(horn.voronoi(320.0, 0.8), 0.12, 0.0)         # the sensory pits of a probing bill
    tip = horn.remap(horn.axis("Z"), 0.17, 0.225, 1.0, 0.55)
    # The nostril groove, painted where the geometry dents it: on the upper half, at about 0.75 of the bill's
    # half-width at that height (the half-width from the same taper as the mesh, the length share from z).
    u_z = horn.math("MULTIPLY", horn.math("ADD", horn.axis("Z"), LONG_SINK), 1.0 / (LONG_LEN * 0.97), clamp=True)
    half_w = horn.math("MULTIPLY", horn.math("SUBTRACT", 1.0, horn.math("MULTIPLY", horn.math("POWER", u_z, 0.8), 0.72)),
                       LONG_ROOT_R)
    ratio = horn.math("DIVIDE", horn.math("ABSOLUTE", horn.axis("X")), half_w)
    above = horn.remap(horn.math("SUBTRACT", horn.axis("Y"),
                                 horn.math("MULTIPLY", horn.math("MULTIPLY", horn.axis("Z"), horn.axis("Z")), -0.9)),
                       0.001, 0.004)
    groove = horn.math("MULTIPLY", horn.math("MULTIPLY", horn.remap(horn.math("ABSOLUTE", horn.math("SUBTRACT", ratio, 0.74)),
                                                                     0.11, 0.03), above),
                       horn.math("MULTIPLY", horn.remap(u_z, 0.1, 0.18), horn.remap(u_z, 0.84, 0.72)))
    h = horn.math("SUBTRACT", horn.math("ADD", streak, horn.math("MULTIPLY", pits, 0.25)),
                  horn.math("ADD", seam, horn.math("MULTIPLY", groove, 0.8)))
    horn.bump(h, 0.3, 0.0012)
    horn_mat = horn.out(_grey(horn, horn.math("MULTIPLY", tip, horn.math("SUBTRACT", horn.remap(streak, 0.25, 0.75, 0.82, 1.0),
                                                                           horn.math("ADD", horn.math("MULTIPLY", seam, 0.45),
                                                                                     horn.math("MULTIPLY", groove, 0.4)))),
                                    0.0), 0.38)
    mats = [gape_mat, horn_mat]
    upper = bc.mesh_object("BeakLong", verts, faces, mats, face_mat)
    lower = bc.mesh_object("BeakLongLower", lverts, lfaces, mats, lface_mat, parent=upper)
    gape_mat.name, horn_mat.name = "M_BeakLongGape", "M_BeakLongHorn"
    baked = _bake_parts([upper, lower], "PartBeakLong", {"M_BeakLongGape": sf.tint(cp._lin("#C98A7A")),
                                                         "M_BeakLongHorn": sf.tint(cp._lin("#E0893A"))})
    pts = cp._check_pivot("beak_long", LONG_SINK)
    foot = cp._footprint(pts, z_max=0.005)
    mp._check(path[-1].y < -0.03, "beak_long: the bill is decurved (tip y %.3f)" % path[-1].y)

    skin = next(i for i, p in enumerate(path) if p.z >= 0.0)
    long_path = _mp_arc((0.0, 0.0, -LONG_SINK), _long_heading, LONG_LEN, steps,
                        stretch=lambda k: 1.35 if k >= skin + 2 else 1.0)
    curve_path = _mp_arc((0.0, 0.0, -LONG_SINK), lambda u: _long_heading(u, 0.55), LONG_LEN, steps)
    length = _mp_follow(path, long_path)
    curve = _mp_follow(path, curve_path)
    hinge = Vector((0.0, -0.004, 0.004))

    def open_lower(co):
        return _mp_bend(co, hinge, math.radians(16.0) * _mp_smooth(co.z, -0.004, 0.02))

    handles = cp._shape_keys(upper, [("H1_Length", length, "the bill 35% longer above the skin"),
                                     ("H2_Curve", curve, "the decurve about 30 degrees deeper at the tip"),
                                     ("H3_Open", lambda co: co, "the lower mandible dropped 16 degrees at the gape")])
    cp._shape_keys(lower, [("H1_Length", length, ""), ("H2_Curve", curve, ""), ("H3_Open", open_lower, "")])
    rules = _rules("beak_long", round(foot + 0.001, 3), LONG_SINK, "forward_cone", ["spine"], 40, 30,
                   centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = ("All three keys are on BeakLong and BeakLongLower with the same names; the runtime sets "
                             "them together. H3_Open moves only the lower mandible.")
    return {"purpose": "Creature mouth part (PROPOSED): a long slender decurved probing bill with a nostril groove "
                       "and a rounded tip, on a fleshy gape; lengthens, curves and opens on shape keys.",
            "category": "part", "part_type": "beak_long", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_BeakLongGape": 0.8, "M_BeakLongHorn": 0.1}, "revision": 1,
            **baked}


# --- Batch B: trunks (mouth) --------------------------------------------------------------------------------------


def _mp_frame_matrix(t, s):
    """bc.revolve's axis (+Y) onto the tangent t, its x onto the in-plane normal s, its z across (+X)."""
    return Matrix((s, t, s.cross(t))).transposed()


def _mp_ellipsoid(centre, t, s, radii, sub=2):
    """An ellipsoid with radii (along t, along s, across) about centre, as verts and faces."""
    unit, faces = bc.icosphere(sub)
    x = s.cross(t)
    return [tuple(centre + t * (v[1] * radii[0]) + s * (v[0] * radii[1]) + x * (v[2] * radii[2])) for v in unit], faces


def _mp_tip_disc(tip, t, s, r_end, flare=1.04, sides=22, aspect=1.0, dome=0.0):
    """A closed cap for a tube's open end: its rim rolls just past the end ring (flare x its radius) and its face
    dishes in toward a shallow centre, like the pad of a trunk (dome > 0 swells it out instead, a rounded nose).
    `aspect` squeezes it along s, to match a tube that is broader than deep (r_end is then the broad radius)."""
    profile = [(-0.010, 0.0), (-0.009, 0.92 * r_end), (-0.001, 0.98 * r_end), (0.0025, flare * r_end),
               (0.0042 + 0.3 * dome, 0.86 * r_end), (0.0025 + 0.75 * dome, 0.6 * r_end),
               (0.0005 + 0.95 * dome, 0.32 * r_end), (-0.001 + dome, 0.0)]
    pv, pf, _ = bc.revolve(profile, sides)
    frame = _mp_frame_matrix(t, s)
    return [tuple(tip + frame @ Vector((v[0] * aspect, v[1], v[2]))) for v in pv], pf


def _mp_append(verts, faces, more_verts, more_faces):
    off = len(verts)
    verts.extend(more_verts)
    faces.extend(tuple(k + off for k in f) for f in more_faces)


TRUNK_SINK = 0.03
TRUNK_LEN = 0.41       # the centreline from the root cap to the tip (about 0.38 m of it above the skin)
TRUNK_R0, TRUNK_R1 = 0.045, 0.018


def _trunk_heading(u, curl=0.0, lift=0.0):
    # Out of the face, bending down to hang nearly straight, the last quarter turning forward toward the grip;
    # H1_Curl and H2_Raise add to it.
    return (1.5 * _mp_smooth(u, 0.05, 0.7) - 0.45 * _mp_smooth(u, 0.75, 1.0)
            + curl * _mp_smooth(u, 0.35, 1.0) ** 1.3 - lift * _mp_smooth(u, 0.1, 0.9))


def build_trunk():
    """An elephant's trunk: thick at the face and tapering over about 0.38 m, hanging down and turning forward at
    the end, wrinkled in rings (deeper on the upper side) and flatter underneath, ending in a dished grip pad with
    two nostrils and two finger-like lips above and below (the TrunkTip child). Prehensile (part_rules
    capabilities ["grasper"]). H1_Curl coils the outer half under, H2_Raise lifts it forward and up, H3_Length
    draws it out."""
    steps, sides = 140, 22
    start = (0.0, 0.0, -TRUNK_SINK)
    path = _mp_arc(start, _trunk_heading, TRUNK_LEN, steps)
    ds = TRUNK_LEN / steps
    phase, ph = [], 0.0
    for i in range(steps + 1):
        phase.append(ph)
        ph += 2.0 * math.pi * ds / (0.012 - 0.005 * i / steps)       # the wrinkles crowd toward the tip

    def radius(i, a):
        u = i / steps
        r = TRUNK_R1 + (TRUNK_R0 - TRUNK_R1) * (1.0 - u) ** 1.15 + 0.008 * (1.0 - _mp_smooth(u, 0.0, 0.12))
        c = math.cos(a)
        r *= 1.0 - 0.1 * max(0.0, -c) ** 2                                       # flatter underneath
        ring = (0.5 + 0.5 * math.cos(phase[i])) ** 0.6                           # broad folds, narrow creases
        amp = min(0.0008, 0.022 * r) * (0.5 + 0.5 * max(0.0, c))
        amp *= _mp_smooth(u, 0.1, 0.16) * (1.0 - _mp_smooth(u, 0.94, 0.99))
        return r + amp * (2.0 * ring - 1.0)

    verts, faces, _ = cp._tube(path, radius, sides)
    frames = _mp_frames(path)
    t_end, s_end = frames[-1]
    tip, r_end = path[-1], radius(steps, 0.5 * math.pi)
    tverts, tfaces = _mp_tip_disc(tip, t_end, s_end, r_end, sides=sides)
    # The two "fingers": a larger one on the upper (outer) side, a smaller one below, half sunk in the rim.
    for side, along, radii in ((1.0, 0.0075, (0.013, 0.0065, 0.010)), (-1.0, 0.0045, (0.009, 0.0055, 0.009))):
        _mp_append(tverts, tfaces, *_mp_ellipsoid(tip + t_end * along + s_end * (side * 0.78 * r_end), t_end, s_end,
                                                  radii))
    x_end = s_end.cross(t_end)

    skin = sf.Shader("M_TrunkSkinProc")
    crackle = skin.remap(skin.voronoi(170.0, 0.9, feature="DISTANCE_TO_EDGE"), 0.0, 0.06)
    grain = skin.noise(320.0, 3.0)
    skin.bump(skin.math("ADD", skin.math("MULTIPLY", crackle, 0.7), skin.math("MULTIPLY", grain, 0.3)), 0.35, 0.0008)
    skin_mat = skin.out(_grey(skin, skin.math("ADD", skin.math("MULTIPLY", crackle, 0.45),
                                              skin.remap(grain, 0.3, 0.7, 0.0, 0.55)), 0.62), 0.78)
    pad = sf.Shader("M_TrunkTipProc")
    holes = None
    for k in (-1.0, 1.0):
        centre = tip + t_end * 0.002 + x_end * (k * 0.36 * r_end)
        d = pad.remap(pad.vmath("LENGTH", pad.vmath("SUBTRACT", pad.pos, tuple(centre))), 0.0055, 0.0032)
        holes = d if holes is None else pad.math("MAXIMUM", holes, d)
    pebble = pad.remap(pad.voronoi(520.0, 0.9), 0.3, 0.05)
    pad.bump(pad.math("SUBTRACT", pad.math("MULTIPLY", pebble, -0.3), pad.math("MULTIPLY", holes, 1.2)), 0.35, 0.0008)
    pad_mat = pad.out(_grey(pad, pad.math("SUBTRACT", pad.math("SUBTRACT", 1.0, pad.math("MULTIPLY", pebble, 0.2)),
                                          pad.math("MULTIPLY", holes, 0.85)), 0.08), 0.4)
    trunk = bc.mesh_object("Trunk", verts, faces, [skin_mat])
    tip_obj = bc.mesh_object("TrunkTip", tverts, tfaces, [pad_mat], parent=trunk)
    skin_mat.name, pad_mat.name = "M_TrunkSkin", "M_TrunkTip"
    baked = _bake_parts([trunk, tip_obj], "PartTrunk", {"M_TrunkSkin": sf.tint(cp._lin("#8E8A9A")),
                                                        "M_TrunkTip": sf.tint(cp._lin("#705E54"))})
    pts = cp._check_pivot("trunk", TRUNK_SINK)
    foot = cp._footprint(pts, z_max=0.005)
    mp._check(tip.y < -0.2 and t_end.z > 0.3, "trunk: hangs down and turns forward at the tip (tip y %.3f)" % tip.y)

    skin_i = next(i for i, p in enumerate(path) if p.z >= 0.0)
    curl_path = _mp_arc(start, lambda u: _trunk_heading(u, curl=1.7), TRUNK_LEN, steps)
    raise_path = _mp_arc(start, lambda u: _trunk_heading(u, lift=1.5), TRUNK_LEN, steps)
    long_path = _mp_arc(start, _trunk_heading, TRUNK_LEN, steps, stretch=lambda k: 1.3 if k >= skin_i + 3 else 1.0)
    keys = (("H1_Curl", curl_path, "the outer half coiled about 100 degrees further under, to grip"),
            ("H2_Raise", raise_path, "the trunk lifted forward and up, its tip turned skyward"),
            ("H3_Length", long_path, "the trunk 30% longer past the face"))
    handles = cp._shape_keys(trunk, [(k, _mp_follow(path, p), meaning) for k, p, meaning in keys])
    cp._shape_keys(tip_obj, [(k, _mp_follow(path, p, fixed=steps), "") for k, p, _ in keys])
    rules = _rules("trunk", round(foot + 0.001, 3), TRUNK_SINK, "forward_cone", ["spine"], 40, 30,
                   centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = ("All three keys are on Trunk and TrunkTip with the same names; the runtime sets them "
                             "together. The grip pad and its fingers move rigidly with the trunk's end.")
    return {"purpose": "Creature mouth part (PROPOSED): a prehensile elephant-like trunk, ring-wrinkled and tapering, "
                       "hanging and turning forward to a two-fingered grip pad with nostrils; curls, lifts and "
                       "lengthens on shape keys.",
            "category": "part", "part_type": "trunk", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_TrunkSkin": 0.9, "M_TrunkTip": 0.5}, "revision": 1, **baked}


SHORT_SINK = 0.025
SHORT_LEN = 0.135      # the snout's centreline from the root cap (about 0.11 m of it above the skin)
SHORT_DEEP, SHORT_BROAD = 0.9, 1.12     # the snout's section: its depth and breadth against a round tube


def _short_heading(u, curl=0.0):
    # Out over the mouth, drooping toward the tip; H1_Curl turns the end further down over the lip.
    return 0.8 * _mp_smooth(u, 0.3, 1.0) ** 1.2 + curl * _mp_smooth(u, 0.25, 1.0) ** 1.2


def build_trunk_short():
    """A tapir's short mobile snout: a broad, slightly flattened tube drooping over a small mouth, softly folded
    across its middle, ending in a dark nose pad with two flared nostrils (the TrunkShortNose child). The lower
    lip (the TrunkShortLip child) sits under its root, so the snout overhangs the mouth. H1_Curl turns the snout
    down over the lip, H2_Length draws it out."""
    steps, sides = 36, 20
    start = (0.0, 0.008, -SHORT_SINK)
    path = _mp_arc(start, _short_heading, SHORT_LEN, steps)

    def radius(i, a):
        u = i / steps
        r = 0.031 * (1.0 - 0.42 * u) + 0.007 * (1.0 - _mp_smooth(u, 0.0, 0.3))
        c, s_ = math.cos(a), math.sin(a)
        r /= math.sqrt((c / SHORT_DEEP) ** 2 + (s_ / SHORT_BROAD) ** 2)            # broader than deep
        fold = (0.5 + 0.5 * math.cos(2.0 * math.pi * u / 0.11)) ** 0.7 * _mp_smooth(u, 0.28, 0.36)
        fold *= 1.0 - _mp_smooth(u, 0.72, 0.8)
        return r - 0.0012 * fold * (0.4 + 0.6 * max(0.0, c))

    verts, faces, _ = cp._tube(path, radius, sides)
    t_end, s_end = _mp_frames(path)[-1]
    tip, r_end = path[-1], radius(steps, 0.5 * math.pi)
    nverts, nfaces = _mp_tip_disc(tip, t_end, s_end, r_end, flare=1.03, sides=sides, aspect=SHORT_DEEP / SHORT_BROAD,
                                  dome=0.011)
    x_end = s_end.cross(t_end)
    nostrils = []
    for k in (-1.0, 1.0):                           # each nostril a flared lobe on the domed pad, opening forward
        c = tip + t_end * 0.0105 + x_end * (k * 0.42 * r_end) + s_end * (0.1 * r_end)
        nostrils.append(c + t_end * 0.0035)
        _mp_append(nverts, nfaces, *_mp_ellipsoid(c, t_end, s_end, (0.0045, 0.0075, 0.0068)))
    # The lower lip: a broad soft chin under the snout's root, its top tucked against the snout's underside so the
    # mouth is a crease between them.
    lip_v, lip_f = _mp_ellipsoid(Vector((0.0, -0.029, 0.006)), Vector((0.0, 0.0, 1.0)), Vector((0.0, 1.0, 0.0)),
                                 (0.024, 0.014, 0.03), sub=3)

    skin = sf.Shader("M_TrunkShortSkinProc")
    grain = skin.noise(520.0, 3.0)
    pores = skin.remap(skin.voronoi(420.0, 0.8), 0.2, 0.04)
    skin.bump(skin.math("SUBTRACT", grain, skin.math("MULTIPLY", pores, 0.5)), 0.18, 0.0005)
    # The mouth's line between the lip and the snout's underside, shaded dark.
    seam = skin.math("MULTIPLY", skin.remap(skin.math("ABSOLUTE", skin.math("ADD", skin.axis("Y"), 0.016)), 0.004, 0.001),
                     skin.math("MULTIPLY", skin.remap(skin.axis("Z"), 0.032, 0.022),
                               skin.remap(skin.math("ABSOLUTE", skin.axis("X")), 0.026, 0.018)))
    skin_mat = skin.out(_grey(skin, skin.math("SUBTRACT", skin.remap(grain, 0.3, 0.7, 0.85, 1.0),
                                              skin.math("MULTIPLY", seam, 0.7)), 0.15), 0.7)
    nose = sf.Shader("M_TrunkShortNoseProc")
    holes = None
    for c in nostrils:
        d = nose.remap(nose.vmath("LENGTH", nose.vmath("MULTIPLY", nose.vmath("SUBTRACT", nose.pos, tuple(c)),
                                                       (1.6, 0.6, 1.0))), 0.0042, 0.0022)
        holes = d if holes is None else nose.math("MAXIMUM", holes, d)
    pebble = nose.remap(nose.voronoi(700.0, 0.9), 0.3, 0.05)
    nose.bump(nose.math("SUBTRACT", nose.math("MULTIPLY", pebble, -0.3), nose.math("MULTIPLY", holes, 1.2)), 0.35,
              0.0006)
    nose_mat = nose.out(_grey(nose, nose.math("SUBTRACT", nose.math("SUBTRACT", 1.0, nose.math("MULTIPLY", pebble, 0.2)),
                                              nose.math("MULTIPLY", holes, 0.9)), 0.05), 0.3)
    snout = bc.mesh_object("TrunkShort", verts, faces, [skin_mat])
    nose_obj = bc.mesh_object("TrunkShortNose", nverts, nfaces, [nose_mat], parent=snout)
    lip = bc.mesh_object("TrunkShortLip", lip_v, lip_f, [skin_mat], parent=snout)
    skin_mat.name, nose_mat.name = "M_TrunkShortSkin", "M_TrunkShortNose"
    baked = _bake_parts([snout, nose_obj, lip], "PartTrunkShort", {"M_TrunkShortSkin": sf.tint(cp._lin("#6E6878")),
                                                                    "M_TrunkShortNose": sf.tint(cp._lin("#3C3438"))},
                        keep=("TrunkShortNose",))         # kept whole: the small pad and nostril lobes stay clean
    pts = cp._check_pivot("trunk_short", SHORT_SINK)
    foot = cp._footprint(pts, z_max=0.005)
    mp._check(tip.z > 0.09 and tip.y < -0.005, "trunk_short: overhangs the mouth and droops (tip %.3f, %.3f)"
              % (tip.y, tip.z))

    skin_i = next(i for i, p in enumerate(path) if p.z >= 0.0)
    curl_path = _mp_arc(start, lambda u: _short_heading(u, curl=0.9), SHORT_LEN, steps)
    long_path = _mp_arc(start, _short_heading, SHORT_LEN, steps, stretch=lambda k: 1.35 if k >= skin_i + 2 else 1.0)
    keys = (("H1_Curl", curl_path, "the snout's end turned about 50 degrees further down over the lip"),
            ("H2_Length", long_path, "the snout 35% longer past the face"))
    handles = cp._shape_keys(snout, [(k, _mp_follow(path, p), meaning) for k, p, meaning in keys])
    cp._shape_keys(nose_obj, [(k, _mp_follow(path, p, fixed=steps), "") for k, p, _ in keys])
    rules = _rules("trunk_short", round(foot + 0.001, 3), SHORT_SINK, "forward_cone", ["spine"], 40, 30,
                   centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = ("Both keys are on TrunkShort and TrunkShortNose with the same names; the runtime sets "
                             "them together. The nose pad moves rigidly with the snout's end; the lip "
                             "(TrunkShortLip) has no keys and stays put.")
    return {"purpose": "Creature mouth part (PROPOSED): a tapir-like short mobile snout overhanging a small mouth, "
                       "with a dark nose pad and flared nostrils; curls and lengthens on shape keys.",
            "category": "part", "part_type": "trunk_short", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_TrunkShortSkin": 0.9, "M_TrunkShortNose": 0.4}, "revision": 1,
            **baked}


# --- Batch C: mouths (mouth_sucker, mouth_fangs) -------------------------------------------------------------------


def _mp_lathe(stations, at, segs):
    """A surface of revolution about +Z whose station i at angle a is at(i, a) -> (r, z) (so the profile can ripple
    with the angle, like a frill). Rings run counterclockwise seen from +Z; with stations going up the outside and
    down the inside, every face points out of the material. A station whose r is 0 is a pole (at either end). Returns verts, faces
    and each face's station index (the lower-numbered of its two rings)."""
    verts, faces, rings, face_station = [], [], [], []
    for i in range(stations):
        r0, z0 = at(i, 0.0)
        if r0 <= 0.0:
            rings.append([len(verts)])
            verts.append((0.0, 0.0, z0))
            continue
        ring = []
        for j in range(segs):
            a = 2.0 * math.pi * j / segs
            r, z = at(i, a)
            ring.append(len(verts))
            verts.append((r * math.cos(a), r * math.sin(a), z))
        rings.append(ring)
    for i in range(stations - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(segs):
            k = (j + 1) % segs
            if len(a) == 1:
                faces.append((a[0], b[k], b[j]))
            else:
                faces.append((a[j], a[k], b[0]) if len(b) == 1 else (a[j], a[k], b[k], b[j]))
            face_station.append(i)
    return verts, faces, face_station


def _mp_spike(path, half_w, half_t, sides, hint=None):
    """An open-rooted tapering spike along `path` (no cap: its root is buried): station i is an ellipse of half-width
    half_w[i] across (perpendicular to the path and to `hint`) and half-thickness half_t[i] along the remaining axis;
    a half-width of 0 closes it to a point. The frame is parallel-transported, so a curving path does not twist it.
    Faces wind inward like cp._tube's; mesh_object's fix_normals turns them out."""
    verts, faces, rings = [], [], []
    n = len(path)
    t0 = (path[1] - path[0]).normalized()
    hint = Vector(hint) if hint is not None else (Vector((0.0, 0.0, 1.0)) if abs(t0.z) < 0.9 else Vector((1.0, 0.0, 0.0)))
    side = t0.cross(hint).normalized()
    for i, p in enumerate(path):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        side = (side - t * side.dot(t)).normalized() if i else side
        up = side.cross(t).normalized()
        if half_w[i] <= 0.0:
            rings.append([len(verts)])
            verts.append(tuple(p))
            continue
        ring = []
        for j in range(sides):
            a = 2.0 * math.pi * j / sides
            ring.append(len(verts))
            verts.append(tuple(p + side * (half_w[i] * math.cos(a)) + up * (half_t[i] * math.sin(a))))
        rings.append(ring)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((a[j], a[k], b[0]) if len(b) == 1 else (a[j], a[k], b[k], b[j]))
    return verts, faces


SUCKER_SINK = 0.03
# The sucker's profile as (r, z): up the funnel's outside from under the skin, over the fleshy bead of the lip and a
# short tuck under it (stations 0 to SUCKER_DISC - 1, the MouthSucker mesh); then, from just inside the bead, down
# across the toothed oral disc and into the throat (the MouthSuckerDisc mesh). The two meshes overlap under the bead,
# so each is decimated with one material and the border between them stays a clean line.
SUCKER_PROFILE = ((0.0290, -0.0285), (0.0310, -0.0120), (0.0325, 0.0), (0.0318, 0.0100), (0.0328, 0.0200),
                  (0.0360, 0.0300), (0.0415, 0.0380), (0.0470, 0.0440),
                  (0.0517, 0.0480), (0.0547, 0.0510), (0.0545, 0.0550), (0.0510, 0.0575), (0.0468, 0.0565),
                  (0.0450, 0.0528), (0.0440, 0.0488), (0.0436, 0.0455),
                  (0.0447, 0.0502), (0.0405, 0.0472), (0.0365, 0.0448), (0.0300, 0.0410), (0.0240, 0.0373),
                  (0.0182, 0.0335), (0.0134, 0.0292), (0.0100, 0.0225), (0.0083, 0.0120), (0.0062, 0.0010),
                  (0.0034, -0.0110), (0.0, -0.0150))
SUCKER_DISC = 16         # the first station of the disc; stations 8 to 13 are the lip's bead
SUCKER_FRILL = {6: 0.2, 7: 0.55, 8: 0.9, 9: 1.0, 10: 1.0, 11: 0.9, 12: 0.6, 13: 0.3, 14: 0.3, 15: 0.3, 16: 0.3,
                17: 0.12}    # station -> how much it ruffles
SUCKER_LOBES = 10
SUCKER_SEGS = 60
SUCKER_TEETH = ((0.0368, 16, 0.0080, 0.0027), (0.0278, 12, 0.0090, 0.0030), (0.0196, 8, 0.0102, 0.0033))   # r, count, length, root radius


def _sucker_at(i, a):
    # Rounded scallops with narrow notches between them, each lobe lifting a little as it bulges out.
    r, z = SUCKER_PROFILE[i]
    w = SUCKER_FRILL.get(i, 0.0)
    lobe = (0.5 + 0.5 * math.cos(SUCKER_LOBES * a)) ** 0.6 - 0.62
    return r * (1.0 + 0.085 * w * lobe), z + 0.004 * w * lobe


def _sucker_station(co):
    """The profile parameter s (a float station index) of the point nearest co, at co's own angle."""
    a = math.atan2(co.y, co.x)
    q = (math.hypot(co.x, co.y), co.z)
    best, best_s = None, 0.0
    for i in range(len(SUCKER_PROFILE) - 1):
        p0, p1 = _sucker_at(i, a), _sucker_at(i + 1, a)
        dx, dz = p1[0] - p0[0], p1[1] - p0[1]
        L2 = dx * dx + dz * dz
        t = 0.0 if L2 == 0.0 else min(1.0, max(0.0, ((q[0] - p0[0]) * dx + (q[1] - p0[1]) * dz) / L2))
        d = (q[0] - p0[0] - t * dx) ** 2 + (q[1] - p0[1] - t * dz) ** 2
        if best is None or d < best:
            best, best_s = d, i + t
    return best_s


def _sucker_gape(s):
    # The disc and throat open: nothing at the rim, 30% wider at the inner tooth ring, 70% at the throat.
    return 0.3 * _mp_smooth(s, 16.5, 20.5) + 0.4 * _mp_smooth(s, 20.5, 23.0)


def _sucker_flare(s):
    # The funnel's upper part, the rim and the disc's outer half spread out and settle a little lower.
    return _mp_smooth(s, 3.0, 8.0) * (1.0 - _mp_smooth(s, 16.5, 20.0))


def _sucker_move(co, handle, s=None):
    s = _sucker_station(co) if s is None else s
    r = math.hypot(co.x, co.y)
    if r < 1e-9:
        return co.copy()
    if handle == "H1_Gape":
        k = _sucker_gape(s)
        return Vector((co.x * (1.0 + k), co.y * (1.0 + k), co.z))
    f = _sucker_flare(s)
    k = (r + 0.012 * f) / r
    return Vector((co.x * k, co.y * k, co.z - 0.007 * f))


def build_mouth_sucker():
    """A lamprey's oral disc: a short trumpet-shaped funnel standing about 5.5 cm off the skin, flaring to a fleshy
    bead of lip scalloped into ten soft ruffled lobes about 11 cm across; inside it a dished disc (MouthSuckerDisc)
    set with three concentric rings of small amber teeth (16, 12 and 8) hooking in toward a dark round throat. It
    reads apart from the maw (a flat ring of rolled lips with fourteen long fangs) by its standing funnel, its
    scalloped rim and its many small teeth. H1_Gape opens the disc and throat, H2_Flare spreads the rim wide and
    flat to latch on."""
    stations = len(SUCKER_PROFILE)
    verts, faces, _ = _mp_lathe(SUCKER_DISC, _sucker_at, SUCKER_SEGS)
    dverts, dfaces, _ = _mp_lathe(stations - SUCKER_DISC, lambda i, a: _sucker_at(SUCKER_DISC + i, a), SUCKER_SEGS)

    # The teeth: hooked cones rooted on the disc, leaning in toward the throat; each ring offset from the next.
    def disc_point(r_root):
        for i in range(SUCKER_DISC, stations - 1):
            (ra, za), (rb, zb) = SUCKER_PROFILE[i], SUCKER_PROFILE[i + 1]
            if rb <= r_root <= ra:
                t = (ra - r_root) / (ra - rb)
                n = Vector((zb - za, -(rb - ra))).normalized()      # (r, z) normal facing the opening (in and up)
                return za + t * (zb - za), n, i + t
        raise ValueError(r_root)

    tverts, tfaces, roots = [], [], []
    for k, (r_root, count, length, r0) in enumerate(SUCKER_TEETH):
        z_root, n_rz, s_root = disc_point(r_root)
        for m in range(count):
            a = 2.0 * math.pi * (m + 0.5 * (k % 2)) / count
            radial = Vector((math.cos(a), math.sin(a), 0.0))
            normal = (radial * n_rz.x + Vector((0.0, 0.0, n_rz.y))).normalized()
            root = radial * r_root + Vector((0.0, 0.0, z_root))
            path = [root - normal * 0.0014, root + normal * (0.5 * length) - radial * (0.12 * length),
                    root + normal * (0.86 * length) - radial * (0.52 * length)]
            v, f = _mp_spike(path, (r0, 0.62 * r0, 0.0), (r0, 0.62 * r0, 0.0), 5)
            _mp_append(tverts, tfaces, v, f)
            roots.append((root, s_root))
    mp._check(min(SUCKER_TEETH[0][0] - SUCKER_TEETH[1][0], SUCKER_TEETH[1][0] - SUCKER_TEETH[2][0]) > 0.007,
              "mouth_sucker: the tooth rings are distinct")

    lip = sf.Shader("M_SuckerLipProc")
    wrinkle = lip.noise(120.0, 2.0, vector=mp._stretched(lip, (1.0, 1.0, 6.0)))     # rings round the funnel
    papillae = lip.remap(lip.voronoi(320.0, 0.7), 0.3, 0.06)                     # small round bumps
    grain = lip.noise(420.0, 3.0)
    lip.bump(lip.math("ADD", lip.math("MULTIPLY", papillae, 0.55),
                      lip.math("ADD", lip.math("MULTIPLY", wrinkle, 0.3), lip.math("MULTIPLY", grain, 0.15))), 0.35, 0.0008)
    lip_mat = lip.out(_grey(lip, lip.math("ADD", lip.remap(wrinkle, 0.3, 0.7, 0.7, 0.95),
                                          lip.math("MULTIPLY", papillae, 0.08)), 0.55), 0.36)
    throat = sf.Shader("M_SuckerThroatProc")
    radial_r = throat.vmath("LENGTH", throat.vmath("MULTIPLY", throat.pos, (1.0, 1.0, 0.0)))
    deep = throat.remap(radial_r, 0.007, 0.03)                                       # near black down the throat
    folds = throat.noise(160.0, 2.0)
    throat.bump(folds, 0.3, 0.0006)
    throat_mat = throat.out(_grey(throat, throat.math("MULTIPLY", deep, throat.remap(folds, 0.3, 0.7, 0.75, 1.0)), 0.04),
                            0.3)
    tooth = sf.Shader("M_SuckerToothProc")
    streak = tooth.noise(220.0, 3.0, vector=mp._stretched(tooth, (4.0, 4.0, 0.4)))
    tooth.bump(streak, 0.12, 0.0004)
    tooth_mat = tooth.out(_grey(tooth, tooth.remap(streak, 0.2, 0.8, 0.82, 1.0), 0.8), 0.25)
    body = bc.mesh_object("MouthSucker", verts, faces, [lip_mat], fix_normals=False)
    disc = bc.mesh_object("MouthSuckerDisc", dverts, dfaces, [throat_mat], parent=body, fix_normals=False)
    teeth = bc.mesh_object("MouthSuckerTeeth", tverts, tfaces, [tooth_mat], parent=body)
    lip_mat.name, throat_mat.name, tooth_mat.name = "M_SuckerLip", "M_SuckerThroat", "M_SuckerTooth"
    baked = _bake_parts([body, disc, teeth], "PartMouthSucker", {"M_SuckerLip": sf.tint(cp._lin("#6E8C86")),
                                                          "M_SuckerThroat": sf.tint(cp._lin("#5E4A5C")),
                                                          "M_SuckerTooth": sf.tint(cp._lin("#EDC27C"))},
                        keep=("MouthSuckerTeeth",))       # the small teeth stay whole
    pts = cp._check_pivot("mouth_sucker", SUCKER_SINK)
    foot = cp._footprint(pts, z_max=0.005)
    top = max(p.z for p in pts)
    mp._check(0.045 < top < 0.065, "mouth_sucker: stands about 5 cm off the skin (top %.3f)" % top)

    def nearest_root(co):
        return min(roots, key=lambda rs: (rs[0] - co).length_squared)

    def body_key(name):
        return lambda co: _sucker_move(co, name)

    def teeth_key(name):
        def move(co):
            root, s_root = nearest_root(co)
            return co + (_sucker_move(root, name, s_root) - root)
        return move

    keys = (("H1_Gape", "the disc and throat open, the throat about 70% wider and the teeth riding out with it"),
            ("H2_Flare", "the rim spread about 1.2 cm wider and flatter, as when it latches on"))
    handles = cp._shape_keys(body, [(k, body_key(k), meaning) for k, meaning in keys])
    cp._shape_keys(disc, [(k, body_key(k), "") for k, _ in keys])
    cp._shape_keys(teeth, [(k, teeth_key(k), "") for k, _ in keys])
    rules = _rules("mouth_sucker", round(foot + 0.001, 3), SUCKER_SINK, "forward_cone", ["spine"], 40, 30,
                   centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = ("Both keys are on MouthSucker, MouthSuckerDisc and MouthSuckerTeeth with the same names; the "
                             "runtime sets them together. Each tooth rides rigidly with the point of the disc it is "
                             "rooted on.")
    return {"purpose": "Creature mouth part (PROPOSED): a lamprey-like oral disc on a short funnel, with a frilled lip "
                       "and three rings of small hooked teeth round a dark throat; gapes and flares on shape keys.",
            "category": "part", "part_type": "mouth_sucker", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_SuckerLip": 0.85, "M_SuckerTooth": 0.0, "M_SuckerThroat": 0.0},
            "revision": 1, **baked}


FANGS_SINK = 0.025
FANGS_HINGE = Vector((0.0, -0.006, -0.02))      # the lower jaw's hinge axis (along X), at the back of the mouth
FANGS_UPPER_HINGE = Vector((0.0, 0.0, -0.02))
FANGS_REST_DROP = math.radians(6.0)             # the mouth rests a little open, so the tongue and fangs show
FANGS_ROOTS = (Vector((0.021, -0.0005, 0.042)), Vector((-0.021, -0.0005, 0.042)))
FANGS_LEN = 0.042


def _fangs_jaw(rx, rz, z0, y0, y_top, y_bottom, top_stations, bottom_stations, front_slope=0.0, segs=28):
    """A jaw as a lathed dome: round in plan (an ellipse of half-width rx and half-length rz, centred at z0), domed
    up to y0 + y_top and down to y0 - y_bottom (a small y_top or y_bottom flattens that side into a palate or a
    mouth floor). The rings crowd toward the lip edge, where the two sides meet, so it stays round at the mouth
    line with few triangles. front_slope lowers the top toward the front, like a snake's snout. Returns verts,
    faces and each face's station (stations before len(top_stations) - 1 are the outer side)."""
    prof = [(rho, y_top * math.sqrt(max(0.0, 1.0 - rho * rho)) ** 0.9) for rho in top_stations]
    prof += [(rho, -y_bottom * math.sqrt(max(0.0, 1.0 - rho * rho))) for rho in bottom_stations]
    lv, faces, station = _mp_lathe(len(prof), lambda i, a: prof[i], segs)
    verts = []
    for x, y, z in lv:
        up = z * (1.0 - front_slope * 0.5 * (1.0 + y)) if z > 0.0 else z
        verts.append(Vector((rx * x, y0 + up, z0 + rz * y)))
    return verts, faces, station


def _rot_x(co, pivot, angle):
    return pivot + Matrix.Rotation(angle, 3, "X") @ (co - pivot)


def _fang_heading(u):
    # From the radians off -Y toward -Z: leaning a little forward at the root, curving back toward the tip.
    return -0.22 + 1.0 * u ** 1.3


def build_mouth_fangs():
    """A snake's mouth: a short, wide, low snout of scaly lips (about 13 cm across and 6 cm deep, with large pale
    lip plates along the mouth line) resting a little open over a shorter lower jaw, with two long ivory fangs
    hanging from the front of the upper jaw in front of the chin and curving back, and a dark forked tongue poking
    out between the lips. H1_Open drops the lower jaw and swings the fangs forward to strike; H2_Tongue flicks the
    tongue out and spreads its fork."""
    clamp = -FANGS_SINK + 0.0012

    def sink(v):
        return Vector((v.x, v.y, max(clamp, v.z)))

    top = (0.0, 0.35, 0.6, 0.78, 0.89, 0.95, 0.985, 1.0)
    under = (0.985, 0.94, 0.8, 0.5, 0.0)
    uv, uf, ust = _fangs_jaw(0.066, 0.064, -0.012, 0.0, 0.03, 0.0075, top, under, front_slope=0.3)
    upper_v = [tuple(sink(v)) for v in uv]
    upper_m = [1 if st >= len(top) + 1 else 0 for st in ust]       # the palate, inside the lip's edge
    lv, lf, lst = _fangs_jaw(0.058, 0.05, -0.014, -0.009, 0.004, 0.021, (0.0, 0.5, 0.8, 0.94, 0.985, 1.0),
                             (0.985, 0.94, 0.85, 0.65, 0.35, 0.0))
    lower_v = [tuple(sink(_rot_x(v, FANGS_HINGE, FANGS_REST_DROP))) for v in lv]
    lower_m = [1 if st < 3 else 0 for st in lst]                   # the mouth floor, inside the lip's edge

    fverts, ffaces, tips = [], [], []
    steps = 8
    for root in FANGS_ROOTS:
        path, p = [], root.copy()
        for k in range(steps):
            path.append(p.copy())
            th = _fang_heading((k + 0.5) / steps)
            p = p + Vector((0.0, -math.cos(th), -math.sin(th))) * (FANGS_LEN / steps)
        path.append(p.copy())
        tips.append(p.copy())
        r = [0.0052 * (1.0 - k / steps) ** 0.85 for k in range(steps + 1)]
        v, f = _mp_spike(path, r, [0.9 * x for x in r], 6, hint=(1.0, 0.0, 0.0))
        _mp_append(fverts, ffaces, v, f)

    # The tongue, authored on the closed jaw's mouth floor and dropped with it: a flat ribbon running forward out
    # between the lips, then two tines that part and lift a little.
    tverts, tfaces = [], []
    zs = [-0.004 + 0.068 * k / 8 for k in range(9)]
    path = [Vector((0.0, -0.0036 + 0.0012 * _mp_smooth(z, 0.04, 0.064), z)) for z in zs]
    half_w = [0.0044 - 0.0012 * k / 8 for k in range(8)] + [0.0]
    v, f = _mp_spike(path, half_w, [0.0012] * 8 + [0.0], 5, hint=(0.0, -1.0, 0.0))
    _mp_append(tverts, tfaces, v, f)
    fork = path[-2]
    for side in (1.0, -1.0):
        tine = [fork + Vector((side * 0.0012, 0.0, -0.002)), fork + Vector((side * 0.0036, 0.0007, 0.0066)),
                fork + Vector((side * 0.0062, 0.0015, 0.0134)), fork + Vector((side * 0.0086, 0.0024, 0.0196))]
        v, f = _mp_spike(tine, (0.0018, 0.0014, 0.0009, 0.0), (0.0010, 0.0008, 0.0006, 0.0), 4, hint=(0.0, -1.0, 0.0))
        _mp_append(tverts, tfaces, v, f)
    tverts = [tuple(_rot_x(Vector(v), FANGS_HINGE, FANGS_REST_DROP)) for v in tverts]

    # Domed scales with crisp grooves: small ones over the snout, large pale lip plates along the mouth line.
    lip = sf.Shader("M_FangsLipProc")
    line = lip.remap(lip.math("ABSOLUTE", lip.math("ADD", lip.axis("Y"), 0.004)), 0.022, 0.012)   # lips and chin

    def scales(scale, stretch):
        vec = mp._stretched(lip, stretch)
        dome = lip.remap(lip.voronoi(scale, 0.45, vector=vec), 0.55, 0.05)
        groove = lip.remap(lip.voronoi(scale, 0.45, vector=vec, feature="DISTANCE_TO_EDGE"), 0.0, 0.06)
        return lip.math("MULTIPLY", groove, lip.math("ADD", 0.45, lip.math("MULTIPLY", dome, 0.55)))

    small, big = scales(150.0, (1.0, 1.0, 1.0)), scales(62.0, (0.6, 1.5, 1.0))
    height = lip.math("ADD", lip.math("MULTIPLY", small, lip.math("SUBTRACT", 1.0, line)), lip.math("MULTIPLY", big, line))
    lip.bump(height, 0.5, 0.0012)
    # The grey detail only darkens the tint, so the snout's scales sit darker and the lip plates near full tint.
    body_fac = lip.math("ADD", 0.12, lip.math("MULTIPLY", height, 0.3))
    lip_mat = lip.out(_grey(lip, lip.math("ADD", lip.math("MULTIPLY", body_fac, lip.math("SUBTRACT", 1.0, line)),
                                          lip.math("MULTIPLY", lip.math("ADD", 0.82, lip.math("MULTIPLY", height, 0.18)),
                                                   line)), 0.4), 0.42)
    mouth = sf.Shader("M_FangsMouthProc")
    folds = mouth.noise(180.0, 2.0)
    mouth.bump(folds, 0.25, 0.0005)
    mouth_mat = mouth.out(_grey(mouth, mouth.remap(folds, 0.3, 0.7, 0.7, 1.0), 0.45), 0.32)
    fang = sf.Shader("M_FangsFangProc")
    streak = fang.noise(240.0, 3.0, vector=mp._stretched(fang, (4.0, 0.4, 4.0)))
    fang.bump(streak, 0.1, 0.0003)
    fang_mat = fang.out(_grey(fang, fang.remap(streak, 0.2, 0.8, 0.86, 1.0), 0.8), 0.22)
    upper = bc.mesh_object("MouthFangs", upper_v, uf, [lip_mat, mouth_mat], upper_m)
    lower = bc.mesh_object("MouthFangsLower", lower_v, lf, [lip_mat, mouth_mat], lower_m, parent=upper)
    fangs = bc.mesh_object("MouthFangsFangs", fverts, ffaces, [fang_mat], parent=upper)
    tongue = bc.mesh_object("MouthFangsTongue", tverts, tfaces, [mouth_mat], parent=upper)
    lip_mat.name, mouth_mat.name, fang_mat.name = "M_FangsLip", "M_FangsMouth", "M_FangsFang"
    baked = _bake_parts([upper, lower, fangs, tongue], "PartMouthFangs",
                        {"M_FangsLip": sf.tint(cp._lin("#3E8A84")), "M_FangsMouth": sf.tint(cp._lin("#5A3452")),
                         "M_FangsFang": sf.tint(cp._lin("#F2EAD4"))},
                        keep=("MouthFangsFangs", "MouthFangsTongue"))       # the thin fangs and tongue stay whole
    pts = cp._check_pivot("mouth_fangs", FANGS_SINK)
    foot = cp._footprint(pts, z_max=0.005)
    chin = max(Vector(v).z for v in lower_v if Vector(v).y < tips[0].y + 0.01)
    mp._check(tips[0].y < -0.03 and tips[0].z > chin + 0.004,
              "mouth_fangs: the fangs hang below the lip in front of the chin (tip %.3f, %.3f; chin %.3f)"
              % (tips[0].y, tips[0].z, chin))
    tongue_tip = max(v[2] for v in tverts)
    mp._check(tongue_tip > max(v[2] for v in upper_v) + 0.015, "mouth_fangs: the fork shows past the lips (%.3f)"
              % tongue_tip)

    open_drop, upper_lift, swing = math.radians(34.0), math.radians(-5.0), math.radians(-55.0)

    def nearest_root(co):
        return min(FANGS_ROOTS, key=lambda r: (r - co).length_squared)

    def fang_open(co):
        root = nearest_root(co)
        return _rot_x(_rot_x(co, root, swing), FANGS_UPPER_HINGE, upper_lift)

    out = Vector((0.0, -math.sin(FANGS_REST_DROP), math.cos(FANGS_REST_DROP)))

    def tongue_out(co):
        k = _mp_smooth(co.z, 0.004, 0.034)
        fork_k = _mp_smooth(co.z, 0.058, 0.08)
        moved = co + out * (0.04 * k)
        return Vector((moved.x * (1.0 + 0.8 * fork_k), moved.y + 0.004 * fork_k, moved.z))

    handles = cp._shape_keys(lower, [("H1_Open", lambda co: _rot_x(co, FANGS_HINGE, open_drop),
                                      "the lower jaw drops about 34 degrees and the fangs swing forward to strike")])
    cp._shape_keys(upper, [("H1_Open", lambda co: _rot_x(co, FANGS_UPPER_HINGE, upper_lift), "")])
    cp._shape_keys(fangs, [("H1_Open", fang_open, "")])
    handles += cp._shape_keys(tongue, [("H1_Open", lambda co: _rot_x(co, FANGS_HINGE, open_drop), ""),
                                       ("H2_Tongue", tongue_out, "the forked tongue flicked 4 cm further out, its tines "
                                                                 "spread and lifted")])[1:]
    rules = _rules("mouth_fangs", round(foot + 0.001, 3), FANGS_SINK, "forward_cone", ["spine"], 40, 30,
                   centerline="required")
    rules["handles"] = handles
    rules["handles_note"] = ("H1_Open is on all four meshes (MouthFangsLower drops on its hinge, MouthFangs lifts 5 "
                             "degrees, MouthFangsFangs swing forward about 55 degrees from their roots, "
                             "MouthFangsTongue drops with the lower jaw); H2_Tongue is on MouthFangsTongue only.")
    return {"purpose": "Creature mouth part (PROPOSED): a snake-like wide lipped mouth with two long curved front "
                       "fangs and a forked tongue; opens to strike and flicks its tongue on shape keys.",
            "category": "part", "part_type": "mouth_fangs", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_FangsLip": 0.85, "M_FangsFang": 0.0, "M_FangsMouth": 0.0},
            "revision": 1, **baked}


# --- Batch D: eyes (eye_turret, eye_lashed) -----------------------------------------------------------------------
# cp's eye convention (build_eye_round): the iris axis is Blender +Z, the upper side +Y; the ball is the root mesh,
# named after the part type, and kept whole in the bake so the iris edge stays a clean ring.


def _mp_eye_ball(name, centre, radius, iris_half, mats, segs=24, iris_bands=3, sclera_bands=(0.15, 0.35, 0.6, 1.0),
                 floor=None):
    """An eyeball revolved round +Z with a ring exactly at the iris edge (as cp._eye_ball), but with fewer rings on
    the hidden back half, which the lids and the skin cover. mats is [sclera, iris] (faces inside iris_half take
    the second), or a single material for the whole ball. `floor` flattens the buried bottom at that z."""
    thetas = [iris_half * k / iris_bands for k in range(iris_bands + 1)]
    thetas += [iris_half + (math.pi - iris_half) * f for f in sclera_bands]
    prof = [(radius * math.cos(t), radius * math.sin(t) if 0.0 < t < math.pi - 1e-9 else 0.0) for t in thetas]
    rv, rf, bands = bc.revolve(prof, segs)
    verts = [centre + Vector(v) for v in cp._up(rv)]
    if floor is not None:
        verts = [Vector((v.x, v.y, max(floor, v.z))) for v in verts]
    face_mats = [1 if b < iris_bands else 0 for b in bands] if len(mats) > 1 else None
    return bc.mesh_object(name, verts, rf, list(mats), face_mats)


def _mp_resample(points, n):
    """n points evenly spaced by arc length along the polyline `points` (2D tuples), with each one's arc length."""
    cum = [0.0]
    for a, b in zip(points, points[1:]):
        cum.append(cum[-1] + math.dist(a, b))
    out = []
    for k in range(n):
        d = cum[-1] * k / (n - 1)
        i = max(0, min(len(points) - 2, next((j for j in range(len(cum) - 1) if cum[j + 1] >= d), len(points) - 2)))
        t = 0.0 if cum[i + 1] == cum[i] else (d - cum[i]) / (cum[i + 1] - cum[i])
        a, b = points[i], points[i + 1]
        out.append(((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])), d))
    return out


TURRET_SINK = 0.025
TURRET_BALL_R = 0.021
TURRET_BALL = Vector((0.0, 0.0, 0.0355))
# The turret's outside as (r, z), from under the skin up a slightly convex cone to the aperture; then the lip, which
# rolls in and down to hug the ball, so the pupil sits just inside the opening.
TURRET_OUTSIDE = ((0.0405, -0.0235), (0.0418, -0.006), (0.0421, 0.004), (0.0408, 0.012), (0.0378, 0.020),
                  (0.0340, 0.028), (0.0298, 0.036), (0.0252, 0.044), (0.0200, 0.051), (0.0158, 0.0553),
                  (0.0124, 0.0585))
TURRET_LIP = ((0.0108, 0.0596), (0.0096, 0.0590), (0.0092, 0.0575), (0.0095, 0.0556))
TURRET_APERTURE = 0.0108
TURRET_TOLERANCE = 0.0003      # a tighter decimation than the default, so the cone and the aperture stay round


def _turret_close(r):
    """How far a point at radius r near the aperture moves in when the eye shuts: the lip almost to the axis, the
    shoulder less, nothing past 2 cm, so the cone puckers shut without folding."""
    if r <= TURRET_APERTURE:
        return 0.9 * r
    return 0.9 * TURRET_APERTURE * (1.0 - _mp_smooth(r, TURRET_APERTURE, 0.02))


def build_eye_turret():
    """A chameleon's eye: a scaly conical turret about 8.4 cm across and 6 cm tall, ringed with concentric ridges of
    granular scales, its skin fused over the ball so only a small aperture at the tip shows a gold-ringed, glossy
    black pupil. H1_Blink draws the aperture shut, H2_Reach stretches the turret about 2 cm further out (the ball
    riding up inside it)."""
    # The concentric ridges of scales are in the shader (so the normal map carries them evenly); the mesh is smooth.
    outside = [p for p, _ in _mp_resample(TURRET_OUTSIDE, 22)]
    profile = outside + list(TURRET_LIP)
    verts, faces, _ = _mp_lathe(len(profile), lambda i, a: profile[i], 32)
    # The ball shows only through the aperture (about 27 degrees of it): a gold iris ring round a glossy black pupil.
    ball_mat = cp._iris_material("M_EyeTurretBallProc", TURRET_BALL, Vector((0.0, 0.0, 1.0)), math.radians(30.0),
                                 math.radians(13.0))
    ball = _mp_eye_ball("EyeTurret", TURRET_BALL, TURRET_BALL_R, math.radians(30.0), [ball_mat], segs=24, iris_bands=4,
                        sclera_bands=(0.4, 1.0))
    # Granular scales: small domed tubercles with crisp gaps, in bands that follow the concentric ridges.
    sh = sf.Shader("M_EyeTurretScaleProc")
    dome = sh.remap(sh.voronoi(330.0, 0.5), 0.55, 0.05)
    gap = sh.remap(sh.voronoi(330.0, 0.5, feature="DISTANCE_TO_EDGE"), 0.0, 0.07)
    grains = sh.math("MULTIPLY", gap, sh.math("ADD", 0.4, sh.math("MULTIPLY", dome, 0.6)))
    mottle = sh.remap(sh.noise(55.0, 2.0), 0.4, 0.62)
    ridges = sh.remap(sh.math("SINE", sh.math("MULTIPLY", sh.axis("Z"), 2.0 * math.pi / 0.0068)), -0.6, 1.0)
    shoulder = sh.remap(sh.axis("Z"), 0.004, 0.012)                  # no ridges where it meets the skin
    sh.bump(sh.math("ADD", sh.math("MULTIPLY", grains, 0.55), sh.math("MULTIPLY", sh.math("MULTIPLY", ridges, shoulder),
                                                                       0.45)), 0.5, 0.0011)
    scale_mat = sh.out(_grey(sh, sh.math("ADD", sh.math("ADD", 0.3, sh.math("MULTIPLY", grains, 0.45)),
                                         sh.math("MULTIPLY", mottle, 0.25)), 0.5), 0.55)
    cone = bc.mesh_object("EyeTurretCone", verts, faces, [scale_mat], parent=ball, fix_normals=False)
    ball_mat.name, scale_mat.name = "M_EyeTurretBall", "M_EyeTurretScale"
    baked = _bake_parts([ball, cone], "PartEyeTurret", {"M_EyeTurretBall": sf.tint(cp._lin("#D9A030")),
                                                       "M_EyeTurretScale": sf.tint(cp._lin("#3A9C94"))},
                        tolerance=TURRET_TOLERANCE, keep=("EyeTurret",))
    pts = cp._check_pivot("eye_turret", TURRET_SINK)
    foot = cp._footprint(pts, z_max=0.006)
    apex = TURRET_BALL.z + TURRET_BALL_R
    mp._check(TURRET_LIP[0][1] - apex < 0.0045 and TURRET_LIP[-1][1] - (TURRET_BALL.z + math.sqrt(
        TURRET_BALL_R ** 2 - TURRET_LIP[-1][0] ** 2)) > 0.0, "eye_turret: the pupil sits just inside the aperture")

    def blink(co):
        if co.z < 0.045:
            return co.copy()
        r = math.hypot(co.x, co.y)
        if r < 1e-9:
            return co.copy()
        d = _turret_close(r)
        return Vector((co.x * (r - d) / r, co.y * (r - d) / r, co.z + 0.0012 * d / (0.9 * TURRET_APERTURE)))

    def reach(co):
        return Vector((co.x, co.y, co.z + 0.022 * _mp_smooth(co.z, 0.006, 0.040)))

    handles = cp._shape_keys(cone, [("H1_Blink", blink, "the aperture drawn shut over the pupil"),
                                    ("H2_Reach", reach, "the turret about 2.2 cm taller, reaching further out")])
    cp._shape_keys(ball, [("H2_Reach", lambda co: co + Vector((0.0, 0.0, 0.022)), "")])
    rules = _rules("eye_turret", round(foot + 0.001, 3), TURRET_SINK, "forward_cone", ["spine", "part"], 60, 45)
    rules["handles"] = handles
    rules["handles_note"] = ("H1_Blink is on EyeTurretCone; H2_Reach is on EyeTurretCone and the ball EyeTurret with "
                             "the same name: the cone stretches and the ball rides up inside it by the same 2.2 cm.")
    return {"purpose": "Creature eye part (PROPOSED): a chameleon-like scaly conical eye turret with a small "
                       "gold-ringed pupil at its tip; shuts and reaches on shape keys.",
            "category": "part", "part_type": "eye_turret", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_EyeTurretBall": 0.0, "M_EyeTurretScale": 0.85}, "revision": 1,
            **baked}


LASHED_R = 0.05
LASHED_SINK = 0.03
LASHED_C = Vector((0.0, 0.0, 0.008))      # the ball's back half is in the skin, like an eye in its socket
# The lid is one ring round an almond opening: its margin's polar angle (from +Z, about the ball's centre) is
# LASHED_TOP at the top (it covers the top of the iris), LASHED_BOTTOM at the bottom and LASHED_CORNER at the two
# corners (+-X); behind, the ring runs back to LASHED_BACK, under the skin.
LASHED_TOP = math.radians(30.0)
LASHED_BOTTOM = math.radians(52.0)
LASHED_CORNER = math.radians(80.0)
LASHED_BACK = math.radians(105.0)
LASHED_SEGS = 48
LASHED_BLINK = math.radians(94.0)         # the upper lid swings down on the corners' hinge to meet the lower lid
LASHED_LASHES = 7


def _lashed_margin(psi):
    """The margin's polar angle at azimuth psi (round +Z from +X; the upper lid is 0 < psi < pi)."""
    s_ = math.sin(psi)
    end = LASHED_TOP if s_ >= 0.0 else LASHED_BOTTOM
    return LASHED_CORNER + (end - LASHED_CORNER) * abs(s_) ** 0.8


def _lashed_lid_loop(psi):
    """The lid's cross-section at azimuth psi as (polar angle, radius) pairs: from the back of its outer face
    forward to a rounded margin and back along its inner face, ending where it began (the seam is under the skin).
    The upper lid is heavy (about 1 cm thick at its margin), the lower one thin."""
    up = max(0.0, math.sin(psi))
    thick, thick_back = 0.0045 + 0.0062 * up ** 1.5, 0.003
    r_in = LASHED_R * (1.03 + 0.015 * up)
    rim_r = 0.5 * thick
    rho_mid = r_in + rim_r
    th_rim = _lashed_margin(psi) + rim_r / rho_mid
    loop = []
    for k in range(5):
        th = LASHED_BACK + (th_rim - LASHED_BACK) * k / 5
        loop.append((th, r_in + thick_back + (thick - thick_back) * _mp_smooth(th, LASHED_BACK, th_rim) ** 1.6))
    for k in range(7):
        ph = math.pi * k / 6
        loop.append((th_rim - (rim_r / rho_mid) * math.sin(ph), rho_mid + rim_r * math.cos(ph)))
    for k in range(1, 4):
        loop.append((th_rim + (LASHED_BACK - th_rim) * k / 3, r_in))
    loop.append(loop[0])
    return loop


def _lashed_point(theta, psi, rho):
    return LASHED_C + Vector((math.sin(theta) * math.cos(psi), math.sin(theta) * math.sin(psi), math.cos(theta))) * rho


LASHED_HINGE = Vector((0.0, 0.0, LASHED_C.z + LASHED_R * 1.08 * math.cos(LASHED_CORNER)))   # through both corners


def _lashed_blink(co, rigid=False):
    """The upper lid (and its lashes) swing down on a hinge through the eye's two corners; the lower lid rises a
    little. Each lid's back, under the skin, stays put."""
    d = co - LASHED_C
    theta = math.atan2(math.hypot(d.x, d.y), d.z)
    w = 1.0 if rigid else 1.0 - _mp_smooth(theta, math.radians(72.0), math.radians(103.0))
    if d.y >= 0.0:
        return _rot_x(co, LASHED_HINGE, LASHED_BLINK * w)
    return _rot_x(co, LASHED_HINGE, -math.radians(7.0) * w)


def build_eye_lashed():
    """A big expressive eye: a white ball 10 cm across, set in the skin to about its middle, with a wide chestnut
    iris and a large pupil, seen through an almond opening in one lid ring that runs back into the skin like a
    socket: heavy and rolled above (covering the top of the iris), thin below, the two meeting smoothly at the
    corners. The upper margin carries seven bold, flat, tapered lashes reaching forward and flicking up, longest
    in the middle. H1_Blink swings the upper lid and its lashes down on a hinge through the corners to meet the
    lower lid (which rises a little); H2_Bulge pushes the ball out."""
    axis = Vector((0.0, 0.0, 1.0))
    sclera = cp._sclera_material("M_EyeLashedBallProc")
    iris_mat = cp._iris_material("M_EyeLashedIrisProc", LASHED_C, axis, math.radians(44.0), math.radians(21.0))
    ball = _mp_eye_ball("EyeLashed", LASHED_C, LASHED_R, math.radians(44.0), [sclera, iris_mat], segs=24,
                        floor=-LASHED_SINK + 0.0005)
    loops = [_lashed_lid_loop(2.0 * math.pi * j / LASHED_SEGS) for j in range(LASHED_SEGS)]

    def lid_at(i, psi):
        th, rho = loops[round(psi * LASHED_SEGS / (2.0 * math.pi)) % LASHED_SEGS][i]
        return rho * math.sin(th), LASHED_C.z + rho * math.cos(th)

    lid_v, lid_f, _ = _mp_lathe(len(loops[0]), lid_at, LASHED_SEGS)
    clamp = -LASHED_SINK + 0.0012
    lid_v = [(x, y, max(clamp, z)) for x, y, z in lid_v]

    # The lashes, rooted on the outer front of the upper lid's margin: each reaches forward off the margin and
    # flicks up at its tip (not back over the lid, where they read as claws), the outer ones fanning to the corners.
    lash_v, lash_f, lash_tips = [], [], []
    for n in range(LASHED_LASHES):
        psi = math.radians(38.0 + 104.0 * n / (LASHED_LASHES - 1))
        loop = _lashed_lid_loop(psi)
        th_root, rho_root = loop[5 + 2]                      # on the rim, just out from its front
        root = _lashed_point(th_root, psi, rho_root - 0.0012)
        d = (root - LASHED_C).normalized()
        e_th = Vector((math.cos(th_root) * math.cos(psi), math.cos(th_root) * math.sin(psi), -math.sin(th_root)))
        e_psi = Vector((-math.sin(psi), math.cos(psi), 0.0))
        fan = -e_psi * (0.65 * math.cos(psi))
        length = 0.032 * (0.75 + 0.25 * math.sin(psi) ** 2)
        path, p, steps = [], root.copy(), 5
        for k in range(steps):
            path.append(p.copy())
            beta = math.radians(6.0 + 56.0 * ((k + 0.5) / steps) ** 1.4)
            p = p + (d * math.cos(beta) + e_th * math.sin(beta) + fan).normalized() * (length / steps)
        path.append(p.copy())
        lash_tips.append(p)
        # Bold flat petals: wide at the root and tapering to a point, as a cartoon lash reads at a distance.
        half_w = [0.0042 * (1.0 - k / steps) ** 0.6 for k in range(steps)] + [0.0]
        half_t = [0.0015 * (1.0 - k / steps) ** 0.6 for k in range(steps)] + [0.0]
        v, f = _mp_spike(path, half_w, half_t, 4, hint=e_th)
        _mp_append(lash_v, lash_f, v, f)

    lid_mat = cp._lid_material("M_EyeLashedLidProc")
    lash = sf.Shader("M_EyeLashedLashProc")
    sheen = lash.noise(300.0, 2.0, vector=mp._stretched(lash, (3.0, 3.0, 3.0)))
    lash_mat = lash.out(_grey(lash, lash.remap(sheen, 0.3, 0.7, 0.8, 1.0), 0.75), 0.3)
    lid = bc.mesh_object("EyeLashedLid", lid_v, lid_f, [lid_mat], parent=ball, fix_normals=False)
    lashes = bc.mesh_object("EyeLashedLashes", lash_v, lash_f, [lash_mat], parent=ball)
    sclera.name, iris_mat.name, lid_mat.name, lash_mat.name = ("M_EyeLashedBall", "M_EyeLashedIris",
                                                               "M_EyeLashedLid", "M_EyeLashedLash")
    baked = _bake_parts([ball, lid, lashes], "PartEyeLashed",
                        {"M_EyeLashedBall": sf.tint(cp._lin("#F2EEE6")), "M_EyeLashedIris": sf.tint(cp._lin("#9A5A2C")),
                         "M_EyeLashedLid": sf.tint(cp._lin("#C49A86")), "M_EyeLashedLash": sf.tint(cp._lin("#2A2230"))},
                        keep=("EyeLashed", "EyeLashedLashes"))      # the iris ring and the thin lashes stay whole
    pts = cp._check_pivot("eye_lashed", LASHED_SINK)
    foot = cp._footprint(pts, z_max=0.02)
    mp._check(min(t.y for t in lash_tips) > LASHED_C.y + 0.03, "eye_lashed: every lash flicks up above the ball")

    def bulge(co):
        return Vector((co.x, co.y, co.z + 0.2 * LASHED_R * max(0.0, co.z) / (LASHED_R * 1.42)))

    handles = cp._shape_keys(lid, [("H1_Blink", _lashed_blink, "the heavy upper lid and its lashes swing down over the "
                                                                "ball to meet the lower lid, which rises a little")])
    cp._shape_keys(lashes, [("H1_Blink", lambda co: _lashed_blink(co, rigid=True), "")])
    handles += cp._shape_keys(ball, [("H2_Bulge", bulge, "the ball pushed 20% further out")])
    rules = _rules("eye_lashed", round(foot + 0.001, 3), LASHED_SINK, "forward_cone", ["spine", "part"], 60, 45)
    rules["handles"] = handles
    rules["handles_note"] = ("H1_Blink is on EyeLashedLid and EyeLashedLashes with the same name (the upper lid and "
                             "its lashes swing down together on a hinge through the eye's corners); H2_Bulge is on "
                             "the ball, EyeLashed. Both are 0 to 1000 per mille.")
    return {"purpose": "Creature eye part (PROPOSED): a big expressive eye with a chestnut iris under a heavy upper "
                       "lid fringed with five bold upcurled lashes; blinks and bulges on shape keys.",
            "category": "part", "part_type": "eye_lashed", "convention": "creature_art_contract v1",
            "part_rules": rules, "paint_mix": {"M_EyeLashedBall": 0.0, "M_EyeLashedIris": 0.0, "M_EyeLashedLid": 0.9,
                                               "M_EyeLashedLash": 0.2}, "revision": 1, **baked}


def _bake_parts(objs, texture, tints, size=512, tolerance=cp.TOLERANCE, keep=()):
    return cp._bake(objs, texture, tints, size=size, tolerance=tolerance, keep=keep)


def _grey(sh, fac, lo):
    return cp._grey(sh, fac, lo)


ASSETS = {
    "cpart_beak_hooked": (build_beak_hooked, 1200),
    "cpart_beak_long": (build_beak_long, 1200),
    "cpart_trunk": (build_trunk, 2500),
    "cpart_trunk_short": (build_trunk_short, 1200),
    "cpart_mouth_sucker": (build_mouth_sucker, 1200),
    "cpart_mouth_fangs": (build_mouth_fangs, 1200),
    "cpart_eye_turret": (build_eye_turret, 1200),
    "cpart_eye_lashed": (build_eye_lashed, 1200),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the more-parts creature parts.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    parser.add_argument("--notes-only", action="store_true",
                        help="rewrite only review_notes in the existing records from REVIEW (no rebuild)")
    args = parser.parse_args(argv)
    ids = [i for i in args.only.split(",") if i] or list(ASSETS)
    unknown = [i for i in ids if i not in ASSETS]
    if unknown:
        parser.error(f"unknown asset id(s): {', '.join(unknown)}; known: {', '.join(ASSETS) or '(none yet)'}")
    if args.notes_only:
        for asset_id in ids:
            path = bc.paths(asset_id)[2]
            with open(path) as f:
                record = json.load(f)
            record["review_notes"] = _review_notes(asset_id)
            record["provenance"] = record.pop("provenance")      # keep provenance last, as bc.export writes it
            with open(path, "w") as f:
                json.dump(record, f, indent=2)
                f.write("\n")
            print(f"{asset_id}: review notes updated")
        return
    for asset_id in ids:
        builder, budget = ASSETS[asset_id]
        bc.reset_scene()
        fields = builder()
        fields["review_notes"] = _review_notes(asset_id)
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR,
                           provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
