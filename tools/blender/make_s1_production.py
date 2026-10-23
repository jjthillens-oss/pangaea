"""Finished versions of the endless world's S1 kit (tools/blender/make_s1_kit.py): the same
geometry, ids, node names, colliders and growth children, surfaced and baked.

Each piece is built by the kit's own builder, so it passes the kit's contract checks unchanged. Its
flat materials then become greyscale procedural detail (silica pores and ribs, membrane cells,
glowing granules, fibrous striae), baked with ambient occlusion and a normal map to one texture
set. Every material keeps its name and flat colour, drawn as the baked detail times that colour, so
the hue checks in tests/test_kit_assets.gd still read the flat colour.

Writes the .blend, GLB and record of each piece (review state "production rev 1 - M1, awaiting owner
look review"), then game/data/placement_kit.json, whose placeholder flag follows the review state.
Run: python tools/blender/make_s1_production.py [--only <id>[,<id>...]]
"""
import argparse
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_s1_kit as kit  # noqa: E402
import surfacing as sf  # noqa: E402
import bpy  # noqa: E402

GENERATOR = "tools/blender/make_s1_production.py"
REVIEW_STATE = "production rev 1 - M1, awaiting owner look review"
PROVENANCE = ("Original geometry from tools/blender/make_s1_kit.py, surfaced in Blender by {}: procedural shaders "
              "baked to textures. No outside sources.").format(GENERATOR)
# A shell is under 3 m across, about 200 px tall at the gameplay camera; landmarks and rare pieces
# fill a good part of the screen; the markers are drawn unlit and nearly flat.
TEXTURE = {"shell": 512, "landmark": 1024, "rare": 1024, "marker": 256}
# Markers keep their own UVs: the column's v runs bottom to top for the engine's fade.
KEEP_UV = {"marker_checkpoint_column"}


def _detail(name):
    """A greyscale detail shader for the flat material `name` (M_<Key>): base, roughness, height."""
    sh = sf.Shader(name)
    key = name[2:].lower()
    grain = sh.noise(9.0, 4.0, 0.6)
    if key in ("silica", "frost", "column", "arrow"):
        # Glass: on faces turned up, radial ribs and rings of pores like a diatom's valve; on the
        # sides, fine vertical striae between pore rows.
        radius = sh.vmath("LENGTH", sh.vmath("MULTIPLY", sh.pos, (1.0, 1.0, 0.0)))
        angle = sh.math("ARCTAN2", sh.axis("Y"), sh.axis("X"))
        up = sh.remap(sh.vmath("DOT_PRODUCT", sh.node("ShaderNodeNewGeometry").outputs["Normal"], (0.0, 0.0, 1.0)), 0.45, 0.85)
        ribs = sh.remap(sh.math("SINE", sh.math("MULTIPLY", angle, 32.0)), 0.5, 0.95)
        rings = sh.remap(sh.math("SINE", sh.math("MULTIPLY", radius, 34.0)), 0.2, 0.9)
        striae = sh.math("MULTIPLY", 0.7, sh.remap(sh.math("SINE", sh.math("MULTIPLY", angle, 64.0)), 0.2, 1.0))
        pores = sh.remap(sh.voronoi(26.0, 0.25), 0.17, 0.1)                     # 1 inside a pore
        face = sh.mix(up, striae, sh.math("MAXIMUM", ribs, sh.math("MULTIPLY", rings, 0.55)))
        pores = sh.math("MULTIPLY", pores, sh.math("SUBTRACT", 1.0, sh.math("MULTIPLY", face, 0.8), clamp=True))
        tone = sh.math("ADD", sh.math("MULTIPLY", face, 0.45), sh.math("MULTIPLY", grain, 0.25))
        tone = sh.math("SUBTRACT", tone, sh.math("MULTIPLY", pores, 0.55))
        base = sh.ramp(tone, [(0.0, (0.38, 0.38, 0.38, 1)), (0.3, (0.74, 0.74, 0.74, 1)), (0.6, (1, 1, 1, 1))])
        height = sh.math("SUBTRACT", face, pores)
        rough = sh.remap(face, 0.0, 1.0, 0.45, 0.2)
    elif key in ("deep", "lavender", "husk"):
        # Membrane and casing: soft polygonal cells with darker seams, mottled.
        seams = sh.remap(sh.voronoi(3.0, 0.8, feature="DISTANCE_TO_EDGE"), 0.01, 0.06)   # 0 on a seam
        mottle = sh.noise(3.0, 3.0)
        base = sh.ramp(sh.math("ADD", sh.math("MULTIPLY", seams, 0.5), sh.math("MULTIPLY", mottle, 0.5)),
                       [(0.2, (0.45, 0.45, 0.45, 1)), (0.6, (0.82, 0.82, 0.82, 1)), (1.0, (1, 1, 1, 1))])
        height = sh.math("ADD", seams, sh.math("MULTIPLY", grain, 0.3))
        rough = sh.remap(seams, 0.0, 1.0, 0.6, 0.42)
    elif key in ("core", "amber"):
        # Living granules: bright beads in a darker matrix.
        beads = sh.remap(sh.voronoi(7.0, 0.8), 0.3, 0.12)
        base = sh.ramp(sh.math("ADD", sh.math("MULTIPLY", beads, 0.6), sh.math("MULTIPLY", grain, 0.4)),
                       [(0.1, (0.45, 0.45, 0.45, 1)), (0.5, (0.8, 0.8, 0.8, 1)), (0.9, (1, 1, 1, 1))])
        height = beads
        rough = sh.remap(beads, 0.0, 1.0, 0.5, 0.3)
    else:
        # Stalks (cream): fibres running along the length, with fine cross banding.
        fibres = sh.noise(2.0, 6.0, 0.7, vector=sh.vmath("MULTIPLY", sh.pos, (24.0, 24.0, 2.0)))
        bands = sh.remap(sh.math("SINE", sh.math("MULTIPLY", sh.axis("Z"), 28.0)), 0.7, 1.0)
        base = sh.ramp(sh.math("ADD", sh.math("MULTIPLY", fibres, 0.7), sh.math("MULTIPLY", bands, -0.15)),
                       [(0.2, (0.5, 0.5, 0.5, 1)), (0.55, (0.84, 0.84, 0.84, 1)), (0.9, (1, 1, 1, 1))])
        height = sh.math("SUBTRACT", fibres, sh.math("MULTIPLY", bands, 0.3))
        rough = sh.remap(fibres, 0.0, 1.0, 0.6, 0.45)
    sh.bump(height, 0.6, 0.012)
    return sh.out(base, rough)


