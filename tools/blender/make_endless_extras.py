"""The endless world's S3 extras (docs/endless-cell-plan.md, section I), in Blender:

- veil_threads: the stinger veil's thread rig. Twelve tapered threads trailing from a ring the size
  of the veil's rim, lying in the swim plane (the hazard is gameplay, so it may sit there), built at
  unit length so the engine scales it to the danger area. No bones (the creature is microscopic):
  UV v runs 0 at the rim to 1 at each tip, and COLOR_0's red holds the same value, so a vertex shader
  can sway the threads more toward their tips. Two engine materials, so the area reads at 14 tm in
  either state: assets/export/M_VeilThreadInk.tres (threat ink, glowing) and M_VeilThreadNeutral.tres.
- cradle_ring: the dressing round the old pool at band 1 ("Your lineage began here"): a low glass
  rim 14 bu across with a frosted lip, sunk below the decor-free band (top at -1.6 bu) so it frames
  the shrunken pool's shells from beneath.
- home_beacon: a giant glass lattice tower for the background over home, seen far below the plane:
  a tall radiolarian spire on a broad foot, top at -12 bu.
- Ghost models: rough Blender models of one size-5 and one size-6 species, the engulfer and the
  lancer, kept as .blend sources for make_endless_sprites.py's near-ghost renders (render-only, no GLB).
- T_BloomTint.png: a soft round gradient (white to clear) the engine tints with the bloom colour in
  the record over the meadow that is blooming.

Run: python tools/blender/make_endless_extras.py [--only <id>[,<id>...]]
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
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

GENERATOR = "tools/blender/make_endless_extras.py"
REVIEW_STATE = p1.REVIEW_STATE
# The thread rig has no baked textures: the engine draws it with its own two materials.
ENGINE_DRAWN_REVIEW = "production rev 1 - M1, engine-drawn materials, awaiting owner look review"
PROVENANCE = "Authored procedurally in Blender by tools/blender/make_endless_extras.py; no external or generated meshes. Textures baked in Blender from procedural shaders."
THREAT_INK = "#D9466B"
THREAD_NEUTRAL = "#C8BEE0"
BLOOM_TINT = "#E8D27A"    # warm gold: 26 degrees of LAB hue from the food green, never the food colour itself


def build_veil_threads():
    """Twelve threads trailing from the rim toward Blender -Y (behind the veil), fanning out."""
    mat = bc.material("M_VeilThread", (0.78, 0.74, 0.88), 0.4)
    verts, faces, uvs, weights = [], [], [], []
    count, steps, sides = 12, 14, 4
    for t_i in range(count):
        a = t_i * math.tau / count
        root = Vector((0.46 * math.cos(a), 0.5 * math.sin(a), 0.0))
        fan = Vector((0.35 * math.cos(a), -1.0, 0.0)).normalized()
        start = len(verts)
        for s in range(steps + 1):
            t = s / steps
            wave = 0.06 * math.sin(t * 9.0 + a * 3.0) * t
            c = root + fan * t + Vector((wave, 0.0, 0.0))
            r = 0.012 * (1.0 - 0.8 * t)
            for j in range(sides):
                ang = math.tau * j / sides
                verts.append(c + Vector((r * math.cos(ang), 0.0, r * math.sin(ang))))
                uvs.append((j / sides, t))
                weights.append(t)
        for s in range(steps):
            for j in range(sides):
                n = (j + 1) % sides
                faces.append((start + s * sides + j, start + s * sides + n, start + (s + 1) * sides + n, start + (s + 1) * sides + j))
    obj = bc.mesh_object("VeilThreads", verts, faces, [mat], smooth=True)
    uv = obj.data.uv_layers.new(name="UVMap")
    for loop in obj.data.loops:
        uv.data[loop.index].uv = uvs[loop.vertex_index]
    col = obj.data.color_attributes.new("ThreadWeight", "FLOAT_COLOR", "POINT")
    for i, w in enumerate(weights):
        col.data[i].color = (w, w, w, 1.0)
    for name, text in (("M_VeilThreadInk", THREAD_INK_TRES), ("M_VeilThreadNeutral", THREAD_NEUTRAL_TRES)):
        with open(os.path.join(bc.ROOT, "assets", "export", f"{name}.tres"), "w") as f:
            f.write(text)
    return {
        "purpose": "S3 stinger veil thread rig: twelve tapered threads trailing from the veil's rim in the swim plane, unit length, drawn with M_VeilThreadInk while they sting and M_VeilThreadNeutral when they no longer can.",
        "category": "part", "kind": "rig",
        "pivot": "centre of the veil on the swim plane; threads trail toward Godot +Z (behind the veil, which faces -Z)",
        "length_m": 1.0,
        "rig": "no bones: UV v and COLOR_0 red run 0 at the rim to 1 at each tip, for a vertex shader's sway",
        "vertex_colors_attribute": "ThreadWeight",
        "dependencies": ["assets/export/M_VeilThreadInk.tres", "assets/export/M_VeilThreadNeutral.tres"],
    }


THREAD_INK_TRES = """[gd_resource type="StandardMaterial3D" format=3]

