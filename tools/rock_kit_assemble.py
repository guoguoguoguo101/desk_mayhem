# Plants, textures, combo prefabs, and the rear-mountain placement for the rock kit.
# Called from tools/build_rock_kit.py.

import array
import importlib.util
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT_DIR = os.path.join(ROOT, "assets", "environment", "kits")
TEXTURE_DIR = os.path.join(KIT_DIR, "textures")
ROCK_DIR = os.path.join(ROOT, "assets", "environment", "rock_kit")
CATALOG_PATH = os.path.join(KIT_DIR, "catalog.json")
PLACEMENTS_PATH = os.path.join(ROOT, "assets", "environment", "mountain_arena", "kit_placements.json")
BLEND_PATH = os.path.join(ROCK_DIR, "rock_kit_preview.blend")
MODULE_PREVIEW = os.path.join(ROCK_DIR, "rock_kit_preview.png")
COMBO_PREVIEW = os.path.join(ROCK_DIR, "rock_kit_combos.png")

KIT_INFO = {
    "rock_base_01": ("base", "宽岩脚，适合山脚和中段，原点在视觉着地中心，地面以下是穿插榫"),
    "rock_base_02": ("base", "高瘦岩柱，适合尖峰核心，原点在视觉着地中心"),
    "rock_base_03": ("base", "中等岩柱，顶部略平，可叠松树，原点在视觉着地中心"),
    "rock_base_04": ("base", "断裂岩壁，大断面朝局部 +Y，原点在视觉着地中心"),
    "rock_base_05": ("base", "阶梯岩体，原点在视觉着地中心"),
    "rock_base_06": ("base", "悬挑岩体，挑出方向是局部 +X，原点在视觉着地中心"),
    "rock_base_07": ("base", "平顶岩台，可放建筑、松或竹，原点在视觉着地中心"),
    "rock_base_08": ("base", "三块小碎石，原点在簇中心的地面"),
    "rock_base_09": ("base", "尖顶岩锥，适合远峰顶部，原点在视觉着地中心"),
    "rock_base_10": ("base", "山脊连接块，长轴沿局部 X，两端和底部是穿插榫"),
    "pine_trunk_01": ("base", "较直的松干，原点在根部"),
    "pine_trunk_02": ("base", "迎客松树干，向局部 +X 倾斜，原点在根部"),
    "pine_crown_01": ("base", "横向展开的松冠，原点在与树干的连接处"),
    "pine_crown_02": ("base", "伞状松冠，原点在连接处"),
    "pine_crown_03": ("base", "偏斜松冠，重心在局部 +X，原点在连接处"),
    "shrub_01": ("base", "低矮圆灌木，原点在根部"),
    "shrub_02": ("base", "更扁的灌木，原点在根部"),
    "vine_01": ("base", "崖壁垂藤，原点在上方悬挂点"),
    "bamboo_01": ("base", "小竹丛，叶是叶片簇，原点在根部"),
    "bamboo_02": ("base", "中竹丛，叶是叶片簇，原点在根部"),
    "bamboo_03": ("base", "高竹丛，叶是叶片簇，原点在根部"),
    "cliff_combo_01": ("base", "宽岩壁、岩柱和松树的组合，原点在地面"),
    "cliff_combo_02": ("base", "阶梯岩体和松树的组合，原点在地面"),
    "cliff_combo_03": ("base", "悬挑岩体和小碎石的组合，原点在地面"),
    "peak_combo_01": ("base", "多根高瘦岩柱组成的主峰，原点在地面"),
    "peak_combo_02": ("base", "中型岩柱和山脊组成的连峰，原点在地面"),
    "peak_combo_03": ("base", "尖峰加山脊连接块，原点在地面"),
    "pine_cliff_01": ("base", "岩台和迎客松，原点在地面"),
    "bamboo_platform_01": ("base", "岩台和竹丛，原点在地面"),
}


def _speck(u, v):
    value = math.sin(u * 127.1 + v * 311.7) * 43758.5453
    return value - math.floor(value)


def paint(name, width, height, painter):
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    image = bpy.data.images.new(name, width, height, alpha=True, float_buffer=False)
    image.colorspace_settings.name = "sRGB"
    image.alpha_mode = "STRAIGHT"
    buf = array.array("f", [0.0]) * (width * height * 4)
    for y in range(height):
        v = (y + 0.5) / height
        row = y * width
        for x in range(width):
            u = (x + 0.5) / width
            red, green, blue, alpha = painter(u, v)
            index = (row + x) * 4
            buf[index] = red
            buf[index + 1] = green
            buf[index + 2] = blue
            buf[index + 3] = alpha
    image.pixels.foreach_set(buf)
    image.update()
    image.filepath_raw = os.path.join(TEXTURE_DIR, name + ".png")
    image.file_format = "PNG"
    image.save()
    return image


def paint_strata(u, v):
    groove = abs(math.sin(u * math.pi * 16.0))
    layer = 0.55 + 0.45 * math.sin((v * 5.0 + u * 0.15) * math.pi)
    grain = 0.85 + 0.15 * _speck(u * 3.0, v * 3.0)
    tone = layer * grain
    if groove < 0.16:
        tone *= 0.52
    if v < 0.1:
        return (0.26 * tone, 0.34 * tone, 0.2 * tone, 1.0)
    return (0.46 * tone, 0.47 * tone, 0.41 * tone, 1.0)


