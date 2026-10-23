"""The endless world's band-1 placement kit (S3, docs/endless-cell-plan.md A.2 and I), in finished art:
five larger glass shells, six landmarks and four rare set pieces for the glass reef, the veil gardens
and the Warden flats.

Every piece meets the band-0 kit's contract in bu (tools/blender/make_s1_kit.py: the swim-band
outline, heights, anchor, apron, colliders, hues, root and growth node names), so the world draws it
2.56 times larger in tm at band 1 with no new rules. Each is built with the band-0 kit's helpers and
checks, then surfaced and baked by make_s1_production.finish(). Records carry "band": 1; the pieces
join game/data/placement_kit.json when engineering's S3 build plan defines the band-1 entries.
Microscopic designs only: glass sponges, foraminifera, heliozoa, diatom chains, stalked bells.

Run: python tools/blender/make_s3_kit.py [--only <id>[,<id>...]]
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_s1_kit as k  # noqa: E402
import make_s1_production as p1  # noqa: E402
from mathutils import Vector  # noqa: E402

GENERATOR = "tools/blender/make_s3_kit.py"
REVIEW_STATE = p1.REVIEW_STATE
PROVENANCE = ("Original geometry from tools/blender/make_s3_kit.py (band-0 kit helpers in make_s1_kit.py), surfaced by "
              "make_s1_production.finish(): procedural shaders baked to textures. No outside sources.")
BAND = 1


# --- Shells -------------------------------------------------------------------------------------


def _shell_base(fr, wall, mat, lobes=(0, 0.0)):
    """The shared shell wall: a round side through the swim band, sunk to a base well below."""
    bottom = -1.6 - 0.4 * fr
    prof = [(0.0, bottom), (fr * 0.6, bottom + 0.15), (fr * 0.92, -1.1), (fr, -0.6), (fr, -0.3), (fr, 0.0), (fr, 0.2), (fr, wall)]
    return prof, bottom


def sh_lattice_cap(m, fr):
    prof, _ = _shell_base(fr, 0.28, m["silica"])
    prof += [(fr * 0.96, 0.32), (0.0, 0.33)]
    k.revolve("Body", prof, m["silica"], 40, lobes=(16, 0.02), lobe_band=(-0.5, 0.5))
    k.lattice("Cap", fr * 0.92, (0, 0, 0.3), m["frost"], 2, 0.035, (1, 1, 0.3), keep=lambda co: co.z > -0.05)


def sh_tiered_disc(m, fr):
    prof, _ = _shell_base(fr, 0.2, m["frost"])
    for r, z in ((fr * 0.98, 0.24), (fr * 0.8, 0.26), (fr * 0.78, 0.38), (fr * 0.56, 0.4), (fr * 0.54, 0.5), (fr * 0.3, 0.52), (0.0, 0.53)):
        prof.append((r, z))
    k.revolve("Body", prof, m["frost"], 40, lobes=(9, 0.04), lobe_band=(-0.5, 0.5))
    k.sphere("Core", fr * 0.22, (0, 0, 0.5), m["core"], 12, 6, (1, 1, 0.6))


def sh_rimmed_cup(m, fr):
    prof, _ = _shell_base(fr, 0.42, m["silica"])
    prof += [(fr * 0.97, 0.47), (fr * 0.88, 0.44), (fr * 0.8, 0.2), (0.0, 0.16)]
    k.revolve("Body", prof, m["silica"], 40, lobes=(20, 0.015), lobe_band=(-0.5, 0.5))
    k.torus("Lip", fr * 0.93, 0.045, m["frost"], (0, 0, 0.46), seg=(32, 4))
    k.sphere("Pearl", fr * 0.2, (0, 0, 0.26), m["lavender"], 12, 6)


def sh_spined_drum(m, fr):
    prof, _ = _shell_base(fr, 0.3, m["frost"])
    prof += [(fr * 0.94, 0.36), (fr * 0.5, 0.4), (0.0, 0.41)]
    k.revolve("Body", prof, m["frost"], 40, lobes=(12, 0.02), lobe_band=(-0.5, 0.5))
    for i in range(12):
        a = i * math.tau / 12
        base = Vector((0.25 * fr * math.cos(a), 0.25 * fr * math.sin(a), 0.4))
        tip = Vector((0.85 * fr * math.cos(a), 0.85 * fr * math.sin(a), 0.56))
        k.tube(f"Spine{i}", [base, (base + tip) / 2 + Vector((0, 0, 0.04)), tip], 0.035, m["silica"], 5, True)


def sh_glass_dome(m, fr):
    prof, _ = _shell_base(fr, 0.22, m["silica"])
    for i in range(1, 6):
        a = i / 5 * math.pi / 2
        prof.append((fr * math.cos(a) ** 0.7, 0.22 + 0.3 * math.sin(a)))
    prof[-1] = (0.0, 0.52)
    k.revolve("Body", prof, m["silica"], 36, lobes=(18, 0.02), lobe_band=(-0.5, 0.5))
    for i in range(8):
        a = i * math.tau / 8
        k.sphere(f"Pore{i}", 0.09, (0.6 * fr * math.cos(a), 0.6 * fr * math.sin(a), 0.44), m["lavender"], 8, 4, (1, 1, 0.5))


SHELLS = {
    # id: (builder, footprint class, footprint radius, scale range, what)
    "shell_b1_lattice_cap": (sh_lattice_cap, "fp_s", 0.8, [0.75, 1.13], "a glass drum under a low lattice cap"),
    "shell_b1_tiered_disc": (sh_tiered_disc, "fp_s", 0.7, [0.85, 1.29], "a stepped, scalloped glass disc with an amber core"),
    "shell_b1_rimmed_cup": (sh_rimmed_cup, "fp_m", 1.0, [0.90, 1.20], "an open glass cup with a rolled lip, a lavender pearl inside"),
    "shell_b1_spined_drum": (sh_spined_drum, "fp_m", 1.1, [0.81, 1.37], "a frosted drum with a star of glass spines on its crown"),
    "shell_b1_glass_dome": (sh_glass_dome, "fp_l", 1.35, [0.88, 1.12], "a broad ribbed glass dome ringed with lavender pores"),
}


def build_shell(asset_id):
    builder, cls, fr, scale, what = SHELLS[asset_id]
    builder(k._mats(), fr)
    k.assemble(asset_id)
    fields = {
        "purpose": f"Endless world band-1 shell (S3): {what}. An obstacle the cell slides around; slots pick it by footprint class.",
        "category": "shell", "kind": "shell", "band": BAND,
        "pivot": "centre of the footprint on the swim plane (Godot y = 0)",
        "footprint_class": cls, "footprint_radius_m": fr, "yaw_rule": "free", "pickable": True,
        "dressings": [{"id": "plain", "tint": k.TINTS["plain"], "growth": "", "scale": 1.0}],
    }
    k.check_contract("shell", asset_id, fields, scale)
    return fields


# --- Landmarks ----------------------------------------------------------------------------------


def lm_sponge_tower(m):
    """A glass-sponge basket: a tall lattice vase on a frosted drum, an amber glow inside."""
    k.drum("Drum", 2.0, 0.4, -3.2, m["frost"], (12, 0.03), apron=2.6)
    k.lattice("Basket", 1.25, (0, 0, 1.9), m["silica"], 2, 0.06, (1, 1, 1.35), keep=lambda co: co.z > -0.95)
    k.torus("Collar", 1.0, 0.09, m["frost"], (0, 0, 3.35), seg=(40, 6))
    k.sphere("Glow", 0.5, (0, 0, 1.3), m["core"], 16, 8)
    return 0.4, 0.2


def lm_coccolith_stack(m):
    """A coccolith tower: overlapping oval plates stacked and turning as they rise."""
    k.drum("Drum", 2.0, 0.35, -3.0, m["frost"], (18, 0.02), apron=2.5)
    for i in range(7):
        z = 0.6 + i * 0.4
        r = 1.5 - 0.12 * i
        k.revolve(f"Plate{i}", [(0.0, z - 0.06), (r * 0.9, z - 0.08), (r, z), (r * 0.92, z + 0.08), (r * 0.3, z + 0.12), (0.0, z + 0.12)],
                  m["cream"] if i % 2 else m["silica"], 32, lobes=(2, 0.12))
    k.sphere("Cap", 0.4, (0, 0, 3.15), m["amber"], 14, 7, (1, 1, 0.6))
    return 0.35, 0.6


def lm_heliozoan(m):
    """A sun-animalcule's empty test: a glass sphere bristling with long, fine radiating spines."""
    k.drum("Drum", 2.0, 0.35, -3.2, m["frost"], (8, 0.03), apron=2.6)
    k.sphere("Test", 1.2, (0, 0, 1.75), m["silica"], 28, 14)
    k.sphere("Heart", 0.55, (0, 0, 1.75), m["core"], 14, 7)
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(34):
        z = 1.0 - 2.0 * (i + 0.5) / 34
        if z < -0.35:
            continue
        r = math.sqrt(1.0 - z * z)
        d = Vector((r * math.cos(golden * i), r * math.sin(golden * i), z))
        base = Vector((0, 0, 1.75)) + d * 1.15
        reach = 0.8 if d.z > 0.3 else 0.55
        k.tube(f"Axopod{i}", [base, base + d * reach * 0.5, base + d * reach], 0.04, m["frost"], 5, True)
    return 0.35, 1.1


