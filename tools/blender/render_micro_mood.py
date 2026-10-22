"""Mood frame for the cell stage as a microscopic world (owner direction 2026-10-22: "like a cell
reproduction stage", not just underwater). A concept render, not game content: it stages the
production assets (the player cell, the step 3 threats, food) in a blue fluid with depth layers,
so the owner can judge the direction before it is built into the pool scene.

Layers, back to front: cloudy blue depths with giant out-of-focus organisms; glassy radiolarian
and diatom shells beside the swim plane; the creatures and swarms of tiny bacteria, spirilla and
spores on it; bubbles and specks drifting between it and the camera. Every design is original.

Writes docs/art/renders/concept/micro_mood_<name>.png (and a greyscale copy for the readability
check). Run: python tools/blender/render_micro_mood.py [--samples N] [--scale PERCENT]
"""
import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

OUT = os.path.join(ld.RENDER_DIR, "concept")
BLEND = os.path.join(ld.ROOT, "assets", "source", "blender")
RX, RZ = 0.46, 0.5   # game/scenes/pool/part_placement.gd: the body frame every part sits on


# --- Materials ---------------------------------------------------------------------------------


def _mat(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat, mat.node_tree.nodes, mat.node_tree.links, mat.node_tree.nodes["Principled BSDF"]


def glass(name, tint, rough=0.12, alpha=1.0, rim=0.0):
    """A thin, glassy shell: mostly transmissive, with a faint bright rim (as silica lit in water)."""
    mat, nodes, links, bsdf = _mat(name)
    bsdf.inputs["Base Color"].default_value = ld.color(tint)
    bsdf.inputs["Transmission Weight"].default_value = 0.85
    bsdf.inputs["IOR"].default_value = 1.12
    bsdf.inputs["Roughness"].default_value = rough
    if rim:
        fres = nodes.new("ShaderNodeLayerWeight")
        fres.inputs["Blend"].default_value = 0.25
        ramp = nodes.new("ShaderNodeMath")
        ramp.operation = "MULTIPLY"
        links.new(fres.outputs["Facing"], ramp.inputs[0])
        ramp.inputs[1].default_value = rim
        links.new(ramp.outputs[0], bsdf.inputs["Emission Strength"])
        bsdf.inputs["Emission Color"].default_value = ld.color("#CFE6FF")
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
    return mat


def soft(name, base, rough=0.45, sss=0.0, emit=None, emit_strength=0.0, alpha=1.0):
    mat, nodes, links, bsdf = _mat(name)
    bsdf.inputs["Base Color"].default_value = ld.color(base)
    bsdf.inputs["Roughness"].default_value = rough
    if sss:
        bsdf.inputs["Subsurface Weight"].default_value = sss
        bsdf.inputs["Subsurface Radius"].default_value = (0.4, 0.3, 0.2)
        bsdf.inputs["Subsurface Scale"].default_value = 0.2
    if emit:
        bsdf.inputs["Emission Color"].default_value = ld.color(emit)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
    return mat


def bubble_material():
    """An air bubble: clear in the middle, a bright silvery rim where it turns away."""
    mat = bpy.data.materials.new("M_Bubble")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.remove(nodes["Principled BSDF"])
    clear = nodes.new("ShaderNodeBsdfTransparent")
    rim = nodes.new("ShaderNodeEmission")
    rim.inputs["Color"].default_value = ld.color("#DDF0FF")
    rim.inputs["Strength"].default_value = 1.6
    gloss = nodes.new("ShaderNodeBsdfGlossy")
    gloss.inputs["Roughness"].default_value = 0.05
    edge = nodes.new("ShaderNodeLayerWeight")
    edge.inputs["Blend"].default_value = 0.12
    shine = nodes.new("ShaderNodeAddShader")
    links.new(rim.outputs["Emission"], shine.inputs[0])
    links.new(gloss.outputs["BSDF"], shine.inputs[1])
    mix = nodes.new("ShaderNodeMixShader")
    links.new(edge.outputs["Facing"], mix.inputs["Fac"])
    links.new(clear.outputs["BSDF"], mix.inputs[1])
    links.new(shine.outputs["Shader"], mix.inputs[2])
    links.new(mix.outputs["Shader"], nodes["Material Output"].inputs["Surface"])
    return mat


# --- Mesh helpers -------------------------------------------------------------------------------


def obj_from(name, verts, faces, mat, location=(0, 0, 0), smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    if smooth:
        mesh.shade_smooth()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    return obj


def uv_sphere(name, radius, location, mat, segments=24, rings=12, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def tube(name, points, radius, mat, sides=8, taper=False):
    """A tube through `points`; tapers to a point at the end when `taper`."""
    verts, faces = [], []
    n = len(points)
    for i, p in enumerate(points):
        t = (points[min(i + 1, n - 1)] - points[max(i - 1, 0)]).normalized()
        ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        a = t.cross(ref).normalized()
        b = t.cross(a).normalized()
        r = radius * ((1.0 - i / (n - 1)) ** 0.8 if taper else 1.0)
        for j in range(sides):
            ang = 2 * math.pi * j / sides
            verts.append(p + (a * math.cos(ang) + b * math.sin(ang)) * max(r, 1e-4))
    for i in range(n - 1):
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((i * sides + j, i * sides + k, (i + 1) * sides + k, (i + 1) * sides + j))
    return obj_from(name, verts, faces, mat)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


# --- Shells -------------------------------------------------------------------------------------


def radiolarian(name, radius, location, rng, mat_shell, mat_core, spines=True):
    """A lattice sphere round a glowing core, with radial spines: original, not any game's design."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=location)
    lattice = bpy.context.object
    lattice.name = name
    wire = lattice.modifiers.new("Lattice", "WIREFRAME")
    wire.thickness = radius * 0.035
    wire.use_even_offset = True
    lattice.modifiers.new("Smooth", "SUBSURF").levels = 1
    lattice.data.materials.append(mat_shell)
    parts = [lattice]
    core = uv_sphere(f"{name}_Core", radius * 0.55, location, mat_core)
    parts_extra = [core]
    if spines:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0)
        guide = bpy.context.object
        dirs = [v.co.normalized() for v in guide.data.vertices]
        bpy.data.objects.remove(guide)
        for i, d in enumerate(dirs):
            length = radius * (0.7 + 0.5 * rng.random())
            pts = [Vector(location) + d * (radius * 0.95 + length * t) for t in (0.0, 0.5, 1.0)]
            parts_extra.append(tube(f"{name}_Spine{i}", pts, radius * 0.03, mat_shell, sides=6, taper=True))
    lattice.rotation_euler = Euler((rng.random(), rng.random(), rng.random()))
    return [lattice] + parts_extra


def diatom(name, radius, location, rotation, mat):
    """A centric diatom: a shallow pillbox with a raised rim, concentric rings and radial ribs."""
    top = [(0.0, 0.16), (0.12, 0.2), (0.2, 0.15), (0.35, 0.155), (0.45, 0.19), (0.52, 0.15), (0.62, 0.17),
           (0.72, 0.2), (0.78, 0.15), (0.82, 0.15), (0.9, 0.16), (0.95, 0.24), (1.0, 0.12)]
    profile = top + [(r, -z) for r, z in reversed(top)]
    seg = 72
    verts, faces = [], []
    for r, z in profile:
        for j in range(seg):
            a = 2 * math.pi * j / seg
            rib = 1.0 + (0.35 if j % 3 == 0 and 0.2 < r < 0.97 else 0.0)
            verts.append((r * radius * math.cos(a), r * radius * math.sin(a), z * radius * 0.6 * rib))
    for i in range(len(profile) - 1):
        for j in range(seg):
            k = (j + 1) % seg
            faces.append((i * seg + j, i * seg + k, (i + 1) * seg + k, (i + 1) * seg + j))
    obj = obj_from(name, verts, faces, mat, location)
    obj.rotation_euler = rotation
    return [obj]


# --- Life -------------------------------------------------------------------------------------


def append_asset(asset_id, location, yaw_deg=0.0, scale=1.0):
    """Links every object of a production asset's .blend (its tinted, baked materials included)."""
    path = os.path.join(BLEND, f"{asset_id}.blend")
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if not n.endswith("_high")]
    roots = []
    for obj in dst.objects:
        if obj is None:
            continue
        bpy.context.collection.objects.link(obj)
        if obj.parent is None:
            roots.append(obj)
    for obj in roots:
        obj.location = Vector(location)
        obj.rotation_euler = (0, 0, math.radians(yaw_deg))
        obj.scale = (scale, scale, scale)
    return roots


def attach(part_id, body_roots, angle, scale_body):
    """A part on the body frame at `angle` (0 = front), as PartPlacement places it."""
    root = body_roots[0]
    p = Vector((RX * math.sin(angle), RZ * math.cos(angle), 0.0))
    n = Vector((math.sin(angle) / RX ** 2, math.cos(angle) / RZ ** 2, 0.0)).normalized()
    rot = Matrix.Rotation(-math.atan2(n.x, n.y), 4, "Z")
    for obj in append_asset(part_id, (0, 0, 0)):
        obj.parent = root
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = Matrix.Translation(p) @ rot


def bacteria_swarm(centre, count, rng, mats, spread=1.6):
    for i in range(count):
        d = Vector((rng.gauss(0, spread), rng.gauss(0, spread * 0.8), rng.gauss(0, 0.25)))
        length = 0.08 + 0.12 * rng.random()
        o = uv_sphere(f"Bacterium{i}", 1.0, Vector(centre) + d, rng.choice(mats), 12, 8, (length * 0.35, length, length * 0.35))
        o.rotation_euler = (rng.random() * 0.6, rng.random() * 0.6, rng.random() * math.tau)


def spirillum(name, location, rng, mat, length=0.7):
    turns = 3.0
    pts = [Vector(location) + Vector((0.05 * math.cos(t * turns * math.tau), length * (t - 0.5), 0.05 * math.sin(t * turns * math.tau)))
           for t in [i / 40 for i in range(41)]]
    o = tube(name, pts, 0.018, mat, 6)
    o.rotation_euler = (0, 0, rng.random() * math.tau)


def spore(name, location, mat, radius=0.07):
    o = uv_sphere(name, radius, location, mat, 16, 8)
    spikes = []
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0)
    guide = bpy.context.object
    dirs = [v.co.normalized() for v in guide.data.vertices]
    bpy.data.objects.remove(guide)
    for i, d in enumerate(dirs):
        spikes.append(tube(f"{name}_s{i}", [Vector(location) + d * radius * k for k in (0.9, 1.35, 1.8)], radius * 0.12, mat, 5, True))
    return join([o] + spikes, name)


def giant_ciliate(location, length, mat, cilia_mat, rng):
    """A huge, slow background protist: a long translucent slipper with a fringe of cilia."""
    body = uv_sphere("GiantCiliate", 1.0, location, mat, 48, 24, (length * 0.28, length * 0.5, length * 0.16))
    body.rotation_euler = (0.25, 0.1, 0.9)
    hairs = []
    for i in range(70):
        a = math.tau * i / 70
        base = Vector((math.sin(a) * length * 0.28, math.cos(a) * length * 0.5, 0.0))
        out = base.normalized() * length * 0.06
        hairs.append(tube(f"Cilium{i}", [base, base + out * 0.5 + Vector((0, 0, 0.1)), base + out], length * 0.006, cilia_mat, 5, True))
    fringe = join(hairs, "GiantCiliateCilia")
    fringe.location = location
    fringe.rotation_euler = body.rotation_euler
    return [body, fringe]


def colony_chain(location, mat, rng, beads=26):
    """A coiled chain of cells, far below and out of focus."""
    objs = []
    for i in range(beads):
        t = i / beads
        a = t * math.tau * 1.4
        r = 4.0 + 2.5 * t
        p = Vector(location) + Vector((r * math.cos(a), r * math.sin(a), 1.2 * math.sin(a * 2)))
        objs.append(uv_sphere(f"Colony{i}", 0.75 + 0.25 * math.sin(i), p, mat, 20, 10))
    return objs


# --- Scene -----------------------------------------------------------------------------------


def build(rng):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # World: deep blue, lighter overhead, like light falling into a drop of water.
    world = bpy.data.worlds.new("Fluid")
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    grad = nt.nodes.new("ShaderNodeTexGradient")
    coords = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coords.outputs["Generated"], sep.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = ld.color("#0B2E6B")
    ramp.color_ramp.elements[1].color = ld.color("#4C9BE0")
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.3
    scene.world = world

    # Cloudy depths: a far plane of soft blue clouds, then haze through the whole volume.
    depths, nodes, links, bsdf = _mat("M_Depths")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.035
    noise.inputs["Detail"].default_value = 4.0
    cr = nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].position = 0.4
    cr.color_ramp.elements[0].color = ld.color("#0D3474")
    cr.color_ramp.elements[1].position = 0.65
    cr.color_ramp.elements[1].color = ld.color("#5AA6E8")
    tc = nodes.new("ShaderNodeTexCoord")
    links.new(tc.outputs["Object"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], cr.inputs["Fac"])
    links.new(cr.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.4
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, -45))
    bpy.context.object.data.materials.append(depths)

    haze = bpy.data.materials.new("M_Haze")
    haze.use_nodes = True
    hn = haze.node_tree
    hn.nodes.remove(hn.nodes["Principled BSDF"])
    vol = hn.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = ld.color("#6AA8E0")
    vol.inputs["Density"].default_value = 0.03
    vol.inputs["Anisotropy"].default_value = 0.55
    hn.links.new(vol.outputs["Volume"], hn.nodes["Material Output"].inputs["Volume"])
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -17))
    box = bpy.context.object
    box.scale = (160, 160, 56)
    box.data.materials.append(haze)

    # Light from above: a soft key and its shafts through the haze.
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 20), rotation=(math.radians(18), math.radians(-12), 0))
    sun = bpy.context.object
    sun.data.energy = 4.0
    sun.data.angle = math.radians(6)
    sun.data.color = (1.0, 0.97, 0.92)

    shell = glass("M_Shell", "#D6E8F4", 0.15, rim=1.6)
    shell_far = glass("M_ShellFar", "#B9D3EC", 0.25, rim=1.0)
    core = soft("M_ShellCore", "#9FC2E0", 0.3, sss=0.4, emit="#BFE3FF", emit_strength=0.4)
    core_warm = soft("M_ShellCoreWarm", "#E7C68B", 0.3, sss=0.4, emit="#F2C26B", emit_strength=0.3)

    # Back: giant, slow organisms far below the swim plane (they blur with depth of field).
    giant = soft("M_Giant", "#E6BFD3", 0.4, sss=0.5, emit="#F0C6DA", emit_strength=0.35, alpha=0.45)
    giant_cilia = soft("M_GiantCilia", "#E5B5C6", 0.5)
    giant_ciliate((-20.0, 26.0, -30.0), 24.0, giant, giant_cilia, rng)
    colony = soft("M_Colony", "#7FBF8E", 0.4, sss=0.6, emit="#A8E3A0", emit_strength=0.15)
    colony_chain((26.0, 16.0, -34.0), colony, rng)
    radiolarian("GiantRadiolarian", 7.0, (18.0, -2.0, -24.0), rng, shell_far, core_warm)
    radiolarian("FarRadiolarian", 3.0, (-15.0, -9.0, -12.0), rng, shell_far, core)

    # Middle: glassy shells beside and just under the swim plane, where rocks were.
    radiolarian("Radiolarian", 1.5, (-6.2, 4.5, -1.2), rng, shell, core)
    radiolarian("RadiolarianSmall", 0.8, (5.6, -3.5, -0.6), rng, shell, core_warm)
    diatom("Diatom", 1.8, (6.5, 5.2, -1.6), (0.5, 0.2, 0.3), shell)
    diatom("DiatomFar", 2.4, (-3.0, 10.0, -5.5), (0.9, -0.3, 0.1), shell_far)
    diatom("DiatomNear", 1.0, (-7.5, -4.0, -0.4), (0.3, 0.6, 0.0), shell)

    # The swim plane: the player cell, the step 3 threats with their parts, food, and swarms.
    cell = append_asset("sample_cell", (0.0, 0.0, 0.0), yaw_deg=-25.0)
    ambush = append_asset("creature_ambush_body", (-3.6, 2.6, 0.0), yaw_deg=-60.0, scale=1.5)
    attach("part_mouth_jaw", ambush, 0.0, 1.5)
    attach("part_flagellum", ambush, math.pi, 1.5)
    rammer = append_asset("creature_rammer_body", (3.4, 1.6, 0.0), yaw_deg=110.0, scale=1.2)
    for a in (0.3, -0.3, 1.9, -1.9):
        attach("part_spike", rammer, a, 1.2)
    attach("part_flagellum", rammer, math.pi, 1.2)
    for i, (x, y) in enumerate([(-1.6, -1.9), (1.2, -2.6), (2.4, -0.4), (-1.0, 2.2), (0.6, 3.6), (-4.6, -2.0)]):
        for obj in append_asset("plankton", (x, y, 0.0), yaw_deg=40.0 * i):
            obj.rotation_euler = (0.4 * (i % 3), 0.3, 0.6 * i)
    append_asset("carrion", (4.4, -2.0, 0.0), yaw_deg=30.0)

    bact = [soft("M_BactGreen", "#6FC46A", 0.35, sss=0.4), soft("M_BactAmber", "#E8B65A", 0.35, sss=0.4),
            soft("M_BactLilac", "#B49BE0", 0.35, sss=0.4)]
    bacteria_swarm((-2.0, -3.4, 0.1), 22, rng, bact, 0.9)
    bacteria_swarm((5.6, 3.0, -0.3), 18, rng, bact, 0.8)
    bacteria_swarm((-6.0, 0.0, -2.5), 30, rng, bact, 1.6)
    spiral = soft("M_Spirillum", "#9BD7C4", 0.35)
    for i, p in enumerate([(1.8, 1.8, 0.2), (-2.8, -0.6, 0.3), (2.9, -3.2, -0.2), (-5.0, 3.0, -0.8)]):
        spirillum(f"Spirillum{i}", p, rng, spiral)
    spore_mat = soft("M_Spore", "#F0D9A0", 0.4, sss=0.3)
    for i in range(14):
        spore(f"Spore{i}", (rng.uniform(-8, 8), rng.uniform(-5, 7), rng.uniform(-3, 0.5)), spore_mat, 0.05 + 0.04 * rng.random())

    # Front: bubbles and specks between the swim plane and the camera, and through the depths.
    bub = bubble_material()
    for i in range(70):
        z = rng.uniform(-6.0, 6.0)
        r = rng.choice([0.04, 0.06, 0.09, 0.14, 0.22]) * (1.6 if z > 2.5 else 1.0)
        uv_sphere(f"Bubble{i}", r, (rng.uniform(-11, 11), rng.uniform(-8, 12), z), bub, 20, 10)
    speck = soft("M_Speck", "#D8E8F0", 0.6, emit="#D8E8F0", emit_strength=0.2)
    for i in range(260):
        uv_sphere(f"Speck{i}", rng.uniform(0.01, 0.035), (rng.uniform(-14, 14), rng.uniform(-10, 18), rng.uniform(-14, 7)), speck, 8, 4)
    return cell


def camera(focus):
    """The gameplay camera's pitch (55 deg) and field of view, a little closer than play."""
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    pitch = math.radians(55.0)
    distance = 12.0
    target = Vector((0.2, 0.8, 0.0))
    cam.location = target + Vector((0.0, -math.cos(pitch) * distance, math.sin(pitch) * distance))
    cam.rotation_euler = (math.pi / 2 - pitch, 0.0, 0.0)
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(45.0)
    cam_data.dof.use_dof = True
    cam_data.dof.focus_distance = distance
    cam_data.dof.aperture_fstop = focus
    bpy.context.scene.camera = cam
    return cam


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=96)
    parser.add_argument("--scale", type=int, default=100)
    parser.add_argument("--fstop", type=float, default=0.08)
    parser.add_argument("--name", default="pool")
    args = parser.parse_args(argv)
    rng = random.Random(7)
    build(rng)
    camera(args.fstop)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    scene.cycles.volume_step_rate = 4.0
    scene.cycles.max_bounces = 6
    scene.cycles.transmission_bounces = 6
    scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
    scene.render.resolution_percentage = args.scale
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.45
    scene.render.image_settings.file_format = "PNG"
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"micro_mood_{args.name}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("saved", path)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
