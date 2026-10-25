"""Build an original stylized boulder; execute only after the shared render window is released."""
from pathlib import Path
import json
import math
import os
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
N = 40
RINGS = [
    (0.03, 0.27), (0.13, 0.46), (0.31, 0.68), (0.53, 0.83),
    (0.75, 0.96), (0.97, 1.00), (1.17, 0.95), (1.34, 0.83),
    (1.44, 0.74), (1.49, 0.70), (1.58, 0.48), (1.64, 0.20),
]

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection.name != bpy.context.scene.collection.name and collection.users == 0:
        bpy.data.collections.remove(collection)

export_group = bpy.data.collections.new("EXPORT_rock_only")
review_group = bpy.data.collections.new("REVIEW_not_exported")
bpy.context.scene.collection.children.link(export_group)
bpy.context.scene.collection.children.link(review_group)

verts = []
cavities = []
for i, (z0, base_r) in enumerate(RINGS):
    for j in range(N):
        z = z0
        a = 2.0 * math.pi * j / N
        r = base_r * (1.0 + 0.060 * math.sin(3*a + 0.3)
                      + 0.036 * math.sin(5*a - 2.4*z)
                      + 0.015 * math.sin(9*a + 4*z))
        x = r * math.cos(a) + 0.030 * math.sin(2.6*z)
        y = 0.77 * r * math.sin(a)
        # A real inset surface: broad cavity on the viewing side left of center.
        cavity = (math.exp(-((x - 0.27) / 0.30)**4 - ((z - 0.94) / 0.34)**4)
                  * max(0.0, math.sin(a))**2)
        y -= 0.82 * cavity
        # The right shoulder remains fuller and smoother than the cavity lip.
        x -= 0.10 * math.exp(-((z - 0.82)/0.43)**2) * max(0.0, -math.cos(a))
        # An uneven cap shelf without a manufactured ring.
        z += 0.04 * math.sin(4*a + 0.8) * math.sin(math.pi * i / (len(RINGS)-1))
        if i >= 8:
            z += 0.12 * max(0.0, -math.cos(a)) * max(0.0, math.sin(a))
        verts.append((x, y, z))
        cavities.append(cavity)

bottom = len(verts)
verts.append((0.0, 0.0, 0.025))
cavities.append(0.0)
top = len(verts)
verts.append((0.0, 0.0, 1.66))
cavities.append(0.0)
faces = []
for i in range(len(RINGS)-1):
    for j in range(N):
        k = (j+1) % N
        a, b, c, d = i*N+j, i*N+k, (i+1)*N+k, (i+1)*N+j
        faces.extend(((a,b,d), (b,c,d)))
for j in range(N):
    k = (j+1) % N
    faces.append((bottom,k,j))
    faces.append((top,(len(RINGS)-1)*N+j,(len(RINGS)-1)*N+k))

mesh = bpy.data.meshes.new("Sandstone_Boulder_Mesh")
mesh.from_pydata(verts, [], faces)
mesh.update()
rock = bpy.data.objects.new("Godfrey_Sandstone_Boulder", mesh)
export_group.objects.link(rock)

uv = mesh.uv_layers.new(name="Rock_UV")
for poly in mesh.polygons:
    idx = [mesh.loops[li].vertex_index for li in poly.loop_indices]
    ring_js = [vi % N for vi in idx if vi < len(RINGS)*N]
    seam = 0 in ring_js and N-1 in ring_js
    for li in poly.loop_indices:
        vi = mesh.loops[li].vertex_index
        if vi >= len(RINGS)*N:
            uv.data[li].uv = (0.5, 0.5)
        else:
            ri, j = divmod(vi, N)
            u = j / N
            if seam and j == 0:
                u = 1.0
            uv.data[li].uv = (u, ri/(len(RINGS)-1))

def mat(name, rgb, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1.0)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = 0.0
    return m

