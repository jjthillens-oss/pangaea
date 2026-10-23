"""Shared look-development helpers: the art-direction palette, the review lighting rig and
turntable rendering. Used by the quality-ladder scripts; see docs/art/ART_DIRECTION.md.

Renders use Cycles on the CPU so they work headless (the bpy module has no GPU context here).
"""
import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RENDER_DIR = os.path.join(ROOT, "docs", "art", "renders")

# Art-direction palette (PROPOSED). Keep in sync with docs/art/ART_DIRECTION.md section 3.
PALETTE = {
    "deep_shadow": "#1D3557",
    "fluid_deep": "#0B2E6B",
    "fluid_light": "#4C9BE0",
    "ambient": "#2F6FB8",
    "pool_teal": "#2A7F86",  # retired as a habitat colour (micro-world plan C9); eye-iris tint only
    "shallow_turquoise": "#49B3A6",
    "algae_green": "#6BAB5A",
    "moss_deep": "#2F6B4A",
    "cream": "#F4EAD2",
    "mineral_amber": "#E3A64A",
    "coral": "#E9744F",
    "rust": "#A94F3A",
    "food_glow": "#CFE86A",
    "threat": "#D9466B",
    "clay": "#B9B3A8",
}
# Kept for the materials that still use them, but no longer on the palette board.
RETIRED = {"pool_teal"}

# Gameplay camera from game/data/pool_m1.json (M1 step 2): pitch 55 deg, FOV 45 deg, 14 m.
GAME_CAMERA = {"pitch_deg": 55.0, "fov_deg": 45.0, "distance": 14.0}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def color(name, alpha=1.0):
    """Palette entry (or a #RRGGBB string) as a linear RGBA tuple for Blender."""
    hexstr = PALETTE.get(name, name).lstrip("#")
    rgb = [srgb_to_linear(int(hexstr[i:i + 2], 16) / 255.0) for i in (0, 2, 4)]
    return (*rgb, alpha)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def principled(name, base, roughness=0.5, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def clay_material():
    mat = bpy.data.materials.get("M_Clay")
    return mat or principled("M_Clay", color("clay"), 0.6)


def setup_render(resolution=640, samples=48, transparent=False):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"


def review_lighting(world_color="#5C7486", strength=0.55):
    """Section 6 lighting: warm key front-left above, cool fill right, teal rim behind."""
    scene = bpy.context.scene
    world = bpy.data.worlds.new("W_Review")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = color(world_color)
    bg.inputs["Strength"].default_value = strength
    scene.world = world

    def area(name, loc, energy, rgb, size):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.color = rgb[:3]
        light.size = size
        obj = bpy.data.objects.new(name, light)
        obj.location = loc
        direction = Vector((0, 0, 0.1)) - Vector(loc)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)
        return obj

    # Light colors are linear and close to white so the albedo palette stays truthful.
    area("Key", (-2.6, 2.4, 3.2), 260, (1.0, 0.9, 0.78), 2.0)
    area("Fill", (3.2, 0.6, 1.0), 70, (0.7, 0.85, 1.0), 3.0)
    area("Rim", (0.6, -3.2, 2.0), 180, (0.55, 1.0, 0.9), 1.5)


def ground_disc(radius=3.0, z=-0.45, name="Ground"):
    """A soft catch surface so contact shadows read (tinted blue, never black)."""
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=radius, fill_type="NGON", location=(0, 0, z))
    disc = bpy.context.active_object
    disc.name = name
    disc.data.materials.append(principled("M_Ground", color("#6F8796"), 0.8))
    return disc


def camera(name="ReviewCam", lens=60.0):
    cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
    cam.data.lens = lens
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam


def aim(cam, target, distance, yaw_deg, pitch_deg):
    """Place `cam` on a sphere around `target`. yaw 0 looks at the creature's face (+Y side)."""
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    offset = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam.location = Vector(target) + offset * distance
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()


