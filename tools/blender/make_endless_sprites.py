"""The endless world's 2D art and engine materials for S2 (docs/endless-cell-plan.md, sections B.8
and I), rendered in Blender from the finished models:

- Near ghosts: pre-blurred billboards of the next sizes' species, seen from the gameplay camera's
  pitch, in one cool neutral ghost colour (never the food or threat colour, B.8). 512 px.
    assets/export/ambience/T_Ghost_<species>.png
- Haze: small soft glitter silhouettes of older sizes' foods and creatures, white so the engine
  tints and fades them as they sink below the plane. 128 px.
    assets/export/ambience/T_Haze_<id>.png
- The Lurker's silt trail: a soft, grainy streak that tiles along its length. 256 x 64 px.
    assets/export/ambience/T_SiltTrail.png
- Engine materials for creature bodies in two roles, drawn as a material_override:
    assets/export/M_Morsel.tres         a morsel: the body's own colours, warmed, no threat colour
    assets/export/M_RemnantLimp.tres    a brainless remnant: the body's colours greyed and cooled

The textures are sRGB with straight alpha. Their sources are the models' own .blend files; this
script and assets/records/sprites/endless_sprites.json record how each was made.
Run: python tools/blender/make_endless_sprites.py [--only ghosts,haze,silt,materials]
"""
import argparse
import json
import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402
import make_ambience_backdrops as ab  # noqa: E402

OUT = os.path.join(ld.ROOT, "assets", "export", "ambience")
SOURCES = os.path.join(ld.ROOT, "assets", "source", "blender")
RECORD = os.path.join(ld.ROOT, "assets", "records", "sprites", "endless_sprites.json")
GENERATOR = "tools/blender/make_endless_sprites.py"

GHOSTS = ["creature_lurker_body", "creature_elder_rammer_body", "creature_veil_body", "creature_warden_body",
          "creature_deep_lurker_body", "creature_elder_warden_body",
          # Size 5 and 6, from rough render-only models (tools/blender/make_endless_extras.py).
          "ghost_engulfer", "ghost_lancer"]
GHOST_COLOR = "#8E9CC8"       # cool lavender-blue: far from the food (h 114) and threat (h 11) hues
GHOST_SHADE = "#5A6796"
GHOST_SIZE, GHOST_SIGMA = 512, 6.0
CAMERA_PITCH = 55.0           # the gameplay camera's pitch (endless plan, layout.camera)
HAZE = ["plankton", "carrion", "algae_ball", "glass_flake", "bead_cluster", "creature_ambush_body", "creature_rammer_body",
        "creature_lurker_body", "creature_elder_rammer_body", "creature_warden_body", "creature_veil_body"]
HAZE_SIZE, HAZE_SIGMA = 128, 1.2


def _species(asset_id):
    return asset_id.replace("creature_", "").replace("_body", "").replace("ghost_", "")


def _open(asset_id):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(SOURCES, f"{asset_id}.blend"))
    for obj in list(bpy.context.scene.objects):
        if obj.type not in ("MESH", "EMPTY"):
            bpy.data.objects.remove(obj)
    # Growth children stay hidden; every other mesh is shown.
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("Growth_")]
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o.name.startswith("Growth_"):
            o.hide_render = True
    return meshes


def _paint(meshes, mat):
    for o in meshes:
        o.data.materials.clear()
        o.data.materials.append(mat)


def _extent(meshes):
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    return max(max(abs(p.x) for p in pts), max(abs(p.y) for p in pts), max(p.z for p in pts) - min(p.z for p in pts)) * 2.0


def _camera(extent, pitch, size):
    ab.SIZE = size
    ab._stage(extent)
    cam = bpy.context.scene.camera
    # Look down at the gameplay pitch from behind (Blender -Y is behind the body; it faces +Y).
    p = math.radians(pitch)
    cam.location = (0.0, -30.0 * math.cos(p), 30.0 * math.sin(p))
    cam.rotation_euler = (math.radians(90.0 - pitch), 0.0, 0.0)


def _render(size):
    tmp = os.path.join(OUT, "_render.png")
    bpy.context.scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)
    bpy.data.images.remove(img)
    os.remove(tmp)
    return px


def _save(name, px):
    h, w = px.shape[:2]
    out = bpy.data.images.new(name, w, h, alpha=True)
    out.pixels.foreach_set(np.clip(px, 0.0, 1.0).ravel())
    out.filepath_raw = os.path.join(OUT, f"{name}.png")
    out.file_format = "PNG"
    out.save()
    print("saved", out.filepath_raw)
    return {"name": name, "path": f"assets/export/ambience/{name}.png", "size": [w, h]}


def ghosts():
    out = []
    for asset_id in GHOSTS:
        meshes = _open(asset_id)
        mat = ld.principled("M_Ghost", ld.color(GHOST_COLOR), 0.6)
        _paint(meshes, mat)
        _camera(_extent(meshes) * 1.1, CAMERA_PITCH, GHOST_SIZE)
        world = bpy.context.scene.world.node_tree.nodes["Background"]
        world.inputs["Color"].default_value = ld.color(GHOST_SHADE)
        px = _render(GHOST_SIZE)
        entry = _save(f"T_Ghost_{_species(asset_id)}", ab._blur(px, GHOST_SIGMA))
        entry.update({"source": f"assets/source/blender/{asset_id}.blend", "kind": "near ghost"})
        out.append(entry)
    return out


