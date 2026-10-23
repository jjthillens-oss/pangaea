"""Build the M1 step 3 threat blockouts: the ambush hunter's body, the territorial rammer's body
and the spike part.

For every asset id this writes (Bible section 16):
  assets/source/blender/<id>.blend   (editable source)
  assets/export/<id>.glb             (engine export)
  assets/records/<id>.json           (asset record: PROPOSED, a blockout, not visually approved)

Run with the pinned Blender (see docs/TOOLCHAIN.md):
  blender --background --python tools/blender/make_m1_threats.py -- [--only <id>[,<id>...]]
or with the bpy module:
  python tools/blender/make_m1_threats.py [--only <id>[,<id>...]]

Conventions (verified by tests/test_assets.gd after import), as in make_m1_blockouts.py:
  * 1 Blender meter = 1 Godot unit. Blender +Y becomes Godot -Z, Blender +Z becomes Godot +Y.
  * Bodies only (decision D22): a species' parts are the player's part GLBs, placed at runtime by
    game/scenes/pool/part_placement.gd, and the creature view scales the whole model by the
    species' body_size. So each body is built at size 1 on the shared frame: at the swim plane
    (Blender z = 0) its outline is PartPlacement's ellipse, FRAME_RX across and FRAME_RZ along, and
    every part sits on its surface at any angle.
  * Pose nodes the creature view animates are children of Body with their origin at their pivot:
    Eye_L and Eye_R (the eye's centre), Brow (ambush) and Hood (rammer).
  * Parts have their origin at the attachment point and extend outward along Blender +Y.
Colours follow docs/art/ART_DIRECTION.md (approved 2026-10-22): shadows lean blue and are never
black, the threat colour #D9466B goes only on sharp shapes (the spike, the rammer's crest points),
and the ambush hunter's eyes are mineral amber.
The output is deterministic: fixed formulas and mathutils.noise at fixed offsets, no random
numbers. GLBs and records come out byte-identical on every run (see make_m1_blockouts.py on the
few bytes of a .blend that Blender takes from the clock).
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first, which provides mathutils)
from mathutils import Matrix, Vector, noise  # noqa: E402

REVIEW_STATE = "blockout - M1 step 3, not visually approved"
GENERATOR = "tools/blender/make_m1_threats.py"

# The shared body frame: game/scenes/pool/part_placement.gd RX (half width) and RZ (half length).
FRAME_RX = 0.46
FRAME_RZ = 0.5
# As make_m1_blockouts.PART_EMBED: how far a part sinks into the body behind its attachment point.
PART_EMBED = 0.03
PART_ATTACHMENT = {
    "origin": "attachment point on the body surface",
    "outward_axis": "Blender +Y (Godot -Z)",
    "embed_m": PART_EMBED,
}

# Palette (docs/art/ART_DIRECTION.md section 3), as sRGB hex.
DEEP_SHADOW = "#1D3557"
CREAM = "#F4EAD2"
MINERAL_AMBER = "#E3A64A"
THREAT = "#D9466B"

# Ambush hunter: a big flat pebble with a heavy brow over glowing amber eyes. It reads flat and
# low next to the round player cell: the whole asset, eyes and brow included, stays within
# AMBUSH_MAX_HEIGHT_SHARE of its width (the test_assets silhouette contract). The plan's sketch of
# 0.24 m above and 0.20 m below the swim plane would be 0.48 of the 0.92 m frame width, so the
# body is lower: about 0.18 m above (eyes and brow included) and 0.10 m below, 0.30 of the width.
AMBUSH_MAX_HEIGHT_SHARE = 0.35
AMBUSH_TOP = 0.11          # crown height of the back
AMBUSH_HEAD = 0.035        # the head rises this much more under the eyes
AMBUSH_TAIL_THIN = 0.025   # the back thins this much toward the tail
AMBUSH_BOTTOM = 0.10       # belly depth under the swim plane
AMBUSH_ROUND = (0.55, 0.6)  # superellipse exponents, top and bottom: a blunt, rounded rim
AMBUSH_EYE = (0.165, 0.27, 0.09)  # eye centre (x, y) and radius: 20% of the body width across
AMBUSH_EYE_SINK = 0.035    # how far the eye centre sits under the socket's surface
AMBUSH_SEGMENTS = 56
AMBUSH_RINGS = (12, 7)     # rings over the top and under the belly
# Colours: a dark mottled olive-brown back over a pale belly. The mottles lean to the deep
# shadow blue, so the darkest patches are blue, never black.
AMBUSH_BACK = "#5B4D31"
AMBUSH_MOTTLE = "#2C2F3B"
AMBUSH_FLECK = "#7D6E45"
AMBUSH_MOTTLE_SHARE = 0.6  # at most this much of the mottle colour, so the back still reads as one dark mass
AMBUSH_BROW = "#3B3324"
AMBUSH_EYE_GLOW = 0.4      # rest emission; the creature view drives it (0.4 noticing, 1.0 in the coil)

# Territorial rammer: a pale domed pebble with three dark bands, a dorsal crest and angry lids.
RAMMER_TOP = 0.40
RAMMER_BOTTOM = 0.30
RAMMER_ROUND = (1.0, 0.85)
RAMMER_EYE_DIR = (0.42, 0.72, 0.42)  # right eye, before normalising; the left one is mirrored
RAMMER_EYE_RADIUS = 0.08
RAMMER_EYE_SINK = 0.03
RAMMER_LID_TILT_DEG = 40.0   # the upper lids sit back over the eyes, so the pupils show from above
RAMMER_LID_FROWN_DEG = 22.0  # and slant down toward the middle of the face
RAMMER_SEGMENTS = 36
RAMMER_RINGS = 18          # rings along the body before the extra rings at the band edges
RAMMER_SAND = "#E2C99A"    # pale sand, warmer and brighter than the pool floor so it reads on it
RAMMER_BAND = "#5E3226"
RAMMER_LID = "#B99B6A"     # a shade darker than the sand (art direction: lids and lips)
RAMMER_BANDS = [(0.15, 0.045), (-0.06, 0.055), (-0.27, 0.045)]  # (centre y, half width) across the back
RAMMER_BAND_EDGE = 0.02    # each band fades in over this much, between two rings
# The dorsal crest (node Hood): CREST_POINTS raked points along the midline, threat-coloured above
# the membrane. Its origin is the middle of its base on the back; the creature view raises it by
# scaling its up axis (Godot +Y), which sinks the base deeper into the body instead of lifting it off.
CREST_SPAN = (0.10, -0.28)  # y from the front of the base to the back
CREST_POINTS = 5
CREST_TIP = 0.17           # point height over the back
CREST_VALLEY = 0.06        # membrane height between the points
CREST_RAKE = 0.035         # points lean back by this much
CREST_SINK = 0.04          # the base sits this far under the back's surface
CREST_THICKNESS = (0.022, 0.004)  # at the base and at the points

# Spike part: a tapered thorn, embedded PART_EMBED behind its attachment point.
SPIKE_LENGTH = 0.32
SPIKE_RADIUS = 0.075       # bold enough to read as a thorn at the widest zoom
SPIKE_ROOT = CREAM          # a bone-coloured collar where it leaves the body
SPIKE_TIP = "#8A2B45"       # the threat colour, darkened toward the point


def _check(condition, message):
    if not condition:
        raise RuntimeError(message)


def linear(hex_color):
    """An sRGB hex colour as linear RGB, the space Blender material and vertex colours use."""
    h = hex_color.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


def _mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def gauss(d2, sigma):
    return math.exp(-d2 / (2.0 * sigma * sigma))


def frame_radius(azimuth):
    """Distance from the centre to the frame ellipse at `azimuth` (0 = front +Y, PI/2 = right +X)."""
    s, c = math.sin(azimuth), math.cos(azimuth)
    return 1.0 / math.sqrt((s / FRAME_RX) ** 2 + (c / FRAME_RZ) ** 2)


def _spow(x, e):
    return math.copysign(abs(x) ** e, x)


def arc_elevations(k, height, count, radius=0.48):
    """`count + 1` elevations from 0 (the equator) to PI/2 (the pole) that space rings evenly
    along a superellipse quarter profile of `radius`, `height` and exponent `k`, so the rounded
    rim and the crown both get rings instead of one long fan round the pole."""
    samples = 512
    es = [math.pi / 2.0 * i / samples for i in range(samples + 1)]
    pts = [(radius * math.cos(e) ** k, height * math.sin(e) ** k) for e in es]
    run = [0.0]
    for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
        run.append(run[-1] + math.hypot(x1 - x0, z1 - z0))
    out, j = [], 0
    for i in range(count + 1):
        target = run[-1] * i / count
        while j < samples - 1 and run[j + 1] < target:
            j += 1
        f = (target - run[j]) / max(run[j + 1] - run[j], 1e-12)
        out.append(es[j] + (es[j + 1] - es[j]) * min(1.0, f))
    out[0], out[-1] = 0.0, math.pi / 2.0
    return out


def _grid_faces(rings, segments):
    """Quads between consecutive rings of `segments` vertices, and fans where a ring is a pole."""
    faces = []
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(segments):
            k = (j + 1) % segments
            if len(a) == 1:
                faces.append((a[0], b[k], b[j]))
            elif len(b) == 1:
                faces.append((a[j], a[k], b[0]))
            else:
                faces.append((a[j], a[k], b[k], b[j]))
    return faces


class Pebble:
    """A closed body on the shared frame whose outline at z = 0 is the frame ellipse.
    `top(x, y)` and `bottom(x, y)` give the crown height and belly depth over each point, so
    features (a head, sockets, a lean) move the surface up and down but never the equator.
    Subclasses lay the vertices out and say how high the top surface is over a point."""

    def __init__(self, top, bottom, rounding):
        self.top = top
        self.bottom = bottom
        self.round_top, self.round_bottom = rounding

    @staticmethod
    def rho(x, y):
        """0 at the centre, 1 on the frame ellipse."""
        return math.hypot(x / FRAME_RX, y / FRAME_RZ)

    def top_z(self, x, y):
        raise NotImplementedError

    def surface_point(self, direction):
        """The point where a ray from the centre along `direction` leaves the top half."""
        d = Vector(direction).normalized()
        lo, hi = 0.0, 1.0
        for _ in range(40):
            t = (lo + hi) / 2.0
            p = d * t
            inside = self.rho(p.x, p.y) < 1.0 and p.z <= self.top_z(p.x, p.y)
            lo, hi = (t, hi) if inside else (lo, t)
        return d * lo


class RadialPebble(Pebble):
    """Rounded radially, like a superellipsoid round the vertical axis: a blunt rim all round.
    Rings of constant elevation run round the vertical axis."""

    def top_z(self, x, y):
        k = self.round_top
        r = min(1.0, self.rho(x, y))
        return self.top(x, y) * (1.0 - r ** (2.0 / k)) ** (k / 2.0)

    def mesh(self, segments, rings_top, rings_bottom):
        """(verts, faces): rings of `segments` vertices from the belly pole to the crown pole."""
        verts, rings = [], []
        top_e = arc_elevations(self.round_top, self.top(0.0, 0.0), rings_top)
        bottom_e = arc_elevations(self.round_bottom, self.bottom(0.0, 0.0), rings_bottom)
        for e in [-b for b in reversed(bottom_e)] + top_e[1:]:
            k = self.round_top if e >= 0.0 else self.round_bottom
            if abs(e) >= math.pi / 2.0:
                rings.append([len(verts)])
                verts.append(Vector((0.0, 0.0, self.top(0.0, 0.0) if e > 0.0 else -self.bottom(0.0, 0.0))))
                continue
            c = math.cos(e) ** k
            s = _spow(math.sin(e), k)
            ring = []
            for j in range(segments):
                a = 2.0 * math.pi * j / segments
                r = frame_radius(a) * c
                x, y = r * math.sin(a), r * math.cos(a)
                ring.append(len(verts))
                verts.append(Vector((x, y, s * (self.top(x, y) if s >= 0.0 else self.bottom(x, y)))))
            rings.append(ring)
        return verts, _grid_faces(rings, segments)


class LengthwisePebble(Pebble):
    """An ellipsoid along its length, rounded across it: rings of constant y run round the swim
    axis from the tail pole to the front pole, so markings across the back (bands) follow rings
    and stay crisp."""

    def _half_width(self, y):
        return math.sqrt(max(0.0, 1.0 - (y / FRAME_RZ) ** 2))

    def top_z(self, x, y):
        w = self._half_width(y)
        if w <= 0.0:
            return 0.0
        k = self.round_top
        c = min(1.0, abs(x) / (FRAME_RX * w))
        return self.top(x, y) * w * (1.0 - c ** (2.0 / k)) ** (k / 2.0)

    def mesh(self, segments, ring_ys):
        """(verts, faces): a ring of `segments` vertices (an even number, so the equator has a
        vertex on each side) at every y in `ring_ys`, which runs from -FRAME_RZ to FRAME_RZ."""
        verts, rings = [], []
        for y in ring_ys:
            w = self._half_width(y)
            if w <= 0.0:
                rings.append([len(verts)])
                verts.append(Vector((0.0, y, 0.0)))
                continue
            ring = []
            for j in range(segments):
                t = 2.0 * math.pi * j / segments  # 0 = right side, PI/2 = top
                k = self.round_top if math.sin(t) >= 0.0 else self.round_bottom
                x = FRAME_RX * w * _spow(math.cos(t), k)
                s = _spow(math.sin(t), k)
                ring.append(len(verts))
                verts.append(Vector((x, y, s * w * (self.top(x, y) if s >= 0.0 else self.bottom(x, y)))))
            rings.append(ring)
        return verts, _grid_faces(rings, segments)


def ellipsoid(radii, center, subdivisions, rotation=None):
    """(verts, faces) of an icosphere scaled to `radii`, rotated by `rotation` (a 3x3 Matrix), at `center`."""
    unit, faces = bc.icosphere(subdivisions)
    rot = rotation or Matrix.Identity(3)
    verts = [Vector(center) + rot @ Vector((v[0] * radii[0], v[1] * radii[1], v[2] * radii[2])) for v in unit]
    return verts, faces


def _origin_of(obj):
    """Where an object built by local_mesh (or the body) has its origin in body space: the sum of
    the locations up its parents, since none of them is rotated or scaled."""
    o = Vector((0.0, 0.0, 0.0))
    while obj is not None:
        o += obj.location
        obj = obj.parent
    return o


def local_mesh(name, verts, faces, materials, origin, parent, face_materials=None, smooth=True, fix_normals=True):
    """A child of `parent` with its origin at `origin` (`verts` and `origin` in body space; the body
    sits at the world origin), so the creature view can scale or turn it about that pivot."""
    o = Vector(origin)
    return bc.mesh_object(name, [Vector(v) - o for v in verts], faces, materials, face_materials, smooth=smooth,
                          parent=parent, location=tuple(o - _origin_of(parent)), fix_normals=fix_normals)


def _frame_fields(verts):
    """Record values the tests check: the frame, the crown and belly, and the height share."""
    every = bc.world_vertices()
    lo = Vector((min(v.x for v in every), min(v.y for v in every), min(v.z for v in every)))
    hi = Vector((max(v.x for v in every), max(v.y for v in every), max(v.z for v in every)))
    size = hi - lo
    equator = [v for v in verts if abs(v.z) < 1e-9]
    worst = max(abs(math.hypot(v.x, v.y) - frame_radius(math.atan2(v.x, v.y))) for v in equator)
    _check(worst < 1e-6, f"the equator is the frame ellipse (off by {worst:.6f} m)")
    return {
        "frame": {
            "equator_rx_m": FRAME_RX,
            "equator_rz_m": FRAME_RZ,
            "source": "game/scenes/pool/part_placement.gd RX and RZ; the part GLBs sit on this outline at the swim plane",
        },
        "top_m": round(hi.z, 3),
        "bottom_m": round(-lo.z, 3),
        "height_to_width": round(size.z / size.x, 3),
    }


# --- Ambush hunter body -----------------------------------------------------------------------


def _ambush_top(x, y):
    ex, ey, _ = AMBUSH_EYE
    h = AMBUSH_TOP
    h += AMBUSH_HEAD * gauss(x * x + (y - 0.2) ** 2, 0.17)
    h -= AMBUSH_TAIL_THIN * bc.smoothstep(-y / 0.5)
    # No perfect symmetry: the left flank behind the head is a little fuller.
    h += 0.008 * gauss((x + 0.2) ** 2 + (y + 0.1) ** 2, 0.1)
    for sx in (-1.0, 1.0):
        h -= 0.02 * gauss((x - sx * ex) ** 2 + (y - ey) ** 2, 0.06)  # eye socket
    return h


def _ambush_bottom(x, y):
    return AMBUSH_BOTTOM * (1.0 - 0.15 * bc.smoothstep(-y / 0.5))


def _ambush_color(p):
    back, mottle, fleck, belly = (linear(c) for c in (AMBUSH_BACK, AMBUSH_MOTTLE, AMBUSH_FLECK, CREAM))
    offset = Vector((7.3, -2.9, 4.1))
    # Mottles and flecks change slowly next to the vertex spacing (about 5 cm), so the
    # interpolation never shows the triangles.
    blot = noise.noise(p * 8.0 + offset) + 0.2 * noise.noise(p * 14.0 - offset)
    color = _mix(back, mottle, AMBUSH_MOTTLE_SHARE * bc.smoothstep((blot + 0.05) / 0.4))
    speck = noise.noise(p * 12.0 + offset * 2.0)
    color = _mix(color, fleck, 0.5 * bc.smoothstep((speck - 0.3) / 0.25))
    ex, ey, _ = AMBUSH_EYE
    for sx in (-1.0, 1.0):  # dark rings round the sockets frame the eyes
        color = _mix(color, mottle, 0.7 * gauss((p.x - sx * ex) ** 2 + (p.y - ey) ** 2, 0.06))
    if p.z < 0.0:
        color = _mix(color, belly, 0.85 * bc.smoothstep((-p.z / AMBUSH_BOTTOM - 0.1) / 0.45))
    return color


def build_ambush_body():
    body_mat = bc.material("M_AmbushBody", (1.0, 1.0, 1.0), 0.55, vertex_colors="AmbushColor")
    amber = linear(MINERAL_AMBER)
    eye_mat = bc.material("M_AmbushEye", amber, 0.05, emission=amber, emission_strength=AMBUSH_EYE_GLOW)
    pupil_mat = bc.material("M_AmbushPupil", linear(DEEP_SHADOW), 0.2)
    brow_mat = bc.material("M_AmbushBrow", linear(AMBUSH_BROW), 0.65)
    pebble = RadialPebble(_ambush_top, _ambush_bottom, AMBUSH_ROUND)
    verts, faces = pebble.mesh(AMBUSH_SEGMENTS, *AMBUSH_RINGS)
    body = bc.mesh_object("Body", verts, faces, [body_mat], vertex_colors=("AmbushColor", [_ambush_color(v) for v in verts]))
    ex, ey, er = AMBUSH_EYE
    for side, sx in (("L", -1.0), ("R", 1.0)):
        centre = Vector((sx * ex, ey, pebble.top_z(sx * ex, ey) - AMBUSH_EYE_SINK))
        ev, ef = ellipsoid((er, er, er), centre, 3)
        eye = local_mesh(f"Eye_{side}", ev, ef, [eye_mat], centre, body)
        # A vertical slit pupil on the front of the eye, looking forward, out and a little up.
        gaze = Vector((sx * 0.35, 1.0, 0.45)).normalized()
        rot = gaze.to_track_quat("Y", "Z").to_matrix()
        pv, pf = ellipsoid((0.018, 0.01, 0.06), centre + gaze * (er - 0.005), 2, rot)
        local_mesh(f"Pupil_{side}", pv, pf, [pupil_mat], centre, eye)
    # The brow: a heavy chevron ridge over the back of both eyes, low in the middle and pointed at
    # the outer ends, so even from straight above the face reads as a scowl. Two halves meet in the
    # middle; each starts with a flat cap there that the other half hides.
    brow_verts, brow_faces = [], []
    brow_z = pebble.top_z(ex, ey - 0.055)
    for sx in (-1.0, 1.0):
        path = [Vector((0.0, 0.29, brow_z - 0.03)), Vector((sx * 0.08, 0.26, brow_z + 0.005)),
                Vector((sx * ex, ey - 0.055, brow_z + 0.035)), Vector((sx * 0.25, 0.17, brow_z + 0.015)),
                Vector((sx * 0.31, 0.11, brow_z - 0.02)), Vector((sx * 0.345, 0.06, brow_z - 0.05))]
        steps = 14
        pts = []
        for i in range(steps + 1):  # Catmull-Rom through the path for a smooth ridge
            u = i / steps * (len(path) - 1)
            k = min(int(u), len(path) - 2)
            t = u - k
            p0, p1, p2, p3 = path[max(k - 1, 0)], path[k], path[k + 1], path[min(k + 2, len(path) - 1)]
            pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
                              + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
        radii = [0.034 * (1.0 - bc.smoothstep((i / steps - 0.45) / 0.55)) ** 0.7 + 0.018 * (1.0 - i / steps) for i in range(steps + 1)]
        radii[-1] = 0.0
        tv, tf = bc.tube(pts, radii, 8, squash=0.6)
        bc.append(brow_verts, brow_faces, tv, tf)
    local_mesh("Brow", brow_verts, brow_faces, [brow_mat], (0.0, ey - 0.055, brow_z), body)
    fields = _frame_fields(verts)
    _check(fields["height_to_width"] <= AMBUSH_MAX_HEIGHT_SHARE,
           f"creature_ambush_body: height {fields['height_to_width']} of the width, at most {AMBUSH_MAX_HEIGHT_SHARE}")
    fields.update({
        "purpose": "M1 step 3 ambush hunter body (role: ambush): a big, flat, dark mottled pebble with glowing amber eyes under a heavy brow. Body only; its parts come from the part GLBs.",
        "category": "creature_body",
        "dependencies": ["assets/export/M_AmbushBody.tres"],
        "vertex_colors_attribute": "AmbushColor",
        "pivot": "body centre on the swim plane (Godot y = 0); built at size 1, the creature view scales it by the species' body_size",
        "pose_nodes": {
            "Eye_L": "child of Body, origin at the eye's centre; material M_AmbushEye, whose emission the creature view drives",
            "Eye_R": "as Eye_L",
            "Brow": "child of Body, origin at the middle of the ridge",
        },
        "eye_material": "M_AmbushEye",
        "eye_emission_rest": AMBUSH_EYE_GLOW,
        "vertex_colors": {
            "attribute": "AmbushColor",
            "encoding": "sRGB-encoded in COLOR_0; the engine material sets vertex_color_is_srgb (assets/export/M_AmbushBody.tres)",
            "note": "Dark olive-brown back with blue-leaning mottles and light olive flecks, dark rings round the eye sockets, a cream belly.",
            "back": AMBUSH_BACK, "mottle": AMBUSH_MOTTLE, "fleck": AMBUSH_FLECK, "belly": CREAM,
        },
    })
    return fields


# --- Territorial rammer body ------------------------------------------------------------------


def _rammer_top(x, y):
    # No perfect symmetry: the dome's crown leans a little back and to the left.
    return RAMMER_TOP * (1.0 + 0.03 * gauss((x + 0.12) ** 2 + (y + 0.08) ** 2, 0.2) - 0.02 * bc.smoothstep(y / 0.5))


def _rammer_bottom(x, y):
    return RAMMER_BOTTOM


def _rammer_ring_ys():
    """Ring positions from the tail pole to the front pole: closer together near the poles, where
    the surface turns fastest, plus a ring at each side of every band edge."""
    ys = [FRAME_RZ * math.sin(math.pi * (i / RAMMER_RINGS - 0.5)) for i in range(RAMMER_RINGS + 1)]
    for centre, half in RAMMER_BANDS:
        for edge in (centre - half, centre + half):
            ys += [edge - RAMMER_BAND_EDGE / 2.0, edge + RAMMER_BAND_EDGE / 2.0]
    ys.sort()
    out = [ys[0]]
    for y in ys[1:]:
        if y - out[-1] > 0.006:
            out.append(y)
    out[0], out[-1] = -FRAME_RZ, FRAME_RZ
    return out


def _rammer_color(p):
    sand, band, belly = (linear(c) for c in (RAMMER_SAND, RAMMER_BAND, CREAM))
    offset = Vector((-3.7, 5.2, 1.9))
    color = tuple(c * (1.0 + 0.05 * noise.noise(p * 9.0 + offset)) for c in sand)
    # Three bands across the back, fading out down the flanks. Their edges lie on rings
    # (_rammer_ring_ys), so they stay straight and crisp.
    on_back = bc.smoothstep((p.z + 0.06) / 0.12)
    for centre, half in RAMMER_BANDS:
        t = 1.0 - bc.smoothstep((abs(p.y - centre) - half + RAMMER_BAND_EDGE / 2.0) / RAMMER_BAND_EDGE)
        color = _mix(color, band, t * on_back)
    if p.z < 0.0:
        color = _mix(color, belly, 0.8 * bc.smoothstep((-p.z / RAMMER_BOTTOM - 0.15) / 0.5))
    return color


def _lid(radius, thickness):
    """(verts, faces) of a closed upper-half shell around an eye of `radius`, rim at z = 0."""
    segments, rings = 16, 5
    verts, faces = [], []
    for r in (radius + thickness, radius + 0.002):
        for i in range(rings + 1):
            e = math.pi / 2.0 * i / rings
            for j in range(segments):
                a = 2.0 * math.pi * j / segments
                if i == rings:
                    if j == 0:
                        verts.append(Vector((0.0, 0.0, r)))
                    continue
                verts.append(Vector((r * math.cos(e) * math.cos(a), r * math.cos(e) * math.sin(a), r * math.sin(e))))
    per_shell = rings * segments + 1

    def idx(shell, i, j):
        return shell * per_shell + (rings * segments if i == rings else i * segments + j % segments)

    for shell in (0, 1):
        for i in range(rings):
            for j in range(segments):
                if i == rings - 1:
                    faces.append((idx(shell, i, j), idx(shell, i, j + 1), idx(shell, rings, 0)))
                else:
                    faces.append((idx(shell, i, j), idx(shell, i, j + 1), idx(shell, i + 1, j + 1), idx(shell, i + 1, j)))
    for j in range(segments):  # the rim joins the two shells
        faces.append((idx(0, 0, j), idx(1, 0, j), idx(1, 0, j + 1), idx(0, 0, j + 1)))
    return verts, faces


def _crest(pebble):
    """(verts, faces, face_materials, origin): the dorsal crest as a closed slab in the x = 0 plane.
    Material 0 is the membrane, 1 the threat-coloured points."""
    y0, y1 = CREST_SPAN
    n = CREST_POINTS * 4  # columns: valley, rise, point, fall per point, then the last valley
    columns = []
    for c in range(n + 1):
        u = c / n
        y = y0 + (y1 - y0) * u
        phase = (c % 4) / 4.0  # 0 valley, 0.25 rising, 0.5 point, 0.75 falling
        lift = {0.0: 0.0, 0.25: 0.55, 0.5: 1.0, 0.75: 0.45}[phase]
        end_fade = 0.55 + 0.45 * math.sin(math.pi * u)  # lower at the ends of the crest
        height = (CREST_VALLEY + (CREST_TIP - CREST_VALLEY) * lift) * end_fade
        base = Vector((0.0, y, pebble.top_z(0.0, y) - CREST_SINK))
        top = Vector((0.0, y - CREST_RAKE * lift, pebble.top_z(0.0, y) + height))
        # The top edge thins to CREST_THICKNESS[1] at the points and to about half the base's
        # thickness in the valleys.
        thick = CREST_THICKNESS[1] + (CREST_THICKNESS[0] - CREST_THICKNESS[1]) * (1.0 - lift) * 0.5
        columns.append((base, top, thick, lift))
    rows = 4  # base .. top
    verts, faces, mats = [], [], []
    grid = {}
    for side, sx in ((0, -1.0), (1, 1.0)):
        for c, (base, top, thick, _) in enumerate(columns):
            for r in range(rows + 1):
                v = r / rows
                p = base.lerp(top, v)
                half = (CREST_THICKNESS[0] + (thick - CREST_THICKNESS[0]) * v) / 2.0
                grid[(side, c, r)] = len(verts)
                verts.append(Vector((sx * half, p.y, p.z)))
    for c in range(n):
        point = max(columns[c][3], columns[c + 1][3]) >= 0.5
        for r in range(rows):
            mat = 1 if point and r >= rows // 2 else 0
            for side in (0, 1):
                quad = (grid[(side, c, r)], grid[(side, c + 1, r)], grid[(side, c + 1, r + 1)], grid[(side, c, r + 1)])
                faces.append(quad if side == 1 else tuple(reversed(quad)))
                mats.append(mat)
        # The top edge and the buried base edge join the two sides.
        faces.append((grid[(0, c, rows)], grid[(1, c, rows)], grid[(1, c + 1, rows)], grid[(0, c + 1, rows)]))
        mats.append(1 if point else 0)
        faces.append((grid[(0, c, 0)], grid[(0, c + 1, 0)], grid[(1, c + 1, 0)], grid[(1, c, 0)]))
        mats.append(0)
    for c in (0, n):  # end caps
        for r in range(rows):
            faces.append((grid[(0, c, r)], grid[(0, c, r + 1)], grid[(1, c, r + 1)], grid[(1, c, r)]))
            mats.append(0)
    mid = (y0 + y1) / 2.0
    origin = Vector((0.0, mid, pebble.top_z(0.0, mid)))
    return verts, faces, mats, origin


def build_rammer_body():
    body_mat = bc.material("M_RammerBody", (1.0, 1.0, 1.0), 0.5, vertex_colors="RammerColor")
    eye_mat = bc.material("M_RammerEye", linear(CREAM), 0.08)
    pupil_mat = bc.material("M_RammerPupil", linear(DEEP_SHADOW), 0.2)
    lid_mat = bc.material("M_RammerLid", linear(RAMMER_LID), 0.65)
    hood_mat = bc.material("M_RammerHood", linear(RAMMER_BAND), 0.6)
    threat_mat = bc.material("M_Threat", linear(THREAT), 0.45)
    pebble = LengthwisePebble(_rammer_top, _rammer_bottom, RAMMER_ROUND)
    verts, faces = pebble.mesh(RAMMER_SEGMENTS, _rammer_ring_ys())
    body = bc.mesh_object("Body", verts, faces, [body_mat], vertex_colors=("RammerColor", [_rammer_color(v) for v in verts]))
    er = RAMMER_EYE_RADIUS
    for side, sx in (("L", -1.0), ("R", 1.0)):
        d = Vector((sx * RAMMER_EYE_DIR[0], RAMMER_EYE_DIR[1], RAMMER_EYE_DIR[2])).normalized()
        surface = pebble.surface_point(d)
        centre = surface - d * RAMMER_EYE_SINK
        ev, ef = ellipsoid((er, er, er), centre, 3)
        eye = local_mesh(f"Eye_{side}", ev, ef, [eye_mat], centre, body)
        gaze = Vector((sx * 0.45, 1.0, 0.2)).normalized()
        rot = gaze.to_track_quat("Y", "Z").to_matrix()
        pv, pf = ellipsoid((0.042, 0.012, 0.042), centre + gaze * (er - 0.006), 2, rot)
        local_mesh(f"Pupil_{side}", pv, pf, [pupil_mat], centre, eye)
        # An upper lid set back over the eye and slanting down toward the middle of the face: a frown.
        lv, lf = _lid(er, 0.012)
        frown = Matrix.Rotation(sx * math.radians(-RAMMER_LID_FROWN_DEG), 3, Vector((0.0, 1.0, 0.0)))
        tilt = Matrix.Rotation(math.radians(RAMMER_LID_TILT_DEG), 3, Vector((1.0, 0.0, 0.0)))
        lid_rot = rot @ frown @ tilt
        local_mesh(f"Lid_{side}", [centre + lid_rot @ v for v in lv], lf, [lid_mat], centre, eye)
    cv, cf, cm, origin = _crest(pebble)
    local_mesh("Hood", cv, cf, [hood_mat, threat_mat], origin, body, face_materials=cm, smooth=False, fix_normals=True)
    fields = _frame_fields(verts)
    fields.update({
        "purpose": "M1 step 3 territorial rammer body (role: territorial): a pale domed pebble with three dark bands, a dorsal crest with threat-coloured points and frowning lids. Body only; its spikes and other parts come from the part GLBs.",
        "category": "creature_body",
        "dependencies": ["assets/export/M_RammerBody.tres"],
        "vertex_colors_attribute": "RammerColor",
        "pivot": "body centre on the swim plane (Godot y = 0); built at size 1, the creature view scales it by the species' body_size",
        "pose_nodes": {
            "Eye_L": "child of Body, origin at the eye's centre (with Pupil_L and Lid_L)",
            "Eye_R": "as Eye_L",
            "Hood": "child of Body: the dorsal crest, origin at the middle of its base on the back; scale its up axis (Godot +Y) to raise it in the puff",
        },
        "vertex_colors": {
            "attribute": "RammerColor",
            "encoding": "sRGB-encoded in COLOR_0; the engine material sets vertex_color_is_srgb (assets/export/M_RammerBody.tres)",
            "note": "Pale sand with three dark bands across the back that fade down the flanks, a cream belly.",
            "sand": RAMMER_SAND, "band": RAMMER_BAND, "belly": CREAM,
        },
    })
    return fields


# --- Spike part -------------------------------------------------------------------------------


def build_spike():
    root = bc.material("M_SpikeRoot", linear(SPIKE_ROOT), 0.6)
    shaft = bc.material("M_SpikeShaft", linear(THREAT), 0.45)
    tip = bc.material("M_SpikeTip", linear(SPIKE_TIP), 0.35)
    end = SPIKE_LENGTH - PART_EMBED
    profile = [(-PART_EMBED, 0.0), (-PART_EMBED, SPIKE_RADIUS), (0.0, SPIKE_RADIUS * 1.04), (0.018, SPIKE_RADIUS * 0.96)]
    steps = 8
    for i in range(1, steps):
        t = i / steps
        profile.append((0.018 + (end - 0.018) * t, SPIKE_RADIUS * 0.9 * (1.0 - t) ** 1.15))
    profile.append((end, 0.0))
    verts, faces, bands = bc.revolve(profile, 14)
    # A bone collar at the root, the threat colour along the shaft, darkening to the point.
    face_materials = [0 if b <= 2 else (2 if b >= len(profile) - 4 else 1) for b in bands]
    bc.mesh_object("Spike", verts, faces, [root, shaft, tip], face_materials)
    pts = bc.world_vertices()
    y_min = min(p.y for p in pts)
    y_max = max(p.y for p in pts)
    _check(y_min >= -0.05, "spike: sinks at most 0.05 m behind its attachment point")
    _check(abs(y_max - end) < 1e-6, "spike: the point is SPIKE_LENGTH - PART_EMBED out")
    return {
        "purpose": "M1 step 3 spike part (rams): a tapered thorn in the threat colour with a bone collar, darkening to its point.",
        "category": "part",
        "part_type": "spike",
        "attachment": dict(PART_ATTACHMENT),
        "length_m": SPIKE_LENGTH,
        "tip_m": round(y_max, 3),
    }


# --- Driver -----------------------------------------------------------------------------------

# asset id -> (builder, triangle budget); the budgets are the step 3 plan's (section 17).
ASSETS = {
    "creature_ambush_body": (build_ambush_body, 4000),
    "creature_rammer_body": (build_rammer_body, 4000),
    "part_spike": (build_spike, 600),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the M1 step 3 threat blockouts.")
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
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
