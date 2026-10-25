"""The placement kit writer: game/data/placement_kit.json from the asset records, bands 0 and 1.

Pure Python (no Blender), run from anywhere with `python3 -I tools/kit/write_kit.py`. It replaces
`tools/blender/make_s1_kit.py write_kit()` as the only kit writer (docs/s3: spine D-92 and 6.2,
s3-sim D-143, build plan BP3-15 and 7.3). Nobody edits placement_kit.json by hand; after a merge
that touched a record, run this and commit what it writes.

What it writes:
- the band-0 entries in make_s1_kit's order (KIT_ORDER + HOME_ROCKS), each built exactly as
  make_s1_kit builds it, so every band-0 entry stays byte-identical to the S1 kit's (S3G8b);
- then the band-1 shells, landmarks and rares, each group in id order;
- `band` -1 for a marker, else the record's `band`, 0 when the record has none (band-0 records
  carry no band key);
- `landmark.groups` per band, {"0": [2, 2, 1, 1], "1": [2, 2, 1, 1]};
- the file as `json.dump(kit, f, indent=2)` followed by one newline, as make_s1_kit writes it.

Modes:
  (no flag)            write the two-band kit to game/data/placement_kit.json (or --out)
  --check              build it and compare with the file on disk byte for byte; exit 1 if they differ
  --legacy-band0       build the S1 band-0 kit instead (make_s1_kit's note and its single groups
                       list); with --check this is the byte check against a band-0 kit on disk
  --band0-against P    compare the band-0 entries of the two-band kit, one by one, with the entries
                       of the kit file P (a band-0 kit such as main's); exit 1 on any difference
  --root DIR           the repository root (default: two levels above this file)
  --out PATH           where to write or what to check (default: <root>/game/data/placement_kit.json)
"""
import argparse
import json
import os
import sys

# make_s1_kit.py's KIT_ORDER (its SHELLS, LANDMARKS and RARES tables, then the markers) and
# HOME_ROCKS, copied as id lists because that script needs Blender to import.
BAND0_SHELLS = ["shell_diatom_disc", "shell_radiolarian_lens", "shell_girdle_drum", "shell_fluted_tower", "shell_bell"]
BAND0_LANDMARKS = ["landmark_great_shell", "landmark_ring", "landmark_spire", "landmark_fan", "landmark_arch",
                   "landmark_shed_husk"]
BAND0_RARES = ["rare_giant_husk", "rare_shell_cathedral"]
MARKERS = ["marker_checkpoint_column", "marker_origin_arrow", "marker_lair_mouth"]
KIT_ORDER_B0 = BAND0_SHELLS + BAND0_LANDMARKS + BAND0_RARES + MARKERS
HOME_ROCKS = ["rock_a", "rock_b", "rock_c"]

# The band-1 pieces (spine 6.2), each group in id order.
BAND1_SHELLS = sorted(["shell_b1_glass_dome", "shell_b1_lattice_cap", "shell_b1_rimmed_cup", "shell_b1_spined_drum",
                       "shell_b1_tiered_disc"])
BAND1_LANDMARKS = sorted(["landmark_b1_bell_colony", "landmark_b1_coccolith_stack", "landmark_b1_diatom_chain",
                          "landmark_b1_foram_spiral", "landmark_b1_heliozoan", "landmark_b1_sponge_tower"])
BAND1_RARES = sorted(["rare_fallen_lattice", "rare_shed_shell", "rare_sponge_grove", "rare_sunbeam_well"])
KIT_ORDER_B1 = BAND1_SHELLS + BAND1_LANDMARKS + BAND1_RARES

# The record kinds that belong in the kit; every band-1 record of these kinds must be in the order.
KIT_KINDS = ("shell", "landmark", "rare", "marker")

# D-93's band-1 shell scale ranges, which T3.2 writes into the records (art confirmed them, A-1).
# The writer copies the records; it only warns when a record does not carry these yet.
D93_SCALE = {"shell_b1_lattice_cap": [0.75, 1.13], "shell_b1_tiered_disc": [0.85, 1.29],
             "shell_b1_rimmed_cup": [0.90, 1.20], "shell_b1_spined_drum": [0.81, 1.37],
             "shell_b1_glass_dome": [0.88, 1.12]}

ANCHOR_R = 3.0
COLLIDE_R = 2.0
GROUPS = [2, 2, 1, 1]
FOOTPRINT_CLASSES = {"fp_s": [0.6, 0.9], "fp_m": [0.9, 1.2], "fp_l": [1.2, 1.5]}
LEGACY_NOTE = ("Band-0 placement kit for the endless world (docs/s1/s1-interfaces.md 4.4). "
               "Written by tools/blender/make_s1_kit.py from the asset records.")
NOTE = ("Placement kit for the endless world, bands 0 and 1 (docs/s1/s1-interfaces.md 4.4; S3 spine 6.2). "
        "Written by tools/kit/write_kit.py from the asset records; never edit it by hand.")


def default_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def read_record(root, asset_id):
    with open(os.path.join(root, "assets", "records", f"{asset_id}.json")) as f:
        return json.load(f)