def paint_cut(u, v):
    tone = 0.78 + 0.22 * _speck(u * 4.0, v * 2.0)
    if abs(math.sin((u * 6.0 + v * 1.4) * math.pi)) < 0.06:
        tone *= 0.72
    return (0.78 * tone, 0.73 * tone, 0.62 * tone, 1.0)


def paint_bark(u, v):
    ridge = 0.45 + 0.55 * abs(math.sin(u * math.pi * 22.0))
    knot = _speck(u * 2.0, v * 5.0)
    tone = ridge * (0.75 + 0.25 * knot)
    if abs(math.sin((v * 9.0 + u) * math.pi)) > 0.93:
        tone *= 0.7
    return (0.34 * tone, 0.2 * tone, 0.1 * tone, 1.0)


def paint_needles(u, v):
    x = (u - 0.5) * 2.0
    y = v
    alpha = 0.0
    shade = 0.3
    for index in range(11):
        angle = -0.95 + index * 0.19
        direction = Vector((math.sin(angle) * 0.85, math.cos(angle)))
        start = Vector((0.0, 0.04))
        point = Vector((x, y)) - start
        along = point.x * direction.x + point.y * direction.y
        if along < 0.0 or along > 1.15:
            continue
        side = abs(point.x * direction.y - point.y * direction.x)
        width = 0.14 * (1.0 - along * 0.35)
        if side < width:
            alpha = max(alpha, 1.0 - side / width)
            shade = 0.25 + 0.15 * (index % 4)
    if alpha <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    return (0.07 + 0.04 * shade, 0.24 + 0.28 * shade, 0.08, alpha)


def paint_shrub(u, v):
    x = (u - 0.5) * 2.0
    y = (v - 0.45) * 2.0
    alpha = 0.0
    blobs = ((-0.2, 0.1, 0.7), (0.35, 0.05, 0.62), (0.0, 0.45, 0.5), (-0.45, -0.2, 0.48), (0.4, -0.35, 0.42))
    for cx, cy, radius in blobs:
        dist = math.hypot(x - cx, y - cy)
        alpha = max(alpha, max(0.0, 1.0 - dist / radius))
    if alpha <= 0.05:
        return (0.0, 0.0, 0.0, 0.0)
    fleck = _speck(u * 8.0, v * 8.0)
    return (0.12 + 0.1 * fleck, 0.34 + 0.22 * alpha, 0.1, alpha)


def paint_vine(u, v):
    x = abs(u - 0.5) * 2.0
    stem = max(0.0, 1.0 - x / 0.08) * (0.35 if v > 0.08 else 0.0)
    alpha = stem
    leaf_row = int(v * 7.0)
    center = 0.22 if leaf_row % 2 == 0 else 0.78
    along = abs(v * 7.0 - leaf_row - 0.5)
    side = abs(u - center)
    leaf = max(0.0, 1.0 - math.hypot(side / 0.22, along / 0.45))
    alpha = max(alpha, leaf * (1.0 if 0.08 < v < 0.96 else 0.0))
    if alpha <= 0.05:
        return (0.0, 0.0, 0.0, 0.0)
    return (0.15, 0.38 + 0.15 * alpha, 0.12, alpha)


def paint_bamboo_leaf(u, v):
    x = (u - 0.5) * 2.0
    y = v
    alpha = 0.0
    for index in range(5):
        angle = -0.7 + index * 0.35
        direction = Vector((math.sin(angle), math.cos(angle) * 1.15))
        point = Vector((x, y - 0.02))
        along = point.x * direction.x + point.y * direction.y
        if along < 0.0 or along > 1.05:
            continue
        side = abs(point.x * direction.y - point.y * direction.x)
        width = 0.18 * (1.0 - along * 0.45)
        if side < width:
            alpha = max(alpha, 1.0 - side / width)
    if alpha <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    return (0.2, 0.48 + 0.2 * alpha, 0.12, alpha)


def paint_bamboo_skin(u, v):
    band = 0.75 + 0.25 * math.sin(v * math.pi * 10.0)
    if abs(math.sin(v * math.pi * 5.0)) > 0.92:
        band *= 0.55
    stripe = 0.9 + 0.1 * math.sin(u * math.pi * 2.0)
    tone = band * stripe
    return (0.28 * tone, 0.55 * tone, 0.16 * tone, 1.0)


def paint_textures():
    return {
        "strata": paint("rock_strata", 256, 256, paint_strata),
        "cut": paint("rock_cut", 256, 256, paint_cut),
        "bark": paint("pine_bark", 128, 256, paint_bark),
        "needle": paint("pine_needle", 160, 160, paint_needles),
        "shrub": paint("shrub_leaf", 160, 160, paint_shrub),
        "vine": paint("vine_leaf", 128, 256, paint_vine),
        "bamboo_leaf": paint("bamboo_leaf_cluster", 160, 160, paint_bamboo_leaf),
        "bamboo_skin": paint("bamboo_skin", 64, 256, paint_bamboo_skin),
    }


