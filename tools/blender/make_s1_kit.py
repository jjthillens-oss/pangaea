"""The endless world's band-0 placement kit, step S1 (docs/s1/s1-interfaces.md sections 4.4 and 5 in
the project files): five shells, six landmarks, two rare set pieces and the two wayfinding markers.

These are the rough pieces (review state "blockout - S1, not visually approved"): final size, final
collision contract, flat colours. Each finished piece later keeps its id, GLB path, footprint or
colliders, class, scale range, group and rare kind, and only bumps its record's revision and review
state. The shapes follow the concept sheet (tools/blender/render_landmark_concepts.py), refitted to
the contract. Every design is original and microscopic in scale: shells, lattices, colonies and
husks of single cells, never anything with bones.

The contract, checked here before export and again by tests/test_kit_assets.gd:
- 1 m = 1 bu at scale 1. Pivot on the swim plane at the footprint centre; bounds centred on it.
- Swim band (-0.45 to +0.45 m, 9 sections): the outline at every azimuth is 0.85 to 1.15 of the
  collision edge (footprint for shells, collide radius 2.0 at both ends of the scale range for
  landmarks, the collider union for rare pieces).
- Shells top at most 0.6 m, base at most -1.5 m. Landmarks top at most 4 m at their top scale,
  inside the 3 m anchor, and above -0.6 m within 1.15 x 2.0 at their top scale (an apron may widen
  below). Rare pieces top at most 4 m and above +0.6 m inside 1.15 x their colliders.
- No colour within 25 degrees of LAB hue of food (h 114) or threat (h 11).
- One root mesh named after the asset in PascalCase; each dressing's growth is a child
  Growth_<Name>, hidden by default.

Writes assets/source/blender/<id>.blend, assets/export/<id>.glb and assets/records/<id>.json.
Run: python tools/blender/make_s1_kit.py [--only <id>[,<id>...]]
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_m1_blockouts as mb  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

GENERATOR = "tools/blender/make_s1_kit.py"
REVIEW_STATE = "blockout - S1, not visually approved"
BAND_HEIGHTS = [-0.45 + 0.1125 * i for i in range(9)]
OUTLINE = (0.85, 1.15)
COLLIDE_R = 2.0          # every landmark's collision circle, bu
ANCHOR_R = 3.0           # every landmark's visual anchor, bu
TOP_MAX = 4.0
APRON_Z = -0.6
LANDMARK_SCALE = [0.92, 1.06]
BUDGET = {"shell": 1300, "landmark": 6000, "rare": 12000, "marker": 800}
FOOD_HUE, THREAT_HUE, HUE_GAP = 114.0, 11.0, 25.0

# Flat colours (linear RGB, roughness): silica blues, lavender, cream and amber.
FLAT = {
    "silica": ((0.62, 0.76, 0.88), 0.25), "frost": ((0.50, 0.64, 0.82), 0.4),
    "deep": ((0.20, 0.27, 0.45), 0.5), "core": ((0.80, 0.56, 0.25), 0.4),
    "cream": ((0.84, 0.66, 0.44), 0.5), "lavender": ((0.40, 0.33, 0.68), 0.45),
    "husk": ((0.55, 0.50, 0.66), 0.5), "amber": ((0.69, 0.38, 0.10), 0.45),
}
# warm was #F3E3C6 until T4 found five albedo x tint products over the look rule; #EAE5C7 clears them all.
TINTS = {"plain": "#FFFFFF", "frost": "#D6E0F5", "warm": "#EAE5C7"}


def _mats():
    return {k: bc.material(f"M_{k.title()}", c, r) for k, (c, r) in FLAT.items()}


def pascal(asset_id):
    return "".join(p.title() for p in asset_id.split("_"))


def _check(condition, message):
    if not condition:
        raise RuntimeError(message)


# --- Geometry helpers ---------------------------------------------------------------------------


def revolve(name, profile, mat, segments=48, location=(0.0, 0.0, 0.0), lobes=(0, 0.0), lobe_band=None):
    """[(radius, z)] around +Z. Lobes scallop the outline, faded out inside `lobe_band` (z lo, hi)."""
    verts, faces = [], []
    for r, z in profile:
        k_band = 1.0
        if lobe_band is not None and lobe_band[0] - 0.15 < z < lobe_band[1] + 0.15:
            k_band = 0.0
        for j in range(segments):
            a = math.tau * j / segments
            k = 1.0 + k_band * lobes[1] * math.cos(lobes[0] * a)
            verts.append((location[0] + r * k * math.cos(a), location[1] + r * k * math.sin(a), location[2] + z))
    rings = len(profile)
    for i in range(rings - 1):
        for j in range(segments):
            n = (j + 1) % segments
            faces.append((i * segments + j, i * segments + n, (i + 1) * segments + n, (i + 1) * segments + j))
    return _obj(name, verts, faces, mat)


def _obj(name, verts, faces, mat, smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    if smooth:
        mesh.shade_smooth()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    return obj


def tube(name, points, radius, mat, sides=8, taper=False):
    verts, faces = [], []
    n = len(points)
    for i, p in enumerate(points):
        t = (points[min(i + 1, n - 1)] - points[max(i - 1, 0)]).normalized()
        ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        a = t.cross(ref).normalized()
        b = t.cross(a).normalized()
        r = radius * ((1.0 - i / (n - 1)) ** 0.8 if taper else 1.0)
        for j in range(sides):
            ang = math.tau * j / sides
            verts.append(p + (a * math.cos(ang) + b * math.sin(ang)) * max(r, 1e-4))
    for i in range(n - 1):
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((i * sides + j, i * sides + k, (i + 1) * sides + k, (i + 1) * sides + j))
    return _obj(name, verts, faces, mat)


def sphere(name, radius, location, mat, segments=12, rings=6, scale=(1, 1, 1)):
    verts, faces = [], []
    for i in range(1, rings):
        th = math.pi * i / rings
        for j in range(segments):
            ph = math.tau * j / segments
            verts.append((location[0] + radius * scale[0] * math.sin(th) * math.cos(ph),
                          location[1] + radius * scale[1] * math.sin(th) * math.sin(ph),
                          location[2] + radius * scale[2] * math.cos(th)))
    top, bot = len(verts), len(verts) + 1
    verts += [(location[0], location[1], location[2] + radius * scale[2]), (location[0], location[1], location[2] - radius * scale[2])]
    for j in range(segments):
        k = (j + 1) % segments
        faces.append((top, j, k))
        for i in range(rings - 2):
            faces.append((i * segments + j, (i + 1) * segments + j, (i + 1) * segments + k, i * segments + k))
        faces.append(((rings - 2) * segments + k, (rings - 2) * segments + j, bot))
    return _obj(name, verts, faces, mat)


def torus(name, major, minor, mat, location=(0, 0, 0), rotation=(0, 0, 0), seg=(48, 10)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg[0],
                                     minor_segments=seg[1], location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def lattice(name, radius, location, mat, subdiv=2, thickness=0.04, squash=(1, 1, 1), keep=lambda co: True):
    """A wire lattice over an icosphere, keeping the vertices where keep(co) holds."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.scale = squash
    obj.location = location
    wire = obj.modifiers.new("Lattice", "WIREFRAME")
    wire.thickness = thickness
    wire.use_even_offset = True
    obj.data.materials.append(mat)
    return obj


