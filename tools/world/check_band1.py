"""Static checks of the band-1 world content from the data alone (S3, track T3).

Checks game/data/tiles/b1/*.json and game/data/cradle_b1.json against every rule of the S3 plan
that the data can show without the engine: docs/s3/s3-build-plan.md (wins), s3-sim.md (T3's rows,
D-134 to D-138, D-146, D-147, the manifest 4.3 and 4.4) and the spine s3-interfaces.md (5.3, 5.4,
6.3, 6.4, D-90 to D-98), on top of S1's tile rules (tile_catalog.gd) and S2's two-post rules.

It is an authoring aid and a cross-check for T3.3/T3.4's GDScript, not a replacement for it: the
engine's TileCatalog.validate and CradleBlock.validate are the gates (S3G1 to S3G7, S3G16, S3G38,
S3G42). Run it with:

    python3 -I tools/world/check_band1.py [--root DIR] [--no-reach] [--quiet]

What it checks, per tile (and per cradle quadrant, as D-94 checks it):
- the schema (keys, ids, band 1, regions and rare kinds per D-90/D-91, set parity, the set piece);
- rules 1 to 12 at sizes 3 and 4 with D-97's roles: shells (radius classes that at least two band-1
  kit shells cover with D-93's scale ranges), zones (static #33 yield, 0.7 bu clear), the anchor and
  its collider (rule 4), set-piece colliders, sites (clear homes, gaps, territories, reach discs inside
  the tile, rules 9 and 10 against every collider, S2's two posts and D-147's elder-Warden meadows),
  rule 7's threats and caps (4 and 2 creature sites; no morsel at 3, 3 at 4), rule 8's strike room, rule 9's prey
  or morsel, rule 11's channel (D-137) and rule 12's hazard room (D-138);
- D-134's anchor rule in tm (band 1 only, BP3-13), BP3-8's clear point within 8 rings in all 8
  orientations, D-135 and SQ3-2 (18 shells, 12 zones, 6 live at size 4), the D-136 manifest, S3G6's
  creature sites at size 4 by set (2 and 1, so 1.5 a region), two threat behaviours a size over band 1,
  S3G42's reach and union bounds, the spine's wide Warden meadows (6 to 8 bu) in the Warden flats, and
  no colour field or value anywhere (the reserved hues are the view's; tiles carry none);
- F9 (S3G38): the worst swim from any open point the sea reaches to a live zone, at sizes 3 and 4,
  with and without the landmark's collider, under the 16.32 tm budget;
- the cradle: pool ring (14.0625 bu, equal to the cradle_ring record; under clear_r_bu), caption and
  dressing (D-116), clear_r_bu 16, no shell or reach disc in the clear disc, shells beyond 17.5 bu
  (Q3V-11), the view point clear, each post in its site's quadrant, s3-sim 4.4's sites per quadrant,
  an elder Warden in every quadrant (SQ3-4), and F9 over the whole block.

It prints one line per problem and exits 1 when there is any. Units: bu, tile-local (x east,
y south, origin at the tile centre); a cradle position is bu from the absolute origin. A length
given in tm at size n is divided by bu_to_tm(n) (1 at size 3, 0.625 at size 4). A species' own
lengths at q = 1 (its entry size, in that size's tm) become bu by k_of(c) = 1.6^(c - 1) / 2.56
(S2's WorldConfig.k_of), so a site's discs are the same in bu at both band-1 sizes.

Species numbers below are copies of creatures_m1.json as S2 and S3 pin them (s3-sim 4.2 and 0.10,
s2-sim 4.2 and D-61): change them here if T1 changes the data.
"""
import argparse
import json
import math
import os
import re
import sys

BAND = 1
SIZES = (3, 4)
FIRST, SECOND = 3, 4
S_TM = {3: 1.0, 4: 0.625}                       # WorldConfig.bu_to_tm(n)
K_OF = {1: 0.390625, 2: 0.625, 3: 1.0, 4: 1.6}  # tm_to_am(c) / 2.56: q = 1 tm of entry size c, in band-1 bu
SHRINK, GROWTH = 0.625, 1.6

REGIONS = ["veil_garden", "warden_flat", "glass_reef"]           # D-90, D-91
RARE_KINDS = ["fallen_lattice", "shed_shell", "sponge_grove", "sunbeam_well"]
RARE = "rare"
TILE_LETTERS = "abcdef"                                            # a to c set 0, d to f set 1

FILE_KEYS = ["schema_version", "status", "note", "id", "band", "region", "set", "rare", "landmark_anchor",
             "set_piece", "shells", "zones", "sites"]
SHELL_KEYS = ["id", "center", "radius", "yaw_deg", "at_second_size"]
ZONE_KEYS = ["id", "center", "radius", "capacity", "growth_rate", "at_second_size"]
SITE_KEYS = ["id", "species", "home", "heading", "sizes"]
SITE_OPTIONAL = ["territory_zone", "post_b"]
POST_KEYS = ["home", "heading"]
POST_OPTIONAL = ["territory_zone"]
SET_PIECE_KEYS = ["asset", "center", "yaw_deg"]
CRADLE_KEYS = ["schema_version", "status", "note", "band", "pool_ring", "clear_r_bu", "view_point_bu", "shells",
               "zones", "sites"]
POOL_RING_KEYS = {"radius_bu": "number", "glitter_radius_bu": "number", "caption": "text", "dressing": "text"}
LOCAL_ID = re.compile(r"^[a-z][a-z0-9]{0,7}$")
PIECE_ID = re.compile(r"^r[0-9]+$")
LANDMARK_ID = "lm"

HALF_TILE = 32.0
SHELL_EDGE = 28.0
ZONE_EDGE = 31.0
ANCHOR_EDGE = 25.0
MIN_SHELL_R, MAX_SHELL_R = 0.6, 1.5
MIN_ZONE_R, MAX_ZONE_R = 2.0, 8.0
SHELL_SECOND = ("keep", "sink")
ZONE_SECOND = ("keep", "thin", "drop")
MAX_ZONE_YIELD = 1.152            # static #33: growth x capacity x (0.25 + 0.05)
YIELD_SHARE, REGROW_FLOOR = 0.25, 0.05
ZONE_CLEAR = 0.7                  # PoolLayout.ZONE_CLEAR_MARGIN (bu)
ZONE_CLEAR_EPS = 1e-5
TUNNEL_LIMIT = 2.0 * 6.0 / 60.0   # two ticks at PoolLayout.MAX_SPEED
SECOND_SIZE_SCALE = 0.625
COLLIDE_R = 2.0                   # kit landmark.collide_radius_bu
ANCHOR_CLEAR_EXTRA = 1.0
ANCHOR_GAP_BU = 0.5
CELL_R_TM = 0.5
RESPAWN_CLEAR_TM = 12.0
LEASH_BAND_TM = 0.1
PINCH_TM = 0.5
MIN_GAP_TM = 2.0                  # spawning.min_gap_m
MAX_SITES = {3: 4, 4: 2}          # creature roles (threat, rival, prey) per tile and quadrant
MAX_MORSEL_SITES = {3: 0, 4: 3}  # D-135: none at size 3, at most 3 at size 4
MAX_SHELLS, MAX_ZONES, MAX_LIVE_ZONES_SECOND = 18, 12, 6          # D-135 (SQ3-2: 6)
MORSEL_MAX_RADIUS_TM = 0.225
REACH_MAX_TM = 18.745             # B-6
UNION_MAX_TM = 18.0               # D-61
CHANNEL_FLANK_TM, CHANNEL_FLANK_SHARE, CHANNEL_STEP = 3.0, 0.6, 0.25
BITE_REACH, RAM_REACH = 0.3, 0.35
CLEAR_STEP_TM, LANDMARK_RINGS = 0.5, 8                              # BP3-8
CLEAR_EPS = 1e-4
BUDGET_TM, REACH_STEP_TM = 16.32, 0.5                               # F9's starving budget and grid
RIVAL_MIN_REL, PREY_MIN_REL, MORSEL_MIN_REL, TOL = 0.8, 0.45, 0.25, 1e-6
CRADLE_HALF = 64.0
CRADLE_CAPTION = "Your lineage began here"
CRADLE_SHELL_BEYOND = 17.5        # Q3V-11: the ring's drawn edge is 16.81 bu
EW_POSTS_BU = (13.0, 16.5)        # D-147
EW_MEADOW_R = (5.0, 6.0)
EW_TRAVEL_S, EW_WANDER_TM_S = 12.8, 0.8112
WARDEN_MEADOW_R = (6.0, 8.0)      # spine 6.3: a Warden flat's Wardens on wide meadows
COLOUR_KEYS = {"tint", "color", "colour", "hue", "albedo"}
HEX_COLOUR = re.compile(r"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")

