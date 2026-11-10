"""Gate review renders for the creature world's assets (tools/blender/make_creature_world.py and its kit), for the
finish gates every 3D asset passes: Gate 1 shape, Gate 2 materials with identity, Gate 3 neutral lighting
(docs/art/creature_world_gates.md records the verdicts). render_production.py keeps its own turntable sheet; this
adds the views that sheet lacks.

For each asset it opens assets/source/blender/<id>.blend, centres it and scales it to about 1.4 units (as
render_production.py does, so lookdev's review lights fit every asset), adds lookdev's review lighting and renders:
  grey_front, grey_side, grey_34, grey_top   Gate 1: neutral clay with one extra grazing key (a low sun from the
                                             left, about 9 degrees above the ground) that rakes broad faces; card
                                             materials keep their alpha cut, so cards show their cut-out shapes
  beauty_34                                  Gate 2/3: the baked materials under the neutral review lights
  closeup                                    Gate 2: the materials up close, through a long lens from outside the
                                             asset (--focus and --closeup-m aim it)
  unlit_34                                   Gate 2: base colour only, no lighting (every Principled base colour
                                             rewired to an emission, Standard view transform), so baked-in light
                                             and hue drift show
  alpha_34, alpha_top                        card assets only: white where the alpha passes Godot's 0.5 scissor,
                                             a see-through red where the card is cut away, so the red deepens with
                                             every layer of card drawn for nothing (overdraw)
A material with Backface Culling on (glTF doubleSided false; the kit's two-sheet cards) is drawn see-through from
behind in every view, as Godot culls it: Cycles itself ignores that flag.
PNGs go to --scratch (default builds/review/<id>/, not kept in git); a labelled contact sheet goes to
docs/art/renders/production/<id>_gates.jpg (ImageMagick montage, a review tool only, not a game dependency).

Run: python tools/blender/render_world_review.py <id> [<id> ...] [--focus x,y,z] [--closeup-m M] [--pitch DEG]
     [--samples N] [--resolution PX] [--scratch DIR] [--no-sheet]
--focus is a point in the asset's own Blender coordinates (metres, +Y front, +Z up) for the close-up, and
--closeup-m the close-up camera's distance from it in metres; by default the close-up aims at the asset's centre
from the review distance through a 135 mm lens (about a quarter of the review frame's width). --pitch overrides the grey views' camera pitch (default 12 degrees, or 32
for a flat asset whose height is under a quarter of its width).
"""
import argparse
import math
import os
import shutil
import subprocess
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookdev as ld  # noqa: E402

SHEET_DIR = os.path.join(ld.RENDER_DIR, "production")
SIZE = 1.4            # the asset's longest side after scaling, units
DISTANCE = 2.4        # the review camera's distance, units (render_production.py's)
LENS = 55.0
CLOSE_LENS = 135.0
GRAZE_ELEVATION_DEG = 9.0
CUT_RED = (0.8, 0.12, 0.08, 1.0)
CUT_OPACITY = 0.3


def _meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name != "Ground"]


def _bounds():
    lo, hi = [1e9] * 3, [-1e9] * 3
    for obj in _meshes():
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            lo = [min(a, b) for a, b in zip(lo, w)]
            hi = [max(a, b) for a, b in zip(hi, w)]
    return lo, hi


def _principled(mat):
    if not mat or not mat.node_tree:
        return None
    return next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)


def _output(nt):
    outs = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"]
    return next((n for n in outs if n.is_active_output), outs[0] if outs else None) or nt.nodes.new("ShaderNodeOutputMaterial")


def _feed(nt, src_input, dst_input):
    """Copies what drives `src_input` (a link or a default value) onto `dst_input`."""
    if src_input.is_linked:
        nt.links.new(src_input.links[0].from_socket, dst_input)
    else:
        value = src_input.default_value
        dst_input.default_value = value if not hasattr(value, "__len__") else tuple(value)[:len(dst_input.default_value)]