def drum(name, r, top, bottom, mat, lobes=(0, 0.0), fillet=0.25, apron=None, segments=48):
    """The landmark body: a vertical wall of radius r through the swim band, a rounded rim at
    `top`, and below -0.6 m an optional apron flaring out to `apron` before it sinks to `bottom`."""
    prof = [(0.0, bottom)]
    if apron:
        prof += [(apron * 0.7, bottom + 0.2), (apron, -1.6), (apron * 0.98, -1.0), (r * 1.02, -0.75)]
    else:
        prof += [(r * 0.8, bottom + 0.3), (r, bottom + 1.0)]
    prof += [(r, -0.6), (r, -0.3), (r, 0.0), (r, 0.3), (r, top - fillet)]
    for i in range(1, 5):
        a = i / 4 * math.pi / 2
        prof.append((r - fillet + fillet * math.cos(a), top - fillet + fillet * math.sin(a)))
    prof += [(r * 0.5, top + 0.02), (0.0, top + 0.03)]
    return revolve(name, prof, mat, segments, lobes=lobes, lobe_band=(-0.5, 0.5))


# --- Assembly and checks ------------------------------------------------------------------------


def _apply_and_join(name, objs):
    for obj in objs:
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = f"{name}_mesh"
    return obj


def assemble(asset_id, growths=None):
    """Joins everything not in a growth into the root mesh; each growth list becomes a hidden
    child Growth_<Name>."""
    growths = growths or {}
    grown = {o for objs in growths.values() for o in objs}
    root = _apply_and_join(pascal(asset_id), [o for o in bpy.context.scene.objects if o.type == "MESH" and o not in grown])
    for gname, objs in growths.items():
        g = _apply_and_join(f"Growth_{gname}", objs)
        g.parent = root
        g.hide_set(True)
        g.hide_render = True
    return root


def _mesh_data(objs):
    pts, tris = [], []
    for obj in objs:
        base = len(pts)
        pts += [obj.matrix_world @ v.co for v in obj.data.vertices]
        obj.data.calc_loop_triangles()
        tris += [tuple(base + i for i in t.vertices) for t in obj.data.loop_triangles]
    return pts, tris


def _far(colliders, deg):
    d = Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg))))
    far = 0.0
    for c in colliders:
        cx, cy = c["center"]
        b = d.x * cx + d.y * cy
        disc = b * b - (cx * cx + cy * cy - c["radius"] ** 2)
        if disc >= 0.0:
            far = max(far, b + math.sqrt(disc))
    return far


def _edge_of_union(colliders, bins=360):
    """For each 1-degree azimuth bin, the (least, greatest) distance from the pivot to the far side
    of the collider union along rays inside the bin. Rays that graze a circle change fast, so a
    bin is judged against its whole range."""
    out = []
    for i in range(bins):
        samples = [_far(colliders, i + k / 4) for k in range(5)]
        out.append((min(samples), max(samples)))
    return out


def _hue(rgb_linear):
    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    r, g, b = rgb_linear
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    return math.degrees(math.atan2(200 * (f(y) - f(z)), 500 * (f(x) - f(y)))) % 360


def _gap(a, b):
    return abs((a - b + 180) % 360 - 180)