def lm_foram_spiral(m):
    """A foraminifer's chambered test: rounded chambers growing in a rising spiral."""
    k.drum("Drum", 2.0, 0.3, -3.2, m["frost"], (10, 0.03), apron=2.6)
    for i in range(9):
        t = i / 8
        a = t * math.tau * 1.15
        rr = 1.15 * (1.0 - 0.6 * t)
        size = 0.75 * (1.0 - 0.55 * t)
        k.sphere(f"Chamber{i}", size, (rr * math.cos(a), rr * math.sin(a), 0.75 + 2.5 * t), m["cream"] if i % 3 else m["husk"], 16, 8, (1, 1, 0.85))
    k.sphere("Aperture", 0.18, (0.3, 0.2, 3.5), m["amber"], 10, 5)
    return 0.3, 2.0


def lm_diatom_chain(m):
    """A chain of diatom drums joined valve to valve, standing in a zig-zag from its drum."""
    k.drum("Drum", 2.0, 0.35, -3.0, m["frost"], (14, 0.025), apron=2.5)
    p = Vector((-0.2, 0.0, 0.62))
    for i in range(6):
        d = Vector((0.45 if i % 2 == 0 else -0.45, 0.0, 0.55)).normalized()
        c = p + d * 0.3
        cell = k.revolve(f"Cell{i}", [(0.0, -0.32), (0.38, -0.3), (0.42, -0.2), (0.42, 0.2), (0.38, 0.3), (0.0, 0.32)], m["silica"], 24,
                         lobes=(16, 0.04))
        cell.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        cell.location = c
        k.torus(f"Girdle{i}", 0.43, 0.04, m["frost"], tuple(c), tuple(d.to_track_quat("Z", "Y").to_euler()), (24, 4))
        p = p + d * 0.58
    return 0.35, 0.9


