"""Author an original pale food prop in Blender, export only after visual gates.

Run under installed Blender with ``--background --python build.py`` after the
shared Blender window is released. The generated mesh is not a production asset.
"""

from pathlib import Path
import json
import math
import sys
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
EXPORT_NAME = "Pale_Fillet_Cluster"
RING_COUNT = 13
SIDES = 20


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != bpy.context.scene.collection.name and collection.users == 0:
            bpy.data.collections.remove(collection)
    export = bpy.data.collections.new("EXPORT_only")
    review = bpy.data.collections.new("REVIEW_only")
    bpy.context.scene.collection.children.link(export)
    bpy.context.scene.collection.children.link(review)
    return export, review


def material(name, color, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def fillet(export, name, center_x, center_y, angle, length, max_width, height,
           twist, top_material, edge_material, seed):
    verts = []
    faces = []
    face_material = []
    ca, sa = math.cos(angle), math.sin(angle)
    for i in range(RING_COUNT):
        t = i / (RING_COUNT - 1)
        # The long, blunt shoulder is at local +Y; the opposite end pinches.
        local_y = (t - 0.5) * length
        shoulder = math.sin(math.pi * (0.15 + 0.80 * t))
        taper = 0.27 + 0.71 * (t ** 0.58)
        width = max_width * shoulder * taper
        for j in range(SIDES):
            a = 2 * math.pi * j / SIDES
            # A soft, flattened bottom and convex upper ridge; no subsurface shader.
            lateral = math.cos(a) * width
            z = 0.025 + height * (0.55 + 0.47 * math.sin(a))
            z += 0.014 * math.sin(2.1 * local_y + seed) * math.sin(a)
            lateral += twist * (1.0 - t) ** 2
            lateral += 0.012 * math.sin(3.0 * t + seed) * math.sin(a)
            x = center_x + lateral * ca - local_y * sa
            y = center_y + lateral * sa + local_y * ca
            verts.append((x, y, max(0.016, z)))
    for i in range(RING_COUNT - 1):
        for j in range(SIDES):
            n = (j + 1) % SIDES
            a = i * SIDES + j
            b = i * SIDES + n
            c = (i + 1) * SIDES + n
            d = (i + 1) * SIDES + j
            faces.extend(((a, b, d), (b, c, d)))
            # A narrow warm edge below the broad body, not a graphic seam.
            face_material.extend((1 if j >= 11 and j <= 16 else 0,) * 2)
    bottom = len(verts)
    verts.append((center_x - 0.12 * math.sin(angle), center_y - 0.45 * length, 0.035))
    top = len(verts)
    verts.append((center_x + 0.12 * math.sin(angle), center_y + 0.45 * length, 0.095))
    for j in range(SIDES):
        n = (j + 1) % SIDES
        faces.append((bottom, n, j))
        faces.append((top, (RING_COUNT - 1) * SIDES + j,
                      (RING_COUNT - 1) * SIDES + n))
        face_material.extend((1, 0))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(top_material)
    mesh.materials.append(edge_material)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    export.objects.link(obj)
    for poly, idx in zip(mesh.polygons, face_material):
        poly.material_index = idx
        poly.use_smooth = True
    uv = mesh.uv_layers.new(name="Fillet_UV")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            ring = min(vi // SIDES, RING_COUNT - 1)
            side = vi % SIDES
            uv.data[li].uv = (side / SIDES, ring / (RING_COUNT - 1))
    return obj


def camera(review, name, location, target, orthographic_scale):
    data = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, data)
    review.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.type = "ORTHO"
    data.ortho_scale = orthographic_scale
    return obj


def light(review, name, location, energy, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    review.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()


def main():
    phase = "gray" if "--phase=gray" in sys.argv else "final"
    export, review = reset()
    rose = material("M_Soft_Clay_Rose", (0.71, 0.41, 0.39), 0.61)
    blush = material("M_Pale_Blush", (0.80, 0.53, 0.49), 0.64)
    warm = material("M_Quiet_Warmth", (0.76, 0.47, 0.43), 0.60)
    cream = material("M_Fold_Cream", (0.87, 0.70, 0.62), 0.72)
    objects = [
        fillet(export, "Left_broad", -0.24, -0.08, -0.21, 0.99, 0.295, 0.14,
               -0.020, rose, cream, 1.0),
        fillet(export, "Middle_fold", 0.05, 0.055, 0.05, 0.87, 0.215, 0.16,
               0.006, blush, cream, 2.2),
        fillet(export, "Right_round", 0.295, 0.025, 0.27, 0.78, 0.215, 0.135,
               0.023, warm, cream, 3.6),
    ]
    # A shallow fold above the middle/right boundary, rounded and non-graphic.
    seam_curve = bpy.data.curves.new("Pale_fold_curve", "CURVE")
    seam_curve.dimensions = "3D"
    seam_curve.bevel_depth = 0.012
    seam_curve.bevel_resolution = 2
    spline = seam_curve.splines.new("BEZIER")
    spline.bezier_points.add(3)
    for bp, co in zip(spline.bezier_points, [
        (0.18, -0.30, 0.15), (0.22, -0.12, 0.19),
        (0.25, 0.12, 0.20), (0.29, 0.31, 0.17),
    ]):
        bp.co = co
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    fold = bpy.data.objects.new("Soft_cream_fold", seam_curve)
    export.objects.link(fold)
    bpy.context.view_layer.objects.active = fold
    fold.select_set(True)
    bpy.ops.object.convert(target="MESH")
    fold.select_set(False)
    fold.data.materials.append(cream)
    objects.append(fold)

    gray = material("REVIEW_Gray", (0.62, 0.60, 0.57), 0.69)
    cam = camera(review, "REVIEW_Camera", (2.2, -3.8, 3.2), (0, 0, 0.08), 2.0)
    light(review, "REVIEW_Key", (-2.0, -2.4, 4.0), 340, 3.4)
    light(review, "REVIEW_Fill", (2.2, 0.9, 2.7), 190, 4.2)
    light(review, "REVIEW_Graze", (0.3, 2.3, 2.2), 145, 2.0)
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.world.color = (0.12, 0.15, 0.20)
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    # First invocation stops after gray views so shape can be inspected/revised.
    bpy.ops.wm.save_as_mainfile(filepath=str(
        OUT / ("meat-pale-blockout.blend" if phase == "gray" else "meat-pale.blend")))
    shots = [
        ("gray_front.png", (0.0, -3.5, 1.95), True),
        ("gray_side.png", (3.1, -0.3, 1.5), True),
        ("gray_three_quarter.png", (2.2, -3.8, 3.2), True),
    ]
    if phase == "final":
        shots.extend([
        ("material_three_quarter.png", (2.2, -3.8, 3.2), False),
        ("material_gameplay.png", (0.0, -3.5, 4.3), False),
        ])
    for file_name, position, clay in shots:
        cam.location = position
        cam.rotation_euler = (Vector((0, 0, 0.08)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.view_layers[0].material_override = gray if clay else None
        scene.render.filepath = str(OUT / file_name)
        bpy.ops.render.render(write_still=True)
    if phase == "gray":
        print("Gray blockout rendered; inspect and revise before --phase=final")
        return
    scene.view_layers[0].material_override = None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=str(OUT / "meat-pale.glb"), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True)
    for obj in objects:
        obj.select_set(False)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "meat-pale.blend"))
    counts = {"triangles": sum(sum(poly.loop_total - 2 for poly in o.data.polygons)
                               for o in objects),
              "materials": 4, "textures": 0, "parts": len(objects),
              "blender_version": bpy.app.version_string}
    (OUT / "technical_report.json").write_text(json.dumps(counts, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