def check_contract(kind, asset_id, fields, scale_range):
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    pts, tris = _mesh_data(objs)
    xs, ys = [p.x for p in pts], [p.y for p in pts]
    _check(abs((max(xs) + min(xs)) / 2) <= 0.15 and abs((max(ys) + min(ys)) / 2) <= 0.15, f"{asset_id}: bounds not centred on the pivot")
    outline = mb.band_outline(pts, tris, BAND_HEIGHTS)
    top = max(p.z for p in pts)
    lo, hi = scale_range
    if kind == "shell":
        fr = fields["footprint_radius_m"]
        _check(OUTLINE[0] * fr <= min(outline) and max(outline) <= OUTLINE[1] * fr, f"{asset_id}: band outline {min(outline):.3f}-{max(outline):.3f} for footprint {fr}")
        _check(top <= 0.6 and min(p.z for p in pts) <= -1.5, f"{asset_id}: top {top:.2f} or base too high")
    elif kind == "landmark":
        # The band must meet the collider at both ends of the scale range.
        _check(OUTLINE[0] * COLLIDE_R <= min(outline) * lo and max(outline) * hi <= OUTLINE[1] * COLLIDE_R,
               f"{asset_id}: band outline {min(outline):.3f}-{max(outline):.3f} x scale {lo}-{hi}")
        _check(top * hi <= TOP_MAX, f"{asset_id}: top {top * hi:.2f} at the top scale")
        for p in pts:
            r = math.hypot(p.x, p.y) * hi
            _check(r <= ANCHOR_R + 1e-3, f"{asset_id}: reaches {r:.2f} past the anchor")
            _check(p.z * hi < APRON_Z or r <= OUTLINE[1] * COLLIDE_R + 1e-3, f"{asset_id}: overhang at r {r:.2f}, z {p.z * hi:.2f}")
    elif kind == "rare":
        edge = _edge_of_union(fields["colliders"])
        for o, (e_lo, e_hi) in zip(outline, edge):
            _check(o <= OUTLINE[1] * e_hi and o >= OUTLINE[0] * e_lo, f"{asset_id}: band outline {o:.2f} against the collider edge {e_lo:.2f}-{e_hi:.2f}")
        _check(top <= TOP_MAX, f"{asset_id}: top {top:.2f}")
        for p in pts:
            if p.z > 0.6:
                _check(any(math.hypot(p.x - c["center"][0], p.y - c["center"][1]) <= OUTLINE[1] * c["radius"] for c in fields["colliders"]),
                       f"{asset_id}: geometry above the plane outside the colliders at {tuple(round(v, 2) for v in p)}")
    for mat in bpy.data.materials:
        if mat.users and mat.node_tree:
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                rgb = tuple(bsdf.inputs["Base Color"].default_value[:3])
                if max(rgb) - min(rgb) > 0.03:
                    h = _hue(rgb)
                    _check(_gap(h, FOOD_HUE) >= HUE_GAP and _gap(h, THREAT_HUE) >= HUE_GAP, f"{asset_id}: {mat.name} hue {h:.0f}")
    fields.update({
        "swim_band_min_radius_m": round(min(o for o in outline if o > 0), 3),
        "swim_band_radius_m": round(max(outline), 3),
        "top_m": round(top, 3),
        "bottom_m": round(min(p.z for p in pts), 3),
        "scale_range": list(scale_range),
    })


# --- Shells -------------------------------------------------------------------------------------

SHELLS = {
    # id: (footprint class, footprint radius, scale range, wall top, dome rise, lobes, colour, what)
    "shell_diatom_disc": ("fp_s", 0.75, [0.8, 1.2], 0.42, 0.08, (36, 0.012), "silica", "a centric diatom disc, flat-topped with radial ribs"),
    "shell_radiolarian_lens": ("fp_s", 0.75, [0.8, 1.2], 0.36, 0.22, (12, 0.03), "frost", "a radiolarian lens, a low scalloped dome"),
    "shell_girdle_drum": ("fp_m", 1.05, [0.85, 1.15], 0.45, 0.12, (24, 0.015), "silica", "a tall diatom drum with a girdle band"),
    "shell_fluted_tower": ("fp_l", 1.2, [0.75, 1.25], 0.46, 0.1, (18, 0.025), "frost", "a fluted glass tower"),
    "shell_bell": ("fp_l", 1.35, [0.88, 1.12], 0.4, 0.18, (10, 0.03), "silica", "a broad bell-shaped shell"),
}


def build_shell(asset_id):
    cls, fr, scale, wall, dome, lobes, colour, what = SHELLS[asset_id]
    m = _mats()
    bottom = -1.6 - 0.4 * fr
    prof = [(0.0, bottom), (fr * 0.6, bottom + 0.15), (fr * 0.92, -1.1), (fr, -0.6), (fr, -0.3), (fr, 0.0), (fr, 0.3), (fr, wall)]
    for i in range(1, 6):
        a = i / 5 * math.pi / 2
        prof.append((fr * math.cos(a) ** 0.6, wall + dome * math.sin(a)))
    prof[-1] = (0.0, wall + dome)
    revolve("Body", prof, m[colour], 40, lobes=lobes, lobe_band=(-0.5, 0.5))
    if asset_id == "shell_girdle_drum":
        torus("Girdle", fr * 0.99, 0.05, m["frost"], (0, 0, -0.9), seg=(32, 4))
    assemble(asset_id)
    fields = {
        "purpose": f"Endless world band-0 shell (S1 rough): {what}. An obstacle the cell slides around; slots pick it by footprint class.",
        "category": "shell", "kind": "shell",
        "pivot": "centre of the footprint on the swim plane (Godot y = 0)",
        "footprint_class": cls, "footprint_radius_m": fr, "yaw_rule": "free", "pickable": True,
        "dressings": [{"id": "plain", "tint": TINTS["plain"], "growth": "", "scale": 1.0}],
    }
    check_contract("shell", asset_id, fields, scale)
    return fields