# Kit fit for band-1 shells: footprint_radius_m and D-93's scale ranges (T3.2 writes them into the
# records; build plan 7.3). PlacementKit.MIN_PICKABLE_PER_CLASS = 2.
B1_SHELLS = {"shell_b1_lattice_cap": (0.8, 0.75, 1.13), "shell_b1_tiered_disc": (0.7, 0.85, 1.29),
             "shell_b1_rimmed_cup": (1.0, 0.90, 1.20), "shell_b1_spined_drum": (1.1, 0.81, 1.37),
             "shell_b1_glass_dome": (1.35, 0.88, 1.12)}
FIT_EPSILON = 1e-6
CLASSES = [("fp_s", 0.6, 0.9), ("fp_m", 0.9, 1.2), ("fp_l", 1.2, 1.5)]

# Rare set pieces' colliders (assets/records/rare_*.json; read from the records when present).
RARE_COLLIDERS = {
    "rare_fallen_lattice": [((0.0, 0.0), 3.2)],
    "rare_shed_shell": [((-2.4, -0.22), 2.0), ((0.9, 0.68), 1.55), ((3.2, 0.18), 1.05)],
    "rare_sponge_grove": [((0.0, 0.0), 1.2), ((2.7, 1.0), 0.95), ((-2.7, -1.0), 0.95), ((1.3, -2.5), 0.9),
                          ((-1.3, 2.5), 0.9)],
    "rare_sunbeam_well": [((3.0571, 0.9457), 0.85), ((0.7096, 3.1203), 0.85), ((-2.3475, 2.1747), 0.85),
                          ((-3.0571, -0.9457), 0.85), ((-0.7096, -3.1203), 0.85), ((2.3475, -2.1747), 0.85)],
}

# Species (q = 1 numbers in tm of the entry size). travel: Locomotion.strike_travel at q = 1 (s3-sim
# 0.10: ambush 2.1290, ram 4.1960). spacing: post homes at q = 1 in tm (S2 D-61); the elder Warden's
# are D-147's, already in bu.
SPECIES = {
    "ambush_hunter": {"c": 1, "R": 0.75, "behavior": "ambush", "leash": 9.0, "travel": 2.129, "bite": True,
                      "start_max": 3.0},
    "rammer": {"c": 1, "R": 0.625, "behavior": "territorial", "leash": 3.0, "margin": 2.0, "travel": 4.196,
               "bite": False, "start_max": 5.0},
    "lurker": {"c": 2, "R": 0.75, "behavior": "ambush", "leash": 9.0, "travel": 2.129, "bite": True,
               "start_max": 3.0, "habit": "out_of_sight", "spacing_tm": (4.0, 6.0)},
    "elder_rammer": {"c": 2, "R": 0.625, "behavior": "territorial", "leash": 3.0, "margin": 2.0, "travel": 4.196,
                     "bite": False, "start_max": 5.0, "habit": "nearer_cell", "spacing_tm": (6.0, 10.5),
                     "nav_s": 16.0, "wander_tm_s": 0.82822},
    "veil": {"c": 3, "R": 0.8, "behavior": "hazard", "leash": 4.75, "thread_len": 2.4, "thread_r": 0.35},
    "warden": {"c": 3, "R": 0.65, "behavior": "territorial", "leash": 3.0, "margin": 2.0, "travel": 4.196,
               "bite": False, "start_max": 5.0},
    "deep_lurker": {"c": 4, "R": 0.78, "behavior": "ambush", "leash": 9.0, "travel": 2.129, "bite": True,
                    "start_max": 3.0, "habit": "channel"},
    "elder_warden": {"c": 4, "R": 0.65, "behavior": "territorial", "leash": 3.0, "margin": 2.0, "travel": 4.196,
                     "bite": False, "start_max": 5.0, "habit": "bloom"},
}
THREAT_BEHAVIORS = ("ambush", "territorial", "hazard")

# D-136: the band-1 manifest (s3-sim 4.3): per tile, (species, sizes, has post_b), as a sorted list.
def _m(*rows):
    return sorted((sp, tuple(sz), pb) for sp, sz, pb in rows)

VG_A = _m(("veil", [3, 4], False), ("veil", [3], False), ("rammer", [3, 4], False), ("rammer", [3, 4], False),
          ("elder_warden", [4], True))
VG_D = _m(("veil", [3], False), ("veil", [3], False), ("rammer", [3, 4], False), ("rammer", [3, 4], False),
          ("elder_warden", [4], True))
VG_F = _m(("veil", [3], False), ("rammer", [3, 4], False), ("rammer", [3, 4], False), ("elder_warden", [4], True))
WF_A = _m(("warden", [3], False), ("rammer", [3, 4], False), ("elder_rammer", [3, 4], True),
          ("elder_warden", [4], True))
WF_B = _m(("warden", [3], False), ("warden", [3], False), ("rammer", [3, 4], False), ("elder_rammer", [3, 4], True),
          ("elder_warden", [4], True))
WF_D = _m(("warden", [3], False), ("rammer", [3, 4], False), ("elder_rammer", [3], True), ("elder_warden", [4], True))
WF_E = _m(("warden", [3], False), ("warden", [3], False), ("rammer", [3, 4], False), ("elder_rammer", [3], True),
          ("elder_warden", [4], True))
GR_A = _m(("veil", [3], False), ("ambush_hunter", [3, 4], False), ("lurker", [3, 4], True), ("deep_lurker", [4], False))
GR_C = _m(("veil", [3], False), ("veil", [3], False), ("ambush_hunter", [3, 4], False), ("lurker", [3, 4], True),
          ("deep_lurker", [4], False))
GR_D = _m(("veil", [3], False), ("ambush_hunter", [3, 4], False), ("lurker", [3], True), ("deep_lurker", [4], False))
GR_F = _m(("veil", [3], False), ("veil", [3], False), ("ambush_hunter", [3, 4], False), ("lurker", [3], True),
          ("deep_lurker", [4], False))
MANIFEST = {
    "veil_garden_a": VG_A, "veil_garden_b": VG_A, "veil_garden_c": VG_A,
    "veil_garden_d": VG_D, "veil_garden_e": VG_D, "veil_garden_f": VG_F,
    "warden_flat_a": WF_A, "warden_flat_b": WF_B, "warden_flat_c": WF_A,
    "warden_flat_d": WF_D, "warden_flat_e": WF_E, "warden_flat_f": WF_D,
    "glass_reef_a": GR_A, "glass_reef_b": GR_A, "glass_reef_c": GR_C,
    "glass_reef_d": GR_D, "glass_reef_e": GR_D, "glass_reef_f": GR_F,
    "sunbeam_well": _m(("warden", [3], False), ("veil", [3], False), ("rammer", [3, 4], False),
                       ("elder_warden", [4], True)),
    "fallen_lattice": _m(("veil", [3], False), ("ambush_hunter", [3, 4], False), ("deep_lurker", [4], False)),
    "sponge_grove": _m(("warden", [3], False), ("elder_rammer", [3, 4], True), ("elder_warden", [4], True)),
    "shed_shell": _m(("veil", [3], False), ("lurker", [3, 4], True), ("deep_lurker", [4], False)),
}
# s3-sim 4.4: the cradle quadrants, keyed by the home tile quadrant_of gives (x < 0 -> -1, y < 0 -> -1).
CRADLE_MANIFEST = {
    (-1, -1): _m(("warden", [3], False), ("rammer", [3, 4], False), ("elder_warden", [4], True)),
    (0, -1): _m(("veil", [3], False), ("ambush_hunter", [3, 4], False), ("elder_warden", [4], True)),
    (-1, 0): _m(("veil", [3], False), ("elder_rammer", [3, 4], True), ("elder_warden", [4], True)),
    (0, 0): _m(("warden", [3], False), ("rammer", [3, 4], False), ("elder_warden", [4], True)),
}


