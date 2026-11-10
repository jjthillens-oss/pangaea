"""Inspect the exported GLB bytes without loading Blender or the game project."""
from pathlib import Path
import json
import struct

root = Path(__file__).resolve().parent
path = root / "rock.glb"
blob = path.read_bytes()
magic, version, declared_length = struct.unpack_from("<4sII", blob, 0)
assert magic == b"glTF" and version == 2 and declared_length == len(blob), "bad GLB header"
chunk_length, chunk_type = struct.unpack_from("<II", blob, 12)
assert chunk_type == 0x4E4F534A, "missing JSON chunk"
doc = json.loads(blob[20:20+chunk_length].decode("utf-8"))
assert len(doc.get("meshes", [])) == 1, "expected one exported mesh"
assert not doc.get("cameras"), "review camera leaked into GLB"
assert not doc.get("extensions", {}).get("KHR_lights_punctual"), "review light leaked into GLB"
assert len(doc.get("materials", [])) in (2,3), "unexpected material count"
assert not doc.get("images"), "unexpected texture dependency"
assert all(not item.get("uri") for item in doc.get("buffers", [])), "external buffer dependency"
tris = 0
positions = []
for mesh in doc["meshes"]:
    for primitive in mesh["primitives"]:
        assert primitive.get("mode", 4) == 4, "not triangles"
        accessor = doc["accessors"][primitive["indices"]]
        assert accessor["count"] % 3 == 0, "index count not triangles"
        tris += accessor["count"] // 3
        positions.append(doc["accessors"][primitive["attributes"]["POSITION"]])
assert 100 <= tris <= 2000, f"triangle budget exceeded: {tris}"
lo = [min(a["min"][i] for a in positions) for i in range(3)]
hi = [max(a["max"][i] for a in positions) for i in range(3)]
dimensions = [hi[i] - lo[i] for i in range(3)]
assert all(0.3 < d < 2.5 for d in dimensions), f"unexpected dimensions: {dimensions}"
assert abs(lo[1]) < 0.15, f"expected ground at Y=0 in glTF: {lo}"
report = {
    "glb_bytes": len(blob),
    "triangles": tris,
    "materials": len(doc["materials"]),
    "textures": len(doc.get("textures", [])),
    "dimensions_gltf_m": dimensions,
    "bounds_min": lo,
    "bounds_max": hi,
    "external_dependencies": 0,
}
(root / "glb_validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