# --- Landmarks ----------------------------------------------------------------------------------


def _growths(m, rim_z, seed):
    """Two growths every landmark offers its dressings: amber bead clusters and glass needles,
    both on the body's rim, inside the overhang limit."""
    beads, needles = [], []
    for i in range(7):
        a = seed + i * math.tau / 7
        c = Vector((1.55 * math.cos(a), 1.55 * math.sin(a), rim_z + 0.05))
        for k in range(2):
            off = Vector((0.16 * math.cos(a + k * 3.1), 0.16 * math.sin(a + k * 3.1), 0.08 * k))
            beads.append(sphere(f"Bead{i}_{k}", 0.14 + 0.04 * k, c + off, m["amber"], 8, 4))
    for i in range(10):
        a = seed + 0.3 + i * math.tau / 10
        base = Vector((1.7 * math.cos(a), 1.7 * math.sin(a), rim_z - 0.05))
        d = Vector((0.25 * math.cos(a), 0.25 * math.sin(a), 1.0)).normalized()
        needles.append(tube(f"Needle{i}", [base, base + d * 0.4, base + d * 0.75], 0.05, m["frost"], 6, True))
    return {"Beads": beads, "Needles": needles}


def _dressings():
    return [
        {"id": "plain", "tint": TINTS["plain"], "growth": "", "scale": 1.0},
        {"id": "frosted", "tint": TINTS["frost"], "growth": "Growth_Needles", "scale": 0.96},
        {"id": "amber", "tint": TINTS["warm"], "growth": "Growth_Beads", "scale": 1.04},
    ]


def lm_great_shell(m):
    """A giant radiolarian dome on its shell drum, an amber heart inside, a crown of short spines."""
    drum("Drum", 2.0, 0.6, -3.2, m["frost"], (14, 0.03), apron=2.6)
    lattice("Dome", 1.85, (0, 0, 0.55), m["silica"], 2, 0.07, (1, 1, 1.25), keep=lambda co: co.z > -0.1)
    sphere("Heart", 0.75, (0, 0, 1.15), m["core"], 20, 10)
    for i in range(9):
        a = i * math.tau / 9
        base = Vector((0.9 * math.cos(a), 0.9 * math.sin(a), 2.55))
        d = Vector((0.3 * math.cos(a), 0.3 * math.sin(a), 1.0)).normalized()
        tube(f"Spine{i}", [base, base + d * 0.4, base + d * 0.8], 0.06, m["silica"], 6, True)
    return 0.6, 0.0


def lm_ring(m):
    """A giant diatom girdle band standing on edge in its cradle, with rows of pores."""
    drum("Cradle", 2.0, 0.35, -3.0, m["frost"], (24, 0.015), apron=2.5)
    torus("Hoop", 1.55, 0.3, m["silica"], (0, 0, 1.75), (math.pi / 2, 0, 0), (56, 10))
    for i in range(24):
        a = i * math.tau / 24
        p = Vector((1.55 * math.cos(a), 0.0, 1.75 + 1.55 * math.sin(a)))
        if p.z > 0.5:
            for side in (-1, 1):
                sphere(f"Pore{i}_{side}", 0.08, p + Vector((0, side * 0.27, 0)), m["lavender"], 6, 3, (1, 0.5, 1))
    return 0.35, 0.4


def lm_spire(m):
    """A sponge-spicule spire: three glass strands braided up from a lobed base, with hooks."""
    drum("Base", 2.0, 0.45, -3.4, m["frost"], (7, 0.04), apron=2.7)
    for s in range(3):
        pts = []
        for i in range(30):
            t = i / 29
            a = s * math.tau / 3 + t * math.tau * 1.2
            r = 0.75 * (1.0 - 0.75 * t)
            pts.append(Vector((r * math.cos(a), r * math.sin(a), 0.3 + 3.2 * t)))
        tube(f"Strand{s}", pts, 0.24, m["silica"], 8, True)
    for w in range(3):
        z = 1.0 + w * 0.8
        r = 0.75 * (1.0 - 0.75 * (z - 0.3) / 3.2)
        for k in range(6):
            a = math.tau * k / 6 + w
            base = Vector((r * math.cos(a), r * math.sin(a), z))
            out = Vector((math.cos(a), math.sin(a), 0.5)).normalized()
            tube(f"Hook{w}_{k}", [base, base + out * 0.45, base + out * 0.65 + Vector((0, 0, -0.2))], 0.045, m["frost"], 5, True)
    sphere("Tip", 0.2, (0, 0, 3.55), m["core"], 12, 6)
    return 0.45, 0.8


