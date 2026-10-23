"""S4 membrane variants: seamless detail sets that change the cell body's skin without re-baking it.

Each membrane is a 512 x 512 tileable pair:
- T_<id>_Detail.png: greyscale albedo multiplier (mid grey 0.5 = no change under a 2x multiply),
- T_<id>_Normal.png: tangent-space normal (OpenGL, +Y up) from the same height field,
for StandardMaterial3D's detail layer (detail_enabled, detail_blend_mode multiply) on the body.
Every pattern is periodic over the tile, so it repeats without seams. PROPOSED, awaiting owner look review.

Run: python tools/blender/make_membranes.py [--review]   (bpy 5.2.2 venv; numpy ships with bpy)
--review renders the sample cell's body in each membrane to docs/art/renders/production/membranes_sheet.jpg
(needs ImageMagick's `montage`, a review tool only).
"""

import json
import os
import shutil
import subprocess
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blockout_common as bc  # noqa: E402

SIZE = 512
UV_SCALE = 3.0      # tiles across the body
# The Detail mask multiplies over the player's hue (2 x detail): at least 0.42 keeps the darkest groove at
# 84% brightness, so every hue still reads as the player cell. Greyscale cannot shift the hue.
DETAIL_MIN = 0.42
OUT = os.path.join(bc.ROOT, "assets", "export", "membranes")
RECORD = os.path.join(bc.ROOT, "assets", "records", "textures", "membranes.json")
GENERATOR = "tools/blender/make_membranes.py"

# Pixel grid in tile units [0, 1).
_V, _U = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64) / SIZE


def _periodic_noise(rng, freqs, amps):
    """Sum of random-phase sines with whole-number frequencies: seamless over the tile."""
    h = np.zeros((SIZE, SIZE))
    for f, a in zip(freqs, amps):
        for _ in range(6):
            kx, ky = rng.integers(-f, f + 1, 2)
            if kx == 0 and ky == 0:
                continue
            h += a * np.sin(2.0 * np.pi * (kx * _U + ky * _V) + rng.uniform(0.0, 2.0 * np.pi))
    return h


def _voronoi(rng, cells):
    """Wrapped Voronoi: distances to the nearest and second-nearest seed, and the nearest seed's index."""
    seeds = rng.uniform(0.0, 1.0, (cells, 2))
    d1 = np.full((SIZE, SIZE), 9.0)
    d2 = np.full((SIZE, SIZE), 9.0)
    idx = np.zeros((SIZE, SIZE), dtype=np.int32)
    for i, (sx, sy) in enumerate(seeds):
        dx = np.abs(_U - sx)
        dy = np.abs(_V - sy)
        dx = np.minimum(dx, 1.0 - dx)
        dy = np.minimum(dy, 1.0 - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, i, idx)
        d1 = np.where(closer, d, d1)
    return d1, d2, idx


def _norm(a):
    return (a - a.min()) / max(1e-9, a.max() - a.min())


def smooth_plasma(rng):
    """Plain fluid membrane: a slow swell with a faint fine stipple. The default look."""
    h = _norm(_periodic_noise(rng, [2, 4, 9], [1.0, 0.45, 0.12]))
    stipple = _norm(_periodic_noise(rng, [40], [1.0]))
    detail = 0.5 + 0.06 * (h - 0.5) + 0.03 * (stipple - 0.5)
    return h * 0.6 + stipple * 0.08, detail, 1.2


def pellicle(rng):
    """A ribbed protein pellicle: fine ribs that run around the body with a slight wave."""
    wave = 0.02 * np.sin(2.0 * np.pi * (2 * _U + rng.uniform()))
    ribs = 0.5 + 0.5 * np.cos(2.0 * np.pi * (9 * (_V + wave)))
    ribs = ribs ** 0.6
    breakup = _norm(_periodic_noise(rng, [3, 7], [1.0, 0.4]))
    h = ribs * (0.75 + 0.25 * breakup)
    detail = 0.5 + 0.1 * (ribs - 0.5) - 0.04 * (1.0 - breakup)
    return h, detail, 1.6


