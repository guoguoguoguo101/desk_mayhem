# Regenerates the modular wuxia arena floor. Run from the repo root:
#   D:\Blender\blender.exe --background --python scripts/blender/generate_arena_floor.py
#
# Ring pivots stay at the arena center so Godot can spin a segment by n * 45 degrees.
# Square modules use a pivot at the center of the bottom face.
# Radii follow the reference sheet scaled onto a 12 m circle. The medallion is
# larger than a strict 3 m guess because that is how the reference is drawn.

import array
import bmesh
import bpy
import importlib.util
import math
import os
from mathutils import Vector

ARENA_DIAMETER = 12.0
CENTER_RADIUS = 2.12
INNER_RING_RADIUS = 2.86
MIDDLE_RING_RADIUS = 3.72
OUTER_RING_RADIUS = 4.46
SEGMENT_COUNT = 8
FLOOR_HEIGHT = 0.18
RELIEF_HEIGHT = 0.032
SLAB_HEIGHT = 0.15
GOLD_HEIGHT = 0.016
SEG_ANGLE = math.tau / SEGMENT_COUNT
ARENA_RADIUS = ARENA_DIAMETER * 0.5
ANG_STEPS = 6

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "environment", "arena_floor")
TEX_DIR = os.path.join(OUT_DIR, "textures")

MAT_LIGHT = 0
MAT_DARK = 1
MAT_GOLD = 2


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.collections):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def hash2(ix, iy):
    n = (int(ix) * 374761393 + int(iy) * 668265263) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return (n & 0xFFFFFF) / float(0xFFFFFF)


def load_texture(name):
    path = os.path.join(TEX_DIR, name + ".png")
    image = bpy.data.images.load(path)
    image.colorspace_settings.name = "sRGB"
    return image