; The stinger veil's threads while they can sting (threat ink #D9466B, glowing so the danger area
; reads at 14 tm). Written by tools/blender/make_endless_extras.py.

[resource]
resource_name = "M_VeilThreadInk"
albedo_color = Color(0.851, 0.275, 0.42, 1)
emission_enabled = true
emission = Color(0.851, 0.275, 0.42, 1)
emission_energy_multiplier = 0.8
roughness = 0.4
"""

THREAD_NEUTRAL_TRES = """[gd_resource type="StandardMaterial3D" format=3]

; The stinger veil's threads once they can no longer sting: a pale neutral lilac, still drawn so the
; area stays readable. Written by tools/blender/make_endless_extras.py.

[resource]
resource_name = "M_VeilThreadNeutral"
albedo_color = Color(0.784, 0.745, 0.878, 1)
emission_enabled = true
emission = Color(0.784, 0.745, 0.878, 1)
emission_energy_multiplier = 0.25
roughness = 0.5
"""


# Pieces that lie wholly below the swim plane keep their albedo luminance at or under this (s3-view
# A3V-2), so the engine draws them as authored instead of dimming them.
BELOW_PLANE_LUMA = 0.38


def _below_plane_mats():
    """The kit's flat materials, each scaled down (hue kept) to linear luminance BELOW_PLANE_LUMA at most."""
    m = k._mats()
    for mat in m.values():
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        c = bsdf.inputs["Base Color"].default_value
        luma = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        if luma > BELOW_PLANE_LUMA:
            f = BELOW_PLANE_LUMA / luma
            bsdf.inputs["Base Color"].default_value = (c[0] * f, c[1] * f, c[2] * f, 1.0)
    return m


# The cradle ring is authored at the old pool's size at band 1 (s3-interfaces A-3), so the engine
# places it at scale 1: the M1 ring of 7 bu, scaled 2.009 in plan, the top kept at -1.6 bu.
CRADLE_R = 14.0625
CRADLE_K = CRADLE_R / 7.0


def build_cradle_ring():
    m = _below_plane_mats()
    r, s = CRADLE_R, CRADLE_K
    top = -1.6
    k.revolve("Rim", [(r - 0.6 * s, top - 1.2 * s), (r - 0.5 * s, top - 0.3 * s), (r - 0.35 * s, top), (r + 0.35 * s, top),
                      (r + 0.55 * s, top - 0.3 * s), (r + 0.9 * s, top - 1.0 * s), (r + 1.3 * s, top - 1.4 * s)],
              m["silica"], 144, lobes=(72, 0.004 * s))
    k.torus("Lip", r, 0.12 * s, m["frost"], (0, 0, top - 0.02 * s), seg=(144, 5))
    for i in range(36):
        a = i * math.tau / 36
        k.sphere(f"Bead{i}", 0.14 * s, (r * math.cos(a), r * math.sin(a), top - 0.05 * s), m["amber"] if i % 3 == 0 else m["lavender"], 8, 4)
    k.assemble("cradle_ring")
    return {
        "purpose": "S3 cradle ring dressing: a low glass rim 28.1 bu across (the old pool at band 1, placed at scale 1) with a frosted lip and a ring of beads, sunk below the decor-free band, framing the old pool shrunk to a tiny dish at band 1.",
        "category": "dressing", "kind": "dressing", "band": 1,
        "pivot": "centre of the old pool on the swim plane (Godot y = 0)",
        "radius_bu": r, "top_bu": top,
    }


def build_home_beacon():
    m = _below_plane_mats()
    base = -40.0
    k.revolve("Foot", [(0.0, base), (6.0, base + 0.5), (5.0, base + 3.0), (2.5, base + 6.0), (1.6, base + 10.0)], m["frost"], 48, lobes=(9, 0.05))
    k.lattice("Spire", 4.0, (0, 0, base + 18.0), m["silica"], 2, 0.25, (1, 1, 2.2), keep=lambda co: True)
    k.lattice("Crown", 2.4, (0, 0, -16.2), m["frost"], 2, 0.18, (1, 1, 1.4), keep=lambda co: co.z > -1.2)
    k.sphere("Heart", 2.0, (0, 0, base + 18.0), m["core"], 20, 10)
    k.assemble("home_beacon")
    pts = bc.world_vertices()
    top = max(p.z for p in pts)
    k._check(top <= -12.0, f"home_beacon: top {top:.1f} must stay at or under -12 bu")
    return {
        "purpose": "S3 home beacon: a giant glass radiolarian spire over home, seen far below the plane, its amber heart a landmark for the way back.",
        "category": "dressing", "kind": "background", "band": 0,
        "pivot": "home on the swim plane; the whole beacon lies below -12 bu",
        "top_bu": round(top, 2),
    }


