"""Quality-ladder demo: one microscopic cell taken from blockout to target quality.

Each rung is its own asset (Blender source, GLB and record) so the steps can be compared side by
side. The rungs follow docs/art/ART_DIRECTION.md section 7 and are owned by the art roles:

  0 blockout  (modeler)          primitives, clay, proportions and silhouette only
  1 form      (modeler)          one shaped body with sockets, lids, lips and organelle beads
  2 surfaced  (surfacing)        UVs, baked albedo and ORM textures in the palette
  3 target    (rigging + tech)   armature, idle/swim/eat actions, budget check, GLB checks

The sample cell (`make_sample_cell.py`) is the gameplay placeholder and is not changed here.
Joshua approved the look on 2026-10-22. These remain reference assets, not gameplay assets.

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


# --- Rung 3: target (rig and animation) ----------------------------------------------------

RIG_FAMILY = "cell_single_body"
FPS = 24
TAIL_BONES = len(FLAGELLUM_PTS)


def eye_frame(side):
    d = EYE_DIR[side]
    centre = ellipsoid_point(d) - d * 0.035
    gaze = Vector((d.x * 0.6, 1.0, 0.18)).normalized()
    return centre, gaze


def build_armature():
    arm_data = bpy.data.armatures.new("CellRig")
    arm = bpy.data.objects.new("CellRig", arm_data)
    bpy.context.collection.objects.link(arm)
    select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, head, tail, parent=None, connect=False):
        b = eb.new(name)
        b.head, b.tail = Vector(head), Vector(tail)
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    bone("root", (0, 0, 0), (0, 0.25, 0))
    bone("body", (0, -0.1, 0), (0, 0.3, 0), "root")
    mouth = ellipsoid_point(MOUTH_DIR)
    bone("mouth", mouth - MOUTH_DIR * 0.1, mouth + MOUTH_DIR * 0.05, "body")
    chain = [Vector((0, -0.34, 0.02))] + [Vector(p) for p in FLAGELLUM_PTS[1:]] + [Vector((0, -1.42, 0.06))]
    for i in range(TAIL_BONES):
        bone(f"tail_{i + 1:02d}", chain[i], chain[i + 1], "body" if i == 0 else f"tail_{i:02d}", connect=i > 0)
    for side in EYE_DIR:
        centre, gaze = eye_frame(side)
        flat = Vector((gaze.x, gaze.y, 0)).normalized() * 0.1
        bone(f"eye_{side}", centre, centre + gaze * 0.1, "body")
        bone(f"lid_upper_{side}", centre, centre + flat, "body")
        bone(f"lid_lower_{side}", centre, centre + flat, "body")
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    return arm


def skin_body(body, arm):
    """Weights by position: tail chain along the flagellum, a soft mouth zone, body elsewhere."""
    groups = {name: body.vertex_groups.new(name=name) for name in ["body", "mouth"] + [f"tail_{i + 1:02d}" for i in range(TAIL_BONES)]}
    chain_y = [-0.34] + [p[1] for p in FLAGELLUM_PTS[1:]] + [-1.42]
    mouth = ellipsoid_point(MOUTH_DIR)
    for v in body.data.vertices:
        co = v.co
        weights = {}
        if co.y < chain_y[0] + 0.06:
            # Position along the chain in bone units, blended across joints.
            y = co.y
            t = 0.0
            for i in range(TAIL_BONES):
                a, b = chain_y[i], chain_y[i + 1]
                if y <= a:
                    t = i + min(1.0, (a - y) / (a - b))
            t = max(0.0, t - 0.5)
            lo = min(int(t), TAIL_BONES - 1)
            frac = min(1.0, t - lo)
            weights[f"tail_{lo + 1:02d}"] = 1.0 - frac
            if lo + 1 < TAIL_BONES:
                weights[f"tail_{lo + 2:02d}"] = frac
            if co.y > chain_y[0] - 0.08:
                # Rear of the body: fade from body into the first tail bone.
                k = (co.y - (chain_y[0] - 0.08)) / 0.14
                weights = {n: w * (1 - k) for n, w in weights.items()}
                weights["body"] = k
        else:
            m = gauss((co - mouth).length_squared, 0.07)
            weights = {"mouth": m, "body": 1.0 - m}
        for name, w in weights.items():
            if w > 0.001:
                groups[name].add([v.index], w, "REPLACE")
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    body.parent = arm


def parent_to_bone(obj, arm, bone):
    world = obj.matrix_world.copy()
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    bpy.context.view_layer.update()
    obj.matrix_world = world


def key(arm, frame, values):
    """values: {bone: {"rot": (x, y, z) degrees, "scale": (x, y, z), "loc": (x, y, z)}}."""
    for name, channels in values.items():
        pb = arm.pose.bones[name]
        if "rot" in channels:
            pb.rotation_euler = [math.radians(a) for a in channels["rot"]]
            pb.keyframe_insert("rotation_euler", frame=frame)
        if "scale" in channels:
            pb.scale = channels["scale"]
            pb.keyframe_insert("scale", frame=frame)
        if "loc" in channels:
            pb.location = channels["loc"]
            pb.keyframe_insert("location", frame=frame)


def new_action(arm, name):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
        pb.location = (0, 0, 0)
    return action


def lids(upper, lower):
    return {f"lid_upper_{s}": {"rot": (upper, 0, 0)} for s in EYE_DIR} | {f"lid_lower_{s}": {"rot": (lower, 0, 0)} for s in EYE_DIR}


def tail_wave(phase, amplitude=1.0):
    return {f"tail_{i + 1:02d}": {"rot": (0, 0, amplitude * (8 + 5 * i) * math.sin(phase - i * 0.9))} for i in range(TAIL_BONES)}


def animate(arm):
    """Idle and swim loop; eat is a one-shot. Lids and body squash carry the emotion (art doc 2)."""
    arm.animation_data_create()
    clips = []

    new_action(arm, "idle")
    for f in range(0, 49, 4):
        ph = 2 * math.pi * f / 48
        breath = 0.5 - 0.5 * math.cos(ph)
        pose = {"body": {"scale": (1 + 0.03 * breath, 1 - 0.015 * breath, 1 + 0.03 * breath)}}
        pose |= tail_wave(ph, 0.45)
        glance = 9 * math.sin(ph)
        pose |= {f"eye_{s}": {"rot": (0, 0, glance)} for s in EYE_DIR}
        pose |= lids(0, 0)
        key(arm, f, pose)
    key(arm, 30, lids(-62, 30))  # the blink closes on frame 30
    clips.append({"name": "idle", "frames": 48, "fps": FPS, "loop": True})

    new_action(arm, "swim")
    for f in range(0, 25, 2):
        ph = 2 * math.pi * f / 24
        pose = tail_wave(ph, 1.0)
        pose["body"] = {"rot": (0, 0, -4 * math.sin(ph + 0.6)),
                        "scale": (1 - 0.02 * math.sin(2 * ph), 1 + 0.035 * math.sin(2 * ph), 1 - 0.02 * math.sin(2 * ph))}
        pose |= lids(-12, 6)  # focused: a slightly narrowed eye
        key(arm, f, pose)
    clips.append({"name": "swim", "frames": 24, "fps": FPS, "loop": True})

    new_action(arm, "eat")
    beats = [(0, 1.0, 0.0, 0, 0), (6, 1.4, 0.07, -8, 4), (10, 0.75, 0.03, -28, 18), (14, 1.08, 0.0, -28, 18), (20, 1.0, 0.0, 0, 0)]
    for f, mouth, lunge, upper, lower in beats:
        pose = {"mouth": {"scale": (mouth, 1.0, mouth)}, "body": {"loc": (0, lunge, 0)}}
        pose |= lids(upper, lower)  # a satisfied squint on the chomp
        pose |= tail_wave(2 * math.pi * f / 20, 0.5)
        key(arm, f, pose)
    clips.append({"name": "eat", "frames": 20, "fps": FPS, "loop": False})

    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_euler, pb.scale, pb.location = (0, 0, 0), (1, 1, 1), (0, 0, 0)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 0, 48
    return clips


def build_target():
    objs, extra = build_surfaced()
    body = objs["body"]
    arm = build_armature()
    bpy.context.view_layer.update()
    sockets = [o for o in bpy.data.objects if o.name.startswith("socket_")]
    for key_, obj in objs.items():
        if key_ == "body":
            continue
        family, _, side = key_.partition("_")
        if family in ("eye", "iris", "pupil"):
            parent_to_bone(obj, arm, f"eye_{side}")
        elif family == "lidupper":
            parent_to_bone(obj, arm, f"lid_upper_{side}")
        elif family == "lidlower":
            parent_to_bone(obj, arm, f"lid_lower_{side}")
        elif family == "lips":
            parent_to_bone(obj, arm, "mouth")
        else:
            parent_to_bone(obj, arm, "body")
    for socket in sockets:
        parent_to_bone(socket, arm, "body")
    skin_body(body, arm)
    clips = animate(arm)
    extra.update({
        "rig_family": RIG_FAMILY,
        "bones": [b.name for b in arm.data.bones],
        "animations": clips,
        "gltf": {"export_animations": True, "export_animation_mode": "ACTIONS", "export_skins": True,
                 "export_def_bones": False, "export_frame_range": False},
    })
    objs["rig"] = arm
    return objs, extra


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
        "review_state": "look approved by the owner on 2026-10-22; reference demo for the art direction, not a gameplay asset",
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


BUILDERS = {"0_blockout": build_blockout, "1_form": build_form, "2_surfaced": build_surfaced, "3_target": build_target}


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