# --- geometry ---

def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def q_of(c, n):
    q = 1.0
    for _ in range(abs(c - n)):
        q *= GROWTH if c > n else SHRINK
    return q


def ladder_role(sp, n):
    s = SPECIES[sp]
    if s["c"] == n:
        return "threat"
    if s["c"] > n:
        return "ghost"
    rel = s["R"] * q_of(s["c"], n) / 0.5
    if rel > RIVAL_MIN_REL + TOL:
        return "rival"
    if rel >= PREY_MIN_REL - TOL:
        return "prey"
    if rel >= MORSEL_MIN_REL - TOL:
        return "morsel"
    return "haze"


def role_at(site, n):
    """TileCatalog.site_role (spine 5.3, s3-sim 3.11): "" unless live at n."""
    if n not in site["sizes"] or n not in SIZES:
        return ""
    r = ladder_role(site["species"], n)
    return r if r in ("threat", "rival", "prey", "morsel") else ""


def body_r(sp, n):
    """The body's radius in bu at size n (radius_at / bu_to_tm(n)); equal to R x k_of(c)."""
    s = SPECIES[sp]
    return s["R"] * q_of(s["c"], n) / S_TM[n]


def morsel_r(sp, n):
    s = SPECIES[sp]
    return min(s["R"] * q_of(s["c"], n), MORSEL_MAX_RADIUS_TM) / S_TM[n]


def union_disc(a, b):
    """The smallest disc holding both (S2 D-82)."""
    d = dist(a["c"], b["c"])
    if d + b["r"] <= a["r"]:
        return dict(a)
    if d + a["r"] <= b["r"]:
        return dict(b)
    r = (d + a["r"] + b["r"]) / 2.0
    t = (r - a["r"]) / d
    return {"c": (a["c"][0] + (b["c"][0] - a["c"][0]) * t, a["c"][1] + (b["c"][1] - a["c"][1]) * t), "r": r}


def post_disc(sp, home, zone):
    s = SPECIES[sp]
    k = K_OF[s["c"]]
    if s["behavior"] == "territorial":
        return {"c": tuple(zone["center"]), "r": zone["radius"] + (s["margin"] + s["leash"]) * k}
    if s["behavior"] == "hazard":
        return {"c": tuple(home), "r": (s["leash"] + s["thread_len"] + s["thread_r"]) * k}
    return {"c": tuple(home), "r": s["leash"] * k}


def yaw_point(x, y, yaw_deg):
    m = round(yaw_deg / 90.0) % 4
    return [(x, y), (y, -x), (-x, -y), (-y, x)][m]


def orient_point(x, y, o):
    """WorldGen.orient_point: mirror x when o >> 2, then turn o & 3 times by (x, y) -> (-y, x)."""
    if (o >> 2) & 1:
        x = -x
    return [(x, y), (-y, x), (-x, -y), (y, -x)][o & 3]


def seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy))


def class_of(r):
    for i, (name, lo, hi) in enumerate(CLASSES):
        if r >= lo and (r < hi or (i == len(CLASSES) - 1 and r <= hi)):
            return name
    return ""


def fitting(r):
    return sorted(i for i, (fr, lo, hi) in B1_SHELLS.items() if lo - FIT_EPSILON <= r / fr <= hi + FIT_EPSILON)


# --- reading ---

class Problems:
    def __init__(self):
        self.items = []

    def add(self, where, rule, text):
        self.items.append(f"{where}: {rule}: {text}")


def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _pair(v):
    return isinstance(v, list) and len(v) == 2 and all(_is_num(x) for x in v)


def _keys(where, d, keys, optional, out):
    if not isinstance(d, dict):
        out.add(where, "schema", "is not an object")
        return False
    for k in keys:
        if k not in d:
            out.add(where, "schema", f"missing key '{k}'")
    for k in d:
        if k not in keys and k not in optional:
            out.add(where, "schema", f"unknown key '{k}'")
    return all(k in d for k in keys)


def _colour_scan(where, v, out):
    if isinstance(v, dict):
        for k, x in v.items():
            if str(k).lower() in COLOUR_KEYS:
                out.add(where, "hues", f"key '{k}' is a colour field; tiles and the cradle carry no colour")
            _colour_scan(where, x, out)
    elif isinstance(v, list):
        for x in v:
            _colour_scan(where, x, out)
    elif isinstance(v, str) and HEX_COLOUR.match(v):
        out.add(where, "hues", f"'{v}' is a colour value")


def read_items(where, data, key, keys, optional, out):
    items = data.get(key, [])
    if not isinstance(items, list):
        out.add(where, "schema", f"'{key}' is not a list")
        return []
    seen = set()
    good = []
    for i, it in enumerate(items):
        iw = f"{where}.{key}[{i}]"
        if not _keys(iw, it, keys, optional, out):
            continue
        iid = it["id"]
        if not isinstance(iid, str) or not LOCAL_ID.match(iid) or iid in seen or iid == LANDMARK_ID or PIECE_ID.match(iid):
            out.add(iw, "schema", f"id '{iid}' is repeated, reserved (lm, r<digits>) or does not match {LOCAL_ID.pattern}")
        seen.add(iid)
        good.append(it)
    return good


def check_items_types(where, shells, zones, sites, zone_ids, out):
    for s in shells:
        w = f"{where} shell '{s['id']}'"
        if not (_pair(s["center"]) and _is_num(s["radius"]) and _pair(s["yaw_deg"]) and s["at_second_size"] in SHELL_SECOND):
            out.add(w, "rule 2", "needs center [x, y], a radius, yaw_deg [lo, hi] and at_second_size keep|sink")
    for z in zones:
        w = f"{where} zone '{z['id']}'"
        if not (_pair(z["center"]) and all(_is_num(z[k]) for k in ("radius", "capacity", "growth_rate"))
                and z["at_second_size"] in ZONE_SECOND):
            out.add(w, "rule 3", "needs center, radius, capacity, growth_rate and at_second_size keep|thin|drop")
    for s in sites:
        w = f"{where} site '{s['id']}'"
        if s["species"] not in SPECIES:
            out.add(w, "rule 6", f"unknown species '{s['species']}'")
        if not (_pair(s["home"]) and _is_num(s["heading"]) and isinstance(s["sizes"], list)):
            out.add(w, "schema", "needs home [x, y], a heading and sizes")
        tz = s.get("territory_zone", "")
        if not isinstance(tz, str) or (tz and tz not in zone_ids):
            out.add(w, "rule 6", f"territory_zone '{tz}' is not a zone of this block")
        if "post_b" in s:
            pb = s["post_b"]
            if _keys(w + ".post_b", pb, POST_KEYS, POST_OPTIONAL, out):
                if not (_pair(pb["home"]) and _is_num(pb["heading"])):
                    out.add(w, "schema", "post_b needs home [x, y] and a heading")
                ptz = pb.get("territory_zone", "")
                if ptz and ptz not in zone_ids:
                    out.add(w, "rule 6", f"post_b.territory_zone '{ptz}' is not a zone of this block")


# --- the per-block rules (a tile, or a cradle quadrant in its own frame) ---

def colliders_of(block, n=None):
    """Shells (only 'keep' at the second size), the landmark collider and the set piece's colliders
    ({id, c, r}) in the block's frame. n=None: every shell."""
    out = []
    for s in block["shells"]:
        if n == SECOND and s["at_second_size"] == "sink":
            continue
        out.append({"id": s["id"], "c": tuple(s["center"]), "r": float(s["radius"])})
    if block.get("anchor") is not None:
        out.append({"id": LANDMARK_ID, "c": tuple(block["anchor"]), "r": COLLIDE_R})
    piece = block.get("set_piece")
    if piece:
        for k, (c, r) in enumerate(RARE_COLLIDERS.get(piece["asset"], [])):
            px, py = yaw_point(c[0], c[1], float(piece["yaw_deg"]))
            out.append({"id": f"r{k}", "c": (piece["center"][0] + px, piece["center"][1] + py), "r": r})
    return out


