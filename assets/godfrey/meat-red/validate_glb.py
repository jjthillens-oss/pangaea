"""Inspect the final GLB without requiring a Blender or Godot runtime."""

from __future__ import annotations

import json
import struct
from pathlib import Path


asset = Path(__file__).with_name("meat-red.glb")
data = asset.read_bytes()
if len(data) < 20:
    raise SystemExit("GLB too short")
magic, version, byte_count = struct.unpack_from("<III", data)
if (magic, version, byte_count) != (0x46546C67, 2, len(data)):
    raise SystemExit("Invalid GLB header or declared byte count")
json_length, json_type = struct.unpack_from("<II", data, 12)
if json_type != 0x4E4F534A:
    raise SystemExit("GLB first chunk is not JSON")
doc = json.loads(data[20 : 20 + json_length])
meshes = doc.get("meshes", [])
materials = doc.get("materials", [])
if not meshes:
    raise SystemExit("No exported mesh")
if doc.get("cameras"):
    raise SystemExit("Review cameras leaked into the GLB")
if doc.get("extensions", {}).get("KHR_lights_punctual"):
    raise SystemExit("Review lights leaked into the GLB")
if not 2 <= len(materials) <= 3:
    raise SystemExit(f"Expected two or three physical materials, got {len(materials)}")
for mat in materials:
    pbr = mat.get("pbrMetallicRoughness")
    if pbr is None:
        raise SystemExit(f"Missing exportable PBR material: {mat.get('name')}")
    if pbr.get("metallicFactor", 0.0) > 0.001:
        raise SystemExit(f"Food material is unexpectedly metallic: {mat.get('name')}")

triangles = 0
for mesh in meshes:
    for primitive in mesh.get("primitives", []):
        if primitive.get("mode", 4) != 4:
            raise SystemExit("A non-triangle primitive was exported")
        accessor = primitive.get("indices")
        if accessor is None:
            raise SystemExit("Expected indexed triangles")
        count = doc["accessors"][accessor]["count"]
        if count % 3:
            raise SystemExit("Index count is not a multiple of three")
        triangles += count // 3

if not 100 <= triangles <= 1200:
    raise SystemExit(f"Triangle budget failed: {triangles} triangles")
print(
    json.dumps(
        {
            "asset": asset.name,
            "byte_count": len(data),
            "triangles": triangles,
            "materials": [m.get("name", "unnamed") for m in materials],
            "images": len(doc.get("images", [])),
            "meshes": len(meshes),
            "cameras": len(doc.get("cameras", [])),
        },
        indent=2,
    )
)
