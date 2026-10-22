"""Shared helpers for the M1 blockout generators (tools/blender/make_m1_blockouts.py).

Scene reset, materials, mesh building (surfaces of revolution, swept tubes, icospheres), bounds,
triangle counts, glTF export and the asset record writer. The export settings and the record
shape match tools/blender/make_sample_cell.py, so every blockout passes the same admission checks
in tests/test_assets.gd.

Everything here is deterministic: no random numbers, only fixed formulas and mathutils.noise
sampled at fixed offsets.
"""
import json
import math
import os

import bpy  # first: with the bpy module, bmesh and mathutils only exist once bpy is imported
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OWNER = "Joshua Jake"
STATUS = "PROPOSED"
REVIEW_STATE = "blockout - M1 step 2, not visually approved"
GENERATOR = "tools/blender/make_m1_blockouts.py"
PROVENANCE = "Authored procedurally in Blender by tools/blender/make_m1_blockouts.py; no external or generated meshes."


def paths(asset_id):
    """(blend, glb, record) absolute paths for an asset id."""
    return (
        os.path.join(ROOT, "assets", "source", "blender", f"{asset_id}.blend"),
        os.path.join(ROOT, "assets", "export", f"{asset_id}.glb"),
        os.path.join(ROOT, "assets", "records", f"{asset_id}.json"),
    )


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def material(name, color, roughness=0.5, emission=None, emission_strength=0.6, vertex_colors=None):
    """A Principled material. With `vertex_colors` (a color attribute name) the base color comes
    from that attribute instead of `color`, and the glTF exporter writes it as COLOR_0.

    Vertex colours are stored sRGB-encoded (see srgb()), because Godot reads COLOR_0 as it is and
    the engine material marks it sRGB (vertex_color_is_srgb), so the Forward+ and Compatibility
    renderers both shade it exactly like an albedo colour. A gamma node decodes it here, so the
    Blender preview matches."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if vertex_colors:
        attribute = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        attribute.layer_name = vertex_colors
        decode = mat.node_tree.nodes.new("ShaderNodeGamma")
        decode.inputs["Gamma"].default_value = 2.2
        mat.node_tree.links.new(attribute.outputs["Color"], decode.inputs["Color"])
        mat.node_tree.links.new(decode.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def srgb(color):
    """Linear RGB to sRGB-encoded RGB (the standard transfer curve), for vertex colours."""
    return tuple(12.92 * c if c <= 0.0031308 else 1.055 * c ** (1.0 / 2.4) - 0.055 for c in color)


def smoothstep(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


# --- Mesh data builders. Each returns (verts, faces) or adds to lists passed in. -----------------


def revolve(profile, segments, phase=0.0):
    """Surface of revolution around Blender +Y (the part's outward axis).

    `profile` is [(y, radius)] from one end to the other; a radius of 0 is a single pole vertex.
    Returns (verts, faces, bands): bands[i] is the index of the profile segment face i lies on,
    which callers use to assign materials along the profile.
    """
    verts, faces, bands, rings = [], [], [], []
    for y, r in profile:
        if r <= 0.0:
            rings.append([len(verts)])
            verts.append((0.0, y, 0.0))
            continue
        ring = []
        for j in range(segments):
            a = phase + 2.0 * math.pi * j / segments
            ring.append(len(verts))
            verts.append((r * math.cos(a), y, r * math.sin(a)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(segments):
            k = (j + 1) % segments
            if len(a) == 1:
                faces.append((a[0], b[k], b[j]))
            elif len(b) == 1:
                faces.append((a[j], a[k], b[0]))
            else:
                faces.append((a[j], a[k], b[k], b[j]))
            bands.append(i)
    return verts, faces, bands


def tube(points, radii, sides, squash=1.0, roll=0.0):
    """A closed tube swept along `points` (Vectors), with a flat cap at the start.

    The last radius may be 0 for a pointed tip. `squash` scales the cross-section along the
    frame's second axis (vertical for paths in the XY plane).
    """
    verts, faces, rings = [], [], []
    n = len(points)
    for i, p in enumerate(points):
        t = (points[min(i + 1, n - 1)] - points[max(i - 1, 0)]).normalized()
        ref = Vector((0.0, 0.0, 1.0)) if abs(t.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        side = t.cross(ref).normalized()
        up = side.cross(t).normalized()
        r = radii[i]
        if r <= 0.0:
            rings.append([len(verts)])
            verts.append(tuple(p))
            continue
        ring = []
        for j in range(sides):
            a = roll + 2.0 * math.pi * j / sides
            q = p + side * (r * math.cos(a)) + up * (r * squash * math.sin(a))
            ring.append(len(verts))
            verts.append(tuple(q))
        rings.append(ring)
    cap = len(verts)
    verts.append(tuple(points[0]))
    first = rings[0]
    for j in range(sides):
        faces.append((cap, first[(j + 1) % sides], first[j]))
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(sides):
            k = (j + 1) % sides
            if len(b) == 1:
                faces.append((a[j], a[k], b[0]))
            else:
                faces.append((a[j], a[k], b[k], b[j]))
    return verts, faces


def icosphere(subdivisions):
    """Unit icosphere as (verts, faces), with stable vertex order.

    Blender counts the plain icosahedron (20 triangles) as subdivision 1; each level multiplies
    the triangles by 4, so 3 gives 320 and 4 gives 1280.
    """
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
    bm.verts.index_update()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return verts, faces


def append(verts, faces, more_verts, more_faces):
    """Appends a second piece of mesh data, re-indexing its faces. Returns the new face indices."""
    base = len(verts)
    verts.extend(more_verts)
    start = len(faces)
    faces.extend(tuple(i + base for i in f) for f in more_faces)
    return range(start, len(faces))


# --- Objects ----------------------------------------------------------------------------------


def mesh_object(name, verts, faces, materials, face_materials=None, smooth=True, parent=None,
                location=(0.0, 0.0, 0.0), fix_normals=True, uv=None, vertex_colors=None):
    """Creates a linked mesh object.

    `fix_normals` makes every face of a closed piece point outward (leave it off for open
    surfaces whose winding is set by construction). `uv(co) -> (u, v)` fills a UV layer so the
    importer can build tangents; blockouts carry no textures, so a simple projection is enough.
    `vertex_colors` is (attribute name, [linear (r, g, b) per vertex]), for a material made with
    the same `vertex_colors` name; they are stored sRGB-encoded.
    """
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    if fix_normals:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    if face_materials is not None:
        mesh.polygons.foreach_set("material_index", list(face_materials))
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    if vertex_colors is not None:
        attr_name, colors = vertex_colors
        attr = mesh.color_attributes.new(name=attr_name, type="FLOAT_COLOR", domain="POINT")
        attr.data.foreach_set("color", [c for rgb in colors for c in (*srgb(rgb), 1.0)])
    uv = uv or (lambda co: (0.5 + 0.5 * math.atan2(co.y, co.x) / math.pi, 0.5 + co.z))
    layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        layer.data[loop.index].uv = uv(mesh.vertices[loop.vertex_index].co)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    if parent is not None:
        obj.parent = parent
    return obj


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


def world_vertices():
    """Every mesh vertex in world space (Blender axes)."""
    bpy.context.view_layer.update()  # parented children only get their world matrix on update
    out = []
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            out.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
    return out


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


def export(asset_id, budget, fields):
    """Saves the .blend, exports the GLB and writes the record. Fails if over the triangle budget.

    `fields` holds the asset-specific record keys (purpose, category and the gameplay contract
    values that tests check, such as footprint_radius_m or item_radius_m).
    """
    bpy.context.view_layer.update()
    tris = triangle_count()
    if tris > budget:
        raise RuntimeError(f"{asset_id}: {tris} triangles is over the budget of {budget}")
    blend_path, glb_path, record_path = paths(asset_id)
    for path in (blend_path, glb_path, record_path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(blend_path):
        os.remove(blend_path)  # otherwise Blender keeps the old file as a .blend1 backup
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, compress=True, relative_remap=True)
    vertex_colors = fields.pop("vertex_colors_attribute", None)
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        # The material decodes the colours through a gamma node, which the exporter does not
        # follow, so name the attribute to write as COLOR_0.
        **({"export_vertex_color": "NAME", "export_vertex_color_name": vertex_colors,
            "export_all_vertex_colors": False} if vertex_colors else {}),
    )
    lo, hi = world_bounds()
    size = hi - lo
    record = {
        "id": asset_id,
        "owner": OWNER,
        "status": STATUS,
        "review_state": REVIEW_STATE,
        "purpose": fields.pop("purpose"),
        "category": fields.pop("category"),
        "source_blend": f"assets/source/blender/{asset_id}.blend",
        "generator_script": GENERATOR,
        "export_path": f"assets/export/{asset_id}.glb",
        "export_format": "GLB",
        "dependencies": fields.pop("dependencies", []),
        "revision": fields.pop("revision", 1),
        "blender_version": bpy.app.version_string,
        "dimensions_m": {"x": round(size.x, 3), "y_forward": round(size.y, 3), "z_up": round(size.z, 3)},
        "triangles": tris,
        "triangle_budget": budget,
        "textures": [],
        "materials": sorted(m.name for m in bpy.data.materials if m.users),
        "rig_family": None,
        "animations": [],
        "sockets": sorted(o.name for o in bpy.data.objects if o.name.startswith("socket_")),
        "nodes": sorted(o.name for o in bpy.data.objects),
    }
    record.update(fields)
    record["provenance"] = PROVENANCE
    with open(record_path, "w") as f:
        json.dump(record, f, indent=2)
        f.write("\n")
    return record
