"""Build the M0 sample asset: a stylized microscopic cell with attachment sockets.

This is the Blender source of record for `sample_cell`. It writes:
  assets/source/blender/sample_cell.blend   (editable source)
  assets/export/sample_cell.glb             (engine export)
  assets/records/sample_cell.json           (asset record, Bible section 16)

Run with the pinned Blender (see docs/TOOLCHAIN.md):
  blender --background --python tools/blender/make_sample_cell.py
or with the bpy module:
  python tools/blender/make_sample_cell.py

Conventions (verified by tests/test_assets.gd):
  * 1 Blender meter = 1 Godot unit.
  * Creature front faces Blender +Y. After glTF export it faces Godot -Z (Godot's forward).
  * Up is Blender +Z, which becomes Godot +Y.
  * Sockets are empties named socket_<role>; gameplay attaches parts to them by name.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

ASSET_ID = "sample_cell"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_PATH = os.path.join(ROOT, "assets", "source", "blender", f"{ASSET_ID}.blend")
GLB_PATH = os.path.join(ROOT, "assets", "export", f"{ASSET_ID}.glb")
RECORD_PATH = os.path.join(ROOT, "assets", "records", f"{ASSET_ID}.json")


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def material(name, color, roughness=0.5, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.6
    return mat


def smooth(obj, levels=2):
    mod = obj.modifiers.new("Subdivision", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    for poly in obj.data.polygons:
        poly.use_smooth = True


def add_sphere(name, radius, location, scale=(1, 1, 1), segments=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = f"{name}_mesh"
    obj.scale = scale
    return obj


def add_socket(name, location, parent):
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "ARROWS"
    empty.empty_display_size = 0.08
    empty.location = location
    empty.parent = parent
    bpy.context.collection.objects.link(empty)
    return empty


def build():
    m_membrane = material("M_CellMembrane", (0.18, 0.62, 0.52), 0.35)
    m_nucleus = material("M_CellNucleus", (0.08, 0.28, 0.26), 0.6)
    m_eye = material("M_EyeWhite", (0.95, 0.97, 0.94), 0.25)
    m_pupil = material("M_EyePupil", (0.02, 0.03, 0.04), 0.2)
    m_mouth = material("M_MouthLip", (0.12, 0.18, 0.16), 0.5)
    m_flag = material("M_Flagellum", (0.55, 0.85, 0.72), 0.4)

    # Body: slightly elongated along the swim axis (+Y), flattened top to bottom.
    body = add_sphere("Body", 0.5, (0, 0, 0), scale=(0.92, 1.0, 0.78))
    body.data.materials.append(m_membrane)
    smooth(body, 2)

    nucleus = add_sphere("Nucleus", 0.18, (-0.08, -0.12, 0.2), segments=16, rings=8)
    nucleus.data.materials.append(m_nucleus)
    nucleus.parent = body
    smooth(nucleus, 1)

    # Eyes on the upper front, so the creature reads as "looking" where it swims.
    for side, x in (("L", -0.17), ("R", 0.17)):
        eye = add_sphere(f"Eye_{side}", 0.11, (x, 0.34, 0.22), segments=16, rings=8)
        eye.data.materials.append(m_eye)
        eye.parent = body
        smooth(eye, 1)
        pupil = add_sphere(f"Pupil_{side}", 0.055, (x, 0.43, 0.25), segments=12, rings=6)
        pupil.data.materials.append(m_pupil)
        pupil.parent = body

    # Mouth ring at the front.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.1, minor_radius=0.035, location=(0, 0.47, -0.02),
                                     rotation=(math.radians(90), 0, 0), major_segments=24, minor_segments=8)
    mouth = bpy.context.active_object
    mouth.name = "Mouth"
    mouth.data.name = "Mouth_mesh"
    mouth.data.materials.append(m_mouth)
    mouth.parent = body
    for poly in mouth.data.polygons:
        poly.use_smooth = True

    # Flagellum: a tapered S-curve trailing behind (-Y), converted to a mesh.
    curve = bpy.data.curves.new("Flagellum_curve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.035
    curve.bevel_resolution = 3
    curve.resolution_u = 12
    spline = curve.splines.new("BEZIER")
    pts = [(0, -0.45, 0), (0.08, -0.7, 0.02), (-0.08, -0.95, 0.0), (0.03, -1.15, -0.02)]
    spline.bezier_points.add(len(pts) - 1)
    for bp, co in zip(spline.bezier_points, pts):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    for i, bp in enumerate(spline.bezier_points):
        bp.radius = 1.0 - 0.8 * i / (len(pts) - 1)
    flag = bpy.data.objects.new("Flagellum", curve)
    bpy.context.collection.objects.link(flag)
    bpy.context.view_layer.objects.active = flag
    flag.select_set(True)
    bpy.ops.object.convert(target="MESH")
    flag = bpy.context.active_object
    flag.name = "Flagellum"
    flag.data.materials.append(m_flag)
    flag.parent = body
    for poly in flag.data.polygons:
        poly.use_smooth = True

    # Attachment sockets (parented to the body, positions in body-local meters before body scale).
    add_socket("socket_mouth", (0, 0.5, 0), body)
    add_socket("socket_tail", (0, -0.5, 0), body)
    add_socket("socket_top", (0, 0, 0.5), body)
    add_socket("socket_side_L", (-0.5, 0, 0), body)
    add_socket("socket_side_R", (0.5, 0, 0), body)
    return body


def triangle_count():
    depsgraph = bpy.context.evaluated_depsgraph_get()
    total = 0
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.evaluated_get(depsgraph).to_mesh()
        mesh.calc_loop_triangles()
        total += len(mesh.loop_triangles)
        obj.evaluated_get(depsgraph).to_mesh_clear()
    return total


def world_bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def main():
    reset_scene()
    build()
    bpy.context.view_layer.update()
    for path in (BLEND_PATH, GLB_PATH, RECORD_PATH):
        os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, compress=True, relative_remap=True)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    lo, hi = world_bounds()
    size = hi - lo
    record = {
        "id": ASSET_ID,
        "owner": "Joshua Jake",
        "status": "PROPOSED",
        "review_state": "sample - pipeline validation only, not visually approved",
        "purpose": "M0 Blender-to-Godot pipeline check: scale, orientation, materials, sockets.",
        "source_blend": "assets/source/blender/sample_cell.blend",
        "generator_script": "tools/blender/make_sample_cell.py",
        "export_path": "assets/export/sample_cell.glb",
        "export_format": "GLB",
        "dependencies": [],
        "revision": 1,
        "blender_version": bpy.app.version_string,
        "dimensions_m": {"x": round(size.x, 3), "y_forward": round(size.y, 3), "z_up": round(size.z, 3)},
        "triangles": triangle_count(),
        "textures": [],
        "materials": sorted(m.name for m in bpy.data.materials if m.users),
        "rig_family": None,
        "animations": [],
        "sockets": sorted(o.name for o in bpy.data.objects if o.name.startswith("socket_")),
        "provenance": "Authored procedurally in Blender by tools/blender/make_sample_cell.py; no external or generated meshes.",
    }
    with open(RECORD_PATH, "w") as f:
        json.dump(record, f, indent=2)
        f.write("\n")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
    sys.stdout.flush()