def lm_bell_colony(m):
    """A colony of stalked bells: coiled stalks rise from one holdfast, each holding an open bell."""
    k.drum("Holdfast", 2.0, 0.3, -3.2, m["deep"], (6, 0.04), apron=2.6)
    for s in range(6):
        a0 = s * math.tau / 6
        foot = Vector((0.5 * math.cos(a0), 0.5 * math.sin(a0), 0.3))
        top = Vector((1.25 * math.cos(a0), 1.25 * math.sin(a0), 2.4 + 0.35 * (s % 3)))
        pts = []
        for i in range(24):
            t = i / 23
            c = foot.lerp(top, t)
            coil = 0.1 * (1.0 - t)
            pts.append(c + Vector((coil * math.cos(t * 30), coil * math.sin(t * 30), 0.0)))
        k.tube(f"Stalk{s}", pts, 0.05, m["cream"], 6)
        d = (top - foot).normalized()
        bell = k.revolve(f"Bell{s}", [(0.05, 0.0), (0.28, 0.1), (0.42, 0.38), (0.46, 0.5), (0.4, 0.52), (0.32, 0.4), (0.0, 0.3)],
                         m["lavender"], 20)
        bell.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        bell.location = top
    return 0.3, 0.5


LANDMARKS = {
    "landmark_b1_sponge_tower": (lm_sponge_tower, 0, "free", "a glass-sponge basket rising from its drum, glowing inside"),
    "landmark_b1_coccolith_stack": (lm_coccolith_stack, 0, "steps_90", "a coccolith tower of overlapping plates turning as they rise"),
    "landmark_b1_heliozoan": (lm_heliozoan, 1, "free", "a sun-animalcule's empty glass test bristling with fine spines"),
    "landmark_b1_foram_spiral": (lm_foram_spiral, 1, "free", "a foraminifer's chambered test climbing in a spiral"),
    "landmark_b1_diatom_chain": (lm_diatom_chain, 2, "steps_90", "a zig-zag chain of diatom drums joined valve to valve"),
    "landmark_b1_bell_colony": (lm_bell_colony, 3, "free", "a colony of lavender bells on coiled cream stalks"),
}


