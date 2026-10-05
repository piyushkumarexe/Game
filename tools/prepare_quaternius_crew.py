#!/usr/bin/env python3
"""Prepare the CC0 Quaternius male base head and Ranger outfit.

Usage:
    python3 tools/prepare_quaternius_crew.py SOURCE_DIR TARGET_DIR

SOURCE_DIR follows the retained `assets/verse/characters/quaternius` layout from
OpenAgentsInc/openagents. The script retains the professional named skeleton in
both scenes, removes body triangles covered by the outfit, and removes the Ranger
hood so Dustbound's cap and sunglasses can be fitted without intersections.
"""
from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

FORMATS = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def values(doc: dict, blob: bytes, accessor_index: int) -> list[tuple]:
    accessor = doc["accessors"][accessor_index]
    view = doc["bufferViews"][accessor["bufferView"]]
    width = WIDTHS[accessor["type"]]
    fmt = "<" + FORMATS[accessor["componentType"]] * width
    item_size = struct.calcsize(fmt)
    stride = view.get("byteStride", item_size)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [struct.unpack_from(fmt, blob, start + i * stride) for i in range(accessor["count"])]


def overwrite_indices(doc: dict, blob: bytearray, accessor_index: int, indices: list[int]) -> None:
    accessor = doc["accessors"][accessor_index]
    view = doc["bufferViews"][accessor["bufferView"]]
    fmt = "<" + FORMATS[accessor["componentType"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    payload = b"".join(struct.pack(fmt, index) for index in indices)
    blob[start : start + len(payload)] = payload
    accessor["count"] = len(indices)


def localize_images(doc: dict) -> None:
    for image in doc.get("images", []):
        image["uri"] = "textures/" + Path(image["uri"]).name


def prepare_head(source: Path, target: Path) -> None:
    gltf_path = source / "base" / "Superhero_Male_FullBody.gltf"
    bin_path = source / "base" / "Superhero_Male_FullBody.bin"
    doc = json.loads(gltf_path.read_text(encoding="utf-8"))
    blob = bytearray(bin_path.read_bytes())
    primitive = doc["meshes"][2]["primitives"][0]
    positions = values(doc, blob, primitive["attributes"]["POSITION"])
    indices = [item[0] for item in values(doc, blob, primitive["indices"])]
    head_indices: list[int] = []
    for offset in range(0, len(indices), 3):
        triangle = indices[offset : offset + 3]
        if sum(positions[index][1] for index in triangle) / 3.0 > 1.52:
            head_indices.extend(triangle)
    overwrite_indices(doc, blob, primitive["indices"], head_indices)
    doc["nodes"][67]["name"] = "ProfessionalHeadAndNeck"
    doc["buffers"][0]["uri"] = "crew_head.bin"
    doc["asset"]["generator"] = "Dustbound Quaternius covered-body removal"
    doc["extras"] = {"creator": "Quaternius", "license": "CC0-1.0",
                     "modification": "covered torso and limbs removed; head and neck retained"}
    localize_images(doc)
    (target / "crew_head.bin").write_bytes(blob)
    (target / "crew_head.gltf").write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")


def prepare_outfit(source: Path, target: Path) -> None:
    doc = json.loads((source / "outfits" / "Male_Ranger.gltf").read_text(encoding="utf-8"))
    blob = (source / "outfits" / "Male_Ranger.bin").read_bytes()
    # Node 72 is the authored hood. Its mesh is retained in the binary for
    # provenance but disconnected to make room for the expedition cap.
    armature_children = doc["nodes"][74]["children"]
    doc["nodes"][74]["children"] = [index for index in armature_children if index != 72]
    doc["buffers"][0]["uri"] = "ranger_outfit.bin"
    doc["asset"]["generator"] = "Dustbound Quaternius Ranger mobile preparation"
    doc["extras"] = {"creator": "Quaternius", "license": "CC0-1.0",
                     "modification": "hood disconnected for expedition cap"}
    localize_images(doc)
    (target / "ranger_outfit.bin").write_bytes(blob)
    (target / "ranger_outfit.gltf").write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: prepare_quaternius_crew.py SOURCE_DIR TARGET_DIR")
    source, target = map(Path, sys.argv[1:])
    target.mkdir(parents=True, exist_ok=True)
    textures = target / "textures"
    textures.mkdir(exist_ok=True)
    prepare_head(source, target)
    prepare_outfit(source, target)
    for texture in (source / "textures").glob("*.png"):
        shutil.copy2(texture, textures / texture.name)
    for animation_asset in ("animations.glb", "animations.json", "animations-license.txt", "animations-readme.txt"):
        source_asset = source / animation_asset
        if source_asset.exists():
            shutil.copy2(source_asset, target / animation_asset)
    print(f"Prepared Quaternius crew and authored animations in {target}")


if __name__ == "__main__":
    main()