def render_to(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def override_materials(objects, mat):
    """Swap every material slot on `objects` to `mat`; returns a restore function."""
    saved = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        for i, slot in enumerate(obj.material_slots):
            saved.append((obj, i, slot.material))
            slot.material = mat
        if not obj.material_slots:
            obj.data.materials.append(mat)
            saved.append((obj, None, None))

    def restore():
        for obj, i, m in saved:
            if i is None:
                obj.data.materials.clear()
            else:
                obj.material_slots[i].material = m
    return restore


def turntable(prefix, target=(0, 0, 0), distance=3.2, frames=8, pitch=18.0, clay=True, beauty=True):
    """Render `frames` views orbiting the creature, clay and/or beauty. Returns written paths."""
    cam = bpy.context.scene.camera or camera()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name != "Ground"]
    written = []
    passes = ([("clay", True)] if clay else []) + ([("beauty", False)] if beauty else [])
    for label, use_clay in passes:
        restore = override_materials(meshes, clay_material()) if use_clay else None
        for i in range(frames):
            # Start from a 3/4 front view so frame 0 is the hero angle.
            aim(cam, target, distance, 35 + i * 360.0 / frames, pitch)
            path = os.path.join(RENDER_DIR, f"{prefix}_{label}_{i:02d}.png")
            render_to(path)
            written.append(path)
        if restore:
            restore()
    return written


def silhouette(prefix, target=(0, 0, 0), resolution=(1920, 1080), crop=360):
    """Black-on-white render from the gameplay camera, cropped around the creature.

    Shows what the player actually sees at 1080p: the creature's pixel height is the
    readability check from section 2.
    """
    scene = bpy.context.scene
    cam = scene.camera or camera()
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(GAME_CAMERA["fov_deg"])
    # The game camera trails the cell; yaw 180 puts it behind the tail.
    aim(cam, target, GAME_CAMERA["distance"], 180.0, GAME_CAMERA["pitch_deg"])
    meshes = [o for o in scene.objects if o.type == "MESH" and o.name != "Ground"]
    ground = scene.objects.get("Ground")
    if ground:
        ground.hide_render = True
    black = principled("M_Silhouette", (0, 0, 0, 1), 1.0)
    restore = override_materials(meshes, black)
    world = scene.world
    old = tuple(world.node_tree.nodes["Background"].inputs["Color"].default_value)
    old_strength = world.node_tree.nodes["Background"].inputs["Strength"].default_value
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    lights = [o for o in scene.objects if o.type == "LIGHT"]
    for light in lights:
        light.hide_render = True
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.use_border = True
    scene.render.use_crop_to_border = True
    half_w, half_h = crop / 2 / resolution[0], crop / 2 / resolution[1]
    scene.render.border_min_x, scene.render.border_max_x = 0.5 - half_w, 0.5 + half_w
    scene.render.border_min_y, scene.render.border_max_y = 0.5 - half_h, 0.5 + half_h
    samples = scene.cycles.samples
    scene.cycles.samples = 8
    view = scene.view_settings.view_transform
    scene.view_settings.view_transform = "Standard"
    path = os.path.join(RENDER_DIR, f"{prefix}_silhouette.png")
    render_to(path)
    # Restore everything for later renders.
    scene.view_settings.view_transform = view
    scene.cycles.samples = samples
    scene.render.use_border = False
    scene.render.use_crop_to_border = False
    for light in lights:
        light.hide_render = False
    world.node_tree.nodes["Background"].inputs["Color"].default_value = old
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = old_strength
    if ground:
        ground.hide_render = False
    restore()
    cam.data.sensor_fit = "AUTO"
    return path


