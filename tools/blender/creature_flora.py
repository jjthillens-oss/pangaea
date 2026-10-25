"""The creature world's flora and rock kit (PROPOSED; docs/art/creature_world_dressing.md), built through
tools/blender/make_creature_world.py, which lists these builders in its ASSETS (so its CLAUDE.md command line,
`python tools/blender/make_creature_world.py [--only id[,id...]]`, builds them too) and writes their engine material
and import options in --import. Original designs; 1 m = 1 unit, the pivot on the ground at the asset's centre
(Blender z = 0, Godot y = 0), Blender +Y forward.

Meadow cards, low walk-through cover for inside the walls (every card stays under 0.45 m, the field's dressing
rule in tests/test_creature_world_art.gd, because the sim has no obstacles yet):
- T_MeadowCards (assets/export/creature_flora/T_MeadowCards.png): one 1024 px RGBA numpy atlas in a 4 x 4 grid of
  256 px cells (CELL_PAINTERS): six grass fans (meadow, tall, short, sage, sedge, fine), three fern fronds (broad,
  narrow, young), five flower sprigs (lilac bells, blue and cream stars, cream umbels, blue bells, fine grass with
  lilac stars) and two broad-leaf cells (a rosette and clover). RGB is the authored colour, painted as strokes in
  CIE LCh so every green keeps hue 139 or more (25 degrees from the food green 114) and no amber or yellow appears
  (they read as fruit); A is the anti-aliased cut-out. Alpha is zero within 4 px of each cell's edge, and under the
  alpha the RGB is the nearest leaf colour pushed outward, so mips and bilinear taps never pull in black or the
  next cell. Cream florets carry a thin near-neutral rim, so their edges blend into the green through grey.
- M_MeadowCards (assets/export/M_MeadowCards.tres, mapped in each card GLB's .import): a StandardMaterial3D, so
  the field can carry merged copies of the cards beside its own ShaderMaterial and still pass test_assets: the atlas
  cut out at 0.5, times the mesh's COLOR_0 (each card's brightness jitter; a scatter can darken a whole clump the
  same way). Every card is two sheets back to back with back faces culled, each sheet's normals leaned toward world
  up, so both sides of a card light like the ground they grow from (one sheet drawn from both sides gets its normal
  flipped for the back face and shades black there). The card GLBs link the atlas by a relative URI (link_atlas,
  run after export) instead of embedding a copy, so the repository holds one atlas, not one per GLB.
- creature_grass_tuft (48 triangles), creature_fern_clump (96) and creature_flower_clump (72): bent two-sided cards
  of two or three segments, which cast no shadow and keep no LODs (the import options; Godot's LOD pass eats whole
  cards).

Rocks, baked like the other world assets (procedural Blender shaders to Albedo, ORM and Normal textures, normals
from the full-detail shape):
- creature_pebble_cluster: seven half-sunk pebbles of 3 to 12 cm in warm grey; walk-through cover.
- creature_boulder_a, _b, _c: rounded boulders of about 1.0, 1.8 and 3.0 m, with soft cleavage facets and moss on
  their up-facing tops. They stand OUTSIDE the walls only (on the berm and the hills) until the sim has obstacles.
  Grain and height come from the CC0 Poly Haven "Rock Boulder Dry" scan in
  assets/source/textures/cc0/polyhaven_rock_boulder_dry/ (box-projected, recoloured to the palette, baked; never
  shown raw), logged in each boulder's record. Stone is a cool blue-grey (hue 250 to 256, chroma about 3), moss a
  blue meadow green (hue 143 to 152); a blend of the two (a far mip, the bake's filter) runs through teal, never
  through the food green's hue, and the edge between them passes through a near-neutral damp grey.
"""
import math
import os
import random

import bpy  # noqa: F401  (imported first by make_creature_world through blockout_common)
import numpy as np
from mathutils import Vector, noise

import blockout_common as bc
import make_m1_production as mp
import surfacing as sf

ROOT = bc.ROOT
FLORA_DIR = os.path.join(ROOT, "assets", "export", "creature_flora")
ATLAS = "T_MeadowCards"
ATLAS_PATH = "assets/export/creature_flora/T_MeadowCards.png"
ATLAS_PX = 1024
CELL = 256
COLS, ROWS = 4, 4
ROOT_PX = 14                 # where blades and stems leave the ground, px above a cell's bottom edge
VC = "Jitter"                # the cards' colour attribute (COLOR_0): a greyscale brightness per card
NORMAL_UP = 1.4              # how much of world up is added to a card's face normal
SHEET_GAP = 0.0012           # a card's two sheets stand this far apart, so a ray tracer meets the near one first
COVER_MAX_M = 0.45           # walk-through cover stands under this (tests/test_creature_world_art.gd)
FOOD_GREEN_H = 114.4
THREAT_PINK_H = 11.1
HUE_GAP = 25.0
CHROMA_MIN = 8.0
SCAN_DIR = "assets/source/textures/cc0/polyhaven_rock_boulder_dry"
SCAN_M = 1.6                 # one scan tile per 1.6 m of stone, the same grain size on every boulder
SCAN_DEPENDENCY = {
    "path": SCAN_DIR, "asset": "Rock Boulder Dry", "source_url": "https://polyhaven.com/a/rock_boulder_dry",
    "files": ["rock_boulder_dry_diff_1k.jpg", "rock_boulder_dry_disp_1k.jpg"],
    "license": "CC0 1.0 (https://polyhaven.com/license)",
    "authors": "Dimitrios Savva (photography), Rico Cilliers (processing)",
    "retrieved": "kept in the repository since the M1 production rocks (docs/art/production_m1.md)",
    "use": "grain (the diffuse scan's luminance, recoloured to the palette) and height (the displacement scan, as bump), box-projected on the boulder and baked; the scan's own colour is never shown"}
PROVENANCE_CARDS = ("Authored procedurally by tools/blender/creature_flora.py (through make_creature_world.py); no "
                    "external or generated meshes. The card atlas is painted in numpy (strokes in CIE LCh); no scans.")
PROVENANCE_PEBBLES = ("Authored procedurally by tools/blender/creature_flora.py (through make_creature_world.py); no "
                      "external or generated meshes. Textures baked in Blender from procedural shaders; no scans.")
PROVENANCE_BOULDER = ("Authored procedurally by tools/blender/creature_flora.py (through make_creature_world.py); no "
                      "external or generated meshes. Textures baked in Blender from procedural shaders over the CC0 "
                      "Poly Haven Rock Boulder Dry scan (grain and height only, recoloured; see dependencies).")


def _lin(hex_color):
    return mp._lin(hex_color)


# --- Colour (CIE LCh, D65) ------------------------------------------------------------------------------------

def lch_srgb(L, C, h):
    """CIE LCh to display sRGB in [0, 1] (arrays or scalars)."""
    L, C, h = np.asarray(L, float), np.asarray(C, float), np.asarray(h, float)
    a, b = C * np.cos(np.radians(h)), C * np.sin(np.radians(h))
    fy = (L + 16.0) / 116.0
    d = 6.0 / 29.0
    finv = lambda f: np.where(f > d, f ** 3, 3.0 * d * d * (f - 4.0 / 29.0))   # noqa: E731
    xyz = np.stack([finv(fy + a / 500.0) * 0.95047, finv(fy), finv(fy - b / 200.0) * 1.08883], -1)
    m = np.array([[3.2404542, -1.5371385, -0.4985314], [-0.9692660, 1.8760108, 0.0415560], [0.0556434, -0.2040259, 1.0572252]])
    lin = np.clip(xyz @ m.T, 0.0, 1.0)
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1.0 / 2.4) - 0.055)


def srgb_lch(rgb):
    """Display sRGB (..., 3) in [0, 1] to CIE L, C, h arrays."""
    rgb = np.asarray(rgb, float)
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
    xyz = lin @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), xyz / 0.128418 + 4.0 / 29.0)
    L = 116.0 * f[..., 1] - 16.0
    a, b = 500.0 * (f[..., 0] - f[..., 1]), 200.0 * (f[..., 1] - f[..., 2])
    return L, np.hypot(a, b), np.degrees(np.arctan2(b, a)) % 360.0


def hue_clash(rgb, alpha=None):
    """The share of opaque (alpha 0.5 or more), chromatic (C 8 or more) texels within 25 degrees of hue of the food
    green or the threat pink."""
    L, C, h = srgb_lch(rgb)
    keep = C >= CHROMA_MIN
    if alpha is not None:
        keep &= alpha >= 0.5
    gap = lambda ref: np.minimum(np.abs(h - ref), 360.0 - np.abs(h - ref))   # noqa: E731
    bad = keep & ((gap(FOOD_GREEN_H) < HUE_GAP) | (gap(THREAT_PINK_H) < HUE_GAP))
    return float(bad.sum()) / max(1, int(keep.sum()))


# --- The meadow card atlas (numpy) -------------------------------------------------------------------------------

def _stroke(xx, yy, pts, half, soft=1.1):
    """A tapered stroke along the polyline `pts` ((k, 2) px, display order: x right, y down) with half-widths
    `half` (k,). Returns, over the grid, the anti-aliased coverage, the position along the stroke of the nearest
    centre-line point (0 base, 1 tip) and the signed distance across as a share of the local half-width."""
    pts = np.asarray(pts, float)
    half = np.asarray(half, float)
    seg = np.diff(pts, axis=0)
    seg_len = np.maximum(np.linalg.norm(seg, axis=1), 1e-9)
    cum = np.concatenate([[0.0], np.cumsum(seg_len)])
    total = cum[-1]
    best = np.full(xx.shape, -1e9)
    t_out = np.zeros(xx.shape)
    across_out = np.zeros(xx.shape)
    for i in range(len(seg)):
        ax, ay = pts[i]
        dx, dy = seg[i] / seg_len[i]
        px, py = xx - ax, yy - ay
        s = np.clip((px * dx + py * dy) / seg_len[i], 0.0, 1.0)
        cx, cy = ax + s * seg[i][0], ay + s * seg[i][1]
        side = (xx - cx) * (-dy) + (yy - cy) * dx
        dist = np.hypot(xx - cx, yy - cy)
        hw = half[i] + (half[i + 1] - half[i]) * s
        inside = hw - dist
        win = inside > best
        best = np.where(win, inside, best)
        t_out = np.where(win, (cum[i] + s * seg_len[i]) / total, t_out)
        across_out = np.where(win, side / np.maximum(hw, 1e-6), across_out)
    alpha = np.clip(best / soft + 0.5, 0.0, 1.0)
    return alpha, t_out, np.clip(across_out, -1.0, 1.0)


class _Cell:
    """One atlas cell being painted, back to front: RGB in display sRGB and the coverage."""

    def __init__(self, rng, under_lch, n=CELL):
        self.n = n
        self.rng = rng
        self.yy, self.xx = np.mgrid[0:n, 0:n].astype(np.float64) + 0.5
        self.rgb = np.empty((n, n, 3))
        self.rgb[...] = lch_srgb(*under_lch)
        self.alpha = np.zeros((n, n))
        edge = np.minimum(np.minimum(self.xx, n - self.xx), np.minimum(self.yy, n - self.yy))
        self.margin = np.clip((edge - 4.5) / 6.0, 0.0, 1.0)     # zero within 4 px of the cell's edge

    def paint(self, pts, half, colour, shadow=0.22):
        """Lays a stroke over what is painted (straight-alpha "over", so the underlay never tints an edge);
        `colour(t, across)` gives its sRGB. The stroke throws a soft contact shadow, a few px wide, on the strokes
        under it, so overlapping blades read in depth."""
        x0, y0 = np.min(pts, axis=0) - np.max(half) - 6
        x1, y1 = np.max(pts, axis=0) + np.max(half) + 6
        sl = (slice(max(0, int(y0)), min(self.n, int(y1) + 1)), slice(max(0, int(x0)), min(self.n, int(x1) + 1)))
        a, t, across = _stroke(self.xx[sl], self.yy[sl], pts, half)
        a = a * self.margin[sl]
        a_wide, _, _ = _stroke(self.xx[sl], self.yy[sl], pts, np.asarray(half) + 3.0)
        under = self.alpha[sl]
        band = np.clip(a_wide - a, 0.0, 1.0) * under
        rgb = self.rgb[sl] * (1.0 - shadow * band)[..., None]
        out_a = a + under * (1.0 - a)
        mix = np.where(out_a > 1e-6, a / np.maximum(out_a, 1e-6), 1.0)
        self.rgb[sl] = rgb * (1.0 - mix)[..., None] + colour(t, across) * mix[..., None]
        self.alpha[sl] = out_a

    def inside(self, pts, pad=13.0):
        pts = np.asarray(pts)
        return (pts[:, 0].min() >= pad and pts[:, 0].max() <= self.n - pad and pts[:, 1].min() >= pad
                and pts[:, 1].max() <= self.n - ROOT_PX + 2)

    def finish(self):
        """Pushes the nearest leaf colour out under the cut-away area (a push-pull fill weighted by coverage), so
        a mip or a bilinear tap at an edge blends toward the leaf, never toward the underlay or the next cell."""
        w = np.clip(self.alpha * 4.0, 0.0, 1.0)
        filled = self.rgb.copy()
        done = self.alpha >= 0.02
        cur_rgb, cur_w = self.rgb * w[..., None], w
        for r in (1, 2, 4, 8, 16, 32):
            cur_rgb, cur_w = _box(cur_rgb, r), _box(cur_w, r)
            ok = ~done & (cur_w > 1e-4)
            filled[ok] = cur_rgb[ok] / cur_w[ok][..., None]
            done |= ok
        return np.concatenate([np.clip(filled, 0.0, 1.0), self.alpha[..., None]], axis=-1)


def _box(a, r):
    """A clamped (not wrapped) box blur of radius r."""
    out = a
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (r, r)
        p = np.pad(out, pad, mode="edge")
        c = np.cumsum(p, axis=axis)
        c = np.concatenate([np.zeros_like(np.take(c, [0], axis=axis)), c], axis=axis)
        n = out.shape[axis]
        out = (np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, range(0, n), axis=axis)) / (2 * r + 1)
    return out


def _arc(root, angle, length, bend, steps=10, curl=1.6):
    """A curved centre line from `root` (display px), leaving at `angle` radians from straight up (positive leans
    right) and turning by `bend` radians toward the tip."""
    pts = [np.array(root, float)]
    step = length / steps
    for k in range(1, steps + 1):
        a = angle + bend * (k / steps) ** curl
        pts.append(pts[-1] + step * np.array([math.sin(a), -math.cos(a)]))
    return np.array(pts)


def _lch_colour(L0, L1, C, h, rib=3.0, edge=6.0):
    """A leaf's colour: darker at the base (L0) to its tip (L1), a lighter mid-rib, darker rounded edges."""
    def colour(t, across):
        L = L0 + (L1 - L0) * t ** 0.7 + rib * (1.0 - np.abs(across)) ** 4 - edge * across ** 2
        return lch_srgb(L, np.full_like(t, C), np.full_like(t, h))
    return colour


GRASS_KINDS = {
    # blades, length (share of the cell), half-width px, lean sigma, hue range, chroma, L base and tip
    "meadow": {"blades": 22, "length": (0.48, 0.86), "half": (3.2, 4.6), "lean": 0.30, "hue": (141.0, 148.0), "chroma": (28.0, 34.0), "L": (30.0, 58.0)},
    "tall": {"blades": 15, "length": (0.70, 0.92), "half": (2.8, 3.8), "lean": 0.40, "hue": (144.0, 151.0), "chroma": (27.0, 33.0), "L": (31.0, 60.0)},
    "short": {"blades": 30, "length": (0.34, 0.64), "half": (3.0, 4.2), "lean": 0.34, "hue": (146.0, 154.0), "chroma": (28.0, 35.0), "L": (29.0, 56.0)},
    "sage": {"blades": 19, "length": (0.45, 0.82), "half": (3.6, 5.2), "lean": 0.28, "hue": (141.0, 147.0), "chroma": (17.0, 23.0), "L": (34.0, 62.0)},
    "sedge": {"blades": 12, "length": (0.5, 0.86), "half": (5.5, 7.5), "lean": 0.36, "hue": (148.0, 155.0), "chroma": (26.0, 31.0), "L": (27.0, 52.0)},
    "fine": {"blades": 44, "length": (0.4, 0.85), "half": (1.7, 2.5), "lean": 0.32, "hue": (141.0, 147.0), "chroma": (19.0, 25.0), "L": (36.0, 64.0)},
}


def _blades(cell, rng, k, count=None):
    """Paints a fan of grass blades rising from a tight base at the cell's bottom centre: tapered, curved strokes,
    each with its own hue in the kind's band, darker toward the base (occlusion, not light)."""
    root_y = CELL - ROOT_PX
    blades = []
    while len(blades) < (count or k["blades"]):
        off = rng.normal(0.0, CELL * 0.055)
        angle = rng.normal(0.0, k["lean"]) + off / (CELL * 0.3)
        length = CELL * rng.uniform(*k["length"])
        bend = rng.normal(0.0, 0.35) + 0.4 * angle
        pts = _arc((CELL / 2 + off, root_y), angle, length, bend)
        if not cell.inside(pts):
            continue
        blades.append((pts, rng.uniform(*k["half"]), rng.uniform(*k["hue"]), rng.uniform(*k["chroma"]), rng.uniform(-5.0, 5.0)))
    blades.sort(key=lambda b: b[4])                               # darker blades at the back
    for pts, w, h, c, tone in blades:
        t = np.linspace(0.0, 1.0, len(pts))
        cell.paint(pts, w * (1.0 - t) ** 0.75 + 0.45, _lch_colour(k["L"][0] + tone, k["L"][1] + tone, c, h))


