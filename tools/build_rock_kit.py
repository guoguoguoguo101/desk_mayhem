# Modular wuxia cliff kit. First pass: ROCK_BASE_01..10 only.
# Z=0 is the visual ground contact. Mesh below Z=0 is the interlock plug.
# Run from the repo root:
#   D:\Blender\blender.exe --background --python tools/build_rock_kit.py

import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "environment", "rock_kit")
BLEND_PATH = os.path.join(OUT_DIR, "rock_kit_preview.blend")
PREVIEW_PATH = os.path.join(OUT_DIR, "rock_kit_preview.png")

BODY_A = 0
BODY_B = 1
CUT = 2
LEDGE = 3
UNDER = 4
PLUG = 5


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.curves,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.texts,
    ):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def stone_material(name, color, roughness):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True
    material.use_backface_culling = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def shade_flat(mesh):
    for polygon in mesh.polygons:
        polygon.use_smooth = False


def centroid(points):
    center = Vector((0.0, 0.0, 0.0))
    for point in points:
        center += point
    return center / len(points)


def ring_area(points):
    area = 0.0
    for index, point in enumerate(points):
        nxt = points[(index + 1) % len(points)]
        area += point.x * nxt.y - nxt.x * point.y
    return abs(area) * 0.5


def yaw_point(point, yaw):
    cosine = math.cos(yaw)
    sine = math.sin(yaw)
    return Vector((
        point.x * cosine - point.y * sine,
        point.x * sine + point.y * cosine,
        point.z,
    ))


def flatten_chord(points, start, end):
    count = len(points)
    span = (end - start) % count
    if span < 2:
        raise RuntimeError("fracture chord needs intermediate vertices")
    anchor_a = points[start]
    anchor_b = points[end]
    for step in range(1, span):
        index = (start + step) % count
        mix = step / float(span)
        points[index] = Vector((
            anchor_a.x + (anchor_b.x - anchor_a.x) * mix,
            anchor_a.y + (anchor_b.y - anchor_a.y) * mix,
            points[index].z,
        ))
    return points


def bulge_vertex(points, index, distance):
    center = centroid(points)
    direction = Vector((points[index].x - center.x, points[index].y - center.y, 0.0))
    if direction.length < 1e-6:
        return
    direction.normalize()
    points[index] = points[index] + direction * distance


def make_plan(angles_deg, radius, stretch, radial, fracture):
    points = []
    for index, degree in enumerate(angles_deg):
        angle = math.radians(degree)
        radius_here = radius * radial[index]
        points.append(Vector((
            math.cos(angle) * radius_here * stretch[0],
            math.sin(angle) * radius_here * stretch[1],
            0.0,
        )))
    ensure_convex(points)
    if fracture is not None:
        flatten_chord(points, fracture[0], fracture[1])
    return points


def fracture_ids(count, fracture):
    if fracture is None:
        return set()
    start, end = fracture
    span = (end - start) % count
    return {(start + step) % count for step in range(span + 1)}


def cut_edges(count, fracture):
    if fracture is None:
        return set()
    start, end = fracture
    span = (end - start) % count
    return {(start + step) % count for step in range(span)}


def ensure_convex(points):
    count = len(points)
    for _ in range(18):
        cx = sum(point.x for point in points) / count
        cy = sum(point.y for point in points) / count
        changed = False
        for index in range(count):
            prev = points[(index - 1) % count]
            curr = points[index]
            nxt = points[(index + 1) % count]
            cross = (curr.x - prev.x) * (nxt.y - curr.y) - (curr.y - prev.y) * (nxt.x - curr.x)
            if cross < 0.04:
                dx = curr.x - cx
                dy = curr.y - cy
                length = math.hypot(dx, dy) or 1.0
                points[index] = Vector((curr.x + dx / length * 0.18, curr.y + dy / length * 0.18, curr.z))
                changed = True
        if not changed:
            break
    return points


