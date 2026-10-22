"""Quality-ladder demo: one microscopic cell taken from blockout to target quality.

Each rung is its own asset (Blender source, GLB and record) so the steps can be compared side by
side. The rungs follow docs/art/ART_DIRECTION.md section 7 and are owned by the art roles:

  0 blockout  (modeler)          primitives, clay, proportions and silhouette only
  1 form      (modeler)          one shaped body with sockets, lids, lips and organelle beads
  2 surfaced  (surfacing)        UVs, baked albedo and ORM textures in the palette
  3 target    (rigging + tech)   armature, idle/swim/eat actions, budget check, GLB checks

The sample cell (`make_sample_cell.py`) is the gameplay placeholder and is not changed here.
These assets are PROPOSED look-development, not production, until Joshua approves the look.

Run with the pinned Blender (docs/TOOLCHAIN.md):
  python tools/blender/cell_ladder.py [rung ...]      (bpy 5.2.2 module; default: every rung)
  blender --background --python tools/blender/cell_ladder.py -- [rung ...]

Conventions match the sample cell: 1 m = 1 Godot unit, front +Y, up +Z, sockets named
socket_<role> with the same five roles.
"""
import json
import math
import os
import sys

import bpy
import bmesh  # after bpy: the bpy module provides bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import lookdev as ld  # noqa: E402
from make_sample_cell import add_socket, triangle_count, world_bounds  # noqa: E402

ROOT = ld.ROOT
RUNGS = ["0_blockout", "1_form", "2_surfaced", "3_target"]
ROLE = {"0_blockout": "modeler", "1_form": "modeler", "2_surfaced": "surfacing",
        "3_target": "rigging and animation, technical artist"}

# Shared proportions (body-local meters, front +Y, up +Z).
BODY_RADII = (0.45, 0.53, 0.38)
EYE_DIR = {"L": Vector((-0.42, 0.72, 0.55)).normalized(), "R": Vector((0.42, 0.72, 0.55)).normalized()}
EYE_RADIUS = 0.115
MOUTH_DIR = Vector((0.0, 1.0, -0.08)).normalized()
FLAGELLUM_PTS = [(0, -0.42, 0.02), (0, -0.66, 0.05), (0, -0.92, 0.07), (0, -1.16, 0.07), (0, -1.36, 0.06)]
FLAGELLUM_RADII = [1.0, 0.72, 0.5, 0.32, 0.12]
SOCKETS = {"socket_mouth": (0, 0.5, 0), "socket_tail": (0, -0.5, 0), "socket_top": (0, 0, 0.5),
           "socket_side_L": (-0.5, 0, 0), "socket_side_R": (0.5, 0, 0)}


def asset_id(rung):
    return f"cell_ladder_{rung}"


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def name_obj(obj, name):
    obj.name = name
    if obj.data:
        obj.data.name = f"{name}_mesh"
    return obj


def ellipsoid_point(direction):
    """Point on the undeformed body ellipsoid along a body-local direction."""
    d = Vector(direction).normalized()
    rx, ry, rz = BODY_RADII
    t = 1.0 / math.sqrt((d.x / rx) ** 2 + (d.y / ry) ** 2 + (d.z / rz) ** 2)
    return d * t


def add_sockets(parent):
    for name, loc in SOCKETS.items():
        add_socket(name, loc, parent)


# --- Rung 0: blockout ----------------------------------------------------------------------

def build_blockout():
    clay = ld.clay_material()
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=1.0)
    body = name_obj(bpy.context.active_object, "Body")
    body.scale = BODY_RADII
    bpy.ops.object.transform_apply(scale=True)
    for side, d in EYE_DIR.items():
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=EYE_RADIUS,
                                             location=ellipsoid_point(d) - d * 0.03)
        name_obj(bpy.context.active_object, f"Eye_{side}").parent = body
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.1, depth=0.08, location=ellipsoid_point(MOUTH_DIR),
                                        rotation=(math.radians(90), 0, 0))
    name_obj(bpy.context.active_object, "Mouth").parent = body
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.05, radius2=0.0, depth=0.95,
                                    location=(0, -0.88, 0.05), rotation=(math.radians(90), 0, 0))
    name_obj(bpy.context.active_object, "Flagellum").parent = body
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.data.materials.append(clay)
    add_sockets(body)
    return {"body": body}


# --- Rung 1: form --------------------------------------------------------------------------

def gauss(d2, sigma):
    return math.exp(-d2 / (2.0 * sigma * sigma))