def membrane_material(name, back="rust", body="coral", belly="cream", spots="mineral_amber", z_range=(-0.45, 0.4)):
    """Procedural membrane (section 4): back-to-belly gradient, soft mottling and back spots.

    Built from object-space coordinates so it can be baked to an albedo/ORM pair for glTF.
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]

    coords = nodes.new("ShaderNodeTexCoord")
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coords.outputs["Object"], xyz.inputs["Vector"])

    height = nodes.new("ShaderNodeMapRange")
    height.inputs["From Min"].default_value, height.inputs["From Max"].default_value = z_range
    links.new(xyz.outputs["Z"], height.inputs["Value"])

    ramp = nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, color(belly)
    els[1].position, els[1].color = 1.0, color(back)
    mid = els.new(0.5)
    mid.color = color(body)
    links.new(height.outputs["Result"], ramp.inputs["Fac"])

    # Soft mottling: low-frequency noise darkens and lightens the membrane a little.
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 5.0
    noise.inputs["Detail"].default_value = 3.0
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    mottle = nodes.new("ShaderNodeMix")
    mottle.data_type = "RGBA"
    mottle.blend_type = "OVERLAY"
    mottle.inputs["Factor"].default_value = 0.3
    links.new(ramp.outputs["Color"], mottle.inputs["A"])
    links.new(noise.outputs["Fac"], mottle.inputs["B"])

    # Bead-sized spots only on the upper body (the "beads" of the shape language).
    vor = nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 7.0
    vor.inputs["Randomness"].default_value = 0.8
    links.new(coords.outputs["Object"], vor.inputs["Vector"])
    spot = nodes.new("ShaderNodeMapRange")
    spot.inputs["From Min"].default_value, spot.inputs["From Max"].default_value = 0.20, 0.13
    links.new(vor.outputs["Distance"], spot.inputs["Value"])
    upper = nodes.new("ShaderNodeMapRange")
    upper.inputs["From Min"].default_value, upper.inputs["From Max"].default_value = 0.55, 0.8
    links.new(height.outputs["Result"], upper.inputs["Value"])
    spot_mask = nodes.new("ShaderNodeMath")
    spot_mask.operation = "MULTIPLY"
    links.new(spot.outputs["Result"], spot_mask.inputs[0])
    links.new(upper.outputs["Result"], spot_mask.inputs[1])
    spotted = nodes.new("ShaderNodeMix")
    spotted.data_type = "RGBA"
    spotted.inputs["B"].default_value = color(spots)
    links.new(spot_mask.outputs["Value"], spotted.inputs["Factor"])
    links.new(mottle.outputs["Result"], spotted.inputs["A"])
    links.new(spotted.outputs["Result"], bsdf.inputs["Base Color"])

    # Roughness: waxy, slightly glossier on the spots.
    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value, rough.inputs["To Max"].default_value = 0.52, 0.34
    links.new(spot_mask.outputs["Value"], rough.inputs["Value"])
    links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def tint_region(mat, centre, radius, tint, strength=1.0, axis=None):
    """Blend `tint` into a membrane's base color near `centre` (object space).

    With `axis` ("X", "Y" or "Z") the blend runs along that axis instead, from `centre` (that
    axis' coordinate, no tint) to `centre + radius` (full tint); radius may be negative.
    """
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    source = bsdf.inputs["Base Color"].links[0].from_socket
    coords = next(n for n in nodes if n.bl_idname == "ShaderNodeTexCoord")
    falloff = nodes.new("ShaderNodeMapRange")
    if axis:
        xyz = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], xyz.inputs["Vector"])
        links.new(xyz.outputs[axis], falloff.inputs["Value"])
        falloff.inputs["From Min"].default_value, falloff.inputs["From Max"].default_value = centre, centre + radius
        falloff.inputs["To Max"].default_value = strength
    else:
        dist = nodes.new("ShaderNodeVectorMath")
        dist.operation = "DISTANCE"
        dist.inputs[1].default_value = centre
        links.new(coords.outputs["Object"], dist.inputs[0])
        links.new(dist.outputs["Value"], falloff.inputs["Value"])
        falloff.inputs["From Min"].default_value, falloff.inputs["From Max"].default_value = 0.0, radius
        falloff.inputs["To Min"].default_value, falloff.inputs["To Max"].default_value = strength, 0.0
    falloff.interpolation_type = "SMOOTHSTEP"
    blend = nodes.new("ShaderNodeMix")
    blend.data_type = "RGBA"
    blend.inputs["B"].default_value = tint
    links.new(falloff.outputs["Result"], blend.inputs["Factor"])
    links.new(source, blend.inputs["A"])
    links.new(blend.outputs["Result"], bsdf.inputs["Base Color"])
    return blend