gray = mat("Shape_gray", (0.43,0.43,0.43), 0.84)
main = mat("Warm_sandstone", (0.33,0.095,0.060), 0.86)
cavity_mat = mat("Weathered_recess", (0.16,0.040,0.027), 0.94)
cap = mat("Sun_worn_cap", (0.42,0.145,0.075), 0.81)
mesh.materials.append(gray)

def light(name, loc, energy, size):
    datablock = bpy.data.lights.new(name, "AREA")
    datablock.energy = energy
    datablock.shape = "DISK"
    datablock.size = size
    obj = bpy.data.objects.new(name, datablock)
    review_group.objects.link(obj)
    obj.location = loc
    direction = Vector((0,0,0.85)) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

light("Neutral_key", (-3.4,4.2,5.2), 620, 4.2)
light("Neutral_fill", (3.2,1.8,2.8), 340, 5.0)
light("Grazing_rim", (0,-3.0,2.5), 430, 2.3)
world = bpy.data.worlds.new("Neutral_studio")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.50,0.55,0.62,1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
bpy.context.scene.world = world

camera_data = bpy.data.cameras.new("Review_camera")
camera = bpy.data.objects.new("Review_camera", camera_data)
review_group.objects.link(camera)
camera_data.type = "ORTHO"
camera_data.ortho_scale = 3.20
bpy.context.scene.camera = camera
scene = bpy.context.scene
scene.render.resolution_x = 760
scene.render.resolution_y = 760
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.view_settings.view_transform = "AgX"
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [x.identifier for x in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"

views = {
    "front": (0.0,4.7,1.45),
    "side": (4.6,0.0,1.45),
    "three_quarter": (3.2,4.0,2.25),
    "gameplay": (3.5,4.8,4.7),
}
def render_view(name, suffix):
    camera.location = views[name]
    camera.rotation_euler = (Vector((0,0,0.85)) - camera.location).to_track_quat("-Z","Y").to_euler()
    camera_data.ortho_scale = 3.2 if name != "gameplay" else 4.8
    scene.render.filepath = str(OUT / (suffix + "_" + name + ".png"))
    bpy.ops.render.render(write_still=True)

# A separate blockout source and three neutral gray inspections precede material work.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "rock_blockout.blend"))
for name in ("front","side","three_quarter"):
    render_view(name, "gray")

if os.environ.get("GODFREY_ROCK_STAGE") == "gray":
    print("Gray shape pass complete; inspect views before running the material stage.")
    raise SystemExit(0)

mesh.materials.clear()
for m in (main,cavity_mat,cap):
    mesh.materials.append(m)
for poly in mesh.polygons:
    indices = [mesh.loops[li].vertex_index for li in poly.loop_indices]
    avg_cavity = sum(cavities[i] for i in indices) / len(indices)
    avg_z = sum(verts[i][2] for i in indices) / len(indices)
    poly.material_index = 1 if avg_cavity > 0.33 else (2 if avg_z > 1.38 and avg_cavity < 0.14 else 0)
    poly.use_smooth = False

for name in ("front","side","three_quarter","gameplay"):
    render_view(name, "material")
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "rock.blend"))

bpy.ops.object.select_all(action="DESELECT")
rock.select_set(True)
bpy.context.view_layer.objects.active = rock
bpy.ops.export_scene.gltf(
    filepath=str(OUT / "rock.glb"), export_format="GLB", use_selection=True,
    export_apply=True, export_yup=True, export_materials="EXPORT",
)

report = {
    "asset_id": "godfrey_rock_01",
    "blender_version": bpy.app.version_string,
    "dimensions_blender_m": list(rock.dimensions),
    "triangles": sum(len(p.vertices)-2 for p in mesh.polygons),
    "vertices": len(mesh.vertices),
    "material_count": len(mesh.materials),
    "texture_count": 0,
    "proposed_triangle_budget": [100,2000],
    "source": "rock.blend",
    "export": "rock.glb",
    "reference": "reference_cc0.jpg",
    "rendered_views": ["gray_front.png","gray_side.png","gray_three_quarter.png",
                       "material_front.png","material_side.png","material_three_quarter.png",
                       "material_gameplay.png"],
}
(OUT / "technical_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