def lm_fan(m):
    """A fan colony: cream stalks branching from a dark holdfast, holding amber bell cells."""
    drum("Holdfast", 2.0, 0.3, -3.2, m["deep"], (6, 0.04), apron=2.6)

    def branch(base, direction, length, depth, idx):
        tip = base + direction * length
        tube(f"Stalk{idx}", [base, base + direction * length * 0.5, tip], 0.03 + 0.025 * depth, m["cream"], 6)
        if depth == 0:
            sphere(f"Bell{idx}", 0.16, tip + direction * 0.1, m["amber"], 8, 4, (1, 1, 0.8))
            return
        for k, turn in enumerate((-0.45, 0.45)):
            d = Vector((direction.x * math.cos(turn) - direction.z * math.sin(turn) * 0.6, direction.y + turn * 0.2, direction.z)).normalized()
            branch(tip, d, length * 0.7, depth - 1, f"{idx}{k}")

    tube("Trunk", [Vector((0, 0, 0.2)), Vector((0, 0, 0.8)), Vector((0, 0, 1.3))], 0.16, m["cream"], 10)
    for k, yaw in enumerate((-0.55, -0.18, 0.18, 0.55)):
        branch(Vector((0, 0, 1.3)), Vector((math.sin(yaw), 0.12 * (k - 1.5), math.cos(yaw))).normalized(), 0.9, 3, f"B{k}")
    return 0.3, 1.6


def lm_arch(m):
    """A curved silica rib springing across its drum, ringed like a long-dead colony's frustule."""
    drum("Drum", 2.0, 0.4, -3.0, m["frost"], (9, 0.03), apron=2.6)
    pts = [Vector((-1.5 * math.cos(math.pi * t), 0.0, 0.3 + 2.95 * math.sin(math.pi * t))) for t in [i / 30 for i in range(31)]]
    tube("Rib", pts, 0.3, m["silica"], 14)
    for i in range(3, 28, 3):
        t = (pts[i + 1] - pts[i - 1]).normalized()
        torus(f"Band{i}", 0.33, 0.05, m["frost"], tuple(pts[i]), t.to_track_quat("Z", "Y").to_euler(), (20, 6))
    for i in (6, 12, 18, 24):
        sphere(f"Bead{i}", 0.12, pts[i] + Vector((0, 0, 0.32)), m["amber"], 10, 5)
    return 0.4, 2.3


def lm_shed_husk(m):
    """A shed casing: the empty, vase-shaped lorica a giant ciliate left behind, open at the top
    with a flared collar, ringed with growth bands and split down one side."""
    outer = [(0.0, -3.0), (1.6, -2.7), (2.0, -1.8), (2.0, -0.6), (2.0, 0.0), (2.0, 0.5), (1.85, 1.2), (1.55, 2.0),
             (1.4, 2.7), (1.55, 3.15), (1.9, 3.4), (1.95, 3.5)]
    inner = [(r - 0.12, z) for r, z in reversed(outer[5:])] + [(1.7, 0.6), (0.0, 0.6)]
    revolve("Lorica", outer + inner, m["husk"], 48, lobes=(5, 0.03), lobe_band=(-0.5, 0.5))
    for k, z in enumerate((0.9, 1.6, 2.3)):
        r = 1.85 - 0.18 * k - 0.05
        torus(f"GrowthBand{k}", r + 0.04, 0.05, m["frost"], (0, 0, z), seg=(48, 6))
    # The split: a dark seam down one side of the casing.
    pts = [Vector((1.9 - 0.25 * t, 0.05 * math.sin(t * 9), 0.7 + 2.6 * t)) for t in [k / 12 for k in range(13)]]
    tube("Split", [Vector((p.x * (1.55 + 0.3 * (1 - (p.z - 0.7) / 2.6)) / 1.9, p.y, p.z)) for p in pts], 0.06, m["deep"], 6)
    return 0.6, 3.1


LANDMARKS = {
    "landmark_great_shell": (lm_great_shell, 0, "free", "a giant radiolarian dome over a glowing amber heart"),
    "landmark_ring": (lm_ring, 0, "steps_90", "a giant diatom girdle band standing on edge in its cradle"),
    "landmark_spire": (lm_spire, 1, "free", "a braided sponge-spicule spire with whorls of hooks"),
    "landmark_fan": (lm_fan, 1, "steps_90", "a fan colony of cream stalks holding amber bell cells"),
    "landmark_arch": (lm_arch, 2, "steps_90", "a ringed silica rib arching over its drum"),
    "landmark_shed_husk": (lm_shed_husk, 3, "free", "the empty, split casing a giant ciliate shed"),
}


def build_landmark(asset_id):
    builder, group, yaw_rule, what = LANDMARKS[asset_id]
    m = _mats()
    rim_z, seed = builder(m)
    growths = _growths(m, rim_z, seed)
    assemble(asset_id, growths)
    fields = {
        "purpose": f"Endless world band-0 landmark (S1 rough): {what}. Collides as a 2 bu circle; the visual fills the 3 bu anchor.",
        "category": "landmark", "kind": "landmark",
        "pivot": "centre of the anchor on the swim plane (Godot y = 0)",
        "group": group, "footprint_radius_m": COLLIDE_R, "collide_radius_bu": COLLIDE_R, "anchor_radius_bu": ANCHOR_R,
        "yaw_rule": yaw_rule, "dressings": _dressings(),
    }
    check_contract("landmark", asset_id, fields, LANDMARK_SCALE)
    return fields


# --- Rare set pieces ----------------------------------------------------------------------------


