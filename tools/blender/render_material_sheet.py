"""Render the art-direction material sphere sheet and palette board (Bible section 15).

Writes docs/art/renders/material_sheet.png and docs/art/renders/palette.png.
Run: python tools/blender/render_material_sheet.py  (bpy 5.2.2) or blender --background --python ...
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import lookdev as ld  # noqa: E402

SPHERES = [
    ("Clay", lambda: ld.clay_material()),
    ("Membrane", lambda: ld.membrane_material("M_Membrane_Coral")),
    ("Membrane teal", lambda: ld.membrane_material("M_Membrane_Teal", back="moss_deep", body="shallow_turquoise", spots="cream")),
    ("Organelle", lambda: ld.principled("M_Organelle", ld.color("mineral_amber"), 0.6, ld.color("mineral_amber"), 0.6)),
    ("Eye", lambda: ld.principled("M_EyeSclera", ld.color("cream"), 0.08)),
    ("Lid and lip", lambda: ld.principled("M_Lid", ld.color("rust"), 0.65)),
    ("Food", lambda: ld.principled("M_Food", ld.color("food_glow"), 0.45, ld.color("food_glow"), 0.8)),
    ("Threat", lambda: ld.principled("M_Threat", ld.color("threat"), 0.35)),
]


def material_sheet():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ld.setup_render(samples=64)
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 1600, 420
    ld.review_lighting()
    spacing = 1.15
    start = -spacing * (len(SPHERES) - 1) / 2
    for i, (label, make) in enumerate(SPHERES):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=0.48, location=(start + i * spacing, 0, 0))
        sphere = bpy.context.active_object
        sphere.name = label
        sphere.data.materials.append(make())
        bpy.ops.object.shade_smooth()
    ld.ground_disc(radius=30, z=-0.5)
    cam = ld.camera(lens=50)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = spacing * len(SPHERES) + 0.2
    cam.location = (0, -8, 0.6)
    cam.rotation_euler = (cam.location * -1).to_track_quat("-Z", "Y").to_euler()
    ld.render_to(os.path.join(ld.RENDER_DIR, "material_sheet.png"))


def palette_board():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    ld.setup_render(samples=1)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    names = list(ld.PALETTE)
    scene.render.resolution_x, scene.render.resolution_y = 120 * len(names), 120
    for i, name in enumerate(names):
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=(i + 0.5 - len(names) / 2, 0, 0))
        plane = bpy.context.active_object
        mat = bpy.data.materials.new(f"Swatch_{name}")
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        nodes.remove(nodes["Principled BSDF"])
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = ld.color(name)
        mat.node_tree.links.new(emit.outputs[0], nodes["Material Output"].inputs["Surface"])
        plane.data.materials.append(mat)
    cam = ld.camera()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = len(names)
    cam.location = (0, 0, 5)
    ld.render_to(os.path.join(ld.RENDER_DIR, "palette.png"))


if __name__ == "__main__":
    material_sheet()
    palette_board()