def zone_live(z, n):
    return n == FIRST or z["at_second_size"] in ("keep", "thin")


def site_discs(block, site):
    """[(label, disc, home)] for the site's reach: one disc, or each post's disc and their union."""
    zones = {z["id"]: z for z in block["zones"]}
    sp = site["species"]
    za = zones.get(site.get("territory_zone", ""))
    a = post_disc(sp, site["home"], za)
    if "post_b" not in site:
        return [("disc", a, tuple(site["home"]))]
    pb = site["post_b"]
    zb = zones.get(pb.get("territory_zone", ""))
    b = post_disc(sp, pb["home"], zb)
    return [("post a", a, tuple(site["home"])), ("post b", b, tuple(pb["home"])), ("union", union_disc(a, b), None)]


def disc_against(where, disc, r, colliders, n, out):
    """SpeciesCatalog.check_disc_against_shells (rules 9 and 10), no wall, margins in bu at n."""
    band = r + LEASH_BAND_TM / S_TM[n]
    passage = 2.0 * r + PINCH_TM / S_TM[n]
    for i, rock in enumerate(colliders):
        d = dist(disc["c"], rock["c"])
        to_circle = abs(d - disc["r"]) - rock["r"]
        if to_circle < band:
            out.add(where, "rule 9", f"{rock['id']} lies {to_circle:.2f} bu from the leash circle; it needs {band:.2f}")
        if d - rock["r"] >= disc["r"] + r:
            continue
        for j, other in enumerate(colliders):
            if j == i:
                continue
            between = dist(rock["c"], other["c"]) - rock["r"] - other["r"]
            if 0.0 < between < passage:
                out.add(where, "rule 10", f"{rock['id']} leaves {between:.2f} bu to {other['id']}; it needs {passage:.2f}")


def check_shells_zones(where, block, half, out, edge_ok=None):
    """Rules 2, 3 (and 5's overlaps) in the block's frame. edge_ok(c, r, limit) decides the edge test
    (a tile: |x|, |y| from its centre; the cradle: only its outer edge)."""
    if edge_ok is None:
        edge_ok = lambda c, r, lim: abs(c[0]) + r <= lim + 1e-9 and abs(c[1]) + r <= lim + 1e-9
    for s in block["shells"]:
        r = float(s["radius"])
        w = f"{where} shell '{s['id']}'"
        if r < MIN_SHELL_R or r > MAX_SHELL_R or not class_of(r):
            out.add(w, "rule 2", f"radius {r} is outside [{MIN_SHELL_R}, {MAX_SHELL_R}]")
        elif len(fitting(r)) < 2:
            out.add(w, "rule 2", f"radius {r} fits {fitting(r)}; it needs 2 band-1 kit shells (D-93 ranges)")
        if not edge_ok(s["center"], r, half - 4.0):
            out.add(w, "rule 2", f"at {s['center']} comes within 4 bu of the edge")
        lo, hi = s["yaw_deg"]
        if not (0.0 <= lo <= hi <= 360.0):
            out.add(w, "rule 2", f"yaw_deg {s['yaw_deg']} needs 0 <= lo <= hi <= 360")
        if not r * SECOND_SIZE_SCALE > TUNNEL_LIMIT:
            out.add(w, "rule 2", "tunnels at the second size")
    cols = colliders_of(block)
    for i in range(len(cols)):
        for j in range(i + 1, len(cols)):
            a, b = cols[i], cols[j]
            if a["id"] == LANDMARK_ID or b["id"] == LANDMARK_ID or (PIECE_ID.match(a["id"]) and PIECE_ID.match(b["id"])):
                continue
            gap = dist(a["c"], b["c"]) - a["r"] - b["r"]
            if gap < 0.0:
                out.add(where, "rule 5" if PIECE_ID.match(b["id"]) else "rule 2", f"'{a['id']}' and '{b['id']}' overlap by {-gap:.2f} bu")
    for z in block["zones"]:
        w = f"{where} zone '{z['id']}'"
        r = float(z["radius"])
        if not (MIN_ZONE_R <= r <= MAX_ZONE_R and z["capacity"] > 0 and z["growth_rate"] > 0):
            out.add(w, "rule 3", f"needs {MIN_ZONE_R} <= radius <= {MAX_ZONE_R} and positive capacity and growth")
            continue
        if not edge_ok(z["center"], r, half - 1.0):
            out.add(w, "rule 3", f"at {z['center']} comes within 1 bu of the edge")
        y = z["growth_rate"] * z["capacity"] * (YIELD_SHARE + REGROW_FLOOR)
        if y > MAX_ZONE_YIELD + 1e-12:
            out.add(w, "rule 3", f"yields {y:.3f} a second; static #33 allows {MAX_ZONE_YIELD}")
        gap, near = min(((dist(z["center"], c["c"]) - r - c["r"], c["id"]) for c in cols), default=(math.inf, ""))
        if gap < ZONE_CLEAR - ZONE_CLEAR_EPS:
            out.add(w, "rule 3", f"is {gap:.2f} bu from collider '{near}'; it keeps {ZONE_CLEAR}")
    zs = block["zones"]
    for i in range(len(zs)):
        for j in range(i + 1, len(zs)):
            if dist(zs[i]["center"], zs[j]["center"]) < zs[i]["radius"] + zs[j]["radius"]:
                out.add(where, "authoring", f"zones '{zs[i]['id']}' and '{zs[j]['id']}' overlap")


def check_anchor_shells(where, block, out):
    """Rule 4: the anchor inside, and its collider leaves the largest body that can be live at each
    size room to every shell (sunk ones too, as S1's rule reads every shell)."""
    a = block["anchor"]
    if abs(a[0]) > ANCHOR_EDGE or abs(a[1]) > ANCHOR_EDGE:
        out.add(where, "rule 4", f"the anchor {a} lies beyond {ANCHOR_EDGE} bu of the centre")
    for n in SIZES:
        r_max = max(body_r(sp, n) for sp in SPECIES if SPECIES[sp]["c"] <= n)
        need = 2.0 * r_max + PINCH_TM / S_TM[n]
        for c in colliders_of(block):
            if c["id"] == LANDMARK_ID or PIECE_ID.match(c["id"]):
                continue
            gap = dist(a, c["c"]) - COLLIDE_R - c["r"]
            if gap < need:
                out.add(where, "rule 4", f"size {n}: the landmark collider leaves {gap:.2f} bu to '{c['id']}'; it needs {need:.2f}")


def clear_point_rings(block, n, o):
    """BP3-8 / S3G5c: the ring (0 = the anchor itself) of PoolSim.clear_point_on's spiral that finds a
    clear point for the cell at size n, orientation o, on the block's own colliders; None past 8."""
    s = S_TM[n]
    cols = []
    for c in colliders_of(block, n):
        x, y = orient_point(c["c"][0], c["c"][1], o)
        cols.append(((x * s, y * s), c["r"] * s))
    ax, ay = orient_point(block["anchor"][0], block["anchor"][1], o)
    p = (ax * s, ay * s)

    def clear(q):
        return all(dist(q, cc) >= cr + CELL_R_TM - CLEAR_EPS for cc, cr in cols)

    if clear(p):
        return 0
    for ring in range(1, LANDMARK_RINGS + 1):
        d = ring * CLEAR_STEP_TM
        m = math.ceil(2.0 * math.pi * d / CLEAR_STEP_TM)
        for k in range(m):
            ang = k * 2.0 * math.pi / m
            if clear((p[0] + math.cos(ang) * d, p[1] + math.sin(ang) * d)):
                return ring
    return None


