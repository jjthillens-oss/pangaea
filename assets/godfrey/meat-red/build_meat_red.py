"""Build an original, matte, stylized red-meat food prop in Blender 5.2.2.

Run only after the shared render window is released:
    blender --background --python build_meat_red.py

The CC0 photograph is a visual reference, never mapped onto the mesh.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


OUT = Path(__file__).resolve().parent
SEGMENTS = 48
MAIN = []


def material(name, color, roughness=0.84):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


muscle = material("muscle_muted_berry", (0.30, 0.065, 0.087))
muscle_dark = material("muscle_soft_burgundy", (0.21, 0.047, 0.067))
fat = material("fat_warm_ivory", (0.77, 0.62, 0.55), 0.9)
clay = material("review_neutral_clay", (0.46, 0.46, 0.44), 0.83)


def outline(theta):
    """Low-frequency lobes and one deliberate inward shoulder notch."""
    broad = 1.0 + 0.085 * math.sin(3 * theta + 0.15)
    broad += 0.052 * math.sin(5 * theta - 0.75)
    broad += 0.022 * math.sin(9 * theta + 0.40)
    notch = 0.17 * math.exp(-((theta - 2.45) / 0.20) ** 2)
    return broad - notch


def point(theta, fraction, z):
    radial = outline(theta) * fraction
    x = 0.36 * radial * math.cos(theta)
    y = 0.31 * radial * math.sin(theta)
    # Asymmetric placement avoids a manufactured ellipse while keeping a flat base.
    x += 0.018 * fraction * math.sin(2 * theta - 0.3)
    y += 0.012 * fraction * math.sin(3 * theta + 0.7)
    return (x, y, z)


def build_body():
    vertices = [(0.012, -0.013, 0.159)]
    rings = []
    for layer, fraction in enumerate((0.28, 0.63, 1.0)):
        ring = []
        for i in range(SEGMENTS):
            angle = i * 2 * math.pi / SEGMENTS
            broad_fold = 0.014 * math.sin(3 * angle + 0.6)
            shallow_folds = 0.006 * math.sin(7 * angle - 0.4)
            height = (0.157, 0.172, 0.111)[layer]
            height += fraction * (broad_fold + shallow_folds)
            ring.append(len(vertices))
            vertices.append(point(angle, fraction, height))
        rings.append(ring)

    side = []
    for i in range(SEGMENTS):
        angle = i * 2 * math.pi / SEGMENTS
        side.append(len(vertices))
        vertices.append(point(angle, 0.965, 0.025))
    underside_center = len(vertices)
    vertices.append((0.0, 0.0, 0.025))

    faces = []
    for i in range(SEGMENTS):
        nxt = (i + 1) % SEGMENTS
        faces.append((0, rings[0][i], rings[0][nxt]))
    for inner, outer in zip(rings[:-1], rings[1:]):
        for i in range(SEGMENTS):
            nxt = (i + 1) % SEGMENTS
            faces.append((inner[i], outer[i], outer[nxt], inner[nxt]))
    for i in range(SEGMENTS):
        nxt = (i + 1) % SEGMENTS
        faces.append((rings[-1][i], side[i], side[nxt], rings[-1][nxt]))
        faces.append((underside_center, side[nxt], side[i]))

    mesh = bpy.data.meshes.new("hand_shaped_red_meat_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("meat_body", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(muscle)
    mesh.materials.append(muscle_dark)
    for poly in mesh.polygons:
        poly.use_smooth = True
        if 0 < poly.index < SEGMENTS * 2 and poly.index % 17 in (0, 1, 2):
            poly.material_index = 1
    MAIN.append(obj)


def mesh_curve(name, coords, thickness, mat, edge_taper=False):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = thickness
    curve.bevel_resolution = 1
    spline = curve.splines.new("POLY")
    spline.points.add(len(coords) - 1)
    for i, (co, p) in enumerate(zip(coords, spline.points)):
        p.co = (*co, 1.0)
        if edge_taper:
            u = i / (len(coords) - 1)
            p.radius = 0.28 + 0.72 * math.sin(math.pi * u) ** 0.6
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    mesh_obj = bpy.context.view_layer.objects.active
    mesh_obj.data.materials.append(mat)
    MAIN.append(mesh_obj)
    return mesh_obj


def build_rim_and_seams():
    # A partial, tapered edge cuff: no all-around white cartoon outline.
    for start, end, thickness in ((2.75, 4.45, 0.020), (4.72, 5.38, 0.013)):
        coords = []
        for j in range(20):
            a = start + (end - start) * j / 19
            coords.append(point(a, 0.992, 0.103 + 0.009 * math.sin(3 * a)))
        mesh_curve("fat_partial_edge", coords, thickness, fat, True)

    # Restrained branchlike pale seams. Deliberate arcs, no texture repetition.
    seam_paths = (
        ((-0.17, -0.11, 0.178), (-0.09, -0.055, 0.185), (-0.025, 0.005, 0.184), (0.042, 0.047, 0.175)),
        ((-0.035, 0.005, 0.184), (0.005, -0.075, 0.183), (0.095, -0.105, 0.172), (0.16, -0.09, 0.151)),
        ((-0.09, -0.055, 0.185), (-0.13, 0.012, 0.185), (-0.122, 0.082, 0.177)),
    )
    for idx, controls in enumerate(seam_paths):
        coords = []
        for j in range(13):
            u = j / 12
            t = u * (len(controls) - 1)
            k = min(int(t), len(controls) - 2)
            blend = t - k
            left = Vector(controls[k])
            right = Vector(controls[k + 1])
            co = left.lerp(right, blend)
            coords.append(tuple(co))
        mesh_curve(f"fat_seam_{idx + 1}", coords, (0.0055, 0.0045, 0.0035)[idx], fat, True)


def camera(name, at):
    cam_data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = at
    target = Vector((0, 0, 0.09))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.10
    return cam


def light(name, at, power, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = at
    obj.rotation_euler = (Vector((0, 0, 0.1)) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_views(prefix):
    views = {
        "front": (0.0, 1.8, 0.42),
        "side": (1.8, 0.0, 0.42),
        "three-quarter": (1.25, 1.35, 1.10),
        "gameplay": (0.95, 0.70, 2.20),
    }
    for key, place in views.items():
        bpy.context.scene.camera = camera(f"review_camera_{prefix}_{key}", place)
        bpy.context.scene.render.filepath = str(OUT / "renders" / f"{prefix}-{key}.png")
        bpy.ops.render.render(write_still=True)


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
build_body()
build_rim_and_seams()

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.color = (0.22, 0.22, 0.22)
scene.view_settings.view_transform = "AgX"
light("review_key", (1.6, 1.7, 2.3), 380, 2.5)
light("review_fill", (-1.9, -0.6, 1.4), 225, 2.8)
light("review_grazing", (-0.7, 1.5, 0.7), 140, 1.1)
(OUT / "renders").mkdir(exist_ok=True)

saved_slots = {obj: tuple(obj.data.materials) for obj in MAIN}
for obj in MAIN:
    obj.data.materials.clear()
    obj.data.materials.append(clay)
render_views("gray")
for obj in MAIN:
    obj.data.materials.clear()
    for mat in saved_slots[obj]:
        obj.data.materials.append(mat)
render_views("material")

bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "meat-red.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in MAIN:
    obj.select_set(True)
bpy.context.view_layer.objects.active = MAIN[0]
bpy.ops.export_scene.gltf(
    filepath=str(OUT / "meat-red.glb"),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
)
print("MEAT_RED_EXPORT", len(MAIN), "objects", sum(len(o.data.polygons) for o in MAIN), "triangulated-face input polygons")
