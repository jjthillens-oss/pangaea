"""Concept sheet for the band-0 landmarks and rare set pieces of the endless cell world
(/mnt/project-files/pangaea/docs/endless-cell-plan.md, section I, step S1). A concept render, not
game content: each design is staged alone at the gameplay camera's pitch, with the player cell for
scale and the 3 m landmark anchor drawn as a faint ring, so the owner can judge the shapes before
they are built as production assets. Every design is original.

Colours keep clear of the food green and the threat pink: silica blues, lavender, cream and amber.

Writes docs/art/renders/concept/landmarks_<name>.jpg per design and landmarks_sheet.jpg (4 x 2).
Run: python tools/blender/render_landmark_concepts.py [--samples N] [--only name,...]
"""
import argparse
import math
import os
import random
import subprocess
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402
import render_micro_mood as mm  # noqa: E402

OUT = os.path.join(ld.RENDER_DIR, "concept")
ANCHOR = 3.0      # every landmark fits a circle of this radius (plan A.2)


# --- Shared pieces ------------------------------------------------------------------------------


def _mats():
    return {
        "silica": mm.glass("M_Silica", "#CFE2F2", 0.12, rim=1.4),
        "silica_frost": mm.glass("M_SilicaFrost", "#BCD2EA", 0.35, rim=1.0),
        "core": mm.soft("M_Core", "#E7C68B", 0.35, sss=0.4, emit="#F2C26B", emit_strength=0.4),
        "cream": mm.soft("M_Cream", "#E9DCC0", 0.45, sss=0.4),
        "lavender": mm.soft("M_Lavender", "#A79AD6", 0.4, sss=0.5, emit="#B8ACE4", emit_strength=0.1),
        "husk": mm.glass("M_Husk", "#CBC2D6", 0.45, rim=0.6),
        "husk_dark": mm.soft("M_HuskDark", "#7F7A8E", 0.6),
        "amber": mm.soft("M_Amber", "#D8A55A", 0.4, sss=0.3),
        "bone": mm.glass("M_Bone", "#D9D2C4", 0.4, rim=0.5),
    }


def lattice_sphere(name, radius, location, mat, subdiv=2, thickness=0.035, squash=(1, 1, 1), half=False):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = squash
    if half:
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -radius * 0.05], context="VERTS")
        bm.to_mesh(obj.data)
        bm.free()
    wire = obj.modifiers.new("Lattice", "WIREFRAME")
    wire.thickness = radius * thickness
    wire.use_even_offset = True
    obj.modifiers.new("Smooth", "SUBSURF").levels = 1
    obj.data.materials.append(mat)
    return obj


def spines(name, centre, radius, dirs, length, mat, thick=0.03):
    out = []
    for i, d in enumerate(dirs):
        d = Vector(d).normalized()
        pts = [Vector(centre) + d * (radius * 0.95 + length * t) for t in (0.0, 0.5, 1.0)]
        out.append(mm.tube(f"{name}{i}", pts, radius * thick, mat, sides=6, taper=True))
    return out


def ico_dirs(subdiv=1, up_only=False):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1.0)
    guide = bpy.context.object
    dirs = [v.co.normalized() for v in guide.data.vertices]
    bpy.data.objects.remove(guide)
    return [d for d in dirs if not up_only or d.z > 0.15]


def revolve(name, profile, mat, segments=64, location=(0, 0, 0), lobes=(0, 0.0)):
    """[(radius, z)] around +Z, with optional scallops."""
    verts, faces = [], []
    for r, z in profile:
        for j in range(segments):
            a = math.tau * j / segments
            k = 1.0 + lobes[1] * math.cos(lobes[0] * a)
            verts.append((r * k * math.cos(a), r * k * math.sin(a), z))
    for i in range(len(profile) - 1):
        for j in range(segments):
            n = (j + 1) % segments
            faces.append((i * segments + j, i * segments + n, (i + 1) * segments + n, (i + 1) * segments + j))
    return mm.obj_from(name, verts, faces, mat, location)


# --- Landmarks ----------------------------------------------------------------------------------