def _grass_cell(rng, kind):
    k = GRASS_KINDS[kind]
    cell = _Cell(rng, (44.0, sum(k["chroma"]) / 2, sum(k["hue"]) / 2))
    _blades(cell, rng, k)
    return cell.finish()


def _fern_cell(rng, kind):
    """A fern frond seen from above, its base at the cell's bottom: a curved rachis with paired, comb-lobed pinnae,
    longest a third of the way up, sweeping toward the tip, with gaps between them so the frond reads as a fern and
    not as one leaf. "broad" has eleven pairs, "narrow" fifteen shorter ones, "young" eight, lighter and more
    upright."""
    pairs, reach, sweep0, lift, hue0 = {"broad": (11, 0.96, 66.0, 0.0, 142.0), "narrow": (15, 0.72, 72.0, 0.0, 143.0),
                                        "young": (8, 0.7, 56.0, 6.0, 140.5)}[kind]
    cell = _Cell(rng, (42.0 + lift, 30.0, hue0 + 3.0))
    root = (CELL / 2, CELL - ROOT_PX)
    sway = rng.uniform(-0.22, 0.22)
    length_px = (CELL - ROOT_PX - 16.0) * (0.86 if kind == "young" else 1.0)
    rachis = _arc(root, sway * 0.4, length_px, sway, steps=16, curl=1.3)
    reach *= CELL / 2 - 16.0
    spacing = 0.86 * length_px / (pairs - 1)
    seg = np.diff(rachis, axis=0)
    pinnae = []
    for i in range(pairs):
        for side in (-1.0, 1.0):
            t = 0.1 + 0.86 * (i + (0.3 if side > 0 else 0.0)) / (pairs - 1)   # sub-opposite, as many ferns are
            if t > 0.985:
                continue
            j = min(len(seg) - 1, int(t * len(seg)))
            base = rachis[j] + seg[j] * (t * len(seg) - j)
            tangent = seg[j] / np.linalg.norm(seg[j])
            up_angle = math.atan2(tangent[0], -tangent[1])        # the rachis's own lean
            size = math.sin(math.pi * min(1.0, 0.18 + t * 0.95)) ** 0.8 * (1.0 - 0.3 * t)
            sweep = (math.radians(sweep0) - math.radians(30.0) * t) * side
            length = reach * size * rng.uniform(0.9, 1.05)
            pts = _arc(base, up_angle + sweep, max(length, 5.0), -side * rng.uniform(0.15, 0.35), steps=8)
            while not cell.inside(pts, pad=11.0) and length > 5.0:
                length *= 0.94
                pts = _arc(base, up_angle + sweep, length, -side * 0.25, steps=8)
            pinnae.append((pts, length, t, rng.uniform(-3.0, 3.0)))
    lobes = 6.0 if kind == "narrow" else 8.0
    for pts, length, t, tone in pinnae:
        u = np.linspace(0.0, 1.0, 33)
        line = np.stack([np.interp(u, np.linspace(0.0, 1.0, len(pts)), pts[:, d]) for d in (0, 1)], axis=1)
        width = min(0.13 * length, 0.42 * spacing)
        notch = 0.45 + 0.55 * np.abs(np.sin(u * math.pi * max(2.0, lobes * length / reach))) ** 0.6
        half = width * np.sin(math.pi * np.clip(u * 0.94 + 0.05, 0.0, 1.0)) ** 0.55 * notch + 0.5
        cell.paint(line, half, _lch_colour(34.0 + lift + 8.0 * t + tone, 50.0 + lift + 6.0 * t + tone, 33.0, hue0 + 6.0 * t, rib=5.0, edge=7.0), shadow=0.18)
    t = np.linspace(0.0, 1.0, len(rachis))
    cell.paint(rachis, 2.6 * (1.0 - t) + 0.8, _lch_colour(30.0, 44.0, 26.0, 141.0, rib=4.0, edge=3.0), shadow=0.1)
    return cell.finish()


def _leaves_at_foot(cell, rng, count, width=4.6, reach=(0.22, 0.4)):
    """Short leaves fanning from the cell's bottom centre, under a flower's stems."""
    leaves = []
    while len(leaves) < count:
        off = rng.normal(0.0, CELL * 0.05)
        angle = rng.normal(0.0, 0.55) + off / (CELL * 0.25)
        pts = _arc((CELL / 2 + off, CELL - ROOT_PX), angle, CELL * rng.uniform(*reach), 0.5 * angle + rng.normal(0.0, 0.3))
        if cell.inside(pts):
            leaves.append(pts)
    for pts in leaves:
        t = np.linspace(0.0, 1.0, len(pts))
        cell.paint(pts, width * (1.0 - t) ** 0.7 + 0.5, _lch_colour(32.0, 52.0, 30.0, rng.uniform(142.0, 149.0)))


def _stems(cell, rng, count, spread, length, pad):
    stems = []
    while len(stems) < count:
        off = rng.normal(0.0, CELL * 0.04)
        angle = (len(stems) - (count - 1) / 2) * spread + rng.normal(0.0, 0.08)
        pts = _arc((CELL / 2 + off, CELL - ROOT_PX), angle, CELL * rng.uniform(*length), rng.normal(0.0, 0.25) + 0.3 * angle)
        if cell.inside(pts, pad=pad):
            stems.append(pts)
    for pts in stems:
        t = np.linspace(0.0, 1.0, len(pts))
        cell.paint(pts, 1.9 * (1.0 - t) + 0.9, _lch_colour(34.0, 46.0, 24.0, 144.0, rib=2.0, edge=2.0), shadow=0.12)
    return stems


def _star(cell, rng, centre, size, hue, L, C, petals=6):
    """A round flower head tilted to the view: petals radiating from a dark violet eye."""
    spin = rng.uniform(0.0, math.tau)
    for p in range(petals):
        a = spin + math.tau * p / petals
        tip = centre + np.array([math.cos(a), math.sin(a) * 0.62]) * size
        line = np.stack([centre + (tip - centre) * f for f in np.linspace(0.12, 1.0, 6)])
        u = np.linspace(0.0, 1.0, 6)
        cell.paint(line, size * 0.34 * np.sin(math.pi * np.clip(u * 0.85 + 0.12, 0.0, 1.0)) ** 0.5 + 0.6,
                   _lch_colour(L - 8.0, L, C, hue, rib=2.0, edge=5.0), shadow=0.1)
    eye = np.stack([centre, centre + np.array([0.01, 0.0])])
    cell.paint(eye, np.full(2, max(2.4, size * 0.24)), _lch_colour(30.0, 34.0, 28.0, 300.0, rib=4.0, edge=2.0), shadow=0.05)


def _bells(cell, rng, pts, count, size, hue, L0, top=0.52):
    """Bells hanging alternately left and right along the upper part of a stem, and a closed bud at its tip."""
    seg = np.diff(pts, axis=0)
    for b in range(count):
        t = top + (0.98 - top) * b / max(1, count - 1)
        j = min(len(seg) - 1, int(t * len(seg)))
        at = pts[j] + seg[j] * (t * len(seg) - j)
        side = 1.0 if b % 2 else -1.0
        hang = np.array([side * 0.75, 0.6])
        hang /= np.linalg.norm(hang)
        length = size * (1.0 - 0.3 * t) + rng.uniform(-1.0, 1.0)
        line = np.stack([at + hang * length * f for f in np.linspace(0.0, 1.0, 6)])
        u = np.linspace(0.0, 1.0, 6)
        half = (0.15 + 0.3 * u ** 0.8) * length * (1.0 - 0.3 * u ** 6) + 0.4
        L = L0 + rng.uniform(-4.0, 4.0)
        cell.paint(line, half, _lch_colour(L - 14.0, L + 4.0, 33.0, hue + rng.uniform(-3.0, 3.0), rib=0.0, edge=7.0), shadow=0.12)
    bud = np.stack([pts[-1], pts[-1] + np.array([0.0, -size * 0.45])])
    cell.paint(bud, np.array([size * 0.2, size * 0.11]), _lch_colour(L0 - 14.0, L0 - 8.0, 30.0, hue, rib=0.0, edge=4.0), shadow=0.05)


def _flower_cell(rng, kind):
    """Wildflower sprigs over leaves at their foot. "lilac_bells" and "blue_bells" hang bells along curved stems;
    "stars" carries round heads in sky blue and cream with a dark violet eye; "umbels" carries domes of small cream
    florets on spokes; "mix" is fine grass with a few small lilac stars. No amber or yellow: those read as fruit."""
    cell = _Cell(rng, (42.0, 28.0, 146.0))
    if kind == "mix":
        _blades(cell, rng, GRASS_KINDS["fine"], 30)
        for pts in _stems(cell, rng, 3, 0.3, (0.5, 0.72), 26.0):
            _star(cell, rng, pts[-1], rng.uniform(10.0, 12.0), rng.uniform(300.0, 306.0), rng.uniform(60.0, 66.0), 32.0, petals=5)
        return cell.finish()
    _leaves_at_foot(cell, rng, 7)
    if kind in ("lilac_bells", "blue_bells"):
        lilac = kind == "lilac_bells"
        for pts in _stems(cell, rng, 4, 0.3, (0.55, 0.8), 24.0):
            _bells(cell, rng, pts, int(rng.integers(5, 8)) if lilac else int(rng.integers(3, 5)), 17.0 if lilac else 21.0,
                   304.0 if lilac else 265.0, 60.0 if lilac else 56.0, top=0.52 if lilac else 0.68)
    elif kind == "stars":
        for s, pts in enumerate(_stems(cell, rng, 6, 0.22, (0.55, 0.8), 34.0)):
            blue = s % 2 == 0
            hue, L, C = (rng.uniform(264.0, 271.0), rng.uniform(62.0, 69.0), 30.0) if blue else (rng.uniform(80.0, 86.0), rng.uniform(87.0, 91.0), 13.0)
            _star(cell, rng, pts[-1], rng.uniform(15.0, 19.0), hue, L, C)
    elif kind == "umbels":
        for pts in _stems(cell, rng, 4, 0.3, (0.5, 0.72), 40.0):
            top = pts[-1]
            for f in range(int(rng.integers(15, 21))):
                a = math.radians(rng.uniform(-160.0, -20.0))
                spoke = np.array([math.cos(a), math.sin(a) * 0.8]) * rng.uniform(5.0, 24.0)
                end = top + spoke
                cell.paint(np.stack([top, end]), np.array([0.9, 0.7]), _lch_colour(38.0, 44.0, 22.0, 145.0, rib=0.0, edge=1.0), shadow=0.05)
                dot = np.stack([end, end + np.array([0.01, 0.0])])
                r = rng.uniform(4.2, 5.6)
                # A thin near-neutral rim first, so the cream's anti-aliased edge blends through grey into the green
                # behind it, never through a yellow-green.
                cell.paint(dot, np.full(2, r + 1.2), _lch_colour(58.0, 60.0, 3.0, 300.0, rib=0.0, edge=0.0), shadow=0.1)
                cell.paint(dot, np.full(2, r), _lch_colour(86.0, 90.0, 12.0, rng.uniform(80.0, 86.0), rib=3.0, edge=10.0), shadow=0.0)
    return cell.finish()


def _leaf_cell(rng, kind):
    """Broad foliage for under the flowers: "rosette", seven or eight wide leaves fanning from the base with a
    pale mid-rib; "clover", thin stems carrying three round leaflets each, seen at a tilt."""
    cell = _Cell(rng, (44.0, 30.0, 149.0))
    if kind == "rosette":
        leaves = []
        while len(leaves) < 8:
            angle = (-1.0 + 2.0 * len(leaves) / 7.0) * 1.0 + rng.normal(0.0, 0.12)   # fanned left to right
            off = rng.normal(0.0, CELL * 0.03)
            length = CELL * rng.uniform(0.3, 0.52) * (1.0 - 0.25 * abs(angle))
            pts = _arc((CELL / 2 + off, CELL - ROOT_PX), angle, length, 0.45 * angle + rng.normal(0.0, 0.2))
            width = rng.uniform(15.0, 21.0)
            if cell.inside(pts, pad=12.0 + width * 0.5):
                leaves.append((pts, width, rng.uniform(-4.0, 4.0), rng.uniform(146.0, 152.0)))
        leaves.sort(key=lambda leaf: leaf[2])
        for pts, width, tone, hue in leaves:
            t = np.linspace(0.0, 1.0, len(pts))
            half = width * np.sin(math.pi * np.clip(t * 0.9 + 0.08, 0.0, 1.0)) ** 0.7 + 0.6
            cell.paint(pts, half, _lch_colour(33.0 + tone, 52.0 + tone, 30.0, hue, rib=7.0, edge=8.0), shadow=0.25)
        return cell.finish()
    stems = []
    while len(stems) < 11:
        off = rng.normal(0.0, CELL * 0.06)
        angle = rng.normal(0.0, 0.45) + off / (CELL * 0.3)
        pts = _arc((CELL / 2 + off, CELL - ROOT_PX), angle, CELL * rng.uniform(0.25, 0.68), rng.normal(0.0, 0.3))
        if cell.inside(pts, pad=30.0):
            stems.append((pts, rng.uniform(-4.0, 4.0)))
    stems.sort(key=lambda s: -s[0][-1][1])                           # the lower heads are further back
    for pts, tone in stems:
        t = np.linspace(0.0, 1.0, len(pts))
        cell.paint(pts, 1.4 * (1.0 - t) + 0.8, _lch_colour(36.0, 46.0, 24.0, 146.0, rib=0.0, edge=1.0), shadow=0.1)
        spin = rng.uniform(-0.4, 0.4)
        hue = rng.uniform(148.0, 154.0)
        for k in range(3):
            a = spin - math.pi / 2 + math.tau * k / 3
            tip = pts[-1] + np.array([math.cos(a), math.sin(a) * 0.7]) * rng.uniform(13.0, 16.0)
            line = np.stack([pts[-1] + (tip - pts[-1]) * f for f in np.linspace(0.0, 1.0, 6)])
            u = np.linspace(0.0, 1.0, 6)
            cell.paint(line, 7.0 * np.sin(math.pi * np.clip(u * 0.8 + 0.18, 0.0, 1.0)) ** 0.5 + 0.6,
                       _lch_colour(38.0 + tone, 55.0 + tone, 30.0, hue, rib=3.0, edge=7.0), shadow=0.2)
    return cell.finish()


# The atlas's cells, in reading order (4 x 4): the builder for each, and which cards use them.
CELL_PAINTERS = (
    ("grass meadow", lambda rng: _grass_cell(rng, "meadow")), ("grass tall", lambda rng: _grass_cell(rng, "tall")),
    ("grass short", lambda rng: _grass_cell(rng, "short")), ("grass sage", lambda rng: _grass_cell(rng, "sage")),
    ("sedge", lambda rng: _grass_cell(rng, "sedge")), ("grass fine", lambda rng: _grass_cell(rng, "fine")),
    ("fern broad", lambda rng: _fern_cell(rng, "broad")), ("fern narrow", lambda rng: _fern_cell(rng, "narrow")),
    ("lilac bells", lambda rng: _flower_cell(rng, "lilac_bells")), ("blue and cream stars", lambda rng: _flower_cell(rng, "stars")),
    ("cream umbels", lambda rng: _flower_cell(rng, "umbels")), ("blue bells", lambda rng: _flower_cell(rng, "blue_bells")),
    ("leaf rosette", lambda rng: _leaf_cell(rng, "rosette")), ("fern young", lambda rng: _fern_cell(rng, "young")),
    ("clover", lambda rng: _leaf_cell(rng, "clover")), ("grass and lilac stars", lambda rng: _flower_cell(rng, "mix")),
)
GRASS_CELLS = (0, 1, 2, 3, 4, 5)
FERN_CELLS = (6, 7, 13)
FLOWER_CELLS = (8, 9, 10, 11, 15)
LEAF_CELLS = (12, 14)

_ATLAS_DONE = {}


def paint_atlas():
    """The atlas's RGBA (display order, row 0 at the top), with each cell's coverage and hue check."""
    rng = np.random.default_rng(5201)
    atlas = np.zeros((ATLAS_PX, ATLAS_PX, 4))
    for i, (name, painter) in enumerate(CELL_PAINTERS):
        rgba = painter(rng)
        col, row = i % COLS, i // COLS
        atlas[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL] = rgba
        share = float((rgba[..., 3] >= 0.5).mean())
        clash = hue_clash(rgba[..., :3], rgba[..., 3])
        mp._check(0.08 < share < 0.6, f"meadow atlas cell {i} ({name}): the cut-out covers a fair share of the card ({share:.2f})")
        mp._check(clash <= 0.01, f"meadow atlas cell {i} ({name}): {clash:.2%} of its chromatic texels sit near the food or threat hue")
        print(f"  meadow cell {i:2d} {name:22s} coverage {share:.2f}, hue clashes {clash:.2%}")
    return atlas


