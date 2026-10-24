"""Writes the T1 fixture kit (tests/fixtures/world/kit_min.json) and its fixture records. Run with
python3 from anywhere; it writes next to itself."""
import json, sys, os
# The repository root: this file lives in tests/fixtures/world.
wt = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
R = "res://tests/fixtures/world/records/"
def rec(id): return R + id + ".json"
assets = []
def shell(id, glb, cls, fr, scale, yaw="free", pickable=True, dress=None, placeholder=True):
    return {"id": id, "kind": "shell", "band": 0, "glb": "res://assets/export/%s.glb" % glb, "record": rec(id),
            "footprint_class": cls, "footprint_radius_m": fr, "scale": scale, "yaw_rule": yaw,
            "dressings": dress or [{"id": "plain", "tint": "#FFFFFF", "growth": "", "scale": 1.0}],
            "pickable": pickable, "placeholder": placeholder, "approved": False}
assets += [
    shell("shell_s_pill", "shell_diatom_disc", "fp_s", 0.75, [0.8, 1.2],
          dress=[{"id": "plain", "tint": "#FFFFFF", "growth": "", "scale": 1.0},
                 {"id": "algae", "tint": "#C8D8B0", "growth": "Growth_Algae", "scale": 1.0}]),
    shell("shell_s_lens", "shell_radiolarian_lens", "fp_s", 0.6, [1.0, 1.5]),
    shell("shell_m_pill", "shell_diatom_disc", "fp_m", 1.0, [0.9, 1.2], yaw="slot"),
    shell("shell_m_lens", "shell_radiolarian_lens", "fp_m", 0.9, [1.0, 1.4]),
    shell("shell_l_bell", "shell_bell", "fp_l", 1.25, [0.96, 1.2]),
    shell("shell_l_tower", "shell_fluted_tower", "fp_l", 1.5, [0.8, 1.0], yaw="slot"),
    shell("shell_l_wide", "shell_bell", "fp_l", 1.2, [1.0, 1.25]),
]
lm_glbs = ["landmark_arch", "landmark_fan", "landmark_great_shell", "landmark_ring", "landmark_spire", "landmark_shed_husk"]
lm_groups = [0, 0, 1, 1, 2, 3]
for glb, g in zip(lm_glbs, lm_groups):
    assets.append({"id": glb, "kind": "landmark", "band": 0, "glb": "res://assets/export/%s.glb" % glb, "record": rec(glb),
                   "group": g, "footprint_radius_m": 2.0, "scale": [0.9, 1.1], "yaw_rule": "steps_90" if g % 2 == 0 else "free",
                   "dressings": [{"id": "pale", "tint": "#E8E0D0", "growth": "", "scale": 1.0},
                                 {"id": "algae", "tint": "#C8D8B0", "growth": "Growth_Algae", "scale": 0.95},
                                 {"id": "tall", "tint": "#D8D0C0", "growth": "", "scale": 1.1}],
                   "placeholder": True, "approved": False})
assets.append({"id": "rare_giant_husk", "kind": "rare", "band": 0, "glb": "res://assets/export/rare_giant_husk.glb",
               "record": rec("rare_giant_husk"), "rare_kind": "giant_husk",
               "colliders": [{"center": [0.0, 0.0], "radius": 3.0}], "scale": [1.0, 1.0], "yaw_rule": "fixed",
               "dressings": [], "placeholder": True, "approved": False})
assets.append({"id": "rare_shell_cathedral", "kind": "rare", "band": 0, "glb": "res://assets/export/rare_shell_cathedral.glb",
               "record": rec("rare_shell_cathedral"), "rare_kind": "shell_cathedral",
               "colliders": [{"center": [-1.5, 0.0], "radius": 2.0}, {"center": [1.5, 0.5], "radius": 1.5}], "scale": [1.0, 1.0],
               "yaw_rule": "fixed", "dressings": [], "placeholder": True, "approved": False})
for mid in ["marker_checkpoint_column", "marker_origin_arrow"]:
    assets.append({"id": mid, "kind": "marker", "band": -1, "glb": "res://assets/export/%s.glb" % mid, "record": rec(mid),
                   "scale": [1.0, 1.0], "yaw_rule": "fixed", "dressings": [], "placeholder": True, "approved": False})
for r in ["rock_a", "rock_b", "rock_c"]:
    assets.append(shell(r, r, "fp_m", 1.0, [0.8, 1.5], pickable=False, placeholder=False))
kit = {"schema_version": 1, "status": "PROPOSED",
       "note": "The smallest kit the endless world's rules accept, for the T1 tests: real GLBs, fixture records.",
       "footprint_classes": {"fp_s": [0.6, 0.9], "fp_m": [0.9, 1.2], "fp_l": [1.2, 1.5]},
       "landmark": {"anchor_radius_bu": 3.0, "collide_radius_bu": 2.0, "groups": [2, 2, 1, 1]},
       "assets": assets}
base = os.path.join(wt, "tests/fixtures/world")
with open(os.path.join(base, "kit_min.json"), "w") as f:
    json.dump(kit, f, indent="\t"); f.write("\n")
def write_rec(path, a, **over):
    r = {"id": a["id"], "status": "PROPOSED",
         "review_state": "blockout - S1 test fixture" if a["placeholder"] else "production - S1 test fixture",
         "export_path": a["glb"][len("res://"):]}
    if "footprint_radius_m" in a:
        r["footprint_radius_m"] = a["footprint_radius_m"]
    r.update(over)
    with open(path, "w") as f:
        json.dump(r, f, indent="\t"); f.write("\n")
for a in assets:
    write_rec(os.path.join(base, "records", a["id"] + ".json"), a)
pill = assets[0]
V = os.path.join(base, "records/variants")
write_rec(os.path.join(V, "wrong_id.json"), pill, id="shell_s_other")
write_rec(os.path.join(V, "wrong_radius.json"), pill, footprint_radius_m=0.7)
write_rec(os.path.join(V, "wrong_export.json"), pill, export_path="assets/export/shell_radiolarian_lens.glb")
write_rec(os.path.join(V, "finished.json"), pill, review_state="production - S1 test fixture")
write_rec(os.path.join(V, "approved.json"), pill, review_state="approved - S1 test fixture", status="APPROVED")
write_rec(os.path.join(V, "finished_proposed.json"), pill, review_state="production - S1 test fixture", status="PROPOSED")