def rare_giant_husk(m):
    """The cracked-open glass husk of a dead giant microbe, picked clean: its broken lattice
    shell lies in pieces in a row, with snapped silica spines and the empty central capsule.
    No soft tissue and no food rim."""
    colliders = []
    for i, (x, y, r) in enumerate([(-3.4, 0.4, 1.1), (-1.15, -0.3, 1.3), (1.15, 0.3, 1.25), (3.4, -0.35, 1.1)]):
        colliders.append({"center": [x, y], "radius": r})
        revolve(f"Stump{i}", [(0.0, -2.6), (r * 0.9, -2.2), (r, -1.2), (r, -0.6), (r, 0.0), (r, 0.4), (r * 0.9, 0.55), (0.0, 0.6)],
                m["frost"], 32, (x, y, 0.0), (10, 0.03), (-0.5, 0.5))
        lattice(f"Broken{i}", r * 0.95, (x, y, 0.55), m["silica"], 2, 0.06, (1, 1, 1.1),
                keep=lambda co, k=i: co.z > 0.0 and (math.atan2(co.y, co.x) + k) % math.tau > 1.6)
        for s in range(4):
            a = s * math.tau / 4 + i
            base = Vector((x + 0.5 * r * math.cos(a), y + 0.5 * r * math.sin(a), 0.6))
            tube(f"Spine{i}_{s}", [base, base + Vector((0.1 * math.cos(a), 0.1 * math.sin(a), 0.6 + 0.3 * (s % 2)))], 0.06, m["silica"], 6, True)
    # Snapped spines lie scattered below the plane, where they may spread past the colliders.
    for i in range(5):
        a = i * 0.9
        for sgn in (1, -1):
            p = Vector((sgn * (-3.6 + 1.6 * i), sgn * 1.6 * math.sin(i * 1.7), -1.4))
            d = Vector((sgn * math.cos(a), sgn * math.sin(a), -0.2)).normalized()
            tube(f"Shard{i}_{sgn}", [p, p + d * 0.6, p + d * 1.1], 0.07, m["frost"], 6, True)
    sphere("Capsule", 0.55, (1.15, 0.3, 1.15), m["core"], 14, 7)
    return colliders


def rare_shell_cathedral(m):
    """Eight tall glass drums in a ring round an open nave, each crowned with a lattice spire,
    and a warm light deep below the nave floor."""
    colliders = []
    for i in range(8):
        a = i * math.tau / 8
        x, y = 3.4 * math.cos(a), 3.4 * math.sin(a)
        colliders.append({"center": [round(x, 4), round(y, 4)], "radius": 0.9})
        h = 1.6 + 0.6 * (i % 2)
        revolve(f"Drum{i}", [(0.0, -3.0), (0.8, -2.7), (0.9, -1.6), (0.9, -0.6), (0.9, 0.0), (0.9, 0.6), (0.9, h),
                             (0.75, h + 0.15), (0.0, h + 0.2)], m["silica"], 32, (x, y, 0.0), (16, 0.02), (-0.5, 0.5))
        lattice(f"Spire{i}", 0.7, (x, y, h + 0.15), m["frost"], 2, 0.05, (1, 1, 2.2), keep=lambda co: co.z > -0.05)
    # The nave floor: a shallow lattice bowl well under the swim plane.
    lattice("Floor", 4.6, (0, 0, -0.9), m["frost"], 2, 0.03, (1, 1, 0.25), keep=lambda co: co.z < 0.05)
    sphere("Light", 0.6, (0, 0, -1.8), m["core"], 16, 8)
    return colliders


RARES = {
    "rare_giant_husk": (rare_giant_husk, "giant_husk", "the cracked-open glass husk of a dead giant microbe, its lattice in pieces"),
    "rare_shell_cathedral": (rare_shell_cathedral, "shell_cathedral", "eight crowned glass drums in a ring round an open nave"),
}


def build_rare(asset_id):
    builder, rare_kind, what = RARES[asset_id]
    colliders = builder(_mats())
    assemble(asset_id)
    fields = {
        "purpose": f"Endless world band-0 rare place (S1 rough): {what}.",
        "category": "rare", "kind": "rare",
        "pivot": "centre of the set piece on the swim plane (Godot y = 0)",
        "rare_kind": rare_kind, "colliders": colliders, "yaw_rule": "fixed", "dressings": [],
    }
    check_contract("rare", asset_id, fields, [1.0, 1.0])
    return fields


# --- Markers ------------------------------------------------------------------------------------


def build_checkpoint_column():
    """Where you come back: an open cream tube 0.5 bu wide, from deep below to high above the
    plane. UV v runs 0 at the bottom to 1 at the top, so the engine's unlit shader fades both ends."""
    mat = bc.material("M_Column", (0.84, 0.66, 0.44), 0.5, emission=(0.84, 0.66, 0.44), emission_strength=2.0)
    verts, faces, seg = [], [], 24
    heights = [-4.0 + 2.0 * i for i in range(8)]
    for z in heights:
        for j in range(seg):
            a = math.tau * j / seg
            verts.append((0.25 * math.cos(a), 0.25 * math.sin(a), z))
    for i in range(len(heights) - 1):
        for j in range(seg):
            k = (j + 1) % seg
            faces.append((i * seg + j, i * seg + k, (i + 1) * seg + k, (i + 1) * seg + j))
    bc.mesh_object("MarkerCheckpointColumn", verts, faces, [mat], fix_normals=False,
                   uv=lambda co: ((math.atan2(co.y, co.x) / math.tau) % 1.0, (co.z + 4.0) / 14.0))
    return {
        "purpose": "Endless world marker (S1 rough): the cream light column at the current checkpoint, 'where you come back'. No collision; drawn unlit by the engine.",
        "category": "marker", "kind": "marker", "pivot": "the checkpoint on the swim plane (Godot y = 0)",
        "yaw_rule": "fixed", "dressings": [], "scale_range": [1.0, 1.0],
    }