def make_image(name, base, amount, cracks):
    size = 256
    image = bpy.data.images.new(name, size, size, alpha=False)
    image.colorspace_settings.name = "sRGB"
    buf = array.array("f", [0.0]) * (size * size * 4)
    for y in range(size):
        for x in range(size):
            n = hash2(x // 3, y // 3) * 0.65 + hash2(x, y) * 0.35
            grain = (n - 0.5) * amount
            color = [max(0.0, min(1.0, channel + grain)) for channel in base]
            if cracks:
                line = abs(math.sin(x * 0.41 + y * 0.17) * math.sin(y * 0.23 - x * 0.11))
                if line > 0.965:
                    color = [channel * 0.62 for channel in color]
            i = (y * size + x) * 4
            buf[i] = color[0]
            buf[i + 1] = color[1]
            buf[i + 2] = color[2]
            buf[i + 3] = 1.0
    image.pixels.foreach_set(buf)
    os.makedirs(TEX_DIR, exist_ok=True)
    image.filepath_raw = os.path.join(TEX_DIR, name + ".png")
    image.file_format = "PNG"
    image.save()
    return image


def make_material(name, image, roughness, metallic):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (1, 1, 1, 1)
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Smart"
    tex.extension = "REPEAT"
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return material


def new_collection(parent, name):
    col = bpy.data.collections.new(name)
    parent.children.link(col)
    return col


def link_object(col, name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    return obj


def uv_of(bm):
    layer = bm.loops.layers.uv.get("UVMap")
    return layer or bm.loops.layers.uv.new("UVMap")


def stamp(face, uv, mat):
    face.material_index = mat
    face.smooth = False
    for loop in face.loops:
        co = loop.vert.co
        if abs(face.normal.z) > 0.45:
            loop[uv].uv = (co.x * 0.55 + 0.5, co.y * 0.55 + 0.5)
        else:
            loop[uv].uv = (co.x * 0.5 + co.y * 0.5, co.z * 4.0)


def add_face(bm, verts, uv, mat):
    face = bm.faces.new(verts)
    face.normal_update()
    stamp(face, uv, mat)
    return face


def sector_solid(bm, r0, r1, a0, a1, z0, z1, na, nr, mat, bottom=True):
    uv = uv_of(bm)
    closed = abs((a1 - a0) - math.tau) < 1e-4
    steps = na if closed else na + 1
    angs = [a0 + (a1 - a0) * i / na for i in range(steps)]
    rads = [r0 + (r1 - r0) * i / nr for i in range(nr + 1)]
    top = []
    bot = []
    for radius in rads:
        top.append([bm.verts.new((math.cos(a) * radius, math.sin(a) * radius, z1)) for a in angs])
        bot.append([bm.verts.new((math.cos(a) * radius, math.sin(a) * radius, z0)) for a in angs])

    def ang_index(ai):
        return 0 if closed and ai == na else ai

    for ri in range(nr):
        for ai in range(na):
            aj = ang_index(ai + 1)
            add_face(bm, [top[ri][ai], top[ri][aj], top[ri + 1][aj], top[ri + 1][ai]], uv, mat)
            if bottom:
                add_face(bm, [bot[ri][ai], bot[ri + 1][ai], bot[ri + 1][aj], bot[ri][aj]], uv, mat)
    for ai in range(na):
        aj = ang_index(ai + 1)
        if r0 > 0.001:
            add_face(bm, [top[0][aj], top[0][ai], bot[0][ai], bot[0][aj]], uv, mat)
        add_face(bm, [top[nr][ai], top[nr][aj], bot[nr][aj], bot[nr][ai]], uv, mat)
    if not closed:
        for ri in range(nr):
            add_face(bm, [top[ri][0], top[ri + 1][0], bot[ri + 1][0], bot[ri][0]], uv, mat)
            add_face(bm, [top[ri + 1][na], top[ri][na], bot[ri][na], bot[ri + 1][na]], uv, mat)


def disc_solid(bm, radius, z0, z1, segs, mat):
    uv = uv_of(bm)
    top_c = bm.verts.new((0.0, 0.0, z1))
    bot_c = bm.verts.new((0.0, 0.0, z0))
    top = []
    bot = []
    for i in range(segs):
        ang = math.tau * i / segs
        top.append(bm.verts.new((math.cos(ang) * radius, math.sin(ang) * radius, z1)))
        bot.append(bm.verts.new((math.cos(ang) * radius, math.sin(ang) * radius, z0)))
    for i in range(segs):
        j = (i + 1) % segs
        add_face(bm, [top_c, top[i], top[j]], uv, mat)
        add_face(bm, [bot_c, bot[j], bot[i]], uv, mat)
        add_face(bm, [top[i], bot[i], bot[j], top[j]], uv, mat)


def cap(bm, points, z0, z1, mat, close_bottom=False):
    uv = uv_of(bm)
    top = [bm.verts.new((x, y, z1)) for x, y in points]
    low = [bm.verts.new((x, y, z0)) for x, y in points]
    add_face(bm, list(top), uv, mat)
    count = len(points)
    for i in range(count):
        j = (i + 1) % count
        add_face(bm, [top[i], top[j], low[j], low[i]], uv, mat)
    if close_bottom:
        add_face(bm, list(reversed(low)), uv, mat)


def ellipse(cx, cy, rx, ry, rot, steps=8):
    pts = []
    ca, sa = math.cos(rot), math.sin(rot)
    for i in range(steps):
        ang = math.tau * i / steps
        x = math.cos(ang) * rx
        y = math.sin(ang) * ry
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return pts


def arc_point(radius, ang):
    return (math.cos(ang) * radius, math.sin(ang) * radius)


def gold_band(bm, r0, r1, a0, a1, z, na):
    sector_solid(bm, r0, r1, a0, a1, z + 0.001, z + GOLD_HEIGHT, na, 1, MAT_GOLD, bottom=False)


def meander(bm, radius, a0, a1, z, keys):
    # A thin gold rail plus short returned strokes. Enough to read as a key fret.
    width = 0.045
    gold_band(bm, radius - width * 0.5, radius + width * 0.5, a0, a1, z, max(3, keys // 2))
    for i in range(keys):
        ang = a0 + (a1 - a0) * (i + 0.5) / keys
        reach = 0.07 if i % 2 == 0 else -0.055
        r_near = radius + (0.02 if reach > 0 else -0.02)
        r_far = radius + reach
        lo, hi = (r_near, r_far) if r_far > r_near else (r_far, r_near)
        half = (a1 - a0) / keys * 0.22
        sector_solid(bm, lo, hi, ang - half, ang + half, z, z + GOLD_HEIGHT * 0.85, 1, 1, MAT_GOLD)


def petal(bm, radius, ang, length, spread, z, mat):
    forward = Vector((math.cos(ang), math.sin(ang)))
    side = Vector((-forward.y, forward.x))
    root = forward * (radius - length * 0.35)
    tip = forward * (radius + length * 0.65)
    left = forward * radius + side * spread
    right = forward * radius - side * spread
    mid = forward * (radius + length * 0.05)
    uv = uv_of(bm)
    z1 = z + RELIEF_HEIGHT
    verts = [
        bm.verts.new((root.x, root.y, z + RELIEF_HEIGHT * 0.25)),
        bm.verts.new((left.x, left.y, z + RELIEF_HEIGHT * 0.45)),
        bm.verts.new((tip.x, tip.y, z + RELIEF_HEIGHT * 0.35)),
        bm.verts.new((right.x, right.y, z + RELIEF_HEIGHT * 0.45)),
        bm.verts.new((mid.x, mid.y, z1)),
    ]
    add_face(bm, [verts[0], verts[1], verts[4]], uv, mat)
    add_face(bm, [verts[1], verts[2], verts[4]], uv, mat)
    add_face(bm, [verts[2], verts[3], verts[4]], uv, mat)
    add_face(bm, [verts[3], verts[0], verts[4]], uv, mat)


def blossom(bm, radius, ang, scale, z, mat):
    cx, cy = arc_point(radius, ang)
    cap(bm, ellipse(cx, cy, 0.22 * scale, 0.22 * scale, ang, 8), z, z + 0.006, MAT_DARK)
    cap(bm, ellipse(cx, cy, 0.09 * scale, 0.09 * scale, ang, 8), z, z + RELIEF_HEIGHT * 0.85, MAT_GOLD)
    for i in range(6):
        petal(bm, radius, ang + i * math.tau / 6, 0.18 * scale, 0.06 * scale, z + 0.004, mat)


def cloud(bm, radius, ang, scale, z):
    cx, cy = arc_point(radius, ang)
    cap(bm, ellipse(cx, cy, 0.28 * scale, 0.18 * scale, ang, 8), z, z + 0.006, MAT_DARK)
    cap(bm, ellipse(cx, cy, 0.22 * scale, 0.12 * scale, ang, 8), z + 0.004, z + RELIEF_HEIGHT * 0.8, MAT_LIGHT)
    cap(bm, ellipse(cx + math.cos(ang) * 0.12 * scale, cy + math.sin(ang) * 0.12 * scale, 0.13 * scale, 0.09 * scale, ang + 0.6, 7), z + 0.004, z + RELIEF_HEIGHT, MAT_LIGHT)
    cap(bm, ellipse(cx - math.cos(ang) * 0.10 * scale, cy - math.sin(ang) * 0.10 * scale, 0.11 * scale, 0.08 * scale, ang - 0.4, 7), z + 0.004, z + RELIEF_HEIGHT * 0.9, MAT_LIGHT)


def finish(bm):
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    tops = [face for face in bm.faces if abs(face.normal.z) > 0.5]
    if tops and sum(face.normal.z for face in tops) < 0.0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    mesh = bpy.data.meshes.new("ArenaPart")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def assign(mesh, materials):
    for material in materials:
        mesh.materials.append(material)
    return mesh


def build_center(materials):
    bm = bmesh.new()
    segs = SEGMENT_COUNT * ANG_STEPS
    disc_solid(bm, CENTER_RADIUS, 0.0, SLAB_HEIGHT, segs, MAT_DARK)
    sector_solid(bm, 1.78, CENTER_RADIUS, 0.0, math.tau, SLAB_HEIGHT + 0.001, SLAB_HEIGHT + 0.008, segs, 1, MAT_LIGHT, bottom=False)
    gold_band(bm, 1.58, 1.76, 0.0, math.tau, SLAB_HEIGHT, segs)
    meander(bm, 1.67, 0.0, math.tau, SLAB_HEIGHT, 48)
    disc_solid(bm, 0.16, SLAB_HEIGHT + 0.002, SLAB_HEIGHT + RELIEF_HEIGHT + 0.008, 12, MAT_GOLD)
    for i in range(12):
        petal(bm, 0.55, i * math.tau / 12, 0.42, 0.11, SLAB_HEIGHT, MAT_LIGHT)
    for i in range(8):
        petal(bm, 0.28, i * math.tau / 8 + 0.2, 0.24, 0.07, SLAB_HEIGHT + 0.004, MAT_GOLD)
    for i, scale in enumerate((1.15, 0.85, 1.05, 0.8, 1.1, 0.9)):
        cloud(bm, 1.22, i * math.tau / 6 + 0.35, scale, SLAB_HEIGHT)
    return assign(finish(bm), materials)


def build_ring(r0, r1, kind, materials):
    bm = bmesh.new()
    a0, a1 = 0.0, SEG_ANGLE
    mid = (a0 + a1) * 0.5
    radius = (r0 + r1) * 0.5
    top_mat = MAT_DARK if kind == "decor" else MAT_LIGHT
    sector_solid(bm, r0, r1, a0, a1, 0.0, SLAB_HEIGHT, ANG_STEPS, 2, top_mat)
    if kind == "inner":
        meander(bm, r0 + 0.16, a0 + 0.03, a1 - 0.03, SLAB_HEIGHT, 7)
        cloud(bm, radius + 0.08, mid, 1.25, SLAB_HEIGHT)
    elif kind == "middle":
        meander(bm, r0 + 0.12, a0 + 0.025, a1 - 0.025, SLAB_HEIGHT, 6)
        meander(bm, r1 - 0.12, a0 + 0.025, a1 - 0.025, SLAB_HEIGHT, 7)
        blossom(bm, radius, mid, 1.35, SLAB_HEIGHT, MAT_LIGHT)
    elif kind == "decor":
        sector_solid(bm, r0 + 0.08, r1 - 0.08, a0 + 0.02, a1 - 0.02, SLAB_HEIGHT, SLAB_HEIGHT + 0.006, ANG_STEPS, 1, MAT_DARK)
        meander(bm, r0 + 0.14, a0 + 0.03, a1 - 0.03, SLAB_HEIGHT, 6)
        meander(bm, r1 - 0.14, a0 + 0.03, a1 - 0.03, SLAB_HEIGHT, 8)
        blossom(bm, radius - 0.08, mid - 0.12, 1.05, SLAB_HEIGHT, MAT_LIGHT)
        blossom(bm, radius + 0.06, mid + 0.12, 0.95, SLAB_HEIGHT, MAT_GOLD)
    else:
        gold_band(bm, r1 - 0.08, r1 - 0.035, a0, a1, SLAB_HEIGHT, ANG_STEPS)
        groove = (a0 + a1) * 0.5
        sector_solid(bm, r0 + 0.05, r1 - 0.12, groove - 0.008, groove + 0.008, SLAB_HEIGHT, SLAB_HEIGHT + 0.008, 1, 1, MAT_DARK)
    return assign(finish(bm), materials)


def build_separator(materials):
    bm = bmesh.new()
    z = SLAB_HEIGHT + 0.004
    half = 0.09
    # Local +X is the authored direction. Preview copies rotate it to the cardinals.
    sector_solid(bm, CENTER_RADIUS + 0.02, ARENA_RADIUS - 0.04, -0.012, 0.012, z, z + 0.02, 1, 8, MAT_DARK)
    gold_band(bm, CENTER_RADIUS + 0.04, ARENA_RADIUS - 0.06, -0.006, -0.003, z + 0.012, 10)
    gold_band(bm, CENTER_RADIUS + 0.04, ARENA_RADIUS - 0.06, 0.003, 0.006, z + 0.012, 10)
    for radius in (INNER_RING_RADIUS, MIDDLE_RING_RADIUS, OUTER_RING_RADIUS):
        sector_solid(bm, radius - 0.16, radius + 0.10, -half * 0.35, half * 0.35, z, z + 0.028, 1, 1, MAT_LIGHT)
        gold_band(bm, radius - 0.12, radius + 0.06, -0.05, 0.05, z + 0.02, 2)
    return assign(finish(bm), materials)


def build_anchor(materials):
    bm = bmesh.new()
    s = 0.6
    slab = SLAB_HEIGHT
    box = [(-s, -s), (s, -s), (s, s), (-s, s)]
    cap(bm, box, 0.0, slab, MAT_LIGHT, close_bottom=True)
    inner = 0.34
    cap(bm, [(-inner, -inner), (inner, -inner), (inner, inner), (-inner, inner)], slab, slab + 0.008, MAT_DARK)
    frame = 0.40
    band = 0.045
    gold_rect(bm, -frame, frame, frame - band, frame, slab, MAT_GOLD)
    gold_rect(bm, -frame, frame, -frame, -frame + band, slab, MAT_GOLD)
    gold_rect(bm, -frame, -frame + band, -frame, frame, slab, MAT_GOLD)
    gold_rect(bm, frame - band, frame, -frame, frame, slab, MAT_GOLD)
    for i in range(8):
        petal(bm, 0.16, i * math.tau / 8, 0.20, 0.055, slab + 0.006, MAT_GOLD)
    disc_solid(bm, 0.07, slab + 0.006, slab + RELIEF_HEIGHT + 0.01, 10, MAT_GOLD)
    return assign(finish(bm), materials)


def gold_rect(bm, x0, x1, y0, y1, z, mat):
    uv = uv_of(bm)
    z1 = z + GOLD_HEIGHT
    verts = [
        bm.verts.new((x0, y0, z1)), bm.verts.new((x1, y0, z1)),
        bm.verts.new((x1, y1, z1)), bm.verts.new((x0, y1, z1)),
        bm.verts.new((x0, y0, z)), bm.verts.new((x1, y0, z)),
        bm.verts.new((x1, y1, z)), bm.verts.new((x0, y1, z)),
    ]
    add_face(bm, verts[0:4], uv, mat)
    add_face(bm, [verts[4], verts[5], verts[1], verts[0]], uv, mat)
    add_face(bm, [verts[5], verts[6], verts[2], verts[1]], uv, mat)
    add_face(bm, [verts[6], verts[7], verts[3], verts[2]], uv, mat)
    add_face(bm, [verts[7], verts[4], verts[0], verts[3]], uv, mat)


def build_transition(materials, side):
    bm = bmesh.new()
    s = 0.6
    box = [(-s, -s), (s, -s), (s, s), (-s, s)]
    cap(bm, box, 0.0, SLAB_HEIGHT, MAT_LIGHT, close_bottom=True)
    x_edge = -0.42 * side
    x_in = x_edge + 0.10 * side
    lo, hi = (x_edge, x_in) if x_in > x_edge else (x_in, x_edge)
    gold_rect(bm, lo, hi, -0.48, 0.48, SLAB_HEIGHT, MAT_GOLD)
    gold_rect(bm, -0.48, 0.48, 0.46, 0.52, SLAB_HEIGHT, MAT_GOLD)
    gold_rect(bm, -0.48, 0.48, -0.52, -0.46, SLAB_HEIGHT, MAT_GOLD)
    # Corner fret, mirrored with `side`.
    fx = -0.28 * side
    gold_rect(bm, fx - 0.08, fx + 0.08, -0.50, -0.30, SLAB_HEIGHT, MAT_GOLD)
    gold_rect(bm, fx - 0.08 * side, fx + 0.16 * side, -0.40, -0.28, SLAB_HEIGHT, MAT_GOLD)
    return assign(finish(bm), materials)


def build_floor_tile(materials, variant):
    bm = bmesh.new()
    uv = uv_of(bm)
    n = 8
    step = 1.0 / n

    def z_at(ix, iy):
        u = -0.5 + ix * step
        v = -0.5 + iy * step
        edge = min(ix, iy, n - ix, n - iy)
        height = SLAB_HEIGHT if edge > 0 else SLAB_HEIGHT - 0.018
        if variant == "A":
            if abs((u - v) - 0.05) < 0.03 and abs(u) < 0.32:
                height -= 0.01
        elif variant == "B":
            if abs(v - 0.22) < 0.025 and -0.35 < u < 0.2:
                height -= 0.01
        else:
            if abs(u + 0.18) < 0.025 and v > -0.05:
                height -= 0.01
            if abs(v + 0.05) < 0.025 and u > -0.2:
                height -= 0.008
        return u, v, height

    top = []
    for iy in range(n + 1):
        row = []
        for ix in range(n + 1):
            u, v, height = z_at(ix, iy)
            row.append(bm.verts.new((u, v, height)))
        top.append(row)
    for iy in range(n):
        for ix in range(n):
            add_face(bm, [top[iy][ix], top[iy][ix + 1], top[iy + 1][ix + 1], top[iy + 1][ix]], uv, MAT_LIGHT)
    rim = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
    low = [bm.verts.new((x, y, 0.0)) for x, y in rim]
    add_face(bm, [low[0], low[3], low[2], low[1]], uv, MAT_LIGHT)
    high = [top[0][0], top[0][n], top[n][n], top[n][0]]
    order = [(0, 1), (1, 2), (2, 3), (3, 0)]
    corners = [high[0], high[1], high[2], high[3]]
    for i, j in order:
        add_face(bm, [corners[i], low[i], low[j], corners[j]], uv, MAT_LIGHT)
    shift = {"A": (0.0, 0.0), "B": (0.37, 0.21), "C": (0.64, 0.48)}[variant]
    for face in bm.faces:
        for loop in face.loops:
            u, v = loop[uv].uv
            loop[uv].uv = (u + shift[0], v + shift[1])
    return assign(finish(bm), materials)


def tri_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def export_glb(obj, filename):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    return path


def duplicate(src, col, name, rot_z=0.0, location=(0.0, 0.0, 0.0)):
    copy = src.copy()
    copy.data = src.data
    copy.name = name
    col.objects.link(copy)
    copy.rotation_euler = (0.0, 0.0, rot_z)
    copy.location = location
    return copy


def render_previews():
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 1280
    scene.render.image_settings.file_format = "PNG"
    world = scene.world
    if world is None:
        world = bpy.data.worlds.new("ArenaWorld")
        scene.world = world
    world.color = (0.05, 0.05, 0.055)
    bpy.ops.object.light_add(type="SUN", location=(4, -6, 12))
    sun = bpy.context.object
    sun.data.energy = 3.8
    sun.data.color = (1.0, 0.94, 0.84)
    sun.rotation_euler = (math.radians(38), 0.0, math.radians(32))
    eevee = scene.eevee
    if hasattr(eevee, "use_gtao"):
        eevee.use_gtao = True
        eevee.gtao_distance = 0.45
        eevee.gtao_factor = 1.4
    bpy.ops.object.camera_add(location=(0.0, 0.0, 18.0))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 15.5
    camera.rotation_euler = (0.0, 0.0, 0.0)
    scene.camera = camera
    scene.render.filepath = os.path.join(OUT_DIR, "arena_floor_top.png")
    bpy.ops.render.render(write_still=True)
    camera.data.type = "PERSP"
    camera.data.lens = 38
    camera.location = (11.5, -11.5, 7.2)
    direction = Vector((0.0, 0.0, 0.2)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_y = 800
    scene.render.filepath = os.path.join(OUT_DIR, "arena_floor_oblique.png")
    bpy.ops.render.render(write_still=True)
    for extra in (sun, camera):
        bpy.data.objects.remove(extra, do_unlink=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    reset_scene()
    light_img = load_texture("stone_light")
    dark_img = load_texture("stone_dark")
    gold_img = load_texture("gold_trim")
    materials = [
        make_material("M_Stone_Light", light_img, 0.90, 0.0),
        make_material("M_Stone_Dark", dark_img, 0.92, 0.0),
        make_material("M_Gold_Trim", gold_img, 0.72, 0.08),
    ]
    root = bpy.data.collections.new("ArenaFloor")
    bpy.context.scene.collection.children.link(root)
    groups = {
        "Center": new_collection(root, "Center"),
        "InnerRing": new_collection(root, "InnerRing"),
        "MiddleRing": new_collection(root, "MiddleRing"),
        "OuterRing": new_collection(root, "OuterRing"),
        "Separators": new_collection(root, "Separators"),
        "AnchorTiles": new_collection(root, "AnchorTiles"),
        "TransitionTiles": new_collection(root, "TransitionTiles"),
        "SquareTiles": new_collection(root, "SquareTiles"),
    }
    preview = new_collection(root, "Preview")

    center = link_object(groups["Center"], "arena_center", build_center(materials))
    inner = link_object(groups["InnerRing"], "arena_inner_segment", build_ring(CENTER_RADIUS, INNER_RING_RADIUS, "inner", materials))
    middle = link_object(groups["MiddleRing"], "arena_middle_segment", build_ring(INNER_RING_RADIUS, MIDDLE_RING_RADIUS, "middle", materials))
    decor = link_object(groups["OuterRing"], "arena_outer_decor_segment", build_ring(MIDDLE_RING_RADIUS, OUTER_RING_RADIUS, "decor", materials))
    plain = link_object(groups["OuterRing"], "arena_outer_plain_segment", build_ring(OUTER_RING_RADIUS, ARENA_RADIUS, "plain", materials))
    separator = link_object(groups["Separators"], "arena_separator", build_separator(materials))
    anchor = link_object(groups["AnchorTiles"], "arena_anchor_tile", build_anchor(materials))
    left = link_object(groups["TransitionTiles"], "arena_transition_left", build_transition(materials, 1.0))
    right = link_object(groups["TransitionTiles"], "arena_transition_right", build_transition(materials, -1.0))
    tile_a = link_object(groups["SquareTiles"], "floor_tile_A", build_floor_tile(materials, "A"))
    tile_b = link_object(groups["SquareTiles"], "floor_tile_B", build_floor_tile(materials, "B"))
    tile_c = link_object(groups["SquareTiles"], "floor_tile_C", build_floor_tile(materials, "C"))

    masters = [
        (center, "arena_center.glb"),
        (inner, "arena_inner_segment.glb"),
        (middle, "arena_middle_segment.glb"),
        (decor, "arena_outer_decor_segment.glb"),
        (plain, "arena_outer_plain_segment.glb"),
        (separator, "arena_separator.glb"),
        (anchor, "arena_anchor_tile.glb"),
        (left, "arena_transition_left.glb"),
        (right, "arena_transition_right.glb"),
        (tile_a, "floor_tile_A.glb"),
        (tile_b, "floor_tile_B.glb"),
        (tile_c, "floor_tile_C.glb"),
    ]
    for obj, _filename in masters:
        if abs(obj.scale.x - 1.0) > 1e-6 or abs(obj.rotation_euler.z) > 1e-6:
            raise SystemExit("MASTER_TRANSFORM %s" % obj.name)
        print("TRIS %s %d" % (obj.name, tri_count(obj.data)))

    for index in range(SEGMENT_COUNT):
        yaw = index * SEG_ANGLE
        for src in (inner, middle, decor, plain):
            duplicate(src, preview, "Preview_%s_%d" % (src.name, index), yaw)
    for index in range(4):
        yaw = index * (math.tau / 4)
        duplicate(separator, preview, "PreviewSeparator_%d" % index, yaw)
        ang = yaw
        radius = 5.05
        duplicate(anchor, preview, "PreviewAnchor_%d" % index, 0.0, (math.cos(ang) * radius, math.sin(ang) * radius, 0.02))
    outside = -(ARENA_RADIUS + 0.85)
    duplicate(left, preview, "PreviewTransitionL", 0.0, (-1.3, outside, 0.0))
    duplicate(right, preview, "PreviewTransitionR", 0.0, (1.3, outside, 0.0))
    for index, src in enumerate((tile_a, tile_b, tile_c, tile_a)):
        duplicate(src, preview, "PreviewTile_%d" % index, 0.0, ((index - 1.5) * 1.0, outside - 1.25, 0.0))

    # Masters stay put. Hide them during the preview render so the circle is not drawn twice.
    for obj, _filename in masters:
        obj.hide_render = obj is not center
    render_previews()
    for obj, _filename in masters:
        obj.hide_render = False
    for obj, filename in masters:
        export_glb(obj, filename)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "arena_floor.blend"))
    _share_textures()
    print("ARENA_FLOOR_BUILT %s" % OUT_DIR)


def _share_textures():
    script = os.path.join(ROOT, "tools", "externalize_glb_textures.py")
    spec = importlib.util.spec_from_file_location("externalize_glb_textures", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.main([OUT_DIR])


if __name__ == "__main__":
    main()