def meadow_atlas():
    """Writes T_MeadowCards once per run (the same seed every run, so the file is the same) and returns its
    record entry."""
    if "entry" in _ATLAS_DONE:
        return dict(_ATLAS_DONE["entry"])
    atlas = paint_atlas()
    px = np.ascontiguousarray(np.clip(atlas[::-1], 0.0, 1.0).astype(np.float32))   # Blender stores rows bottom-up
    img = bpy.data.images.new(ATLAS, ATLAS_PX, ATLAS_PX, alpha=True)
    img.colorspace_settings.name = "Non-Color"      # values are written as-is; the RGB is already sRGB-encoded
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(px.ravel())
    os.makedirs(FLORA_DIR, exist_ok=True)
    img.filepath_raw = os.path.join(FLORA_DIR, f"{ATLAS}.png")
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    _ATLAS_DONE["entry"] = {"name": ATLAS, "path": ATLAS_PATH, "size": [ATLAS_PX, ATLAS_PX], "colorspace": "sRGB",
                            "packing": "RGB the authored colour (CIE LCh greens at hue 139 or more; lilac, sky blue and cream flowers) in a 4 x 4 grid of 256 px cells: " + "; ".join(f"{i} {n}" for i, (n, _) in enumerate(CELL_PAINTERS)) + "; A the cut-out mask (alpha scissor at 0.5)"}
    return dict(_ATLAS_DONE["entry"])


# --- Cards --------------------------------------------------------------------------------------------------------

def _cell_uv(cell, flip, grid=(COLS, ROWS)):
    """The cell's UV rectangle in Blender's convention (v up; the atlas's top row is the high v half):
    (u at the left edge, u at the right edge, v at the base, v at the tip)."""
    cols, rows = grid
    col, row = cell % cols, cell // cols
    u0, u1 = col / cols, (col + 1) / cols
    v0, v1 = 1.0 - (row + 1) / rows, 1.0 - row / rows
    return (u1, u0, v0, v1) if flip else (u0, u1, v0, v1)


class _Cards:
    """Two-sided card strips gathered into one mesh: vertices, quads, a UV, a jitter colour and a lit normal per
    vertex. Each card is two sheets of quads back to back with opposite winding, 1.2 mm apart (coincident sheets
    confuse a ray tracer: Blender's review would skip the near sheet), each with its own normal leaned toward world
    up, and the material culls back faces: from either side the near sheet draws and lights like the ground. (A single sheet drawn from both sides cannot do that: the renderer flips its normal for the
    back face, so one side of every card would shade as if facing the soil.)"""

    def __init__(self, grid=(COLS, ROWS), lit=None):
        """`grid` is the atlas's (columns, rows). `lit(point) -> Vector`, when given, is the lit normal of both
        sheets at a vertex (a canopy shades as one rounded volume: the normal points out of the crown wherever a
        card faces); otherwise each sheet's own face normal plus NORMAL_UP x world up."""
        self.grid, self.lit = grid, lit
        self.verts, self.faces, self.uvs, self.cols, self.normals, self.facing = [], [], [], [], [], []

    def strip(self, centres, sides, half_width, cell, flip=False, shade=1.0):
        """A card along `centres` (base to tip, one row each) spanning +-half_width along each row's `sides`
        vector, mapped to the whole of atlas `cell`. The front sheet is the one whose normal leans up (the top of
        a fern frond)."""
        u_l, u_r, v0, v1 = _cell_uv(cell, flip, self.grid)
        rows = len(centres)
        up = Vector((0.0, 0.0, 1.0))
        left, right, row_n = [], [], []
        for k, (c, s) in enumerate(zip(centres, sides)):
            hw = half_width[k] if isinstance(half_width, (list, tuple)) else half_width
            left.append(c - s * hw)
            right.append(c + s * hw)
        for k in range(rows):
            i = min(k, rows - 2)
            row_n.append((right[i] - left[i]).cross(left[i + 1] - left[i]).normalized())
        front_up = sum(n.z for n in row_n) >= 0.0
        for sheet in (1.0, -1.0):
            start = len(self.verts)
            for k in range(rows):
                v = v0 + (v1 - v0) * k / (rows - 1)
                n = row_n[k] * (sheet if front_up else -sheet)
                gap = n * (SHEET_GAP / 2)                          # each sheet stands just off the card on its side
                self.verts += [tuple(left[k] + gap), tuple(right[k] + gap)]
                self.uvs += [(u_l, v), (u_r, v)]
                self.cols += [(shade, shade, shade)] * 2
                if self.lit is None:
                    lit = (n + up * NORMAL_UP).normalized()
                    self.normals += [tuple(lit), tuple(lit)]
                else:
                    self.normals += [tuple(self.lit(left[k])), tuple(self.lit(right[k]))]
                self.facing += [tuple(n), tuple(n)]
            outward = sheet if front_up else -sheet                # wind each sheet so its face normal is its n
            for k in range(rows - 1):
                a = start + 2 * k
                self.faces.append((a, a + 1, a + 3, a + 2) if outward > 0 else (a, a + 2, a + 3, a + 1))

    def build(self, name, material):
        obj = bc.mesh_object(name, self.verts, self.faces, [material], fix_normals=False,
                             vertex_colors=(VC, [tuple(_srgb_to_lin(c) for c in col) for col in self.cols]))
        mesh = obj.data
        layer = mesh.uv_layers["UVMap"]
        for loop in mesh.loops:
            layer.data[loop.index].uv = self.uvs[loop.vertex_index]
        mesh.normals_split_custom_set([self.normals[loop.vertex_index] for loop in mesh.loops])
        mesh.update()
        for poly in mesh.polygons:                                   # each sheet is wound to face its own side
            mp._check(poly.normal.dot(Vector(self.facing[poly.vertices[0]])) > 0.0, f"{name}: a card sheet is wound against its side")
        return obj


def _srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _card_material(name="M_MeadowCards", atlas=ATLAS, path=ATLAS_PATH):
    """The cards' Blender material: the atlas's colour times the decoded jitter colour, cut out by its alpha (the
    Round node is what the glTF exporter reads as alphaMode MASK). The engine draws M_MeadowCards.tres (or, for
    the tree canopies, M_TreeCanopyCards.tres) instead."""
    if atlas == ATLAS:
        meadow_atlas()                               # writes the atlas on the first card of a run
    path = os.path.join(ROOT, path)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    img = bpy.data.images.load(path, check_existing=True)
    img.name = atlas
    img.colorspace_settings.name = "sRGB"
    img.alpha_mode = "STRAIGHT"            # not packed: the .blend links the atlas by a relative path, as the GLB does
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = VC
    decode = nodes.new("ShaderNodeGamma")
    decode.inputs["Gamma"].default_value = 2.2
    links.new(attr.outputs["Color"], decode.inputs["Color"])
    mul = nodes.new("ShaderNodeMix")
    mul.data_type, mul.blend_type = "RGBA", "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    links.new(tex.outputs["Color"], mul.inputs["A"])
    links.new(decode.outputs["Color"], mul.inputs["B"])
    links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    clip = nodes.new("ShaderNodeMath")
    clip.operation = "ROUND"
    links.new(tex.outputs["Alpha"], clip.inputs[0])
    links.new(clip.outputs[0], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    mat.blend_method = "CLIP"
    mat.alpha_threshold = 0.5
    mat.use_backface_culling = True        # glTF doubleSided false: each card is two sheets, one per side
    return mat


def _bent_card(cards, base, yaw, width, height, cell, rng, segs=2, bend=0.0, lean=0.0, flip=None, sink=None, shade=None):
    """A card standing at `base`, facing yaw (radians; the card spans the horizontal direction at yaw + 90
    degrees), leaning `lean` radians toward its normal at the base and curving `bend` radians more by the tip.
    Its bottom edge sinks so the painted roots (ROOT_PX up the cell) meet the ground."""
    face = Vector((math.cos(yaw), math.sin(yaw), 0.0))
    side = Vector((-math.sin(yaw), math.cos(yaw), 0.0))
    sink = height * ROOT_PX / CELL + 0.008 if sink is None else sink
    centres, sides = [], []
    p = base - Vector((0.0, 0.0, sink))
    step = height / segs
    for k in range(segs + 1):
        centres.append(p.copy())
        sides.append(side)
        a = lean + bend * ((k + 0.5) / segs) ** 1.5
        p = p + (Vector((0.0, 0.0, math.cos(a))) + face * math.sin(a)) * step
    cards.strip(centres, sides, width / 2.0, cell, rng.random() < 0.5 if flip is None else flip,
                rng.uniform(0.82, 1.0) if shade is None else shade)


def _card_record(purpose, kind, cards_n, extra=None):
    out = {"purpose": purpose, "category": "environment", "kind": kind,
           "pivot": "the clump's centre on the ground (Godot y = 0); card bottoms sink about 2 cm so the roots meet the ground on gentle relief",
           "external_material": "res://assets/export/M_MeadowCards.tres",
           "placement": f"walk-through cover: under {COVER_MAX_M} m, so it may stand anywhere inside the walls outside the nest's 8 m clearing (tests/test_creature_world_art.gd)",
           "cards": {"count": cards_n, "atlas": ATLAS_PATH, "material": "M_MeadowCards (StandardMaterial3D: alpha scissor 0.5, back faces culled, COLOR_0 jitter)",
                     "sides": "two sheets back to back per card, opposite winding", "normals": f"each sheet's face normal plus {NORMAL_UP} x world up, so both sides light like the ground"},
           "vertex_colors_attribute": VC, "textures": [meadow_atlas()], "revision": 1, "provenance": PROVENANCE_CARDS}
    out.update(extra or {})
    return out


def _check_cover(what):
    pts = bc.world_vertices()
    top = max(p.z for p in pts)
    mp._check(top <= COVER_MAX_M - 0.02, f"{what}: stands under {COVER_MAX_M} m ({top:.3f})")
    mp._check(min(p.z for p in pts) >= -0.05, f"{what}: sinks no more than 5 cm")
    return top


def build_grass_tuft():
    """A grass tuft about 0.4 m tall and 0.5 m across: three bent cards crossed through its centre (a six-pointed star from
    above: the meadow, tall and short fans) and three shorter cards leaning out round its foot (sage, sedge, and
    fine grass with a few lilac stars), which break the star's silhouette. Each card is mirrored at random and has
    its own brightness. Six two-sided cards of two segments: 48 triangles."""
    rng = random.Random(4101)
    cards = _Cards()
    mat = _card_material()
    spin = rng.uniform(0.0, math.tau)
    for i in range(3):
        yaw = spin + math.pi * i / 3 + rng.uniform(-0.15, 0.15)
        _bent_card(cards, Vector((rng.uniform(-0.01, 0.01), rng.uniform(-0.01, 0.01), 0.0)), yaw,
                   rng.uniform(0.4, 0.48), rng.uniform(0.38, 0.44), (0, 1, 2)[i], rng, bend=rng.choice((-1, 1)) * rng.uniform(0.25, 0.45))
    for i in range(3):
        a = spin + math.tau * (i + 0.5) / 3 + rng.uniform(-0.3, 0.3)
        out = Vector((math.cos(a), math.sin(a), 0.0))
        _bent_card(cards, out * 0.1, a, rng.uniform(0.3, 0.34), rng.uniform(0.26, 0.31), (3, 4, 15)[i], rng,
                   lean=rng.uniform(0.3, 0.45), bend=rng.uniform(0.15, 0.3))
    cards.build("GrassTuft", mat)
    top = _check_cover("grass tuft")
    return _card_record("Creature world ground cover (PROPOSED): a meadow grass tuft of bent, crossed cards cut out by the T_MeadowCards grass fans.",
                        "flora_cover", 6, {"height_m": round(top, 3)})


def build_fern_clump():
    """A fern clump about 0.4 m tall: eight arching fronds, each a four-segment card leaving the crown steeply
    and arching over to a drooping tip, twisted a little along its length; two inner fronds (the young fern cell)
    stand more upright. The others alternate between the broad and the narrow fern cells. Eight two-sided fronds
    of three segments: 96 triangles."""
    rng = random.Random(4102)
    cards = _Cards()
    mat = _card_material()
    spin = rng.uniform(0.0, math.tau)
    up = Vector((0.0, 0.0, 1.0))
    for i in range(8):
        az = spin + math.tau * i / 8 + rng.uniform(-0.2, 0.2)
        inner = i in (2, 6)
        out = Vector((math.cos(az), math.sin(az), 0.0))
        e0, e1 = (math.radians(rng.uniform(78, 84)), math.radians(rng.uniform(30, 42))) if inner else \
            (math.radians(rng.uniform(58, 70)), math.radians(rng.uniform(-18, -6)))
        length = rng.uniform(0.36, 0.42) if inner else rng.uniform(0.44, 0.52)
        width = rng.uniform(0.15, 0.18) if not inner else 0.13
        twist = rng.uniform(-0.3, 0.3)
        segs = 3
        centres, sides = [], []
        p = out * 0.025 - up * 0.02
        for k in range(segs + 1):
            t = k / segs
            centres.append(p.copy())
            side = Vector((-math.sin(az), math.cos(az), 0.0))
            e = e0 + (e1 - e0) * min(1.0, (t + 0.5 / segs)) ** 1.2
            tangent = (out * math.cos(e) + up * math.sin(e)).normalized()
            roll = twist * t
            side = (side * math.cos(roll) + tangent.cross(side) * math.sin(roll)).normalized()
            sides.append(side)
            p = p + tangent * (length / segs)
        halfs = [width / 2 * (0.75 + 0.25 * min(1.0, 3.0 * k / segs)) for k in range(segs + 1)]
        cards.strip(centres, sides, halfs, 13 if inner else (6, 7)[i % 2], rng.random() < 0.5, rng.uniform(0.84, 1.0))
    cards.build("FernClump", mat)
    top = _check_cover("fern clump")
    return _card_record("Creature world ground cover (PROPOSED): a fern clump of eight arching frond cards cut out by the T_MeadowCards fern cells.",
                        "flora_cover", 8, {"height_m": round(top, 3)})


def build_flower_clump():
    """A wildflower clump about 0.35 m tall: three short leaf cards crossed at its foot (the leaf rosette, clover
    and fine grass), and six sprig cards in three crossed pairs rising above them: lilac bells, blue and cream
    stars, and cream umbels crossed with blue bells. Nine two-sided cards of two segments: 72 triangles."""
    rng = random.Random(4103)
    cards = _Cards()
    mat = _card_material()
    spin = rng.uniform(0.0, math.tau)
    for i, cell in enumerate((12, 14, 5)):
        _bent_card(cards, Vector((0.0, 0.0, 0.0)), spin + math.pi * i / 3, 0.3, rng.uniform(0.18, 0.22), cell, rng,
                   bend=rng.uniform(0.2, 0.4))
    for i, pair in enumerate(((8, 8), (9, 9), (10, 11))):
        a = spin + math.tau * i / 3 + 0.4
        at = Vector((math.cos(a), math.sin(a), 0.0)) * 0.035
        yaw = a + math.pi / 2 + rng.uniform(-0.3, 0.3)
        for j in range(2):
            _bent_card(cards, at, yaw + math.pi / 2 * j, rng.uniform(0.27, 0.31), rng.uniform(0.33, 0.4), pair[j], rng,
                       lean=rng.uniform(0.05, 0.15) * (1 if j else -1), bend=rng.uniform(-0.2, 0.2))
    cards.build("FlowerClump", mat)
    top = _check_cover("flower clump")
    return _card_record("Creature world ground cover (PROPOSED): a wildflower clump, leaf cards at its foot and sprig cards of lilac bells and sky-blue and cream star heads (T_MeadowCards).",
                        "flora_cover", 9, {"height_m": round(top, 3), "flowers": ["lilac bells (LCh hue 300-308)", "sky blue star heads (hue 264-271) and bells (hue 262-268)", "cream star heads and umbels (hue 80-86), the stars with a dark violet eye"]})


# --- Rocks ----------------------------------------------------------------------------------------------------

def _reduce_to(obj, budget, protect=None):
    """Collapse-decimates `obj` to at most `budget` triangles, keeping a hidden full-detail copy for the normal
    bake; the vertices of vertex group `protect`, when given, are left as they are. Returns (triangles before,
    after, the copy, the largest surface error in metres)."""
    high = obj.copy()
    high.data = obj.data.copy()
    high.name = f"{obj.name}_high"
    bpy.context.collection.objects.link(high)
    high.matrix_world = obj.matrix_world.copy()
    before = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    mod = obj.modifiers.new("Reduce", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.use_collapse_triangulate = True
    if protect is not None:
        keep = obj.vertex_groups[protect].index
        free = [v.index for v in obj.data.vertices if not any(g.group == keep and g.weight > 0.0 for g in v.groups)]
        obj.vertex_groups.new(name="Reduce").add(free, 1.0, "REPLACE")
        mod.vertex_group = "Reduce"
    ratio = budget * 0.985 / before
    deps = bpy.context.evaluated_depsgraph_get()
    for _ in range(40):
        mod.ratio = ratio
        bpy.context.view_layer.update()
        mesh = obj.evaluated_get(deps).to_mesh()
        tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
        obj.evaluated_get(deps).to_mesh_clear()
        if tris <= budget:
            break
        ratio *= 0.985
    sf.select([obj])
    bpy.ops.object.modifier_apply(modifier="Reduce")
    after = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    error = sf._surface_error(obj, high)
    high.hide_render = True
    high.hide_set(True)
    return before, after, high, error


def _bake_rock(obj, budget, texture, size, tints=None, protect=None):
    before, after, high, error = _reduce_to(obj, budget, protect)
    sf.unwrap([obj])
    textures = sf.bake_set([obj], texture, size, normal=True, highs={obj.name: high}, tints=tints)
    sf.drop_highs([high])
    for mesh in [m for m in bpy.data.meshes if m.users == 0]:     # the full-detail copy's mesh, still holding the
        bpy.data.meshes.remove(mesh)                              # procedural material the bake replaced
    for mat in [m for m in bpy.data.materials if m.users == 0]:
        bpy.data.materials.remove(mat)
    return {"textures": textures,
            "reduction": {"method": "Blender collapse decimation to the triangle budget; the full-detail shape and shader relief baked to the normal map",
                          "triangles_before": before, "triangles_after": after, "surface_error_m": round(error, 4)}}


def _smin(a, b, k):
    """Polynomial smooth minimum: a rounded edge of about k where two surfaces meet."""
    h = max(k - abs(a - b), 0.0) / k
    return min(a, b) - h * h * k * 0.25


def build_pebble_cluster():
    """Seven pebbles of 3 to 12 cm lying half sunk in a patch about 0.4 m across: rounded, flattened river
    stones with a slight lumpiness, their undersides cut off below the ground. Warm grey, each pebble a little
    lighter or darker. 160 triangles, baked 512."""
    rng = random.Random(4201)
    unit, ufaces = bc.icosphere(3)
    verts, faces = [], []
    placed = []
    sizes = [0.12, 0.09, 0.075, 0.06, 0.05, 0.04, 0.03]
    for size in sizes:
        for _ in range(200):
            a, r = rng.uniform(0.0, math.tau), rng.uniform(0.02, 0.2)
            c = Vector((r * math.cos(a), r * math.sin(a), 0.0))
            if all((c - q).length > (size + s) * 0.5 * 0.9 for q, s in placed):
                break
        placed.append((c, size))
        axes = Vector((size / 2, size / 2 * rng.uniform(0.6, 0.85), size / 2 * rng.uniform(0.5, 0.68)))
        yaw, tilt = rng.uniform(0.0, math.tau), rng.uniform(-0.25, 0.25)
        lift = axes.z * rng.uniform(0.05, 0.35)                     # half sunk: the centre a little over the ground
        seed = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
        piece = []
        for co in unit:
            n = Vector(co).normalized()
            r = 1.0 + 0.07 * noise.noise(n * 1.6 + seed) + 0.025 * noise.noise(n * 4.0 + seed)
            p = Vector((n.x * axes.x, n.y * axes.y, n.z * axes.z)) * r
            p = Vector((p.x, p.y * math.cos(tilt) - p.z * math.sin(tilt), p.y * math.sin(tilt) + p.z * math.cos(tilt)))
            p = Vector((p.x * math.cos(yaw) - p.y * math.sin(yaw), p.x * math.sin(yaw) + p.y * math.cos(yaw), p.z + lift))
            piece.append(c + p)
        keep = [f for f in ufaces if max(piece[i].z for i in f) > 0.0]    # the part under the ground is never seen
        used = sorted({i for f in keep for i in f})
        remap = {old: k + len(verts) for k, old in enumerate(used)}
        verts.extend(tuple(Vector((piece[i].x, piece[i].y, max(piece[i].z, -0.006)))) for i in used)
        faces.extend(tuple(remap[i] for i in f) for f in keep)
    sh = sf.Shader("M_PebbleProc")
    speck = sh.noise(180.0, 2.0)
    mottle = sh.noise(22.0, 3.0)
    per = sh.noise(5.0, 1.0)                                         # low frequency: each pebble a different value
    sh.bump(sh.math("ADD", sh.math("MULTIPLY", speck, 0.4), sh.math("MULTIPLY", mottle, 0.6)), 0.25, 0.002)
    fac = sh.math("ADD", sh.math("ADD", sh.math("MULTIPLY", sh.remap(per, 0.3, 0.7), 0.45), sh.math("MULTIPLY", sh.remap(mottle, 0.3, 0.7), 0.35)),
                  sh.math("MULTIPLY", speck, 0.2), clamp=True)
    mat = sh.out(mp._grey(sh, fac, 0.62), sh.remap(mottle, 0.0, 1.0, 0.62, 0.8))
    obj = bc.mesh_object("PebbleCluster", verts, faces, [mat])
    mat.name = "M_Pebble"
    baked = _bake_rock(obj, 160, "CreaturePebbleCluster", 512, tints={"M_Pebble": sf.tint(_lin("#8C8070"))})
    pts = bc.world_vertices()
    mp._check(max(p.z for p in pts) <= 0.08, "pebbles: lie low (the largest stands under 8 cm)")
    mp._check(min(p.z for p in pts) >= -0.01, "pebbles: cut off just under the ground")
    mp._check(max(math.hypot(p.x, p.y) for p in pts) <= 0.3, "pebbles: a patch about 0.4 m across")
    return {"purpose": "Creature world ground cover (PROPOSED): a patch of seven half-sunk, rounded pebbles of 3 to 12 cm in warm grey.",
            "category": "environment", "kind": "rock_cover", "pivot": "the patch's centre on the ground (Godot y = 0)",
            "placement": f"walk-through cover: under {COVER_MAX_M} m, so it may lie anywhere inside the walls outside the nest's 8 m clearing, thicker on the bare earth patches",
            "pebbles_m": sizes, "revision": 1, "provenance": PROVENANCE_PEBBLES, **baked}


BOULDERS = {
    # id: (node, longest side m, triangle budget, seed)
    "creature_boulder_a": ("BoulderA", 1.0, 700, 4301),
    "creature_boulder_b": ("BoulderB", 1.8, 900, 4302),
    "creature_boulder_c": ("BoulderC", 3.0, 1200, 4303),
}
BOULDER_TEX = {"creature_boulder_a": 512}           # px; the others 1024, so the stone's grain is about as fine on each
# Cool blue-grey stone (LCh L 36 to 66, chroma about 3, hue 250 to 256). A warm stone would be the obvious choice,
# but any blend of a warm grey with the moss, a mip far off or a bake's filtering, lands on the food green's hue
# (rev 1's warm stone averaged h 112 to 116 at chroma 9.5); a blend of this stone with the moss runs through teal.
STONE_DARK, STONE_LIGHT = "#52565A", "#9DA2A6"
STONE_DAMP = "#606365"                              # the near-neutral damp edge under the moss, about the stone's lightness
MOSS_DARK, MOSS_LIGHT = "#2F5A3E", "#5C8A5E"        # blue meadow moss (LCh hue about 145 to 148)


def _boulder_shape(size, seed, depth, height):
    """The boulder's surface in unit direction n: an ellipsoid cut by a near-level top plane and six to nine side
    planes through a smooth minimum (broad cleavage facets with rounded edges, none underneath), with a low
    lumpiness and a slight lean. Returns a function n -> point (before the final fit to `size`) and the sink."""
    rng = random.Random(seed)
    planes = [(Vector((math.cos(rng.uniform(0, math.tau)) * 0.15, math.sin(rng.uniform(0, math.tau)) * 0.15, 1.0)).normalized(),
               rng.uniform(0.74, 0.82))]
    for _ in range(rng.randint(6, 9)):
        az, el = rng.uniform(0.0, math.tau), math.radians(rng.uniform(-5.0, 45.0))
        planes.append((Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el))), rng.uniform(0.74, 0.88)))
    off = Vector((rng.uniform(0, 40), rng.uniform(0, 40), rng.uniform(0, 40)))
    radii = Vector((size / 2, size / 2 * depth, size / 2 * height))
    lean = Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), 0.0))

    def point(n):
        r = 1.0 + 0.06 * noise.noise(n * 1.3 + off) + 0.02 * noise.noise(n * 3.1 + off)
        for d, o in planes:
            dot = n.dot(d)
            if dot > 0.05:
                r = _smin(r, o / dot, 0.07)
        p = Vector((n.x * radii.x, n.y * radii.y, n.z * radii.z)) * r
        return p + lean * (p.z + radii.z)

    return point


