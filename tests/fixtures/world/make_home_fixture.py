"""Writes the T1 fixture home block (tests/fixtures/world/home_min.json): the M1 pool from its base
files plus a seam ring of 16 outer zones hugging the block's edge, 4 inner zones on the diagonals
bridging the pool to the ring, and 8 shells at r 44. Reach over [-64, 64)^2 (the M1 rocks and zones
plus this ring, 0.5 bu grid, 8 directions) is 13.6 tm against the 16.3 tm budget; with zone e
deleted it is 25.4 tm. Run with python3 from anywhere; it writes next to itself."""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUTER = [("e", 50, 0), ("ese", 56, 28), ("se", 56, 56), ("sse", 28, 56), ("s", 0, 50), ("ssw", -28, 56),
         ("sw", -56, 56), ("wsw", -56, 28), ("w", -50, 0), ("wnw", -56, -28), ("nw", -56, -56), ("nnw", -28, -56),
         ("n", 0, -50), ("nne", 28, -56), ("ne", 56, -56), ("ene", 56, -28)]
INNER = [("ise", 30, 30), ("isw", -30, 30), ("inw", -30, -30), ("ine", 30, -30)]
RADII = [1.4, 1.0, 0.8, 1.2, 0.9, 1.3, 0.7, 1.1]

zones = [{"id": zid, "center": [float(x), float(y)], "radius": 6.0, "capacity": 16.0, "growth_rate": 0.08,
          "at_second_size": "keep"} for zid, x, y in OUTER]
zones += [{"id": zid, "center": [float(x), float(y)], "radius": 5.0, "capacity": 16.0, "growth_rate": 0.08,
           "at_second_size": "thin"} for zid, x, y in INNER]
shells = []
for k in range(8):
    a = math.radians(22.5 + 45 * k)
    shells.append({"id": "s" + "abcdefgh"[k], "center": [round(44 * math.cos(a), 2), round(44 * math.sin(a), 2)],
                   "radius": RADII[k], "yaw_deg": [0.0, 360.0], "at_second_size": "keep"})
home = {"schema_version": 1, "status": "PROPOSED",
        "note": "T1 test fixture: the M1 pool unwalled plus a minimal seam ring (20 zones, 8 shells); not game content.",
        "band": 0, "base_layout": "res://game/data/pool_m1.json", "base_sites": "res://game/data/creatures_m1.json",
        "seam_inner_r": 36.0, "shells": shells, "zones": zones, "sites": []}
with open(os.path.join(HERE, "home_min.json"), "w") as f:
    json.dump(home, f, indent="\t")
    f.write("\n")
