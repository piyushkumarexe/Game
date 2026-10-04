#!/usr/bin/env python3
"""Prepare Karol Miklas' CC-BY GMC motorhome glTF for Dustbound.

Usage:
    python3 tools/prepare_gmc_motorhome.py /path/to/downloaded/source \
        assets/third_party/gmc_motorhome

The source directory must contain scene.gltf, scene.bin and textures/. The script
keeps the authored body/materials, opens the passenger-side doorway, removes the
baked wheel pairs so physics-driven wheels can be used, and extracts one complete
wheel assembly. Texture resizing is deliberately handled separately so this tool
has no non-standard Python dependencies.
"""
from __future__ import annotations

import copy
import json
import math
import shutil
import struct
import sys
from pathlib import Path

COMPONENT_FORMAT = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
TYPE_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor_values(doc: dict, blob: bytes, accessor_index: int) -> list[tuple]:
    accessor = doc["accessors"][accessor_index]
    view = doc["bufferViews"][accessor["bufferView"]]
    component = accessor["componentType"]
    width = TYPE_WIDTH[accessor["type"]]
    fmt = "<" + COMPONENT_FORMAT[component] * width
    item_size = struct.calcsize(fmt)
    stride = view.get("byteStride", item_size)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [struct.unpack_from(fmt, blob, start + index * stride) for index in range(accessor["count"])]


def overwrite_indices(doc: dict, blob: bytearray, accessor_index: int, indices: list[int]) -> None:
    accessor = doc["accessors"][accessor_index]
    view = doc["bufferViews"][accessor["bufferView"]]
    component = accessor["componentType"]
    fmt = "<" + COMPONENT_FORMAT[component]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    encoded = b"".join(struct.pack(fmt, index) for index in indices)
    old_bytes = accessor["count"] * struct.calcsize(fmt)
    if len(encoded) > old_bytes:
        raise ValueError("filtered index data unexpectedly grew")
    blob[start : start + len(encoded)] = encoded
    accessor["count"] = len(indices)


def open_passenger_doorway(doc: dict, blob: bytearray) -> None:
    # Source coordinates: the passenger side is -X. After the runtime 180-degree
    # yaw this becomes +X. The retained opening matches the functional door,
    # steps and split shell collider in rv_controller.gd.
    for mesh_index in (6, 10):  # painted coach body and glazing
        for primitive in doc["meshes"][mesh_index]["primitives"]:
            positions = accessor_values(doc, blob, primitive["attributes"]["POSITION"])
            flat_indices = [value[0] for value in accessor_values(doc, blob, primitive["indices"])]
            retained: list[int] = []
            for offset in range(0, len(flat_indices), 3):
                triangle = flat_indices[offset : offset + 3]
                center = tuple(sum(positions[index][axis] for index in triangle) / 3.0 for axis in range(3))
                in_opening = center[0] < -1.0 and -1.76 < center[2] < -0.42 and -0.76 < center[1] < 1.42
                if not in_opening:
                    retained.extend(triangle)
            overwrite_indices(doc, blob, primitive["indices"], retained)


def write_body(source: Path, target: Path) -> None:
    doc = json.loads((source / "scene.gltf").read_text(encoding="utf-8"))
    blob = bytearray((source / "scene.bin").read_bytes())
    open_passenger_doorway(doc, blob)
    # Cube.003_2 and Cube.002_5 are the source's massively oversized duplicated
    # cockpit-seat assemblies. On a phone they filled the windshield and also
    # protruded through the opened doorway. Dustbound supplies correctly scaled
    # cockpit seats at runtime. Plane.001_11, Plane.003_12 and Plane.004_13 are
    # the three baked axle pairs replaced by physics-driven wheel assemblies.
    # Geometry remains in the licensed shared binary for provenance, but none of
    # these source nodes can render.
    root_children = doc["nodes"][2]["children"]
    removed_nodes = (7, 13, 17, 19, 21)
    doc["nodes"][2]["children"] = [index for index in root_children if index not in removed_nodes]
    doc["asset"]["generator"] = "Dustbound CC-BY GMC mobile preparation"
    doc["extras"] = {
        "source": "https://sketchfab.com/3d-models/free-gmc-motorhome-reimagined-low-poly-6hiH0iyDqXqtdD9wbqSbyLLhKmz",
        "author": "Karol Miklas",
        "modifications": "passenger doorway opened; oversized source seats and baked wheels removed; textures mobile-sized",
    }
    doc["buffers"][0]["uri"] = "motorhome.bin"
    (target / "motorhome.bin").write_bytes(blob)
    (target / "motorhome.gltf").write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")


