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


def paint_texture(name: str, base: tuple[int, int, int], seed: int, pattern: str) -> None:
    rng = random.Random(seed)
    noise = [[rng.randint(-13, 13) for _ in range(128)] for _ in range(128)]

    def pixel(x: int, y: int) -> tuple[int, int, int]:
        value = noise[y][x]
        if pattern == "panel":
            if x % 64 in (0, 1) or y % 48 in (0, 1):
                value -= 24
            if (x + y * 3) % 97 < 2:
                value += 12
        elif pattern == "stripe":
            value += 15 if (y // 12) % 2 == 0 else -8
            if y % 32 < 2:
                value += 30
        elif pattern == "wood":
            value += int(math.sin(x * 0.20 + math.sin(y * 0.08) * 2.2) * 17)
            if x % 31 < 2:
                value -= 25
        elif pattern == "pine":
            value += int(math.sin((x + y) * 0.17) * 11)
            if (x * 5 + y * 3) % 43 < 3:
                value += 22
        elif pattern == "rock":
            value += int(math.sin(x * 0.09) * 9 + math.cos(y * 0.13) * 12)
            if ((x // 18) + (y // 15)) % 3 == 0:
                value -= 11
        elif pattern == "fabric":
            value += 8 if (x + y) % 5 == 0 else -3
        return tuple(channel + value for channel in base)

    write_png(name, 128, 128, pixel)


for args in [
    ("rv_cream.png", (215, 202, 166), 17, "panel"),
    ("rv_stripe.png", (158, 64, 35), 29, "stripe"),
    ("trail_wood.png", (121, 76, 42), 41, "wood"),
    ("pine_needles.png", (45, 82, 62), 53, "pine"),
    ("canyon_stone.png", (126, 78, 54), 67, "rock"),
    ("crew_fabric.png", (174, 78, 42), 71, "fabric"),
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
    return (int(132 + value), int(82 + value * 0.72), int(52 + value * 0.48))


write_png("ground_dirt.png", 512, 512, ground_pixel)


class Obj:
    def __init__(self, name: str):
        self.name = name
        self.vertices: list[tuple[float, float, float]] = []
        self.uvs: list[tuple[float, float]] = []
        self.normals: list[tuple[float, float, float]] = []
        self.lines: list[str] = ["# Original Dustbound Expeditions low-poly model", "mtllib dustbound.mtl"]
        self.current_material = ""

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
        self.lines.append(f"o {object_name}")
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

    def cylinder(self, object_name: str, center: tuple[float, float, float], radius: float, height: float, material: str, segments: int = 10, axis: str = "y") -> None:
        self.lines.append(f"o {object_name}")
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
        self.lines.append(f"o {object_name}")
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
        self.lines.append(f"o {object_name}")
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
        self.lines.append(f"o {object_name}")
        cx, cy, cz = center
        grid = []
        for i in range(segments):
            a = math.tau * i / segments
            row = []
            for j in range(sides):
                b = math.tau * j / sides
                radial = major + math.cos(b)*minor
                if axis == "z": point = (cx + math.cos(a)*radial, cy + math.sin(a)*radial, cz + math.sin(b)*minor)
                else: point = (cx + math.cos(a)*radial, cy + math.sin(b)*minor, cz + math.sin(a)*radial)
                row.append(point)
            grid.append(row)
        for i in range(segments):
            for j in range(sides):
                ni, nj = (i+1)%segments, (j+1)%sides
                points = [grid[i][j], grid[ni][j], grid[ni][nj], grid[i][nj]]
                self._face(points, (0, 0, 1), material)

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
rv.box("Coach", (0, .83, .28), (2.48, 1.92, 5.05), "RV_Cream")
rv.box("Cab", (0, .28, -2.65), (2.38, 1.15, 1.10), "RV_Cream")
rv.box("RoofCap", (0, 1.91, .28), (2.58, .18, 5.20), "RV_Cream")
for side in (-1, 1):
    rv.box(f"StripeSide{side}", (side*1.255, .55, .18), (.045, .36, 4.80), "RV_Stripe")
rv.box("StripeFront", (0, .48, -3.215), (2.28, .30, .045), "RV_Stripe")
rv.box("Windshield", (0, .91, -3.225), (1.74, .61, .04), "Window")
for side in (-1, 1):
    rv.box(f"CabSideWindow{side}", (side*1.215, .92, -2.55), (.035, .58, .75), "Window")
for index, z in enumerate((-.72, .42, 1.52)):
    rv.box(f"CoachWindowL{index}", (-1.26, 1.13, z), (.035, .60, .74), "Window")
rv.box("CoachWindowR", (1.26, 1.13, -.58), (.035, .60, 1.08), "Window")
rv.box("Door", (1.265, .68, 1.26), (.04, 1.62, .82), "RV_Cream")
rv.box("DoorWindow", (1.29, 1.12, 1.26), (.025, .53, .58), "Window")
rv.box("FrontBumper", (0, -.18, -3.32), (2.58, .22, .28), "LightMetal")
rv.box("RearBumper", (0, -.18, 2.94), (2.52, .22, .27), "LightMetal")
rv.box("Grille", (0, .18, -3.25), (1.16, .34, .04), "DarkMetal")
for x in (-.82, .82): rv.box(f"Headlamp{x}", (x, .38, -3.25), (.36, .27, .05), "Lamp")
for x in (-.86, .86):
    rv.box("RackRail", (x, 2.09, .45), (.07, .17, 3.55), "DarkMetal")
for z in (-1.22, -.2, .82, 1.75): rv.box("RackCrossbar", (0, 2.09, z), (1.82, .07, .07), "DarkMetal")
rv.box("RoofCargo", (-.42, 2.30, .45), (.82, .42, 1.18), "Wood")
rv.cylinder("SpareWheel", (0, .55, 2.86), .58, .26, "Rubber", 14, "z")
for y in (.15, .62, 1.09, 1.56): rv.box("RearLadderRung", (1.02, y, 2.87), (.42, .045, .06), "LightMetal")
rv.save()

crew = Obj("crew_member")
crew.ellipsoid("Torso", (0, 1.05, 0), (.48, .68, .36), "CrewCloth", 12, 7)
crew.ellipsoid("Head", (0, 1.92, -.03), (.36, .38, .35), "Skin", 12, 7)
crew.ellipsoid("Nose", (0, 1.88, -.35), (.11, .09, .14), "Skin", 8, 5)
crew.cylinder("LeftLeg", (-.22, .37, 0), .16, .65, "Canvas", 9)
crew.cylinder("RightLeg", (.22, .37, 0), .16, .65, "Canvas", 9)
crew.cylinder("LeftArm", (-.53, 1.08, 0), .12, .72, "Skin", 9)
crew.cylinder("RightArm", (.53, 1.08, 0), .12, .72, "Skin", 9)
crew.cylinder("Cap", (0, 2.25, -.02), .37, .12, "Denim", 12)
crew.box("CapBrim", (0, 2.22, -.37), (.48, .05, .28), "Denim")
crew.box("Backpack", (0, 1.17, .39), (.58, .72, .23), "Canvas")
crew.save()

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

cockpit = Obj("rv_cockpit")
cockpit.box("Dashboard", (0, -.47, -1.08), (2.25, .38, .58), "DarkMetal")
cockpit.box("DashTop", (0, -.27, -1.14), (2.28, .10, .70), "RV_Cream")
# Windshield pillars are provided by the exterior/chase view; omitting the
# chunky placeholders keeps the first-person road view open.
cockpit.torus("SteeringWheel", (.48, -.36, -.74), .34, .045, "Rubber", "z", 14, 6)
cockpit.cylinder("SteeringColumn", (.48, -.36, -.94), .055, .45, "LightMetal", 8, "z")
for x in (-.52, -.22, .08): cockpit.cylinder("Gauge", (x, -.40, -1.385), .09, .025, "Lamp", 10, "z")
cockpit.save()

sign = Obj("trail_sign")
sign.cylinder("Post", (0, 1.18, 0), .10, 2.36, "Wood", 9)
sign.box("SignBoard", (0, 2.18, 0), (1.65, .72, .14), "Wood")
sign.box("PaintMark", (0, 2.18, -.08), (1.30, .12, .025), "Lamp")
sign.save()

# Convert the simple authoring OBJ files to portable glTF 2.0 scenes. Godot's
# glTF importer is used for every target, avoiding platform-specific OBJ/MTL
# behavior while keeping the generated source geometry easy to inspect.
MATERIALS = {
    "RV_Cream": ((0.84, 0.79, 0.65, 1.0), "rv_cream.png", 0.90),
    "RV_Stripe": ((0.62, 0.25, 0.14, 1.0), "rv_stripe.png", 0.88),
    "Window": ((0.10, 0.20, 0.23, 0.72), None, 0.18),
    "DarkMetal": ((0.15, 0.16, 0.16, 1.0), None, 0.38),
    "LightMetal": ((0.48, 0.50, 0.48, 1.0), None, 0.30),
    "Lamp": ((1.00, 0.72, 0.22, 1.0), None, 0.45),
    "Rubber": ((0.035, 0.04, 0.045, 1.0), None, 0.98),
    "Wood": ((0.50, 0.30, 0.16, 1.0), "trail_wood.png", 0.92),
    "Pine": ((0.16, 0.33, 0.22, 1.0), "pine_needles.png", 0.95),
    "Stone": ((0.49, 0.30, 0.21, 1.0), "canyon_stone.png", 0.96),
    "CrewCloth": ((0.68, 0.30, 0.15, 1.0), "crew_fabric.png", 0.90),
    "Denim": ((0.15, 0.25, 0.34, 1.0), None, 0.92),
    "Skin": ((0.78, 0.54, 0.38, 1.0), None, 0.86),
    "Canvas": ((0.69, 0.60, 0.43, 1.0), None, 0.94),
    "Tool": ((0.26, 0.31, 0.32, 1.0), None, 0.28),
}


def convert_obj_to_gltf(source: Path) -> None:
    vertices: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    normals: list[tuple[float, float, float]] = []
    groups: dict[str, list[list[tuple[int, int, int]]]] = {}
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
        elif parts[0] == "usemtl":
            material = parts[1]
        elif parts[0] == "f":
            face = []
            for ref in parts[1:]:
                indices = ref.split("/")
                face.append((int(indices[0]) - 1, int(indices[1]) - 1, int(indices[2]) - 1))
            groups.setdefault(material, []).append(face)

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

    def add_accessor(view: int, component: int, count: int, kind: str, minimum=None, maximum=None) -> int:
        accessor = {"bufferView": view, "componentType": component, "count": count, "type": kind}
        if minimum is not None:
            accessor["min"] = minimum
            accessor["max"] = maximum
        accessors.append(accessor)
        return len(accessors) - 1

    used_materials = list(groups)
    material_defs = []
    images = []
    textures = []
    texture_lookup: dict[str, int] = {}
    for name in used_materials:
        color, texture_file, roughness = MATERIALS[name]
        pbr = {"baseColorFactor": list(color), "roughnessFactor": roughness, "metallicFactor": 0.0}
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
        if name == "Lamp":
            definition["emissiveFactor"] = [0.35, 0.18, 0.04]
        material_defs.append(definition)

    primitives = []
    for material_index, name in enumerate(used_materials):
        local_map: dict[tuple[int, int, int], int] = {}
        local_positions = []
        local_normals = []
        local_uvs = []
        local_indices = []
        for face in groups[name]:
            face_indices = []
            for ref in face:
                if ref not in local_map:
                    local_map[ref] = len(local_positions)
                    local_positions.append(vertices[ref[0]])
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
        mins = [min(value[axis] for value in local_positions) for axis in range(3)]
        maxs = [max(value[axis] for value in local_positions) for axis in range(3)]
        primitives.append({
            "attributes": {
                "POSITION": add_accessor(position_view, 5126, len(local_positions), "VEC3", mins, maxs),
                "NORMAL": add_accessor(normal_view, 5126, len(local_normals), "VEC3"),
                "TEXCOORD_0": add_accessor(uv_view, 5126, len(local_uvs), "VEC2"),
            },
            "indices": add_accessor(index_view, 5125, len(local_indices), "SCALAR"),
            "material": material_index,
            "mode": 4,
        })

    document = {
        "asset": {"version": "2.0", "generator": "Dustbound original low-poly asset generator"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": source.stem, "mesh": 0}],
        "meshes": [{"name": source.stem, "primitives": primitives}],
        "materials": material_defs,
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": images,
        "textures": textures,
        "buffers": [{"byteLength": len(blob), "uri": "data:application/octet-stream;base64," + base64.b64encode(blob).decode("ascii")}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }
    (MODEL_DIR / f"{source.stem}.gltf").write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")


for obj_path in sorted(MODEL_DIR.glob("*.obj")):
    convert_obj_to_gltf(obj_path)
    obj_path.unlink()
(MODEL_DIR / "dustbound.mtl").unlink(missing_ok=True)
print(f"Generated {len(list(MODEL_DIR.glob('*.gltf')))} glTF models and {len(list(TEXTURE_DIR.glob('*.png')))} textures.")