def build_landmark(asset_id):
    builder, group, yaw_rule, what = LANDMARKS[asset_id]
    m = k._mats()
    rim_z, seed = builder(m)
    growths = k._growths(m, rim_z, seed)
    k.assemble(asset_id, growths)
    fields = {
        "purpose": f"Endless world band-1 landmark (S3): {what}. Collides as a 2 bu circle; the visual fills the 3 bu anchor.",
        "category": "landmark", "kind": "landmark", "band": BAND,
        "pivot": "centre of the anchor on the swim plane (Godot y = 0)",
        "group": group, "footprint_radius_m": k.COLLIDE_R, "collide_radius_bu": k.COLLIDE_R, "anchor_radius_bu": k.ANCHOR_R,
        "yaw_rule": yaw_rule, "dressings": k._dressings(),
    }
    k.check_contract("landmark", asset_id, fields, k.LANDMARK_SCALE)
    return fields


# --- Rare set pieces ----------------------------------------------------------------------------


def _pillar(name, x, y, r, h, mat, lobes=(12, 0.02)):
    return k.revolve(name, [(0.0, -3.0), (r * 0.9, -2.7), (r, -1.6), (r, -0.6), (r, 0.0), (r, 0.6), (r, h), (r * 0.8, h + 0.15), (0.0, h + 0.2)],
                     mat, 32, (x, y, 0.0), lobes, (-0.5, 0.5))


def rare_sunbeam_well(m):
    """Six tall glass pillars round a deep well, each crowned with a lattice cap; far below, a
    bright pool of light where the sunbeam lands (the engine draws the beam)."""
    colliders = []
    for i in range(6):
        a = i * math.tau / 6 + 0.3
        x, y = 3.2 * math.cos(a), 3.2 * math.sin(a)
        colliders.append({"center": [round(x, 4), round(y, 4)], "radius": 0.85})
        h = 2.4 + 0.6 * (i % 3) / 2
        _pillar(f"Pillar{i}", x, y, 0.85, h, m["silica"])
        k.lattice(f"Cap{i}", 0.75, (x, y, h + 0.1), m["frost"], 2, 0.05, (1, 1, 0.9), keep=lambda co: co.z > -0.05)
    k.revolve("Well", [(0.0, -3.4), (2.0, -3.2), (2.4, -2.6), (2.5, -1.7), (2.2, -1.6), (0.0, -2.9)], m["frost"], 48)
    k.sphere("Light", 1.3, (0, 0, -2.6), m["cream"], 24, 10, (1, 1, 0.35))
    return colliders, "sunbeam_well", "six crowned glass pillars round a deep well where a sunbeam lands"


def rare_fallen_lattice(m):
    """A giant radiolarian lattice, fallen and half sunk: one great broken dome, its spines snapped
    and lying round it below the plane."""
    colliders = [{"center": [0.0, 0.0], "radius": 3.2}]
    k.revolve("Rim", [(0.0, -3.4), (2.9, -3.0), (3.2, -1.6), (3.2, -0.6), (3.2, 0.0), (3.2, 0.5), (3.0, 0.7), (0.0, 0.75)],
              m["frost"], 64, lobes=(18, 0.02), lobe_band=(-0.5, 0.5))
    k.lattice("Dome", 3.1, (0, 0, 0.6), m["silica"], 3, 0.08, (1, 1, 0.95),
              keep=lambda co: co.z > 0.0 and not (co.x > 0.9 and co.y > -0.6))   # a broken-open side
    k.sphere("Capsule", 1.0, (-0.6, 0.3, 1.2), m["husk"], 18, 9)
    for i in range(10):
        a = i * math.tau / 10
        p = Vector((3.6 * math.cos(a), 3.6 * math.sin(a), -1.6))
        d = Vector((math.cos(a + 0.6), math.sin(a + 0.6), -0.1)).normalized()
        k.tube(f"Snapped{i}", [p, p + d * 0.7, p + d * 1.2], 0.08, m["silica"], 6, True)
    return colliders, "fallen_lattice", "a giant radiolarian lattice, fallen and half sunk, one side broken open"