def check_sites(where, block, half, out, anchor_rule=True, inset_half=None):
    """Rule 6 (with S2's two-post rules and D-97's roles), D-134's anchor rule, rules 8, 11 and 12, at
    sizes 3 and 4. inset_half: the half-width of the square a reach disc must stay inside."""
    inset_half = half if inset_half is None else inset_half
    zones = {z["id"]: z for z in block["zones"]}
    used_as_territory = {}
    for s in block["sites"]:
        for z in (s.get("territory_zone", ""), s.get("post_b", {}).get("territory_zone", "")):
            if z:
                used_as_territory.setdefault(z, []).append(s["id"])
    for s in block["sites"]:
        w = f"{where} site '{s['id']}'"
        sp = s["species"]
        if sp not in SPECIES:
            continue
        spec = SPECIES[sp]
        sizes = s["sizes"]
        if not sizes or any(n not in SIZES for n in sizes) or len(set(sizes)) != len(sizes):
            out.add(w, "rule 6", f"sizes {sizes} must be some of [3, 4]")
        for n in sizes:
            if n in SIZES and (spec["c"] > n or ladder_role(sp, n) not in ("threat", "rival", "prey", "morsel")):
                out.add(w, "rule 6", f"'{sp}' is {ladder_role(sp, n)} at size {n}; it cannot be live there (D-97)")
        terr = spec["behavior"] == "territorial"
        if terr and s.get("territory_zone", "") not in zones:
            out.add(w, "rule 6", f"a territorial site needs a territory_zone of this tile")
            continue
        if not terr and s.get("territory_zone", ""):
            out.add(w, "rule 6", "only a territorial site names a territory_zone")
        if "post_b" in s:
            pb = s["post_b"]
            if "habit" not in spec or spec["habit"] == "channel":
                out.add(w, "rule 6", f"post_b needs a two-post habit species, not '{sp}'")
                continue
            if terr != bool(pb.get("territory_zone", "")):
                out.add(w, "rule 6", "post_b.territory_zone is required for a territorial site and refused otherwise")
                continue
            if terr and pb["territory_zone"] == s["territory_zone"]:
                out.add(w, "rule 6", "the two posts need two distinct territory zones")
            d = dist(s["home"], pb["home"])
            if sp == "elder_warden":
                lo, hi = EW_POSTS_BU
                if not (lo <= d <= hi):
                    out.add(w, "D-147", f"posts {d:.2f} bu apart; they need {lo} to {hi}")
                if d * S_TM[SECOND] / EW_WANDER_TM_S > EW_TRAVEL_S + 1e-9:
                    out.add(w, "D-147", f"the move takes {d * S_TM[SECOND] / EW_WANDER_TM_S:.2f} s; at most {EW_TRAVEL_S}")
                ma, mb = zones[s["territory_zone"]], zones[pb["territory_zone"]]
                for m in (ma, mb):
                    if not (EW_MEADOW_R[0] <= m["radius"] <= EW_MEADOW_R[1]) or m["at_second_size"] != "keep":
                        out.add(w, "D-147", f"meadow '{m['id']}' needs radius 5 to 6 bu and at_second_size keep")
                    if used_as_territory.get(m["id"], []) != [s["id"]]:
                        out.add(w, "D-128", f"meadow '{m['id']}' belongs to one site only, not {used_as_territory.get(m['id'])}")
                if dist(ma["center"], mb["center"]) < ma["radius"] + mb["radius"]:
                    out.add(w, "D-147", "the two meadows overlap")
            else:
                k = K_OF[spec["c"]]
                lo, hi = spec["spacing_tm"][0] * k, spec["spacing_tm"][1] * k
                if not (lo - 1e-9 <= d <= hi + 1e-9):
                    out.add(w, "D-61", f"posts {d:.2f} bu apart; they need {lo:.3f} to {hi:.3f} (q = 1 tm x k_of)")
                if "nav_s" in spec and d / k / spec["wander_tm_s"] > 0.8 * spec["nav_s"] + 1e-9:
                    out.add(w, "D-61", f"the move takes {d / k / spec['wander_tm_s']:.2f} s; at most {0.8 * spec['nav_s']}")
                if terr:
                    for zid in (s["territory_zone"], pb["territory_zone"]):
                        if zones[zid]["at_second_size"] != "keep":
                            out.add(w, "D-61", f"post zone '{zid}' must be keep")
    for n in SIZES:
        s_tm = S_TM[n]
        cols = colliders_of(block, n)
        live = [(s, role_at(s, n)) for s in block["sites"] if s["species"] in SPECIES and role_at(s, n)]
        for i, (s, role) in enumerate(live):
            w = f"{where} size {n} site '{s['id']}' ({role})"
            sp = s["species"]
            spec = SPECIES[sp]
            homes = [tuple(s["home"])] + ([tuple(s["post_b"]["home"])] if "post_b" in s else [])
            for j in range(i):
                gap = dist(s["home"], live[j][0]["home"])
                if gap < MIN_GAP_TM / s_tm:
                    out.add(w, "rule 6", f"is {gap:.2f} bu from site '{live[j][0]['id']}'; sites keep {MIN_GAP_TM / s_tm:.2f} apart")
            if role == "morsel":
                r = morsel_r(sp, n)
                h = tuple(s["home"])
                for c in cols:
                    if dist(h, c["c"]) < c["r"] + r - CLEAR_EPS:
                        out.add(w, "rule 6", f"home {list(h)} is not clear of '{c['id']}'")
                if abs(h[0]) + r > inset_half or abs(h[1]) + r > inset_half:
                    out.add(w, "rule 6", "the morsel lies outside its tile")
                continue
            r = body_r(sp, n)
            for h in homes:
                for c in cols:
                    if dist(h, c["c"]) < c["r"] + r - CLEAR_EPS:
                        out.add(w, "rule 6", f"home {list(h)} is not clear of '{c['id']}'")
            zone_ids = [s.get("territory_zone", "")] + ([s["post_b"].get("territory_zone", "")] if "post_b" in s else [])
            for zid in zone_ids:
                if zid and not zone_live(zones[zid], n):
                    out.add(w, "rule 6", f"territory zone '{zid}' is dropped at size {n}")
            margin = LEASH_BAND_TM / s_tm
            for label, disc, home in site_discs(block, s):
                dw = f"{w} {label}"
                c, reach = disc["c"], disc["r"]
                inset = reach + r + margin
                if abs(c[0]) + inset > inset_half + 1e-9 or abs(c[1]) + inset > inset_half + 1e-9:
                    out.add(dw, "rule 6", f"reach disc at ({c[0]:.2f}, {c[1]:.2f}) r {reach:.2f} leaves the tile")
                if home is not None and dist(home, c) + r > reach + 1e-9:
                    out.add(dw, "rule 6", "the home is not inside its reach disc")
                disc_against(dw, disc, r, cols, n, out)
                if anchor_rule and block.get("anchor") is not None:
                    clear = dist(block["anchor"], c) - reach - r - (COLLIDE_R + CELL_R_TM / s_tm + ANCHOR_GAP_BU)
                    need = (RESPAWN_CLEAR_TM + ANCHOR_CLEAR_EXTRA) / s_tm
                    if clear < need:
                        out.add(dw, "D-134", f"can reach {clear:.2f} bu from the landmark anchor; it must stay {need:.2f} away")
                if label in ("disc", "union") and reach * s_tm >= REACH_MAX_TM:
                    out.add(dw, "S3G42", f"reach {reach * s_tm:.2f} tm is not under {REACH_MAX_TM}")
                if label == "union" and reach * s_tm > UNION_MAX_TM:
                    out.add(dw, "S3G42", f"union disc {reach * s_tm:.2f} tm is over {UNION_MAX_TM}")
            q = q_of(spec["c"], n)
            if spec["behavior"] in ("ambush", "territorial"):
                lane = spec["travel"] * q + spec["R"] * q + (BITE_REACH if spec["bite"] else RAM_REACH) + CELL_R_TM
                room = spec["leash"] * q
                if spec["behavior"] == "territorial":
                    smallest = min(zones[z]["radius"] for z in zone_ids if z)
                    room += smallest * s_tm + spec["margin"] * q
                if lane > room + 1e-9:
                    out.add(w, "rule 8", f"strike lane {lane:.2f} tm is longer than its room {room:.2f} tm")
            if spec["behavior"] == "hazard":
                need = (spec["leash"] + spec["R"]) * q / s_tm
                for c in cols:
                    gap = dist(s["home"], c["c"]) - c["r"]
                    if gap < need:
                        out.add(w, "rule 12", f"'{c['id']}' is {gap:.2f} bu from the hazard's home; it needs {need:.2f}")
            if spec.get("habit") == "channel" and role == "threat":
                check_channel(w, s, n, cols, out)