def shape_body(v):
    """Sculpt the unit quad-sphere point `v` into the pebble body (section 2 of the art doc)."""
    rx, ry, rz = BODY_RADII
    p = Vector((v.x * rx, v.y * ry, v.z * rz))
    # Pebble: weight sits low, the belly is flatter and the rear is fuller than the face.
    if p.z < 0:
        p.x *= 1.0 + 0.10 * (-p.z / rz)
        p.z *= 0.86
    p.x *= 1.0 - 0.07 * (p.y / ry)
    p.z *= 1.0 - 0.05 * (p.y / ry)
    # A small deliberate lean: the rear-left flank bulges a little (no perfect symmetry).
    p.x -= 0.018 * gauss((p.y + 0.28) ** 2 + (p.z + 0.05) ** 2, 0.16)
    n = p.normalized()
    offset = 0.0
    for d in EYE_DIR.values():
        centre = ellipsoid_point(d)
        offset -= 0.045 * gauss((p - centre).length_squared, 0.085)            # eye socket
        brow = centre + Vector((0, -0.05, 0.07))
        offset += 0.022 * gauss((p - brow).length_squared, 0.06)               # brow petal
    mouth = ellipsoid_point(MOUTH_DIR)
    offset -= 0.06 * gauss((p - mouth).length_squared, 0.075)                  # mouth recess
    cheek_l, cheek_r = mouth + Vector((-0.16, -0.08, -0.02)), mouth + Vector((0.16, -0.08, -0.02))
    offset += 0.018 * (gauss((p - cheek_l).length_squared, 0.07) + gauss((p - cheek_r).length_squared, 0.07))
    if p.z > 0:
        # Dorsal ridge running from the brow to the tail root.
        offset += 0.02 * gauss(p.x * p.x, 0.045) * max(0.0, 1.0 - abs(p.y + 0.05) / 0.45)
    return p + n * offset


def build_body_mesh(level=4):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    for _ in range(level):
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    for v in bm.verts:
        v.co = shape_body(v.co.normalized())
    mesh = bpy.data.meshes.new("Body_mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Body", mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def add_eye(side, body):
    """Eyeball, iris and pupil caps, and two lids that pivot on the eye centre (for blinks)."""
    d = EYE_DIR[side]
    centre = ellipsoid_point(d) - d * 0.035
    gaze = Vector((d.x * 0.6, 1.0, 0.18)).normalized()
    parts = {}
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=EYE_RADIUS, location=centre)
    parts["eye"] = name_obj(bpy.context.active_object, f"Eye_{side}")
    rot = gaze.to_track_quat("Z", "Y").to_euler()
    for name, radius, depth, flat in (("Iris", 0.068, EYE_RADIUS - 0.018, 0.4), ("Pupil", 0.036, EYE_RADIUS + 0.004, 0.35)):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=8, radius=radius, location=centre + gaze * depth)
        cap = name_obj(bpy.context.active_object, f"{name}_{side}")
        cap.scale = (1, 1, flat)
        cap.rotation_euler = rot
        parts[name.lower()] = cap
    yaw = math.atan2(-gaze.x, gaze.y)
    for lid, keep_upper, tilt in (("LidUpper", True, 52.0), ("LidLower", False, -58.0)):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=EYE_RADIUS + 0.012)
        doomed = [v for v in bm.verts if (v.co.z < -0.004 if keep_upper else v.co.z > 0.004)]
        bmesh.ops.delete(bm, geom=doomed, context="VERTS")
        mesh = bpy.data.meshes.new(f"{lid}_{side}_mesh")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(f"{lid}_{side}", mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = centre
        obj.rotation_euler = (math.radians(tilt), 0, yaw)
        solid = obj.modifiers.new("Solidify", "SOLIDIFY")
        solid.thickness = 0.014
        solid.offset = 1.0
        for poly in mesh.polygons:
            poly.use_smooth = True
        parts[lid.lower()] = obj
    for obj in parts.values():
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.shade_smooth()
        obj.parent = body
    return parts


def add_lips(body):
    centre = ellipsoid_point(MOUTH_DIR) - MOUTH_DIR * 0.035
    bpy.ops.mesh.primitive_torus_add(major_radius=0.085, minor_radius=0.03, major_segments=32, minor_segments=10,
                                     location=centre, rotation=(math.radians(90 - 4.6), 0, 0))
    lips = name_obj(bpy.context.active_object, "Lips")
    lips.scale = (1.15, 1.0, 0.72)
    bpy.ops.object.shade_smooth()
    lips.parent = body
    return lips


def add_flagellum(body):
    curve = bpy.data.curves.new("Flagellum_curve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.055
    curve.bevel_resolution = 4
    curve.resolution_u = 10
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(FLAGELLUM_PTS) - 1)
    for bp, co, r in zip(spline.bezier_points, FLAGELLUM_PTS, FLAGELLUM_RADII):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        bp.radius = r
    curve.use_fill_caps = True
    obj = bpy.data.objects.new("Flagellum", curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj = name_obj(bpy.context.active_object, "Flagellum")
    bpy.ops.object.shade_smooth()
    obj.parent = body
    # Collar bead where the flagellum leaves the body.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.06, minor_radius=0.022, major_segments=24, minor_segments=8,
                                     location=(0, -0.44, 0.02), rotation=(math.radians(90), 0, 0))
    collar = name_obj(bpy.context.active_object, "Collar")
    bpy.ops.object.shade_smooth()
    collar.parent = body
    return obj, collar


def add_organelles(body):
    """Three glowing beads along the back: the cell's identity mark from the gameplay camera."""
    beads = []
    for i, (y, r) in enumerate(((0.06, 0.075), (-0.12, 0.06), (-0.27, 0.045))):
        top = shape_body(ellipsoid_point(Vector((0, y / BODY_RADII[1], 0.9))).normalized())
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=r, location=top - Vector((0, 0, r * 0.45)))
        bead = name_obj(bpy.context.active_object, f"Organelle_{i}")
        bead.scale = (1, 1.1, 0.8)
        bpy.ops.object.shade_smooth()
        bead.parent = body
        beads.append(bead)
    return beads