def image_material(name, image, roughness, tint=(1.0, 1.0, 1.0), repeat=True, masked=False):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (tint[0], tint[1], tint[2], 1.0)
    material.use_nodes = True
    material.use_backface_culling = False
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "BLENDED"
    tree = material.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    tex.extension = "REPEAT" if repeat else "CLIP"
    color = tex.outputs["Color"]
    if tint != (1.0, 1.0, 1.0):
        mix = tree.nodes.new("ShaderNodeVectorMath")
        mix.operation = "MULTIPLY"
        mix.inputs[1].default_value = (tint[0], tint[1], tint[2])
        tree.links.new(color, mix.inputs[0])
        color = mix.outputs["Vector"]
    tree.links.new(color, bsdf.inputs["Base Color"])
    if masked:
        clip = tree.nodes.new("ShaderNodeMath")
        clip.operation = "GREATER_THAN"
        clip.inputs[1].default_value = 0.15
        tree.links.new(tex.outputs["Alpha"], clip.inputs[0])
        tree.links.new(clip.outputs["Value"], bsdf.inputs["Alpha"])
    return material


def dress_rocks(materials, images):
    # Body, alternate body, cut, mossy ledge, underside, buried plug.
    specs = (
        (images["strata"], (1.0, 1.0, 1.0)),
        (images["strata"], (0.78, 0.82, 0.74)),
        (images["cut"], (1.0, 1.0, 1.0)),
        (images["strata"], (0.62, 0.78, 0.52)),
        (images["strata"], (0.42, 0.4, 0.36)),
        (images["strata"], (0.36, 0.32, 0.28)),
    )
    for material, (image, tint) in zip(materials, specs):
        tree = material.node_tree
        bsdf = tree.nodes.get("Principled BSDF")
        tex = tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Linear"
        tex.extension = "REPEAT"
        mix = tree.nodes.new("ShaderNodeVectorMath")
        mix.operation = "MULTIPLY"
        mix.inputs[1].default_value = (tint[0], tint[1], tint[2])
        tree.links.new(tex.outputs["Color"], mix.inputs[0])
        tree.links.new(mix.outputs["Vector"], bsdf.inputs["Base Color"])


def rock_materials(images):
    return [
        image_material("RockBody", images["strata"], 0.9),
        image_material("RockCut", images["cut"], 0.78),
        image_material("RockPlug", images["strata"], 0.95, tint=(0.42, 0.4, 0.36)),
    ]


def _mesh_object(name, bm, materials, collection):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for material in materials:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj["kit_id"] = name
    zs = [vertex.co.z for vertex in mesh.vertices]
    if zs:
        top = max(zs)
        obj["top"] = float(top)
        obj["plug_depth"] = float(-min(min(zs), 0.0))
        tips = [vertex.co for vertex in mesh.vertices if vertex.co.z > top - 0.2]
        obj["tip_x"] = float(sum(point.x for point in tips) / len(tips))
        obj["tip_y"] = float(sum(point.y for point in tips) / len(tips))
        obj["tip_z"] = float(top)
    return obj


def _loft(bm, rings, mat_index, uv_layer):
    count = len(rings[0])
    verts = [[bm.verts.new(point) for point in ring] for ring in rings]
    bm.verts.ensure_lookup_table()
    for span in range(len(rings) - 1):
        for index in range(count):
            nxt = (index + 1) % count
            face = bm.faces.new((verts[span][index], verts[span][nxt], verts[span + 1][nxt], verts[span + 1][index]))
            face.material_index = mat_index
            for loop in face.loops:
                co = loop.vert.co
                loop[uv_layer].uv = ((math.atan2(co.y, co.x) / math.tau) % 1.0, co.z * 0.35)
    cap_top = bm.faces.new(verts[-1])
    cap_top.material_index = mat_index
    cap_bottom = bm.faces.new(list(reversed(verts[0])))
    cap_bottom.material_index = mat_index
    for face in (cap_top, cap_bottom):
        for loop in face.loops:
            loop[uv_layer].uv = (0.5, 0.5)
    bm.normal_update()
    inward = []
    for face in bm.faces:
        if abs(face.normal.z) > 0.6:
            continue
        center = face.calc_center_median()
        if face.normal.x * center.x + face.normal.y * center.y < 0.0:
            inward.append(face)
    for face in inward:
        face.normal_flip()