def entry_of(root, asset_id, home_rock=False):
    """One kit entry, built exactly as make_s1_kit.write_kit builds a band-0 entry; `band` falls back
    to 0 for a record with no band key (BP3-15)."""
    rec = read_record(root, asset_id)
    kind = rec.get("kind", "shell")
    entry = {"id": asset_id, "kind": kind, "band": -1 if kind == "marker" else rec.get("band", 0),
             "glb": f"res://{rec['export_path']}", "record": f"res://assets/records/{asset_id}.json"}
    if home_rock:
        entry.update({"footprint_class": "fp_m", "footprint_radius_m": 1.0, "pickable": False, "scale": [0.8, 1.5],
                      "yaw_rule": "free", "dressings": [{"id": "plain", "tint": "#FFFFFF", "growth": "", "scale": 1.0}]})
    else:
        entry.update({"scale": rec["scale_range"], "yaw_rule": rec["yaw_rule"], "dressings": rec["dressings"]})
        if kind == "shell":
            entry.update({k: rec[k] for k in ("footprint_class", "footprint_radius_m", "pickable")})
        elif kind == "landmark":
            entry.update({"group": rec["group"], "footprint_radius_m": rec["footprint_radius_m"]})
        elif kind == "rare":
            entry.update({"rare_kind": rec["rare_kind"], "colliders": rec["colliders"]})
    entry["placeholder"] = rec["review_state"].startswith("blockout")
    entry["approved"] = rec.get("status") == "APPROVED" and not entry["placeholder"]
    return entry


def band0_entries(root):
    return [entry_of(root, i) for i in KIT_ORDER_B0] + [entry_of(root, i, home_rock=True) for i in HOME_ROCKS]


def band1_entries(root):
    out = []
    for asset_id in KIT_ORDER_B1:
        e = entry_of(root, asset_id)
        if e["band"] != 1:
            raise SystemExit(f"write_kit: {asset_id}'s record has band {e['band']}, not 1")
        out.append(e)
    return out


def unlisted_band1(root):
    """Band-1 records of a kit kind that the order does not name (a new art piece needs a line here)."""
    missing = []
    rec_dir = os.path.join(root, "assets", "records")
    for name in sorted(os.listdir(rec_dir)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(rec_dir, name)) as f:
                rec = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(rec, dict) and rec.get("band") == 1 and rec.get("kind") in KIT_KINDS:
            if name[:-5] not in KIT_ORDER_B1:
                missing.append(name[:-5])
    return missing


def build_kit(root, legacy_band0=False):
    if legacy_band0:
        return {"schema_version": 1, "status": "PROPOSED", "note": LEGACY_NOTE,
                "footprint_classes": FOOTPRINT_CLASSES,
                "landmark": {"anchor_radius_bu": ANCHOR_R, "collide_radius_bu": COLLIDE_R, "groups": GROUPS},
                "assets": band0_entries(root)}
    return {"schema_version": 1, "status": "PROPOSED", "note": NOTE,
            "footprint_classes": FOOTPRINT_CLASSES,
            "landmark": {"anchor_radius_bu": ANCHOR_R, "collide_radius_bu": COLLIDE_R,
                         "groups": {"0": list(GROUPS), "1": list(GROUPS)}},
            "assets": band0_entries(root) + band1_entries(root)}


def kit_text(kit):
    """The file's exact text: json.dump(kit, f, indent=2), then one newline."""
    return json.dumps(kit, indent=2) + "\n"


def d93_warnings(kit):
    out = []
    for e in kit["assets"]:
        want = D93_SCALE.get(e["id"])
        if want is not None and [float(v) for v in e["scale"]] != want:
            out.append(f"{e['id']} scale_range {e['scale']} is not D-93's {want} (T3.2's record edit is not applied)")
    return out


def band0_diff(kit, other_path):
    """Problems comparing the band-0 entries of `kit` with the band-0 entries of the kit at other_path,
    entry by entry as text (S3G8b)."""
    with open(other_path) as f:
        other = json.load(f)
    mine = [e for e in kit["assets"] if e["band"] in (-1, 0)]
    theirs = [e for e in other.get("assets", []) if e.get("band") in (-1, 0)]
    problems = []
    if [e["id"] for e in mine] != [e.get("id") for e in theirs]:
        problems.append("band-0 ids differ: %s vs %s" % ([e["id"] for e in mine], [e.get("id") for e in theirs]))
    for a, b in zip(mine, theirs):
        if json.dumps(a, indent=2) != json.dumps(b, indent=2):
            problems.append(f"band-0 entry {a['id']} differs")
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description="Write game/data/placement_kit.json from the asset records.")
    ap.add_argument("--check", action="store_true", help="compare with the file on disk; exit 1 if it differs")
    ap.add_argument("--legacy-band0", action="store_true", help="the S1 band-0 kit (make_s1_kit's format)")
    ap.add_argument("--band0-against", metavar="PATH", help="compare band-0 entries with this kit file")
    ap.add_argument("--root", default=default_root())
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    out = args.out or os.path.join(root, "game", "data", "placement_kit.json")

    if not args.legacy_band0:
        missing = unlisted_band1(root)
        if missing:
            print("write_kit: band-1 records not in the kit order: %s" % ", ".join(missing), file=sys.stderr)
            return 1
    kit = build_kit(root, args.legacy_band0)
    text = kit_text(kit)
    if not args.legacy_band0:
        for w in d93_warnings(kit):
            print("write_kit: note: " + w, file=sys.stderr)

    status = 0
    if args.band0_against:
        problems = band0_diff(kit, args.band0_against)
        for p in problems:
            print("write_kit: " + p, file=sys.stderr)
        print("write_kit: band-0 entries %s %s" % ("differ from" if problems else "equal", args.band0_against))
        status = 1 if problems else 0
    if args.check:
        try:
            with open(out, "rb") as f:
                on_disk = f.read()
        except OSError:
            on_disk = None
        same = on_disk == text.encode("utf-8")
        print("write_kit: %s %s" % ("matches" if same else "differs from", out))
        return status or (0 if same else 1)
    if args.band0_against:
        return status
    with open(out, "w", newline="\n") as f:
        f.write(text)
    print("write_kit: wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
