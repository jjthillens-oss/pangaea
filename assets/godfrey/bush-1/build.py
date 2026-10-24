"""Build an original, deterministic low-poly flowering shrub in Blender.

Run from this directory with: blender --background --python build.py
The script deliberately has no network or external asset dependency.
"""

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parent
VIEWS = ROOT / "views"
VIEWS.mkdir(exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, rgb, roughness=0.87):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0
    return mat


wood = material("weathered gray brown wood", (0.30, 0.28, 0.22))
leaf = material("muted sage leaf", (0.38, 0.48, 0.29))
flower = material("blue violet flower", (0.27, 0.24, 0.60))
gray = material("shape review gray", (0.46, 0.46, 0.46))

verts = []
faces = []
mat_ids = []


def polygon(points, mat_id):
    """Emit a polygon with explicit geometry and one material slot."""
    first = len(verts)
    verts.extend(tuple(p) for p in points)
    faces.append(tuple(range(first, len(verts))))
    mat_ids.append(mat_id)


def tapered_stem(a, b, bottom_radius, top_radius, sides=5):
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    helper = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(helper).normalized()
    v = axis.cross(u).normalized()
    base = [a + bottom_radius * (math.cos(2 * math.pi * i / sides) * u + math.sin(2 * math.pi * i / sides) * v) for i in range(sides)]
    tip = [b + top_radius * (math.cos(2 * math.pi * i / sides) * u + math.sin(2 * math.pi * i / sides) * v) for i in range(sides)]
    for i in range(sides):
        j = (i + 1) % sides
        polygon((base[i], base[j], tip[j], tip[i]), 0)


def narrow_leaf(center, outward, length, width, twist):
    """A bent lens with thickness and its own two-sided triangulated geometry."""
    center = Vector(center)
    outward = Vector(outward).normalized()
    across = Vector((-outward.y, outward.x, twist)).normalized()
    root = center
    left = center + outward * (length * 0.43) + across * (width * 0.5)
    right = center + outward * (length * 0.43) - across * (width * 0.5)
    ridge = center + outward * (length * 0.47) + Vector((0, 0, width * 0.17))
    tip = center + outward * length + Vector((0, 0, length * 0.10))
    polygon((root, left, ridge), 1)
    polygon((root, ridge, right), 1)
    polygon((left, tip, ridge), 1)
    polygon((ridge, tip, right), 1)
    # A thin back surface remains visible from the opposite game-camera side.
    offset = Vector((0, 0, -0.003))
    polygon((ridge + offset, left + offset, root + offset), 1)
    polygon((right + offset, ridge + offset, root + offset), 1)
    polygon((ridge + offset, tip + offset, left + offset), 1)
    polygon((right + offset, tip + offset, ridge + offset), 1)


def small_bloom(center, angle):
    center = Vector(center)
    direction = Vector((math.cos(angle), math.sin(angle), 0.08)).normalized()
    across = Vector((-direction.y, direction.x, 0.10)).normalized()
    stem_tip = center + Vector((0, 0, 0.035))
    polygon((stem_tip, stem_tip + direction * 0.052 + across * 0.026,
             stem_tip + direction * 0.082, stem_tip + direction * 0.052 - across * 0.026), 2)
    polygon((stem_tip + direction * 0.03 + across * 0.014,
             stem_tip + direction * 0.068 + across * 0.045,
             stem_tip + direction * 0.074 + across * 0.005), 2)


# Seven distinct primary fans plus a lower outward branch. These are designed
# positions, not contours traced from the reference photo.
fans = [
    ((-0.035, 0.000, 0.09), (-0.72, -0.02, 0.78), (-0.83, -0.08, 1.10)),
    ((-0.025, 0.005, 0.10), (-0.48, 0.16, 0.92), (-0.52, 0.22, 1.22)),
    ((0.000, -0.015, 0.12), (-0.23, -0.13, 0.94), (-0.18, -0.18, 1.27)),
    ((0.015, 0.010, 0.10), (0.09, 0.26, 0.88), (0.16, 0.36, 1.14)),
    ((0.028, -0.010, 0.10), (0.34, -0.21, 0.78), (0.42, -0.33, 1.04)),
    ((0.025, 0.020, 0.12), (0.56, 0.13, 0.70), (0.66, 0.18, 0.93)),
    ((0.005, -0.025, 0.09), (0.68, -0.25, 0.43), (0.87, -0.30, 0.48)),
]

