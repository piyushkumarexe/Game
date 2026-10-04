#!/usr/bin/env python3
"""Generate Dustbound Expeditions' original low-poly OBJ models and painted textures.

The generator uses only Python's standard library so the source assets are reproducible.
All geometry, palettes, and textures are original to this project.
"""
from __future__ import annotations

import base64
import json
import math
import random
import struct
import zlib
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "assets" / "models"
TEXTURE_DIR = ROOT / "assets" / "textures"
MODEL_DIR.mkdir(parents=True, exist_ok=True)
TEXTURE_DIR.mkdir(parents=True, exist_ok=True)


def _chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_png(name: str, width: int, height: int, pixel: Callable[[int, int], tuple[int, int, int]]) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(max(0, min(255, value)) for value in pixel(x, y))
    data = b"\x89PNG\r\n\x1a\n"
    data += _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    data += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += _chunk(b"IEND", b"")
    (TEXTURE_DIR / name).write_bytes(data)


def paint_texture(name: str, base: tuple[int, int, int], seed: int, pattern: str, size: int = 256) -> None:
    """Paint seamless, low-frequency material detail without visible tile grids."""
    def pixel(x: int, y: int) -> tuple[int, int, int]:
        detail_hash = (x * 73856093 ^ y * 19349663 ^ seed * 83492791) & 0xFFFFFFFF
        value = (detail_hash % 15) - 7
        u, v = x / float(size), y / float(size)
        value += int(math.sin(math.tau * (u * 2.0 + v)) * 5 + math.cos(math.tau * (v * 3.0 - u)) * 3)
        if pattern == "detail":
            # Readable moss/soil grain on phone screens instead of an almost
            # white texture that reduced the terrain to one flat green color.
            broad = math.sin(math.tau * (u * 5.0 + v * 3.0)) * 11
            mottling = math.cos(math.tau * (u * 11.0 - v * 7.0)) * 7
            fleck = -22 if detail_hash % 173 < 5 else (8 if detail_hash % 229 < 4 else 0)
            value = int(value * 0.65 + broad + mottling + fleck)
        elif pattern == "gravel":
            value = (detail_hash % 17) - 8
            if detail_hash % 293 < 4:
                value -= 18
            elif detail_hash % 211 < 3:
                value += 12
        elif pattern == "panel":
            value += int(math.sin(math.tau * u) * 4)
            if detail_hash % 521 < 2:
                value -= 12
        elif pattern == "stripe":
            value += int(math.sin(math.tau * (v * 2.0 + u * 0.4)) * 7)
        elif pattern == "wood":
            value += int(math.sin(x * 0.12 + math.sin(y * 0.035) * 2.2) * 14)
            if x % 73 < 2:
                value -= 15
        elif pattern == "pine":
            value += int(math.sin((x + y) * 0.11) * 9)
            if detail_hash % 89 < 4:
                value += 14
        elif pattern == "rock":
            value += int(math.sin(x * 0.055) * 7 + math.cos(y * 0.071) * 9)
        elif pattern == "fabric":
            value += 5 if (x + y) % 7 == 0 else -2
        elif pattern == "upholstery":
            weave = ((x // 3 + y // 3) % 2) * 5 - 2
            seam = -18 if x % 127 < 2 else 0
            value = int(value * 0.35) + weave + seam
        elif pattern == "vinyl":
            value = int(value * 0.28)
            if y % 96 < 2:
                value -= 11
        elif pattern == "rubber":
            value = int(value * 0.45)
            tread = ((x + y * 2) % 31 < 7) or ((x * 2 - y) % 37 < 6)
            value += -13 if tread else 3
        elif pattern == "metal":
            value = int(value * 0.18) + int(math.sin(y * 0.31) * 2)
        return tuple(channel + value for channel in base)

    write_png(name, size, size, pixel)


for args in [
    ("rv_cream.png", (205, 190, 154), 17, "panel", 1024),
    ("rv_stripe.png", (151, 68, 37), 29, "stripe", 1024),
    ("rv_interior_wood.png", (124, 76, 43), 31, "wood", 512),
    ("rv_upholstery.png", (101, 122, 112), 33, "upholstery", 512),
    ("rv_vinyl.png", (58, 63, 61), 35, "vinyl", 512),
    ("rv_tire.png", (36, 38, 40), 37, "rubber", 512),
    ("rv_metal.png", (153, 158, 153), 39, "metal", 256),
    ("trail_wood.png", (132, 86, 47), 41, "wood", 256),
    ("pine_needles.png", (58, 103, 67), 53, "pine", 256),
    ("canyon_stone.png", (142, 102, 74), 67, "rock", 256),
    ("crew_fabric.png", (174, 78, 42), 71, "fabric", 256),
    ("terrain_detail.png", (242, 243, 232), 89, "detail", 512),
    ("road_gravel.png", (151, 116, 79), 97, "gravel", 512),
]:
    paint_texture(*args)


def ground_pixel(x: int, y: int) -> tuple[int, int, int]:
    """Seamless multi-scale sandstone soil without obvious checker bands."""
    u = x / 512.0
    v = y / 512.0
    macro = (
        math.sin(math.tau * (u + v)) * 10.0
        + math.sin(math.tau * (u * 3.0 - v * 2.0)) * 6.0
        + math.cos(math.tau * (u * 7.0 + v * 5.0)) * 3.5
    )
    cell_x, cell_y = x // 32, y // 32
    cell_hash = (cell_x * 928371 + cell_y * 364479 + 83) & 0xFFFFFFFF
    patch = ((cell_hash >> 9) % 15) - 7
    grain_hash = (x * 73856093 ^ y * 19349663 ^ 83492791) & 0xFFFFFFFF
    grain = (grain_hash % 13) - 6
    pebble = -18 if grain_hash % 389 < 3 else (11 if grain_hash % 257 < 3 else 0)
    value = macro + patch + grain * 0.45 + pebble
    return (int(166 + value), int(124 + value * 0.72), int(78 + value * 0.48))


write_png("ground_dirt.png", 512, 512, ground_pixel)


class Obj:
    def __init__(self, name: str):
        self.name = name
        self.vertices: list[tuple[float, float, float]] = []
        self.uvs: list[tuple[float, float]] = []
        self.normals: list[tuple[float, float, float]] = []
        self.lines: list[str] = ["# Original Dustbound Expeditions low-poly model", "mtllib dustbound.mtl"]
        self.current_material = ""
        self.object_counts: dict[str, int] = {}

    def _start_object(self, object_name: str) -> None:
        """Start a uniquely named component so glTF keeps useful scene nodes."""
        count = self.object_counts.get(object_name, 0)
        self.object_counts[object_name] = count + 1
        unique_name = object_name if count == 0 else f"{object_name}_{count + 1:02d}"
        self.lines.append(f"o {unique_name}")

    def _material(self, material: str) -> None:
        if material != self.current_material:
            self.lines.append(f"usemtl {material}")
            self.current_material = material

    def _face(self, points: list[tuple[float, float, float]], normal: tuple[float, float, float], material: str) -> None:
        self._material(material)
        v_start = len(self.vertices) + 1
        vt_start = len(self.uvs) + 1
        n_index = len(self.normals) + 1
        self.vertices.extend(points)
        if len(points) <= 4:
            face_uvs = [(0, 0), (1, 0), (1, 1), (0, 1)][: len(points)]
        else:
            face_uvs = [
                (0.5 + math.cos(math.tau * index / len(points)) * 0.5,
                 0.5 + math.sin(math.tau * index / len(points)) * 0.5)
                for index in range(len(points))
            ]
        self.uvs.extend(face_uvs)
        self.normals.append(normal)
        refs = [f"{v_start + index}/{vt_start + index}/{n_index}" for index in range(len(points))]
        self.lines.append("f " + " ".join(refs))

    def box(self, object_name: str, center: tuple[float, float, float], size: tuple[float, float, float], material: str) -> None:
        self._start_object(object_name)
        cx, cy, cz = center
        hx, hy, hz = (value * 0.5 for value in size)
        p = {
            "lbf": (cx-hx, cy-hy, cz-hz), "rbf": (cx+hx, cy-hy, cz-hz),
            "rtf": (cx+hx, cy+hy, cz-hz), "ltf": (cx-hx, cy+hy, cz-hz),
            "lbb": (cx-hx, cy-hy, cz+hz), "rbb": (cx+hx, cy-hy, cz+hz),
            "rtb": (cx+hx, cy+hy, cz+hz), "ltb": (cx-hx, cy+hy, cz+hz),
        }
        for keys, normal in [
            (("lbf", "ltf", "rtf", "rbf"), (0, 0, -1)),
            (("rbb", "rtb", "ltb", "lbb"), (0, 0, 1)),
            (("lbb", "ltb", "ltf", "lbf"), (-1, 0, 0)),
            (("rbf", "rtf", "rtb", "rbb"), (1, 0, 0)),
            (("ltf", "ltb", "rtb", "rtf"), (0, 1, 0)),
            (("lbb", "lbf", "rbf", "rbb"), (0, -1, 0)),
        ]:
            self._face([p[key] for key in keys], normal, material)

    @staticmethod
    def _normal_for(points: list[tuple[float, float, float]]) -> tuple[float, float, float]:
        ax, ay, az = points[0]
        bx, by, bz = points[1]
        cx, cy, cz = points[2]
        ux, uy, uz = bx - ax, by - ay, bz - az
        vx, vy, vz = cx - ax, cy - ay, cz - az
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        length = max(0.00001, math.sqrt(nx * nx + ny * ny + nz * nz))
        return nx / length, ny / length, nz / length

    def quad(self, object_name: str, points: list[tuple[float, float, float]], material: str) -> None:
        """Create a thin authored panel such as a sloped windshield or decal."""
        self._start_object(object_name)
        self._face(points, self._normal_for(points), material)

    def profile_prism(self, object_name: str, z_front: float, z_back: float,
                      front: tuple[float, float, float, float],
                      back: tuple[float, float, float, float], material: str) -> None:
        """Make a cab-like prism from front/back (xmin, xmax, ymin, ymax) profiles."""
        self._start_object(object_name)
        fx0, fx1, fy0, fy1 = front
        bx0, bx1, by0, by1 = back
        p = {
            "flb": (fx0, fy0, z_front), "frb": (fx1, fy0, z_front),
            "frt": (fx1, fy1, z_front), "flt": (fx0, fy1, z_front),
            "blb": (bx0, by0, z_back), "brb": (bx1, by0, z_back),
            "brt": (bx1, by1, z_back), "blt": (bx0, by1, z_back),
        }
        for keys in [
            ("flb", "flt", "frt", "frb"), ("brb", "brt", "blt", "blb"),
            ("flb", "blb", "blt", "flt"), ("frb", "frt", "brt", "brb"),
            ("flt", "blt", "brt", "frt"), ("flb", "frb", "brb", "blb"),
        ]:
            points = [p[key] for key in keys]
            self._face(points, self._normal_for(points), material)

    def cylinder(self, object_name: str, center: tuple[float, float, float], radius: float, height: float, material: str, segments: int = 10, axis: str = "y") -> None:
        self._start_object(object_name)
        cx, cy, cz = center
        half = height * 0.5
        top: list[tuple[float, float, float]] = []
        bottom: list[tuple[float, float, float]] = []
        for index in range(segments):
            angle = math.tau * index / segments
            a, b = math.cos(angle) * radius, math.sin(angle) * radius
            if axis == "y":
                bottom.append((cx + a, cy - half, cz + b)); top.append((cx + a, cy + half, cz + b))
            elif axis == "x":
                bottom.append((cx - half, cy + a, cz + b)); top.append((cx + half, cy + a, cz + b))
            else:
                bottom.append((cx + a, cy + b, cz - half)); top.append((cx + a, cy + b, cz + half))
        for index in range(segments):
            nxt = (index + 1) % segments
            if axis == "y": normal = (math.cos(math.tau * (index + .5) / segments), 0, math.sin(math.tau * (index + .5) / segments))
            elif axis == "x": normal = (0, math.cos(math.tau * (index + .5) / segments), math.sin(math.tau * (index + .5) / segments))
            else: normal = (math.cos(math.tau * (index + .5) / segments), math.sin(math.tau * (index + .5) / segments), 0)
            self._face([bottom[index], top[index], top[nxt], bottom[nxt]], normal, material)
        top_normal = (0, 1, 0) if axis == "y" else ((1, 0, 0) if axis == "x" else (0, 0, 1))
        self._face(top, top_normal, material)
        self._face(list(reversed(bottom)), tuple(-v for v in top_normal), material)

    def frustum(self, object_name: str, center: tuple[float, float, float], bottom_radius: float, top_radius: float, height: float, material: str, segments: int = 9) -> None:
        self._start_object(object_name)
        cx, cy, cz = center
        bottom = []
        top = []
        for index in range(segments):
            angle = math.tau * index / segments
            bottom.append((cx + math.cos(angle)*bottom_radius, cy-height*.5, cz + math.sin(angle)*bottom_radius))
            top.append((cx + math.cos(angle)*top_radius, cy+height*.5, cz + math.sin(angle)*top_radius))
        for index in range(segments):
            nxt = (index + 1) % segments
            angle = math.tau * (index + .5) / segments
            self._face([bottom[index], top[index], top[nxt], bottom[nxt]], (math.cos(angle), .25, math.sin(angle)), material)
        self._face(top, (0, 1, 0), material)
        self._face(list(reversed(bottom)), (0, -1, 0), material)

    def ellipsoid(self, object_name: str, center: tuple[float, float, float], radii: tuple[float, float, float], material: str, segments: int = 10, rings: int = 6, irregular: float = 0.0, seed: int = 0) -> None:
        self._start_object(object_name)
        cx, cy, cz = center
        rx, ry, rz = radii
        rng = random.Random(seed)
        scales = [1.0 + rng.uniform(-irregular, irregular) for _ in range(segments)]
        grid = []
        for ring in range(rings + 1):
            phi = -math.pi * 0.5 + math.pi * ring / rings
            row = []
            for segment in range(segments):
                theta = math.tau * segment / segments
                scale = scales[segment]
                row.append((cx + math.cos(phi)*math.cos(theta)*rx*scale,
                            cy + math.sin(phi)*ry,
                            cz + math.cos(phi)*math.sin(theta)*rz*scale))
            grid.append(row)
        for ring in range(rings):
            for segment in range(segments):
                nxt = (segment + 1) % segments
                points = [grid[ring][segment], grid[ring+1][segment], grid[ring+1][nxt], grid[ring][nxt]]
                px = sum(point[0] for point in points)/4-cx
                py = sum(point[1] for point in points)/4-cy
                pz = sum(point[2] for point in points)/4-cz
                length = max(.001, math.sqrt(px*px+py*py+pz*pz))
                self._face(points, (px/length, py/length, pz/length), material)

    def torus(self, object_name: str, center: tuple[float, float, float], major: float, minor: float, material: str, axis: str = "z", segments: int = 12, sides: int = 6) -> None:
        self._start_object(object_name)
        cx, cy, cz = center
        grid = []
        for i in range(segments):
            a = math.tau * i / segments
            row = []
            for j in range(sides):
                b = math.tau * j / sides
                radial = major + math.cos(b)*minor
                if axis == "z":
                    point = (cx + math.cos(a)*radial, cy + math.sin(a)*radial, cz + math.sin(b)*minor)
                elif axis == "x":
                    point = (cx + math.sin(b)*minor, cy + math.cos(a)*radial, cz + math.sin(a)*radial)
                else:
                    point = (cx + math.cos(a)*radial, cy + math.sin(b)*minor, cz + math.sin(a)*radial)
                row.append(point)
            grid.append(row)
        for i in range(segments):
            for j in range(sides):
                ni, nj = (i+1)%segments, (j+1)%sides
                points = [grid[i][j], grid[ni][j], grid[ni][nj], grid[i][nj]]
                self._face(points, self._normal_for(points), material)

    def wheel_arch(self, object_name: str, center: tuple[float, float, float], major: float,
                   minor: float, material: str, segments: int = 18, sides: int = 6) -> None:
        """Upper half-torus around the X wheel axis, avoiding a fake full ring."""
        self._start_object(object_name)
        cx, cy, cz = center
        grid = []
        for i in range(segments + 1):
            a = math.pi * i / segments
            row = []
            for j in range(sides):
                b = math.tau * j / sides
                radial = major + math.cos(b) * minor
                row.append((cx + math.sin(b) * minor,
                            cy + math.sin(a) * radial,
                            cz + math.cos(a) * radial))
            grid.append(row)
        for i in range(segments):
            for j in range(sides):
                nj = (j + 1) % sides
                points = [grid[i][j], grid[i + 1][j], grid[i + 1][nj], grid[i][nj]]
                self._face(points, self._normal_for(points), material)

    def save(self) -> None:
        output = self.lines[:2]
        vertex_lines = [f"v {x:.5f} {y:.5f} {z:.5f}" for x, y, z in self.vertices]
        uv_lines = [f"vt {u:.5f} {v:.5f}" for u, v in self.uvs]
        normal_lines = [f"vn {x:.5f} {y:.5f} {z:.5f}" for x, y, z in self.normals]
        output.extend(vertex_lines)
        output.extend(uv_lines)
        output.extend(normal_lines)
        output.extend(self.lines[2:])
        (MODEL_DIR / f"{self.name}.obj").write_text("\n".join(output) + "\n", encoding="utf-8")


MTL = """# Original Dustbound Expeditions materials
newmtl RV_Cream
Kd 0.84 0.79 0.65
Ns 10
map_Kd ../textures/rv_cream.png
newmtl RV_Stripe
Kd 0.62 0.25 0.14
Ns 8
map_Kd ../textures/rv_stripe.png
newmtl Window
Kd 0.10 0.20 0.23
Ks 0.35 0.35 0.35
Ns 90
d 0.72
newmtl DarkMetal
Kd 0.15 0.16 0.16
Ks 0.25 0.25 0.25
Ns 45
newmtl LightMetal
Kd 0.48 0.50 0.48
Ks 0.30 0.30 0.30
Ns 55
newmtl Lamp
Kd 1.00 0.72 0.22
Ke 0.35 0.18 0.04
newmtl Rubber
Kd 0.035 0.04 0.045
Ns 5
newmtl Wood
Kd 0.50 0.30 0.16
map_Kd ../textures/trail_wood.png
newmtl Pine
Kd 0.16 0.33 0.22
map_Kd ../textures/pine_needles.png
newmtl Stone
Kd 0.49 0.30 0.21
map_Kd ../textures/canyon_stone.png
newmtl CrewCloth
Kd 0.68 0.30 0.15
map_Kd ../textures/crew_fabric.png
newmtl Denim
Kd 0.15 0.25 0.34
newmtl Skin
Kd 0.78 0.54 0.38
newmtl Canvas
Kd 0.69 0.60 0.43
newmtl Tool
Kd 0.26 0.31 0.32
Ks 0.35 0.35 0.35
Ns 60
"""
(MODEL_DIR / "dustbound.mtl").write_text(MTL, encoding="utf-8")

rv = Obj("rv_exterior")
# ---------------------------------------------------------------------------
# Original mobile-ready Class C expedition motorhome. The silhouette, cockpit
# and living space are modeled as one coherent vehicle; first person uses this
# actual interior rather than a camera-attached dashboard overlay.
# ---------------------------------------------------------------------------
# Structural chassis and underbody.
rv.box("ChassisMain", (0.0, -0.28, 0.08), (1.72, 0.22, 6.35), "DarkMetal")
for x in (-0.78, 0.78):
    rv.box("ChassisRail", (x, -0.38, 0.12), (0.16, 0.18, 6.10), "DarkMetal")
rv.cylinder("PropShaft", (0.0, -0.50, 0.25), 0.075, 4.4, "DarkMetal", 12, "z")
rv.box("FreshWaterTank", (-0.43, -0.34, 0.75), (0.72, 0.38, 1.25), "Tank")
rv.box("FuelTank", (0.52, -0.36, 0.45), (0.64, 0.34, 1.05), "DarkMetal")
rv.cylinder("ExhaustPipe", (-0.78, -0.44, 2.63), 0.055, 1.10, "LightMetal", 10, "z")
rv.cylinder("ExhaustTip", (-0.78, -0.44, 3.18), 0.085, 0.14, "DarkMetal", 12, "z")

# Completely rebuilt vintage Class-A shell. The previous truck hood and cab-over
# sleeper produced the wrong silhouette; the target is an old flat-front coach
# with panoramic glass, squared shoulders, real window apertures and roof cage.
body_front, body_rear = -3.34, 3.18
body_length = body_rear - body_front
rv.box("CoachFloorShell", (0.0, -0.07, (body_front + body_rear) * 0.5),
       (2.56, 0.16, body_length), "RV_Cream")
rv.box("CoachRoofShell", (0.0, 2.06, (body_front + body_rear) * 0.5),
       (2.52, 0.16, body_length), "RV_Cream")
# Horizontal shoulder bands form both sides; middle wall pieces are inserted only
# between the authored windows, leaving actual holes behind every pane.
rv.box("CoachLowerShoulderLeft", (-1.24, 0.34, -0.08),
       (0.12, 0.72, body_length), "RV_Cream")
# Split the passenger-side lower shoulder around the entry aperture; no visual
# panel or collision-like slab is allowed to cover the walk-through doorway.
rv.box("CoachLowerShoulderRightFront", (1.24, 0.34, (body_front + 0.48) * 0.5),
       (0.12, 0.72, 0.48 - body_front), "RV_Cream")
rv.box("CoachLowerShoulderRightRear", (1.24, 0.34, (1.48 + body_rear) * 0.5),
       (0.12, 0.72, body_rear - 1.48), "RV_Cream")
for side in (-1, 1):
    rv.box("CoachUpperShoulder", (side * 1.24, 1.96, -0.08),
           (0.12, 0.24, body_length), "RV_Cream")
left_gaps = [(-2.03, -1.55), (-0.55, -0.39), (0.55, 0.78), (1.82, body_rear)]
right_gaps = [(-2.03, -1.34), (-0.10, 0.48), (1.48, 1.70), (2.54, body_rear)]
for side, gaps in ((-1, left_gaps), (1, right_gaps)):
    for start, finish in gaps:
        rv.box("CoachWindowBayPillar", (side * 1.24, 1.22, (start + finish) * 0.5),
               (0.12, 1.08, finish - start), "RV_Cream")
# Door aperture spans z=.50..1.46 and remains open into the real interior.
rv.box("CoachRightDoorHeader", (1.24, 1.96, 0.98), (0.12, 0.24, 0.96), "RV_Cream")
rv.box("CoachRightDoorSill", (1.24, -0.02, 0.98), (0.12, 0.10, 0.96), "RV_Accent")
# Chamfered roof rails and front brow stop the profile reading as a raw cube.
rv.cylinder("CoachRoofEdgeLeft", (-1.18, 2.08, -0.08), 0.16, body_length, "RV_Cream", 16, "z")
rv.cylinder("CoachRoofEdgeRight", (1.18, 2.08, -0.08), 0.16, body_length, "RV_Cream", 16, "z")
rv.box("CoachRoofCrown", (0.0, 2.22, -0.08), (2.34, 0.12, body_length - 0.12), "RV_Cream")
rv.profile_prism("FrontRoofBrow", -3.56, -3.02,
                 (-1.12, 1.12, 1.78, 2.20),
                 (-1.28, 1.28, 1.74, 2.24), "RV_Cream")
# Flat-front fascia is built around (not behind) the panoramic windshield.
rv.box("FrontLowerShell", (0.0, 0.29, -3.48), (2.20, 0.74, 0.16), "RV_Cream")
rv.box("FrontLeftPillar", (-1.11, 1.19, -3.47), (0.17, 1.24, 0.18), "RV_Cream")
rv.box("FrontRightPillar", (1.11, 1.19, -3.47), (0.17, 1.24, 0.18), "RV_Cream")
rv.box("FrontHeader", (0.0, 1.82, -3.46), (2.20, 0.18, 0.18), "RV_Cream")
rv.box("RearWallCap", (0.0, 1.01, 3.22), (2.59, 2.30, 0.14), "RV_Cream")
# Lower skirts are cut around both wheel openings instead of passing through tires.
for side in (-1, 1):
    for center_z, length in ((-0.15, 2.88), (2.99, 0.38)):
        rv.box("LowerSkirt", (side * 1.27, 0.00, center_z), (0.12, 0.32, length), "RV_Accent")

# Long faded graphics match the utilitarian old-road-trip coach proportions.
for side in (-1, 1):
    x = side * 1.337
    rv.box("WideCoachStripe", (x, 0.67, 0.08), (0.032, 0.28, 5.88), "RV_Stripe")
    rv.box("ThinCoachStripe", (x + side * 0.012, 0.46, 0.04), (0.026, 0.070, 5.96), "RV_Gold")
    rv.box("UpperPinstripe", (x, 1.73, 0.18), (0.028, 0.045, 5.62), "RV_Stripe")
rv.box("FrontStripe", (0.0, 0.56, -3.575), (2.02, 0.18, 0.030), "RV_Stripe")
rv.box("RearStripe", (0.0, 0.67, 3.298), (2.28, 0.28, 0.030), "RV_Stripe")

# Tall, slightly raked panoramic windshield and real side cab glass.
rv.quad("WindshieldLeft", [(-1.02, 0.68, -3.575), (-0.07, 0.68, -3.575),
                            (-0.07, 1.73, -3.455), (-0.98, 1.73, -3.455)], "Window")
rv.quad("WindshieldRight", [(0.07, 0.68, -3.575), (1.02, 0.68, -3.575),
                             (0.98, 1.73, -3.455), (0.07, 1.73, -3.455)], "Window")
rv.box("WindshieldCenterPillar", (0.0, 1.20, -3.525), (0.09, 1.12, 0.10), "DarkMetal")
rv.box("WindshieldTopSeal", (0.0, 1.76, -3.475), (2.10, 0.08, 0.09), "DarkMetal")
rv.box("WindshieldLowerSeal", (0.0, 0.64, -3.590), (2.16, 0.10, 0.09), "DarkMetal")
rv.box("WindshieldWiperLeft", (-0.48, 0.75, -3.630), (0.78, 0.030, 0.025), "DarkMetal")
rv.box("WindshieldWiperRight", (0.48, 0.75, -3.630), (0.78, 0.030, 0.025), "DarkMetal")
for side in (-1, 1):
    rv.quad("CabSideGlass", [(side * 1.305, 0.66, -3.25), (side * 1.305, 0.66, -2.06),
                              (side * 1.305, 1.60, -2.03), (side * 1.305, 1.60, -3.18)] if side > 0 else
                             [(side * 1.305, 0.66, -2.06), (side * 1.305, 0.66, -3.25),
                              (side * 1.305, 1.60, -3.18), (side * 1.305, 1.60, -2.03)], "Window")
    rv.box("CabWindowLowerTrim", (side * 1.325, 0.63, -2.66), (0.055, 0.09, 1.24), "DarkMetal")
    rv.box("CabDoorInset", (side * 1.305, 0.32, -2.66), (0.045, 0.54, 1.12), "RV_Accent")
    rv.box("CabDoorPanel", (side * 1.334, 0.33, -2.66), (0.022, 0.44, 1.02), "RV_Cream")
    rv.box("CabDoorHandle", (side * 1.365, 0.72, -2.22), (0.035, 0.07, 0.23), "Chrome")
    rv.box("MirrorSupport", (side * 1.48, 1.06, -3.02), (0.42, 0.06, 0.06), "DarkMetal")
    rv.box("MirrorHousing", (side * 1.68, 1.09, -3.02), (0.12, 0.44, 0.31), "DarkMetal")
    rv.box("MirrorGlass", (side * 1.745, 1.09, -3.02), (0.018, 0.34, 0.22), "Mirror")

# Coach windows: deep frames, tinted panes and fabric curtains visible inside.
window_layout = [(-1, -1.05, 0.94), (-1, 0.08, 0.88), (-1, 1.30, 0.98),
                 (1, -0.72, 1.18), (1, 2.12, 0.78)]
for side, z, width in window_layout:
    x = side * 1.316
    rv.box("CoachWindowFrame", (x, 1.36, z), (0.075, 0.83, width + 0.14), "DarkMetal")
    rv.box("CoachWindowGlass", (x + side * 0.043, 1.36, z), (0.018, 0.67, width), "Window")
    rv.box("CoachWindowCurtain", (x - side * 0.055, 1.36, z + width * 0.38),
           (0.025, 0.60, 0.13), "InteriorFabric")

# Passenger entry door, open frame, hinges, handle, step and service hatches.
for z in (0.50, 1.46):
    rv.box("EntryDoorFrameRail", (1.326, 0.91, z), (0.085, 1.92, 0.075), "DarkMetal")
rv.box("EntryDoorFrameHeader", (1.326, 1.84, 0.98), (0.085, 0.075, 1.03), "DarkMetal")
rv.box("EntryDoorFrameSill", (1.326, -0.02, 0.98), (0.085, 0.075, 1.03), "DarkMetal")
rv.box("EntryDoor", (1.377, 0.91, 0.98), (0.035, 1.80, 0.84), "RV_Cream")
rv.box("EntryDoorGlass", (1.401, 1.36, 0.98), (0.018, 0.60, 0.56), "Window")
rv.box("EntryDoorHandle", (1.435, 0.91, 0.68), (0.04, 0.075, 0.22), "Chrome")
for y in (0.34, 1.46):
    rv.cylinder("EntryDoorHinge", (1.425, y, 1.40), 0.035, 0.14, "Chrome", 10, "y")
rv.box("ElectricStep", (1.56, -0.23, 0.98), (0.58, 0.10, 0.82), "DarkMetal")
rv.box("UtilityHatch", (-1.348, 0.35, 1.84), (0.025, 0.48, 0.84), "RV_Cream")
rv.box("UtilityHatchTrim", (-1.371, 0.35, 1.84), (0.018, 0.53, 0.89), "DarkMetal")
rv.box("PowerSocket", (-1.389, 0.44, 1.55), (0.025, 0.16, 0.19), "DarkMetal")
rv.cylinder("FuelFiller", (1.39, 0.36, -0.52), 0.13, 0.025, "DarkMetal", 16, "x")
rv.cylinder("WaterFiller", (-1.39, 0.36, 2.42), 0.10, 0.025, "RV_Accent", 16, "x")

# Wheel wells and mud guards clearly frame the four physical tire assemblies.
for side in (-1, 1):
    for z in (-2.35, 1.90):
        rv.cylinder("WheelWellShadow", (side * 1.255, -0.58, z), 0.67, 0.035, "Rubber", 24, "x")
        rv.wheel_arch("WheelArchTrim", (side * 1.410, -0.58, z), 0.66, 0.040, "Chrome", 20, 7)
        rv.box("MudFlap", (side * 1.26, -0.56, z + 0.62), (0.12, 0.68, 0.34), "Rubber")

# Flat-nose automotive equipment: bumper, broad grille and paired lamps sit
# directly below the windshield rather than at the end of a fake truck hood.
rv.box("FrontBumper", (0.0, -0.11, -3.68), (2.35, 0.25, 0.28), "Chrome")
rv.box("FrontValance", (0.0, 0.19, -3.64), (2.12, 0.33, 0.12), "RV_Accent")
rv.box("FrontGrille", (0.0, 0.30, -3.725), (0.94, 0.30, 0.035), "DarkMetal")
for x in (-0.35, -0.12, 0.12, 0.35):
    rv.box("GrilleSlat", (x, 0.30, -3.749), (0.055, 0.25, 0.018), "Chrome")
for x in (-0.79, 0.79):
    rv.box("HeadlampHousing", (x, 0.48, -3.66), (0.46, 0.30, 0.09), "DarkMetal")
    rv.box("HeadlampLens", (x, 0.49, -3.713), (0.34, 0.20, 0.022), "Headlamp")
    rv.box("FrontIndicator", (x + (0.26 if x > 0 else -0.26), 0.42, -3.70), (0.13, 0.17, 0.025), "Amber")
rv.box("FrontLicensePlate", (0.0, -0.03, -3.835), (0.62, 0.18, 0.025), "Plate")
rv.box("RearBumper", (0.0, -0.14, 3.35), (2.50, 0.25, 0.30), "Chrome")
rv.box("RearLicensePlate", (0.0, 0.10, 3.335), (0.58, 0.20, 0.025), "Plate")
for x in (-0.92, 0.92):
    rv.box("TailLampHousing", (x, 0.54, 3.343), (0.31, 0.54, 0.07), "DarkMetal")
    rv.box("TailLampRed", (x, 0.67, 3.387), (0.22, 0.19, 0.025), "TailLamp")
    rv.box("TailLampAmber", (x, 0.43, 3.387), (0.22, 0.15, 0.025), "Amber")
for x in (-0.93, 0.0, 0.93):
    rv.box("RoofMarkerFront", (x, 2.08, -3.30), (0.16, 0.10, 0.055), "Amber")
    rv.box("RoofMarkerRear", (x, 2.09, 3.265), (0.16, 0.10, 0.045), "TailLamp")

# Expedition roof: awning, ladder, solar array, AC, vents, rack and cargo.
rv.cylinder("AwningCase", (1.45, 2.04, 0.08), 0.105, 4.22, "RV_Stripe", 16, "z")
rv.box("AwningEndFront", (1.45, 2.04, -2.06), (0.26, 0.27, 0.16), "DarkMetal")
rv.box("AwningEndRear", (1.45, 2.04, 2.22), (0.26, 0.27, 0.16), "DarkMetal")
for x in (-0.92, 0.92):
    rv.box("RoofRackRail", (x, 2.48, 0.56), (0.07, 0.16, 4.26), "DarkMetal")
for z in (-1.34, -0.30, 0.75, 1.82, 2.38):
    rv.box("RoofRackCrossbar", (0.0, 2.48, z), (1.88, 0.07, 0.07), "DarkMetal")
rv.box("SolarPanelLeft", (-0.54, 2.45, -0.54), (0.92, 0.08, 1.58), "Solar")
rv.box("SolarPanelRight", (0.54, 2.45, -0.54), (0.92, 0.08, 1.58), "Solar")
for x in (-0.54, 0.54):
    for z in (-1.14, 0.06):
        rv.box("SolarCell", (x, 2.496, z), (0.74, 0.012, 0.48), "SolarCell")
rv.box("RoofACBase", (0.42, 2.52, 1.37), (1.05, 0.24, 0.86), "LightMetal")
rv.box("RoofACShroud", (0.42, 2.70, 1.37), (0.86, 0.20, 0.67), "RV_Cream")
for z in (1.17, 1.30, 1.43, 1.56):
    rv.box("ACVentSlot", (0.42, 2.72, z), (0.66, 0.08, 0.035), "DarkMetal")
rv.box("RoofVentFrame", (-0.55, 2.50, 2.10), (0.62, 0.17, 0.62), "Chrome")
rv.box("RoofVentLid", (-0.55, 2.62, 2.05), (0.54, 0.09, 0.54), "Window")
rv.box("RoofCargo", (-0.52, 2.68, -1.72), (0.82, 0.48, 0.94), "InteriorWood")
for axis in (-0.32, 0.32):
    rv.box("CargoBand", (-0.52 + axis, 2.69, -1.72), (0.055, 0.51, 0.98), "DarkMetal")
rv.cylinder("SpareTire", (-0.25, 0.62, 3.42), 0.56, 0.27, "Rubber", 24, "z")
rv.cylinder("SpareRim", (-0.25, 0.62, 3.58), 0.24, 0.045, "Chrome", 16, "z")
for x in (0.71, 1.13):
    rv.box("RearLadderRail", (x, 1.17, 3.43), (0.055, 2.05, 0.07), "Chrome")
for y in (0.28, 0.64, 1.00, 1.36, 1.72, 2.08):
    rv.box("RearLadderRung", (0.92, y, 3.45), (0.48, 0.055, 0.075), "Chrome")
rv.box("RearCameraHousing", (0.0, 1.98, 3.37), (0.25, 0.16, 0.17), "DarkMetal")
rv.cylinder("RearCameraLens", (0.0, 1.97, 3.47), 0.055, 0.025, "Window", 12, "z")

# Fully modeled cockpit. The player viewpoint sits behind this steering wheel.
rv.box("CabInteriorFloor", (0.0, -0.01, -2.38), (2.35, 0.09, 2.18), "InteriorVinyl")
rv.box("DashboardMain", (0.0, 0.62, -2.87), (2.20, 0.42, 0.52), "Dashboard")
rv.box("DashboardTop", (0.0, 0.85, -2.98), (2.28, 0.10, 0.64), "Dashboard")
rv.profile_prism("DashboardBrow", -3.23, -2.70,
                 (-0.98, 0.98, 0.73, 0.88), (-1.08, 1.08, 0.70, 0.94), "Dashboard")
rv.box("InstrumentCluster", (0.52, 0.81, -2.62), (0.76, 0.30, 0.11), "DarkMetal")
for x in (0.27, 0.51, 0.75):
    rv.cylinder("DashboardGauge", (x, 0.82, -2.55), 0.105, 0.028, "Gauge", 20, "z")
    rv.cylinder("GaugeNeedle", (x, 0.82, -2.53), 0.018, 0.032, "TailLamp", 8, "z")
rv.box("CenterConsole", (-0.15, 0.56, -2.59), (0.42, 0.58, 0.24), "Dashboard")
rv.box("NavigationScreen", (-0.15, 0.69, -2.455), (0.29, 0.18, 0.025), "Screen")
for y in (0.43, 0.54):
    for x in (-0.26, -0.04):
        rv.cylinder("ConsoleControl", (x, y, -2.455), 0.035, 0.024, "Chrome", 10, "z")
rv.box("GearGate", (0.10, 0.43, -2.19), (0.30, 0.08, 0.40), "DarkMetal")
rv.cylinder("GearLever", (0.10, 0.64, -2.19), 0.038, 0.42, "Chrome", 12, "y")
rv.ellipsoid("GearKnob", (0.10, 0.88, -2.19), (0.09, 0.12, 0.09), "Dashboard", 14, 8)
rv.torus("CockpitSteeringWheel", (0.53, 0.79, -2.22), 0.29, 0.043, "Rubber", "z", 24, 8)
rv.cylinder("SteeringHub", (0.53, 0.79, -2.22), 0.105, 0.09, "Dashboard", 16, "z")
rv.box("SteeringSpokeHorizontal", (0.53, 0.79, -2.235), (0.48, 0.060, 0.055), "Dashboard")
rv.box("SteeringSpokeLower", (0.53, 0.63, -2.235), (0.065, 0.30, 0.06), "Dashboard")
rv.cylinder("SteeringColumn", (0.53, 0.73, -2.48), 0.065, 0.55, "DarkMetal", 12, "z")
for x in (0.43, 0.64):
    rv.box("Pedal", (x, 0.16, -2.71), (0.13, 0.06, 0.22), "Rubber")

# Driver and passenger seats with separate cushions, bolsters and headrests.
for x, prefix in ((0.54, "Driver"), (-0.54, "Passenger")):
    rv.box(prefix + "SeatBase", (x, 0.30, -1.56), (0.66, 0.24, 0.76), "DarkMetal")
    rv.box(prefix + "SeatCushion", (x, 0.49, -1.64), (0.68, 0.22, 0.72), "InteriorFabric")
    rv.box(prefix + "SeatBack", (x, 0.91, -1.25), (0.70, 0.86, 0.20), "InteriorFabric")
    rv.box(prefix + "Headrest", (x, 1.44, -1.25), (0.42, 0.27, 0.20), "InteriorFabric")
    for side in (-1, 1):
        rv.box(prefix + "SeatBolster", (x + side * 0.30, 0.55, -1.61), (0.10, 0.28, 0.72), "InteriorVinyl")
    rv.box(prefix + "SeatBelt", (x + (0.28 if x > 0 else -0.28), 1.00, -1.13), (0.045, 0.85, 0.035), "SeatBelt")
# Keep the overhead console behind the driver eye; placing it above the dash
# projected a giant black slab across the upper third of the windshield.
rv.box("CabOverheadConsole", (0.0, 2.00, -1.28), (1.04, 0.12, 0.38), "InteriorVinyl")
rv.box("SunVisorDriver", (0.57, 1.69, -2.96), (0.62, 0.13, 0.045), "InteriorFabric")
rv.box("SunVisorPassenger", (-0.57, 1.69, -2.96), (0.62, 0.13, 0.045), "InteriorFabric")
rv.box("RearViewMirror", (0.0, 1.54, -2.94), (0.48, 0.17, 0.07), "Mirror")

# Warm, navigable living compartment visible through the cab and side windows.
rv.box("InteriorFloor", (0.0, 0.00, 0.82), (2.34, 0.10, 4.68), "InteriorWood")
rv.box("InteriorCeiling", (0.0, 2.05, 0.66), (2.34, 0.08, 4.92), "InteriorVinyl")
# Living-space liners begin behind the seat backs; extending them alongside the
# driver eye created the giant cream slab seen when looking left/right in 1P.
# Interior liners repeat the exterior's real window/door apertures. Solid liner
# slabs previously sat immediately behind the glass and made every window fake.
for y, height in ((0.38, 0.72), (1.90, 0.26)):
    rv.box("InteriorWallLeftBand", (-1.20, y, 1.03), (0.07, height, 4.16), "InteriorWall")
    rv.box("InteriorWallRightFrontBand", (1.20, y, -0.28), (0.07, height, 1.54), "InteriorWall")
    rv.box("InteriorWallRightRearBand", (1.20, y, 2.31), (0.07, height, 1.70), "InteriorWall")
for side, gaps in ((-1, [(-1.58, -1.55), (-0.55, -0.39), (0.55, 0.78), (1.82, 3.11)]),
                   (1, [(-1.58, -1.34), (-0.10, 0.48), (1.48, 1.70), (2.54, 3.11)])):
    for start, finish in gaps:
        if finish - start > 0.06:
            rv.box("InteriorWindowPillar", (side * 1.20, 1.24, (start + finish) * 0.5),
                   (0.07, 1.02, finish - start), "InteriorWall")
rv.box("InteriorDoorHeader", (1.20, 1.90, 0.98), (0.07, 0.18, 0.96), "InteriorWall")
rv.box("CabDividerLeft", (-0.92, 1.24, -1.12), (0.48, 1.44, 0.10), "InteriorWood")
rv.box("CabDividerRight", (0.92, 1.24, -1.12), (0.48, 1.44, 0.10), "InteriorWood")
# Kitchen on the left.
rv.box("KitchenLowerCabinet", (-0.90, 0.46, 0.18), (0.55, 0.82, 1.62), "InteriorWood")
rv.box("KitchenCounter", (-0.88, 0.91, 0.18), (0.64, 0.10, 1.68), "Countertop")
rv.box("KitchenUpperCabinet", (-0.94, 1.67, 0.34), (0.46, 0.58, 1.28), "InteriorWood")
rv.box("RefrigeratorBody", (-0.91, 1.03, 1.46), (0.54, 1.72, 0.66), "LightMetal")
rv.box("RefrigeratorDoor", (-0.60, 1.03, 1.46), (0.035, 1.58, 0.58), "InteriorVinyl")
rv.box("FridgeHandle", (-0.56, 1.20, 1.20), (0.025, 0.42, 0.055), "Chrome")
rv.box("FridgeFreezerLine", (-0.555, 1.47, 1.46), (0.020, 0.035, 0.54), "DarkMetal")
for z in (-0.26, 0.28, 0.82):
    rv.box("KitchenCabinetDoor", (-0.595, 0.54, z), (0.035, 0.55, 0.44), "InteriorWood")
    rv.box("KitchenCabinetHandle", (-0.565, 0.58, z - 0.14), (0.025, 0.05, 0.14), "Chrome")
rv.box("StoveTop", (-0.87, 0.975, -0.14), (0.44, 0.025, 0.50), "DarkMetal")
for x in (-0.98, -0.77):
    for z in (-0.29, 0.01):
        rv.cylinder("StoveBurner", (x, 0.995, z), 0.075, 0.02, "Rubber", 12, "y")
rv.box("KitchenSink", (-0.87, 0.975, 0.55), (0.39, 0.025, 0.42), "Chrome")
rv.cylinder("KitchenFaucet", (-0.87, 1.11, 0.72), 0.035, 0.30, "Chrome", 10, "y")
# Dinette on the right.
for z in (-0.05, 1.05):
    rv.box("DinetteBenchBase", (0.91, 0.34, z), (0.55, 0.58, 0.76), "InteriorWood")
    rv.box("DinetteBenchCushion", (0.90, 0.66, z), (0.58, 0.17, 0.72), "InteriorFabric")
    rv.box("DinetteBackCushion", (1.08, 1.00, z), (0.17, 0.60, 0.70), "InteriorFabric")
rv.cylinder("DinetteTableLeg", (0.50, 0.58, 0.50), 0.055, 0.82, "Chrome", 12, "y")
rv.box("DinetteTable", (0.50, 0.98, 0.50), (0.78, 0.09, 0.92), "InteriorWood")
# Rear bed/storage and overhead cabinetry.
rv.box("RearBedBase", (0.0, 0.38, 2.42), (2.18, 0.68, 1.30), "InteriorWood")
rv.box("RearMattress", (0.0, 0.78, 2.42), (2.12, 0.18, 1.24), "InteriorFabric")
rv.box("RearBlanket", (0.0, 0.90, 2.66), (2.04, 0.10, 0.68), "Blanket")
for x in (-0.72, 0.0, 0.72):
    rv.box("RearOverheadCabinet", (x, 1.73, 2.63), (0.64, 0.52, 0.48), "InteriorWood")
    rv.box("RearCabinetHandle", (x, 1.66, 2.35), (0.16, 0.04, 0.025), "Chrome")
# Ceiling fixtures and small lived-in details.
for z in (-0.55, 0.70, 1.82):
    rv.cylinder("InteriorCeilingLight", (0.0, 1.99, z), 0.16, 0.035, "InteriorLight", 16, "y")
rv.box("RouteMap", (-1.145, 1.35, -0.72), (0.025, 0.52, 0.68), "Map")
rv.box("FireExtinguisher", (1.08, 0.43, -0.68), (0.15, 0.52, 0.15), "TailLamp")
rv.cylinder("ExtinguisherTop", (1.08, 0.73, -0.68), 0.065, 0.12, "DarkMetal", 10, "y")
rv.save()

# Detailed wheel assembly is attached to each VehicleWheel3D so tires visibly
# steer, spin and ride the suspension rather than being painted onto the shell.
wheel = Obj("rv_wheel")
wheel.torus("AllTerrainTire", (0.0, 0.0, 0.0), 0.47, 0.14, "Rubber", "x", 28, 10)
wheel.cylinder("RimOuter", (0.0, 0.0, 0.0), 0.315, 0.30, "Chrome", 24, "x")
wheel.cylinder("RimInset", (0.0, 0.0, 0.0), 0.235, 0.325, "DarkMetal", 20, "x")
wheel.cylinder("HubCap", (0.0, 0.0, 0.0), 0.125, 0.35, "Chrome", 18, "x")
for angle_index in range(6):
    angle = math.tau * angle_index / 6.0
    wheel.cylinder("LugNut", (0.18, math.cos(angle) * 0.17, math.sin(angle) * 0.17),
                   0.028, 0.055, "DarkMetal", 8, "x")
wheel.save()
crate = Obj("trail_crate")
crate.box("CrateCore", (0, 0, 0), (.86, .70, .72), "Wood")
for y in (-.28, 0, .28):
    crate.box("FrontSlat", (0, y, -.375), (.92, .13, .06), "Canvas")
    crate.box("BackSlat", (0, y, .375), (.92, .13, .06), "Canvas")
for x in (-.39, .39): crate.box("Band", (x, 0, 0), (.08, .76, .78), "DarkMetal")
crate.save()

pine = Obj("pine_tree")
pine.cylinder("Trunk", (0, 1.35, 0), .22, 2.70, "Wood", 9)
pine.frustum("LowerCrown", (0, 2.75, 0), 1.55, .14, 2.55, "Pine", 10)
pine.frustum("MiddleCrown", (0, 3.85, 0), 1.22, .10, 2.25, "Pine", 10)
pine.frustum("TopCrown", (0, 4.82, 0), .83, .04, 1.85, "Pine", 10)
pine.save()

rock = Obj("canyon_rock")
rock.ellipsoid("CanyonRock", (0, .65, 0), (1.08, .74, .91), "Stone", 9, 5, .22, 101)
rock.save()

hands = Obj("first_person_hands")
# Keep first-person arms low and peripheral so they frame gameplay instead of
# obscuring the trail on a phone-sized screen.
hands.ellipsoid("LeftForearm", (-.72, -.69, -.98), (.11, .12, .48), "CrewCloth", 14, 8)
hands.ellipsoid("RightForearm", (.72, -.69, -.98), (.11, .12, .48), "CrewCloth", 14, 8)
hands.ellipsoid("LeftHand", (-.67, -.62, -1.37), (.13, .10, .15), "Skin", 14, 8)
hands.ellipsoid("RightHand", (.67, -.62, -1.37), (.13, .10, .15), "Skin", 14, 8)
hands.save()

sign = Obj("trail_sign")
sign.cylinder("Post", (0, 1.18, 0), .10, 2.36, "Wood", 9)
sign.box("SignBoard", (0, 2.18, 0), (1.65, .72, .14), "Wood")
sign.box("PaintMark", (0, 2.18, -.08), (1.30, .12, .025), "Lamp")
sign.save()

# Convert the simple authoring OBJ files to portable glTF 2.0 scenes. Godot's
# glTF importer is used for every target, avoiding platform-specific OBJ/MTL
# behavior while keeping the generated source geometry easy to inspect.
MATERIALS = {
    "RV_Cream": ((0.70, 0.64, 0.51, 1.0), "rv_cream.png", 0.94),
    "RV_Stripe": ((0.62, 0.25, 0.14, 1.0), "rv_stripe.png", 0.88),
    "Window": ((0.12, 0.24, 0.28, 0.34), None, 0.12),
    "DarkMetal": ((0.15, 0.16, 0.16, 1.0), None, 0.38),
    "LightMetal": ((0.48, 0.50, 0.48, 1.0), None, 0.30),
    "Lamp": ((1.00, 0.72, 0.22, 1.0), None, 0.45),
    "Rubber": ((0.035, 0.04, 0.045, 1.0), "rv_tire.png", 0.98),
    "Wood": ((0.50, 0.30, 0.16, 1.0), "trail_wood.png", 0.92),
    "Pine": ((0.16, 0.33, 0.22, 1.0), "pine_needles.png", 0.95),
    "Stone": ((0.49, 0.30, 0.21, 1.0), "canyon_stone.png", 0.96),
    "CrewCloth": ((0.68, 0.30, 0.15, 1.0), "crew_fabric.png", 0.90),
    "Denim": ((0.15, 0.25, 0.34, 1.0), None, 0.92),
    "Skin": ((0.78, 0.54, 0.38, 1.0), None, 0.86),
    "Canvas": ((0.69, 0.60, 0.43, 1.0), None, 0.94),
    "Tool": ((0.26, 0.31, 0.32, 1.0), None, 0.28),
    "RV_Accent": ((0.10, 0.19, 0.19, 1.0), None, 0.78),
    "RV_Gold": ((0.78, 0.52, 0.24, 1.0), None, 0.64),
    "Chrome": ((0.69, 0.72, 0.71, 1.0), "rv_metal.png", 0.20),
    "Mirror": ((0.30, 0.43, 0.46, 1.0), None, 0.08),
    "Headlamp": ((1.0, 0.88, 0.59, 1.0), None, 0.20),
    "TailLamp": ((0.68, 0.055, 0.035, 1.0), None, 0.28),
    "Amber": ((1.0, 0.43, 0.07, 1.0), None, 0.32),
    "Plate": ((0.86, 0.85, 0.72, 1.0), None, 0.62),
    "Tank": ((0.30, 0.39, 0.40, 1.0), None, 0.74),
    "Solar": ((0.055, 0.12, 0.17, 1.0), None, 0.16),
    "SolarCell": ((0.08, 0.24, 0.34, 1.0), None, 0.12),
    "InteriorVinyl": ((0.24, 0.26, 0.25, 1.0), "rv_vinyl.png", 0.84),
    "InteriorWood": ((0.49, 0.30, 0.17, 1.0), "rv_interior_wood.png", 0.78),
    "InteriorFabric": ((0.39, 0.48, 0.44, 1.0), "rv_upholstery.png", 0.93),
    "InteriorWall": ((0.80, 0.76, 0.65, 1.0), None, 0.94),
    "Dashboard": ((0.12, 0.14, 0.14, 1.0), "rv_vinyl.png", 0.82),
    "Gauge": ((0.035, 0.11, 0.14, 1.0), None, 0.24),
    "Screen": ((0.035, 0.20, 0.22, 1.0), None, 0.18),
    "SeatBelt": ((0.08, 0.08, 0.075, 1.0), None, 0.96),
    "Countertop": ((0.67, 0.62, 0.51, 1.0), None, 0.70),
    "Blanket": ((0.60, 0.25, 0.16, 1.0), None, 0.94),
    "InteriorLight": ((1.0, 0.83, 0.49, 1.0), None, 0.32),
    "Map": ((0.76, 0.68, 0.49, 1.0), None, 0.90),
}


def convert_obj_to_gltf(source: Path) -> None:
    """Convert authoring OBJ while preserving every named component as a node."""
    vertices: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    normals: list[tuple[float, float, float]] = []
    objects: dict[str, dict[str, list[list[tuple[int, int, int]]]]] = {}
    object_name = source.stem
    material = "Stone"
    for raw in source.read_text(encoding="utf-8").splitlines():
        parts = raw.split()
        if not parts:
            continue
        if parts[0] == "v":
            vertices.append(tuple(map(float, parts[1:4])))
        elif parts[0] == "vt":
            uvs.append(tuple(map(float, parts[1:3])))
        elif parts[0] == "vn":
            normals.append(tuple(map(float, parts[1:4])))
        elif parts[0] == "o":
            authored_name = parts[1]
            if source.stem == "rv_exterior":
                dynamic_components = {
                    "RoofCargo", "FrontBumper", "CockpitSteeringWheel",
                    "SteeringHub", "SteeringSpokeHorizontal", "SteeringSpokeLower",
                    "EntryDoor", "EntryDoorGlass", "EntryDoorHandle",
                    "GearLever", "GearKnob",
                }
                cockpit_interior_prefixes = (
                    "CabInterior", "Dashboard", "Instrument", "Gauge", "CenterConsole",
                    "Navigation", "ConsoleControl", "Pedal", "Driver", "Passenger",
                    "CabOverhead", "SunVisor", "RearView", "GearGate",
                )
                interior_prefixes = (
                    "Interior", "CabDivider", "Kitchen", "Stove", "Dinette",
                    "RearBed", "RearMattress", "RearBlanket", "RearOverhead",
                    "RearCabinet", "RouteMap", "FireExtinguisher", "Extinguisher",
                    "Refrigerator", "Fridge",
                )
                cockpit_frame_prefixes = (
                    "Windshield", "CabSideGlass", "CabWindowLowerTrim",
                    "FrontLeftPillar", "FrontRightPillar", "FrontHeader",
                    "MirrorSupport", "MirrorHousing", "MirrorGlass",
                )
                if authored_name in dynamic_components:
                    object_name = authored_name
                elif authored_name.startswith(cockpit_interior_prefixes):
                    object_name = "StaticCockpitInterior"
                elif authored_name.startswith(interior_prefixes):
                    object_name = "StaticRVInterior"
                elif authored_name.startswith(cockpit_frame_prefixes):
                    object_name = "StaticCockpitFrame"
                else:
                    object_name = "StaticRVExterior"
            elif source.stem == "rv_wheel":
                object_name = "DetailedWheelAssembly"
            else:
                object_name = authored_name
        elif parts[0] == "usemtl":
            material = parts[1]
        elif parts[0] == "f":
            face = []
            for ref in parts[1:]:
                indices = ref.split("/")
                face.append((int(indices[0]) - 1, int(indices[1]) - 1, int(indices[2]) - 1))
            objects.setdefault(object_name, {}).setdefault(material, []).append(face)

    blob = bytearray()
    buffer_views = []
    accessors = []

    def align() -> None:
        while len(blob) % 4:
            blob.append(0)

    def add_data(data: bytes, target: int | None = None) -> int:
        align()
        offset = len(blob)
        blob.extend(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        buffer_views.append(view)
        return len(buffer_views) - 1

    def add_accessor(view: int, component: int, count: int, kind: str,
                     minimum=None, maximum=None) -> int:
        accessor = {"bufferView": view, "componentType": component, "count": count, "type": kind}
        if minimum is not None:
            accessor["min"] = minimum
            accessor["max"] = maximum
        accessors.append(accessor)
        return len(accessors) - 1

    used_materials: list[str] = []
    for groups in objects.values():
        for name in groups:
            if name not in used_materials:
                used_materials.append(name)
    material_indices = {name: index for index, name in enumerate(used_materials)}
    material_defs = []
    images = []
    textures = []
    texture_lookup: dict[str, int] = {}
    metallic_names = {"Chrome", "LightMetal", "Mirror"}
    emissive_colors = {
        "Lamp": (0.35, 0.18, 0.04), "Headlamp": (0.55, 0.42, 0.18),
        "TailLamp": (0.36, 0.015, 0.008), "Amber": (0.42, 0.12, 0.01),
        "InteriorLight": (0.48, 0.30, 0.08), "Gauge": (0.02, 0.18, 0.22),
        "Screen": (0.01, 0.19, 0.23),
    }
    for name in used_materials:
        color, texture_file, roughness = MATERIALS[name]
        # Painted textures carry their own authored color. Other materials use
        # physically plausible roughness/metal response in Godot's mobile PBR.
        factor = (1.0, 1.0, 1.0, color[3]) if texture_file else color
        pbr = {
            "baseColorFactor": list(factor),
            "roughnessFactor": roughness,
            "metallicFactor": 0.78 if name in metallic_names else 0.0,
        }
        if texture_file:
            if texture_file not in texture_lookup:
                images.append({"uri": f"../textures/{texture_file}"})
                textures.append({"source": len(images) - 1, "sampler": 0})
                texture_lookup[texture_file] = len(textures) - 1
            pbr["baseColorTexture"] = {"index": texture_lookup[texture_file]}
        definition = {"name": name, "pbrMetallicRoughness": pbr}
        if color[3] < 1.0:
            definition["alphaMode"] = "BLEND"
            definition["doubleSided"] = True
        if name in {"Map", "SolarCell"}:
            definition["doubleSided"] = True
        if name in emissive_colors:
            definition["emissiveFactor"] = list(emissive_colors[name])
        material_defs.append(definition)

    meshes = []
    nodes = [{"name": source.stem, "children": []}]
    for current_object, groups in objects.items():
        referenced = [vertices[ref[0]] for faces in groups.values() for face in faces for ref in face]
        if not referenced:
            continue
        mins = [min(value[axis] for value in referenced) for axis in range(3)]
        maxs = [max(value[axis] for value in referenced) for axis in range(3)]
        center = tuple((mins[axis] + maxs[axis]) * 0.5 for axis in range(3))
        primitives = []
        for name, faces in groups.items():
            local_map: dict[tuple[int, int, int], int] = {}
            local_positions = []
            local_normals = []
            local_uvs = []
            local_indices = []
            for face in faces:
                face_indices = []
                for ref in face:
                    if ref not in local_map:
                        local_map[ref] = len(local_positions)
                        position = vertices[ref[0]]
                        local_positions.append(tuple(position[axis] - center[axis] for axis in range(3)))
                        local_uvs.append((uvs[ref[1]][0], 1.0 - uvs[ref[1]][1]))
                        local_normals.append(normals[ref[2]])
                    face_indices.append(local_map[ref])
                for index in range(1, len(face_indices) - 1):
                    local_indices.extend((face_indices[0], face_indices[index], face_indices[index + 1]))
            position_bytes = b"".join(struct.pack("<3f", *value) for value in local_positions)
            normal_bytes = b"".join(struct.pack("<3f", *value) for value in local_normals)
            uv_bytes = b"".join(struct.pack("<2f", *value) for value in local_uvs)
            index_bytes = b"".join(struct.pack("<I", value) for value in local_indices)
            position_view = add_data(position_bytes, 34962)
            normal_view = add_data(normal_bytes, 34962)
            uv_view = add_data(uv_bytes, 34962)
            index_view = add_data(index_bytes, 34963)
            position_mins = [min(value[axis] for value in local_positions) for axis in range(3)]
            position_maxs = [max(value[axis] for value in local_positions) for axis in range(3)]
            primitives.append({
                "attributes": {
                    "POSITION": add_accessor(position_view, 5126, len(local_positions), "VEC3",
                                               position_mins, position_maxs),
                    "NORMAL": add_accessor(normal_view, 5126, len(local_normals), "VEC3"),
                    "TEXCOORD_0": add_accessor(uv_view, 5126, len(local_uvs), "VEC2"),
                },
                "indices": add_accessor(index_view, 5125, len(local_indices), "SCALAR"),
                "material": material_indices[name],
                "mode": 4,
            })
        mesh_index = len(meshes)
        meshes.append({"name": current_object, "primitives": primitives})
        node_index = len(nodes)
        nodes.append({"name": current_object, "mesh": mesh_index, "translation": list(center)})
        nodes[0]["children"].append(node_index)

    document = {
        "asset": {"version": "2.0", "generator": "Dustbound original component-preserving asset generator"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": material_defs,
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": images,
        "textures": textures,
        "buffers": [{"byteLength": len(blob),
                     "uri": "data:application/octet-stream;base64," + base64.b64encode(blob).decode("ascii")}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }
    (MODEL_DIR / f"{source.stem}.gltf").write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")

for obj_path in sorted(MODEL_DIR.glob("*.obj")):
    convert_obj_to_gltf(obj_path)
    obj_path.unlink()
(MODEL_DIR / "dustbound.mtl").unlink(missing_ok=True)
print(f"Generated {len(list(MODEL_DIR.glob('*.gltf')))} glTF models and {len(list(TEXTURE_DIR.glob('*.png')))} textures.")