def crack_face(points, fracture, depth):
    if fracture is None or depth <= 0.0:
        return
    start, end = fracture
    count = len(points)
    span = (end - start) % count
    index = (start + max(1, span // 2)) % count
    center = centroid(points)
    direction = Vector((center.x - points[index].x, center.y - points[index].y, 0.0))
    if direction.length < 1e-6:
        return
    direction.normalize()
    points[index] = points[index] + direction * depth


def course_ring(plan, scale, offset, fracture, fixed_face, anchor, bulge, vertex_scale=None, crack=0.0, twist=0.0):
    points = []
    locked = fracture_ids(len(plan), fracture) if fixed_face else set()
    ox, oy = offset
    for index, point in enumerate(plan):
        if index in locked:
            placed = Vector((point.x, point.y, 0.0))
        else:
            mul = scale if vertex_scale is None else scale * vertex_scale[index]
            placed = Vector((
                anchor.x + (point.x - anchor.x) * mul + ox,
                anchor.y + (point.y - anchor.y) * mul + oy,
                0.0,
            ))
        points.append(placed)
    if bulge is not None and bulge[0] not in locked:
        bulge_vertex(points, bulge[0], bulge[1])
    if not fixed_face:
        ensure_convex(points)
        if fracture is not None:
            flatten_chord(points, fracture[0], fracture[1])
            crack_face(points, fracture, crack)
    if twist:
        points = [yaw_point(point, twist) for point in points]
    return points


def same_point(vert, point):
    return (vert.co - point).length < 1e-4


def loft(name, rings, span_mats, materials, collection, top_mat):
    count = len(rings[0].points)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    vert_rings = []
    for ring_index, ring in enumerate(rings):
        if len(ring.points) != count:
            raise RuntimeError("%s ring vertex counts differ" % name)
        row = []
        for index, point in enumerate(ring.points):
            reused = None
            if ring_index > 0 and same_point(vert_rings[ring_index - 1][index], point):
                reused = vert_rings[ring_index - 1][index]
            row.append(reused if reused is not None else bm.verts.new(point))
        vert_rings.append(row)
    bottom_center = bm.verts.new(centroid(rings[0].points))
    top_center = bm.verts.new(centroid(rings[-1].points))
    bm.verts.ensure_lookup_table()

    def add_face(verts, material_index):
        ordered = []
        seen = set()
        for vert in verts:
            marker = id(vert)
            if marker in seen:
                continue
            seen.add(marker)
            ordered.append(vert)
        if len(ordered) < 3:
            return
        face = bm.faces.new(tuple(ordered))
        face.material_index = material_index
        for loop in face.loops:
            co = loop.vert.co
            loop[uv_layer].uv = ((math.atan2(co.y, co.x) / math.tau) % 1.0, (co.z + 2.0) * 0.16)

    for index in range(count):
        nxt = (index + 1) % count
        add_face((bottom_center, vert_rings[0][nxt], vert_rings[0][index]), PLUG)
    for span, ring_mats in enumerate(span_mats):
        for index in range(count):
            nxt = (index + 1) % count
            add_face((
                vert_rings[span][index],
                vert_rings[span][nxt],
                vert_rings[span + 1][nxt],
                vert_rings[span + 1][index],
            ), ring_mats[index])
    for index in range(count):
        nxt = (index + 1) % count
        add_face((top_center, vert_rings[-1][index], vert_rings[-1][nxt]), top_mat)

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bm.calc_volume() < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    shade_flat(mesh)
    for material in materials:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj["origin"] = "visual_base_z0"
    obj["plug"] = "mesh below local Z=0 sinks into the next rock"
    obj["kit_id"] = name.lower()
    zs = [vertex.co.z for vertex in mesh.vertices]
    top = max(zs) if zs else 0.0
    obj["top"] = float(top)
    obj["plug_depth"] = float(-min(min(zs), 0.0)) if zs else 0.0
    tips = [vertex.co for vertex in mesh.vertices if vertex.co.z > top - 0.25]
    if tips:
        obj["tip_x"] = float(sum(point.x for point in tips) / len(tips))
        obj["tip_y"] = float(sum(point.y for point in tips) / len(tips))
        obj["tip_z"] = float(sum(point.z for point in tips) / len(tips))
    return obj


class Ring(object):
    def __init__(self, points, slab, role):
        self.points = points
        self.slab = slab
        self.role = role


def span_materials(rings, cuts):
    spans = []
    for lower, upper in zip(rings, rings[1:]):
        expanding = ring_area(upper.points) > ring_area(lower.points) * 1.08
        row = []
        for edge in range(len(lower.points)):
            if lower.role == "plug":
                row.append(PLUG)
            elif lower.slab != upper.slab:
                row.append(UNDER if expanding else LEDGE)
            elif edge in cuts:
                row.append(CUT)
            else:
                row.append(BODY_A if lower.slab % 2 == 0 else BODY_B)
        spans.append(row)
    return spans


def stack_rock(name, angles, radius, stretch, radial, fracture, courses, plugs, materials, collection, top_mat, yaw, fixed_face=False):
    plan = make_plan(angles, radius, stretch, radial, fracture)
    anchor = centroid([plan[index] for index in fracture_ids(len(plan), fracture)]) if fixed_face else Vector((0.0, 0.0, 0.0))
    rings = []
    slab_id = 0
    for z0, z1, scale, offset in plugs:
        shape = course_ring(plan, scale, offset, fracture, fixed_face, anchor, None)
        rings.append(Ring([Vector((point.x, point.y, z0)) for point in shape], slab_id, "plug"))
        rings.append(Ring([Vector((point.x, point.y, z1)) for point in shape], slab_id, "plug"))
        slab_id += 1
    for course in courses:
        shape = course_ring(
            plan,
            course["s"],
            (course.get("ox", 0.0), course.get("oy", 0.0)),
            fracture,
            fixed_face,
            anchor,
            course.get("bulge"),
            vertex_scale=side_scales(len(plan), fracture, course),
            crack=course.get("crack", 0.0),
            twist=course.get("twist", 0.0),
        )
        rings.append(Ring([Vector((point.x, point.y, course["z0"])) for point in shape], slab_id, "body"))
        rings.append(Ring([Vector((point.x, point.y, course["z1"])) for point in shape], slab_id, "body"))
        slab_id += 1
    for ring in rings:
        ring.points = [yaw_point(point, yaw) for point in ring.points]
    return loft(name, rings, span_materials(rings, cut_edges(len(angles), fracture)), materials, collection, top_mat)


def courses_from(specs):
    z = 0.0
    courses = []
    for spec in specs:
        height = spec["h"]
        course = dict(spec)
        course["z0"] = z
        course["z1"] = z + height
        courses.append(course)
        z += height
    return courses


def standard_plug(scale):
    return [(-1.05, -0.48, scale * 0.62, (0.0, 0.0)), (-0.48, -0.02, scale * 0.78, (0.0, 0.0))]


def wall_angles():
    return [0, 22, 46, 72, 104, 146, 184, 224, 268, 318]


def pillar_angles():
    return [0, 14, 30, 48, 74, 118, 160, 206, 250, 292, 332]


def chunk_angles():
    return [0, 28, 58, 96, 142, 188, 232, 286, 338]


def radial_row(count, seed):
    pattern = [1.0, 0.74, 1.08, 0.68, 1.14, 0.8, 0.96, 0.66, 1.06, 0.72, 0.9]
    row = [pattern[(index + seed) % len(pattern)] for index in range(count)]
    return row


def side_scales(count, fracture, course):
    rng = random.Random(course.get("seed", 1))
    locked = fracture_ids(count, fracture)
    front = course.get("front", 0.96)
    back_lo = course.get("lo", 0.58)
    back_hi = course.get("hi", 0.92)
    scales = []
    for index in range(count):
        if index in locked:
            scales.append(rng.uniform(front * 0.9, front))
        else:
            scales.append(rng.uniform(back_lo, back_hi))
    return scales


def facing_yaw(angles, fracture, extra_deg):
    start = angles[fracture[0]]
    end = angles[fracture[1]]
    if end < start:
        end += 360.0
    bisector = (start + end) * 0.5
    return math.radians(-42.0 - bisector + extra_deg)


def make_rocks(collection, materials):
    rocks = []
    wall = wall_angles()
    pillar = pillar_angles()
    chunk = chunk_angles()

    rocks.append(stack_rock(
        "ROCK_BASE_01", wall, 4.35, (1.16, 0.86), radial_row(len(wall), 0), (0, 4),
        courses_from([
            {"h": 1.45, "s": 1.0, "ox": 0.0, "oy": 0.0, "seed": 11, "front": 1.0, "lo": 0.7, "hi": 1.08, "crack": 0.7, "bulge": (6, 0.85)},
            {"h": 1.2, "s": 0.9, "ox": 0.85, "oy": 0.4, "seed": 12, "front": 0.94, "lo": 0.46, "hi": 0.86, "crack": 0.5, "twist": 0.1, "bulge": (7, 0.6)},
            {"h": 1.35, "s": 0.74, "ox": -0.55, "oy": 0.95, "seed": 13, "front": 0.9, "lo": 0.38, "hi": 0.78, "crack": 0.4, "twist": -0.12},
            {"h": 1.05, "s": 0.58, "ox": 0.4, "oy": 0.3, "seed": 14, "front": 0.86, "lo": 0.34, "hi": 0.7, "crack": 0.3, "twist": 0.08, "bulge": (5, 0.45)},
        ]),
        standard_plug(1.0), materials, collection, BODY_B, facing_yaw(wall, (0, 4), -8),
    ))

    rocks.append(stack_rock(
        "ROCK_BASE_02", pillar, 1.72, (1.0, 0.9), radial_row(len(pillar), 2), (0, 4),
        courses_from([
            {"h": 2.15, "s": 1.0, "ox": 0.0, "oy": 0.0, "seed": 21, "front": 1.0, "lo": 0.52, "hi": 0.95, "crack": 0.32, "bulge": (6, 0.4)},
            {"h": 1.9, "s": 0.84, "ox": 0.28, "oy": -0.18, "seed": 22, "front": 0.94, "lo": 0.4, "hi": 0.82, "crack": 0.26, "twist": 0.12},
            {"h": 2.05, "s": 0.68, "ox": 0.15, "oy": 0.32, "seed": 23, "front": 0.9, "lo": 0.34, "hi": 0.75, "crack": 0.22, "twist": -0.1, "bulge": (8, 0.28)},
            {"h": 1.8, "s": 0.52, "ox": 0.42, "oy": -0.12, "seed": 24, "front": 0.86, "lo": 0.3, "hi": 0.66, "crack": 0.16, "twist": 0.14},
            {"h": 1.7, "s": 0.38, "ox": 0.2, "oy": 0.18, "seed": 25, "front": 0.82, "lo": 0.28, "hi": 0.58, "crack": 0.12, "twist": -0.08},
            {"h": 1.45, "s": 0.26, "ox": 0.35, "oy": -0.05, "seed": 26, "front": 0.78, "lo": 0.26, "hi": 0.5, "crack": 0.08, "twist": 0.16},
        ]),
        [(-1.7, -0.7, 0.58, (0.0, 0.0)), (-0.7, -0.02, 0.74, (0.0, 0.0))],
        materials, collection, BODY_A, facing_yaw(pillar, (0, 4), 8),
    ))

    rocks.append(stack_rock(
        "ROCK_BASE_03", pillar, 2.2, (1.05, 0.88), radial_row(len(pillar), 4), (0, 4),
        courses_from([
            {"h": 1.7, "s": 1.0, "ox": 0.0, "oy": 0.05, "seed": 31, "front": 1.0, "lo": 0.58, "hi": 1.0, "crack": 0.35, "bulge": (6, 0.4)},
            {"h": 1.5, "s": 0.8, "ox": 0.35, "oy": -0.22, "seed": 32, "front": 0.92, "lo": 0.42, "hi": 0.8, "crack": 0.28, "twist": 0.1},
            {"h": 1.35, "s": 0.62, "ox": -0.2, "oy": 0.28, "seed": 33, "front": 0.88, "lo": 0.36, "hi": 0.7, "crack": 0.2, "twist": -0.12, "bulge": (7, 0.3)},
            {"h": 1.15, "s": 0.48, "ox": 0.12, "oy": 0.08, "seed": 34, "front": 0.84, "lo": 0.32, "hi": 0.6, "crack": 0.14, "twist": 0.08},
            {"h": 0.28, "s": 0.66, "ox": 0.05, "oy": 0.02, "seed": 35, "front": 1.02, "lo": 0.7, "hi": 1.05, "crack": 0.08, "twist": -0.04},
            {"h": 0.7, "s": 0.6, "ox": 0.0, "oy": 0.0, "seed": 36, "front": 0.98, "lo": 0.72, "hi": 1.0, "crack": 0.05},
        ]),
        standard_plug(1.0), materials, collection, CUT, facing_yaw(pillar, (0, 4), -14),
    ))

    rocks.append(stack_rock(
        "ROCK_BASE_04", wall, 3.9, (1.28, 0.62), radial_row(len(wall), 1), (0, 4),
        courses_from([
            {"h": 1.7, "s": 1.0, "ox": 0.0, "oy": 0.0, "seed": 41, "front": 1.0, "lo": 0.42, "hi": 0.72, "crack": 0.85, "bulge": (6, 0.7)},
            {"h": 1.55, "s": 0.96, "ox": 0.2, "oy": 0.15, "seed": 42, "front": 0.98, "lo": 0.28, "hi": 0.55, "crack": 0.65, "twist": 0.05},
            {"h": 1.65, "s": 0.92, "ox": -0.25, "oy": 0.1, "seed": 43, "front": 0.97, "lo": 0.22, "hi": 0.48, "crack": 0.5, "twist": -0.06, "bulge": (7, 0.55)},
            {"h": 1.4, "s": 0.88, "ox": 0.15, "oy": -0.2, "seed": 44, "front": 0.95, "lo": 0.18, "hi": 0.4, "crack": 0.35, "twist": 0.07},
        ]),
        standard_plug(1.0), materials, collection, BODY_B, facing_yaw(wall, (0, 4), 0),
    ))

    rocks.append(stack_rock(
        "ROCK_BASE_05", chunk, 3.55, (1.12, 0.92), radial_row(len(chunk), 3), (0, 3),
        courses_from([
            {"h": 1.55, "s": 1.0, "ox": 0.0, "oy": 0.0, "seed": 51, "front": 1.0, "lo": 0.68, "hi": 1.05, "crack": 0.45, "bulge": (5, 0.55)},
            {"h": 1.4, "s": 0.78, "ox": 0.45, "oy": 1.05, "seed": 52, "front": 0.92, "lo": 0.48, "hi": 0.88, "crack": 0.32, "twist": 0.08, "bulge": (6, 0.35)},
            {"h": 1.45, "s": 0.56, "ox": -0.25, "oy": 1.85, "seed": 53, "front": 0.88, "lo": 0.4, "hi": 0.78, "crack": 0.22, "twist": -0.1},
            {"h": 1.2, "s": 0.4, "ox": 0.3, "oy": 2.35, "seed": 54, "front": 0.84, "lo": 0.36, "hi": 0.7, "crack": 0.14, "twist": 0.06, "bulge": (4, 0.25)},
        ]),
        standard_plug(1.0), materials, collection, CUT, facing_yaw(chunk, (0, 3), 12),
    ))

    rocks.append(stack_rock(
        "ROCK_BASE_06", wall, 2.15, (1.18, 0.78), radial_row(len(wall), 5), (0, 4),
        courses_from([
            {"h": 1.55, "s": 0.62, "ox": 0.0, "oy": 0.0, "seed": 61, "front": 0.95, "lo": 0.6, "hi": 0.95, "crack": 0.25},
            {"h": 1.25, "s": 0.7, "ox": 0.3, "oy": -0.25, "seed": 62, "front": 0.96, "lo": 0.5, "hi": 0.9, "crack": 0.3, "twist": 0.06, "bulge": (6, 0.35)},
            {"h": 1.7, "s": 1.2, "ox": 1.55, "oy": -1.25, "seed": 63, "front": 1.05, "lo": 0.72, "hi": 1.12, "crack": 0.4, "twist": -0.05, "bulge": (7, 0.5)},
            {"h": 1.2, "s": 1.02, "ox": 1.85, "oy": -1.45, "seed": 64, "front": 0.9, "lo": 0.48, "hi": 0.85, "crack": 0.22, "twist": 0.08},
        ]),
        [(-1.15, -0.5, 0.5, (0.0, 0.0)), (-0.5, -0.02, 0.6, (0.0, 0.0))],
        materials, collection, CUT, facing_yaw(wall, (0, 4), 16),
    ))

    rocks.append(stack_rock(
        "ROCK_BASE_07", wall, 3.7, (1.22, 0.84), radial_row(len(wall), 2), (0, 4),
        courses_from([
            {"h": 1.2, "s": 1.0, "ox": 0.0, "oy": 0.0, "seed": 71, "front": 1.0, "lo": 0.72, "hi": 1.08, "crack": 0.5, "bulge": (6, 0.65)},
            {"h": 1.0, "s": 0.9, "ox": 0.45, "oy": 0.25, "seed": 72, "front": 0.96, "lo": 0.55, "hi": 0.95, "crack": 0.35, "twist": 0.07},
            {"h": 0.85, "s": 0.86, "ox": -0.2, "oy": 0.15, "seed": 73, "front": 0.98, "lo": 0.62, "hi": 1.0, "crack": 0.18, "bulge": (7, 0.4)},
        ]),
        [(-0.85, -0.4, 0.7, (0.0, 0.0)), (-0.4, -0.02, 0.82, (0.0, 0.0))],
        materials, collection, CUT, facing_yaw(wall, (0, 4), -6),
    ))

    rubble_parts = []
    rubble_specs = [
        ((0.0, 0.15), 0.78, 1.2, 0.2, chunk_angles(), (0, 3)),
        ((1.25, -0.55), 0.92, 1.55, -0.35, wall_angles(), (0, 4)),
        ((-1.05, -0.65), 0.58, 0.85, 0.55, chunk_angles(), (0, 3)),
    ]
    for (ox, oy), radius, height, lean, angles, fracture in rubble_specs:
        plan = make_plan(angles, radius, (1.0, 0.9), radial_row(len(angles), 1), fracture)
        yaw = facing_yaw(angles, fracture, lean * 40.0)
        bands = [
            (-0.38, -0.16, 0.6, (0.0, 0.0)),
            (-0.16, -0.02, 0.75, (0.0, 0.0)),
            (0.0, height * 0.42, 1.0, (lean * 0.05, 0.02)),
            (height * 0.42, height * 0.75, 0.82, (lean * 0.1, -0.02)),
            (height * 0.75, height, 0.58, (lean * 0.14, 0.0)),
        ]
        stone_rings = []
        for slab, (z0, z1, scale, offset) in enumerate(bands):
            role = "plug" if z1 <= 0.0 else "body"
            course = {"seed": 80 + slab, "front": 0.96, "lo": 0.45, "hi": 0.9}
            shape = course_ring(
                plan, scale, offset, fracture, False, Vector((0.0, 0.0, 0.0)), None,
                vertex_scale=None if role == "plug" else side_scales(len(plan), fracture, course),
                crack=0.0 if role == "plug" else 0.12,
                twist=0.0 if role == "plug" else lean * 0.2,
            )
            moved = [yaw_point(point, yaw) + Vector((ox, oy, 0.0)) for point in shape]
            stone_rings.append(Ring([Vector((point.x, point.y, z0)) for point in moved], slab, role))
            stone_rings.append(Ring([Vector((point.x, point.y, z1)) for point in moved], slab, role))
        rubble_parts.append(loft(
            "ROCK_BASE_08_PART",
            stone_rings,
            span_materials(stone_rings, cut_edges(len(angles), fracture)),
            materials,
            collection,
            BODY_A,
        ))
    rocks.append(join_objects("ROCK_BASE_08", rubble_parts, collection))

    rocks.append(stack_rock(
        "ROCK_BASE_09", pillar, 1.85, (1.0, 0.88), radial_row(len(pillar), 6), (0, 4),
        courses_from([
            {"h": 1.9, "s": 1.0, "ox": 0.0, "oy": 0.0, "seed": 91, "front": 1.0, "lo": 0.5, "hi": 0.95, "crack": 0.3, "bulge": (6, 0.3)},
            {"h": 1.75, "s": 0.72, "ox": 0.22, "oy": -0.16, "seed": 92, "front": 0.9, "lo": 0.38, "hi": 0.75, "crack": 0.22, "twist": 0.12},
            {"h": 1.6, "s": 0.5, "ox": -0.12, "oy": 0.2, "seed": 93, "front": 0.84, "lo": 0.3, "hi": 0.62, "crack": 0.16, "twist": -0.1, "bulge": (8, 0.18)},
            {"h": 1.4, "s": 0.32, "ox": 0.16, "oy": 0.05, "seed": 94, "front": 0.8, "lo": 0.26, "hi": 0.5, "crack": 0.1, "twist": 0.14},
            {"h": 1.15, "s": 0.18, "ox": 0.05, "oy": -0.04, "seed": 95, "front": 0.75, "lo": 0.24, "hi": 0.42, "crack": 0.06, "twist": -0.08},
        ]),
        [(-1.35, -0.55, 0.58, (0.0, 0.0)), (-0.55, -0.02, 0.74, (0.0, 0.0))],
        materials, collection, BODY_B, facing_yaw(pillar, (0, 4), 4),
    ))

    rocks.append(build_ridge(collection, materials))
    return rocks


def join_objects(name, objects, collection):
    bm = bmesh.new()
    for obj in objects:
        bm.from_mesh(obj.data)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    shade_flat(mesh)
    for material in objects[0].data.materials:
        mesh.materials.append(material)
    for obj in objects:
        mesh_data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh_data.users == 0:
            bpy.data.meshes.remove(mesh_data)
    joined = bpy.data.objects.new(name, mesh)
    collection.objects.link(joined)
    joined["origin"] = "visual_base_z0"
    joined["plug"] = "mesh below local Z=0 sinks into the next rock"
    joined["kit_id"] = name.lower()
    zs = [vertex.co.z for vertex in mesh.vertices]
    top = max(zs) if zs else 0.0
    joined["top"] = float(top)
    joined["plug_depth"] = float(-min(min(zs), 0.0)) if zs else 0.0
    tips = [vertex.co for vertex in mesh.vertices if vertex.co.z > top - 0.25]
    if tips:
        joined["tip_x"] = float(sum(point.x for point in tips) / len(tips))
        joined["tip_y"] = float(sum(point.y for point in tips) / len(tips))
        joined["tip_z"] = float(sum(point.z for point in tips) / len(tips))
    return joined


def build_ridge(collection, materials):
    stations = [
        (-7.8, 2.3, 1.15, 0.0, 0.95),
        (-6.2, 4.2, 1.8, 0.22, 0.0),
        (-4.6, 3.5, 1.6, -0.28, 0.0),
        (-3.1, 4.8, 1.95, 0.16, 0.0),
        (-1.5, 3.7, 1.65, -0.3, 0.0),
        (0.1, 5.0, 2.05, 0.2, 0.0),
        (1.7, 3.6, 1.6, -0.18, 0.0),
        (3.2, 4.9, 1.9, 0.32, 0.0),
        (4.7, 3.8, 1.6, -0.22, 0.0),
        (6.2, 4.3, 1.75, 0.12, 0.0),
        (7.7, 2.35, 1.15, 0.0, 0.95),
    ]
    rings = []
    for index, (x, height, half_w, y_shift, plug) in enumerate(stations):
        crest = y_shift + (-0.28 if index % 2 else 0.2)
        points = [
            Vector((x, y_shift - half_w * 0.2, -plug)),
            Vector((x, y_shift + half_w * 0.9, -plug * 0.25)),
            Vector((x, y_shift + half_w * 0.72, height * 0.28)),
            Vector((x, y_shift + half_w * 0.4, height * 0.78)),
            Vector((x, crest, height)),
            Vector((x, y_shift - half_w * 0.24, height * 0.8)),
            Vector((x, y_shift - half_w * 0.88, height * 0.22)),
            Vector((x, y_shift - half_w * 0.55, 0.0)),
        ]
        rings.append(Ring(points, index, "body"))
    cuts = {2, 3}
    spans = []
    for index, (lower, upper) in enumerate(zip(rings, rings[1:])):
        dropped = abs(stations[index][1] - stations[index + 1][1]) > 0.9
        row = []
        for edge in range(len(lower.points)):
            quad_z = min(
                lower.points[edge].z,
                lower.points[(edge + 1) % len(lower.points)].z,
                upper.points[edge].z,
                upper.points[(edge + 1) % len(upper.points)].z,
            )
            if quad_z < -0.04:
                row.append(PLUG)
            elif edge in cuts:
                row.append(CUT)
            elif dropped and edge in (3, 4, 5):
                row.append(BODY_B)
            else:
                row.append(BODY_A)
        spans.append(row)
    return loft("ROCK_BASE_10", rings, spans, materials, collection, BODY_A)


def local_bounds(obj):
    xs, ys, zs = [], [], []
    for corner in obj.bound_box:
        point = Vector(corner)
        xs.append(point.x)
        ys.append(point.y)
        zs.append(point.z)
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


def link_only(obj, collection):
    for parent in list(obj.users_collection):
        parent.objects.unlink(obj)
    collection.objects.link(obj)


def add_label(collection, text, location, material):
    curve = bpy.data.curves.new("Label_%s" % text, "FONT")
    curve.body = text
    curve.align_x = "CENTER"
    curve.size = 0.62
    curve.extrude = 0.03
    obj = bpy.data.objects.new("LABEL_%s" % text, curve)
    obj.location = location
    obj.rotation_euler = (math.radians(68), 0.0, 0.0)
    obj.data.materials.append(material)
    collection.objects.link(obj)
    return obj


def arrange(rocks, label_collection, label_material):
    gap = 4.2
    columns = 5
    cursor_x = 0.0
    cursor_y = 0.0
    row_depth = 0.0
    for index, obj in enumerate(rocks):
        if index > 0 and index % columns == 0:
            cursor_y -= row_depth + gap + 3.4
            cursor_x = 0.0
            row_depth = 0.0
        minx, maxx, miny, maxy, _, _ = local_bounds(obj)
        obj.location = (cursor_x - minx, cursor_y - (miny + maxy) * 0.5, 0.0)
        cursor_x += (maxx - minx) + gap
        row_depth = max(row_depth, maxy - miny)
        add_label(
            label_collection,
            obj.name,
            (obj.location.x + (minx + maxx) * 0.5, obj.location.y + miny - 2.1, 0.05),
            label_material,
        )
    return rocks


def add_scale_figure(collection, label_collection, label_material):
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.22, depth=1.05, location=(0.0, 0.0, 0.78))
    body = bpy.context.object
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=8, radius=0.18, location=(0.0, 0.0, 1.48))
    head = bpy.context.object
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    head.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    figure = bpy.context.object
    figure.name = "SCALE_1P8"
    material = bpy.data.materials.new("ScaleMarker")
    material.diffuse_color = (0.12, 0.12, 0.13, 1.0)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.12, 0.12, 0.13, 1.0)
    figure.data.materials.append(material)
    link_only(figure, collection)
    add_label(label_collection, "1.8m", (0.0, -0.7, 0.15), label_material)
    return figure