def check_channel(where, s, n, cols, out):
    """Rule 11 (D-137): the strike lane from the lair is clear of colliders and flanked on both sides."""
    spec = SPECIES[s["species"]]
    s_tm = S_TM[n]
    q = q_of(spec["c"], n)
    length = (spec["start_max"] + spec["travel"]) * q / s_tm
    hw = (spec["R"] * q + BITE_REACH + CELL_R_TM) / s_tm
    h = float(s["heading"])
    u = (math.cos(h), math.sin(h))
    a = tuple(s["home"])
    b = (a[0] + u[0] * length, a[1] + u[1] * length)
    for c in cols:
        if seg_dist(c["c"], a, b) < hw + c["r"]:
            out.add(where, "rule 11", f"'{c['id']}' lies in the channel lane")
    flank = CHANNEL_FLANK_TM / s_tm
    stations = int(math.floor(length / CHANNEL_STEP + 1e-9)) + 1
    flanked = 0
    for k in range(stations):
        p = (a[0] + u[0] * k * CHANNEL_STEP, a[1] + u[1] * k * CHANNEL_STEP)
        left = right = False
        for c in cols:
            if dist(p, c["c"]) - c["r"] <= flank:
                side = u[0] * (c["c"][1] - p[1]) - u[1] * (c["c"][0] - p[0])
                left = left or side > 0.0
                right = right or side < 0.0
        flanked += 1 if (left and right) else 0
    if flanked < CHANNEL_FLANK_SHARE * stations:
        out.add(where, "rule 11", f"{flanked} of {stations} lane stations are flanked; at least {CHANNEL_FLANK_SHARE:.0%}")


def content_counts(block):
    """{n: {"creature", "morsel", "threats": [behaviours], "prey_or_morsel"}}"""
    out = {}
    for n in SIZES:
        c = {"creature": 0, "morsel": 0, "threats": [], "prey_or_morsel": 0}
        for s in block["sites"]:
            if s["species"] not in SPECIES:
                continue
            role = role_at(s, n)
            if role in ("threat", "rival", "prey"):
                c["creature"] += 1
            if role == "morsel":
                c["morsel"] += 1
            if role == "threat" and SPECIES[s["species"]]["behavior"] in THREAT_BEHAVIORS:
                c["threats"].append(SPECIES[s["species"]]["behavior"])
            if role in ("prey", "morsel"):
                c["prey_or_morsel"] += 1
        out[n] = c
    return out


def check_content(where, block, out, ordinary=True):
    """Rule 7 (threats, caps), rules 9 and 10 (prey or morsel; morsel cap) and D-135's counts."""
    counts = content_counts(block)
    if not block["zones"]:
        out.add(where, "rule 7", "needs at least one zone")
    if len(block["shells"]) > MAX_SHELLS:
        out.add(where, "D-135", f"{len(block['shells'])} shells; at most {MAX_SHELLS}")
    if len(block["zones"]) > MAX_ZONES:
        out.add(where, "D-135", f"{len(block['zones'])} zones; at most {MAX_ZONES}")
    live4 = sum(1 for z in block["zones"] if zone_live(z, SECOND))
    if live4 > MAX_LIVE_ZONES_SECOND or live4 < 1:
        out.add(where, "D-135", f"{live4} zones live at size 4; 1 to {MAX_LIVE_ZONES_SECOND} (SQ3-2)")
    for n in SIZES:
        c = counts[n]
        if c["creature"] > MAX_SITES[n]:
            out.add(where, "rule 7", f"{c['creature']} creature sites at size {n}; at most {MAX_SITES[n]}")
        if c["morsel"] > MAX_MORSEL_SITES[n]:
            out.add(where, "D-135", f"{c['morsel']} morsel sites at size {n}; at most {MAX_MORSEL_SITES[n]}")
        if not c["threats"]:
            out.add(where, "rule 7", f"needs a live threat at size {n} (band 1 has no transit region)")
        if ordinary and c["prey_or_morsel"] == 0:
            out.add(where, "rule 9", f"needs a prey or morsel site at size {n}")
    return counts


def check_manifest(where, sites, want, out):
    got = sorted((s["species"], tuple(s["sizes"]), "post_b" in s) for s in sites)
    if got != want:
        out.add(where, "D-136", f"sites {got} are not the manifest's {want}")