# Root knot: short leaning stems make an irregular base rather than a sphere.
for i, (root, middle, tip) in enumerate(fans):
    tapered_stem(root, middle, 0.047 - i * 0.003, 0.020, 6)
    tapered_stem(middle, tip, 0.022, 0.007, 5)
    m = Vector(middle)
    t = Vector(tip)
    axis = (t - m).normalized()
    for k in range(3):
        fraction = 0.22 + k * 0.25
        anchor = m.lerp(t, fraction)
        side = -1 if (i + k) % 2 else 1
        azimuth = (i * 0.87 + k * 1.42)
        splay = Vector((math.cos(azimuth) * side, math.sin(azimuth) * side, 0.28))
        twig_tip = anchor + splay * (0.13 + 0.02 * ((i + k) % 3)) + axis * 0.05
        tapered_stem(anchor, twig_tip, 0.009, 0.002, 5)
        for n in range(2):
            location = anchor.lerp(twig_tip, 0.47 + n * 0.31)
            outward = splay + Vector((0.19 * (-1 if n else 1), 0.09, 0.10))
            narrow_leaf(location, outward, 0.105 + 0.013 * ((i + n) % 3), 0.034, 0.16 * side)
        if (i * 3 + k) % 5 == 0:
            small_bloom(twig_tip, azimuth)

mesh = bpy.data.meshes.new("flowering_sage_original_mesh")
mesh.from_pydata(verts, [], faces)
mesh.update()
shrub = bpy.data.objects.new("Bush 1 - airy flowering sage", mesh)
bpy.context.collection.objects.link(shrub)
for mat in (wood, leaf, flower):
    mesh.materials.append(mat)
for face, mat_id in zip(mesh.polygons, mat_ids):
    face.material_index = mat_id

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes.get("Background").inputs["Color"].default_value = (0.55, 0.57, 0.60, 1)
world.node_tree.nodes.get("Background").inputs["Strength"].default_value = 0.5

light_data = bpy.data.lights.new("neutral softbox", "AREA")
light = bpy.data.objects.new("neutral softbox", light_data)
bpy.context.collection.objects.link(light)
light.location = (1.8, -2.5, 3.8)
light_data.energy = 350
light_data.shape = "DISK"
light_data.size = 3

camera_data = bpy.data.cameras.new("review camera")
camera = bpy.data.objects.new("review camera", camera_data)
bpy.context.collection.objects.link(camera)
bpy.context.scene.camera = camera
camera_data.type = "ORTHO"
camera_data.ortho_scale = 2.2

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 800
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = True


def render_view(name, position):
    camera.location = position
    target = Vector((0, 0, 0.67))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(VIEWS / name)
    bpy.ops.render.render(write_still=True)


view_positions = {
    "front": (0, -3.7, 1.15),
    "side": (3.7, 0, 1.15),
    "three_quarter": (2.7, -3.1, 2.1),
}

# Preserve a shape-only editable state and evidence before material identity.
original_materials = list(mesh.materials)
mesh.materials.clear()
mesh.materials.append(gray)
for poly in mesh.polygons:
    poly.material_index = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "bush-1-shape.blend"))
for label, position in view_positions.items():
    render_view(f"gray-{label}.png", position)

mesh.materials.clear()
for mat in original_materials:
    mesh.materials.append(mat)
for poly, mat_id in zip(mesh.polygons, mat_ids):
    poly.material_index = mat_id
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "bush-1.blend"))
for label, position in view_positions.items():
    render_view(f"material-{label}.png", position)

bpy.ops.object.select_all(action="DESELECT")
shrub.select_set(True)
bpy.context.view_layer.objects.active = shrub
bpy.ops.export_scene.gltf(filepath=str(ROOT / "bush-1.glb"), export_format="GLB", use_selection=True)

report = {
    "asset": "Bush 1 - airy flowering sage",
    "vertices": len(mesh.vertices),
    "triangles": sum(len(poly.vertices) - 2 for poly in mesh.polygons),
    "materials": [mat.name for mat in original_materials],
    "bounds_min_m": [min(v.co[i] for v in mesh.vertices) for i in range(3)],
    "bounds_max_m": [max(v.co[i] for v in mesh.vertices) for i in range(3)],
    "notes": "Designed original geometry; Blender Z-up; glTF Godot conversion handles Y-up.",
}
(ROOT / "geometry-report.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