def _boulder_material(size):
    """Stone from the CC0 scan's luminance (box-projected at one tile per SCAN_M metres) recoloured between a dark
    and a light cool grey, with broad weathered value patches; height from the scan's displacement and a broad
    noise, as bump. A moss cap where the surface faces up and toward the top, its edge ragged with a fine fractal
    noise so it reads as growth rather than a painted blob, flecked light and dark with a fuzzy bump. At the moss's
    edge the stone first goes to a near-neutral damp grey of about its own lightness, then the moss comes in."""
    sh = sf.Shader("M_BoulderProc")
    diff = sh.image(os.path.join(ROOT, SCAN_DIR, "rock_boulder_dry_diff_1k.jpg"), "sRGB", "BOX", 0.3, 1.0 / SCAN_M)
    disp = sh.image(os.path.join(ROOT, SCAN_DIR, "rock_boulder_dry_disp_1k.jpg"), "Non-Color", "BOX", 0.3, 1.0 / SCAN_M)
    lum = sh.node("ShaderNodeRGBToBW")
    sh.link(diff, lum.inputs["Color"])
    height = sh.node("ShaderNodeRGBToBW")
    sh.link(disp, height.inputs["Color"])
    broad = sh.noise(0.9 / size, 3.0)
    weather = sh.noise(2.2 / size, 2.0)
    grain = sh.math("ADD", sh.math("MULTIPLY", sh.remap(lum.outputs["Val"], 0.15, 0.75), 0.6), sh.math("MULTIPLY", sh.remap(weather, 0.3, 0.7), 0.4), clamp=True)
    stone = sh.mix(grain, _lin_rgba(STONE_DARK), _lin_rgba(STONE_LIGHT))
    geo = sh.node("ShaderNodeNewGeometry")
    nz = sh.node("ShaderNodeSeparateXYZ")
    sh.link(geo.outputs["Normal"], nz.inputs["Vector"])
    patch = sh.noise(2.5 / size, 3.0, 0.55)
    ragged = sh.noise(16.0 / size, 8.0, 0.7)
    fleck = sh.noise(60.0 / size, 4.0, 0.6)
    up = sh.remap(nz.outputs["Z"], 0.2, 0.95, smooth=False)
    top = sh.remap(sh.axis("Z"), 0.0, size * 0.32, smooth=False)
    field = sh.math("ADD", sh.math("ADD", sh.math("MULTIPLY", up, 0.6), sh.math("MULTIPLY", top, 0.4)),
                    sh.math("ADD", sh.math("MULTIPLY", sh.math("SUBTRACT", patch, 0.5), 0.6), sh.math("MULTIPLY", sh.math("SUBTRACT", ragged, 0.5), 0.45)))
    damp = sh.remap(field, 0.5, 0.6)
    moss_in = sh.remap(field, 0.58, 0.66)
    moss_col = sh.mix(sh.math("ADD", sh.math("MULTIPLY", sh.remap(fleck, 0.3, 0.7), 0.7), sh.math("MULTIPLY", sh.remap(patch, 0.35, 0.75), 0.3), clamp=True),
                      _lin_rgba(MOSS_DARK), _lin_rgba(MOSS_LIGHT))
    base = sh.mix(moss_in, sh.mix(damp, stone, _lin_rgba(STONE_DAMP)), moss_col)
    relief = sh.math("ADD", sh.math("ADD", sh.math("MULTIPLY", height.outputs["Val"], 0.55), sh.math("MULTIPLY", broad, 0.25)),
                     sh.math("MULTIPLY", sh.math("ADD", sh.math("MULTIPLY", fleck, 0.6), 0.3), moss_in))
    sh.bump(relief, 0.45, 0.012 * size)
    rough = sh.math("ADD", sh.math("MULTIPLY", moss_in, 0.12), 0.82, clamp=True)
    return sh.out(base, rough)


def _lin_rgba(hex_color):
    return (*_lin(hex_color), 1.0)


def build_boulder(asset_id):
    node, size, budget, seed = BOULDERS[asset_id]
    rng = random.Random(seed)
    depth, height = rng.uniform(0.72, 0.86), rng.uniform(0.6, 0.72)
    point = _boulder_shape(size, seed, depth, height)
    unit, ufaces = bc.icosphere(6 if size > 1.5 else 5)
    pts = [point(Vector(co).normalized()) for co in unit]
    # Fit: the longest horizontal side to `size`, the height to `height` x size, the base sunk 12% of that height.
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    k = size / max(hi.x - lo.x, hi.y - lo.y)
    kz = size * height / (hi.z - lo.z)
    sink = 0.12 * size * height
    mid = (lo + hi) / 2
    pts = [Vector(((p.x - mid.x) * k, (p.y - mid.y) * k, (p.z - lo.z) * kz - sink)) for p in pts]
    floor = -sink * 0.92
    keep = [f for f in ufaces if max(pts[i].z for i in f) > floor]
    used = sorted({i for f in keep for i in f})
    remap = {old: n for n, old in enumerate(used)}
    verts = [tuple(Vector((pts[i].x, pts[i].y, max(pts[i].z, -sink)))) for i in used]
    faces = [tuple(remap[i] for i in f) for f in keep]
    obj = bc.mesh_object(node, verts, faces, [_boulder_material(size)])
    baked = _bake_rock(obj, budget, f"Creature{node}", BOULDER_TEX.get(asset_id, 1024))
    w = bc.world_vertices()
    low = min(p.z for p in w)
    mp._check(low >= -sink - 0.03 * size, f"{node}: sunk about {sink:.2f} m, no deeper ({low:.3f}; decimation may move the cut edge a little)")
    mp._check(min(p.z for p in w) < -0.03, f"{node}: its base sits under the ground, so it never hovers on the berm")
    return {"purpose": f"Creature world rock (PROPOSED): a rounded, mossy boulder about {size:g} m across with soft cleavage facets, warm grey stone and blue-green moss on its up-facing top.",
            "category": "environment", "kind": "boulder", "pivot": f"the boulder's centre on the ground (Godot y = 0); its base sinks {sink:.2f} m so it sits into a slope",
            "placement": "an obstacle-sized rock: OUTSIDE the walls only (the berm and the hills, where max(|x|, |z|) is 80.5 m or more) until the sim has obstacles; tests/test_creature_world_art.gd keeps anything over 0.45 m out of the walkable field",
            "size_m": size, "sink_m": round(sink, 3), "dependencies": [dict(SCAN_DEPENDENCY)], "revision": 1,
            "provenance": PROVENANCE_BOULDER, **baked}


# --- Trees (outside the walls only, until the sim has obstacles) ----------------------------------------------

CANOPY_ATLAS = "T_TreeCanopyCards"
CANOPY_PATH = "assets/export/creature_flora/T_TreeCanopyCards.png"
CANOPY_PX = 1024
CANOPY_CELL = 512
CANOPY_GRID = (2, 2)
CANOPY_UMBRELLA, CANOPY_UMBRELLA_FINE, CANOPY_CURTAIN, CANOPY_CAP = 0, 1, 2, 3
CANOPY_NORMAL_UP = 0.45      # how much of world up joins the crown's outward normal on the canopy cards
PROVENANCE_TREE = ("Authored procedurally by tools/blender/creature_flora.py (through make_creature_world.py); no "
                   "external or generated meshes. The wood is a skin-modifier skeleton baked in Blender from "
                   "procedural shaders; the canopy card atlas is painted in numpy (strokes in CIE LCh); no scans.")


def _lch_lin(L, C, h):
    """CIE LCh to a linear RGBA tuple for a Blender shader."""
    srgb = lch_srgb(L, C, h)
    return (*(float(_srgb_to_lin(float(c))) for c in srgb), 1.0)


def _leaf(cell, base, angle, length, width, colour, bend=0.0, shadow=0.24):
    """An ovate leaf from `base` (its petiole end) at `angle` from straight up: widest a third of the way along,
    tapering to a soft point."""
    pts = _arc(base, angle, length, bend, steps=8)
    u = np.linspace(0.0, 1.0, len(pts))
    half = width * np.sin(np.pi * np.clip(u * 0.9 + 0.08, 0.0, 1.0)) ** 0.6 * (1.0 - 0.3 * u ** 2) + 0.6
    cell.paint(pts, half, colour, shadow=shadow)