def build_origin_arrow():
    """Where you began: a flat cream chevron 1.2 bu long, pointing Blender +Y (Godot -Z)."""
    mat = bc.material("M_Arrow", (0.84, 0.66, 0.44), 0.5, emission=(0.84, 0.66, 0.44), emission_strength=1.0)
    outline = [(0.0, 0.6), (0.5, -0.1), (0.24, -0.1), (0.24, -0.6), (-0.24, -0.6), (-0.24, -0.1), (-0.5, -0.1)]
    t = 0.04
    verts = [(x, y, t) for x, y in outline] + [(x, y, -t) for x, y in outline]
    n = len(outline)
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    bc.mesh_object("MarkerOriginArrow", verts, faces, [mat], smooth=False)
    return {
        "purpose": "Endless world marker (S1 rough): the cream arrow toward the origin, 'where you began'. Lies flat; a different shape from the column.",
        "category": "marker", "kind": "marker", "pivot": "centre of the arrow; it points Godot -Z",
        "yaw_rule": "fixed", "dressings": [], "scale_range": [1.0, 1.0],
    }


# The Lurker's lair mouth (docs/s2/lurker-lair-mouth-spec.md): authored in units of the Lurker's drawn radius R = 1.
LAIR_INNER, LAIR_OUTER, LAIR_FLOOR = 1.3, 2.6, -1.2
LAIR_ARC = 240.0        # degrees of crust; the gap is centred on +X, the post heading and the Lurker's lunge
LAIR_COLOR = (0.16, 0.2, 0.25)    # linear: the silt trail's grey-blue, luminance under 0.40, no mauve


def build_lair_mouth():
    """An open horseshoe of silt-crusted shell grit round a darker silt hollow, with a few flattened
    shell flakes in the crust. Low, broken and granular, so it never reads as a shell or a food patch.
    The origin is the ring's centre at lip-top height; everything is at or below it."""
    import random
    rng = random.Random(41)
    mat = bc.material("M_LairMouth", LAIR_COLOR, 0.85)
    half = math.radians(LAIR_ARC) / 2.0
    cols, radial = 26, [LAIR_INNER, 1.45, 1.75, 2.05, 2.35, LAIR_OUTER]
    # Crest height across the crust (0 at the inner wall foot, 1 at the crest), broken by noise.
    lift = [0.0, 0.78, 1.0, 0.8, 0.45, 0.12]
    verts, faces, grid = [], [], []
    for c in range(cols + 1):
        t = c / cols
        a = math.pi - half + 2.0 * half * t           # from one horn of the horseshoe round the back to the other
        end = min(t, 1.0 - t)
        taper = min(1.0, end / 0.16) ** 0.8         # the arms crumble down toward the opening
        pinch = min(1.0, end / 0.1)                  # and narrow to a ragged point of grit
        ragged = 0.22 * math.sin(5.0 * a + 0.7) * math.sin(11.0 * a + 2.1) + rng.uniform(-0.12, 0.12)
        row = []
        for k, r0 in enumerate(radial):
            if k == len(radial) - 1:
                r0 = r0 + ragged                         # a broken outer edge, never a clean arc
            elif k > 0:
                r0 = r0 + rng.uniform(-0.07, 0.07)
            r = 1.9 + (r0 - 1.9) * (0.25 + 0.75 * pinch)
            crest = lift[k] * taper * (0.82 + 0.18 * math.sin(7.0 * a + 1.3) * math.cos(3.0 * a)) - rng.uniform(0.0, 0.1) * lift[k]
            z = LAIR_FLOOR + (0.0 - LAIR_FLOOR) * crest if k < 3 else -0.95 + 0.95 * crest
            z = min(0.0, z)
            row.append(len(verts))
            verts.append((r * math.cos(a), r * math.sin(a), z))
        grid.append(row)
    for c in range(cols):
        for k in range(len(radial) - 1):
            faces.append((grid[c][k], grid[c][k + 1], grid[c + 1][k + 1], grid[c + 1][k]))
    # The hollow's silt floor: a disc inside the inner radius.
    seg = 18
    centre = len(verts)
    verts.append((0.0, 0.0, LAIR_FLOOR))
    ring = []
    for j in range(seg):
        a = math.tau * j / seg
        ring.append(len(verts))
        verts.append((LAIR_INNER * 1.02 * math.cos(a), LAIR_INNER * 1.02 * math.sin(a), LAIR_FLOOR + 0.02 * math.sin(3 * a)))
    for j in range(seg):
        faces.append((centre, ring[j], ring[(j + 1) % seg]))
    # A few shed shell flakes lying flat in the crust.
    for i in range(5):
        a = math.pi - half * 0.85 + 2.0 * half * 0.85 * (i + rng.uniform(0.2, 0.8)) / 5
        r = rng.uniform(1.6, 2.2)
        cx, cy = r * math.cos(a), r * math.sin(a)
        size = rng.uniform(0.16, 0.26)
        tilt = rng.uniform(-0.15, 0.15)
        cz = -0.06 - rng.uniform(0.0, 0.12)
        base = len(verts)
        sides = rng.choice((4, 5, 6))
        for j in range(sides):
            b = math.tau * j / sides + rng.uniform(-0.35, 0.35)
            reach = size * rng.uniform(0.55, 1.0)
            dx, dy = reach * math.cos(b), reach * 0.7 * math.sin(b)
            verts.append((cx + dx, cy + dy, min(0.0, cz + tilt * dx)))
        faces.append(tuple(range(base, base + sides)))
    bc.mesh_object("LairMouth", verts, faces, [mat], fix_normals=False, smooth=True)
    return {
        "purpose": "S2 Lurker lair mouth (marker): an open horseshoe reef mouth of silt-crusted shell grit round a darker silt hollow, placed at both posts of every Lurker site so both read as lairs. Authored at R = 1 (the Lurker's drawn radius); the opening faces +X, the post heading. No collision.",
        "category": "marker", "kind": "marker",
        "pivot": "centre of the ring at lip-top height; all geometry at or below it (Godot y <= 0)",
        "yaw_rule": "fixed", "dressings": [], "scale_range": [1.0, 1.0],
        "authored_radius": {"inner": LAIR_INNER, "outer": LAIR_OUTER, "floor": LAIR_FLOOR, "arc_deg": LAIR_ARC, "units": "the Lurker's drawn radius"},
    }