def cell_wall(rng):
    """A plated cell wall: polygonal plates parted by soft grooves, each plate a touch different."""
    d1, d2, idx = _voronoi(rng, 34)
    edge = d2 - d1
    groove = np.clip(edge / 0.035, 0.0, 1.0) ** 0.7
    tone = rng.uniform(-0.05, 0.05, idx.max() + 1)[idx]
    grain = _norm(_periodic_noise(rng, [30], [1.0]))
    h = groove * (0.9 + 0.1 * grain)
    detail = 0.5 + tone + 0.12 * (groove - 1.0) + 0.02 * (grain - 0.5)
    return h, detail, 2.4


def capsule(rng):
    """A slime capsule: clustered round vesicles of a few sizes, domed and glossy-looking."""
    h = np.zeros((SIZE, SIZE))
    for cells, scale in ((22, 1.0), (60, 0.55)):
        d1, _, _ = _voronoi(rng, cells)
        r = 0.55 / np.sqrt(cells)
        dome = np.sqrt(np.clip(1.0 - (d1 / r) ** 2, 0.0, 1.0))
        h = np.maximum(h, dome * scale)
    detail = 0.5 + 0.08 * (h - 0.4)
    return h, detail, 2.6


# Stable ids: S4 stores them in saves as Genome appearance.membrane. Never rename one.
MEMBRANES = {
    "membrane_smooth_plasma": (smooth_plasma, "Smooth plasma membrane: a slow swell and a faint stipple; the default skin."),
    "membrane_ribbed_pellicle": (pellicle, "Ribbed pellicle: fine protein ribs that wrap the body; reads as tougher and faster."),
    "membrane_plated_wall": (cell_wall, "Plated cell wall: polygonal plates parted by grooves; reads as armoured."),
    "membrane_bubbly_capsule": (capsule, "Slime capsule: clustered domed vesicles; reads as soft and sticky."),
}


