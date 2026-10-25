"""Check the exported GLB's real contents, not only Blender's reported counts."""

from pathlib import Path
import json
import struct

ROOT = Path(__file__).resolve().parent
DATA = (ROOT / "meat-pale.glb").read_bytes()
assert len(DATA) >= 20, "GLB too short"
magic, version, length = struct.unpack_from("<4sII", DATA)
assert magic == b"glTF" and version == 2 and length == len(DATA)
chunk_length, kind = struct.unpack_from("<I4s", DATA, 12)
assert kind == b"JSON"
scene = json.loads(DATA[20:20 + chunk_length])
assert len(scene["meshes"]) == 3
assert len(scene["materials"]) == 4
assert len(scene.get("images", [])) == 0
assert len(scene.get("textures", [])) == 0
assert not scene.get("cameras") and not scene.get("extensionsUsed")
assert len(scene["scenes"][scene["scene"]]["nodes"]) == 3

primitives = [part for mesh in scene["meshes"] for part in mesh["primitives"]]
assert all(part["mode"] == 4 for part in primitives if "mode" in part)
assert all("POSITION" in part["attributes"] and "NORMAL" in part["attributes"]
           for part in primitives)
triangles = sum(scene["accessors"][part["indices"]]["count"] // 3
                for part in primitives)
assert triangles <= 1500, triangles
assert triangles == 1296, triangles
position_accessors = [scene["accessors"][part["attributes"]["POSITION"]]
                      for part in primitives]
lower = [min(accessor["min"][i] for accessor in position_accessors)
         for i in range(3)]
upper = [max(accessor["max"][i] for accessor in position_accessors)
         for i in range(3)]
dimensions = [round(upper[i] - lower[i], 4) for i in range(3)]
assert all(0.0 <= material["pbrMetallicRoughness"]["roughnessFactor"] <= 1.0
           and material["pbrMetallicRoughness"]["metallicFactor"] == 0.0
           for material in scene["materials"])

report = {
    "file_bytes": len(DATA),
    "triangle_count": triangles,
    "mesh_count": len(scene["meshes"]),
    "material_count": len(scene["materials"]),
    "image_count": len(scene.get("images", [])),
    "texture_count": len(scene.get("textures", [])),
    "gltf_xyz_min": [round(n, 4) for n in lower],
    "gltf_xyz_max": [round(n, 4) for n in upper],
    "gltf_xyz_dimensions": dimensions,
    "y_up_ground_gap_m": round(lower[1], 4),
}
(ROOT / "glb_validation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
