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

    def __init__(self, rng, under_lch):
        n = CELL
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
        sl = (slice(max(0, int(y0)), min(CELL, int(y1) + 1)), slice(max(0, int(x0)), min(CELL, int(x1) + 1)))
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
        return (pts[:, 0].min() >= pad and pts[:, 0].max() <= CELL - pad and pts[:, 1].min() >= pad
                and pts[:, 1].max() <= CELL - ROOT_PX + 2)

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

def _cell_uv(cell, flip):
    """The cell's UV rectangle in Blender's convention (v up; the atlas's top row is the high v half):
    (u at the left edge, u at the right edge, v at the base, v at the tip)."""
    col, row = cell % COLS, cell // COLS
    u0, u1 = col / COLS, (col + 1) / COLS
    v0, v1 = 1.0 - (row + 1) / ROWS, 1.0 - row / ROWS
    return (u1, u0, v0, v1) if flip else (u0, u1, v0, v1)


class _Cards:
    """Two-sided card strips gathered into one mesh: vertices, quads, a UV, a jitter colour and a lit normal per
    vertex. Each card is two sheets of quads back to back with opposite winding, 1.2 mm apart (coincident sheets
    confuse a ray tracer: Blender's review would skip the near sheet), each with its own normal leaned toward world
    up, and the material culls back faces: from either side the near sheet draws and lights like the ground. (A single sheet drawn from both sides cannot do that: the renderer flips its normal for the
    back face, so one side of every card would shade as if facing the soil.)"""

    def __init__(self):
        self.verts, self.faces, self.uvs, self.cols, self.normals, self.facing = [], [], [], [], [], []

    def strip(self, centres, sides, half_width, cell, flip=False, shade=1.0):
        """A card along `centres` (base to tip, one row each) spanning +-half_width along each row's `sides`
        vector, mapped to the whole of atlas `cell`. The front sheet is the one whose normal leans up (the top of
        a fern frond)."""
        u_l, u_r, v0, v1 = _cell_uv(cell, flip)
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
                lit = (n + up * NORMAL_UP).normalized()
                gap = n * (SHEET_GAP / 2)                          # each sheet stands just off the card on its side
                self.verts += [tuple(left[k] + gap), tuple(right[k] + gap)]
                self.uvs += [(u_l, v), (u_r, v)]
                self.cols += [(shade, shade, shade)] * 2
                self.normals += [tuple(lit), tuple(lit)]
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


def _card_material():
    """The cards' Blender material: the atlas's colour times the decoded jitter colour, cut out by its alpha (the
    Round node is what the glTF exporter reads as alphaMode MASK). The engine draws M_MeadowCards.tres instead."""
    meadow_atlas()                                   # writes the atlas on the first card of a run
    path = os.path.join(ROOT, ATLAS_PATH)
    mat = bpy.data.materials.new("M_MeadowCards")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    img = bpy.data.images.load(path, check_existing=True)
    img.name = ATLAS
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

def _reduce_to(obj, budget):
    """Collapse-decimates `obj` to at most `budget` triangles, keeping a hidden full-detail copy for the normal
    bake. Returns (triangles before, after, the copy, the largest surface error in metres)."""
    high = obj.copy()
    high.data = obj.data.copy()
    high.name = f"{obj.name}_high"
    bpy.context.collection.objects.link(high)
    high.matrix_world = obj.matrix_world.copy()
    before = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    mod = obj.modifiers.new("Reduce", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.use_collapse_triangulate = True
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


def _bake_rock(obj, budget, texture, size, tints=None):
    before, after, high, error = _reduce_to(obj, budget)
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


# --- The card GLBs' atlas link ----------------------------------------------------------------------------------

def link_atlas(glb_path):
    """Rewrites a card GLB so its image points at the shared atlas file (a relative URI,
    creature_flora/T_MeadowCards.png) instead of embedding a copy of it: the repository then holds one 1 MB atlas,
    not one per card GLB, and a glTF viewer or Godot's importer still finds the texture beside the GLB. The image's
    bufferView is dropped and the binary chunk repacked."""
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
        if img.get("name") == ATLAS and "bufferView" in img:
            drop.add(img.pop("bufferView"))
            img.pop("mimeType", None)
            img["uri"] = os.path.relpath(os.path.join(ROOT, ATLAS_PATH), os.path.dirname(glb_path)).replace(os.sep, "/")
    mp._check(len(drop) == 1, f"{glb_path}: one embedded {ATLAS} to link")
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

# asset id -> (builder, triangle budget)
ASSETS = {
    "creature_grass_tuft": (build_grass_tuft, 48),
    "creature_fern_clump": (build_fern_clump, 96),
    "creature_flower_clump": (build_flower_clump, 120),
    "creature_pebble_cluster": (build_pebble_cluster, 160),
    **{asset_id: ((lambda i=asset_id: build_boulder(i)), spec[2]) for asset_id, spec in BOULDERS.items()},
}

EXTERNAL = {asset_id: {"M_MeadowCards": "M_MeadowCards"} for asset_id in CARD_ASSETS}

# The cards keep no LODs (Godot's LOD pass collapses whole cards) and cast no shadow (cover; the field's scatter
# draws its cover without shadows too).
IMPORT_OPTIONS = {asset_id: {"meshes": {f"{asset_id}_{node}_mesh": {"generate/lods": 2}},
                             "nodes": {f"PATH:{node}": {"mesh_instance/cast_shadow": 0}}}
                  for asset_id, node in CARD_ASSETS.items()}

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


def map_materials(export, set_import_param):
    """Writes M_MeadowCards.tres and gives the atlas mipmaps. make_creature_world.map_materials calls this."""
    with open(os.path.join(export, "M_MeadowCards.tres"), "w") as f:
        f.write(MEADOW_TRES.format(atlas=ATLAS_PATH))
    set_import_param(os.path.join(FLORA_DIR, f"{ATLAS}.png.import"), "mipmaps/generate", "true")
    print("mipmaps:", ATLAS)