ASSETS = {
    **{i: ((lambda i=i: build_shell(i)), BUDGET["shell"]) for i in SHELLS},
    **{i: ((lambda i=i: build_landmark(i)), BUDGET["landmark"]) for i in LANDMARKS},
    **{i: ((lambda i=i: build_rare(i)), BUDGET["rare"]) for i in RARES},
    "marker_checkpoint_column": (build_checkpoint_column, BUDGET["marker"]),
    "marker_origin_arrow": (build_origin_arrow, BUDGET["marker"]),
    "marker_lair_mouth": (build_lair_mouth, 600),
}


KIT_PATH = os.path.join(bc.ROOT, "game", "data", "placement_kit.json")
KIT_ORDER = list(SHELLS) + list(LANDMARKS) + list(RARES) + ["marker_checkpoint_column", "marker_origin_arrow", "marker_lair_mouth"]
# The pool's three M1 rocks, used only by the home block's fixed rocks (rule 12).
HOME_ROCKS = ["rock_a", "rock_b", "rock_c"]


def write_kit():
    """game/data/placement_kit.json (docs/s1/s1-interfaces.md 4.4) from the records, so the kit
    always agrees with what was exported."""
    import json
    assets = []
    for asset_id in KIT_ORDER + HOME_ROCKS:
        with open(os.path.join(bc.ROOT, "assets", "records", f"{asset_id}.json")) as f:
            rec = json.load(f)
        kind = rec.get("kind", "shell")
        entry = {"id": asset_id, "kind": kind, "band": -1 if kind == "marker" else 0,
                 "glb": f"res://{rec['export_path']}", "record": f"res://assets/records/{asset_id}.json"}
        if asset_id in HOME_ROCKS:
            entry.update({"footprint_class": "fp_m", "footprint_radius_m": 1.0, "pickable": False, "scale": [0.8, 1.5],
                          "yaw_rule": "free", "dressings": [{"id": "plain", "tint": "#FFFFFF", "growth": "", "scale": 1.0}]})
        else:
            entry.update({"scale": rec["scale_range"], "yaw_rule": rec["yaw_rule"], "dressings": rec["dressings"]})
            if kind == "shell":
                entry.update({k: rec[k] for k in ("footprint_class", "footprint_radius_m", "pickable")})
            elif kind == "landmark":
                entry.update({"group": rec["group"], "footprint_radius_m": rec["footprint_radius_m"]})
            elif kind == "rare":
                entry.update({"rare_kind": rec["rare_kind"], "colliders": rec["colliders"]})
        entry["placeholder"] = rec["review_state"].startswith("blockout")
        entry["approved"] = rec.get("status") == "APPROVED" and not entry["placeholder"]
        assets.append(entry)
    kit = {
        "schema_version": 1, "status": "PROPOSED",
        "note": "Band-0 placement kit for the endless world (docs/s1/s1-interfaces.md 4.4). Written by tools/blender/make_s1_kit.py from the asset records.",
        "footprint_classes": {"fp_s": [0.6, 0.9], "fp_m": [0.9, 1.2], "fp_l": [1.2, 1.5]},
        "landmark": {"anchor_radius_bu": ANCHOR_R, "collide_radius_bu": COLLIDE_R, "groups": [2, 2, 1, 1]},
        "assets": assets,
    }
    with open(KIT_PATH, "w") as f:
        json.dump(kit, f, indent=2)
        f.write("\n")
    print("wrote", KIT_PATH)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the endless world's S1 kit (rough pieces).")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    args = parser.parse_args(argv)
    ids = [i for i in args.only.split(",") if i] or list(ASSETS)
    unknown = [i for i in ids if i not in ASSETS]
    if unknown:
        parser.error(f"unknown asset id(s): {', '.join(unknown)}; known: {', '.join(ASSETS)}")
    for asset_id in ids:
        builder, budget = ASSETS[asset_id]
        bc.reset_scene()
        fields = builder()
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")
    write_kit()


if __name__ == "__main__":
    main()
    sys.stdout.flush()