def build_form():
    body = build_body_mesh()
    objs = {"body": body, "lips": add_lips(body)}
    for side in EYE_DIR:
        for key, obj in add_eye(side, body).items():
            objs[f"{key}_{side}"] = obj
    objs["flagellum"], objs["collar"] = add_flagellum(body)
    for i, bead in enumerate(add_organelles(body)):
        objs[f"organelle_{i}"] = bead
    clay = ld.clay_material()
    for obj in objs.values():
        obj.data.materials.append(clay)
    add_sockets(body)
    return objs


# --- Rung 2: surfaced ----------------------------------------------------------------------

TEXTURE_SIZE = 512  # Microscopic creature budget (art direction section 4).


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def join_into(target, others):
    """Join meshes into `target` so the skinned body is one mesh with one texture set."""
    select_only(target)
    for obj in others:
        obj.select_set(True)
    bpy.ops.object.join()
    return target


def unwrap(obj):
    select_only(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.012, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def body_membrane():
    mat = ld.membrane_material("M_Membrane_Procedural")
    mouth = ellipsoid_point(MOUTH_DIR)
    ld.tint_region(mat, tuple(mouth - MOUTH_DIR * 0.06), 0.09, ld.color("#5A2230"), 0.95)   # mouth interior
    ld.tint_region(mat, -0.5, -0.8, ld.color("cream"), 0.7, axis="Y")                       # flagellum tip
    for d in EYE_DIR.values():
        ld.tint_region(mat, tuple(ellipsoid_point(d)), 0.17, ld.color("rust"), 0.35)       # eye shadow
    return mat


def bake(obj, mat, kind, image, pass_filter=None):
    nodes = mat.node_tree.nodes
    node = nodes.new("ShaderNodeTexImage")
    node.image = image
    nodes.active = node
    select_only(obj)
    scene = bpy.context.scene
    scene.render.bake.margin = 6
    kwargs = {"type": kind, "use_clear": True}
    if pass_filter:
        kwargs["pass_filter"] = pass_filter
    bpy.ops.object.bake(**kwargs)
    nodes.remove(node)


def new_image(name, colorspace):
    img = bpy.data.images.new(name, TEXTURE_SIZE, TEXTURE_SIZE, alpha=False)
    img.colorspace_settings.name = colorspace
    return img


def bake_body(body):
    """Bake the procedural membrane to an albedo and an ORM texture, then swap in a glTF-safe material."""
    scene = bpy.context.scene
    ld.setup_render(samples=16)
    proc = body_membrane()
    body.data.materials.clear()
    body.data.materials.append(proc)
    albedo = new_image("T_CellLadder_Albedo", "sRGB")
    rough = new_image("T_CellLadder_Roughness", "Non-Color")
    ao = new_image("T_CellLadder_AO", "Non-Color")
    bake(body, proc, "DIFFUSE", albedo, {"COLOR"})
    bake(body, proc, "ROUGHNESS", rough)
    scene.cycles.samples = 64
    bake(body, proc, "AO", ao)
    # ORM: R occlusion, G roughness, B metallic (0). Albedo gets a soft cavity darkening from the
    # AO so the form holds in Godot even without an occlusion map.
    import numpy as np
    n = TEXTURE_SIZE * TEXTURE_SIZE * 4
    a, r, o = (np.empty(n, dtype=np.float32) for _ in range(3))
    albedo.pixels.foreach_get(a)
    rough.pixels.foreach_get(r)
    ao.pixels.foreach_get(o)
    occ = o.reshape(-1, 4)[:, 0]
    rgba = a.reshape(-1, 4)
    rgba[:, :3] *= (0.7 + 0.3 * occ)[:, None]
    albedo.pixels.foreach_set(rgba.ravel())
    orm = new_image("T_CellLadder_ORM", "Non-Color")
    packed = np.stack([occ, r.reshape(-1, 4)[:, 0], np.zeros_like(occ), np.ones_like(occ)], axis=1)
    orm.pixels.foreach_set(packed.ravel())
    bpy.data.images.remove(rough)
    bpy.data.images.remove(ao)
    for img in (albedo, orm):
        img.file_format = "PNG"
        img.pack()

    mat = bpy.data.materials.new("M_CellMembrane")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex_a = nodes.new("ShaderNodeTexImage")
    tex_a.image = albedo
    links.new(tex_a.outputs["Color"], bsdf.inputs["Base Color"])
    tex_orm = nodes.new("ShaderNodeTexImage")
    tex_orm.image = orm
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(tex_orm.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    body.data.materials.clear()
    body.data.materials.append(mat)
    bpy.data.materials.remove(proc)
    return [{"name": img.name, "size": [TEXTURE_SIZE, TEXTURE_SIZE], "colorspace": img.colorspace_settings.name,
             "packing": "albedo RGB" if img is albedo else "R occlusion, G roughness, B metallic"}
            for img in (albedo, orm)]


def surface_parts(objs):
    mats = {
        "eye": ld.principled("M_EyeSclera", ld.color("cream"), 0.08),
        "iris": ld.principled("M_EyeIris", ld.color("pool_teal"), 0.25),
        "pupil": ld.principled("M_EyePupil", ld.color("#0E1A26"), 0.05),
        "lidupper": ld.principled("M_Lid", ld.color("rust"), 0.62),
        "lips": ld.principled("M_Lips", ld.color("#8E3A33"), 0.55),
        "organelle": ld.principled("M_Organelle", ld.color("mineral_amber"), 0.45, ld.color("mineral_amber"), 0.5),
    }
    mats["lidlower"] = mats["lidupper"]
    for key, obj in objs.items():
        family = key.split("_")[0]
        if family in mats:
            obj.data.materials.clear()
            obj.data.materials.append(mats[family])


def build_surfaced():
    objs = build_form()
    body = join_into(objs["body"], [objs.pop("flagellum"), objs.pop("collar")])
    unwrap(body)
    textures = bake_body(body)
    surface_parts(objs)
    clay = bpy.data.materials.get("M_Clay")
    if clay:
        bpy.data.materials.remove(clay)
    return objs, {"textures": textures}


# --- Export and record ---------------------------------------------------------------------

def export(rung, objs, extra=None):
    aid = asset_id(rung)
    blend = os.path.join(ROOT, "assets", "source", "blender", f"{aid}.blend")
    glb = os.path.join(ROOT, "assets", "export", f"{aid}.glb")
    record_path = os.path.join(ROOT, "assets", "records", f"{aid}.json")
    bpy.context.view_layer.update()
    for path in (blend, glb, record_path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True, relative_remap=True)
    gltf = dict(filepath=glb, export_format="GLB", export_yup=True, export_apply=True, export_materials="EXPORT",
                export_cameras=False, export_lights=False)
    gltf.update((extra or {}).get("gltf", {}))
    bpy.ops.export_scene.gltf(**gltf)
    lo, hi = world_bounds()
    size = hi - lo
    record = {
        "id": aid,
        "owner": "Joshua Jake",
        "status": "PROPOSED",
        "review_state": "look-development, awaiting owner review of the art direction; not for gameplay use",
        "purpose": f"Quality-ladder demo rung {rung} (docs/art/quality_ladder.md).",
        "ladder_rung": rung,
        "art_role": ROLE[rung],
        "source_blend": f"assets/source/blender/{aid}.blend",
        "generator_script": "tools/blender/cell_ladder.py",
        "export_path": f"assets/export/{aid}.glb",
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
        "provenance": "Authored procedurally in Blender by tools/blender/cell_ladder.py; no external or generated meshes or images.",
    }
    for key, value in (extra or {}).items():
        if key != "gltf":
            record[key] = value
    with open(record_path, "w") as f:
        json.dump(record, f, indent=2)
        f.write("\n")
    print(json.dumps(record, indent=2))
    return record


BUILDERS = {"0_blockout": build_blockout, "1_form": build_form, "2_surfaced": build_surfaced}


def build(rung):
    reset_scene()
    result = BUILDERS[rung]()
    objs, extra = result if isinstance(result, tuple) else (result, {})
    return export(rung, objs, extra)


def main(argv):
    rungs = [r for r in RUNGS if r in BUILDERS and (not argv or r in argv or r[0] in argv)]
    for rung in rungs:
        build(rung)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(args)
    sys.stdout.flush()
