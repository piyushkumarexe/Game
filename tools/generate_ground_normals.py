#!/usr/bin/env python3
"""Generate tangent-space normal maps from the committed ground albedos.

Requires ImageMagick's `convert`; uses only the Python standard library for the
normal calculation so the result is reproducible in CI and asset rebuilds.
"""
from __future__ import annotations

import math
import subprocess
import sys
from pathlib import Path


def image_size(path: Path) -> tuple[int, int]:
    output = subprocess.check_output(["identify", "-format", "%w %h", str(path)], text=True)
    width, height = map(int, output.split())
    return width, height


def build(source: Path, target: Path, strength: float = 3.1) -> None:
    width, height = image_size(source)
    raw_path = target.with_suffix(".gray")
    ppm_path = target.with_suffix(".ppm")
    subprocess.run([
        "convert", str(source), "-colorspace", "Gray", "-depth", "8", f"gray:{raw_path}"
    ], check=True)
    heightmap = raw_path.read_bytes()
    if len(heightmap) != width * height:
        raise RuntimeError(f"unexpected grayscale size for {source}: {len(heightmap)}")
    pixels = bytearray(width * height * 3)
    for y in range(height):
        ym = (y - 1) % height
        yp = (y + 1) % height
        for x in range(width):
            xm = (x - 1) % width
            xp = (x + 1) % width
            dx = (heightmap[y * width + xp] - heightmap[y * width + xm]) / 255.0
            dy = (heightmap[yp * width + x] - heightmap[ym * width + x]) / 255.0
            nx, ny, nz = -dx * strength, -dy * strength, 1.0
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            offset = (y * width + x) * 3
            pixels[offset] = round((nx / length * 0.5 + 0.5) * 255.0)
            pixels[offset + 1] = round((ny / length * 0.5 + 0.5) * 255.0)
            pixels[offset + 2] = round((nz / length * 0.5 + 0.5) * 255.0)
    ppm_path.write_bytes(f"P6\n{width} {height}\n255\n".encode() + pixels)
    subprocess.run(["convert", str(ppm_path), "-define", "png:color-type=2", str(target)], check=True)
    raw_path.unlink()
    ppm_path.unlink()
    print(f"generated {target} ({width}x{height})")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    textures = root / "assets" / "textures"
    pairs = [
        (textures / "forest_ground_albedo.jpg", textures / "forest_ground_normal.png"),
        (textures / "trail_ground_albedo.jpg", textures / "trail_ground_normal.png"),
    ]
    for source, target in pairs:
        build(source, target)


if __name__ == "__main__":
    main()
