"""Build a standalone, original nest-straw art candidate in Blender 5.2.

Run only after the coordinator releases the render window:
    blender --background --python assets/godfrey/nest-straw/build_nest.py
No externally sourced mesh or textures are used. The CC0 photograph is visual reference only.
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
PHASE = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "final"
if PHASE not in ("gray", "final"):
    raise ValueError("Phase must be gray or final")
RNG = random.Random(20261024)
VERTS: list[tuple[float, float, float]] = []
FACES: list[tuple[int, ...]] = []
FACE_MATS: list[int] = []
UVS: list[tuple[float, float]] = []


def add_vertex(xyz, uv):
    VERTS.append(tuple(xyz))
    UVS.append(tuple(uv))
    return len(VERTS) - 1


def add_face(indices, material):
    FACES.append(tuple(indices))
    FACE_MATS.append(material)


def woven_strip(path, width, material, sides=4):
    """A tapered swept fiber with actual volume and an unpainted physical overlap."""
    pts = [Vector(p) for p in path]
    rings = []
    for i, p in enumerate(pts):
        tangent = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = tangent.cross(Vector((0, 0, 1))).normalized()
        if side.length < 0.001:
            side = Vector((1, 0, 0))
        up = tangent.cross(side).normalized()
        taper = 0.38 if i in (0, len(pts) - 1) else 1.0
        ring = []
        for j in range(sides):
            angle = 2 * math.pi * j / sides
            q = p + (side * math.cos(angle) + up * math.sin(angle)) * width * taper
            ring.append(add_vertex(q, (i / max(1, len(pts) - 1), j / sides)))
        rings.append(ring)
    for first, second in zip(rings[:-1], rings[1:]):
        for j in range(sides):
            add_face((first[j], first[(j + 1) % sides],
                      second[(j + 1) % sides], second[j]), material)
    add_face(tuple(reversed(rings[0])), material)
    add_face(tuple(rings[-1]), material)


def base_web():
    """A concave lower basket, not a flat black insert."""
    rings = []
    for radius, height in ((0.025, 0.045), (0.16, 0.055), (0.27, 0.085), (0.36, 0.145)):
        ring = []
        for i in range(16):
            a = 2 * math.pi * i / 16
            jitter = 1 + 0.025 * math.sin(3 * a + 0.8)
            x = 0.95 * radius * jitter * math.cos(a)
            y = 0.85 * radius * jitter * math.sin(a)
            z = height + 0.006 * math.sin(5 * a)
            ring.append(add_vertex((x, y, z), (x + 0.5, y + 0.5)))
        rings.append(ring)
    for first, second in zip(rings[:-1], rings[1:]):
        for i in range(16):
            add_face((first[i], first[(i + 1) % 16],
                      second[(i + 1) % 16], second[i]), 2)


def build_geometry():
    base_web()

    # Radial reeds tie the central well to an irregular wide rim.
    for i in range(12):
        a = 2 * math.pi * (i + RNG.uniform(-0.16, 0.16)) / 12
        path = []
        for j, r in enumerate((0.10, 0.19, 0.29, 0.38, 0.46)):
            wobble = 0.014 * math.sin(2 * j + i)
            theta = a + wobble
            z = (0.048, 0.060, 0.100, 0.170, 0.225)[j] + RNG.uniform(-0.009, 0.009)
            path.append((0.95 * r * math.cos(theta), 0.85 * r * math.sin(theta), z))
        woven_strip(path, RNG.uniform(0.012, 0.021), i % 3 if i % 4 == 0 else i % 2)

    # Long overlapping bands. In section they cross at distinct heights.
    for i in range(17):
        start = 2 * math.pi * (i / 17) + RNG.uniform(-0.22, 0.22)
        sweep = RNG.uniform(1.15, 2.25)
        radius = RNG.uniform(0.31, 0.45)
        z_base = RNG.uniform(0.16, 0.225)
        path = []
        for j in range(6):
            a = start + sweep * j / 5
            r = radius + 0.017 * math.sin(3 * a + i)
            z = z_base + 0.012 * math.sin(2 * a + i)
            path.append((0.95 * r * math.cos(a), 0.85 * r * math.sin(a), z))
        woven_strip(path, RNG.uniform(0.016, 0.026), i % 3 if i % 5 == 0 else i % 2)

    # A few outward stalks puncture the silhouette. They do not form a uniform fringe.
    for i, a in enumerate((0.2, 0.9, 1.55, 2.28, 3.4, 4.45, 5.16, 5.72)):
        a += RNG.uniform(-0.11, 0.11)
        reach = RNG.uniform(0.51, 0.63)
        z0 = RNG.uniform(0.18, 0.23)
        path = [
            (0.95 * 0.36 * math.cos(a), 0.85 * 0.36 * math.sin(a), z0),
            (0.95 * 0.44 * math.cos(a + 0.08), 0.85 * 0.44 * math.sin(a + 0.08), z0 + 0.055),
            (0.95 * reach * math.cos(a + 0.17), 0.85 * reach * math.sin(a + 0.17), z0 + RNG.uniform(0.07, 0.17)),
        ]
        woven_strip(path, 0.008 + 0.002 * (i % 3), 2, sides=3)

    mesh = bpy.data.meshes.new("Nest_Original_Woven_Mesh")
    mesh.from_pydata(VERTS, [], FACES)
    mesh.update()
    # Put the lowest physical fiber on the ground plane while leaving the
    # object origin at the footprint center for predictable Godot placement.
    floor = min(vertex.co.z for vertex in mesh.vertices)
    for vertex in mesh.vertices:
        vertex.co.z -= floor
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly, material in zip(mesh.polygons, FACE_MATS):
        poly.material_index = material
        for loop_idx in poly.loop_indices:
            uv_layer.data[loop_idx].uv = UVS[mesh.loops[loop_idx].vertex_index]
    obj = bpy.data.objects.new("Nest_Export", mesh)
    return obj


def pbr(name, rgb, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    mat.diffuse_color = (*rgb, 1.0)
    return mat


def camera_at(azimuth, elevation, name):
    camera_data = bpy.data.cameras.new(name)
    camera = bpy.data.objects.new(name, camera_data)
    bpy.context.scene.collection.objects.link(camera)
    radius = 1.7
    camera.location = (radius * math.cos(azimuth), radius * math.sin(azimuth),
                       radius * math.tan(elevation))
    target = Vector((0.0, 0.0, 0.13))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.53
    return camera


def add_area(name, location, energy, size):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (-obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = energy
    data.shape = "DISK"
    data.size = size


def render(path, camera):
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.render.resolution_x = 960
    scene.render.resolution_y = 636
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (0.36, 0.38, 0.40)
    scene.view_settings.view_transform = "AgX"

    nest = build_geometry()
    export_collection = bpy.data.collections.new("EXPORT_ONLY")
    scene.collection.children.link(export_collection)
    export_collection.objects.link(nest)
    neutral = pbr("Gray_Shape", (0.46, 0.46, 0.46), 0.82)
    final_mats = (
        pbr("Warm_Reed", (0.44, 0.27, 0.105), 0.84),
        pbr("Pale_Fiber", (0.62, 0.43, 0.19), 0.88),
        pbr("Dark_Twig", (0.16, 0.105, 0.052), 0.91),
    )
    for _ in range(3):
        nest.data.materials.append(neutral)

    cameras = {
        "threequarter": camera_at(-0.75, 0.43, "Review_ThreeQuarter"),
        "front": camera_at(-math.pi / 2, 0.12, "Review_Front"),
        "side": camera_at(0.0, 0.15, "Review_Side"),
        "top": camera_at(-math.pi / 2, 1.35, "Review_Top"),
    }
    add_area("Neutral_Key", (0.3, -1.5, 2.5), 340, 2.4)
    add_area("Neutral_Fill", (-1.2, 0.5, 1.6), 180, 2.0)
    add_area("Grazing", (1.6, 0.7, 0.85), 130, 1.0)

    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "nest-straw-blockout.blend"))
    if PHASE == "gray":
        for view in ("threequarter", "front", "side"):
            render(OUT / f"gray-{view}.png", cameras[view])
        print("GRAY_PHASE_COMPLETE")
        return

    nest.data.materials.clear()
    for mat in final_mats:
        nest.data.materials.append(mat)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "nest-straw.blend"))
    for view in ("threequarter", "top"):
        render(OUT / f"material-{view}.png", cameras[view])

    bpy.ops.object.select_all(action="DESELECT")
    nest.select_set(True)
    bpy.context.view_layer.objects.active = nest
    bpy.ops.export_scene.gltf(filepath=str(OUT / "nest-straw.glb"),
                              export_format="GLB", use_selection=True,
                              export_apply=True)

    tri_count = sum(len(poly.vertices) - 2 for poly in nest.data.polygons)
    extents = [round(v, 4) for v in nest.dimensions]
    report = {
        "status": "candidate_pending_visual_review",
        "blender": bpy.app.version_string,
        "triangles": tri_count,
        "triangle_budget": 2000,
        "materials": [m.name for m in final_mats],
        "texture_files": [],
        "dimensions_blender_m": extents,
        "origin": "bottom-center",
        "front": "+Y",
        "up": "+Z",
        "export": "nest-straw.glb",
    }
    (OUT / "mesh-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