def reach_worst(block, n, lo, hi, with_anchor=True):
    """F9 (S3G38): the worst swim distance (tm) from an open grid point to a live zone at size n, on
    an 8-neighbour grid 0.5 tm apart over [lo, hi]^2 bu, round the block's colliders at n (with or
    without the landmark's, as S1's G5 test runs it). Only the open points the sea outside reaches count
    (a sealed pocket, such as the inside of the sunbeam well's ring at size 4, has none; S1's B-29)."""
    s = S_TM[n]
    step = REACH_STEP_TM / s
    cols = [(c["c"], c["r"]) for c in colliders_of(block, n) if with_anchor or c["id"] != LANDMARK_ID]
    zones = [z for z in block["zones"] if zone_live(z, n)]
    size = int(math.ceil((hi - lo) / step)) + 1
    pts = [lo + i * step for i in range(size)]
    body = CELL_R_TM / s
    open_ = bytearray(size * size)
    for yi, y in enumerate(pts):
        near = [(c, r) for c, r in cols if abs(c[1] - y) < r + body]
        for xi, x in enumerate(pts):
            ok = all(math.hypot(x - c[0], y - c[1]) >= r + body - CLEAR_EPS for c, r in near)
            open_[yi * size + xi] = 1 if ok else 0
    INF = 1 << 30
    units = [INF] * (size * size)
    buckets = [[]]
    for yi, y in enumerate(pts):
        for xi, x in enumerate(pts):
            i = yi * size + xi
            if open_[i] and any(math.hypot(x - z["center"][0], y - z["center"][1]) <= z["radius"] for z in zones):
                units[i] = 0
                buckets[0].append(i)
    b = 0
    while b < len(buckets):
        for i in buckets[b]:
            if units[i] != b:
                continue
            x, y = i % size, i // size
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if not (dx or dy):
                        continue
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < size and 0 <= ny < size:
                        j = ny * size + nx
                        if open_[j]:
                            cost = b + (14 if dx and dy else 10)
                            if cost < units[j]:
                                units[j] = cost
                                while len(buckets) <= cost:
                                    buckets.append([])
                                buckets[cost].append(j)
        b += 1
    sea = bytearray(size * size)
    stack = [i for i in range(size * size) if open_[i] and (i % size in (0, size - 1) or i // size in (0, size - 1))]
    for i in stack:
        sea[i] = 1
    while stack:
        i = stack.pop()
        x, y = i % size, i // size
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < size and 0 <= ny < size:
                    j = ny * size + nx
                    if open_[j] and not sea[j]:
                        sea[j] = 1
                        stack.append(j)
    worst, at = 0.0, None
    for i in range(size * size):
        if sea[i]:
            m = units[i] * REACH_STEP_TM / 10.0 if units[i] != INF else math.inf
            if m > worst:
                worst, at = m, (pts[i % size], pts[i // size])
    return worst, at


# --- tiles ---

def load_tile(path, out):
    name = os.path.basename(path)[:-5]
    w = f"b1/{name}"
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        out.add(w, "schema", f"not readable JSON ({e})")
        return None
    _colour_scan(w, data, out)
    if not _keys(w, data, FILE_KEYS, [], out):
        return None
    if data["schema_version"] != 1 or not isinstance(data["status"], str) or not isinstance(data["note"], str):
        out.add(w, "schema", "schema_version 1, a status and a note")
    if data["id"] != name:
        out.add(w, "schema", f"id '{data['id']}' is not the file's name")
    if data["band"] != BAND:
        out.add(w, "schema", f"band {data['band']} is not 1")
    region = data["region"]
    is_rare = region == RARE
    if not (region in REGIONS or is_rare):
        out.add(w, "D-91", f"region '{region}' is not one of {REGIONS} or rare")
    if is_rare:
        if data["set"] is not None or data["landmark_anchor"] is not None:
            out.add(w, "schema", "a rare tile has set null and landmark_anchor null")
        if data["rare"] not in RARE_KINDS:
            out.add(w, "D-91", f"rare kind '{data['rare']}' is not one of {RARE_KINDS}")
        piece = data["set_piece"]
        if _keys(w + ".set_piece", piece, SET_PIECE_KEYS, [], out):
            if piece["asset"] != f"rare_{data['rare']}":
                out.add(w, "rule 5", f"the set piece '{piece['asset']}' is not the band-1 piece of kind '{data['rare']}'")
            yaw = float(piece["yaw_deg"])
            if math.fmod(yaw, 90.0) != 0.0 or yaw < 0.0 or yaw >= 360.0:
                out.add(w, "rule 5", f"yaw_deg {yaw} is not 0, 90, 180 or 270")
    else:
        if data["set"] not in (0, 1):
            out.add(w, "schema", "an ordinary tile has set 0 or 1")
        if data["rare"] != "" or data["set_piece"] is not None:
            out.add(w, "schema", "an ordinary tile has rare \"\" and set_piece null")
        if not _pair(data["landmark_anchor"]):
            out.add(w, "schema", "an ordinary tile has landmark_anchor [x, y]")
            return None
    shells = read_items(w, data, "shells", SHELL_KEYS, [], out)
    zones = read_items(w, data, "zones", ZONE_KEYS, [], out)
    sites = read_items(w, data, "sites", SITE_KEYS, SITE_OPTIONAL, out)
    check_items_types(w, shells, zones, sites, {z["id"] for z in zones}, out)
    return {"where": w, "id": data["id"], "region": region, "set": data["set"], "rare": data["rare"],
            "anchor": tuple(data["landmark_anchor"]) if not is_rare else None,
            "set_piece": data["set_piece"] if is_rare else None, "shells": shells, "zones": zones, "sites": sites}


def check_tile(t, out, reach=True, report=None):
    """Every per-tile rule (2 to 12, D-134, D-135, D-136, D-147, BP3-8, F9); returns content_counts."""
    w = t["where"]
    check_shells_zones(w, t, HALF_TILE, out)
    if t["anchor"] is not None:
        check_anchor_shells(w, t, out)
        for n in SIZES:
            for o in range(8):
                if clear_point_rings(t, n, o) is None:
                    out.add(w, "BP3-8", f"size {n} orientation {o}: no clear point within {LANDMARK_RINGS} rings of the anchor")
    else:
        for c in colliders_of(t):
            if PIECE_ID.match(c["id"]) and (abs(c["c"][0]) + c["r"] > SHELL_EDGE or abs(c["c"][1]) + c["r"] > SHELL_EDGE):
                out.add(w, "rule 5", f"set-piece collider '{c['id']}' comes within 4 bu of the edge")
    check_sites(w, t, HALF_TILE, out)
    if t["region"] == "warden_flat":
        zones = {z["id"]: z for z in t["zones"]}
        for s in t["sites"]:
            z = zones.get(s.get("territory_zone", ""))
            if s["species"] == "warden" and z is not None and not (WARDEN_MEADOW_R[0] <= z["radius"] <= WARDEN_MEADOW_R[1]):
                out.add(f"{w} site '{s['id']}'", "spine 6.3", f"a Warden flat's Warden holds a wide meadow, radius {WARDEN_MEADOW_R[0]} to {WARDEN_MEADOW_R[1]} bu")
    counts = check_content(w, t, out, ordinary=t["region"] != RARE)
    if t["id"] in MANIFEST:
        check_manifest(w, t["sites"], MANIFEST[t["id"]], out)
    if reach:
        for n in SIZES:
            for with_anchor in ((True, False) if t["anchor"] is not None else (True,)):
                worst, at = reach_worst(t, n, -HALF_TILE, HALF_TILE, with_anchor)
                label = "" if with_anchor else " without the landmark"
                if report is not None:
                    report.append(f"{t['id']} size {n}{label}: F9 worst {worst:.2f} tm at {at}")
                if worst > BUDGET_TM:
                    out.add(w, "F9", f"size {n}{label}: an open point {at} is {worst:.2f} tm from food; budget {BUDGET_TM}")
    return counts


def check_tiles(tiles, out, reach=True, report=None):
    by_id = {t["id"]: t for t in tiles}
    # Rule 1: 3 + 3 tiles per region (ids a to c set 0, d to f set 1), one tile per rare kind.
    for region in REGIONS:
        for i, letter in enumerate(TILE_LETTERS):
            tid = f"{region}_{letter}"
            t = by_id.get(tid)
            if t is None:
                out.add(f"b1/{tid}", "rule 1", "missing")
            elif t["region"] != region or t["set"] != (0 if i < 3 else 1):
                out.add(t["where"], "rule 1", f"needs region {region} and set {0 if i < 3 else 1}")
    kinds = sorted(t["rare"] for t in tiles if t["region"] == RARE)
    if kinds != RARE_KINDS:
        out.add("b1", "rule 1", f"rare kinds {kinds}; they must be {RARE_KINDS}, one tile each")
    for t in tiles:
        if t["region"] == RARE and t["id"] != t["rare"]:
            out.add(t["where"], "rule 1", f"a rare tile is named after its kind ('{t['rare']}')")
    extra = sorted(set(by_id) - set(MANIFEST))
    if extra:
        out.add("b1", "rule 1", f"tiles outside the manifest: {extra}")
    behaviours = {n: set() for n in SIZES}
    per_region = {r: {0: [], 1: []} for r in REGIONS}
    for t in tiles:
        counts = check_tile(t, out, reach, report)
        for n in SIZES:
            behaviours[n].update(counts[n]["threats"])
        if t["region"] in REGIONS and t["set"] in (0, 1):
            per_region[t["region"]][t["set"]].append(counts[SECOND]["creature"])
    for n in SIZES:
        if len(behaviours[n]) < 2:
            out.add("b1", "rule 7", f"the live threats at size {n} are {sorted(behaviours[n])}; they need 2 behaviours")
    # S3G6 and D-97: set-0 tiles carry 2 creature sites at size 4 and set-1 tiles 1, so every region
    # averages 1.5 and any 2 x 2 of tiles holds at most 6.
    for region, sets in per_region.items():
        if any(c != 2 for c in sets[0]) or any(c != 1 for c in sets[1]):
            out.add(f"b1/{region}", "S3G6", f"creature sites at size 4 by set {sets}; set 0 has 2 and set 1 has 1")
        allc = sets[0] + sets[1]
        if len(allc) == 6 and sum(allc) / 6.0 != 1.5:
            out.add(f"b1/{region}", "S3G6", f"size-4 average {sum(allc) / 6.0}; it is 1.5")


# --- the cradle ---

def quadrant_of(x, y):
    return (-1 if x < 0 else 0, -1 if y < 0 else 0)


def quadrant_block(cradle, q):
    """A quadrant as a tile (CradleBlock.as_tiles): what is centred in it, moved to its own frame."""
    ox, oy = 32.0 * (2 * q[0] + 1), 32.0 * (2 * q[1] + 1)

    def mv(p):
        return [p[0] - ox, p[1] - oy]

    shells = [dict(s, center=mv(s["center"])) for s in cradle["shells"] if quadrant_of(*s["center"]) == q]
    zones = [dict(z, center=mv(z["center"])) for z in cradle["zones"] if quadrant_of(*z["center"]) == q]
    sites = []
    for s in cradle["sites"]:
        if quadrant_of(*s["home"]) != q:
            continue
        m = dict(s, home=mv(s["home"]))
        if "post_b" in s:
            m["post_b"] = dict(s["post_b"], home=mv(s["post_b"]["home"]))
        sites.append(m)
    return {"where": f"cradle quadrant {q}", "shells": shells, "zones": zones, "sites": sites, "anchor": None,
            "set_piece": None, "origin": (ox, oy)}


def check_cradle(path, root, out, reach=True, report=None):
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        out.add("cradle_b1", "schema", f"not readable JSON ({e})")
        return
    check_cradle_data(data, root, out, reach, report)


def check_cradle_data(data, root, out, reach=True, report=None):
    """S3G3 and the per-quadrant tile rules (D-94, s3-sim 4.4), and F9 over the whole block."""
    w = "cradle_b1"
    _colour_scan(w, data, out)
    if not _keys(w, data, CRADLE_KEYS, [], out):
        return
    if data["schema_version"] != 1 or data["band"] != BAND:
        out.add(w, "schema", "schema_version 1 and band 1")
    ring = data["pool_ring"]
    if _keys(w + ".pool_ring", ring, list(POOL_RING_KEYS), [], out):
        for k, kind in POOL_RING_KEYS.items():
            if (kind == "number") != _is_num(ring[k]) or (kind == "text" and not isinstance(ring[k], str)):
                out.add(w, "schema", f"pool_ring.{k} must be a {kind}")
        rec_path = os.path.join(root, "assets", "records", "cradle_ring.json")
        try:
            with open(rec_path) as f:
                rec_r = json.load(f).get("radius_bu")
        except (OSError, ValueError):
            rec_r = None
        if ring["radius_bu"] != 14.0625 or (rec_r is not None and ring["radius_bu"] != rec_r):
            out.add(w, "BP3-14", f"pool_ring.radius_bu {ring['radius_bu']} must equal the cradle_ring record's {rec_r} (14.0625)")
        if not (ring["radius_bu"] < data["clear_r_bu"]):
            out.add(w, "S3G3", "pool_ring.radius_bu must be under clear_r_bu")
        if ring["caption"] != CRADLE_CAPTION or ring["dressing"] != "cradle_ring":
            out.add(w, "D-116", f"caption '{CRADLE_CAPTION}' and dressing 'cradle_ring'")
    clear_r = float(data["clear_r_bu"])
    if clear_r != 16.0:
        out.add(w, "D-95", f"clear_r_bu {clear_r}; the plan's is 16.0")
    shells = read_items(w, data, "shells", SHELL_KEYS, [], out)
    zones = read_items(w, data, "zones", ZONE_KEYS, [], out)
    sites = read_items(w, data, "sites", SITE_KEYS, SITE_OPTIONAL, out)
    check_items_types(w, shells, zones, sites, {z["id"] for z in zones}, out)
    cradle = {"where": w, "shells": shells, "zones": zones, "sites": sites, "anchor": None, "set_piece": None}
    outer = lambda c, r, lim: abs(c[0]) + r <= CRADLE_HALF - (32.0 - lim) + 1e-9 and abs(c[1]) + r <= CRADLE_HALF - (32.0 - lim) + 1e-9
    check_shells_zones(w, cradle, 32.0, out, edge_ok=outer)
    for s in shells:
        d = dist((0.0, 0.0), s["center"]) - s["radius"]
        if d < clear_r:
            out.add(f"{w} shell '{s['id']}'", "S3G3", f"lies {d:.2f} bu from the centre, inside the clear disc {clear_r}")
        if d < CRADLE_SHELL_BEYOND:
            out.add(f"{w} shell '{s['id']}'", "Q3V-11", f"lies {d:.2f} bu from the centre; cradle shells keep beyond {CRADLE_SHELL_BEYOND}")
    vp = data["view_point_bu"]
    for n in SIZES:
        for c in colliders_of(cradle, n):
            if dist(vp, c["c"]) < c["r"] + CELL_R_TM / S_TM[n]:
                out.add(w, "S3G3", f"size {n}: view_point_bu {vp} is not clear of '{c['id']}'")
    for s in sites:
        for label, disc, _ in site_discs(cradle, s):
            for n in SIZES:
                if role_at(s, n) in ("threat", "rival", "prey"):
                    gap = dist((0.0, 0.0), disc["c"]) - disc["r"] - body_r(s["species"], n)
                    if gap < clear_r:
                        out.add(f"{w} site '{s['id']}' {label}", "S3G3", f"size {n}: its reach disc comes {gap:.2f} bu from the centre, inside {clear_r}")
        if "post_b" in s and quadrant_of(*s["post_b"]["home"]) != quadrant_of(*s["home"]):
            out.add(f"{w} site '{s['id']}'", "D-94", "both posts lie in the site's quadrant")
    quadrants = [(-1, -1), (0, -1), (-1, 0), (0, 0)]
    for q in quadrants:
        b = quadrant_block(cradle, q)
        # Each quadrant is checked as one tile (D-94): its shells keep 4 bu inside the quadrant and its
        # zones 1 bu, except a zone centred in the clear disc (the spine's g1), which spans quadrants.
        for s, raw in zip(b["shells"], [x for x in shells if quadrant_of(*x["center"]) == q]):
            if abs(s["center"][0]) + s["radius"] > SHELL_EDGE + 1e-9 or abs(s["center"][1]) + s["radius"] > SHELL_EDGE + 1e-9:
                out.add(f"{b['where']} shell '{s['id']}'", "rule 2", f"at {raw['center']} comes within 4 bu of its quadrant's edge")
        for z, raw in zip(b["zones"], [x for x in zones if quadrant_of(*x["center"]) == q]):
            if dist((0.0, 0.0), raw["center"]) < clear_r:
                continue
            if abs(z["center"][0]) + z["radius"] > ZONE_EDGE + 1e-9 or abs(z["center"][1]) + z["radius"] > ZONE_EDGE + 1e-9:
                out.add(f"{b['where']} zone '{z['id']}'", "rule 3", f"at {raw['center']} comes within 1 bu of its quadrant's edge")
        check_sites(b["where"], b, 32.0, out, anchor_rule=False)
        check_content(b["where"], b, out, ordinary=True)
        check_manifest(b["where"], b["sites"], CRADLE_MANIFEST[q], out)
        if not any(s["species"] == "elder_warden" for s in b["sites"]):
            out.add(b["where"], "SQ3-4", "an elder Warden in every quadrant")
    if reach:
        for n in SIZES:
            worst, at = reach_worst(cradle, n, -CRADLE_HALF, CRADLE_HALF)
            if report is not None:
                report.append(f"cradle size {n}: F9 worst {worst:.2f} tm at {at}")
            if worst > BUDGET_TM:
                out.add(w, "F9", f"size {n}: an open point {at} is {worst:.2f} tm from food; budget {BUDGET_TM}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Check the band-1 tiles and cradle from the data alone.")
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    ap.add_argument("--no-reach", action="store_true", help="skip the F9 reach grids (the slow part)")
    ap.add_argument("--quiet", action="store_true", help="print problems only")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    out = Problems()
    report = None if args.quiet else []
    tile_dir = os.path.join(root, "game", "data", "tiles", "b1")
    names = sorted(n for n in os.listdir(tile_dir) if n.endswith(".json")) if os.path.isdir(tile_dir) else []
    if not names:
        out.add("b1", "rule 1", f"no tiles in {tile_dir}")
    tiles = [t for t in (load_tile(os.path.join(tile_dir, n), out) for n in names) if t is not None]
    check_tiles(tiles, out, reach=not args.no_reach, report=report)
    check_cradle(os.path.join(root, "game", "data", "cradle_b1.json"), root, out, reach=not args.no_reach, report=report)
    for line in report or []:
        print("check_band1: " + line)
    for p in out.items:
        print("check_band1: " + p)
    print(f"check_band1: {len(tiles)} tiles and the cradle, {len(out.items)} problems")
    return 1 if out.items else 0


if __name__ == "__main__":
    sys.exit(main())
