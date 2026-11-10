"""Bounded structural checks for the standalone Tideleaf GLB export."""

import json
import struct
import sys
from pathlib import Path


def inspect(path: Path):
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError("not a binary glTF file")
    version, total = struct.unpack_from("<II", data, 4)
    if version != 2 or total != len(data):
        raise ValueError("invalid glTF version or length")
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    if json_type != b"JSON" or 20 + json_len > len(data):
        raise ValueError("missing or truncated glTF JSON chunk")
    doc = json.loads(data[20 : 20 + json_len].decode("utf-8"))
    if doc.get("images"):
        raise ValueError("unexpected image dependency; this prop uses solid PBR materials")

    triangles = 0
    vertex_min = [float("inf")] * 3
    vertex_max = [float("-inf")] * 3
    for mesh in doc.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if primitive.get("mode", 4) != 4:
                raise ValueError("non-triangle primitive")
            position_accessor = doc["accessors"][primitive["attributes"]["POSITION"]]
            for axis in range(3):
                vertex_min[axis] = min(vertex_min[axis], position_accessor["min"][axis])
                vertex_max[axis] = max(vertex_max[axis], position_accessor["max"][axis])
            if "indices" in primitive:
                count = doc["accessors"][primitive["indices"]]["count"]
            else:
                count = position_accessor["count"]
            if count % 3:
                raise ValueError("triangle index count is not divisible by three")
            triangles += count // 3

    materials = doc.get("materials", [])
    if not 100 <= triangles <= 2000:
        raise ValueError(f"triangle budget exceeded: {triangles}")
    if not materials or any("pbrMetallicRoughness" not in mat for mat in materials):
        raise ValueError("missing export-compatible PBR material")
    if not all(mat.get("doubleSided", False) for mat in materials[:3]):
        raise ValueError("thin frond materials need double-sided rendering")
    print(f"triangles={triangles} materials={len(materials)}")
    print(f"bounds_min={vertex_min} bounds_max={vertex_max}")
    print(f"dimensions={[round(hi - lo, 3) for lo, hi in zip(vertex_min, vertex_max)]} metres")


if __name__ == "__main__":
    inspect(Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).with_name("tideleaf.glb")))
