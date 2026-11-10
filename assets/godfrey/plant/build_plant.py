"""Build the original Tideleaf marine-flora prop with Blender 5.2.

Run: blender --background --python build_plant.py
The CC0 photo in this folder is visual reference only. Geometry and materials are
authored here from independent parametric curves and are not derived from pixels.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parent
RENDER_DIR = ROOT / "renders"
RENDER_DIR.mkdir(exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for material in tuple(bpy.data.materials):
        bpy.data.materials.remove(material)


def material(name: str, rgb: tuple[float, float, float], roughness: float):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1.0)
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def mesh_object(name: str, vertices, faces, materials, face_materials):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)
    for polygon, index in zip(mesh.polygons, face_materials):
        polygon.material_index = index
        polygon.use_smooth = True
    return obj


def make_fronds(mats):
    vertices, faces, face_mats = [], [], []
    # Deterministic, uneven crown: a dozen lobed marine fronds of three size classes.
    lengths = [1.31, 1.10, 1.44, 0.94, 1.23, 0.83, 1.36, 1.02, 1.15, 0.76, 1.28]
    azimuths = [12, 49, 86, 127, 165, 205, 239, 270, 309, 338, 188]
    for blade, (length, degrees) in enumerate(zip(lengths, azimuths)):
        az = math.radians(degrees)
        radial = Vector((math.cos(az), math.sin(az), 0.0))
        sideways = Vector((-radial.y, radial.x, 0.0))
        lean = 0.20 + 0.28 * (blade % 4) / 3.0
        phase = blade * 1.71
        base = len(vertices)
        for row in range(11):
            t = row / 10.0
            # Three broad lobes offset differently per leaf; no rectangular cards.
            envelope = max(0.035, math.sin(math.pi * t) ** 0.38)
            lobes = 1.0 + 0.22 * math.sin(5.5 * math.pi * t + phase)
            width = (0.16 + 0.075 * (blade % 3)) * envelope * lobes
            center = (
                radial * (0.055 + lean * t * t + 0.035 * math.sin(2.8 * t + phase))
                + sideways * (0.035 * math.sin(3.1 * t + phase))
                + Vector((0, 0, 0.055 + length * t))
            )
            twist = 0.26 * math.sin(2.2 * t + phase)
            normal = sideways * math.cos(twist) + radial * math.sin(twist)
            for col in range(5):
                across = (col - 2) / 2.0
                ripple = 1.0 + (0.06 * math.sin(17.0 * t + phase + col) if abs(across) == 1 else 0)
                point = center + normal * (across * width * ripple)
                point.z += 0.025 * (1.0 - across * across) * envelope
                vertices.append(tuple(point))
        for row in range(10):
            for col in range(4):
                a = base + row * 5 + col
                b = a + 1
                c = a + 5
                d = c + 1
                # Reverse no faces: GLB material is double sided for thin flora.
                faces.extend([(a, c, b), (b, c, d)])
                face_mats.extend([blade % 3, blade % 3])
    return mesh_object("Tideleaf_fronds", vertices, faces, mats, face_mats)


def make_holdfast(mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, location=(0, 0, 0.08))
    obj = bpy.context.object
    obj.name = "Tideleaf_holdfast"
    obj.scale = (0.18, 0.15, 0.085)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def point_camera(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def setup_studio():
    world = bpy.context.scene.world or bpy.data.worlds.new("neutral_world")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.14, 0.16, 0.19, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.name = "Studio_camera_not_exported"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.2
    bpy.context.scene.camera = camera

    for name, location, energy, size in (
        ("Key", (2.6, 3.2, 4.8), 400, 3.0),
        ("Fill", (-3.3, 1.6, 2.2), 260, 3.7),
        ("Rim", (0.5, -3.0, 3.5), 330, 2.8),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = f"Studio_{name}_not_exported"
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        point_camera(light, (0, 0, 0.7))

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.render.film_transparent = False
    return camera


def render_views(camera, model, gray=False):
    positions = {
        "front": (0.0, 3.5, 1.3),
        "side": (3.5, 0.0, 1.3),
        "top": (0.01, 0.0, 4.0),
    }
    originals = [(obj, [slot.material for slot in obj.material_slots]) for obj in model]
    if gray:
        clay = material("temporary_gray_clay", (0.46, 0.47, 0.49), 0.72)
        for obj in model:
            for slot in obj.material_slots:
                slot.material = clay
    for view, position in positions.items():
        camera.location = position
        point_camera(camera, (0, 0, 0.71))
        bpy.context.scene.render.filepath = str(RENDER_DIR / f"{'gray' if gray else 'beauty'}-{view}.png")
        bpy.ops.render.render(write_still=True)
    for obj, materials in originals:
        for slot, mat in zip(obj.material_slots, materials):
            slot.material = mat


def main():
    clear_scene()
    mats = [
        material("Tideleaf_wine", (0.15, 0.025, 0.04), 0.8),
        material("Tideleaf_rose", (0.24, 0.055, 0.07), 0.78),
        material("Tideleaf_copper", (0.18, 0.04, 0.035), 0.82),
    ]
    hold = material("Tideleaf_holdfast_mauve", (0.17, 0.09, 0.1), 0.9)
    model = [make_fronds(mats), make_holdfast(hold)]
    camera = setup_studio()

    # The saved source retains the final glTF-compatible materials and a neutral studio.
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "tideleaf.blend"))
    render_views(camera, model, gray=True)
    render_views(camera, model, gray=False)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in model:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = model[0]
    bpy.ops.export_scene.gltf(
        filepath=str(ROOT / "tideleaf.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print("ASSET_METRICS")
    for obj in model:
        print(f"{obj.name}: vertices={len(obj.data.vertices)} triangles={sum(len(p.vertices)-2 for p in obj.data.polygons)}")


if __name__ == "__main__":
    main()