def great_shell(m, rng):
    """A giant radiolarian dome: a domed lattice helmet over a glowing amber heart, with a crown of
    spines and a skirt of feet that sink into the depths."""
    dome = lattice_sphere("Dome", 2.8, (0, 0, -0.6), m["silica"], 3, 0.03, (1, 1, 1.15), half=True)
    inner = lattice_sphere("Inner", 1.7, (0, 0, -0.4), m["silica_frost"], 2, 0.04)
    heart = mm.uv_sphere("Heart", 0.9, (0, 0, 0.2), m["core"], 32, 16)
    crown = spines("Crown", (0, 0, -0.6), 3.0, [d for d in ico_dirs(2, True) if d.z > 0.55], 1.6, m["silica"], 0.02)
    feet = []
    for i in range(10):
        a = math.tau * i / 10
        base = Vector((2.7 * math.cos(a), 2.7 * math.sin(a), -0.6))
        feet.append(mm.tube(f"Foot{i}", [base, base * 1.06 + Vector((0, 0, -2.0)), base * 1.02 + Vector((0, 0, -4.5))], 0.12, m["silica"], 8, True))
    return 3.4


def arch(m, rng):
    """A curved silica rib, the last bone of a long-dead colony, springing from two ribbed feet."""
    pts = []
    for i in range(41):
        t = i / 40
        a = math.pi * t
        pts.append(Vector((-2.6 * math.cos(a), 0.4 * math.sin(2 * a), -1.8 + 6.0 * math.sin(a))))
    rib = mm.tube("Rib", pts, 0.38, m["silica"], 16)
    # Ribbing: rings along the arch.
    for i in range(2, 39, 3):
        p = pts[i]
        t = (pts[i + 1] - pts[i - 1]).normalized()
        ring = bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.06, location=p)
        r = bpy.context.object
        r.rotation_euler = t.to_track_quat("Z", "Y").to_euler()
        r.data.materials.append(m["silica_frost"])
    for x in (-2.6, 2.6):
        revolve(f"Foot{x}", [(0.0, -3.0), (0.9, -2.6), (0.75, -1.2), (0.55, -0.4), (0.4, 0.4), (0.0, 0.5)],
                m["silica_frost"], 48, (x, 0, 0), (9, 0.08))
    for i in range(6):
        mm.uv_sphere(f"Bead{i}", 0.14, pts[6 + i * 5] + Vector((0, 0, 0.42)), m["amber"], 16, 8)
    return 3.6


def giant_carcass(m, rng):
    """The collapsed husk of a giant protist: a deflated, ribbed membrane with its glassy skeleton
    showing through and a spill of cream granules. Pale and greyed, never carrion red or threat pink."""
    husk = mm.uv_sphere("Husk", 1.0, (0, 0, -0.8), m["husk"], 64, 32, (3.0, 2.0, 1.1))
    husk.rotation_euler = (0.0, 0.15, 0.4)
    dent = husk.modifiers.new("Wrinkle", "DISPLACE")
    tex = bpy.data.textures.new("Wrinkles", "CLOUDS")
    tex.noise_scale = 0.6
    dent.texture = tex
    dent.strength = 0.5
    husk.modifiers.new("Smooth", "SUBSURF").levels = 1
    for i in range(9):
        a = -1.1 + i * 0.27
        pts = [Vector((math.sin(a) * 2.4 * math.cos(t), math.cos(a) * 1.7, -0.6 + 1.6 * math.sin(t))) for t in [k / 12 * math.pi for k in range(13)]]
        rib = mm.tube(f"Rib{i}", pts, 0.09, m["silica_frost"], 8)
        rib.rotation_euler = (0, 0, 0.4)
    for i in range(40):
        p = Vector((rng.uniform(1.6, 3.2), rng.uniform(-1.6, 1.6), rng.uniform(-1.2, 0.0)))
        mm.uv_sphere(f"Granule{i}", rng.uniform(0.06, 0.16), p, m["cream"], 12, 6)
    return 3.6


def spire(m, rng):
    """A twisted sponge spicule tower: three glassy strands braided upward, with whorls of hooks."""
    for s in range(3):
        pts = []
        for i in range(60):
            t = i / 59
            a = s * math.tau / 3 + t * math.tau * 1.6
            r = 0.8 * (1.0 - 0.7 * t)
            pts.append(Vector((r * math.cos(a), r * math.sin(a), -3.0 + 10.5 * t)))
        mm.tube(f"Strand{s}", pts, 0.26 * (1.0 - 0.0), m["silica"], 10, True)
    for w in range(5):
        z = -0.5 + w * 1.7
        r = 0.8 * (1.0 - 0.7 * (z + 3.0) / 10.5)
        for k in range(7):
            a = math.tau * k / 7 + w
            base = Vector((r * math.cos(a), r * math.sin(a), z))
            out = Vector((math.cos(a), math.sin(a), 0.6)).normalized()
            mm.tube(f"Hook{w}_{k}", [base, base + out * 0.6, base + out * 0.9 + Vector((0, 0, -0.25))], 0.05, m["silica_frost"], 6, True)
    mm.uv_sphere("Tip", 0.25, (0, 0, 7.6), m["core"], 16, 8)
    revolve("Base", [(0.0, -3.5), (2.2, -2.8), (1.8, -1.6), (1.2, -0.8), (0.9, -0.2), (0.0, 0.0)], m["silica_frost"], 48, lobes=(7, 0.1))
    return 5.6