def _ghost_model(name, build):
    bc.reset_scene()
    build(k._mats())
    path = os.path.join(bc.ROOT, "assets", "source", "blender", f"{name}.blend")
    if os.path.exists(path):
        os.remove(path)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    print("saved", path)


def engulfer(m):
    """Size 5: the engulfer, a great amoeba reaching with blunt pseudopods round a food cup."""
    body = k.sphere("Body", 1.0, (0, 0, 0.0), m["husk"], 32, 16, (1.3, 1.1, 0.45))
    for i in range(6):
        a = i * math.tau / 6 + 0.4
        d = Vector((math.cos(a), math.sin(a), 0.0))
        tip = d * (1.8 + 0.3 * (i % 2))
        k.tube(f"Pseudopod{i}", [d * 0.9, d * 1.4 + Vector((0, 0, 0.03)), tip], 0.3, m["husk"], 12)
        k.sphere(f"PodTip{i}", 0.3, tip, m["husk"], 16, 8, (1, 1, 0.8))    # blunt, rounded ends
    k.sphere("Nucleus", 0.35, (0.2, -0.1, 0.25), m["lavender"], 16, 8)
    for i in range(5):
        k.sphere(f"Vacuole{i}", 0.12, (0.6 * math.cos(i * 1.3), 0.5 * math.sin(i * 1.3), 0.2), m["frost"], 10, 5)
    return body


def lancer(m):
    """Size 6: the lancer, a long needle-bodied swimmer with a glass rostrum and trailing fins."""
    k.sphere("Body", 1.0, (0, 0, 0), m["deep"], 24, 12, (0.25, 1.4, 0.22))
    k.tube("Rostrum", [Vector((0, 1.3, 0)), Vector((0, 2.0, 0.02)), Vector((0, 2.8, 0.04))], 0.08, m["silica"], 8, True)
    for side in (-1, 1):
        k.tube(f"Fin{side}", [Vector((side * 0.2, -0.4, 0)), Vector((side * 0.6, -1.0, 0.02)), Vector((side * 0.5, -1.6, 0.0))], 0.08, m["frost"], 6, True)
    k.tube("Tail", [Vector((0, -1.3, 0)), Vector((0, -2.0, 0.05)), Vector((0, -2.6, 0.0))], 0.1, m["deep"], 8, True)


def bloom_tint():
    size = 256
    y, x = np.mgrid[-1:1:size * 1j, -1:1:size * 1j]
    r = np.sqrt(x * x + y * y)
    a = np.clip(1.0 - r, 0.0, 1.0) ** 1.6
    px = np.ones((size, size, 4), dtype=np.float32)
    px[..., 3] = a
    img = bpy.data.images.new("T_BloomTint", size, size, alpha=True)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(bc.ROOT, "assets", "export", "ambience", "T_BloomTint.png")
    img.file_format = "PNG"
    img.save()
    print("saved", img.filepath_raw)


GLBS = {
    "veil_threads": (build_veil_threads, 2000, "dressing"),
    "cradle_ring": (build_cradle_ring, 6000, "landmark"),
    "home_beacon": (build_home_beacon, 8000, "rare"),
}
OTHERS = {
    "ghost_engulfer": lambda: _ghost_model("ghost_engulfer", engulfer),
    "ghost_lancer": lambda: _ghost_model("ghost_lancer", lancer),
    "bloom_tint": bloom_tint,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the endless world's S3 extras.")
    parser.add_argument("--only", default="", help="comma-separated ids: " + ",".join(list(GLBS) + list(OTHERS)))
    args = parser.parse_args(argv)
    ids = [i for i in args.only.split(",") if i] or list(GLBS) + list(OTHERS)
    for asset_id in ids:
        if asset_id in OTHERS:
            OTHERS[asset_id]()
            continue
        builder, budget, texture_kind = GLBS[asset_id]
        bc.reset_scene()
        fields = builder()
        review = ENGINE_DRAWN_REVIEW
        if asset_id != "veil_threads":    # the threads are drawn by their engine materials
            fields["textures"] = p1.finish(asset_id, texture_kind)
            review = REVIEW_STATE
        record = bc.export(asset_id, budget, fields, review_state=review, generator=GENERATOR, provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