def _card(bm, center, normal, width, height, uv_layer, mat_index, twist=0.0):
    normal = normal.normalized()
    up = Vector((0.0, 0.0, 1.0))
    if abs(normal.z) > 0.92:
        up = Vector((0.0, 1.0, 0.0))
    tangent = normal.cross(up).normalized()
    bitangent = tangent.cross(normal).normalized()
    spin = Matrix.Rotation(twist, 3, normal)
    tangent = spin @ tangent * (width * 0.5)
    bitangent = spin @ bitangent * (height * 0.5)
    offset = normal * 0.01
    corners = (
        center - tangent - bitangent,
        center + tangent - bitangent,
        center + tangent + bitangent,
        center - tangent + bitangent,
    )
    front = [bm.verts.new(point + offset) for point in corners]
    back = [bm.verts.new(point - offset) for point in corners]
    face = bm.faces.new(front)
    rear = bm.faces.new(list(reversed(back)))
    face.material_index = mat_index
    rear.material_index = mat_index
    for loop, uv in zip(face.loops, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
        loop[uv_layer].uv = uv
    for loop, uv in zip(rear.loops, ((0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0))):
        loop[uv_layer].uv = uv


def build_trunk(name, height, base_r, lean, collection, material):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    rings = []
    steps = 7
    sides = 7
    for step in range(steps):
        t = step / (steps - 1)
        z = height * (t ** 0.92)
        radius = base_r * (1.0 - t) + 0.06 * t
        center = Vector((lean * (t ** 1.65), math.sin(t * math.pi) * lean * 0.12, z))
        ring = []
        for index in range(sides):
            angle = math.tau * index / sides
            wobble = 0.7 if index == 2 else 1.0 + 0.06 * math.sin(index * 1.7)
            ring.append(center + Vector((math.cos(angle) * radius * wobble, math.sin(angle) * radius * wobble * 0.86, 0.0)))
        rings.append(ring)
    _loft(bm, rings, 0, uv_layer)
    obj = _mesh_object(name, bm, [material], collection)
    obj["tip_x"] = float(lean)
    obj["tip_y"] = 0.0
    obj["tip_z"] = float(height)
    obj["top"] = float(height)
    return obj


def build_crown(name, kind, collection, material):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    rng = random.Random({"wide": 3, "umbrella": 5, "lean": 9}[kind])
    if kind == "wide":
        tiers = ((0.35, 2.5, 16), (0.95, 1.9, 12), (1.5, 1.05, 8))
        bias = 0.0
    elif kind == "umbrella":
        tiers = ((0.22, 3.15, 18), (0.62, 2.2, 12), (1.05, 0.9, 7))
        bias = 0.0
    else:
        tiers = ((0.3, 1.3, 8), (0.75, 2.15, 12), (1.2, 1.45, 8))
        bias = 1.15
    for height, radius, count in tiers:
        for index in range(count):
            angle = math.tau * (index + rng.random() * 0.25) / count
            spread = radius * (0.62 + 0.38 * rng.random())
            if kind == "lean":
                spread *= 0.35 + 0.95 * max(0.0, math.cos(angle))
            center = Vector((math.cos(angle) * spread + bias * 0.25, math.sin(angle) * spread * 0.72, height))
            normal = Vector((math.cos(angle) * 0.65, math.sin(angle) * 0.45, 0.9)).normalized()
            _card(bm, center, normal, 1.45, 0.85, uv_layer, 0, rng.uniform(-0.4, 0.4))
    return _mesh_object(name, bm, [material], collection)


def build_shrub(name, radius, height, collection, material, seed):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    rng = random.Random(seed)
    for index in range(20):
        angle = rng.random() * math.tau
        dist = radius * math.sqrt(rng.random())
        z = height * (0.25 + 0.7 * rng.random())
        center = Vector((math.cos(angle) * dist, math.sin(angle) * dist * 0.8, z))
        normal = Vector((math.cos(angle), math.sin(angle) * 0.7, 0.6)).normalized()
        _card(bm, center, normal, radius * 0.7, height * 0.55, uv_layer, 0, rng.uniform(-0.5, 0.5))
    return _mesh_object(name, bm, [material], collection)


def build_vine(collection, material):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for strand in range(4):
        x = (strand - 1.5) * 0.16
        for step in range(6):
            z = -0.12 - step * 0.38
            sway = math.sin(step * 0.9 + strand) * 0.14
            center = Vector((x + sway, strand * 0.02, z))
            normal = Vector((sway, 1.0, 0.15)).normalized()
            _card(bm, center, normal, 0.28, 0.36, uv_layer, 0, sway)
    return _mesh_object("vine_01", bm, [material], collection)


def build_bamboo(name, culms, height, collection, skin, leaf, seed):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    rng = random.Random(seed)
    for index in range(culms):
        angle = math.tau * index / culms + 0.4
        dist = 0.12 + (index % 4) * 0.16
        base = Vector((math.cos(angle) * dist, math.sin(angle) * dist, 0.0))
        culm_h = height * (0.68 + 0.32 * rng.random())
        lean = Vector((rng.uniform(-0.18, 0.18), rng.uniform(-0.12, 0.14), 0.0))
        radius = 0.05 if index % 3 else 0.07
        rings = []
        for step in range(5):
            t = step / 4.0
            center = base + lean * t + Vector((0.0, 0.0, culm_h * t))
            ring = []
            for side in range(6):
                ang = math.tau * side / 6.0
                ring.append(center + Vector((math.cos(ang) * radius * (1.0 - t * 0.4), math.sin(ang) * radius * (1.0 - t * 0.4), 0.0)))
            rings.append(ring)
        _loft(bm, rings, 0, uv_layer)
        top = rings[-1][0]
        top.z = culm_h
        for leaf_index in range(4):
            leaf_angle = angle + leaf_index * 1.4
            center = Vector((base.x + lean.x, base.y + lean.y, culm_h * 0.82)) + Vector((math.cos(leaf_angle) * 0.25, math.sin(leaf_angle) * 0.25, 0.15 * leaf_index))
            normal = Vector((math.cos(leaf_angle), math.sin(leaf_angle), 0.7)).normalized()
            _card(bm, center, normal, 1.15, 0.7, uv_layer, 1, leaf_index * 0.3)
    return _mesh_object(name, bm, [skin, leaf], collection)


def build_plants(images, collection):
    bark = image_material("PineBark", images["bark"], 0.84)
    needle = image_material("PineNeedle", images["needle"], 0.55, repeat=False, masked=True)
    shrub = image_material("ShrubLeaf", images["shrub"], 0.6, repeat=False, masked=True)
    vine = image_material("VineLeaf", images["vine"], 0.58, repeat=False, masked=True)
    skin = image_material("BambooSkin", images["bamboo_skin"], 0.5)
    leaf = image_material("BambooLeaf", images["bamboo_leaf"], 0.5, repeat=False, masked=True)
    plants = [
        build_trunk("pine_trunk_01", 5.6, 0.34, 0.35, collection, bark),
        build_trunk("pine_trunk_02", 4.4, 0.3, 1.65, collection, bark),
        build_crown("pine_crown_01", "wide", collection, needle),
        build_crown("pine_crown_02", "umbrella", collection, needle),
        build_crown("pine_crown_03", "lean", collection, needle),
        build_shrub("shrub_01", 0.85, 1.05, collection, shrub, 21),
        build_shrub("shrub_02", 1.25, 0.72, collection, shrub, 34),
        build_vine(collection, vine),
        build_bamboo("bamboo_01", 5, 3.6, collection, skin, leaf, 41),
        build_bamboo("bamboo_02", 8, 5.4, collection, skin, leaf, 52),
        build_bamboo("bamboo_03", 12, 7.2, collection, skin, leaf, 63),
    ]
    return {obj.name: obj for obj in plants}


def _empty(name, collection):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 1.2
    collection.objects.link(obj)
    obj["kit_id"] = name
    return obj


def _spawn(master, parent, name, location, rot_z=0.0, scale=1.0):
    obj = master.copy()
    obj.data = master.data
    obj.name = name
    parent.users_collection[0].objects.link(obj)
    obj.parent = parent
    obj.matrix_parent_inverse.identity()
    obj.location = Vector(location)
    obj.rotation_euler = (0.0, 0.0, rot_z)
    obj.scale = (scale, scale, scale)
    return obj


def _seat(master, scale, host_top, sink=0.68):
    return host_top - float(master["plug_depth"]) * scale * sink


def _pine(masters, parent, trunk_id, crown_id, location, rot_z, scale):
    trunk = masters[trunk_id]
    _spawn(trunk, parent, trunk_id, location, rot_z, scale)
    tip = Vector((float(trunk["tip_x"]), float(trunk["tip_y"]), float(trunk["tip_z"]))) * scale
    tip = Matrix.Rotation(rot_z, 3, "Z") @ tip
    _spawn(masters[crown_id], parent, crown_id, Vector(location) + tip, rot_z + 0.2, scale)


def build_combos(masters, collection):
    made = []

    root = _empty("cliff_combo_01", collection)
    wall_top = float(masters["ROCK_BASE_04"]["top"]) * 1.15
    _spawn(masters["ROCK_BASE_04"], root, "wall", (0.0, 0.0, 0.0), 0.1, 1.15)
    _spawn(masters["ROCK_BASE_01"], root, "foot", (-2.4, -1.6, 0.0), 0.5, 0.62)
    _spawn(masters["ROCK_BASE_02"], root, "pillar", (-0.3, -0.2, _seat(masters["ROCK_BASE_02"], 0.58, wall_top * 0.62)), 0.25, 0.58)
    _pine(masters, root, "pine_trunk_01", "pine_crown_01", (1.5, 0.3, wall_top * 0.48), -0.4, 0.8)
    _spawn(masters["shrub_01"], root, "shrub", (2.4, -1.8, 0.0), 0.2, 1.0)
    _spawn(masters["vine_01"], root, "vine", (0.4, 1.7, 4.4), 0.0, 1.1)
    _spawn(masters["ROCK_BASE_08"], root, "rubble", (3.1, 1.1, 0.0), 0.6, 1.15)
    made.append(root)

    root = _empty("cliff_combo_02", collection)
    step_top = float(masters["ROCK_BASE_05"]["top"]) * 1.1
    _spawn(masters["ROCK_BASE_05"], root, "steps", (0.0, 0.0, 0.0), 0.2, 1.1)
    _pine(masters, root, "pine_trunk_01", "pine_crown_02", (0.4, 0.2, step_top * 0.78), 0.3, 0.75)
    _spawn(masters["shrub_02"], root, "shrub", (2.6, 1.4, 0.0), 1.0, 1.0)
    _spawn(masters["ROCK_BASE_08"], root, "rubble", (-2.8, 1.2, 0.0), 0.4, 1.2)
    made.append(root)

    root = _empty("cliff_combo_03", collection)
    _spawn(masters["ROCK_BASE_06"], root, "nose", (0.0, 0.0, 0.0), -0.2, 1.15)
    _spawn(masters["ROCK_BASE_08"], root, "rubble", (3.4, 0.4, 0.0), 0.8, 1.3)
    _spawn(masters["ROCK_BASE_01"], root, "foot", (-1.6, -1.2, 0.0), 0.7, 0.48)
    _spawn(masters["vine_01"], root, "vine", (1.8, 0.2, 3.6), 0.4, 0.9)
    _spawn(masters["shrub_01"], root, "shrub", (2.2, -1.6, 0.0), 0.0, 0.9)
    made.append(root)

    root = _empty("peak_combo_01", collection)
    base_top = float(masters["ROCK_BASE_01"]["top"]) * 1.25
    _spawn(masters["ROCK_BASE_01"], root, "foot", (0.0, 0.0, 0.0), 0.3, 1.25)
    tall_z = _seat(masters["ROCK_BASE_02"], 1.0, base_top * 0.82)
    _spawn(masters["ROCK_BASE_02"], root, "pillar_a", (0.4, -0.3, tall_z), 0.15, 1.0)
    _spawn(masters["ROCK_BASE_02"], root, "pillar_b", (-2.7, 0.9, _seat(masters["ROCK_BASE_02"], 0.7, base_top * 0.5)), -0.45, 0.7)
    side_z = _seat(masters["ROCK_BASE_02"], 0.55, base_top * 0.38)
    _spawn(masters["ROCK_BASE_02"], root, "pillar_c", (3.0, 0.8, side_z), 0.55, 0.55)
    tall_top = tall_z + float(masters["ROCK_BASE_02"]["top"])
    _spawn(masters["ROCK_BASE_09"], root, "spire", (0.55, -0.25, _seat(masters["ROCK_BASE_09"], 0.6, tall_top)), 0.2, 0.6)
    _spawn(masters["ROCK_BASE_04"], root, "slab", (-1.2, 2.6, 0.0), 0.9, 0.72)
    _pine(masters, root, "pine_trunk_02", "pine_crown_03", (3.0, 0.7, side_z + float(masters["ROCK_BASE_02"]["top"]) * 0.55), 0.4, 0.7)
    _spawn(masters["shrub_01"], root, "shrub_a", (3.4, -2.2, 0.0), 0.2, 1.1)
    _spawn(masters["shrub_02"], root, "shrub_b", (-3.2, -1.4, 0.0), 1.1, 1.0)
    _spawn(masters["ROCK_BASE_08"], root, "rubble", (1.5, 3.2, 0.0), 0.3, 1.2)
    made.append(root)

    root = _empty("peak_combo_02", collection)
    _spawn(masters["ROCK_BASE_03"], root, "column_a", (-6.3, 0.0, 0.0), 0.2, 1.0)
    _spawn(masters["ROCK_BASE_03"], root, "column_b", (6.5, 0.4, 0.0), -0.35, 0.9)
    _spawn(masters["ROCK_BASE_01"], root, "foot_a", (-6.4, 0.6, 0.0), 0.6, 0.7)
    _spawn(masters["ROCK_BASE_01"], root, "foot_b", (6.6, -0.4, 0.0), -0.2, 0.62)
    _spawn(masters["ROCK_BASE_10"], root, "ridge", (0.2, 0.15, 2.5), 0.05, 1.0)
    cap_a = float(masters["ROCK_BASE_03"]["top"])
    _pine(masters, root, "pine_trunk_01", "pine_crown_02", (-6.2, 0.1, cap_a * 0.96), 0.4, 0.7)
    _pine(masters, root, "pine_trunk_01", "pine_crown_01", (6.5, 0.4, cap_a * 0.86), -0.2, 0.62)
    _spawn(masters["ROCK_BASE_05"], root, "steps", (0.2, 3.8, 0.0), 0.1, 0.8)
    _spawn(masters["shrub_02"], root, "shrub", (0.4, -2.6, 0.0), 0.0, 1.1)
    made.append(root)

    root = _empty("peak_combo_03", collection)
    core_z = 0.0
    _spawn(masters["ROCK_BASE_02"], root, "core", (-1.2, 0.0, core_z), 0.1, 1.05)
    core_top = float(masters["ROCK_BASE_02"]["top"]) * 1.05
    _spawn(masters["ROCK_BASE_09"], root, "spire", (-0.9, 0.15, _seat(masters["ROCK_BASE_09"], 0.72, core_top)), 0.3, 0.72)
    _spawn(masters["ROCK_BASE_10"], root, "ridge", (5.2, -0.6, 1.7), 0.28, 0.9)
    _spawn(masters["ROCK_BASE_03"], root, "end", (11.4, -2.3, 0.0), -0.4, 0.78)
    _pine(masters, root, "pine_trunk_02", "pine_crown_01", (11.2, -2.2, float(masters["ROCK_BASE_03"]["top"]) * 0.7), 0.6, 0.65)
    _spawn(masters["ROCK_BASE_01"], root, "foot", (-2.0, 1.4, 0.0), 0.8, 0.55)
    _spawn(masters["shrub_01"], root, "shrub", (2.4, 1.6, 0.0), 0.2, 1.0)
    made.append(root)

    root = _empty("pine_cliff_01", collection)
    deck = float(masters["ROCK_BASE_07"]["top"]) * 1.15
    _spawn(masters["ROCK_BASE_07"], root, "deck", (0.0, 0.0, 0.0), 0.15, 1.15)
    _pine(masters, root, "pine_trunk_02", "pine_crown_03", (1.3, -0.2, deck - 0.05), 0.35, 1.05)
    _spawn(masters["ROCK_BASE_08"], root, "rubble", (-3.2, 1.4, 0.0), 0.5, 1.1)
    _spawn(masters["shrub_02"], root, "shrub", (-1.4, 2.2, deck - 0.05), 0.8, 0.9)
    _spawn(masters["shrub_01"], root, "shrub_b", (3.0, 1.6, 0.0), 0.1, 1.0)
    made.append(root)

    root = _empty("bamboo_platform_01", collection)
    deck = float(masters["ROCK_BASE_07"]["top"]) * 1.2
    _spawn(masters["ROCK_BASE_07"], root, "deck", (0.0, 0.0, 0.0), -0.2, 1.2)
    _spawn(masters["bamboo_03"], root, "grove", (-0.4, 0.2, deck - 0.08), 0.4, 1.0)
    _spawn(masters["bamboo_02"], root, "mid", (1.8, -0.8, deck - 0.08), 1.1, 1.0)
    _spawn(masters["bamboo_01"], root, "small", (-2.0, -0.6, deck - 0.08), 0.2, 1.0)
    _spawn(masters["ROCK_BASE_08"], root, "rubble", (3.4, 1.5, 0.0), 0.7, 1.15)
    _spawn(masters["shrub_01"], root, "shrub", (-3.3, 1.8, 0.0), 0.3, 1.0)
    made.append(root)
    return made


def _bounds(objects):
    low = Vector((1e9, 1e9, 1e9))
    high = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            low.x, low.y, low.z = min(low.x, point.x), min(low.y, point.y), min(low.z, point.z)
            high.x, high.y, high.z = max(high.x, point.x), max(high.y, point.y), max(high.z, point.z)
    return low, high


def _layout(objects, y, gap, start_x=0.0):
    bpy.context.view_layer.update()
    cursor = start_x
    for obj in objects:
        meshes = [obj] if obj.type == "MESH" else [child for child in obj.children_recursive if child.type == "MESH"]
        low, high = _bounds(meshes)
        obj.location.x += cursor - low.x
        obj.location.y += y - (low.y + high.y) * 0.5
        cursor += (high.x - low.x) + gap
    bpy.context.view_layer.update()


def _label(collection, text, location):
    curve = bpy.data.curves.new("Label_" + text, "FONT")
    curve.body = text
    curve.align_x = "CENTER"
    curve.size = 0.48
    curve.extrude = 0.015
    obj = bpy.data.objects.new("LABEL_" + text, curve)
    obj.location = location
    obj.rotation_euler = (math.radians(70), 0.0, 0.0)
    collection.objects.link(obj)


def _render(scene, camera, objects, path):
    bpy.context.view_layer.update()
    meshes = []
    for obj in objects:
        if obj.type == "MESH":
            meshes.append(obj)
        meshes.extend(child for child in obj.children_recursive if child.type == "MESH")
    low, high = _bounds(meshes)
    center = (low + high) * 0.5
    span_x = high.x - low.x
    span_z = max(high.z - low.z, 1.0)
    camera.data.ortho_scale = max(span_x, span_z * 1.9) * 1.28
    location = center + Vector((0.18, -1.0, 0.7)).normalized() * (span_x + 36.0)
    target = Vector((center.x, center.y, low.z + span_z * 0.28))
    camera.location = location
    camera.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED %s" % path)


def _walk(obj):
    yield obj
    for child in obj.children:
        yield from _walk(child)


def _export(obj, path):
    saved = obj.matrix_basis.copy()
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    bpy.ops.object.select_all(action="DESELECT")
    for node in _walk(obj):
        node.hide_set(False)
        node.select_set(True)
    bpy.context.view_layer.objects.active = obj
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    obj.matrix_basis = saved


def _externalize(paths):
    script = os.path.join(ROOT, "tools", "externalize_glb_textures.py")
    spec = importlib.util.spec_from_file_location("externalize_glb_textures", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    canonical = {}
    for name in os.listdir(TEXTURE_DIR):
        if name.lower().endswith(".png"):
            texture = os.path.join(TEXTURE_DIR, name)
            canonical[module._hash_file(texture)] = texture
    for path in paths:
        print("externalized %s (%s)" % (os.path.basename(path), module.externalize_glb(path, canonical)))
    for name in os.listdir(KIT_DIR):
        path = os.path.join(KIT_DIR, name)
        if name.lower().endswith(".png") and os.path.isfile(path) and module._hash_file(path) in canonical:
            os.remove(path)
            print("removed sidecar %s" % name)


def _yaw_quat(yaw):
    return [0.0, round(math.sin(yaw * 0.5), 5), 0.0, round(math.cos(yaw * 0.5), 5)]


def _place(kit, x, z, yaw, scale, y=0.0):
    return {
        "kit": kit,
        "position": [round(x, 4), round(y, 4), round(z, 4)],
        "quaternion": _yaw_quat(yaw),
        "scale": [round(scale, 4), round(scale, 4), round(scale, 4)],
    }


def rear_placements():
    return [
        _place("peak_combo_01", 0.0, -58.0, 0.35, 1.65),
        _place("peak_combo_01", -34.0, -56.0, -0.8, 1.2),
        _place("peak_combo_02", 26.0, -54.0, 0.5, 1.25),
        _place("peak_combo_03", -16.0, -52.0, -0.25, 1.15),
        _place("cliff_combo_01", 12.0, -48.0, 1.1, 1.05),
        _place("cliff_combo_02", -6.0, -47.0, -0.5, 1.0),
        _place("cliff_combo_03", 38.0, -49.0, 0.9, 1.05),
        _place("pine_cliff_01", -48.0, -46.0, 0.4, 1.2),
        _place("bamboo_platform_01", 50.0, -46.0, -0.6, 1.15),
        _place("rock_base_10", 8.0, -51.0, 0.15, 1.35),
        _place("rock_base_01", -24.0, -49.0, 0.7, 1.3),
        _place("rock_base_04", 20.0, -47.5, -0.4, 1.1),
        _place("rock_base_08", -10.0, -46.0, 0.2, 1.4),
        _place("rock_base_08", 30.0, -46.0, 1.2, 1.2),
        _place("shrub_01", -40.0, -45.5, 0.3, 1.4),
        _place("shrub_02", 16.0, -45.5, -0.2, 1.3),
    ]


def _merge_json(exported_ids, placements):
    extra = [
        {"id": kit_id, "file": kit_id + ".glb", "origin": origin, "description": description}
        for kit_id, (origin, description) in KIT_INFO.items()
    ]
    os.makedirs(ROCK_DIR, exist_ok=True)
    with open(os.path.join(ROCK_DIR, "catalog_extra.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(extra, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    with open(os.path.join(ROCK_DIR, "rear_placements.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(placements, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    if os.path.exists(CATALOG_PATH):
        with open(CATALOG_PATH, encoding="utf-8") as handle:
            catalog = json.load(handle)
        catalog["kits"] = [item for item in catalog["kits"] if item["id"] not in exported_ids] + extra
        with open(CATALOG_PATH, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(catalog, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
    if os.path.exists(PLACEMENTS_PATH):
        with open(PLACEMENTS_PATH, encoding="utf-8") as handle:
            placed = json.load(handle)
        placed["placements"] = [item for item in placed["placements"] if item.get("kit") not in exported_ids] + placements
        with open(PLACEMENTS_PATH, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(placed, handle, ensure_ascii=False)
            handle.write("\n")
    print("ROCK_KIT_MERGED kits=%d rear=%d" % (len(extra), len(placements)))


def finish(rocks, images, modules, labels, camera, scene):
    plants_col = bpy.data.collections.new("Plants")
    combos_col = bpy.data.collections.new("Combos")
    scene.collection.children.link(plants_col)
    scene.collection.children.link(combos_col)
    plants = build_plants(images, plants_col)
    masters = {obj.name: obj for obj in rocks}
    masters.update(plants)
    bpy.context.view_layer.update()
    bpy.context.view_layer.update()
    rock_high_x = max((obj.matrix_world @ Vector(corner)).x for obj in rocks for corner in obj.bound_box)
    _layout(list(plants.values()), 0.0, 2.4, rock_high_x + 6.0)
    for obj in plants.values():
        low, _high = _bounds([obj])
        _label(labels, obj.name, (obj.matrix_world.translation.x, low.y - 0.3, 0.1))
    combos = build_combos(masters, combos_col)
    _layout(combos, -42.0, 6.0)
    for root in combos:
        low, _high = _bounds([child for child in root.children_recursive if child.type == "MESH"])
        _label(labels, root.name, ((low.x + _high.x) * 0.5, low.y - 0.4, 0.1))

    combos_col.hide_render = True
    _render(scene, camera, list(rocks) + list(plants.values()), MODULE_PREVIEW)
    combos_col.hide_render = False
    modules.hide_render = True
    plants_col.hide_render = True
    labels.hide_render = True
    _render(scene, camera, combos, COMBO_PREVIEW)
    modules.hide_render = False
    plants_col.hide_render = False
    labels.hide_render = False

    paths = []
    exported = []
    for obj in list(rocks) + list(plants.values()) + combos:
        kit_id = str(obj["kit_id"])
        path = os.path.join(KIT_DIR, kit_id + ".glb")
        _export(obj, path)
        paths.append(path)
        exported.append(kit_id)
        print("EXPORTED %s" % kit_id)
    _externalize(paths)
    _merge_json(set(exported), rear_placements())
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("ROCK_KIT_DONE %s" % BLEND_PATH)
