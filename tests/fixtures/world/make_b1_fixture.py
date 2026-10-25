"""Writes the band-1 test world (s3-sim D-146; S3 T3.1): tests/fixtures/world/world_b1_min.json and its
band-1 tiles in tests/fixtures/world/tiles_b1/b1. Each region's tiles are two of the real ones, _a for
set 0 and _d for set 1, each copied three times under the ids _a to _c and _d to _f, so rule 1's
3 + 3 per region holds with a small, fixed set; the 4 rare tiles are the real ones. Band 0 is
world_min.json's, the cradle the real cradle_b1.json, and landmark_return is on (BP3-17).
Run with python3 -I tests/fixtures/world/make_b1_fixture.py from anywhere."""
import json, os, shutil

wt = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
real = os.path.join(wt, "game/data/tiles/b1")
out = os.path.join(wt, "tests/fixtures/world/tiles_b1/b1")
if os.path.isdir(out):
    shutil.rmtree(out)
os.makedirs(out)

def write(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

for region in ["veil_garden", "warden_flat", "glass_reef"]:
    for source, ids in [("a", "abc"), ("d", "def")]:
        with open(os.path.join(real, "%s_%s.json" % (region, source))) as f:
            tile = json.load(f)
        for letter in ids:
            copy = dict(tile)
            copy["id"] = "%s_%s" % (region, letter)
            copy["note"] = "Test copy of %s_%s (D-146)." % (region, source)
            write(os.path.join(out, copy["id"] + ".json"), copy)
for rare in ["sunbeam_well", "fallen_lattice", "sponge_grove", "shed_shell"]:
    shutil.copyfile(os.path.join(real, rare + ".json"), os.path.join(out, rare + ".json"))

with open(os.path.join(wt, "tests/fixtures/world/world_min.json")) as f:
    world = json.load(f)
world["note"] = "The band-1 test world (s3-sim D-146), written by make_b1_fixture.py: world_min.json reaching size 4."
world["sizes"]["max_in_build"] = 4
world["arrangement"]["bands"] = {"1": {"region_order": ["veil_garden", "warden_flat", "glass_reef"],
                                       "fixed_rare_kind": "sunbeam_well"}}
world["content"]["tiles"]["1"] = "res://tests/fixtures/world/tiles_b1/b1"
world["content"]["cradle"] = {"1": "res://game/data/cradle_b1.json"}
world["ladder"]["food_looks"] = [{"plant": "plankton", "meat": "carrion"}, {"plant": "algae_ball", "meat": "carrion"},
                                 {"plant": "glass_flake", "meat": "carrion"}, {"plant": "bead_cluster", "meat": "carrion"}]
world["switches"]["landmark_return"] = True
write(os.path.join(wt, "tests/fixtures/world/world_b1_min.json"), world)
print("make_b1_fixture: %d tiles and world_b1_min.json" % len(os.listdir(out)))
