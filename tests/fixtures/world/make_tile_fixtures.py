"""Writes the T1 fixture tiles (tests/fixtures/world/tiles/b0): 6 per region in two sets, and the two
rare tiles. Each ordinary tile is one of three templates under one of six square symmetries, with its
radii nudged, so no two tiles are the same and every rule of spine 4.2 holds, at size 1 and at size 2
(S2: each threat tile's size-2 threat, a Lurker in reef and the giant husk, an elder rammer in sunlit
and the shell cathedral, with the ambush hunter its second live site there; the anchor sits 25 bu out,
where the size-2 threat's reach keeps the respawn clearance from it)."""
import json, math, os, sys

# The repository root: this file lives in tests/fixtures/world.
wt = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
out = os.path.join(wt, "tests/fixtures/world/tiles/b0")
os.makedirs(out, exist_ok=True)
for f in os.listdir(out):
    os.remove(os.path.join(out, f))

# (mirror, quarter turns) for the six variants; the maps are spine 3.6's orient_point.
VARIANTS = [(0, 0), (1, 0), (0, 1), (0, 2), (0, 3), (1, 1)]

def orient(x, y, m, k):
    if m:
        x = -x
    for _ in range(k):
        x, y = -y, x
    return [x + 0.0, y + 0.0]

def heading(h, m, k):
    if m:
        h = math.pi - h
    h += k * math.pi / 2
    while h >= math.pi:
        h -= 2 * math.pi
    while h < -math.pi:
        h += 2 * math.pi
    return round(h, 4)

THREAT_SHELLS = [("a", -16, -8, 1.2), ("b", -22, -16, 0.8), ("c", -10, -25, 1.0), ("d", 16, -8, 1.4),
                 ("e", 22, -18, 0.7), ("f", 10, -25, 1.1), ("g", -25, 25, 0.9), ("h", 25, 25, 1.35)]
REEF_EXTRA = [("i", -4, -13, 0.8), ("j", 4, -2, 0.7)]
THREAT_ZONES = [("a", 12, 12, 4.0, 40.0, 0.08, "keep"), ("b", -14, 4, 3.0, 30.0, 0.08, "thin")]
THREAT_SITES = [("a", "rammer", 12, 13, -1.5708, "a", [1]), ("b", "ambush_hunter", -12, 12, 0.0, "", [1, 2])]
# The size-2 threats (S2), live at size 2 only.
LURKER = ("lk", "lurker", 8, 14, -2.0899, "", [2])
ELDER = ("er", "elder_rammer", 11.5, 11.5, -2.3562, "a", [2])
RARE_LURKER = ("lk", "lurker", -13, 5, -0.3672, "", [2])
THREAT_ANCHOR = (0, -25)
DRIFT_SHELLS = [("a", -20, 18, 1.0), ("b", -6, 22, 0.7), ("c", 20, 14, 1.4), ("d", 22, -2, 0.9),
                ("e", -22, -22, 1.2), ("f", 2, -4, 0.6)]
DRIFT_ZONES = [("a", 6, 8, 5.0, 40.0, 0.06, "keep"), ("b", -14, -10, 3.0, 24.0, 0.08, "drop")]

def tile(tid, region, set_index, shells, zones, sites, anchor, m, k, nudge, rare="", piece=None):
    data = {"schema_version": 1, "status": "PROPOSED",
            "note": "T1 test fixture: the smallest tile set the rules accept; not game content.",
            "id": tid, "band": 0, "region": region, "set": set_index, "rare": rare,
            "landmark_anchor": None if anchor is None else orient(anchor[0], anchor[1], m, k),
            "set_piece": piece, "shells": [], "zones": [], "sites": []}
    for i, (sid, x, y, r) in enumerate(shells):
        r2 = round(min(1.5, max(0.6, r + nudge * (1 if i % 2 == 0 else -1))), 2)
        yaw = [0.0, 360.0] if i % 3 else [30.0, 120.0]
        data["shells"].append({"id": sid, "center": orient(x, y, m, k), "radius": r2, "yaw_deg": yaw,
                               "at_second_size": "sink" if i == 1 else "keep"})
    for zid, x, y, r, cap, g, second in zones:
        data["zones"].append({"id": zid, "center": orient(x, y, m, k), "radius": r, "capacity": cap,
                              "growth_rate": g, "at_second_size": second})
    for sid, sp, x, y, h, tz, sizes in sites:
        site = {"id": sid, "species": sp, "home": orient(x, y, m, k), "heading": heading(h, m, k), "sizes": sizes}
        if tz:
            site["territory_zone"] = tz
        data["sites"].append(site)
    with open(os.path.join(out, tid + ".json"), "w") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")

for v, (m, k) in enumerate(VARIANTS):
    letter = "abcdef"[v]
    nudge = 0.02 * v
    tile("sunlit_" + letter, "sunlit", v % 2, THREAT_SHELLS, THREAT_ZONES, THREAT_SITES + [ELDER], THREAT_ANCHOR, m, k, nudge)
    tile("reef_" + letter, "reef", v % 2, THREAT_SHELLS + REEF_EXTRA, THREAT_ZONES,
         (THREAT_SITES[:1] if v % 3 == 2 else THREAT_SITES) + [LURKER], THREAT_ANCHOR, m, k, nudge + 0.01)
    tile("drift_" + letter, "drift", v % 2, DRIFT_SHELLS, DRIFT_ZONES, [], (10, -16), m, k, nudge)

RARE_SHELLS = [("a", -20, -20, 1.0), ("b", 20, -20, 1.2), ("c", -25, 25, 0.9), ("d", 25, 25, 1.3)]
for kind, asset in [("giant_husk", "rare_giant_husk"), ("shell_cathedral", "rare_shell_cathedral")]:
    tile("rare_" + kind, "rare", None, RARE_SHELLS, THREAT_ZONES, THREAT_SITES + [RARE_LURKER if kind == "giant_husk" else ELDER],
         None, 0, 0, 0.0, rare=kind,
         piece={"asset": asset, "center": [0.0, -14.0], "yaw_deg": 0.0 if kind == "giant_husk" else 90.0})
print(len(os.listdir(out)), "tiles")