def ring(m, rng):
    """A giant diatom girdle band standing on edge: a glassy hoop with rows of pores, half sunk."""
    bpy.ops.mesh.primitive_torus_add(major_radius=2.6, minor_radius=0.42, major_segments=96, minor_segments=24, location=(0, 0, 0.6))
    hoop = bpy.context.object
    hoop.name = "Hoop"
    hoop.rotation_euler = (math.pi / 2, 0, 0.35)
    hoop.scale = (1.0, 1.0, 1.0)
    hoop.data.materials.append(m["silica"])
    for i in range(36):
        a = math.tau * i / 36
        p = Vector((2.6 * math.cos(a), 0.0, 0.6 + 2.6 * math.sin(a)))
        for side in (-1, 1):
            q = p + Vector((0.0, side * 0.43, 0.0))
            o = mm.uv_sphere(f"Pore{i}_{side}", 0.11, q, m["lavender"], 10, 6, (1, 0.4, 1))
            o.rotation_euler = (0, 0, 0)
    for o in [o for o in bpy.data.objects if o.name.startswith("Pore")]:
        o.location = Euler((0, 0, 0.35)).to_matrix() @ o.location
    for x in (-1.0, 1.0):
        revolve(f"Cradle{x}", [(0.0, -2.8), (1.3, -2.3), (1.0, -1.4), (0.6, -0.9), (0.0, -0.8)], m["silica_frost"], 40, (x * 1.6, 0, 0))
    return 3.6


def fan(m, rng):
    """A fan colony: branching cream stalks holding amber bell-shaped cells, spread like a hand."""
    def branch(base, direction, length, depth, idx):
        tip = base + direction * length
        mid = base + direction * length * 0.5 + Vector((0, 0, 0.1))
        mm.tube(f"Stalk{idx}", [base, mid, tip], 0.07 * (0.7 ** (3 - depth)) + 0.02, m["cream"], 8)
        if depth == 0:
            bell = revolve(f"Bell{idx}", [(0.0, -0.05), (0.12, 0.0), (0.22, 0.18), (0.24, 0.32), (0.16, 0.34), (0.0, 0.3)],
                           m["amber"], 20, tip, (8, 0.06))
            bell.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
            return
        for k, turn in enumerate((-0.42, 0.42)):
            d = (Euler((0, turn * 0.6, turn)).to_matrix() @ direction).normalized()
            branch(tip, d, length * 0.72, depth - 1, f"{idx}{k}")
    root = Vector((0, 0, -3.0))
    mm.tube("Trunk", [root, Vector((0, 0, -1.4)), Vector((0, 0, 0.0))], 0.24, m["cream"], 12)
    for k, yaw in enumerate((-0.6, -0.2, 0.2, 0.6)):
        branch(Vector((0, 0, 0.0)), Vector((math.sin(yaw), 0.15, math.cos(yaw) * 1.2)).normalized(), 1.6, 3, f"B{k}")
    revolve("Holdfast", [(0.0, -3.6), (1.4, -3.2), (0.9, -2.6), (0.3, -2.4), (0.0, -2.4)], m["husk_dark"], 40, lobes=(6, 0.2))
    return 4.2


# --- Rare set pieces ----------------------------------------------------------------------------


def giant_bones(m, rng):
    """The picked-clean remains of something huge: a curved chain of hollow vertebral rings and a
    fan of bare ribs, cream-grey glass with no soft tissue, no granules and no food rim, so it never
    reads as food."""
    path = [Vector((-5.0 + 10.0 * t, 1.2 * math.sin(t * math.pi * 1.2), -0.6 + 0.9 * math.sin(t * math.pi))) for t in [k / 13 for k in range(14)]]
    for k, p in enumerate(path):
        t = (path[min(k + 1, 13)] - path[max(k - 1, 0)]).normalized()
        size = 0.8 * (1.0 - 0.45 * abs(k - 5) / 8)
        bpy.ops.mesh.primitive_torus_add(major_radius=size, minor_radius=size * 0.42, major_segments=32, minor_segments=12, location=p)
        ring = bpy.context.object
        ring.rotation_euler = t.to_track_quat("Z", "Y").to_euler()
        ring.data.materials.append(m["bone"])
        mm.tube(f"Process{k}", [p, p + Vector((0, 0, size * 1.4)), p + Vector((0.1, 0, size * 2.0))], size * 0.16, m["bone"], 6, True)
        if 2 <= k <= 9:
            for side in (-1, 1):
                # Ribs arch up and over, then fall away to their broken tips in the depths.
                ribs = [p + Vector((0.3 * math.sin(a), side * (size + 1.9 * math.sin(a)), 2.2 * math.sin(a * 0.9) - 2.8 * (a / math.pi) ** 2))
                        for a in [q / 12 * math.pi for q in range(13)]]
                mm.tube(f"Rib{k}_{side}", ribs, size * 0.22, m["bone"], 10, True)
    return 4.6


