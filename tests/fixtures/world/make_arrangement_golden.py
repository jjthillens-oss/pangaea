"""Writes tests/fixtures/world/arrangement_golden.json: WorldGen.tile_info and landmark_of_cell on the
fixture world for a spread of tiles and cells and two seeds, computed again here in Python from the
spine's arrangement (docs/s1/s1-interfaces.md 3.6, docs/s1/s1-core.md 6.4) and tools/world_hash_ref.py,
not from the GDScript. tests/test_world_gen.gd checks the generator against it, so a slip in the
noise, the drift swap, the rare blocks, the id pick or the landmark pick fails a test.

Run with python3 -I from anywhere; it reads the fixture world next to itself and writes next to it.
"""
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
_spec = importlib.util.spec_from_file_location("world_hash_ref", os.path.join(ROOT, "tools", "world_hash_ref.py"))
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)

SEEDS = [4242, 401]
GEN = 1
BAND = 0


def res(path):
    return os.path.join(ROOT, path[len("res://"):])


world = json.load(open(os.path.join(HERE, "world_min.json")))
arr = world["arrangement"]
P = arr["region_period_tiles"]
T0, T1 = arr["region_thresholds"]
ORDER = arr["region_order"]
DRIFT = ORDER.index("drift")
HOME_LO, HOME_HI = arr["home_tiles"]
FIRST = arr["rare_block_first_tile"]
BLOCK = arr["rare_block_tiles"]
CELL = arr["landmark_cell_tiles"]
FIXED_TILE = tuple(arr["fixed_rare"]["tile"])
FIXED_KIND = arr["fixed_rare"]["kind"]

tiles = []
tile_dir = res(world["content"]["tiles"]["0"])
for name in sorted(os.listdir(tile_dir)):
    if name.endswith(".json"):
        tiles.append(json.load(open(os.path.join(tile_dir, name))))
kit = json.load(open(res(world["content"]["kit"])))


def ids_of(region, set_index):
    return sorted(t["id"] for t in tiles if t["band"] == BAND and t["region"] == region and t["set"] == set_index)


RARE_KINDS = sorted({t["rare"] for t in tiles if t["region"] == "rare"})
RARE_ID = {t["rare"]: t["id"] for t in sorted(tiles, key=lambda t: t["id"]) if t["region"] == "rare"}


def landmarks(group):
    return sorted(a["id"] for a in kit["assets"] if a["kind"] == "landmark" and a["band"] == BAND and a["group"] == group)


DRESSINGS = {a["id"]: [d["id"] for d in a["dressings"]] for a in kit["assets"]}


def fdiv(a, n):
    return a // n   # Python's // floors, as the spine's fdiv does


def lerp(a, b, t):
    return a + (b - a) * t   # Godot's lerpf