def finish(asset_id, kind):
    """Swaps every flat material for its detail shader under the same name, then bakes one
    texture set. Returns the record's `textures`."""
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    hidden = [o for o in objs if o.hide_get() or o.hide_render]
    for o in hidden:
        o.hide_set(False)
        o.hide_render = False
    tints = {}
    for flat in {s.material for o in objs for s in o.material_slots if s.material}:
        bsdf = flat.node_tree.nodes["Principled BSDF"]
        name = flat.name
        color = tuple(bsdf.inputs["Base Color"].default_value[:3])
        strength = bsdf.inputs["Emission Strength"].default_value
        emission = tuple(bsdf.inputs["Emission Color"].default_value[:3]) if strength > 0.0 else None
        flat.name = f"{name}_flat"
        detail = _detail(name)
        for o in objs:
            for slot in o.material_slots:
                if slot.material == flat:
                    slot.material = detail
        bpy.data.materials.remove(flat)
        tints[name] = sf.tint(color=color, emission=emission, emission_strength=strength)
    if asset_id not in KEEP_UV:
        sf.unwrap(objs)
    textures = sf.bake_set(objs, kit.pascal(asset_id), TEXTURE[kind], normal=True, tints=tints)
    for o in hidden:
        o.hide_set(True)
        o.hide_render = True
    return textures


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the finished S1 kit pieces.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    args = parser.parse_args(argv)
    ids = [i for i in args.only.split(",") if i] or list(kit.ASSETS)
    unknown = [i for i in ids if i not in kit.ASSETS]
    if unknown:
        parser.error(f"unknown asset id(s): {', '.join(unknown)}; known: {', '.join(kit.ASSETS)}")
    for asset_id in ids:
        builder, budget = kit.ASSETS[asset_id]
        bc.reset_scene()
        fields = builder()
        fields["textures"] = finish(asset_id, fields["kind"])
        fields["revision"] = 2
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR, provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")
    kit.write_kit()


if __name__ == "__main__":
    main()
    sys.stdout.flush()