def shell_cathedral(m, rng):
    """A ring of tall glass drums with pointed lattice spires around a lit nave, like a cathedral
    grown by diatoms."""
    for i in range(7):
        a = math.tau * i / 7
        p = Vector((3.4 * math.cos(a), 3.4 * math.sin(a), 0.0))
        h = 2.0 + 2.2 * (0.5 + 0.5 * math.cos(a - 1.2))
        revolve(f"Drum{i}", [(0.0, -3.0), (1.0, -2.8), (1.0, h - 1.0), (0.8, h - 0.6), (0.0, h - 0.5)], m["silica"], 48, p, (24, 0.03))
        lattice_sphere(f"Spire{i}", 0.75, p + Vector((0, 0, h - 0.4)), m["silica_frost"], 2, 0.05, (1, 1, 2.4), half=True)
    lattice_sphere("Vault", 4.4, (0, 0, -0.5), m["silica"], 2, 0.012, (1, 1, 0.9), half=True)
    mm.uv_sphere("Light", 0.7, (0, 0, -1.5), m["core"], 32, 16)
    return 5.6


DESIGNS = {
    "great_shell": great_shell, "arch": arch, "giant_carcass": giant_carcass, "spire": spire,
    "ring": ring, "fan": fan, "giant_bones": giant_bones, "shell_cathedral": shell_cathedral,
}
LABELS = {
    "great_shell": "1 Great shell", "arch": "2 Arch", "giant_carcass": "3 Giant carcass", "spire": "4 Spire",
    "ring": "5 Ring", "fan": "6 Fan", "giant_bones": "Rare: giant bones", "shell_cathedral": "Rare: shell cathedral",
}


# --- Staging ------------------------------------------------------------------------------------


def _stage(extent, samples):
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Fluid")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = ld.color("#123E78")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 20), rotation=(math.radians(35), 0, math.radians(-135)))
    bpy.context.object.data.energy = 3.2
    bpy.context.object.data.color = (0.957, 0.918, 0.824)
    # The swim plane's anchor: a faint ring of radius ANCHOR, and the player cell beside it for scale.
    bpy.ops.mesh.primitive_torus_add(major_radius=ANCHOR, minor_radius=0.02, major_segments=128, minor_segments=6)
    bpy.context.object.data.materials.append(mm.soft("M_Anchor", "#F2E6C8", 0.5, emit="#F2E6C8", emit_strength=0.6))
    mm.append_asset("sample_cell", (ANCHOR + 1.2, -ANCHOR * 0.6, 0.0), yaw_deg=-40.0)
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    pitch = math.radians(55.0)
    distance = extent * 3.4
    target = Vector((0.0, 0.0, 0.6 + max(0.0, extent - 4.0) * 0.8))
    cam.location = target + Vector((0.0, -math.cos(pitch) * distance, math.sin(pitch) * distance))
    cam.rotation_euler = (math.pi / 2 - pitch, 0.0, 0.0)
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(45.0)
    cam_data.clip_end = 500
    scene.camera = cam
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.transmission_bounces = 6
    scene.render.resolution_x, scene.render.resolution_y = 960, 540
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.3
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 88


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=48)
    parser.add_argument("--only", default="")
    args = parser.parse_args(argv)
    names = [n for n in DESIGNS if not args.only or n in args.only.split(",")]
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        extent = DESIGNS[name](_mats(), random.Random(name))
        _stage(extent, args.samples)
        bpy.context.scene.render.filepath = os.path.join(OUT, f"landmarks_{name}.jpg")
        bpy.ops.render.render(write_still=True)
        print("saved", name)
    tiles = []
    for name in DESIGNS:
        path = os.path.join(OUT, f"landmarks_{name}.jpg")
        if os.path.exists(path):
            tiles += ["-label", LABELS[name], path]
    subprocess.run(["montage", *tiles, "-tile", "4x2", "-geometry", "+6+6", "-background", "#0A1A33",
                    "-fill", "#F2E6C8", "-pointsize", "26", "-quality", "88", os.path.join(OUT, "landmarks_sheet.jpg")], check=True)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