def _spray_cell(rng, fine):
    """A leaf spray seen from above, its stem leaving the cell's bottom centre (where the card meets its branch):
    a curved stem with side twigs, each carrying rounded leaves that fan outward, so laid on a crown the cards
    build a soft, rounded canopy surface with a leafy edge. "fine" carries more, smaller and bluer leaves."""
    n = CANOPY_CELL
    hue = (161.0, 172.0) if fine else (155.0, 166.0)
    cell = _Cell(rng, (40.0, 28.0, sum(hue) / 2), n=n)
    root = np.array((n / 2, n - ROOT_PX))
    stem = _arc(root, rng.normal(0.0, 0.08), n * 0.7, rng.normal(0.0, 0.2), steps=14)
    twigs = [stem]
    for k in range(9 if fine else 7):
        t = 0.18 + 0.7 * k / (8 if fine else 6) + rng.uniform(-0.03, 0.03)
        j = int(t * (len(stem) - 1))
        side = -1.0 if k % 2 else 1.0
        d = stem[min(j + 1, len(stem) - 1)] - stem[j]
        up_angle = math.atan2(d[0], -d[1])
        twig = _arc(stem[j], up_angle + side * rng.uniform(0.75, 1.15), n * rng.uniform(0.2, 0.32) * (1.0 - 0.35 * t),
                    -side * rng.uniform(0.2, 0.5), steps=8)
        twigs.append(twig)
    leaves = []
    size = (34.0, 52.0, 10.0, 14.0) if fine else (52.0, 80.0, 17.0, 24.0)
    for twig in twigs:
        seg = np.diff(twig, axis=0)
        count = int(len(twig) * (1.6 if fine else 1.0))
        for i in range(count):
            t = 0.2 + 0.8 * i / max(1, count - 1)
            j = min(len(seg) - 1, int(t * len(seg)))
            at = twig[j] + seg[j] * (t * len(seg) - j)
            d = seg[j] / max(1e-6, np.linalg.norm(seg[j]))
            along = math.atan2(d[0], -d[1])
            for side in ((-1.0, 1.0) if i % 2 == 0 else (rng.choice((-1.0, 1.0)),)):
                angle = along + side * rng.uniform(0.45, 0.95)
                length = rng.uniform(size[0], size[1]) * (1.0 - 0.25 * t)
                pts = _arc(at, angle, length, side * rng.uniform(-0.15, 0.25), steps=8)
                if not cell.inside(pts, pad=12.0 + size[3]):
                    continue
                leaves.append((at, angle, length, rng.uniform(size[2], size[3]), rng.uniform(*hue), rng.uniform(26.0, 33.0),
                               rng.uniform(-6.0, 6.0), side))
        tip = twig[-1]
        d = twig[-1] - twig[-2]
        angle = math.atan2(d[0], -d[1])
        pts = _arc(tip, angle, size[1], 0.0, steps=8)
        if cell.inside(pts, pad=12.0 + size[3]):
            leaves.append((tip, angle, size[1] * 0.9, size[3], rng.uniform(*hue), 30.0, 3.0, 1.0))
    for twig in twigs:                                                 # the wood, under the leaves
        t = np.linspace(0.0, 1.0, len(twig))
        cell.paint(twig, (4.5 if twig is stem else 2.6) * (1.0 - 0.6 * t) + 0.8, _lch_colour(29.0, 36.0, 12.0, 152.0, rib=2.0, edge=2.0), shadow=0.1)
    leaves.sort(key=lambda leaf: leaf[6])                              # darker leaves at the back
    for at, angle, length, width, h, c, tone, side in leaves:
        _leaf(cell, at, angle, length, width, _lch_colour(33.0 + tone, 55.0 + tone, c, h, rib=5.0, edge=8.0),
              bend=side * 0.12, shadow=0.26)
    return cell.finish()


def _frond(cell, rng, root, angle, length, leaflet, hue, light=0.0, steps=18, sweep=0.62, width=0.2):
    """A hanging frond: a fine rachis from `root` with paired narrow leaflets that sweep toward its tip, so hung
    tip-down it droops."""
    rachis = _arc(root, angle, length, rng.normal(0.0, 0.12), steps=steps, curl=1.2)
    seg = np.diff(rachis, axis=0)
    pairs = int(length / (leaflet * 0.42))
    leaflets = []
    for i in range(pairs):
        t = 0.04 + 0.94 * i / max(1, pairs - 1)
        j = min(len(seg) - 1, int(t * len(seg)))
        at = rachis[j] + seg[j] * (t * len(seg) - j)
        d = seg[j] / max(1e-6, np.linalg.norm(seg[j]))
        along = math.atan2(d[0], -d[1])
        for side in (-1.0, 1.0):
            size = leaflet * (1.0 - 0.55 * t ** 1.4) * rng.uniform(0.85, 1.1)
            pts = _arc(at, along + side * rng.uniform(sweep - 0.12, sweep + 0.12), max(6.0, size), -side * 0.18, steps=6)
            if cell.inside(pts, pad=10.0):
                leaflets.append((pts, size, t, rng.uniform(-4.0, 4.0)))
    for pts, size, t, tone in leaflets:
        u = np.linspace(0.0, 1.0, len(pts))
        half = size * width * np.sin(np.pi * np.clip(u * 0.92 + 0.06, 0.0, 1.0)) ** 0.7 + 0.5
        cell.paint(pts, half, _lch_colour(36.0 + light + 10.0 * t + tone, 56.0 + light + 6.0 * t + tone, 30.0, hue + 4.0 * t, rib=3.0, edge=6.0), shadow=0.18)
    t = np.linspace(0.0, 1.0, len(rachis))
    cell.paint(rachis, 2.4 * (1.0 - t) + 0.9, _lch_colour(34.0 + light, 46.0 + light, 22.0, hue - 4.0, rib=2.0, edge=2.0), shadow=0.08)


def _curtain_cell(rng):
    """Four hanging fronds side by side from the cell's bottom edge (the card's attached end) to near its top (the
    tip), with full leaflets that overlap their neighbours', turquoise, lighter toward their tips: hung from the
    lantern tree's crown, a card is a strip of curtain dense enough to keep its shape far off."""
    n = CANOPY_CELL
    cell = _Cell(rng, (44.0, 27.0, 171.0), n=n)
    for k, x in enumerate((0.17, 0.39, 0.61, 0.83)):
        _frond(cell, rng, (n * x + rng.uniform(-6.0, 6.0), n - ROOT_PX), rng.normal(0.0, 0.04), n * rng.uniform(0.8, 0.88),
               rng.uniform(58.0, 66.0), rng.uniform(166.0, 172.0), light=rng.uniform(-2.0, 3.0), width=0.3)
    return cell.finish()


def _cap_cell(rng):
    """Short fronds fanned from the cell's bottom centre: laid round the top of the lantern tree's crown."""
    n = CANOPY_CELL
    cell = _Cell(rng, (42.0, 27.0, 166.0), n=n)
    fronds = sorted(range(7), key=lambda _: rng.random())
    for k in fronds:
        angle = (-1.0 + 2.0 * k / 6.0) * 0.85 + rng.normal(0.0, 0.05)
        _frond(cell, rng, (n / 2 + rng.normal(0.0, 6.0), n - ROOT_PX), angle, n * rng.uniform(0.5, 0.64) * (1.0 - 0.25 * abs(angle)),
               rng.uniform(38.0, 46.0), rng.uniform(161.0, 168.0), light=rng.uniform(-3.0, 3.0), steps=14, sweep=0.7)
    return cell.finish()


CANOPY_PAINTERS = (("umbrella spray", lambda rng: _spray_cell(rng, False)), ("umbrella spray fine", lambda rng: _spray_cell(rng, True)),
                   ("lantern curtain", _curtain_cell), ("lantern cap", _cap_cell))


def canopy_atlas():
    """Writes T_TreeCanopyCards once per run (seeded, so the same file every run) and returns its record entry."""
    if "canopy" in _ATLAS_DONE:
        return dict(_ATLAS_DONE["canopy"])
    rng = np.random.default_rng(5301)
    cols, rows = CANOPY_GRID
    atlas = np.zeros((CANOPY_PX, CANOPY_PX, 4))
    for i, (name, painter) in enumerate(CANOPY_PAINTERS):
        rgba = painter(rng)
        col, row = i % cols, i // cols
        atlas[row * CANOPY_CELL:(row + 1) * CANOPY_CELL, col * CANOPY_CELL:(col + 1) * CANOPY_CELL] = rgba
        share = float((rgba[..., 3] >= 0.5).mean())
        clash = hue_clash(rgba[..., :3], rgba[..., 3])
        L, C, h = srgb_lch(rgba[..., :3][rgba[..., 3] >= 0.5].mean(axis=0))
        mp._check(0.12 < share < 0.75, f"canopy atlas cell {i} ({name}): the cut-out covers a fair share of the card ({share:.2f})")
        mp._check(clash <= 0.01, f"canopy atlas cell {i} ({name}): {clash:.2%} of its chromatic texels sit near the food or threat hue")
        print(f"  canopy cell {i} {name:20s} coverage {share:.2f}, hue clashes {clash:.2%}, mean L {float(L):.0f} C {float(C):.0f} h {float(h):.0f}")
    _save_rgba(CANOPY_ATLAS, atlas, CANOPY_PX)
    _ATLAS_DONE["canopy"] = {"name": CANOPY_ATLAS, "path": CANOPY_PATH, "size": [CANOPY_PX, CANOPY_PX], "colorspace": "sRGB",
                             "packing": "RGB the authored colour (CIE LCh greens and turquoise at hue 155 to 176, stems a low-chroma brown) in a 2 x 2 grid of 512 px cells: " + "; ".join(f"{i} {n}" for i, (n, _) in enumerate(CANOPY_PAINTERS)) + "; A the cut-out mask (alpha scissor at 0.5)"}
    return dict(_ATLAS_DONE["canopy"])


def _save_rgba(name, rgba, px):
    out = np.ascontiguousarray(np.clip(rgba[::-1], 0.0, 1.0).astype(np.float32))   # Blender stores rows bottom-up
    img = bpy.data.images.new(name, px, px, alpha=True)
    img.colorspace_settings.name = "Non-Color"      # values are written as-is; the RGB is already sRGB-encoded
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(out.ravel())
    os.makedirs(FLORA_DIR, exist_ok=True)
    img.filepath_raw = os.path.join(FLORA_DIR, f"{name}.png")
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def _canopy_material():
    """The canopy cards' Blender material: as the meadow cards' (the atlas times the decoded jitter, cut out at
    0.5, back faces culled); the engine draws M_TreeCanopyCards.tres instead."""
    canopy_atlas()
    mat = _card_material(name="M_TreeCanopyCards", atlas=CANOPY_ATLAS, path=CANOPY_PATH)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    return mat


def _skin(name, verts, edges, radii, levels=2, branch_smoothing=0.5):
    """A smooth organic tube network from a skeleton (Blender's Skin modifier, then subdivision), applied to a
    plain mesh. `radii` is each skeleton vertex's radius; vertex 0 is the root."""
    mesh = bpy.data.meshes.new(f"{name}_skeleton")
    mesh.from_pydata([tuple(v) for v in verts], [tuple(e) for e in edges], [])
    obj = bpy.data.objects.new(f"{name}_skeleton", mesh)
    bpy.context.collection.objects.link(obj)
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.branch_smoothing = branch_smoothing
    skin.use_smooth_shade = True
    if not len(obj.data.skin_vertices):
        sf.select([obj])
        bpy.ops.mesh.customdata_skin_add()
    data = obj.data.skin_vertices[0].data
    for i, r in enumerate(radii):
        data[i].radius = (r, r)
        data[i].use_root = i == 0
    sub = obj.modifiers.new("Smooth", "SUBSURF")
    sub.levels = sub.render_levels = levels
    deps = bpy.context.evaluated_depsgraph_get()
    out_mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    out_mesh.name = f"{name}_mesh"
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    out = bpy.data.objects.new(name, out_mesh)
    bpy.context.collection.objects.link(out)
    return out


class _Skeleton:
    """Skeleton vertices, edges and radii; chains sampled from a path function."""

    def __init__(self):
        self.verts, self.edges, self.radii = [], [], []

    def chain(self, path, radius, steps, start=None):
        """Adds `steps` segments along path(t), t in [0, 1], with radius(t); joined to vertex `start` when given
        (the chain's t = 0 is then that vertex). Returns the chain's vertex indices."""
        ids = []
        prev = start
        for k in range(0 if start is None else 1, steps + 1):
            t = k / steps
            self.verts.append(Vector(path(t)))
            self.radii.append(radius(t))
            i = len(self.verts) - 1
            if prev is not None:
                self.edges.append((prev, i))
            prev = i
            ids.append(i)
        return ids

    def nearest(self, ids, z):
        return min(ids, key=lambda i: abs(self.verts[i].z - z))


def _bezier(a, b, c):
    a, b, c = Vector(a), Vector(b), Vector(c)
    return lambda t: a * (1 - t) ** 2 + b * 2 * t * (1 - t) + c * t * t


def _smooth_radius(stops):
    """Radius along a chain from (t, radius) stops, smoothstep between them."""
    def radius(t):
        for (t0, r0), (t1, r1) in zip(stops, stops[1:]):
            if t <= t1:
                return r0 + (r1 - r0) * bc.smoothstep((t - t0) / max(1e-6, t1 - t0))
        return stops[-1][1]
    return radius


def _flare(obj, axis_at, height, lobes, amount, seed, sink):
    """Root flare: near the ground the wood swells outward in `lobes` buttresses (each a little different), fading
    out by `height`; under the ground everything is pressed to `-sink`, so the base sits into a slope. `axis_at(z)`
    is the trunk's centre at height z."""
    rng = random.Random(seed)
    phase = rng.uniform(0.0, math.tau)
    weights = [rng.uniform(0.7, 1.15) for _ in range(lobes)]
    for v in obj.data.vertices:
        co = v.co
        if co.z < height:
            c = axis_at(max(co.z, 0.0))
            d = Vector((co.x - c.x, co.y - c.y, 0.0))
            if d.length > 1e-5:
                a = math.atan2(d.y, d.x) - phase
                k = int((((a + math.pi / lobes) % math.tau) / math.tau) * lobes) % lobes
                lobe = (0.5 + 0.5 * math.cos(lobes * a)) ** 2.5 * weights[k]
                f = (1.0 - bc.smoothstep(max(co.z, 0.0) / height)) ** 2
                s = 1.0 + amount * f * (0.3 + 0.7 * lobe)
                co.x, co.y = c.x + d.x * s, c.y + d.y * s
        if co.z < -sink:
            co.z = -sink


def _lumps(obj, amount, scale, seed):
    """A low, broad irregularity over the wood (bark is not a machined tube)."""
    off = Vector((seed * 0.37, seed * 0.11, seed * 0.73))
    obj.data.update()
    for v in obj.data.vertices:
        v.co += v.normal * (amount * noise.noise(v.co * scale + off))


def _bark_material(name, kind):
    """Bark from object-space noise, baked. "umbrella": dark warm grey-brown (LCh hue 60 to 68, chroma 9 to 12)
    with deep fibrous ridges that spiral round the trunk (the grain's coordinates turn with height), and paler
    weathered patches. "lantern": a smooth pale grey-tan with dark ring scars (horizontal bands) every 15 to 25 cm.
    No moss: a green on the bark would pull its mean toward the food green."""
    sh = sf.Shader(name)
    if kind == "umbrella":
        rot = sh.node("ShaderNodeVectorRotate", rotation_type="Z_AXIS")
        sh.link(sh.pos, rot.inputs["Vector"])
        sh.link(sh.math("MULTIPLY", sh.axis("Z"), 0.32), rot.inputs["Angle"])
        grain_v = sh.node("ShaderNodeVectorMath", operation="MULTIPLY")
        sh.link(rot.outputs["Vector"], grain_v.inputs[0])
        grain_v.inputs[1].default_value = (6.5, 6.5, 0.7)
        g = grain_v.outputs["Vector"]
        ridge = sh.voronoi(1.3, 1.0, vector=g, feature="DISTANCE_TO_EDGE")
        fibre = sh.noise(3.0, 6.0, 0.62, vector=g)
        groove = sh.remap(ridge, 0.0, 0.16)                          # 0 in the grooves, 1 on the ridges
        patch = sh.noise(0.7, 3.0, 0.5)
        tone = sh.math("ADD", sh.math("MULTIPLY", groove, 0.55), sh.math("MULTIPLY", sh.remap(fibre, 0.3, 0.7), 0.45), clamp=True)
        bark = sh.mix(tone, _lch_lin(27.0, 9.0, 60.0), _lch_lin(49.0, 12.0, 66.0))
        base = sh.mix(sh.math("MULTIPLY", sh.remap(patch, 0.55, 0.75), groove), bark, _lch_lin(58.0, 7.0, 70.0))
        sh.bump(sh.math("ADD", sh.math("MULTIPLY", groove, 0.75), sh.math("MULTIPLY", fibre, 0.25)), 0.6, 0.03)
        return sh.out(base, sh.remap(groove, 0.0, 1.0, 0.95, 0.82))
    ring_v = sh.node("ShaderNodeVectorMath", operation="MULTIPLY")
    sh.link(sh.pos, ring_v.inputs[0])
    ring_v.inputs[1].default_value = (0.6, 0.6, 5.0)
    wobble = sh.noise(1.2, 2.0, 0.5)
    rings = sh.math("SINE", sh.math("ADD", sh.math("MULTIPLY", sh.axis("Z"), math.tau / 0.19), sh.math("MULTIPLY", wobble, 3.0)))
    scar = sh.remap(rings, 0.82, 0.97)                               # thin dark bands
    speck = sh.noise(40.0, 3.0, 0.6)
    tone = sh.math("ADD", sh.math("MULTIPLY", sh.remap(sh.noise(5.0, 4.0, 0.6, vector=ring_v.outputs["Vector"]), 0.3, 0.7), 0.7), sh.math("MULTIPLY", speck, 0.3), clamp=True)
    bark = sh.mix(tone, _lch_lin(56.0, 6.0, 66.0), _lch_lin(71.0, 6.0, 72.0))
    base = sh.mix(scar, bark, _lch_lin(38.0, 8.0, 60.0))
    sh.bump(sh.math("SUBTRACT", sh.math("MULTIPLY", speck, 0.2), sh.math("MULTIPLY", scar, 0.8)), 0.5, 0.01)
    return sh.out(base, 0.7)


def _pod_material():
    """The lantern tree's seed pods: a pale lilac cream (LCh L 78 to 87, chroma 9 to 12, hue 302 to 308; no amber,
    which reads as fruit), softly mottled; the facets of the lathed pod carry its ribs."""
    sh = sf.Shader("M_LanternPodProc")
    mottle = sh.noise(30.0, 3.0)
    base = sh.mix(sh.remap(mottle, 0.3, 0.7), _lch_lin(78.0, 12.0, 302.0), _lch_lin(87.0, 9.0, 308.0))
    sh.bump(mottle, 0.15, 0.003)
    return sh.out(base, 0.6)