def _cut_by_alpha(nt, bsdf, shader_socket, out):
    """Routes `shader_socket` to the output through the material's alpha, so cut-away card areas stay see-through."""
    if bsdf is None or not bsdf.inputs["Alpha"].is_linked:
        nt.links.new(shader_socket, out.inputs["Surface"])
        return
    mix = nt.nodes.new("ShaderNodeMixShader")
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    step = nt.nodes.new("ShaderNodeMath")
    step.operation = "GREATER_THAN"
    step.inputs[1].default_value = 0.5
    nt.links.new(bsdf.inputs["Alpha"].links[0].from_socket, step.inputs[0])
    nt.links.new(step.outputs[0], mix.inputs["Fac"])
    nt.links.new(clear.outputs[0], mix.inputs[1])
    nt.links.new(shader_socket, mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def _cull_backfaces(mat):
    """Cycles ignores a material's Backface Culling flag, which Godot honours (glTF doubleSided false); a two-sided
    card made of two sheets back to back would then draw both sheets. For such a material the review routes the
    surface through a transparent shader wherever the face is seen from behind, as the engine culls it."""
    if mat is None or not mat.use_backface_culling or not mat.node_tree:
        return
    nt = mat.node_tree
    out = _output(nt)
    if not out.inputs["Surface"].is_linked or out.inputs["Surface"].links[0].from_node.name == "ReviewCull":
        return
    src = out.inputs["Surface"].links[0].from_socket
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.name = "ReviewCull"
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    nt.links.new(geo.outputs["Backfacing"], mix.inputs["Fac"])
    nt.links.new(src, mix.inputs[1])
    nt.links.new(clear.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def _unlit_copy(mat):
    """`mat` with its Principled base colour as an emission of strength 1 (no lighting at all)."""
    copy = mat.copy()
    copy.name = mat.name + "_unlit"
    nt = copy.node_tree
    bsdf = _principled(copy)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    if bsdf is None:
        print(f"  {mat.name}: no Principled BSDF; shown magenta in the unlit pass")
        emit.inputs["Color"].default_value = (1.0, 0.0, 1.0, 1.0)
    else:
        _feed(nt, bsdf.inputs["Base Color"], emit.inputs["Color"])
    _cut_by_alpha(nt, bsdf, emit.outputs[0], _output(nt))
    _cull_backfaces(copy)
    return copy


def _alpha_copy(mat):
    """White where the material's alpha passes 0.5, a see-through red where it is cut; dark grey when opaque."""
    copy = mat.copy()
    copy.name = mat.name + "_alpha"
    nt = copy.node_tree
    bsdf = _principled(copy)
    out = _output(nt)
    keep = nt.nodes.new("ShaderNodeEmission")
    if bsdf is None or not bsdf.inputs["Alpha"].is_linked:
        keep.inputs["Color"].default_value = (0.12, 0.12, 0.12, 1.0)
        nt.links.new(keep.outputs[0], out.inputs["Surface"])
        return copy
    keep.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    cut = nt.nodes.new("ShaderNodeEmission")
    cut.inputs["Color"].default_value = CUT_RED
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    tint = nt.nodes.new("ShaderNodeMixShader")   # the cut area: CUT_OPACITY of red over what lies behind
    tint.inputs["Fac"].default_value = CUT_OPACITY
    nt.links.new(clear.outputs[0], tint.inputs[1])
    nt.links.new(cut.outputs[0], tint.inputs[2])
    step = nt.nodes.new("ShaderNodeMath")
    step.operation = "GREATER_THAN"
    step.inputs[1].default_value = 0.5
    nt.links.new(bsdf.inputs["Alpha"].links[0].from_socket, step.inputs[0])
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(step.outputs[0], mix.inputs["Fac"])
    nt.links.new(tint.outputs[0], mix.inputs[1])
    nt.links.new(keep.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    _cull_backfaces(copy)
    return copy


def _clay_copy(mat):
    """The review clay for `mat`: lookdev's shared clay, or for a card material a clay copy that keeps the card's
    alpha cut at 0.5 (Godot's scissor), so Gate 1 judges the cut-out shapes and not the quads."""
    bsdf = _principled(mat)
    if bsdf is None or not bsdf.inputs["Alpha"].is_linked:
        return ld.clay_material()
    clay_bsdf = _principled(ld.clay_material())
    copy = mat.copy()
    copy.name = mat.name + "_clay"
    nt = copy.node_tree
    bsdf = _principled(copy)
    for name in ("Base Color", "Roughness", "Metallic", "Normal", "Emission Color"):
        for link in list(bsdf.inputs[name].links):
            nt.links.remove(link)
    bsdf.inputs["Base Color"].default_value = clay_bsdf.inputs["Base Color"].default_value
    bsdf.inputs["Roughness"].default_value = clay_bsdf.inputs["Roughness"].default_value
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Strength"].default_value = 0.0
    step = nt.nodes.new("ShaderNodeMath")
    step.operation = "GREATER_THAN"
    step.inputs[1].default_value = 0.5
    nt.links.new(bsdf.inputs["Alpha"].links[0].from_socket, step.inputs[0])
    nt.links.new(step.outputs[0], bsdf.inputs["Alpha"])
    return copy


def _swap(make):
    """Replaces every slot material of the asset's meshes by make(material); returns a restore function."""
    made, saved = {}, []
    for obj in _meshes():
        for i, slot in enumerate(obj.material_slots):
            if slot.material is None:
                continue
            if slot.material.name not in made:
                made[slot.material.name] = make(slot.material)
            saved.append((obj, i, slot.material))
            slot.material = made[slot.material.name]

    def restore():
        for obj, i, m in saved:
            obj.material_slots[i].material = m
    return restore


def _is_cards():
    return any((b := _principled(s.material)) is not None and b.inputs["Alpha"].is_linked
               for o in _meshes() for s in o.material_slots if s.material)


def _grazing_key():
    light = bpy.data.lights.new("Graze", "SUN")
    light.energy = 2.2
    light.angle = math.radians(2.0)
    light.color = (1.0, 0.95, 0.88)
    obj = bpy.data.objects.new("Graze", light)
    # Light travels along the object's -Z: from the left (-X), GRAZE_ELEVATION_DEG above the ground.
    e = math.radians(GRAZE_ELEVATION_DEG)
    direction = Vector((math.cos(e), -0.25, -math.sin(e))).normalized()
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render(asset_id, args):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ld.ROOT, "assets", "source", "blender", f"{asset_id}.blend"))
    for mat in bpy.data.materials:
        _cull_backfaces(mat)                  # before the copies below, which keep it (the clay) or redo it
    lo, hi = _bounds()
    centre = [(a + b) / 2 for a, b in zip(lo, hi)]
    dims = [b - a for a, b in zip(lo, hi)]
    size = max(dims)
    scale = SIZE / size
    for obj in bpy.context.scene.objects:
        if obj.parent is None:
            obj.location = [(o - c) * scale for o, c in zip(obj.location, centre)]
            obj.scale = [s * scale for s in obj.scale]
    flat = dims[2] < 0.25 * max(dims[0], dims[1])
    pitch = args.pitch if args.pitch is not None else (32.0 if flat else 12.0)
    print(f"{asset_id}: {dims[0]:.2f} x {dims[1]:.2f} x {dims[2]:.2f} m, scaled x{scale:.4f}, grey pitch {pitch:g}")

    ld.setup_render(resolution=args.resolution, samples=args.samples)
    scene = bpy.context.scene
    # Card clumps stack many cut-out layers (two sheets a card, one culled to transparent): Cycles' default of 8
    # transparent bounces ends a ray inside a clump and leaves a grey veil where the cards are cut away.
    scene.cycles.transparent_max_bounces = 64
    ld.review_lighting()
    review_world = scene.world
    floor = ld.ground_disc(radius=200, z=(lo[2] - centre[2]) * scale - 0.002)
    cam = ld.camera(lens=LENS)
    out = args.scratch.replace("{id}", asset_id)
    os.makedirs(out, exist_ok=True)
    shots = []

    def shot(name, yaw, pitch_deg, distance=DISTANCE, target=(0.0, 0.0, 0.0), lens=LENS):
        cam.data.lens = lens
        ld.aim(cam, target, distance, yaw, pitch_deg)
        path = os.path.join(out, f"{asset_id}_{name}.png")
        ld.render_to(path)
        shots.append(path)

    # Gate 1: clay with the grazing key.
    graze = _grazing_key()
    restore = _swap(_clay_copy)
    shot("grey_front", 0.0, pitch)
    shot("grey_side", 90.0, pitch)
    shot("grey_34", 35.0, pitch)
    shot("grey_top", 35.0, 80.0)
    restore()
    bpy.data.objects.remove(graze)

    # Gate 2/3: the materials under the neutral review lights, then up close.
    shot("beauty_34", 35.0, max(pitch, 22.0))
    if args.focus:
        focus = Vector([(f - c) * scale for f, c in zip(args.focus, centre)])
    else:
        focus = Vector((0.0, 0.0, 0.0))
    near = args.closeup_m * scale if args.closeup_m else DISTANCE
    shot("closeup", 35.0, 30.0, near, tuple(focus), CLOSE_LENS)

    # Unlit base colour and alpha coverage: emission only, Standard view, a plain grey backdrop, no ground.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    grey = bpy.data.worlds.new("W_Grey")
    grey.use_nodes = True
    grey.node_tree.nodes["Background"].inputs["Color"].default_value = (0.18, 0.18, 0.18, 1.0)
    scene.world = grey
    floor.hide_render = True
    restore = _swap(_unlit_copy)
    shot("unlit_34", 35.0, max(pitch, 22.0))
    restore()
    if _is_cards():
        restore = _swap(_alpha_copy)
        shot("alpha_34", 35.0, max(pitch, 22.0))
        shot("alpha_top", 35.0, 80.0)
        restore()
    scene.world = review_world
    floor.hide_render = False

    if not args.no_sheet and shutil.which("montage"):
        os.makedirs(SHEET_DIR, exist_ok=True)
        sheet = os.path.join(SHEET_DIR, f"{asset_id}_gates.jpg")
        labelled = []
        for p in shots:
            labelled += ["-label", os.path.basename(p)[len(asset_id) + 1:-4], p]
        subprocess.run(["montage", *labelled, "-tile", "4x", "-geometry", "360x360+3+3", "-pointsize", "16",
                        "-fill", "#E8EEF2", "-background", "#22303A", "-title", asset_id, "-quality", "86", sheet],
                       check=True)
        print("sheet", os.path.relpath(sheet, ld.ROOT))
    for p in shots:
        print("render", p)


def main(argv):
    parser = argparse.ArgumentParser(description="Gate review renders for the creature world's assets.")
    parser.add_argument("ids", nargs="+")
    parser.add_argument("--focus", type=lambda s: [float(v) for v in s.split(",")], default=None,
                        help="close-up target x,y,z in the asset's Blender coordinates, metres")
    parser.add_argument("--closeup-m", type=float, default=None, help="close-up camera distance, metres")
    parser.add_argument("--pitch", type=float, default=None, help="grey views' pitch, degrees")
    parser.add_argument("--samples", type=int, default=40)
    parser.add_argument("--resolution", type=int, default=480)
    parser.add_argument("--scratch", default=os.path.join(ld.ROOT, "builds", "review", "{id}"),
                        help="where the PNGs go; {id} is replaced by the asset id")
    parser.add_argument("--no-sheet", action="store_true", help="skip the contact sheet")
    args = parser.parse_args(argv)
    for asset_id in args.ids:
        render(asset_id, args)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    sys.stdout.flush()