def add_buffer(blob: bytearray, payload: bytes, target: int) -> int:
    while len(blob) % 4:
        blob.append(0)
    start = len(blob)
    blob.extend(payload)
    return start


def write_wheel(source: Path, target: Path) -> None:
    src = json.loads((source / "scene.gltf").read_text(encoding="utf-8"))
    source_blob = (source / "scene.bin").read_bytes()
    primitive = src["meshes"][7]["primitives"][0]
    positions = accessor_values(src, source_blob, primitive["attributes"]["POSITION"])
    normals = accessor_values(src, source_blob, primitive["attributes"]["NORMAL"])
    uvs = accessor_values(src, source_blob, primitive["attributes"]["TEXCOORD_0"])
    indices = [value[0] for value in accessor_values(src, source_blob, primitive["indices"])]
    kept_triangles = [indices[i : i + 3] for i in range(0, len(indices), 3)
                      if sum(positions[index][0] for index in indices[i : i + 3]) / 3.0 > 0.0]
    used = sorted({index for triangle in kept_triangles for index in triangle})
    remap = {old: new for new, old in enumerate(used)}
    selected_positions = [positions[index] for index in used]
    center_x = (min(value[0] for value in selected_positions) + max(value[0] for value in selected_positions)) * 0.5
    selected_positions = [(value[0] - center_x, value[1], value[2]) for value in selected_positions]
    selected_normals = [normals[index] for index in used]
    selected_uvs = [uvs[index] for index in used]
    selected_indices = [remap[index] for triangle in kept_triangles for index in triangle]

    blob = bytearray()
    views: list[dict] = []
    accessors: list[dict] = []

    def append(values: list[tuple], fmt: str, target_code: int, kind: str,
               component: int, bounds: bool = False) -> int:
        payload = b"".join(struct.pack("<" + fmt, *value) for value in values)
        offset = add_buffer(blob, payload, target_code)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(payload), "target": target_code})
        result = {"bufferView": len(views) - 1, "componentType": component,
                  "count": len(values), "type": kind}
        if bounds:
            result["min"] = [min(value[axis] for value in values) for axis in range(len(values[0]))]
            result["max"] = [max(value[axis] for value in values) for axis in range(len(values[0]))]
        accessors.append(result)
        return len(accessors) - 1

    position_accessor = append(selected_positions, "3f", 34962, "VEC3", 5126, True)
    normal_accessor = append(selected_normals, "3f", 34962, "VEC3", 5126)
    uv_accessor = append(selected_uvs, "2f", 34962, "VEC2", 5126)
    index_accessor = append([(value,) for value in selected_indices], "I", 34963, "SCALAR", 5125)
    wheel_material = copy.deepcopy(src["materials"][2])
    wheel_material["pbrMetallicRoughness"]["baseColorTexture"]["index"] = 0
    wheel_material["pbrMetallicRoughness"]["metallicRoughnessTexture"]["index"] = 1
    document = {
        "asset": {"version": "2.0", "generator": "Dustbound CC-BY GMC wheel extraction"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "ProfessionalTireRim", "mesh": 0}],
        "meshes": [{"name": "ProfessionalTireRim", "primitives": [{
            "attributes": {"POSITION": position_accessor, "NORMAL": normal_accessor, "TEXCOORD_0": uv_accessor},
            "indices": index_accessor, "material": 0, "mode": 4,
        }]}],
        "materials": [wheel_material],
        "samplers": copy.deepcopy(src["samplers"]),
        "images": [{"uri": "textures/clay.001_baseColor.jpeg"},
                   {"uri": "textures/clay.001_metallicRoughness.png"}],
        "textures": [{"sampler": 0, "source": 0}, {"sampler": 0, "source": 1}],
        "buffers": [{"byteLength": len(blob), "uri": "wheel.bin"}],
        "bufferViews": views,
        "accessors": accessors,
        "extras": {"source_author": "Karol Miklas", "license": "CC-BY-4.0"},
    }
    (target / "wheel.bin").write_bytes(blob)
    (target / "wheel.gltf").write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: prepare_gmc_motorhome.py SOURCE_DIR TARGET_DIR")
    source, target = map(Path, sys.argv[1:])
    target.mkdir(parents=True, exist_ok=True)
    (target / "textures").mkdir(exist_ok=True)
    write_body(source, target)
    write_wheel(source, target)
    for texture in (source / "textures").iterdir():
        shutil.copy2(texture, target / "textures" / texture.name)
    print(f"Prepared motorhome in {target}")


if __name__ == "__main__":
    main()