def _crown_normal(centre, radii, up=CANOPY_NORMAL_UP):
    """A canopy card vertex's lit normal: out of the crown's ellipsoid (centre, radii), leaned toward world up."""
    centre, radii = Vector(centre), Vector(radii)
    def lit(p):
        d = p - centre
        n = Vector((d.x / radii.x ** 2, d.y / radii.y ** 2, d.z / radii.z ** 2))
        if n.length < 1e-6:
            n = Vector((0.0, 0.0, 1.0))
        return (n.normalized() + Vector((0.0, 0.0, up))).normalized()
    return lit


def _check_tree(what, reach_max):
    pts = bc.world_vertices()
    low = min(p.z for p in pts)
    reach = max(math.hypot(p.x, p.y) for p in pts)
    mp._check(low < -0.03, f"{what}: its base sits under the ground ({low:.3f})")
    mp._check(low >= -0.2, f"{what}: sinks no more than 20 cm ({low:.3f})")
    mp._check(reach <= reach_max, f"{what}: keeps within {reach_max} m of its trunk ({reach:.2f})")
    return max(p.z for p in pts), reach


# Umbrella tree: a central crown pad and four lower pads round it, (centre, radius) in metres from the trunk base.
UMBRELLA_PADS = [((0.15, 0.05, 7.05), 1.95), ((2.35, 0.55, 6.05), 1.55), ((-1.25, 2.2, 6.25), 1.5),
                 ((-2.0, -1.15, 5.85), 1.6), ((0.85, -2.3, 6.35), 1.4)]
UMBRELLA_FORK = 4.5
UMBRELLA_WOOD = 1000        # triangles for the trunk and limbs after reduction
TREE_TEX = 1024


def _umbrella_axis(z):
    t = z / UMBRELLA_FORK
    return Vector((0.22 * math.sin(math.pi * t * 1.3), 0.16 * math.sin(math.pi * t * 0.8 + 0.5), z))


def build_tree_umbrella():
    """An umbrella tree about 7.5 m tall and 8 m across (PROPOSED, original): a bulbous trunk, swollen at about
    1.5 m like a water-storing bottle tree and narrowing to a fork, with five buttress roots flaring into the
    ground and a spiral bark grain; five limbs carry a layered umbrella crown of five flat-topped pads (a high
    central one and four lower ones round it), each a dome of leaf-spray cards laid in rings with a drooping
    fringe, so the silhouette is a broad, scalloped parasol. The wood is baked (1024); the cards share
    T_TreeCanopyCards and shade as one rounded crown (normals out of each pad)."""
    rng = random.Random(4401)
    sk = _Skeleton()
    trunk = sk.chain(lambda t: _umbrella_axis(-0.25 + (UMBRELLA_FORK + 0.25) * t),
                     _smooth_radius([(0.0, 0.42), (0.1, 0.44), (0.38, 0.56), (0.62, 0.42), (0.85, 0.27), (1.0, 0.21)]), 22)
    top = sk.chain(lambda t: _bezier(_umbrella_axis(UMBRELLA_FORK), _umbrella_axis(UMBRELLA_FORK) + Vector((0.0, 0.0, 1.2)),
                                     Vector(UMBRELLA_PADS[0][0]) - Vector((0.0, 0.0, 0.45)))(t),
                   _smooth_radius([(0.0, 0.2), (1.0, 0.1)]), 8, start=trunk[-1])
    for k, (centre, radius) in enumerate(UMBRELLA_PADS[1:]):
        z0 = UMBRELLA_FORK - 0.15 - 0.22 * k
        s = sk.nearest(trunk, z0)
        a = sk.verts[s].copy()
        end = Vector(centre) - Vector((0.0, 0.0, 0.4))
        mid = a + (end - a) * 0.3 + Vector((0.0, 0.0, 0.9))
        sk.chain(_bezier(a, mid, end), _smooth_radius([(0.0, 0.17), (0.4, 0.13), (1.0, 0.07)]), 9, start=s)
    obj = _skin("UmbrellaTree", sk.verts, sk.edges, [r * 1.12 for r in sk.radii], levels=3)
    _flare(obj, _umbrella_axis, 1.1, 5, 1.05, 4402, 0.12)
    _lumps(obj, 0.025, 1.6, 7)
    obj.data.materials.append(_bark_material("M_UmbrellaBarkProc", "umbrella"))
    for poly in obj.data.polygons:
        poly.use_smooth = True
    baked = _bake_rock(obj, UMBRELLA_WOOD, "CreatureTreeUmbrella", TREE_TEX)
    wood_tris = baked["reduction"]["triangles_after"]
    # The crown: per pad a ring of near-flat cards at the top, two rings sloping out and down, and a drooping
    # fringe, every card radial (its stem toward the pad's centre) and bent down at its tip.
    cards = _Cards(CANOPY_GRID)
    mat = _canopy_material()
    n_cards = 0
    for p, (centre, radius) in enumerate(UMBRELLA_PADS):
        c = Vector(centre)
        lit = _crown_normal(c - Vector((0.0, 0.0, 0.35 * radius)), (radius * 1.05, radius * 1.05, radius * 0.62))
        cards.lit = lit
        spin = rng.uniform(0.0, math.tau)
        rings = [(0.0, 3, 0.95, (8, 16), 0.15), (0.42, 7, 0.9, (14, 26), 0.3), (0.78, 10, 0.78, (30, 44), 0.4),
                 (0.98, 12, 0.66, (55, 72), 0.25)]
        for ring, (r_share, count, size, tilt, bend) in enumerate(rings):
            count = max(3, int(round(count * radius / 1.75)))
            for i in range(count):
                az = spin + math.tau * (i + 0.5 * (ring % 2)) / count + rng.uniform(-0.12, 0.12)
                out = Vector((math.cos(az), math.sin(az), 0.0))
                side = Vector((-math.sin(az), math.cos(az), 0.0))
                length = radius * size * rng.uniform(0.9, 1.08)
                dome = 0.3 * radius * (1.0 - r_share ** 2)                   # the pad's top is a low dome
                base = c + out * (radius * r_share - 0.35 * length) + Vector((0.0, 0.0, dome - 0.06 * ring))
                e0 = -math.radians(rng.uniform(*tilt))
                centres, sides = [], []
                q = base.copy()
                for k in range(3):
                    centres.append(q.copy())
                    sides.append(side)
                    e = e0 - bend * (k + 0.5) / 2
                    q = q + (out * math.cos(e) + Vector((0.0, 0.0, math.sin(e)))) * (length / 2)
                shade = rng.uniform(0.84, 1.0) if ring < 3 else rng.uniform(0.74, 0.9)
                cell = CANOPY_UMBRELLA_FINE if (ring + i + p) % 3 == 0 else CANOPY_UMBRELLA
                cards.strip(centres, sides, length * rng.uniform(0.42, 0.5), cell, rng.random() < 0.5, shade)
                n_cards += 1
    cards.build("UmbrellaCanopy", mat)
    top_z, reach = _check_tree("umbrella tree", 4.4)
    return _tree_record("Creature world tree (PROPOSED, original): an umbrella tree about %.1f m tall with a bulbous, buttressed trunk and a broad layered umbrella crown of leaf-spray cards." % top_z,
                        "UmbrellaTree", "UmbrellaCanopy", n_cards, wood_tris, top_z, reach, baked)


LANTERN_TOP = Vector((0.85, 0.3, 4.75))
LANTERN_WOOD = 1150


def _lantern_axis(z):
    t = max(0.0, min(1.0, z / LANTERN_TOP.z))
    return Vector((LANTERN_TOP.x * t ** 2.2, LANTERN_TOP.y * math.sin(math.pi * t * 0.9), z))


def _pod(centre, height, radius, sides=7, rings=6):
    """A pod: a lathed teardrop, its stalk end up."""
    verts, faces = [], []
    for k in range(rings + 1):
        t = k / rings
        r = radius * math.sin(math.pi * t) ** 0.8 * (1.0 - 0.35 * t)
        z = height * (0.5 - t)
        if k in (0, rings):
            verts.append(tuple(Vector(centre) + Vector((0.0, 0.0, z))))
            continue
        for j in range(sides):
            a = math.tau * j / sides
            verts.append(tuple(Vector(centre) + Vector((r * math.cos(a), r * math.sin(a), z))))
    top, bottom = 0, len(verts) - 1
    for j in range(sides):
        faces.append((top, 1 + (j + 1) % sides, 1 + j))
    for k in range(rings - 2):
        a0, b0 = 1 + k * sides, 1 + (k + 1) * sides
        for j in range(sides):
            jn = (j + 1) % sides
            faces.append((a0 + j, a0 + jn, b0 + jn, b0 + j))
    last = 1 + (rings - 2) * sides
    for j in range(sides):
        faces.append((last + j, last + (j + 1) % sides, bottom))
    return verts, faces


def build_tree_lantern():
    """A lantern tree about 5 m tall (PROPOSED, original): a slender trunk that rises in a slow curve and leans
    its crown out over its foot, with three small root flares and pale bark ringed with dark scars; the crown is a
    domed cap of fronds arching over a dense curtain of long turquoise fronds that falls almost straight down round
    it like a lampshade, and six round pale lilac-cream seed pods hang on fine pale stalks from the hub, down inside
    the curtain to about its hem, like lanterns in a shade. Wood, stalks and pods are baked (1024; the pods are kept
    out of the triangle reduction so they stay round); the cards share T_TreeCanopyCards and shade as one rounded
    crown."""
    rng = random.Random(4501)
    sk = _Skeleton()
    trunk = sk.chain(lambda t: _lantern_axis(-0.22 + (LANTERN_TOP.z + 0.22) * t),
                     _smooth_radius([(0.0, 0.2), (0.12, 0.17), (0.5, 0.13), (0.9, 0.105), (1.0, 0.14)]), 20)
    hub = trunk[-1]
    pods = []
    spin = rng.uniform(0.0, math.tau)
    for k in range(6):
        az = spin + math.tau * k / 6 + rng.uniform(-0.2, 0.2)
        out = Vector((math.cos(az), math.sin(az), 0.0))
        r = rng.uniform(0.55, 0.75)
        drop = rng.uniform(1.5, 2.0)
        a = LANTERN_TOP + out * 0.12
        end = LANTERN_TOP + out * r - Vector((0.0, 0.0, drop))
        mid = LANTERN_TOP + out * (r * 0.9) + Vector((0.0, 0.0, 0.05))
        sk.chain(_bezier(a, mid, end), lambda t: 0.012, 5, start=hub)
        pods.append(end - Vector((0.0, 0.0, 0.17)))
    obj = _skin("LanternTree", sk.verts, sk.edges, [r * 1.12 for r in sk.radii], levels=3)
    _flare(obj, _lantern_axis, 0.6, 3, 0.8, 4502, 0.1)
    _lumps(obj, 0.008, 3.0, 11)
    bark = _bark_material("M_LanternBarkProc", "lantern")
    pod_mat = _pod_material()
    obj.data.materials.append(bark)
    obj.data.materials.append(pod_mat)
    for poly in obj.data.polygons:                    # the stalks: pale like the pods, not ringed like the trunk
        c = poly.center
        poly.material_index = 1 if c.z > 2.0 and (Vector((c.x, c.y, 0.0)) - _lantern_axis(c.z).to_2d().to_3d()).length > 0.17 else 0
    pverts, pfaces = [], []
    for c in pods:
        v, f = _pod(c, rng.uniform(0.34, 0.4), rng.uniform(0.12, 0.14), sides=8, rings=6)
        bc.append(pverts, pfaces, v, f)
    pod_obj = bc.mesh_object("LanternPods", pverts, pfaces, [pod_mat])
    pod_obj.vertex_groups.new(name="Pods").add(list(range(len(pverts))), 1.0, "REPLACE")
    sf.select([obj, pod_obj])
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    for poly in obj.data.polygons:
        poly.use_smooth = True
    baked = _bake_rock(obj, LANTERN_WOOD, "CreatureTreeLantern", TREE_TEX, protect="Pods")
    wood_tris = baked["reduction"]["triangles_after"]
    cards = _Cards(CANOPY_GRID)
    mat = _canopy_material()
    crown = LANTERN_TOP - Vector((0.0, 0.0, 0.9))
    cards.lit = _crown_normal(crown, (1.4, 1.4, 1.6))
    n_cards = 0
    # The cap: fronds radiating from the hub, level at first and arching down over the curtain's top.
    for i in range(14):
        az = spin + math.tau * i / 14 + rng.uniform(-0.08, 0.08)
        out = Vector((math.cos(az), math.sin(az), 0.0))
        side = Vector((-math.sin(az), math.cos(az), 0.0))
        length = rng.uniform(1.15, 1.35)
        q = LANTERN_TOP + Vector((0.0, 0.0, 0.1)) - out * 0.1
        centres, sides = [], []
        e0 = math.radians(rng.uniform(10.0, 16.0))
        for k in range(3):
            centres.append(q.copy())
            sides.append(side)
            e = e0 - 0.9 * (k + 0.5) / 2
            q = q + (out * math.cos(e) + Vector((0.0, 0.0, math.sin(e)))) * (length / 2)
        cards.strip(centres, sides, rng.uniform(0.4, 0.46), CANOPY_CAP, rng.random() < 0.5, rng.uniform(0.88, 1.0))
        n_cards += 1
    # The curtain: long fronds from under the cap's rim, falling steeply and then straight down.
    count = 30
    for i in range(count):
        az = spin + math.tau * (i + 0.5) / count + rng.uniform(-0.05, 0.05)
        out = Vector((math.cos(az), math.sin(az), 0.0))
        side = Vector((-math.sin(az), math.cos(az), 0.0))
        length = rng.uniform(2.0, 2.6)
        q = LANTERN_TOP + out * rng.uniform(0.95, 1.08) - Vector((0.0, 0.0, rng.uniform(0.15, 0.3)))
        centres, sides = [], []
        for k in range(5):
            centres.append(q.copy())
            sides.append(side)
            e = -math.radians(50.0) - math.radians(40.0) * ((k + 0.5) / 4) ** 0.8
            q = q + (out * math.cos(e) + Vector((0.0, 0.0, math.sin(e)))) * (length / 4)
        cards.strip(centres, sides, rng.uniform(0.3, 0.36), CANOPY_CURTAIN, rng.random() < 0.5, rng.uniform(0.8, 1.0))
        n_cards += 1
    canopy = cards.build("LanternCanopy", mat)
    top_z, reach = _check_tree("lantern tree", 3.6)
    hem = min((canopy.matrix_world @ v.co).z for v in canopy.data.vertices)
    mp._check(hem > 1.6, f"lantern tree: the curtain's hem stays well above the ground, so the trunk shows under it ({hem:.2f})")
    record = _tree_record("Creature world tree (PROPOSED, original): a lantern tree about %.1f m tall, a slender curved trunk under a domed crown with a curtain of hanging turquoise fronds and pale lilac-cream seed pods." % top_z,
                          "LanternTree", "LanternCanopy", n_cards, wood_tris, top_z, reach, baked)
    record["pods"] = {"count": len(pods), "colour": "pale lilac cream, CIE LCh L 78 to 87, chroma 9 to 12, hue 302 to 308 (no amber: amber reads as fruit); the stalks the same",
                      "reduction": "kept out of the triangle reduction (vertex group), so they stay round"}
    return record


def _tree_record(purpose, wood, canopy, n_cards, wood_tris, top_z, reach, baked):
    textures = baked.pop("textures") + [canopy_atlas()]
    return {"purpose": purpose, "category": "environment", "kind": "tree",
            "pivot": "the trunk's foot on the ground (Godot y = 0); the roots sink about 10 cm so the tree sits into a slope",
            "placement": "an obstacle: OUTSIDE the walls only (the berm and the hills, where max(|x|, |z|) is 80.5 m or more, crown included) until the sim has obstacles (issue #210); tests/test_creature_world_art.gd keeps anything over 0.45 m out of the walkable field",
            "height_m": round(top_z, 2), "crown_reach_m": round(reach, 2),
            "wood": {"node": wood, "triangles": wood_tris, "lods": "Godot's generated LODs"},
            "canopy": {"node": canopy, "cards": n_cards, "atlas": CANOPY_PATH,
                       "material": "M_TreeCanopyCards (StandardMaterial3D: alpha scissor 0.5, back faces culled, COLOR_0 jitter)",
                       "sides": "two sheets back to back per card, opposite winding",
                       "normals": f"out of the crown's ellipsoid plus {CANOPY_NORMAL_UP} x world up on both sheets, so the crown shades as one rounded volume",
                       "lods": "none (Godot's LOD pass collapses whole cards)"},
            "vertex_colors_attribute": VC, "textures": textures, "revision": 1, "provenance": PROVENANCE_TREE, **baked}


# --- The field's scatter (field rev 2b): the kit composed into chunked meshes of creature_field_ground ------------

