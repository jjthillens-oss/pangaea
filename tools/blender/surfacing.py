"""Surfacing helpers for production assets: procedural shader building, UV unwrapping and baking
to glTF-safe texture sets (docs/art/ART_DIRECTION.md section 4).

A production asset is shaded in Blender with a procedural material (object-space coordinates,
noise, Voronoi, ramps and, where it helps, a CC0 scan used for detail). `bake_set` bakes that
material on every given object into one shared texture set and swaps in a single glTF-safe
material that Godot imports as it is:

  T_<Name>_Albedo     sRGB       base colour, with a soft cavity darkening from baked AO
  T_<Name>_ORM        Non-Color  R occlusion, G roughness, B metallic (glTF reads G and B)
  T_<Name>_Normal     Non-Color  tangent-space detail normals (optional)
  T_<Name>_Emission   sRGB       emitted colour (optional)

Baking uses Cycles on the CPU, so it works headless with the bpy module.
"""
import math

import bpy  # first: with the bpy module, bmesh and mathutils only exist once bpy is imported
import numpy as np

import lookdev as ld

AO_IN_ALBEDO = 0.3   # share of the albedo that the baked AO may darken (crevices read without an AO map)


# --- Node building ---------------------------------------------------------------------------


class Shader:
    """A small builder over one material's node tree. Inputs may be sockets or plain numbers."""

    def __init__(self, name):
        self.mat = bpy.data.materials.new(name)
        self.mat.use_nodes = True
        self.nt = self.mat.node_tree
        self.bsdf = self.nt.nodes["Principled BSDF"]
        self.bsdf.inputs["Metallic"].default_value = 0.0
        self._coords = self.node("ShaderNodeTexCoord")
        self._xyz = None

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for key, value in props.items():
            setattr(n, key, value)
        return n

    def link(self, value, socket):
        if isinstance(value, bpy.types.NodeSocket):
            self.nt.links.new(value, socket)
        else:
            socket.default_value = value

    @property
    def pos(self):
        return self._coords.outputs["Object"]

    def axis(self, name):
        if self._xyz is None:
            self._xyz = self.node("ShaderNodeSeparateXYZ")
            self.link(self.pos, self._xyz.inputs["Vector"])
        return self._xyz.outputs[name]

    def math(self, op, a, b=0.0, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.link(a, n.inputs[0])
        self.link(b, n.inputs[1])
        return n.outputs[0]

    def vmath(self, op, a, b=(0.0, 0.0, 0.0)):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self.link(a, n.inputs[0])
        self.link(b, n.inputs[1])
        return n.outputs["Value"] if op in ("LENGTH", "DISTANCE", "DOT_PRODUCT") else n.outputs["Vector"]

    def remap(self, value, lo, hi, to_lo=0.0, to_hi=1.0, smooth=True):
        n = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP" if smooth else "LINEAR")
        self.link(value, n.inputs["Value"])
        n.inputs["From Min"].default_value, n.inputs["From Max"].default_value = lo, hi
        n.inputs["To Min"].default_value, n.inputs["To Max"].default_value = to_lo, to_hi
        return n.outputs["Result"]

    def noise(self, scale, detail=3.0, roughness=0.55, vector=None, w=None):
        n = self.node("ShaderNodeTexNoise")
        if w is not None:
            n.noise_dimensions = "4D"
            n.inputs["W"].default_value = w
        self.link(vector if vector is not None else self.pos, n.inputs["Vector"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = roughness
        return n.outputs["Fac"]

    def voronoi(self, scale, randomness=0.9, vector=None, feature="F1"):
        n = self.node("ShaderNodeTexVoronoi", feature=feature)
        self.link(vector if vector is not None else self.pos, n.inputs["Vector"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = randomness
        return n.outputs["Distance"]

    def ramp(self, fac, stops):
        """`stops` is [(position, colour)], colours as palette names, hex strings or RGBA tuples."""
        n = self.node("ShaderNodeValToRGB")
        els = n.color_ramp.elements
        while len(els) < len(stops):
            els.new(0.5)
        for el, (position, col) in zip(els, stops):
            el.position = position
            el.color = ld.color(col) if isinstance(col, str) else col
        self.link(fac, n.inputs["Fac"])
        return n.outputs["Color"]

    def mix(self, fac, a, b, blend="MIX"):
        n = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        self.link(fac, n.inputs["Factor"])
        self.link(ld.color(a) if isinstance(a, str) else a, n.inputs["A"])
        self.link(ld.color(b) if isinstance(b, str) else b, n.inputs["B"])
        return n.outputs["Result"]

    def image(self, path, colorspace="sRGB", projection="BOX", blend=0.25, scale=1.0):
        """A (CC0) image projected on object coordinates; BOX projection needs no UVs."""
        img = bpy.data.images.load(path, check_existing=True)
        img.colorspace_settings.name = colorspace
        n = self.node("ShaderNodeTexImage", projection=projection, projection_blend=blend)
        n.image = img
        self.link(self._scaled(scale), n.inputs["Vector"])
        return n.outputs["Color"]

    def _scaled(self, scale):
        n = self.node("ShaderNodeVectorMath", operation="SCALE")
        self.link(self.pos, n.inputs[0])
        n.inputs["Scale"].default_value = scale
        return n.outputs["Vector"]

    def bump(self, height, strength=0.4, distance=0.01):
        n = self.node("ShaderNodeBump")
        self.link(height, n.inputs["Height"])
        n.inputs["Strength"].default_value = strength
        n.inputs["Distance"].default_value = distance
        self.link(n.outputs["Normal"], self.bsdf.inputs["Normal"])

    def out(self, base, roughness, emission=None, emission_strength=1.0):
        self.link(ld.color(base) if isinstance(base, str) else base, self.bsdf.inputs["Base Color"])
        self.link(roughness, self.bsdf.inputs["Roughness"])
        if emission is not None:
            self.link(ld.color(emission) if isinstance(emission, str) else emission, self.bsdf.inputs["Emission Color"])
            self.bsdf.inputs["Emission Strength"].default_value = emission_strength
        return self.mat


# --- Triangle reduction --------------------------------------------------------------------


def _surface_error(obj_a, obj_b):
    """Largest distance between the two objects' surfaces, both ways, measured at the vertices."""
    from mathutils.bvhtree import BVHTree
    deps = bpy.context.evaluated_depsgraph_get()
    worst = 0.0
    for src, dst in ((obj_a, obj_b), (obj_b, obj_a)):
        tree = BVHTree.FromObject(dst, deps)
        mesh = src.evaluated_get(deps).to_mesh()
        for v in mesh.vertices:
            hit = tree.find_nearest(v.co)
            worst = max(worst, hit[3] if hit[0] is not None else 1e9)
        src.evaluated_get(deps).to_mesh_clear()
    return worst


def reduce(obj, tolerance, keep_high=True, steps=9):
    """Cuts `obj`'s triangles as far as Blender's collapse decimation allows while its surface stays
    within `tolerance` metres of the original everywhere (checked both ways at every vertex).

    With keep_high the original stays as a hidden copy, named <name>_high, so bake_set can bake
    its shading into the reduced mesh's normal map. Returns (triangles before, after, high copy)."""
    high = obj.copy()
    high.data = obj.data.copy()
    high.name = f"{obj.name}_high"
    bpy.context.collection.objects.link(high)
    high.parent = obj.parent
    high.matrix_world = obj.matrix_world.copy()
    before = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    lo, hi = 0.0, 1.0      # lo: smallest ratio known to fail, hi: smallest known to pass
    mod = obj.modifiers.new("Reduce", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.use_collapse_triangulate = True
    for _ in range(steps):
        mid = (lo + hi) / 2.0
        mod.ratio = mid
        bpy.context.view_layer.update()
        if _surface_error(obj, high) <= tolerance:
            hi = mid
        else:
            lo = mid
    mod.ratio = hi
    select([obj])
    if hi < 1.0:
        bpy.ops.object.modifier_apply(modifier="Reduce")
    else:
        obj.modifiers.remove(mod)
    after = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if not keep_high:
        bpy.data.objects.remove(high)
        high = None
    else:
        high.hide_render = True
        high.hide_set(True)
    return before, after, high


def drop_highs(highs):
    for high in highs:
        if high is not None:
            bpy.data.objects.remove(high)


# --- UVs and baking --------------------------------------------------------------------------


def select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def unwrap(objs, margin=0.01, angle=60.0):
    """One shared, non-overlapping UV layout over every object (so they can share one texture)."""
    select(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=margin, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def _image(name, size, colorspace):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = colorspace
    return img


def _bake(objs, image, kind, **kwargs):
    """Bakes `kind` from every material on `objs` into `image`."""
    nodes = []
    for mat in {slot.material for obj in objs for slot in obj.material_slots if slot.material}:
        n = mat.node_tree.nodes.new("ShaderNodeTexImage")
        n.image = image
        mat.node_tree.nodes.active = n
        nodes.append((mat, n))
    select(objs)
    bpy.ops.object.bake(type=kind, use_clear=True, margin=4, **kwargs)
    for mat, n in nodes:
        mat.node_tree.nodes.remove(n)


def _bake_from_high(high, low, image, clear):
    """Bakes `high`'s shading normals into `low`'s tangent space (selected to active)."""
    high.hide_set(False)
    nodes = []
    for mat in {slot.material for slot in low.material_slots if slot.material}:
        n = mat.node_tree.nodes.new("ShaderNodeTexImage")
        n.image = image
        mat.node_tree.nodes.active = n
        nodes.append((mat, n))
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    size = max(low.dimensions)
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_selected_to_active=True,
                        cage_extrusion=0.02 * size, max_ray_distance=0.05 * size, use_clear=clear, margin=4)
    for mat, n in nodes:
        mat.node_tree.nodes.remove(n)
    high.hide_set(True)


def _pixels(image):
    buf = np.empty(image.size[0] * image.size[1] * 4, dtype=np.float32)
    image.pixels.foreach_get(buf)
    return buf.reshape(-1, 4)


def bake_set(objs, name, size, normal=False, emission=False, ao_samples=64, metallic=0.0, highs=None):
    """Bakes the procedural materials on `objs` to one texture set and gives every face of every
    object a single glTF-safe material M_<name>. Returns the record's `textures` entries.

    `highs` maps an object's name to its unreduced copy (from reduce()); that object's normal map
    is then baked from the copy, so reduction keeps the original's shading. A normal map is baked
    whenever any object has a copy."""
    highs = {k: v for k, v in (highs or {}).items() if v is not None}
    normal = normal or bool(highs)
    scene = bpy.context.scene
    ld.setup_render(samples=8)
    scene.render.bake.margin_type = "EXTEND"
    albedo = _image(f"T_{name}_Albedo", size, "sRGB")
    rough = _image(f"T_{name}_Rough", size, "Non-Color")
    ao = _image(f"T_{name}_AO", size, "Non-Color")
    _bake(objs, albedo, "DIFFUSE", pass_filter={"COLOR"})
    _bake(objs, rough, "ROUGHNESS")
    scene.cycles.samples = ao_samples
    _bake(objs, ao, "AO")
    scene.cycles.samples = 8
    extra = []
    if normal:
        nor = _image(f"T_{name}_Normal", size, "Non-Color")
        own = [o for o in objs if o.name not in highs]
        if own:
            _bake(own, nor, "NORMAL", normal_space="TANGENT")
        for i, obj in enumerate(o for o in objs if o.name in highs):
            _bake_from_high(highs[obj.name], obj, nor, clear=not own and i == 0)
        extra.append(nor)
    if emission:
        emit = _image(f"T_{name}_Emission", size, "sRGB")
        _bake(objs, emit, "EMIT")
        extra.append(emit)

    occ = _pixels(ao)[:, 0]
    rgba = _pixels(albedo)
    rgba[:, :3] *= (1.0 - AO_IN_ALBEDO + AO_IN_ALBEDO * occ)[:, None]
    albedo.pixels.foreach_set(rgba.ravel())
    orm = _image(f"T_{name}_ORM", size, "Non-Color")
    packed = np.stack([occ, _pixels(rough)[:, 0], np.full_like(occ, metallic), np.ones_like(occ)], axis=1)
    orm.pixels.foreach_set(packed.ravel())
    bpy.data.images.remove(rough)
    bpy.data.images.remove(ao)
    images = [albedo, orm] + extra
    for img in images:
        img.file_format = "PNG"
        img.pack()

    mat = bpy.data.materials.new(f"M_{name}")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = albedo
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    tex_orm = nodes.new("ShaderNodeTexImage")
    tex_orm.image = orm
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(tex_orm.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    if normal:
        tex_n = nodes.new("ShaderNodeTexImage")
        tex_n.image = extra[0]
        nmap = nodes.new("ShaderNodeNormalMap")
        links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
        links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if emission:
        tex_e = nodes.new("ShaderNodeTexImage")
        tex_e.image = extra[-1]
        links.new(tex_e.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0

    old = {slot.material for obj in objs for slot in obj.material_slots if slot.material}
    for obj in objs:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        obj.data.polygons.foreach_set("material_index", [0] * len(obj.data.polygons))
    for m in old:
        if m.users == 0:
            bpy.data.materials.remove(m)
    packing = {"Albedo": "albedo RGB (baked AO darkens crevices)", "ORM": "R occlusion, G roughness, B metallic",
               "Normal": "tangent-space normal (OpenGL, +Y up)", "Emission": "emitted colour RGB"}
    return [{"name": img.name, "size": [size, size], "colorspace": img.colorspace_settings.name,
             "packing": packing[img.name.rsplit("_", 1)[1]]} for img in images]