def add_ground(collection, bounds_min, bounds_max):
    width = (bounds_max.x - bounds_min.x) + 10.0
    depth = (bounds_max.y - bounds_min.y) + 10.0
    bpy.ops.mesh.primitive_grid_add(
        x_subdivisions=max(8, int(width / 2)),
        y_subdivisions=max(6, int(depth / 2)),
        size=1.0,
        location=((bounds_min.x + bounds_max.x) * 0.5, (bounds_min.y + bounds_max.y) * 0.5, -0.01),
    )
    grid = bpy.context.object
    grid.name = "GROUND_Z0"
    grid.scale = (width, depth, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    wire = grid.modifiers.new("Wire", "WIREFRAME")
    wire.thickness = 0.015
    wire.use_replace = True
    wire.use_boundary = True
    material = bpy.data.materials.new("GroundGrid")
    material.diffuse_color = (0.55, 0.58, 0.6, 1.0)
    grid.data.materials.append(material)
    link_only(grid, collection)
    return grid


def world_bounds(objects):
    low = Vector((1e9, 1e9, 1e9))
    high = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            low.x = min(low.x, point.x)
            low.y = min(low.y, point.y)
            low.z = min(low.z, point.z)
            high.x = max(high.x, point.x)
            high.y = max(high.y, point.y)
            high.z = max(high.z, point.z)
    return low, high


def aim_camera(camera, location, target):
    camera.location = location
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def validate(rocks):
    print("ROCK_KIT_REPORT")
    for obj in rocks:
        mesh = obj.data
        minx, maxx, miny, maxy, minz, maxz = local_bounds(obj)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        nonmanifold = sum(1 for edge in bm.edges if not edge.is_manifold)
        volume = bm.calc_volume()
        bm.free()
        print(
            "%s verts=%d faces=%d size=%.1f x %.1f x %.1f plug=%.2f nonmanifold=%d volume=%.1f"
            % (
                obj.name,
                len(mesh.vertices),
                len(mesh.polygons),
                maxx - minx,
                maxy - miny,
                maxz - minz,
                -minz,
                nonmanifold,
                volume,
            )
        )
        if minz >= -0.2:
            raise RuntimeError("%s has no interlock plug" % obj.name)
        if nonmanifold:
            raise RuntimeError("%s is not a closed mesh" % obj.name)
        if volume <= 0:
            raise RuntimeError("%s has no positive volume" % obj.name)
        if obj.name not in ("ROCK_BASE_06", "ROCK_BASE_07", "ROCK_BASE_10"):
            top = [vertex.co for vertex in mesh.vertices if vertex.co.z > maxz - 0.35]
            seat = [vertex.co for vertex in mesh.vertices if -0.05 <= vertex.co.z <= 0.05]
            if top and seat:
                top_span = max(
                    max(point.x for point in top) - min(point.x for point in top),
                    max(point.y for point in top) - min(point.y for point in top),
                )
                seat_span = max(
                    max(point.x for point in seat) - min(point.x for point in seat),
                    max(point.y for point in seat) - min(point.y for point in seat),
                )
                if top_span > seat_span * 1.08:
                    print("WARN %s top is wider than its seat (%.2f > %.2f)" % (obj.name, top_span, seat_span))


def render_still(scene, camera, path, location, target):
    aim_camera(camera, location, target)
    scene.camera = camera
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED %s" % path)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    reset_scene()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    materials = [
        stone_material("RockBodyA", (0.47, 0.49, 0.45), 0.94),
        stone_material("RockBodyB", (0.30, 0.32, 0.29), 0.96),
        stone_material("RockCut", (0.78, 0.66, 0.46), 0.74),
        stone_material("RockLedge", (0.40, 0.48, 0.34), 0.9),
        stone_material("RockUnder", (0.18, 0.16, 0.15), 0.97),
        stone_material("RockPlug", (0.36, 0.2, 0.12), 0.95),
    ]
    modules = bpy.data.collections.new("Modules")
    labels = bpy.data.collections.new("Labels")
    guides = bpy.data.collections.new("Guides")
    for item in (modules, labels, guides):
        scene.collection.children.link(item)

    label_material = stone_material("LabelInk", (0.1, 0.1, 0.11), 0.8)
    figure = add_scale_figure(guides, labels, label_material)
    rocks = make_rocks(modules, materials)
    arrange(rocks, labels, label_material)
    minx, _, miny, _, _, _ = local_bounds(rocks[0])
    figure.location = (rocks[0].location.x + minx - 1.6, rocks[0].location.y, 0.0)
    for obj in labels.objects:
        if obj.name == "LABEL_1.8m":
            obj.location = (figure.location.x, figure.location.y + miny - 0.85, 0.15)

    notes = bpy.data.texts.new("KIT_NOTES")
    notes.write(
        "ROCK_BASE_01..10 预览。\n"
        "Z=0 是视觉着地点。Z<0 的深色部分是穿插榫，用来嵌进另一块岩体。\n"
        "浅色立面是断裂切面，暗绿横面是岩层台面，深色横面是悬挑底面。\n"
        "先确认这 10 个基础件，再做植被和组合山峰。\n"
    )

    bpy.context.view_layer.update()
    low, high = world_bounds(list(rocks) + [figure])
    print("BOUNDS %s %s" % (tuple(round(v, 1) for v in low), tuple(round(v, 1) for v in high)))
    add_ground(guides, low, high)

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.lens = 48
    camera.data.clip_end = 800
    bpy.ops.object.light_add(type="SUN")
    sun = bpy.context.object
    sun.rotation_euler = (math.radians(58), math.radians(6), math.radians(-42))
    sun.data.energy = 2.6
    sun.data.angle = math.radians(8)
    bpy.ops.object.light_add(type="AREA", location=((low.x + high.x) * 0.5, low.y - 8.0, high.z * 0.6))
    fill = bpy.context.object
    fill.data.energy = 120
    fill.data.size = 24

    validate(rocks)
    center = (low + high) * 0.5
    span = max(high.x - low.x, high.y - low.y, 1.0)
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 1400
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = -0.35
    scene.world.color = (0.63, 0.68, 0.72)
    if scene.world.use_nodes:
        background = scene.world.node_tree.nodes.get("Background")
        if background:
            background.inputs[0].default_value = (0.58, 0.62, 0.66, 1.0)
            background.inputs[1].default_value = 0.9
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        try:
            scene.render.engine = "BLENDER_EEVEE"
        except TypeError:
            scene.render.engine = "BLENDER_WORKBENCH"
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = 32

    camera.data.type = "ORTHO"
    camera.data.sensor_fit = "HORIZONTAL"
    camera.data.ortho_scale = max(high.x - low.x, (high.y - low.y) * 1.78, (high.z - low.z) * 2.2) * 1.18
    print("ORTHO %.1f" % camera.data.ortho_scale)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    render_still(
        scene,
        camera,
        PREVIEW_PATH,
        center + Vector((0.62, -1.0, 0.34)).normalized() * (span + 48.0),
        Vector((center.x, center.y, max(high.z * 0.16, 1.0))),
    )
    print("ROCK_KIT_PREVIEW %s" % BLEND_PATH)


if __name__ == "__main__":
    main()