SCATTER_SEED = 6100
CHUNK_M = 20.0
CHUNKS = 8                  # 8 x 8 cover chunks of 20 m over +-80 m
COVER_EDGE_M = 78.3         # cover stays inside this square (the berm starts rising at 79 m)
COVER_CLEAR_M = 8.05        # and every vertex outside the nest's clearing (the art test's 8 m)
COVER_TRIS = 50000          # PROPOSED budgets: cover inside the walls, and the berm's trees and boulders
BERM_TRIS = 50000
COVER_VIS_END_M = 60.0      # a cover chunk draws while the camera is within this of its centre (its origin)
OBSTACLE_EDGE_M = 81.0      # every vertex of a berm piece stands at max(|x|, |y|) of this or more (the test's 80.5)
SECTORS = 8
TREE_SLOPE_MAX_M = 0.45     # a tree's foot: the ground may rise or fall this much within 1.2 m of its trunk
PATCH_ANGLE, PATCH_WARP, PATCH_M = 0.6, 0.22, 37.0   # as shaders/creature_field.gdshader reads its patch mask
EARTH_LOW, EARTH_HIGH = 0.56, 0.7
CLEARING_R, CLEARING_SOFT = 7.5, 3.0
# Stand-in materials in the field's .blend and GLB: no images, named as the kit's own, and mapped in the field's
# .glb.import to the .tres files map_materials writes (so the field GLB embeds no copy of a kit texture).
KIT_MATERIALS = {
    # material: (kit id it comes from, baked texture set or None for a card atlas, sRGB tint or None, stand-in colour)
    "M_MeadowCards": ("creature_grass_tuft", None, None, "#4E7A52"),
    "M_Pebble": ("creature_pebble_cluster", "CreaturePebbleCluster", "#8C8070", "#8C8070"),
    "M_CreatureBoulderA": ("creature_boulder_a", "CreatureBoulderA", None, "#7D8287"),
    "M_CreatureBoulderB": ("creature_boulder_b", "CreatureBoulderB", None, "#7D8287"),
    "M_CreatureBoulderC": ("creature_boulder_c", "CreatureBoulderC", None, "#7D8287"),
    "M_TreeCanopyCards": ("creature_tree_umbrella", None, None, "#3D8A72"),
    "M_CreatureTreeUmbrella": ("creature_tree_umbrella", "CreatureTreeUmbrella", None, "#5A5047"),
    "M_CreatureTreeLantern": ("creature_tree_lantern", "CreatureTreeLantern", None, "#A49B90"),
}
COVER_KIT = ("creature_grass_tuft", "creature_fern_clump", "creature_flower_clump", "creature_pebble_cluster")
BERM_KIT = ("creature_tree_umbrella", "creature_tree_lantern", "creature_boulder_a", "creature_boulder_b", "creature_boulder_c")
CLUSTERS = {
    # cluster: ([(kit id, fewest, most)], spread sigma range in metres)
    "tufts": ([("creature_grass_tuft", 4, 9), ("creature_flower_clump", 0, 1)], (0.45, 1.1)),
    "ferns": ([("creature_fern_clump", 2, 4), ("creature_grass_tuft", 1, 3)], (0.55, 1.2)),
    "flowers": ([("creature_flower_clump", 3, 6), ("creature_grass_tuft", 1, 3)], (0.45, 1.0)),
    "stones": ([("creature_pebble_cluster", 1, 3), ("creature_grass_tuft", 0, 2)], (0.4, 0.9)),
}
CLUSTERS_PER_CHUNK = 7.0    # before thinning to the budget
SINGLES_PER_CHUNK = 5.0


class _Kit:
    """One kit asset read back from its exported GLB: per source mesh, the arrays a merged copy needs."""

    def __init__(self, asset_id):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets", "export", f"{asset_id}.glb"))
        objs = [o for o in bpy.data.objects if o not in before]
        self.id, self.parts = asset_id, []
        lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
        for obj in sorted((o for o in objs if o.type == "MESH"), key=lambda o: o.name):
            m = obj.data
            world = np.array(obj.matrix_world)                       # the importer's node transform, if any
            normal_m = np.array(obj.matrix_world.to_3x3().inverted().transposed())
            verts = np.array([v.co[:] for v in m.vertices]) @ world[:3, :3].T + world[:3, 3]
            polys = [tuple(p.vertices) for p in m.polygons]
            normals = np.array([n.vector[:] for n in m.corner_normals]) @ normal_m.T
            normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
            uv = m.uv_layers.active
            uvs = np.array([d.uv[:] for d in uv.data])
            colours = None
            if len(m.color_attributes):
                attr = m.color_attributes[0]
                vals = np.array([d.color[:3] for d in attr.data])
                if attr.domain == "CORNER":                       # one colour a card: any corner of a vertex will do
                    per_vertex = np.ones((len(verts), 3))
                    for loop in m.loops:
                        per_vertex[loop.vertex_index] = vals[loop.index]
                    vals = per_vertex
                colours = vals
            mats = [m.materials[p.material_index].name.split(".")[0] for p in m.polygons]
            self.parts.append({"name": obj.name, "verts": verts, "polys": polys, "normals": normals, "uvs": uvs,
                               "colours": colours, "mats": mats, "cards": colours is not None})
            lo = Vector(np.minimum(lo, verts.min(axis=0)))
            hi = Vector(np.maximum(hi, verts.max(axis=0)))
        self.tris = sum(len(p) - 2 for part in self.parts for p in part["polys"])
        self.top = hi.z
        self.reach = max(float(np.hypot(part["verts"][:, 0], part["verts"][:, 1]).max()) for part in self.parts)
        for obj in objs:
            bpy.data.objects.remove(obj)


class _Merged:
    """The merged copies going into one field object: vertices, faces, corner normals and UVs, vertex colours."""

    def __init__(self, name, origin):
        self.name, self.origin = name, Vector(origin)
        self.verts, self.faces, self.normals, self.uvs, self.cols, self.mats = [], [], [], [], [], []
        self.tris = 0

    def add(self, part, at, yaw, scale, shade=1.0):
        c, s = math.cos(yaw), math.sin(yaw)
        rot = np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])
        base = len(self.verts)
        pts = part["verts"] @ rot.T * scale + (np.array(at[:]) - np.array(self.origin[:]))
        self.verts.extend(map(tuple, pts))
        self.faces.extend(tuple(i + base for i in p) for p in part["polys"])
        self.normals.extend(map(tuple, part["normals"] @ rot.T))
        self.uvs.extend(map(tuple, part["uvs"]))
        cols = part["colours"] if part["colours"] is not None else np.ones((len(pts), 3))
        self.cols.extend(map(tuple, np.clip(cols * shade, 0.0, 1.0)))
        self.mats.extend(part["mats"])
        self.tris += sum(len(p) - 2 for p in part["polys"])

    def build(self, materials, colours):
        if not self.faces:
            return None
        mesh = bpy.data.meshes.new(f"{self.name}_mesh")
        mesh.from_pydata(self.verts, [], self.faces)
        names = sorted(set(self.mats))
        for n in names:
            mesh.materials.append(materials[n])
        mesh.polygons.foreach_set("material_index", [names.index(n) for n in self.mats])
        mesh.polygons.foreach_set("use_smooth", [True] * len(self.faces))
        layer = mesh.uv_layers.new(name="UVMap")
        layer.data.foreach_set("uv", [c for uv in self.uvs for c in uv])
        if colours:
            attr = mesh.color_attributes.new(name=VC, type="FLOAT_COLOR", domain="POINT")
            attr.data.foreach_set("color", [c for rgb in self.cols for c in (*rgb, 1.0)])
        mesh.normals_split_custom_set(self.normals)
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = self.origin
        return obj


def _stand_ins():
    """The stand-in materials: a flat colour each, no images (Godot maps them to the kit's .tres)."""
    out = {}
    for name, (_kit, _tex, _tint, colour) in KIT_MATERIALS.items():
        out[name] = bc.material(name, _lin(colour), 0.9)
    return out


class _PatchMask:
    """The field shader's earth weight and lush mask (shaders/creature_field.gdshader), sampled from the patch
    tile as the shader samples it (world xz, rotated, domain-warped, bilinear, repeating), so cover follows the
    turf and the bare earth the player sees."""

    def __init__(self):
        img = bpy.data.images.load(os.path.join(ROOT, "assets", "export", "creature_field", "T_CreatureField_Patch.png"))
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        self.r = px.reshape(h, w, 4)[::-1, :, 0].astype(np.float64)    # top row first, as a shader's v runs
        bpy.data.images.remove(img)

    def sample(self, u, v):
        h, w = self.r.shape
        x, y = u * w - 0.5, v * h - 0.5
        x0, y0 = math.floor(x), math.floor(y)
        fx, fy = x - x0, y - y0
        a = self.r[y0 % h, x0 % w] * (1 - fx) + self.r[y0 % h, (x0 + 1) % w] * fx
        b = self.r[(y0 + 1) % h, x0 % w] * (1 - fx) + self.r[(y0 + 1) % h, (x0 + 1) % w] * fx
        return a * (1 - fy) + b * fy

    def earth(self, x, y):
        X, Z = x, -y                                                    # Blender (x, y) is Godot (x, -z)
        c, s = math.cos(PATCH_ANGLE), math.sin(PATCH_ANGLE)
        pu, pv = (c * X - s * Z) / PATCH_M, (s * X + c * Z) / PATCH_M
        wu, wv = self.sample(pu * 1.9 + 0.21, pv * 1.9 + 0.53), self.sample(pu * 1.9 + 0.71, pv * 1.9 + 0.08)
        pu, pv = pu + PATCH_WARP * (wu - 0.5) * 2.0, pv + PATCH_WARP * (wv - 0.5) * 2.0
        t = bc.smoothstep((self.sample(pu, pv) - EARTH_LOW) / (EARTH_HIGH - EARTH_LOW))
        clearing = 1.0 - bc.smoothstep((math.hypot(x, y) - CLEARING_R) / CLEARING_SOFT)
        return max(t, clearing)

    def lush(self, x, y):
        return bc.smoothstep((self.sample(x / (PATCH_M * 0.61) + 0.63, -y / (PATCH_M * 0.61) + 0.12) - 0.5) / 0.3)


class _Ground:
    """Ray casts down onto the field and hills meshes, so every piece stands on the surface the game draws."""

    def __init__(self, objs):
        from mathutils.bvhtree import BVHTree
        deps = bpy.context.evaluated_depsgraph_get()
        self.trees = [BVHTree.FromObject(o, deps) for o in objs]

    def z(self, x, y):
        best = None
        for tree in self.trees:
            hit = tree.ray_cast(Vector((x, y, 200.0)), Vector((0.0, 0.0, -1.0)))
            if hit[0] is not None and (best is None or hit[0].z > best):
                best = hit[0].z
        mp._check(best is not None, f"scatter: ground under ({x:.1f}, {y:.1f})")
        return best