def haze():
    out = []
    for asset_id in HAZE:
        meshes = _open(asset_id)
        mat = bpy.data.materials.new("M_Haze")
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        nodes.clear()
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        res = nodes.new("ShaderNodeOutputMaterial")
        mat.node_tree.links.new(emit.outputs["Emission"], res.inputs["Surface"])
        _paint(meshes, mat)
        _camera(_extent(meshes) * 1.2, 90.0, HAZE_SIZE)
        px = _render(HAZE_SIZE)
        # Glitter: the silhouette broken into soft sparkles, brighter at a few points.
        rng = np.random.default_rng(abs(hash(asset_id)) % (2 ** 32))
        sparkle = 0.45 + 0.55 * rng.random((HAZE_SIZE, HAZE_SIZE)) ** 3
        px[..., 3] *= sparkle
        px[..., :3] = 1.0
        entry = _save(f"T_Haze_{_species(asset_id)}", ab._blur(px, HAZE_SIGMA))
        entry.update({"source": f"assets/source/blender/{asset_id}.blend", "kind": "haze"})
        out.append(entry)
    return out


def silt():
    """A soft streak of silt grains, denser along its middle, tiling along x."""
    w, h = 256, 64
    rng = np.random.default_rng(7)
    y = np.linspace(-1.0, 1.0, h)[:, None]
    band = np.exp(-(y * y) / (2 * 0.32 ** 2)) * np.ones((h, w))
    grains = np.zeros((h, w))
    for _ in range(900):
        gx, gy = rng.integers(0, w), int(np.clip(rng.normal(h / 2, h / 6), 0, h - 1))
        grains[gy, gx] = rng.uniform(0.5, 1.0)
    px = np.zeros((h, w, 4), dtype=np.float32)
    px[..., 0], px[..., 1], px[..., 2] = 0.78, 0.74, 0.82     # pale silt, faintly violet, under any tint
    px[..., 3] = 0.35 * band
    px = ab._blur(px, 3.0)
    px[..., 3] = np.clip(px[..., 3] + 0.6 * grains * band, 0.0, 1.0)
    px = ab._blur(px, 0.8)
    # Wrap the ends so it tiles: cross-fade the last 16 columns into the first.
    fade = np.linspace(0.0, 1.0, 16)[None, :, None]
    px[:, :16] = px[:, :16] * fade + px[:, -16:] * (1 - fade)
    entry = _save("T_SiltTrail", px)
    entry.update({"source": GENERATOR, "kind": "trail texture, tiles along x"})
    return [entry]


MORSEL = """[gd_resource type="StandardMaterial3D" format=3]

; A creature body drawn as a morsel (docs/endless-cell-plan.md B.4, I): the body's own vertex colours,
; warmed a little so it reads as food under the green rim, with no threat colour, because as a
; material_override it replaces every surface, crest points included. Written by {gen}.

[resource]
resource_name = "M_Morsel"
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
albedo_color = Color(1, 0.88, 0.74, 1)
roughness = 0.55
"""

LIMP = """[gd_resource type="StandardMaterial3D" format=3]

; A brainless remnant after a growth (docs/endless-cell-plan.md B.4, I): the body's vertex colours
; greyed and cooled so it reads as spent, with no threat colour (a material_override replaces every
; surface). Written by {gen}.

[resource]
resource_name = "M_RemnantLimp"
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
albedo_color = Color(0.6, 0.64, 0.74, 1)
roughness = 0.8
"""


def materials():
    out = []
    for name, text in (("M_Morsel", MORSEL), ("M_RemnantLimp", LIMP)):
        path = os.path.join(ld.ROOT, "assets", "export", f"{name}.tres")
        with open(path, "w") as f:
            f.write(text.format(gen=GENERATOR))
        out.append({"name": name, "path": f"assets/export/{name}.tres", "kind": "material_override"})
        print("wrote", path)
    return out


def bloom():
    """Recorded here; drawn by tools/blender/make_endless_extras.py."""
    return [{"name": "T_BloomTint", "path": "assets/export/ambience/T_BloomTint.png", "size": [256, 256],
             "kind": "bloom tint: a soft round gradient, white to clear, that the engine tints #E8D27A over a blooming meadow",
             "source": "tools/blender/make_endless_extras.py"}]


PARTS = {"ghosts": ghosts, "haze": haze, "silt": silt, "materials": materials, "bloom": bloom}


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="", help="comma-separated parts: " + ",".join(PARTS))
    args = parser.parse_args(argv)
    parts = [p for p in args.only.split(",") if p] or list(PARTS)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.dirname(RECORD), exist_ok=True)
    record = {}
    if os.path.exists(RECORD):
        with open(RECORD) as f:
            record = json.load(f)
    record.update({
        "id": "endless_sprites", "owner": "Joshua Jake", "status": "PROPOSED",
        "review_state": "production rev 1 - M1, awaiting owner look review",
        "purpose": "S2 2D art and engine materials for the endless world: near-ghost billboards, haze glitter, the Lurker's silt trail, and the morsel and remnant material overrides.",
        "generator_script": GENERATOR,
        "provenance": "Rendered in Blender (Cycles) from the listed models' own .blend files and blurred by the script; the trail and materials are generated by the script. No outside sources.",
        "rules": "No food or threat hue (ghosts are one cool lavender-blue; haze and the trail are near-white for the engine to tint); pre-blurred, no depth of field needed.",
    })
    items = {i["name"]: i for i in record.get("items", [])}
    for part in parts:
        for item in PARTS[part]():
            items[item["name"]] = item
    record["items"] = sorted(items.values(), key=lambda i: i["name"])
    with open(RECORD, "w") as f:
        json.dump(record, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
