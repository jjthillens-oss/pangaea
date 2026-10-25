"""Author an original dense bronzeleaf bush in Blender 5.2.2.

Run in this directory: blender --background --python build.py
Only the authored mesh is selected for GLB export. Review cameras/lights stay in
the editable .blend, and a separate gray-state .blend records the shape gate.
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


def pbr(name, color, roughness):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*color, 1.0)
    node.inputs["Roughness"].default_value = roughness
    node.inputs["Metallic"].default_value = 0.0
    return material


wood = pbr("bronzeleaf fibrous stem", (0.27, 0.20, 0.16), 0.91)
bronze = pbr("bronze-purple upper leaf", (0.31, 0.18, 0.23), 0.78)
olive = pbr("muted olive lower leaf", (0.31, 0.39, 0.20), 0.83)
clay = pbr("neutral shape clay", (0.49, 0.47, 0.43), 0.65)

vertices = []
faces = []
face_materials = []


def face(points, material_index):
    first = len(vertices)
    vertices.extend(tuple(point) for point in points)
    faces.append(tuple(range(first, len(vertices))))
    face_materials.append(material_index)


def stem(start, end, bottom_radius, top_radius):
    """Five-sided tapered wood sections, including their visible end caps."""
    start, end = Vector(start), Vector(end)
    axis = (end - start).normalized()
    helper = Vector((0, 1, 0)) if abs(axis.y) < 0.92 else Vector((1, 0, 0))
    u = axis.cross(helper).normalized()
    v = axis.cross(u).normalized()
    ring_a = [start + bottom_radius * (math.cos(t) * u + math.sin(t) * v)
              for t in [2 * math.pi * i / 5 for i in range(5)]]
    ring_b = [end + top_radius * (math.cos(t) * u + math.sin(t) * v)
              for t in [2 * math.pi * i / 5 for i in range(5)]]
    for i in range(5):
        j = (i + 1) % 5
        face((ring_a[i], ring_a[j], ring_b[j], ring_b[i]), 0)
    face(tuple(reversed(ring_a)), 0)
    face(tuple(ring_b), 0)


def lance_leaf(anchor, azimuth, length, width, lift, sweep, material_index):
    """A pointed, recurved broad leaf with center ridge and visible back.

    The four triangles on each side have actual bent vertices. This geometry,
    not an alpha cutout or noise material, carries the crown silhouette.
    """
    anchor = Vector(anchor)
    radial = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
    across = Vector((-radial.y, radial.x, 0.0))
    base = anchor
    left = anchor + radial * (length * 0.44) + across * (width * 0.49) + Vector((0, 0, lift * 0.43))
    right = anchor + radial * (length * 0.44) - across * (width * 0.49) + Vector((0, 0, lift * 0.43))
    ridge = anchor + radial * (length * 0.45) + across * sweep + Vector((0, 0, lift * 0.49 + width * 0.14))
    tip = anchor + radial * length + across * sweep * 1.7 + Vector((0, 0, lift - length * 0.13))
    face((base, left, ridge), material_index)
    face((base, ridge, right), material_index)
    face((left, tip, ridge), material_index)
    face((ridge, tip, right), material_index)
    back = Vector((0, 0, -0.003))
    face((ridge + back, left + back, base + back), material_index)
    face((right + back, ridge + back, base + back), material_index)
    face((ridge + back, tip + back, left + back), material_index)
    face((right + back, tip + back, ridge + back), material_index)


# Designed crown centers, not traced photo coordinates. Each stem has a distinct
# height, depth and lean; a tall center is balanced by shorter offset crowns.
crowns = [
    ((0.00, 0.00, 0.03), (0.05, 0.03, 1.61), 4, 11, 0.34),
    ((-0.31, -0.05, 0.02), (-0.44, -0.13, 1.15), 3, 9, 0.31),
    ((0.30, 0.06, 0.02), (0.43, 0.19, 1.24), 3, 9, 0.31),
    ((-0.34, 0.13, 0.02), (-0.57, 0.32, 0.73), 2, 7, 0.24),
    ((0.24, -0.15, 0.02), (0.52, -0.27, 0.78), 2, 7, 0.24),
]

for crown_index, (base, apex, tiers, leaves_per_tier, reach) in enumerate(crowns):
    base, apex = Vector(base), Vector(apex)
    mid = base.lerp(apex, 0.50)
    mid.x += 0.018 * (1 if crown_index % 2 else -1)
    stem(base, mid, 0.050 if crown_index == 0 else 0.033, 0.027)
    stem(mid, apex, 0.027, 0.008)
    for tier in range(tiers):
        fraction = 0.24 + tier * (0.62 / max(1, tiers - 1))
        center = base.lerp(apex, fraction)
        count = leaves_per_tier - (1 if tier == tiers - 1 else 0)
        for index in range(count):
            angle = 2 * math.pi * (index + 0.43 * (tier % 2)) / count
            angle += crown_index * 0.31 + tier * 0.11
            variation = 0.91 + 0.12 * ((index * 7 + tier * 3 + crown_index) % 5) / 4
            length = reach * variation * (0.92 if tier == tiers - 1 else 1.0)
            width = length * (0.31 + 0.05 * ((index + tier) % 3))
            lift = length * (0.44 if tier == tiers - 1 else 0.21)
            # Lower tiers keep olive undertones; upper crowns make the bronze
            # region visible at gameplay distance without a painted highlight.
            material_index = 2 if tier == 0 or (tier == 1 and index % 4 == 0) else 1
            lance_leaf(center, angle, length, width, lift,
                       0.012 * ((index % 3) - 1), material_index)

mesh = bpy.data.meshes.new("bronzeleaf_crown_mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
plant = bpy.data.objects.new("Bush 2 - dense bronzeleaf", mesh)
bpy.context.collection.objects.link(plant)
materials = (wood, bronze, olive)
for material in materials:
    mesh.materials.append(material)
for polygon, material_index in zip(mesh.polygons, face_materials):
    polygon.material_index = material_index

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 800
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = True
scene.view_settings.view_transform = "Standard"

scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = (0.52, 0.55, 0.59, 1.0)
background.inputs["Strength"].default_value = 0.55


def area_light(name, position, energy, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    item = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(item)
    item.location = position
    item.rotation_euler = (Vector((0, 0, 0.83)) - item.location).to_track_quat("-Z", "Y").to_euler()


area_light("neutral broad key", (-2.2, -2.0, 3.3), 400, 3.2)
area_light("neutral cool fill", (2.6, 1.7, 2.0), 180, 2.7)
camera_data = bpy.data.cameras.new("review camera")
camera = bpy.data.objects.new("review camera", camera_data)
bpy.context.collection.objects.link(camera)
camera_data.type = "ORTHO"
camera_data.ortho_scale = 2.5
scene.camera = camera


def render(label, position):
    camera.location = position
    camera.rotation_euler = (Vector((0, 0, 0.83)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(VIEWS / label)
    bpy.ops.render.render(write_still=True)


angles = {"front": (0, -4.0, 1.65), "side": (4.0, 0, 1.65),
          "three-quarter": (3.0, -3.0, 2.7), "game-distance": (0, -8.0, 6.5)}

# Gate 1 is deliberately saved and rendered before the material pass.
mesh.materials.clear()
mesh.materials.append(clay)
for polygon in mesh.polygons:
    polygon.material_index = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "bush-2-shape.blend"))
for label, position in angles.items():
    render("gray-" + label + ".png", position)

mesh.materials.clear()
for material in materials:
    mesh.materials.append(material)
for polygon, material_index in zip(mesh.polygons, face_materials):
    polygon.material_index = material_index
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "bush-2.blend"))
for label, position in angles.items():
    render("material-" + label + ".png", position)

bpy.ops.object.select_all(action="DESELECT")
plant.select_set(True)
bpy.context.view_layer.objects.active = plant
bpy.ops.export_scene.gltf(filepath=str(ROOT / "bush-2.glb"), export_format="GLB", use_selection=True)

report = {
    "asset": "Bush 2 - dense bronzeleaf",
    "vertices": len(mesh.vertices),
    "triangles": sum(len(polygon.vertices) - 2 for polygon in mesh.polygons),
    "materials": [material.name for material in materials],
    "bounds_min_m": [min(vertex.co[axis] for vertex in mesh.vertices) for axis in range(3)],
    "bounds_max_m": [max(vertex.co[axis] for vertex in mesh.vertices) for axis in range(3)],
    "texture_count": 0,
    "notes": "Original Blender geometry; Z up, radial shrub with no rig.",
}
(ROOT / "geometry-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
