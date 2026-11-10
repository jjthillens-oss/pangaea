"""Aquatic reef dressing trial (PROPOSED, docs/DECISIONS.md "Outside scenery meshes: reef trial").

Brings twelve low-poly reef props from Polyfork (https://polyfork.dev, CC BY 4.0), fetched through
Patch's asset library, into the asset pipeline: each downloaded GLB in
assets/source/third_party/polyfork/ becomes an editable .blend, a GLB in assets/export/ and a record.
Nothing is modelled here. The script joins each prop's pieces into one mesh, turns it to the
project's front (+Y in Blender), names its one vertex-coloured material M_PatchReef and drops any
animation. These are scenery only: no animal comes from an outside mesh.

Run: blender --background --python tools/blender/import_patch_reef.py [-- --only id[,id...]]
Then godot --headless --import, twice (the first pass writes the .glb.import files, which
map_materials() below then points at assets/export/M_PatchReef.tres).
"""

import argparse
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402

GENERATOR = "tools/blender/import_patch_reef.py"
REVIEW_STATE = "outside mesh trial - aquatic reef, awaiting owner look review"
SOURCE_DIR = "assets/source/third_party/polyfork"
MATERIAL = "M_PatchReef"
ENGINE_MATERIAL = "res://assets/export/M_PatchReef.tres"
LICENSE = "CC BY 4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
RETRIEVED = "2026-11-10"
# Twice the largest source mesh, so a wrong file fails loudly.
BUDGET = 2000

# asset id -> (Polyfork slug, title, what it is in the reef)
ASSETS = {
    "reef_brain_coral": ("brain-coral-head-7db21a", "Brain Coral Head", "a low brain coral dome"),
    "reef_staghorn_coral": ("staghorn-coral-422d23", "Staghorn Coral", "a branching staghorn coral"),
    "reef_table_coral": ("table-coral-193fa6", "Table Coral", "a flat table coral on a stalk"),
    "reef_pillar_coral": ("pillar-coral-colony-9336e9", "Pillar Coral Colony", "a cluster of pillar corals"),
    "reef_soft_coral": ("soft-coral-tree-450af0", "Soft Coral Tree", "a soft coral tree"),
    "reef_sea_fan": ("sea-fan-bafd49", "Sea Fan", "a sea fan"),
    "reef_seagrass": ("seagrass-tuft-862cc5", "Seagrass Tuft", "a tuft of seagrass"),
    "reef_algae_frond": ("broad-algae-frond-88a644", "Broad Algae Frond", "a broad-leaved algae"),
    "reef_tube_sponge": ("tube-sponge-df576b", "Tube Sponge", "a tube sponge cluster"),
    "reef_barrel_sponge": ("barrel-sponge-ab460c", "Barrel Sponge", "a barrel sponge"),
    "reef_boulder": ("encrusted-reef-boulder-972d95", "Encrusted Reef Boulder", "a reef boulder with growth on it"),
    "reef_bubble_vent": ("seabed-bubble-vent-cfa541", "Seabed Bubble Vent", "a sea-bed vent with a still bubble column"),
}


def build(asset_id):
    slug, title, what = ASSETS[asset_id]
    source = f"{SOURCE_DIR}/{slug}.glb"
    bc.reset_scene()
    bpy.ops.import_scene.gltf(filepath=os.path.join(bc.ROOT, source))
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"{asset_id}: {source} holds no mesh")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.animation_data_clear()
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    # Keep each piece where the file put it, then make one mesh of them.
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    prop = bpy.context.view_layer.objects.active
    for obj in list(bpy.context.scene.objects):
        if obj != prop:
            bpy.data.objects.remove(obj, do_unlink=True)
    prop.name = "".join(part.capitalize() for part in asset_id.split("_"))
    prop.data.name = prop.name
    # glTF's front is +Z, which Blender's importer turns to -Y; the project's front is +Y.
    prop.rotation_euler = (0.0, 0.0, math.pi)
    bpy.ops.object.select_all(action="DESELECT")
    prop.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    colors = prop.data.color_attributes
    if not colors:
        raise RuntimeError(f"{asset_id}: {source} has no vertex colours")
    attribute = colors[0].name
    colors.active_color = colors[0]
    colors.render_color_index = 0
    prop.data.materials.clear()
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    mat = bpy.data.materials.new(MATERIAL)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.85
    node = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    node.layer_name = attribute
    mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    prop.data.materials.append(mat)
    for poly in prop.data.polygons:
        poly.material_index = 0
    return bc.export(asset_id, BUDGET, {
        "purpose": f"Aquatic stage reef dressing (PROPOSED trial): {what}. Scenery only; it has no gameplay role.",
        "category": "environment",
        "kind": "dressing",
        "vertex_colors_attribute": attribute,
        "pivot": "bottom centre, on the sea floor (Godot y = 0)",
        "engine_material": ENGINE_MATERIAL,
        "license": f"{LICENSE} (attribution required; credited in CREDITS.md)",
        "third_party_sources": [{
            "name": title,
            "author": "Polyfork (Lucas Martinic)",
            "url": f"https://polyfork.dev/asset/{slug}",
            "retrieved_through": f"Patch asset library (patch.gg), id polyfork:{slug}",
            "retrieved": RETRIEVED,
            "path": source,
            "license": LICENSE,
            "license_url": LICENSE_URL,
            "credit": f"{title} by Polyfork (https://polyfork.dev/asset/{slug}), CC BY 4.0",
            "modified": "pieces joined into one mesh, turned 180 degrees about the up axis, the material renamed "
                        "M_PatchReef, animation removed; the shape and vertex colours are unchanged",
        }],
    }, review_state=REVIEW_STATE, generator=GENERATOR, provenance=(
        f"An outside mesh: {title} by Polyfork (CC BY 4.0), a model its author generates from code, taken unchanged "
        f"in shape and colour from {source}. {GENERATOR} only joins, turns and renames it. Not authored in-house."))


def map_materials():
    """Points each prop's imported material at the shared engine material (Godot's glTF import leaves vertex
    colours unused). Run after Godot has written the .glb.import files."""
    mapping = ('_subresources={\n"materials": {\n"%s": {\n"use_external/enabled": true,\n'
               '"use_external/fallback_path": "%s",\n"use_external/path": "%s"\n}\n}\n}' % (MATERIAL, ENGINE_MATERIAL, ENGINE_MATERIAL))
    mapped = 0
    for asset_id in ASSETS:
        path = os.path.join(bc.ROOT, "assets", "export", f"{asset_id}.glb.import")
        if not os.path.exists(path):
            continue
        with open(path, newline="") as f:
            text = f.read()
        new = re.sub(r"_subresources=\{.*?\n\}(?=\n|$)|_subresources=\{\}", lambda _m: mapping, text, count=1, flags=re.S)
        if new != text:
            with open(path, "w", newline="") as f:
                f.write(new)
        mapped += 1
    return mapped


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--map-only", action="store_true", help="only map the .glb.import materials")
    args = parser.parse_args(argv)
    if not args.map_only:
        ids = [i for i in args.only.split(",") if i] or list(ASSETS)
        for asset_id in ids:
            record = build(asset_id)
            print(f"{asset_id}: {record['triangles']} triangles, {record['dimensions_m']}")
    print(f"mapped {map_materials()} .glb.import files to {ENGINE_MATERIAL}")


if __name__ == "__main__":
    main()