def rare_sponge_grove(m):
    """A grove of glass-sponge vases of different heights, lattice-walled, with amber light inside."""
    spots = [(0.0, 0.0, 1.2, 3.2), (2.7, 1.0, 0.95, 2.4), (-2.7, -1.0, 0.95, 2.7), (1.3, -2.5, 0.9, 2.0), (-1.3, 2.5, 0.9, 1.7)]
    colliders = []
    for i, (x, y, r, h) in enumerate(spots):
        colliders.append({"center": [x, y], "radius": r})
        _pillar(f"Base{i}", x, y, r, 0.55, m["frost"], (10, 0.03))
        k.lattice(f"Vase{i}", r * 0.92, (x, y, 0.5 + (h - 0.5) / 2), m["silica"], 2, 0.05, (1, 1, (h - 0.5) / (2 * r * 0.92)),
                  keep=lambda co: True)
        k.sphere(f"Glow{i}", r * 0.45, (x, y, 0.9), m["core"], 12, 6)
    return colliders, "sponge_grove", "a grove of lattice-walled glass-sponge vases glowing amber inside"


def rare_shed_shell(m):
    """A giant's shed shell: the empty chambered test of a giant foraminifer lying on its side,
    three great chambers shrinking along a curve, the largest broken open."""
    chambers = [(-2.4, -0.22, 2.0), (0.9, 0.68, 1.55), (3.2, 0.18, 1.05)]
    colliders = []
    for i, (x, y, r) in enumerate(chambers):
        colliders.append({"center": [x, y], "radius": r})
        k.revolve(f"Chamber{i}", [(0.0, -3.0), (r * 0.9, -2.6), (r, -1.5), (r, -0.6), (r, 0.0), (r, 0.4)] +
                  [(r * math.cos(a) ** 0.8, 0.4 + min(r, 1.8) * math.sin(a)) for a in [j / 6 * math.pi / 2 for j in range(1, 7)]],
                  m["cream"] if i != 1 else m["husk"], 40, (x, y, 0.0), (8, 0.025), (-0.5, 0.5))
    k.lattice("Break", 1.6, (-2.4, -0.22, 1.9), m["frost"], 2, 0.06, (1, 1, 0.5), keep=lambda co: co.z > 0.2)
    for i in range(2):
        x = (chambers[i][0] + chambers[i + 1][0]) / 2
        y = (chambers[i][1] + chambers[i + 1][1]) / 2
        k.torus(f"Suture{i}", 0.4, 0.08, m["deep"], (x, y, -0.9), seg=(20, 4))
    return colliders, "shed_shell", "the empty chambered test of a giant foraminifer lying on its side, broken open"


RARES = {
    "rare_sunbeam_well": rare_sunbeam_well,
    "rare_fallen_lattice": rare_fallen_lattice,
    "rare_sponge_grove": rare_sponge_grove,
    "rare_shed_shell": rare_shed_shell,
}


def build_rare(asset_id):
    colliders, rare_kind, what = RARES[asset_id](k._mats())
    k.assemble(asset_id)
    fields = {
        "purpose": f"Endless world band-1 rare place (S3): {what}.",
        "category": "rare", "kind": "rare", "band": BAND,
        "pivot": "centre of the set piece on the swim plane (Godot y = 0)",
        "rare_kind": rare_kind, "colliders": colliders, "yaw_rule": "fixed", "dressings": [],
    }
    k.check_contract("rare", asset_id, fields, [1.0, 1.0])
    return fields


ASSETS = {
    **{i: ((lambda i=i: build_shell(i)), k.BUDGET["shell"]) for i in SHELLS},
    **{i: ((lambda i=i: build_landmark(i)), k.BUDGET["landmark"]) for i in LANDMARKS},
    **{i: ((lambda i=i: build_rare(i)), k.BUDGET["rare"]) for i in RARES},
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the endless world's band-1 kit.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    parser.add_argument("--rough", action="store_true", help="skip surfacing and baking (fast contract check)")
    args = parser.parse_args(argv)
    ids = [i for i in args.only.split(",") if i] or list(ASSETS)
    unknown = [i for i in ids if i not in ASSETS]
    if unknown:
        parser.error(f"unknown asset id(s): {', '.join(unknown)}; known: {', '.join(ASSETS)}")
    failed = []
    for asset_id in ids:
        builder, budget = ASSETS[asset_id]
        bc.reset_scene()
        try:
            fields = builder()
        except RuntimeError as err:
            print("FAILED", err)
            failed.append(asset_id)
            continue
        if args.rough:
            print(f"{asset_id}: contract ok, {bc.triangle_count()} triangles")
            continue
        fields["textures"] = p1.finish(asset_id, fields["kind"])
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR, provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")
    if failed:
        raise SystemExit(f"failed: {', '.join(failed)}")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