def _cover_layout(kits, mask, ground):
    """Clusters of cover over the walkable field: each cluster's kind follows the ground under its centre (stones
    on the bare earth, tufts on its edges, tufts, ferns and flowers on the turf, more flowers where the turf is
    lush), and single tufts scattered between. Then whole clusters are dropped, in a seeded order, until the cover
    fits COVER_TRIS. Returns {chunk: [(kit id, position, yaw, scale, shade)]}."""
    clusters = []
    for ci in range(CHUNKS):
        for cj in range(CHUNKS):
            rng = random.Random(SCATTER_SEED * 100 + ci * CHUNKS + cj)
            x0, y0 = -CHUNKS * CHUNK_M / 2 + ci * CHUNK_M, -CHUNKS * CHUNK_M / 2 + cj * CHUNK_M
            groups = [("cluster", n) for n in range(_poisson(rng, CLUSTERS_PER_CHUNK))] + \
                     [("single", n) for n in range(_poisson(rng, SINGLES_PER_CHUNK))]
            for kind, _n in groups:
                cx, cy = x0 + rng.uniform(0.0, CHUNK_M), y0 + rng.uniform(0.0, CHUNK_M)
                if max(abs(cx), abs(cy)) > COVER_EDGE_M - 0.6 or math.hypot(cx, cy) < COVER_CLEAR_M + 0.8:
                    continue
                earth = mask.earth(cx, cy)
                if kind == "single":
                    if earth > 0.4:
                        continue
                    members, spread = [("creature_grass_tuft", 1, 1)], (0.0, 0.0)
                else:
                    if earth > 0.55:
                        name = "stones"
                    elif earth > 0.3:
                        name = rng.choice(("tufts", "stones"))
                    else:
                        lush = mask.lush(cx, cy)
                        name = _weighted(rng, {"tufts": 0.45, "ferns": 0.25, "flowers": 0.3 * (0.6 + lush)})
                    members, spread = CLUSTERS[name]
                sigma = rng.uniform(*spread)
                pieces = []
                for kit_id, lo, hi in members:
                    for _ in range(rng.randint(lo, hi)):
                        kit = kits[kit_id]
                        scale = min(rng.uniform(0.8, 1.12), (COVER_MAX_M - 0.02) / kit.top)
                        for _try in range(12):
                            px, py = cx + rng.gauss(0.0, sigma), cy + rng.gauss(0.0, sigma)
                            reach = kit.reach * scale
                            if max(abs(px), abs(py)) + reach > COVER_EDGE_M or math.hypot(px, py) - reach < COVER_CLEAR_M:
                                continue
                            if any(math.hypot(px - q[1][0], py - q[1][1]) < 0.55 * (reach + q[5]) for q in pieces):
                                continue
                            pieces.append((kit_id, (px, py), rng.uniform(0.0, math.tau), scale, rng.uniform(0.88, 1.0), reach))
                            break
                if pieces:
                    clusters.append((rng.random(), pieces))
    clusters.sort(key=lambda c: c[0])
    tris = sum(kits[p[0]].tris for _k, ps in clusters for p in ps)
    while tris > COVER_TRIS:
        _k, dropped = clusters.pop()
        tris -= sum(kits[p[0]].tris for p in dropped)
    out = {}
    for _k, pieces in clusters:
        for kit_id, (px, py), yaw, scale, shade, _reach in pieces:
            ci = min(CHUNKS - 1, int((px + CHUNKS * CHUNK_M / 2) // CHUNK_M))
            cj = min(CHUNKS - 1, int((py + CHUNKS * CHUNK_M / 2) // CHUNK_M))
            out.setdefault((ci, cj), []).append((kit_id, Vector((px, py, ground.z(px, py))), yaw, scale, shade))
    return out, tris


def _poisson(rng, mean):
    k, p, limit = 0, 1.0, math.exp(-mean)
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


def _weighted(rng, weights):
    total = sum(weights.values())
    r = rng.uniform(0.0, total)
    for name in sorted(weights):
        r -= weights[name]
        if r <= 0.0:
            return name
    return sorted(weights)[-1]


def _ring_point(angle, d):
    """The point at `angle` (radians) whose square distance max(|x|, |y|) from the origin is d."""
    c, s = math.cos(angle), math.sin(angle)
    k = d / max(abs(c), abs(s))
    return c * k, s * k


def _berm_layout(kits, ground):
    """Per sector (eighths of the ring, by angle), a grove of an umbrella and a lantern tree, and a third tree, on
    the hills just past the berm, and boulders on the berm's crest and outer slope, some at the grove's foot. Every
    piece keeps its whole footprint at max(|x|, |y|) >= OBSTACLE_EDGE_M (outside the walls), and trees stand only
    where the ground is near level. The third trees and the boulders are dropped in a seeded order until the berm
    fits BERM_TRIS.
    Returns {sector: [(kit id, position, yaw, scale, 1.0)]}."""
    picks = []
    placed = []                                       # (x, y, footprint radius) of every piece so far
    def clear(x, y, r):
        return all(math.hypot(x - qx, y - qy) >= r + qr for qx, qy, qr in placed)
    for k in range(SECTORS):
        rng = random.Random(SCATTER_SEED * 7 + k)
        mid = math.tau * k / SECTORS
        grove = mid + rng.uniform(-0.25, 0.25)
        trees = ["creature_tree_umbrella", "creature_tree_lantern"]
        if rng.random() < 0.5:
            trees.reverse()
        trees.append("creature_tree_umbrella" if k % 2 else "creature_tree_lantern")   # a third, kept if the budget allows
        for n, kit_id in enumerate(trees):
            kit = kits[kit_id]
            scale = rng.uniform(0.95, 1.3) if kit_id == "creature_tree_umbrella" else rng.uniform(0.9, 1.2)
            key = 0.0 if n < 2 else rng.uniform(0.0, 1.0)
            for _try in range(30):
                a = grove + (n - 1.0) * rng.uniform(0.06, 0.1) + rng.uniform(-0.02, 0.02)
                d = rng.uniform(87.0, 97.0) + 2.0 * (n % 2)
                x, y = _ring_point(a, d)
                if max(abs(x), abs(y)) - kit.reach * scale < OBSTACLE_EDGE_M + 0.5:
                    continue
                if not clear(x, y, 1.2):
                    continue
                around = [ground.z(x + 1.2 * math.cos(t), y + 1.2 * math.sin(t)) for t in np.linspace(0.0, math.tau, 6, endpoint=False)]
                if max(around) - min(around) > TREE_SLOPE_MAX_M:
                    continue
                picks.append((k, key, kit_id, Vector((x, y, min(around) - 0.03)), rng.uniform(0.0, math.tau), scale))
                placed.append((x, y, 1.2))
                break
        for n in range(rng.randint(3, 4)):
            kit_id = rng.choice(("creature_boulder_a", "creature_boulder_a", "creature_boulder_b", "creature_boulder_b", "creature_boulder_c"))
            kit = kits[kit_id]
            scale = rng.uniform(0.8, 1.2)
            near_grove = n < 2
            for _try in range(30):
                a = (grove + rng.uniform(-0.12, 0.12)) if near_grove else (mid + rng.uniform(-0.38, 0.38))
                d = rng.uniform(82.0, 92.0) if near_grove else rng.uniform(81.5, 87.0)
                x, y = _ring_point(a, d)
                if max(abs(x), abs(y)) - kit.reach * scale < OBSTACLE_EDGE_M:
                    continue
                if not clear(x, y, kit.reach * scale * 0.85):
                    continue
                r = kit.reach * scale * 0.9
                around = [ground.z(x + r * math.cos(t), y + r * math.sin(t)) for t in np.linspace(0.0, math.tau, 6, endpoint=False)]
                sink = 0.12 * kit.top * scale
                picks.append((k, rng.uniform(1e-6, 1.0), kit_id, Vector((x, y, min(around) + 0.4 * sink)), rng.uniform(0.0, math.tau), scale))
                placed.append((x, y, kit.reach * scale * 0.85))
                break
    kept = [p for p in picks if p[1] == 0.0]                       # two trees a sector, always
    optional = sorted((p for p in picks if p[1] > 0.0), key=lambda p: p[1])
    tris = sum(kits[p[2]].tris for p in picks)
    while tris > BERM_TRIS and optional:
        tris -= kits[optional.pop()[2]].tris
    out = {}
    for k, _key, kit_id, at, yaw, scale in kept + optional:
        out.setdefault(k, []).append((kit_id, at, yaw, scale, 1.0))
    return out, tris


def _centre(items):
    xs = [p[1].x for p in items]
    ys = [p[1].y for p in items]
    return Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, 0.0))


def build_field_scatter(ground_objs):
    """Composes the kit into the field (field rev 2b, PROPOSED; no game code): the cover as 8 x 8 chunks of 20 m
    inside the walls (CoverIJ_Cards and CoverIJ_Stones, each object's origin at its chunk's centre so a visibility
    range reads the same from either end), and the trees and boulders as 8 sectors on the berm and hills outside
    the walls (BermK_Cards and BermK_Wood). Each piece is a merged copy of a kit GLB's meshes (their UVs, corner
    normals and card colours), turned, scaled and set on the ground by a ray cast. Returns the record's `scatter`
    block."""
    kits = {kit_id: _Kit(kit_id) for kit_id in COVER_KIT + BERM_KIT}
    for mat in list(bpy.data.materials):                               # the kit's own materials and images go
        if mat.name.split(".")[0] in KIT_MATERIALS or mat.users == 0:
            mat.name = f"_kit_{mat.name}"
    materials = _stand_ins()
    mask, ground = _PatchMask(), _Ground(ground_objs)
    cover, cover_tris = _cover_layout(kits, mask, ground)
    berm, berm_tris = _berm_layout(kits, ground)
    counts, nodes = {}, []
    groups = [((f"Cover{ci}{cj}", Vector((-CHUNKS * CHUNK_M / 2 + (ci + 0.5) * CHUNK_M, -CHUNKS * CHUNK_M / 2 + (cj + 0.5) * CHUNK_M, 0.0))), items)
              for (ci, cj), items in sorted(cover.items())]
    groups += [((f"Berm{k}", _centre(items)), items) for k, items in sorted(berm.items())]
    for (name, origin), items in groups:
        cards, solid = _Merged(f"{name}_Cards", origin), _Merged(f"{name}_Stones" if name.startswith("Cover") else f"{name}_Wood", origin)
        for kit_id, at, yaw, scale, shade in items:
            counts[kit_id] = counts.get(kit_id, 0) + 1
            for part in kits[kit_id].parts:
                (cards if part["cards"] else solid).add(part, at, yaw, scale, shade)
        for merged, coloured in ((cards, True), (solid, False)):
            if merged.build(materials, coloured) is not None:
                nodes.append(merged.name)
    for mat in [m for m in bpy.data.materials if m.name.startswith("_kit_")]:
        bpy.data.materials.remove(mat)
    for img in [i for i in bpy.data.images if i.users == 0]:
        bpy.data.images.remove(img)
    for mesh in [m for m in bpy.data.meshes if m.users == 0]:
        bpy.data.meshes.remove(mesh)
    bpy.context.view_layer.update()                                    # the new objects' world matrices
    pts = [(o, o.matrix_world @ v.co) for o in bpy.context.scene.objects if o.name.startswith(("Cover", "Berm")) for v in o.data.vertices]
    for o, p in pts:
        if o.name.startswith("Cover"):
            mp._check(math.hypot(p.x, p.y) >= COVER_CLEAR_M - 0.05 and max(abs(p.x), abs(p.y)) <= COVER_EDGE_M + 0.05 and p.z <= COVER_MAX_M + 0.13,
                      f"scatter: {o.name} keeps to the walkable cover rules ({p.x:.2f}, {p.y:.2f}, {p.z:.2f})")
        else:
            mp._check(max(abs(p.x), abs(p.y)) >= OBSTACLE_EDGE_M - 0.05, f"scatter: {o.name} stays outside the walls ({p.x:.2f}, {p.y:.2f})")
    print(f"  scatter: cover {cover_tris} triangles in {sum(1 for n in nodes if n.startswith('Cover'))} objects, berm {berm_tris} in "
          f"{sum(1 for n in nodes if n.startswith('Berm'))}; pieces {counts}")
    return {"generator": "tools/blender/creature_flora.py build_field_scatter (through make_creature_world.py)",
            "kit": {kit_id: {"pieces": counts.get(kit_id, 0), "triangles_each": kits[kit_id].tris, "source": f"assets/export/{kit_id}.glb"} for kit_id in COVER_KIT + BERM_KIT},
            "seed": SCATTER_SEED,
            "cover": {"triangles": cover_tris, "budget": COVER_TRIS, "chunks": f"{CHUNKS} x {CHUNKS} of {CHUNK_M:g} m, CoverIJ_Cards and CoverIJ_Stones, origin at the chunk centre",
                      "inside_m": COVER_EDGE_M, "clear_of_nest_m": COVER_CLEAR_M, "height_max_m": COVER_MAX_M,
                      "density": f"Poisson, {CLUSTERS_PER_CHUNK:g} clusters and {SINGLES_PER_CHUNK:g} single tufts per chunk before whole clusters are dropped in a seeded order to the budget; stones on the bare earth (shader patch mask), tufts on its edges, tufts, ferns and flowers on the turf (flowers more where it is lush)",
                      "clusters": {k: {"members": [list(m) for m in v[0]], "spread_sigma_m": list(v[1])} for k, v in CLUSTERS.items()},
                      "import": f"no shadow, visibility range end {COVER_VIS_END_M:g} m, card meshes without LODs"},
            "berm": {"triangles": berm_tris, "budget": BERM_TRIS, "sectors": f"{SECTORS} by angle, BermK_Cards (canopy, no LODs) and BermK_Wood (bark and boulders, Godot's LODs)",
                     "outside_m": OBSTACLE_EDGE_M, "tree_slope_max_m": TREE_SLOPE_MAX_M,
                     "layout": "per sector a grove of one umbrella and one lantern tree and a third tree at 87 to 99 m (umbrellas scaled 0.95 to 1.3, lanterns 0.9 to 1.2), three or four boulders on the berm's crest and outer slope (81.5 to 92 m), some at the grove's foot; the third trees and the boulders dropped in a seeded order to the budget"},
            "materials": {name: (f"res://assets/export/{name}.tres") for name in KIT_MATERIALS},
            "nodes": nodes}


def scatter_import_options(nodes):
    """The field's per-node and per-mesh import options for its scatter objects (from the record's node list)."""
    out = {"meshes": {}, "nodes": {}}
    for name in nodes:
        if name.endswith("_Cards"):
            out["meshes"][f"creature_field_ground_{name}_mesh"] = {"generate/lods": 2}
        if name.startswith("Cover"):
            out["nodes"][f"PATH:{name}"] = {"mesh_instance/cast_shadow": 0, "mesh_instance/visibility_range_end": COVER_VIS_END_M}
    return out


BAKED_TRES = """[gd_resource type="StandardMaterial3D" load_steps=4 format=3]

; {mat}: the creature field's merged copies of {kit} (field rev 2b scatter, tools/blender/creature_flora.py
; build_field_scatter) draw with the kit asset's own baked textures, which Godot extracted from
; assets/export/{kit}.glb, as that GLB's material does (its base colour factor as the albedo colour; roughness in
; the ORM's green; metallic is 0 throughout, the ORM's blue). The field's stand-in {mat} is mapped here in its
; .glb.import. Written by tools/blender/make_creature_world.py --import.

[ext_resource type="Texture2D" path="res://assets/export/{kit}_T_{tex}_Albedo.png" id="1_albedo"]
[ext_resource type="Texture2D" path="res://assets/export/{kit}_T_{tex}_ORM.png" id="2_orm"]
[ext_resource type="Texture2D" path="res://assets/export/{kit}_T_{tex}_Normal.png" id="3_normal"]

[resource]
resource_name = "{mat}"
albedo_color = Color({r}, {g}, {b}, 1)
albedo_texture = ExtResource("1_albedo")
roughness_texture = ExtResource("2_orm")
roughness_texture_channel = 1
normal_enabled = true
normal_texture = ExtResource("3_normal")
"""


def write_kit_materials(export):
    """The .tres files the field's baked stand-ins map to (the card stand-ins map to M_MeadowCards.tres and
    M_TreeCanopyCards.tres)."""
    for name, (kit, tex, tint, _colour) in KIT_MATERIALS.items():
        if tex is None:
            continue
        r, g, b = (round(int((tint or "#FFFFFF").lstrip("#")[i:i + 2], 16) / 255.0, 3) for i in (0, 2, 4))
        with open(os.path.join(export, f"{name}.tres"), "w") as f:
            f.write(BAKED_TRES.format(mat=name, kit=kit, tex=tex, r=r, g=g, b=b))
        print("kit material:", name)


# --- The card GLBs' atlas link ----------------------------------------------------------------------------------

def link_atlas(glb_path, name=ATLAS, path=ATLAS_PATH):
    """Rewrites a card GLB so its atlas image `name` points at the shared atlas file (a relative URI, e.g.
    creature_flora/T_MeadowCards.png) instead of embedding a copy of it: the repository then holds one atlas, not
    one per card GLB, and a glTF viewer or Godot's importer still finds the texture beside the GLB. The image's
    bufferView is dropped and the binary chunk repacked; other (baked) images stay embedded."""
    import json
    import struct
    with open(glb_path, "rb") as f:
        data = f.read()
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    mp._check(magic == b"glTF" and version == 2, f"{glb_path}: a glTF 2 binary")
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    doc = json.loads(data[20:20 + json_len])
    bin_at = 20 + json_len
    bin_len, bin_type = struct.unpack_from("<I4s", data, bin_at)
    blob = data[bin_at + 8:bin_at + 8 + bin_len]
    drop = set()
    for img in doc.get("images", []):
        if img.get("name") == name and "bufferView" in img:
            drop.add(img.pop("bufferView"))
            img.pop("mimeType", None)
            img["uri"] = os.path.relpath(os.path.join(ROOT, path), os.path.dirname(glb_path)).replace(os.sep, "/")
    mp._check(len(drop) == 1, f"{glb_path}: one embedded {name} to link")
    views, remap, packed = [], {}, b""
    for i, view in enumerate(doc["bufferViews"]):
        if i in drop:
            continue
        chunk = blob[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        packed += b"\0" * (-len(packed) % 4)
        view["byteOffset"] = len(packed)
        packed += chunk
        remap[i] = len(views)
        views.append(view)
    doc["bufferViews"] = views
    for acc in doc.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
    for img in doc.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = remap[img["bufferView"]]
    packed += b"\0" * (-len(packed) % 4)
    doc["buffers"][0]["byteLength"] = len(packed)
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(text) + 8 + len(packed))
    out += struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(packed), b"BIN\0") + packed
    with open(glb_path, "wb") as f:
        f.write(out)
    print(f"  {os.path.basename(glb_path)}: the atlas linked by URI, {len(data) // 1024} KB -> {len(out) // 1024} KB")


# --- Registration (read by make_creature_world.py) --------------------------------------------------------------

CARD_ASSETS = {"creature_grass_tuft": "GrassTuft", "creature_fern_clump": "FernClump", "creature_flower_clump": "FlowerClump"}
# tree id -> (wood node, canopy card node)
TREE_ASSETS = {"creature_tree_umbrella": ("UmbrellaTree", "UmbrellaCanopy"), "creature_tree_lantern": ("LanternTree", "LanternCanopy")}
# asset id -> the shared atlas its GLB links by URI after export (make_creature_world.main)
ATLAS_LINKS = {**{asset_id: (ATLAS, ATLAS_PATH) for asset_id in CARD_ASSETS},
               **{asset_id: (CANOPY_ATLAS, CANOPY_PATH) for asset_id in TREE_ASSETS}}

# asset id -> (builder, triangle budget)
ASSETS = {
    "creature_grass_tuft": (build_grass_tuft, 48),
    "creature_fern_clump": (build_fern_clump, 96),
    "creature_flower_clump": (build_flower_clump, 120),
    "creature_pebble_cluster": (build_pebble_cluster, 160),
    **{asset_id: ((lambda i=asset_id: build_boulder(i)), spec[2]) for asset_id, spec in BOULDERS.items()},
    "creature_tree_umbrella": (build_tree_umbrella, 3000),
    "creature_tree_lantern": (build_tree_lantern, 2500),
}

EXTERNAL = {**{asset_id: {"M_MeadowCards": "M_MeadowCards"} for asset_id in CARD_ASSETS},
            **{asset_id: {"M_TreeCanopyCards": "M_TreeCanopyCards"} for asset_id in TREE_ASSETS}}

# The cards keep no LODs (Godot's LOD pass collapses whole cards) and cast no shadow (cover; the field's scatter
# draws its cover without shadows too). A tree's canopy keeps no LODs either but casts its shadow (it stands
# outside the walls, where its shade grounds it on the berm); its wood keeps Godot's generated LODs.
IMPORT_OPTIONS = {**{asset_id: {"meshes": {f"{asset_id}_{node}_mesh": {"generate/lods": 2}},
                                "nodes": {f"PATH:{node}": {"mesh_instance/cast_shadow": 0}}}
                     for asset_id, node in CARD_ASSETS.items()},
                  **{asset_id: {"meshes": {f"{asset_id}_{canopy}_mesh": {"generate/lods": 2}}}
                     for asset_id, (_wood, canopy) in TREE_ASSETS.items()}}

MEADOW_TRES = """[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

; The creature world's meadow cards (assets/records/creature_grass_tuft.json, creature_fern_clump.json,
; creature_flower_clump.json; tools/blender/creature_flora.py): the T_MeadowCards atlas's authored colour times the
; mesh's COLOR_0 (a greyscale brightness per card, read as sRGB), cut out by the atlas's alpha (transparency 2 is
; TRANSPARENCY_ALPHA_SCISSOR, at 0.5; 1 would be alpha blending, sorted and without depth writes). Back
; faces are culled: every card is two sheets back to back, each with a normal leaned toward world up, so both sides
; light like the ground. A StandardMaterial3D rather than a shader, so the field can carry merged copies beside its
; own ShaderMaterial.
; It reads the authored atlas, which the card GLBs link by URI rather than embed. Each card GLB's .glb.import points
; the imported M_MeadowCards here. Written by tools/blender/make_creature_world.py --import.

[ext_resource type="Texture2D" path="res://{atlas}" id="1_albedo"]

[resource]
resource_name = "M_MeadowCards"
transparency = 2
alpha_scissor_threshold = 0.5
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
albedo_texture = ExtResource("1_albedo")
metallic_specular = 0.3
roughness = 0.9
"""


CANOPY_TRES = """[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

; The creature world trees' canopy cards (assets/records/creature_tree_umbrella.json, creature_tree_lantern.json;
; tools/blender/creature_flora.py): the T_TreeCanopyCards atlas's authored colour times the mesh's COLOR_0 (a
; greyscale brightness per card, read as sRGB), cut out by the atlas's alpha (transparency 2, alpha scissor at 0.5).
; Back faces are culled: every card is two sheets back to back whose normals point out of the crown, so the crown
; shades as one rounded volume from any side. It casts shadows (the scissor cuts them out too) but receives none:
; a card's lower sheet lies 1.2 mm under its upper one, so with shadows received every underside fell into its own
; card's shadow and the crown read as black and mint blotches (the first engine frames); the crown's rounded normals
; shade it instead. A StandardMaterial3D, so the field can carry merged copies beside its own ShaderMaterial. Each
; tree GLB's .glb.import and the field's point the imported M_TreeCanopyCards here. Written by
; tools/blender/make_creature_world.py --import.

[ext_resource type="Texture2D" path="res://{atlas}" id="1_albedo"]

[resource]
resource_name = "M_TreeCanopyCards"
transparency = 2
disable_receive_shadows = true
alpha_scissor_threshold = 0.5
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
albedo_texture = ExtResource("1_albedo")
metallic_specular = 0.25
roughness = 0.85
"""


def map_materials(export, set_import_param):
    """Writes M_MeadowCards.tres and M_TreeCanopyCards.tres and gives their atlases mipmaps.
    make_creature_world.map_materials calls this."""
    with open(os.path.join(export, "M_MeadowCards.tres"), "w") as f:
        f.write(MEADOW_TRES.format(atlas=ATLAS_PATH))
    with open(os.path.join(export, "M_TreeCanopyCards.tres"), "w") as f:
        f.write(CANOPY_TRES.format(atlas=CANOPY_PATH))
    for name in (ATLAS, CANOPY_ATLAS):
        path = os.path.join(FLORA_DIR, f"{name}.png.import")
        if os.path.exists(path):
            set_import_param(path, "mipmaps/generate", "true")
            print("mipmaps:", name)