def _normal_map(h, strength):
    """Tangent-space normal (OpenGL, +Y up) from a height field with wrapped differences."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength * SIZE / 64.0
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength * SIZE / 64.0
    n = np.stack([-dx, -dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def _save(name, rgb, colorspace):
    """rgb: (SIZE, SIZE, 3) in display order, row 0 = top. Blender stores rows bottom-up."""
    px = np.ones((SIZE, SIZE, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb[::-1], 0.0, 1.0)
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
    img.colorspace_settings.name = "Non-Color"     # values are written as-is; sRGB data is already encoded
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(OUT, f"{name}.png")
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    print("saved", os.path.join(OUT, f"{name}.png"))
    return {"name": name, "path": f"assets/export/membranes/{name}.png", "size": [SIZE, SIZE], "colorspace": colorspace}


def main():
    os.makedirs(OUT, exist_ok=True)
    items = []
    for i, (mid, (fn, look)) in enumerate(MEMBRANES.items()):
        rng = np.random.default_rng(4100 + i)
        h, detail, strength = fn(rng)
        h = _norm(h)
        detail = np.clip(detail, DETAIL_MIN, 0.62)
        tex = [_save(f"T_{mid}_Detail", np.repeat(detail[..., None], 3, axis=-1), "sRGB"),
               _save(f"T_{mid}_Normal", _normal_map(h, strength), "Non-Color")]
        # Seam check: the wrap difference must look like any neighbouring pixel difference.
        jump = max(np.abs(h[0] - h[-1]).max(), np.abs(h[:, 0] - h[:, -1]).max())
        inner = max(np.abs(np.diff(h, axis=0)).max(), np.abs(np.diff(h, axis=1)).max())
        assert jump <= inner * 1.05 + 1e-6, f"{mid}: seam {jump:.3f} vs neighbours {inner:.3f}"
        items.append({"id": mid, "look": look, "detail": tex[0]["path"], "normal": tex[1]["path"],
                      "uv_scale": UV_SCALE, "detail_min": round(float(detail.min()), 3), "textures": tex,
                      "normal_strength": strength})
    record = {
        "id": "membranes",
        "owner": "Joshua Jake",
        "status": "PROPOSED",
        "review_state": "production rev 1 - S4, awaiting owner look review",
        "purpose": "S4 cell editor membrane variants: seamless detail sets that change the cell body's skin texture without re-baking the body.",
        "generator_script": GENERATOR,
        "provenance": "Generated by the script from periodic sine sums and wrapped Voronoi in numpy; no outside sources.",
        "usage": ("StandardMaterial3D detail layer on the body material: detail_enabled = true, detail_blend_mode = multiply "
                  "(the Detail texture is centred on 0.5; scale albedo by 2 x detail), detail_albedo = T_<id>_Detail, "
                  "detail_normal = T_<id>_Normal, triplanar or UV2 at uv_scale tiles across the body. "
                  "Import the Normal texture as a normal map."),
        "rules": "Greyscale only, so the body keeps its own hue and never drifts toward the food or threat hue; the Detail mask stays at or above 0.42 (84% brightness under the 2x multiply) so every hue still reads against the deep-blue fluid.",
        "default": "membrane_smooth_plasma",
        "items": items,
    }
    with open(RECORD, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=1)
        fh.write("\n")
    print("wrote", RECORD)


def _apply(body, mid):
    """A review-only copy of the body material with the membrane layered on, the way the detail layer draws it."""
    mat = bpy.data.materials["M_PlayerCell"].copy()
    body.data.materials[0] = mat
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    scale = nodes.new("ShaderNodeVectorMath")
    scale.operation = "SCALE"
    scale.inputs["Scale"].default_value = UV_SCALE / 1.0     # the body is about 1 m across
    links.new(coords.outputs["Object"], scale.inputs[0])
    texs = {}
    for kind in ("Detail", "Normal"):
        img = bpy.data.images.load(os.path.join(OUT, f"T_{mid}_{kind}.png"))
        img.colorspace_settings.name = "sRGB" if kind == "Detail" else "Non-Color"
        tex = nodes.new("ShaderNodeTexImage")
        tex.image, tex.projection, tex.projection_blend = img, "BOX", 0.3
        links.new(scale.outputs[0], tex.inputs["Vector"])
        texs[kind] = tex
    mult = nodes.new("ShaderNodeMix")
    mult.data_type, mult.blend_type = "RGBA", "MULTIPLY"
    mult.inputs["Factor"].default_value = 1.0
    links.new(nodes["Image Texture"].outputs["Color"], mult.inputs["A"])
    double = nodes.new("ShaderNodeVectorMath")
    double.operation = "SCALE"
    double.inputs["Scale"].default_value = 2.0
    links.new(texs["Detail"].outputs["Color"], double.inputs[0])
    links.new(double.outputs[0], mult.inputs["B"])
    links.new(mult.outputs["Result"], bsdf.inputs["Base Color"])
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(texs["Normal"].outputs["Color"], nmap.inputs["Color"])
    blend = nodes.new("ShaderNodeVectorMath")
    blend.operation = "ADD"
    links.new(nodes["Normal Map"].outputs["Normal"], blend.inputs[0])
    links.new(nmap.outputs["Normal"], blend.inputs[1])
    norm = nodes.new("ShaderNodeVectorMath")
    norm.operation = "NORMALIZE"
    links.new(blend.outputs[0], norm.inputs[0])
    links.new(norm.outputs[0], bsdf.inputs["Normal"])


def review():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import lookdev as ld
    out = os.path.join(ld.RENDER_DIR, "production")
    os.makedirs(out, exist_ok=True)
    frames = []
    for mid in MEMBRANES:
        bpy.ops.wm.open_mainfile(filepath=os.path.join(bc.ROOT, "assets", "source", "blender", "sample_cell.blend"))
        _apply(bpy.data.objects["Body"], mid)
        ld.setup_render(resolution=480, samples=40)
        ld.review_lighting()
        ld.ground_disc(radius=200, z=-0.5)
        cam = ld.camera(lens=55)
        ld.aim(cam, (0, 0, 0.05), 2.6, 35.0, 30.0)
        path = os.path.join(out, f"{mid}_beauty_00.png")
        ld.render_to(path)
        frames.append(path)
    if shutil.which("montage"):
        subprocess.run(["montage", *frames, "-tile", "4x1", "-geometry", "300x300+2+2", "-background", "#22303A",
                        "-quality", "88", os.path.join(out, "membranes_sheet.jpg")], check=True)


if __name__ == "__main__":
    if "--review" in sys.argv:
        review()
    else:
        main()
