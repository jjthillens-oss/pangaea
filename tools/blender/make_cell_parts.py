"""The cell parts the M1 editor lists without a model yet (game/data/part_catalog.json): cilia, the shell
plate and the toxin gland, in finished art for S4's editor. PROPOSED.

They follow the M1 cell parts' contract (make_m1_blockouts._part_fields, tests/test_assets.gd PART_IDS):
the origin is the attachment point on the body surface, Blender +Y (Godot -Z) points outward, and a part
sinks at most PART_EMBED (0.03 m) behind its origin. Each is finished like the M1 parts: procedural
greyscale detail baked to one texture set (albedo detail with AO, ORM, normal), every material keeping
its name and flat colour. Colours keep 25 degrees of LAB hue from the food green and the threat pink.

- part_cilia: a pad of twelve short hairs in three rows. Shape key Beat (rests at 0) bends them in a
  power stroke toward the tail, each row a little later, for the engine to drive back and forth.
- part_shell_plate: a domed silica scute with radial ribs and growth rings; it faces outward.
- part_toxin_gland: a translucent teal sac of dark glowing granules on a short neck, with a nozzle.

The cell stage is microscopic: no bone, horn or teeth here.
Run: python tools/blender/make_cell_parts.py [--only <id>[,<id>...]]
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_m1_blockouts as mb  # noqa: E402
import make_m1_production as mp  # noqa: E402
import surfacing as sf  # noqa: E402
from mathutils import Vector  # noqa: E402

GENERATOR = "tools/blender/make_cell_parts.py"
REVIEW_STATE = mp.REVIEW_STATE
PROVENANCE = "Authored procedurally in Blender by tools/blender/make_cell_parts.py; no external or generated meshes. Textures baked in Blender from procedural shaders."
EMBED = mb.PART_EMBED
TOLERANCE = mp.PART_TOLERANCE


def _bake(objs, texture, tints, tolerance=TOLERANCE):
    before = after = 0
    highs = {}
    for obj in objs:
        b, a, high = sf.reduce(obj, tolerance)
        before, after = before + b, after + a
        if a == b:
            sf.drop_highs([high])
            high = None
        highs[obj.name] = high
    sf.unwrap(objs)
    textures = sf.bake_set(objs, texture, mp.PART_TEXTURE, highs=highs, tints=tints)
    sf.drop_highs(highs.values())
    return {"textures": textures,
            "reduction": {"method": "Blender collapse decimation within a surface tolerance; full-detail shading baked to the normal map",
                          "tolerance_m": tolerance, "triangles_before": before, "triangles_after": after}}


def _fields(part_type, purpose, baked, extra=None):
    fields = mb._part_fields(part_type, purpose)
    fields.update({"revision": 1, **baked, **(extra or {})})
    return fields


def _tint(hex_color, emission=None, strength=0.0):
    if emission is None:
        return sf.tint(mp._lin(hex_color))
    return sf.tint(color=mp._lin(hex_color), emission=mp._lin(emission), emission_strength=strength)


# --- Cilia ------------------------------------------------------------------------------------

CILIA_ROWS = (-0.045, 0.0, 0.045)      # along the body (Blender Z here is across the pad)
CILIA_PER_ROW = 4
CILIA_LEN = 0.13
CILIA_R = 0.0085


def build_cilia():
    pad = sf.Shader("M_CiliaPadProc")
    cells = pad.remap(pad.voronoi(160.0, 0.6), 0.2, 0.06)
    pad.bump(pad.math("SUBTRACT", 0.0, cells), 0.25, 0.0008)
    pad_mat = pad.out(mp._grey(pad, pad.math("SUBTRACT", 1.0, pad.math("MULTIPLY", cells, 0.3)), 0.8), 0.55)
    hair = sf.Shader("M_CiliaHairProc")
    fibre = hair.noise(120.0, 2.0, vector=mp._stretched(hair, (6.0, 0.4, 6.0)))
    hair.bump(fibre, 0.15, 0.0005)
    hair_mat = hair.out(mp._grey(hair, hair.remap(fibre, 0.3, 0.7), 0.85), 0.4)
    # The pad: a low lens the hairs root in.
    profile = [(-EMBED, 0.0), (-EMBED, 0.085), (-0.01, 0.088), (0.006, 0.075), (0.014, 0.045), (0.017, 0.0)]
    verts, faces, _ = bc.revolve(profile, 28)
    face_materials = [0] * len(faces)
    hair_tips = []
    for r, z in enumerate(CILIA_ROWS):
        for k in range(CILIA_PER_ROW):
            x = (k - (CILIA_PER_ROW - 1) / 2) * 0.034 + (0.008 if r % 2 else -0.008)
            base = Vector((x, 0.004, z))
            lean = Vector((0.0, 1.0, -0.12)).normalized()
            path = [base + lean * (CILIA_LEN * t) + Vector((0.0, 0.0, -0.012 * t * t)) for t in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0)]
            hv, hf = mp._sweep(path, lambda i, a: CILIA_R * (1.0 - 0.55 * i / 5) if i < 5 else 0.0, 7)
            bc.append(verts, faces, hv, hf)
            face_materials += [1] * len(hf)
            hair_tips.append(path[-1])
    cilia = bc.mesh_object("Cilia", verts, faces, [pad_mat, hair_mat], face_materials)
    pad_mat.name, hair_mat.name = "M_CiliaPad", "M_CiliaHair"
    baked = _bake([cilia], "PartCilia", {"M_CiliaPad": _tint("#9FC3D8"), "M_CiliaHair": _tint("#D7E7EE")})

    # Beat: a power stroke toward the tail (Blender -Z on the part, which sits on the body's side), stronger
    # toward the tips, each row a little later so a driven weight reads as a travelling wave.
    cilia.shape_key_add(name="Basis", from_mix=False)
    beat = cilia.shape_key_add(name="Beat", from_mix=False)
    beat.value = 0.0
    for i, v in enumerate(cilia.data.vertices):
        co = v.co.copy()
        h = max(0.0, co.y - 0.012) / CILIA_LEN
        row_lag = 1.0 - 0.25 * ((co.z - CILIA_ROWS[0]) / (CILIA_ROWS[-1] - CILIA_ROWS[0]) if co.y > 0.012 else 0.0)
        bend = math.radians(55.0) * h * row_lag
        dy, dz = co.y - 0.012, 0.0
        if co.y > 0.012:
            co.y = 0.012 + dy * math.cos(bend)
            co.z = co.z - dy * math.sin(bend)
        beat.data[i].co = co
    return _fields("cilia", "Cell cilia part (S4 editor): a lens-shaped pad of twelve short hairs in three rows; shape key Beat bends them in a power stroke toward the tail.",
                   baked, {"shape_keys": {"Beat": "power stroke toward the tail, rows lagging; rests at 0, the engine drives it 0 to 1 and back"},
                           "hairs": len(hair_tips), "hair_length_m": CILIA_LEN})


# --- Shell plate ------------------------------------------------------------------------------

PLATE_R = 0.19
PLATE_TOP = 0.14


def build_shell_plate():
    sh = sf.Shader("M_ShellPlateProc")
    radius = sh.vmath("LENGTH", sh.vmath("MULTIPLY", sh.pos, (1.0, 0.0, 1.0)))
    angle = sh.math("ARCTAN2", sh.axis("Z"), sh.axis("X"))
    rings = sh.remap(sh.math("SINE", sh.math("MULTIPLY", radius, 168.0)), 0.3, 1.0)
    ribs = sh.remap(sh.math("ABSOLUTE", sh.math("COSINE", sh.math("MULTIPLY", angle, 3.0))), 0.9, 1.0)
    pores = sh.remap(sh.voronoi(220.0, 0.4), 0.12, 0.06)
    h = sh.math("SUBTRACT", sh.math("ADD", sh.math("MULTIPLY", rings, 0.35), sh.math("MULTIPLY", ribs, 0.6)), sh.math("MULTIPLY", pores, 0.4))
    sh.bump(h, 0.45, 0.0015)
    plate_mat = sh.out(mp._grey(sh, sh.math("ADD", 0.35, sh.math("MULTIPLY", h, 0.65)), 0.55), 0.3)
    edge = sf.Shader("M_ShellPlateEdgeProc")
    grain = edge.noise(90.0, 3.0)
    edge.bump(grain, 0.2, 0.001)
    edge_mat = edge.out(mp._grey(edge, edge.remap(grain, 0.3, 0.7), 0.8), 0.45)
    # A domed scute: rolled rim, then a dome to a low boss. Six raised ribs run from the boss to the rim.
    steps = 22
    profile = [(-EMBED, 0.0), (-EMBED, PLATE_R * 0.9), (-0.012, PLATE_R), (0.004, PLATE_R * 1.02), (0.018, PLATE_R * 0.98)]
    for i in range(1, steps + 1):
        t = i / steps
        r = PLATE_R * 0.97 * (1.0 - t)
        profile.append((0.018 + (PLATE_TOP - 0.018) * (1.0 - (r / (PLATE_R * 0.97)) ** 2) ** 0.55, r))   # a spherical cap
    profile[-1] = (PLATE_TOP, 0.0)
    verts, faces, bands = bc.revolve(profile, 60)
    shaped = []
    for x, y, z in verts:
        if y > 0.02:
            a = math.atan2(z, x)
            r = math.hypot(x, z)
            rib = abs(math.cos(3.0 * a)) ** 10                       # six ribs from the crown to the rim
            k = min(1.0, max(0.0, (r / PLATE_R - 0.4) / 0.2))
            y += 0.02 * rib * k * (1.0 - r / PLATE_R)
        shaped.append((x, y, z))
    face_materials = [0 if b < 4 else 1 for b in bands]
    plate = bc.mesh_object("ShellPlate", shaped, faces, [edge_mat, plate_mat], face_materials)
    edge_mat.name, plate_mat.name = "M_ShellPlateEdge", "M_ShellPlate"
    baked = _bake([plate], "PartShellPlate", {"M_ShellPlateEdge": _tint("#B8A27E"), "M_ShellPlate": _tint("#E6D9B8")})
    return _fields("shell_plate", "Cell shell plate part (S4 editor, band 1): a domed silica scute with six radial ribs, growth rings and fine pores on a rolled rim; it faces outward and blocks stings and rams on its side.",
                   baked, {"plate_radius_m": PLATE_R, "dome_height_m": PLATE_TOP})


# --- Toxin gland ------------------------------------------------------------------------------

SAC_R = 0.075
SAC_Y = 0.075
NOZZLE_TIP = 0.215


def build_toxin_gland():
    objs = []
    # Sac: a squashed translucent bulb with dark granules that glow teal.
    sac_sh = sf.Shader("M_ToxinSacProc")
    gran = sac_sh.remap(sac_sh.voronoi(70.0, 0.9), 0.32, 0.14)
    murk = sac_sh.noise(25.0, 3.0)
    tone = sac_sh.math("ADD", sac_sh.math("MULTIPLY", murk, 0.4), 0.55)
    base = sac_sh.mix(gran, (0.85, 0.85, 0.85, 1.0), (0.25, 0.25, 0.25, 1.0))
    base = sac_sh.mix(sac_sh.math("MULTIPLY", tone, 0.3), base, (1.0, 1.0, 1.0, 1.0))
    sac_sh.bump(sac_sh.math("SUBTRACT", murk, gran), 0.25, 0.001)
    sac_mat = sac_sh.out(base, 0.15, sac_sh.mix(gran, (0, 0, 0, 1), (1, 1, 1, 1)), 0.6)
    unit, ifaces = bc.icosphere(4)
    sac_v = []
    for co in unit:
        n = Vector(co).normalized()
        p = Vector((n.x * SAC_R, SAC_Y + n.y * SAC_R * 0.85, n.z * SAC_R))
        p.y = max(p.y, -EMBED + 0.004)
        sac_v.append(tuple(p))
    sac = bc.mesh_object("ToxinGland", sac_v, ifaces, [sac_mat])
    sac_mat.name = "M_ToxinSac"
    objs.append(sac)
    # Neck and nozzle: a fleshy collar narrowing to a puckered pore.
    neck_sh = sf.Shader("M_ToxinNozzleProc")
    rings = neck_sh.remap(neck_sh.math("SINE", neck_sh.math("MULTIPLY", neck_sh.axis("Y"), 520.0)), 0.5, 1.0)
    neck_sh.bump(rings, 0.3, 0.0008)
    neck_mat = neck_sh.out(mp._grey(neck_sh, neck_sh.math("SUBTRACT", 1.0, neck_sh.math("MULTIPLY", rings, 0.25)), 0.8), 0.5)
    y0 = SAC_Y + SAC_R * 0.6
    profile = [(y0, 0.0), (y0, 0.034), (y0 + 0.03, 0.03), (y0 + 0.06, 0.02), (NOZZLE_TIP - 0.012, 0.016),
               (NOZZLE_TIP - 0.004, 0.019), (NOZZLE_TIP, 0.012), (NOZZLE_TIP - 0.008, 0.004), (NOZZLE_TIP - 0.012, 0.0)]
    nv, nf, _ = bc.revolve(profile, 20)
    nozzle = bc.mesh_object("Nozzle", nv, nf, [neck_mat], parent=sac)
    neck_mat.name = "M_ToxinNozzle"
    objs.append(nozzle)
    baked = _bake(objs, "PartToxinGland", {"M_ToxinSac": _tint("#5FC7BE", emission="#3FE0CF", strength=0.6),
                                            "M_ToxinNozzle": _tint("#7FA6A8")})
    return _fields("toxin_gland", "Cell toxin gland part (S4 editor): a translucent teal sac of dark granules that glow, on a ringed fleshy neck ending in a puckered nozzle that faces outward.",
                   baked, {"nozzle_tip_m": NOZZLE_TIP, "sac_radius_m": SAC_R})


# asset id -> (builder, triangle budget): the M1 part budget (tests/test_assets.gd).
ASSETS = {
    "part_cilia": (build_cilia, 1500),
    "part_shell_plate": (build_shell_plate, 1500),
    "part_toxin_gland": (build_toxin_gland, 1500),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the S4 cell parts.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    args = parser.parse_args(argv)
    ids = [i for i in args.only.split(",") if i] or list(ASSETS)
    unknown = [i for i in ids if i not in ASSETS]
    if unknown:
        parser.error(f"unknown asset id(s): {', '.join(unknown)}; known: {', '.join(ASSETS)}")
    for asset_id in ids:
        builder, budget = ASSETS[asset_id]
        bc.reset_scene()
        fields = builder()
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR, provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