class Gen:
    def __init__(self, seed):
        self.seed = seed
        self.lattice = {}

    def key(self, i, j, purpose):
        return wh.key(self.seed, GEN, BAND, i, j, purpose)

    def lat(self, i, j):
        if (i, j) not in self.lattice:
            self.lattice[(i, j)] = self.key(i, j, "region") / 4294967296.0
        return self.lattice[(i, j)]

    def raw(self, tx, ty):
        i0, j0 = fdiv(tx, P), fdiv(ty, P)
        fx = (float(tx - i0 * P) + 0.5) / P
        fy = (float(ty - j0 * P) + 0.5) / P
        sx = fx * fx * (3.0 - 2.0 * fx)
        sy = fy * fy * (3.0 - 2.0 * fy)
        top = lerp(self.lat(i0, j0), self.lat(i0 + 1, j0), sx)
        bottom = lerp(self.lat(i0, j0 + 1), self.lat(i0 + 1, j0 + 1), sx)
        v = lerp(top, bottom, sy)
        return 0 if v < T0 else (1 if v < T1 else 2)

    def region(self, tx, ty):
        r = self.raw(tx, ty)
        if r == DRIFT and ((self.raw(tx - 1, ty) == DRIFT and self.raw(tx - 2, ty) == DRIFT)
                           or (self.raw(tx, ty - 1) == DRIFT and self.raw(tx, ty - 2) == DRIFT)):
            return "sunlit"
        return ORDER[r]

    def rare_of_block(self, bx, by):
        if (bx, by) == (0, 0):
            return FIXED_TILE, FIXED_KIND, 0
        h = self.key(bx, by, "rare")
        tile = (FIRST + BLOCK * bx + 2 + h % 2, FIRST + BLOCK * by + 2 + (h // 2) % 2)
        return tile, RARE_KINDS[(h // 4) % len(RARE_KINDS)], wh.mix32(h, 3) % 8

    def tile_info(self, tx, ty):
        if HOME_LO <= tx <= HOME_HI and HOME_LO <= ty <= HOME_HI:
            return {"id": "", "region": "home", "rare": "", "set": -1, "orientation": 0}
        tile, kind, o = self.rare_of_block(fdiv(tx - FIRST, BLOCK), fdiv(ty - FIRST, BLOCK))
        if tile == (tx, ty):
            return {"id": RARE_ID.get(kind, ""), "region": "rare", "rare": kind, "set": -1, "orientation": o}
        region = self.region(tx, ty)
        s = (tx + ty) % 2
        ids = ids_of(region, s)
        h = self.key(tx, ty, "tile")
        return {"id": ids[h % 3], "region": region, "rare": "", "set": s, "orientation": (h // 3) % 8}

    def landmark_of_cell(self, lx, ly):
        cands = []
        for dy in range(CELL):
            for dx in range(CELL):
                t = (CELL * lx + dx, CELL * ly + dy)
                if self.tile_info(*t)["region"] not in ("home", "rare"):
                    cands.append(t)
        models = landmarks(lx % 2 + 2 * (ly % 2))
        if not cands or not models:
            return {}
        h = self.key(lx, ly, "landmark")
        model = models[wh.mix32(h, 1) % len(models)]
        dressings = DRESSINGS[model]
        return {"tile": list(cands[h % len(cands)]), "model": model,
                "dressing": dressings[wh.mix32(h, 2) % len(dressings)]}


points = [(tx, ty) for ty in range(-41, 42, 9) for tx in range(-40, 41, 7)]
points += [(tx, ty) for ty in range(-2, 2) for tx in range(-2, 4)]           # home, its ring, the fixed rare
points += [(1562, -1563), (-1563, 1562), (100000, -100000), (-7, 13), (13, -7)]
points += [(tx, ty) for ty in range(-50, -38) for tx in range(100, 112)]     # a dense patch, for drift runs
cells = [(lx, ly) for ly in range(-6, 7, 3) for lx in range(-6, 7, 2)] + [(-1, -1), (0, 0), (781, -782)]
out = {"note": "Written by make_arrangement_golden.py from the spine's arrangement and tools/world_hash_ref.py; "
               "do not edit by hand. Band 0, gen_version 1, the fixture world.",
       "tiles": [], "landmarks": []}
for seed in SEEDS:
    g = Gen(seed)
    rare_points = []
    for by in range(-2, 3):
        for bx in range(-2, 3):
            (rx, ry), _, _ = g.rare_of_block(bx, by)
            rare_points += [(rx, ry), (rx + 1, ry)]
    for tx, ty in points + rare_points:
        out["tiles"].append({"seed": seed, "tx": tx, "ty": ty, "info": g.tile_info(tx, ty)})
    for lx, ly in cells:
        out["landmarks"].append({"seed": seed, "lx": lx, "ly": ly, "value": g.landmark_of_cell(lx, ly)})
with open(os.path.join(HERE, "arrangement_golden.json"), "w") as f:
    f.write('{"note": %s,\n "tiles": [\n' % json.dumps(out["note"]))
    f.write(",\n".join("  " + json.dumps(e, sort_keys=True) for e in out["tiles"]))
    f.write('],\n "landmarks": [\n')
    f.write(",\n".join("  " + json.dumps(e, sort_keys=True) for e in out["landmarks"]))
    f.write("]}\n")
regions = {}
for e in out["tiles"]:
    regions[e["info"]["region"]] = regions.get(e["info"]["region"], 0) + 1
print("tiles %d (%s), landmarks %d (%d empty)" % (len(out["tiles"]), regions, len(out["landmarks"]),
                                                  sum(1 for e in out["landmarks"] if not e["value"])))
