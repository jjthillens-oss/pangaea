"""Bounded, dependency-free GLB structure and budget check for bush 2.

Static validation is necessary but does not replace Godot render inspection.
Run after exporting the GLB: python validate_glb.py
"""

import json
import struct
from pathlib import Path


asset = Path(__file__).with_name("bush-2.glb")
blob = asset.read_bytes()
assert len(blob) >= 20, "GLB is truncated"
magic, version, declared = struct.unpack_from("<4sII", blob)
assert magic == b"glTF" and version == 2, "Expected glTF 2.0 GLB"
assert declared == len(blob), "GLB byte count disagrees with header"
json_length, chunk_kind = struct.unpack_from("<I4s", blob, 12)
assert chunk_kind == b"JSON" and 20 + json_length <= len(blob), "Missing JSON chunk"
document = json.loads(blob[20:20 + json_length].decode("utf-8"))

assert len(document.get("meshes", [])) == 1, "Export one original authored mesh"
assert len(document.get("materials", [])) <= 4, "Material slot budget exceeded"
assert not document.get("images"), "Unexpected baked texture dependency"
assert not document.get("animations"), "Unexpected animation in static bush"

triangles = 0
for mesh in document["meshes"]:
    for primitive in mesh["primitives"]:
        assert primitive.get("mode", 4) == 4, "Nontriangle primitive"
        accessor = document["accessors"][primitive["indices"]]
        assert accessor["count"] % 3 == 0, "Broken index triplets"
        triangles += accessor["count"] // 3
        assert "POSITION" in primitive["attributes"], "Missing positions"
        assert "NORMAL" in primitive["attributes"], "Missing normals"

assert 0 < triangles <= 2000, f"Triangle budget exceeded: {triangles}"
for material in document.get("materials", []):
    assert material.get("alphaMode", "OPAQUE") == "OPAQUE", "Translucent foliage not planned"
    pbr = material.get("pbrMetallicRoughness", {})
    assert pbr.get("metallicFactor", 0.0) == 0.0, "Organic foliage must not be metallic"

result = {"asset": asset.name, "bytes": len(blob), "triangles": triangles,
          "material_count": len(document.get("materials", [])),
          "image_count": len(document.get("images", [])),
          "static_glb_gate": "pass", "godot_visual_gate": "separate"}
print(json.dumps(result, indent=2))
