import array
import bmesh
import bpy
import importlib.util
import json
import math
import os
import random
import sys
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "environment", "mountain_arena")
SOURCE_DIR = os.path.join(ROOT, "source_art", "mountain_arena")
SHELL_GLB_PATH = os.path.join(OUT_DIR, "mountain_arena_shell.glb")
SHELL_OBJ_PATH = os.path.join(OUT_DIR, "mountain_arena_shell.obj")
BLEND_PATH = os.path.join(SOURCE_DIR, "mountain_arena.blend")
PREVIEW_PATH = os.path.join(OUT_DIR, "mountain_arena_preview.png")
BAMBOO_PREVIEW_PATH = os.path.join(OUT_DIR, "mountain_arena_bamboo_preview.png")
GARDEN_PREVIEW_PATH = os.path.join(OUT_DIR, "mountain_arena_garden_preview.png")
HALL_PREVIEW_PATH = os.path.join(OUT_DIR, "mountain_arena_hall_preview.png")
KIT_DIR = os.path.join(ROOT, "assets", "environment", "kits")
CATALOG_PATH = os.path.join(KIT_DIR, "catalog.json")
PLACEMENTS_PATH = os.path.join(OUT_DIR, "kit_placements.json")
# Blender (x, y, z) -> Godot (x, z, -y). Same remap glTF uses for Y-up.
GODOT_AXIS = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
random.seed(20260928)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
    pass
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(SOURCE_DIR, exist_ok=True)


def mat(name, color, roughness=0.75, metallic=0.0, emission=None):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    return m


STONE = mat("Stone Warm", (0.43, 0.39, 0.32), 0.92)
STONE_LIGHT = mat("Stone Light", (0.68, 0.63, 0.53), 0.9)
PLASTER = mat("Warm Plaster", (0.82, 0.76, 0.64), 0.88)
WOOD = mat("Dark Timber", (0.25, 0.095, 0.045), 0.72)
RED = mat("Cinnabar", (0.48, 0.055, 0.028), 0.62)
ROOF = mat("Blue Black Roof", (0.055, 0.085, 0.105), 0.68)
GOLD = mat("Old Gold", (0.62, 0.37, 0.09), 0.5, 0.18)
BAMBOO = mat("Bamboo", (0.24, 0.58, 0.18), 0.48)
BAMBOO_DARK = mat("Bamboo Dark", (0.13, 0.36, 0.10), 0.55)
BAMBOO_NODE = mat("Bamboo Node", (0.55, 0.40, 0.16), 0.62)
LEAF = mat("Leaf", (0.40, 0.66, 0.16), 0.42)
LEAF_YOUNG = mat("Leaf Young", (0.68, 0.78, 0.28), 0.38)
for foliage in (LEAF, LEAF_YOUNG):
    if hasattr(foliage, "use_backface_culling"):
        foliage.use_backface_culling = False
MOUNTAIN = mat("Distant Mountain", (0.20, 0.25, 0.22), 1.0)
WATER = mat("Water", (0.08, 0.30, 0.34), 0.2, 0.05)
LANTERN = mat("Lantern Glow", (0.9, 0.32, 0.07), 0.45, emission=(1.0, 0.18, 0.025))
BARK = mat("Bark", (0.28, 0.16, 0.08), 0.78)


def finish(obj, material, bevel=0.0):
    obj.data.materials.append(material)
    if bevel > 0:
        mod = obj.modifiers.new("Soft edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    return obj


def cube(name, loc, scale, material, bevel=0.0, rot=(0, 0, 0)):
    # Inputs use Godot coordinates; Blender is Z-up and its +Y maps to Godot -Z.
    bpy.ops.mesh.primitive_cube_add(location=(loc[0], -loc[2], loc[1]), rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (scale[0], scale[2], scale[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, material, bevel)


def cylinder(name, loc, radius, height, material, vertices=12, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=height, location=(loc[0], -loc[2], loc[1]))
    obj = bpy.context.object
    obj.name = name
    return finish(obj, material, bevel)


def roof(name, loc, width, depth, height):
    # Eaves and the ridge are shared kits. Scale is per building; the mesh is not copied into the shell.
    place_box_kit(name + "_slab", "roof_tile", loc, (width, 0.24, depth))
    place_box_kit(name + "_eave_front", "roof_tile", (loc[0], loc[1] - 0.10, loc[2] - depth * 0.48), (width + 1.2, 0.18, 0.45))
    place_box_kit(name + "_eave_back", "roof_tile", (loc[0], loc[1] - 0.10, loc[2] + depth * 0.48), (width + 1.2, 0.18, 0.45))
    place_box_kit(name + "_ridge", "roof_ridge", (loc[0], loc[1] + height, loc[2]), (width * 0.9, 0.22, 0.26))


def stairs(name, center, width, depth, count=6):
    for i in range(count):
        h = 0.12 * (i + 1)
        z = center[2] + depth * 0.5 - (i + 0.5) * depth / count
        cube(f"{name}_{i:02d}", (center[0], h * 0.5, z), (width, h, depth / count + 0.03), STONE_LIGHT, 0.025)


def image_mat(name, filename, roughness, repeat=True, bright=0.0, emission=0.0, tint=None):
    image = load_card_image(name, filename)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    tree = material.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    tex.extension = "REPEAT" if repeat else "CLIP"
    color = tex.outputs["Color"]
    if tint:
        grade_tint = tree.nodes.new("ShaderNodeVectorMath")
        grade_tint.operation = "MULTIPLY"
        grade_tint.inputs[1].default_value = tint
        tree.links.new(color, grade_tint.inputs[0])
        color = grade_tint.outputs[0]
    if bright:
        grade = tree.nodes.new("ShaderNodeBrightContrast")
        grade.inputs["Bright"].default_value = bright
        tree.links.new(color, grade.inputs["Color"])
        color = grade.outputs["Color"]
    tree.links.new(color, bsdf.inputs["Base Color"])
    if emission:
        tree.links.new(color, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    return material


def scale_uv(obj, su, sv):
    uv = obj.data.uv_layers.active
    if uv is None:
        return
    for loop in uv.data:
        loop.uv.x *= su
        loop.uv.y *= sv


def build_hip_roof(name, width, depth, rise, material, repeats, lift=1.6):
    # 歇山飞檐。Local Blender: +X is Godot +X, -Y is the court side, +Z is up.
    # Mid-eave sits at z=0. Ridge is +rise. Corners sweep up by about `lift`.
    bm = bmesh.new()
    nu, nv = 28, 14
    hw, hd = width * 0.5, depth * 0.5
    ridge_band = 0.58

    def height(ax, ay):
        side = max(0.0, (ax - ridge_band) / (1.0 - ridge_band))
        slope = max(side, ay) ** 0.82
        end = max(0.0, ax - 0.42) / 0.58
        edge = max(0.0, ay - 0.15) / 0.85
        return rise * (1.0 - slope) + lift * (end ** 1.55) * min(1.0, edge)

    grid = []
    for j in range(nv + 1):
        row = []
        ay = abs(j / nv * 2.0 - 1.0)
        y = -hd + depth * (j / nv)
        for i in range(nu + 1):
            ax = abs(i / nu * 2.0 - 1.0)
            x = -hw + width * (i / nu)
            row.append(bm.verts.new((x, y, height(ax, ay))))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm)
    extruded = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for vert in extruded["geom"]:
        if isinstance(vert, bmesh.types.BMVert):
            vert.co.z -= 0.16
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop in face.loops:
            x, y, _z = loop.vert.co
            loop[uv].uv = ((x / width + 0.5) * repeats, (y / depth + 0.5) * repeats)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    return mesh


def parent_keep(child, root):
    world = child.matrix_world.copy()
    child.parent = root
    child.matrix_world = world


def place_hierarchy(kit_id, name, root, x, z, y=0.0):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in walk_tree(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.object.duplicate()
    copy = bpy.context.view_layer.objects.active
    copy.name = name
    copy.location = (x, -z, y)
    copy["kit_id"] = kit_id
    INSTANCES.append(copy)
    return copy


def prepare_hall_assets():
    if "main_hall" in KIT_DEFS:
        return
    art = {
        "tile": image_mat("Hall Tile", "hall_tile.png", 0.58, bright=0.08, tint=(0.72, 0.84, 1.05)),
        "wood": image_mat("Hall Wood", "hall_wood.png", 0.52, bright=0.18, emission=0.06),
        "stone": image_mat("Hall Stone", "hall_stone.png", 0.84, bright=0.16),
        "lattice": image_mat("Hall Lattice", "hall_lattice.png", 0.45, repeat=False, emission=1.1),
        "plaque": image_mat("Hall Plaque", "hall_plaque.png", 0.4, repeat=False, emission=0.55),
        "banner": card_mat("Hall Banner", load_card_image("hall_banner", "hall_banner.png"), 0.45),
    }
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=1.0, depth=1.0, location=(0.0, 0.0, 40.0))
    pillar_obj = bpy.context.object
    pillar_mesh = pillar_obj.data
    pillar_mesh.name = "WoodPillar"
    pillar_mesh.materials.append(art["wood"])
    pillar_mesh.use_fake_user = True
    bpy.data.objects.remove(pillar_obj, do_unlink=True)
    register_kit("wood_pillar", "深色木柱，半径 1、高 1，原点在柱心", "center")
    KIT_DEFS["wood_pillar"]["mesh"] = pillar_mesh

    bm = bmesh.new()
    banner_w, banner_h = 0.82, 3.15
    banner_verts = [bm.verts.new(co) for co in ((-banner_w, 0.0, 0.0), (banner_w, 0.0, 0.0), (banner_w, 0.0, -banner_h), (-banner_w, 0.0, -banner_h))]
    banner_face = bm.faces.new(banner_verts)
    banner_uv = bm.loops.layers.uv.new("UVMap")
    for loop, coord in zip(banner_face.loops, ((0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0))):
        loop[banner_uv].uv = coord
    banner_mesh = bpy.data.meshes.new("MartialBanner")
    bm.to_mesh(banner_mesh)
    bm.free()
    banner_mesh.materials.append(art["banner"])
    banner_mesh.use_fake_user = True
    register_kit("martial_banner", "蓝色武字旗，原点在上方挂杆中心", "base")
    KIT_DEFS["martial_banner"]["mesh"] = banner_mesh

    parts = [
        cube("PalaceLanternCap", (0, -0.08, 0), (0.46, 0.12, 0.46), art["wood"]),
        cube("PalaceLanternBody", (0, -0.48, 0), (0.32, 0.58, 0.32), LANTERN),
        cube("PalaceLanternFrameX", (0, -0.48, 0), (0.4, 0.62, 0.06), art["wood"]),
        cube("PalaceLanternFrameZ", (0, -0.48, 0), (0.06, 0.62, 0.4), art["wood"]),
        cylinder("PalaceLanternTail", (0, -0.96, 0), 0.04, 0.28, art["wood"], 6),
    ]
    lantern_root = bpy.data.objects.new("PalaceLantern", None)
    bpy.context.scene.collection.objects.link(lantern_root)
    for part in parts:
        parent_keep(part, lantern_root)
    register_kit("palace_lantern", "檐下宫灯，原点在挂钩", "base")
    KIT_DEFS["palace_lantern"]["root"] = lantern_root
    KIT_DEFS["main_hall"] = {"description": "演武场北侧主殿，原点在台基中心地面", "origin": "base", "art": art}


def build_main_hall_master(width, depth):
    art = KIT_DEFS["main_hall"]["art"]
    root = bpy.data.objects.new("MainHall", None)
    bpy.context.scene.collection.objects.link(root)
    parts = []

    def add_box(name, loc, scale, material, repeat):
        obj = cube(name, loc, scale, material)
        scale_uv(obj, repeat[0], repeat[1])
        parts.append(obj)
        return obj

    add_box("HallPlatform", (0, 0.42, 0.15), (width, 0.84, depth + 0.8), art["stone"], (8, 3))
    add_box("HallWallBack", (0, 2.35, -depth * 0.5 + 0.7), (width - 2.4, 3.5, 0.45), art["wood"], (6, 2))
    add_box("HallWallLeft", (-width * 0.5 + 0.7, 2.35, -0.3), (0.45, 3.5, depth - 1.6), art["wood"], (2, 2))
    add_box("HallWallRight", (width * 0.5 - 0.7, 2.35, -0.3), (0.45, 3.5, depth - 1.6), art["wood"], (2, 2))
    front_face = depth * 0.5 - 0.2
    for index, px in enumerate((-0.9, 0.9)):
        add_box("HallDoor_%d" % index, (px, 2.15, front_face), (1.55, 2.85, 0.1), art["lattice"], (1, 1))
    for index, px in enumerate((-11.2, -7.2, 7.2, 11.2)):
        add_box("HallLattice_%d" % index, (px, 2.35, front_face), (2.5, 2.35, 0.1), art["lattice"], (1, 1))
    add_box("HallBeam", (0, 4.05, front_face + 0.05), (width - 1.4, 0.38, 0.62), art["wood"], (8, 1))
    for index, px in enumerate(range(-14, 15, 2)):
        add_box("HallBracket_%d" % index, (px, 4.42, front_face + 0.28), (0.62, 0.32, 0.95), art["wood"], (1, 1))
        add_box("HallBracketCap_%d" % index, (px, 4.68, front_face + 0.42), (0.95, 0.16, 0.55), art["wood"], (1, 1))
    rail_z = depth * 0.5 + 0.55
    for side, x0, x1 in ((-1, -width * 0.5 + 0.6, -3.8), (1, 3.8, width * 0.5 - 0.6)):
        span = x1 - x0
        mid = (x0 + x1) * 0.5
        add_box("HallRail_%d" % side, (mid, 1.28, rail_z), (span, 0.1, 0.1), art["wood"], (4, 1))
        add_box("HallRailLow_%d" % side, (mid, 0.95, rail_z), (span, 0.08, 0.08), art["wood"], (4, 1))
        post = x0
        post_index = 0
        while post <= x1 + 0.05:
            add_box("HallPost_%d_%d" % (side, post_index), (post, 1.12, rail_z), (0.1, 0.7, 0.1), art["wood"], (1, 1))
            post += 2.1
            post_index += 1
    plaque_bm = bmesh.new()
    plaque_verts = [plaque_bm.verts.new(co) for co in ((-2.7, 0.0, -0.62), (2.7, 0.0, -0.62), (2.7, 0.0, 0.62), (-2.7, 0.0, 0.62))]
    plaque_face = plaque_bm.faces.new(plaque_verts)
    plaque_uv = plaque_bm.loops.layers.uv.new("UVMap")
    for loop, coord in zip(plaque_face.loops, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
        loop[plaque_uv].uv = coord
    plaque_mesh = bpy.data.meshes.new("HallPlaque")
    plaque_bm.to_mesh(plaque_mesh)
    plaque_bm.free()
    plaque_mesh.materials.append(art["plaque"])
    plaque_obj = place_mesh("HallPlaque", plaque_mesh, (0, 3.45, depth * 0.5 + 0.35))
    parts.append(plaque_obj)
    lower = place_mesh("HallLowerRoof", build_hip_roof("HallLowerRoof", width + 4.0, depth + 3.2, 2.55, art["tile"], 9.0, lift=1.85), (0, 4.2, 0))
    upper = place_mesh("HallUpperRoof", build_hip_roof("HallUpperRoof", width - 8.0, depth - 1.2, 2.15, art["tile"], 6.0, lift=1.45), (0, 7.05, 0))
    parts.extend((lower, upper))
    add_box("HallClerestory", (0, 6.85, -0.15), (width - 10.5, 1.15, depth - 3.6), art["wood"], (5, 2))
    add_box("HallRidge", (0, 9.35, 0), (width * 0.28, 0.18, 0.22), GOLD, (1, 1))
    for index, px in enumerate((-3.4, -1.7, 0.0, 1.7, 3.4)):
        parts.append(cylinder("HallFinial_%d" % index, (px, 9.55, 0), 0.1, 0.32, GOLD, 8))
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(cylinder(
                "HallBell_%d_%d" % (sx, sz),
                (sx * (width * 0.5 + 1.5), 5.7, sz * (depth * 0.5 + 1.15)),
                0.08, 0.32, GOLD, 8,
            ))
    for part in parts:
        parent_keep(part, root)
    KIT_DEFS["main_hall"]["root"] = root
    return root


def hall(name, center, width, depth, tall=5.2):
    # Visual only. The blocking box stays in mountain_arena_layout.gd.
    prepare_hall_assets()
    root = build_main_hall_master(width, depth)
    x, _, z = center
    place_hierarchy("main_hall", name, root, x, z)
    front = z + depth * 0.5 - 0.05
    for px in (-14.0, -9.2, -5.2, -1.7, 1.7, 5.2, 9.2, 14.0):
        place_kit("wood_pillar", "%s_pillar_%d" % (name, int(px * 10)), KIT_DEFS["wood_pillar"]["mesh"], (x + px, 2.7, front), scale=(0.42, 0.42, 3.7))
        cube("%s_base_%d" % (name, int(px * 10)), (x + px, 1.02, front), (0.85, 0.36, 0.85), STONE, 0.02)
    for px, pz in ((-15.2, -1.6), (15.2, -1.6), (-15.2, 2.2), (15.2, 2.2)):
        place_kit("wood_pillar", "%s_side_%d_%d" % (name, int(px), int(pz * 10)), KIT_DEFS["wood_pillar"]["mesh"], (x + px, 2.7, z + pz), scale=(0.38, 0.38, 3.7))
    for px in (-3.6, 3.6):
        place_kit("martial_banner", "%s_banner_%d" % (name, int(px * 10)), KIT_DEFS["martial_banner"]["mesh"], (x + px, 3.95, front + 0.7))
    for px in (-7.4, -2.6, 2.6, 7.4):
        place_hierarchy("palace_lantern", "%s_lantern_%d" % (name, int(px * 10)), KIT_DEFS["palace_lantern"]["root"], x + px, front + 0.85, 3.85)
    for px in (-9.2, 9.2):
        place_hierarchy("palace_lantern", "%s_stair_lantern_%d" % (name, int(px)), KIT_DEFS["palace_lantern"]["root"], x + px, z + depth * 0.5 + 1.3, 1.85)


def pavilion(name, center):
    x, _, z = center
    cube(name + "_base", (x, 0.25, z), (8.2, 0.5, 10.0), STONE, 0.12)
    for px in (-3.2, 3.2):
        for pz in (-4.0, 4.0):
            place_pillar(name + f"_pillar_{px}_{pz}", (x + px, 2.35, z + pz), 0.24, 4.5)
    roof(name + "_roof", (x, 4.75, z), 9.5, 11.2, 0.38)
    for pz in (-4.0, 4.0):
        cube(name + f"_rail_{pz}", (x, 1.05, z + pz), (6.5, 0.8, 0.16), WOOD, 0.04)


def gate():
    for x in (-6.1, 6.1):
        cube(f"GateTower_{x}", (x, 2.5, 38), (8.0, 5.0, 6.4), PLASTER, 0.08)
        for px in (-2.8, 2.8):
            place_pillar(f"GatePillar_{x}_{px}", (x + px, 2.8, 34.7), 0.30, 5.2)
        roof(f"GateRoof_{x}", (x, 5.25, 38), 9.5, 7.6, 0.35)
    cube("GateBeam", (0, 5.0, 37.2), (8.5, 1.0, 1.0), WOOD, 0.08)
    cube("GatePlaque", (0, 5.0, 36.55), (4.4, 1.35, 0.18), GOLD, 0.05)
    roof("GateCenterRoof", (0, 6.1, 37.4), 11.0, 3.2, 0.3)


def stone_lantern(name, x, z):
    place_lantern(name, x, z)


def add_leaf(bm, origin, direction, length, width, droop, material_index):
    # Lanceolate card: pointed base and tip, widest near the middle, tip droops.
    d = direction.normalized()
    side = d.cross(Vector((0.0, 0.0, 1.0)))
    if side.length < 1e-5:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()

    def at(t, lateral):
        bulge = math.sin(t * math.pi) ** 0.55
        sag = Vector((0.0, 0.0, -droop * math.sin(t * math.pi)))
        return origin + d * (length * t) + side * (lateral * width * bulge) + sag

    base = bm.verts.new(at(0.0, 0.0))
    left = bm.verts.new(at(0.42, -1.0))
    right = bm.verts.new(at(0.42, 1.0))
    tip = bm.verts.new(at(1.0, 0.0))
    normal = (left.co - base.co).cross(right.co - base.co)
    if normal.length_squared < 1e-10:
        normal = Vector((0.0, 0.0, 1.0))
    normal.normalize()
    # A second shell keeps the leaf visible from both sides after OBJ import.
    shift = normal * 0.004
    copies = {}

    def shifted(vert):
        copy = copies.get(vert)
        if copy is None:
            copy = bm.verts.new(vert.co - shift)
            copies[vert] = copy
        return copy

    for loop in ((base, left, right), (left, tip, right)):
        face = bm.faces.new(loop)
        face.material_index = material_index
        face.smooth = False
        back = bm.faces.new(tuple(shifted(vert) for vert in reversed(loop)))
        back.material_index = material_index
        back.smooth = False


def add_cone(bm, material_index, **kwargs):
    # Blender 5.2 create_cone only returns vertices, so new faces are diffed here.
    existing = set(bm.faces)
    bmesh.ops.create_cone(bm, **kwargs)
    created = [face for face in bm.faces if face not in existing]
    for face in created:
        face.material_index = material_index
        face.smooth = True
    return created


def build_culm(name, height, radius, leaf_start, leaves_per_node, seed, culm_material):
    rng = random.Random(seed)
    bm = bmesh.new()
    segments = max(6, int(round(height / 0.7)))
    seg_h = height / segments
    for i in range(segments):
        t0 = i / segments
        t1 = (i + 1) / segments
        r1 = radius * (1.0 - 0.4 * t0)
        r2 = radius * (1.0 - 0.4 * t1)
        add_cone(
            bm, 0, cap_ends=True, cap_tris=True, segments=8,
            radius1=r1, radius2=r2, depth=seg_h,
            matrix=Matrix.Translation((0.0, 0.0, seg_h * (i + 0.5))),
        )
        if i == segments - 1:
            continue
        ring_r = r2 * 1.28
        add_cone(
            bm, 1, cap_ends=True, cap_tris=True, segments=8,
            radius1=ring_r, radius2=ring_r, depth=max(0.03, radius * 0.28),
            matrix=Matrix.Translation((0.0, 0.0, seg_h * (i + 1))),
        )
        if t1 < leaf_start:
            continue
        z = seg_h * (i + 1)
        for k in range(leaves_per_node):
            ang = (k / leaves_per_node) * math.tau + rng.uniform(-0.2, 0.2) + i * 0.55
            direction = Vector((math.cos(ang), math.sin(ang), rng.uniform(0.28, 0.85))).normalized()
            origin = Vector((math.cos(ang) * r2, math.sin(ang) * r2, z))
            twig_len = rng.uniform(0.12, 0.22)
            twig_dir = Vector((0.0, 0.0, 1.0)).rotation_difference(direction).to_matrix().to_4x4()
            add_cone(
                bm, 0, cap_ends=True, cap_tris=True, segments=5,
                radius1=radius * 0.16, radius2=radius * 0.07, depth=twig_len,
                matrix=Matrix.Translation(origin + direction * (twig_len * 0.5)) @ twig_dir,
            )
            leaf_origin = origin + direction * twig_len
            for branch in range(2):
                spread = ang + rng.uniform(-0.35, 0.35) + branch * 0.4
                leaf_dir = Vector((math.cos(spread), math.sin(spread), rng.uniform(0.15, 0.7))).normalized()
                length = rng.uniform(0.55, 1.15)
                add_leaf(
                    bm, leaf_origin, leaf_dir, length, length * rng.uniform(0.13, 0.2),
                    length * rng.uniform(0.12, 0.28), 3 if rng.random() < 0.3 else 2,
                )
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for material in (culm_material, BAMBOO_NODE, LEAF, LEAF_YOUNG):
        mesh.materials.append(material)
    return mesh


def build_leaf_card(name, material_index, material):
    bm = bmesh.new()
    add_leaf(bm, Vector((0.0, 0.0, 0.0)), Vector((1.0, 0.15, 0.2)), 1.0, 0.18, 0.16, material_index)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    return mesh


def build_rock():
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for face in bm.faces:
        face.smooth = True
    mesh = bpy.data.meshes.new("BambooRock")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(STONE)
    return mesh


KIT_DEFS = {}
INSTANCES = []
UNIT_MESHES = {}


def place_mesh(name, mesh, godot_xyz, rot=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0)):
    obj = bpy.data.objects.new(name, mesh)
    x, y, z = godot_xyz
    obj.location = (x, -z, y)
    obj.rotation_euler = rot
    obj.scale = scale
    bpy.context.scene.collection.objects.link(obj)
    return obj


def register_kit(kit_id, description, origin):
    KIT_DEFS.setdefault(kit_id, {"description": description, "origin": origin})


def place_kit(kit_id, name, mesh, godot_xyz, rot=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0)):
    obj = place_mesh(name, mesh, godot_xyz, rot, scale)
    obj["kit_id"] = kit_id
    INSTANCES.append(obj)
    return obj


def unit_cube(name, material):
    if name in UNIT_MESHES:
        return UNIT_MESHES[name]
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    UNIT_MESHES[name] = mesh
    return mesh


def unit_pillar():
    if "cinnabar_pillar" in UNIT_MESHES:
        return UNIT_MESHES["cinnabar_pillar"]
    mesh = bpy.data.meshes.new("CinnabarPillar")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=12, radius1=1.0, radius2=1.0, depth=1.0)
    for face in bm.faces:
        face.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(RED)
    UNIT_MESHES["cinnabar_pillar"] = mesh
    return mesh


def place_box_kit(name, kit_id, godot_loc, godot_size):
    material = GOLD if kit_id == "roof_ridge" else ROOF
    mesh = unit_cube(kit_id, material)
    register_kit(kit_id, "1米见方的屋面构件，按建筑尺寸缩放", "center")
    KIT_DEFS[kit_id]["mesh"] = mesh
    # Blender scale is (Godot X, Godot Z, Godot Y) because the cube is authored Z-up.
    return place_kit(kit_id, name, mesh, godot_loc, scale=(godot_size[0], godot_size[2], godot_size[1]))


def place_pillar(name, godot_center, radius, height):
    mesh = unit_pillar()
    register_kit("cinnabar_pillar", "朱红柱，网格半径 1、高 1，原点在柱心", "center")
    KIT_DEFS["cinnabar_pillar"]["mesh"] = mesh
    return place_kit("cinnabar_pillar", name, mesh, godot_center, scale=(radius, radius, height))


def walk_tree(obj):
    yield obj
    for child in list(obj.children):
        yield from walk_tree(child)


def stash_master(root):
    masters = bpy.data.collections.get("KitMasters")
    if masters is None:
        masters = bpy.data.collections.new("KitMasters")
    for obj in walk_tree(root):
        for coll in list(obj.users_collection):
            coll.objects.unlink(obj)
        if obj.name not in masters.objects:
            masters.objects.link(obj)
    return masters


def build_lantern_master():
    if "stone_lantern" in KIT_DEFS and KIT_DEFS["stone_lantern"].get("root"):
        return KIT_DEFS["stone_lantern"]["root"]
    parts = [
        cube("LanternMaster_foot", (0, 0.13, 0), (1.15, 0.26, 1.15), STONE_LIGHT, 0.08),
        cylinder("LanternMaster_stem", (0, 0.65, 0), 0.20, 0.9, STONE_LIGHT, 8, 0.025),
        cube("LanternMaster_lamp", (0, 1.18, 0), (0.75, 0.68, 0.75), STONE_LIGHT, 0.06),
        cube("LanternMaster_glow", (0, 1.18, 0), (0.48, 0.42, 0.48), LANTERN, 0.025),
        cylinder("LanternMaster_cap", (0, 1.62, 0), 0.62, 0.16, STONE_LIGHT, 8, 0.03),
    ]
    root = bpy.data.objects.new("LanternMaster", None)
    bpy.context.scene.collection.objects.link(root)
    for part in parts:
        world = part.matrix_world.copy()
        part.parent = root
        part.matrix_world = world
    register_kit("stone_lantern", "石灯整件，原点在地面中心", "base")
    KIT_DEFS["stone_lantern"]["root"] = root
    return root


def place_lantern(name, x, z):
    root = build_lantern_master()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in walk_tree(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.object.duplicate()
    copy = bpy.context.view_layer.objects.active
    copy.name = name
    copy.location = (x, -z, 0.0)
    copy["kit_id"] = "stone_lantern"
    INSTANCES.append(copy)
    return copy


def _check_kit_transforms(placements):
    roof = next(item for item in placements if item["kit"] == "roof_tile" and abs(item["position"][0] + 43) < 0.3 and abs(item["position"][1] - 4.75) < 0.15)
    if abs(roof["position"][2] - 2) > 0.4:
        raise SystemExit("KIT_TRANSFORM roof pos=%s" % roof["position"])
    pillar = next(item for item in placements if item["kit"] == "cinnabar_pillar" and abs(item["scale"][1] - 4.5) < 0.05)
    if abs(pillar["scale"][0] - 0.24) > 0.02 or abs(pillar["scale"][2] - 0.24) > 0.02:
        raise SystemExit("KIT_TRANSFORM pillar scale=%s" % pillar["scale"])
    lantern = next(item for item in placements if item["kit"] == "stone_lantern" and abs(abs(item["position"][0]) - 29) < 0.05)
    if abs(lantern["position"][1]) > 0.05 or abs(abs(lantern["position"][2]) - 18) > 0.05:
        raise SystemExit("KIT_TRANSFORM lantern pos=%s" % lantern["position"])


def godot_placement(obj):
    converted = GODOT_AXIS @ obj.matrix_world @ GODOT_AXIS.inverted()
    loc, quat, scale = converted.decompose()
    return {
        "kit": obj["kit_id"],
        "position": [round(loc.x, 4), round(loc.y, 4), round(loc.z, 4)],
        "quaternion": [round(quat.x, 5), round(quat.y, 5), round(quat.z, 5), round(quat.w, 5)],
        "scale": [round(abs(scale.x), 4), round(abs(scale.y), 4), round(abs(scale.z), 4)],
    }


def export_selected_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)


def export_kits():
    os.makedirs(KIT_DIR, exist_ok=True)
    scene_col = bpy.context.scene.collection
    masters = bpy.data.collections.get("KitMasters")
    masters_linked = masters is not None and masters.name in [c.name for c in scene_col.children]
    if masters and not masters_linked:
        scene_col.children.link(masters)
    for kit_id, spec in KIT_DEFS.items():
        bpy.ops.object.select_all(action="DESELECT")
        temp = None
        if spec.get("root"):
            for obj in walk_tree(spec["root"]):
                obj.hide_set(False)
                obj.select_set(True)
            bpy.context.view_layer.objects.active = spec["root"]
        else:
            temp = bpy.data.objects.new(kit_id, spec["mesh"])
            scene_col.objects.link(temp)
            temp.select_set(True)
            bpy.context.view_layer.objects.active = temp
        export_selected_glb(os.path.join(KIT_DIR, kit_id + ".glb"))
        if temp is not None:
            bpy.data.objects.remove(temp, do_unlink=True)
    if masters and not masters_linked:
        scene_col.children.unlink(masters)


BAMBOO_LIB = {}


def prepare_bamboo():
    if BAMBOO_LIB:
        return
    specs = (
        ("tall", "bamboo_culm_tall", "高竹竿，叶较疏，原点在根部", lambda: build_culm("CulmTall", 6.8, 0.105, 0.46, 3, 11, BAMBOO)),
        ("tall_b", "bamboo_culm_tall_b", "更高的疏叶竹竿，原点在根部", lambda: build_culm("CulmTallB", 7.4, 0.09, 0.4, 2, 29, BAMBOO)),
        ("mid", "bamboo_culm_mid", "中等密叶竹竿，原点在根部", lambda: build_culm("CulmMid", 5.4, 0.085, 0.36, 3, 47, BAMBOO_DARK)),
        ("mid_b", "bamboo_culm_mid_b", "较矮的密叶竹竿，原点在根部", lambda: build_culm("CulmMidB", 4.8, 0.075, 0.42, 3, 71, BAMBOO)),
        ("slim", "bamboo_culm_slim", "细竹竿，原点在根部", lambda: build_culm("CulmSlim", 6.1, 0.06, 0.5, 2, 97, BAMBOO)),
        ("shoot", "bamboo_culm_shoot", "矮笋，原点在根部", lambda: build_culm("CulmShoot", 1.45, 0.032, 0.48, 2, 113, BAMBOO_DARK)),
        ("leaf", "bamboo_leaf", "一片落叶，叶尖朝局部 +X", lambda: build_leaf_card("GroundLeaf", 0, LEAF)),
        ("leaf_young", "bamboo_leaf_young", "偏黄的落叶，叶尖朝局部 +X", lambda: build_leaf_card("GroundLeafYoung", 0, LEAF_YOUNG)),
        ("rock", "bamboo_rock", "半径 1 的碎石，原点在球心", lambda: build_rock()),
    )
    for key, kit_id, description, builder in specs:
        mesh = builder()
        BAMBOO_LIB[key] = mesh
        register_kit(kit_id, description, "base" if key != "rock" else "center")
        KIT_DEFS[kit_id]["mesh"] = mesh
        BAMBOO_LIB["kit:" + key] = kit_id


def bamboo_cluster(name, x, z, kind="grove"):
    # Decorative only. Gameplay collision stays in mountain_arena_layout.gd.
    prepare_bamboo()
    if kind == "single":
        stems, shoots, spread, rocks, leaves = 1, 2, 0.35, 3, 8
    elif kind == "clump":
        stems, shoots, spread, rocks, leaves = 5, 4, 1.15, 4, 12
    else:
        stems, shoots, spread, rocks, leaves = 12, 7, 1.85, 6, 18
    culms = ("tall", "tall_b", "mid", "mid_b", "slim")
    for i in range(stems):
        ox = random.uniform(-spread, spread)
        oz = random.uniform(-spread, spread)
        yaw = random.uniform(0.0, math.tau)
        tilt = random.uniform(0.02, 0.09)
        scale = random.uniform(0.86, 1.12)
        kind = culms[i % len(culms)]
        place_kit(
            BAMBOO_LIB["kit:" + kind], f"{name}_culm_{i}", BAMBOO_LIB[kind], (x + ox, 0.0, z + oz),
            rot=(tilt * math.cos(yaw), tilt * math.sin(yaw), yaw), scale=(scale, scale, scale),
        )
    for i in range(shoots):
        ox = random.uniform(-spread * 0.65, spread * 0.65)
        oz = random.uniform(-spread * 0.65, spread * 0.65)
        place_kit(
            BAMBOO_LIB["kit:shoot"], f"{name}_shoot_{i}", BAMBOO_LIB["shoot"], (x + ox, 0.0, z + oz),
            rot=(0.0, 0.0, random.uniform(0.0, math.tau)),
            scale=(1.0, 1.0, random.uniform(0.7, 1.35)),
        )
    for i in range(rocks):
        ox = random.uniform(-spread * 0.8, spread * 0.8)
        oz = random.uniform(-spread * 0.8, spread * 0.8)
        sx = random.uniform(0.16, 0.34)
        sy = random.uniform(0.14, 0.28)
        sz = random.uniform(0.08, 0.16)
        place_kit(
            BAMBOO_LIB["kit:rock"], f"{name}_rock_{i}", BAMBOO_LIB["rock"], (x + ox, sz * 0.45, z + oz),
            rot=(random.uniform(0.0, 0.4), random.uniform(0.0, 0.4), random.uniform(0.0, math.tau)),
            scale=(sx, sy, sz),
        )
    for i in range(leaves):
        ox = random.uniform(-spread, spread)
        oz = random.uniform(-spread, spread)
        leaf_key = "leaf_young" if i % 4 == 0 else "leaf"
        length = random.uniform(0.28, 0.62)
        place_kit(
            BAMBOO_LIB["kit:" + leaf_key], f"{name}_ground_{i}", BAMBOO_LIB[leaf_key], (x + ox, 0.02, z + oz),
            rot=(random.uniform(-0.2, 0.2), random.uniform(-0.15, 0.15), random.uniform(0.0, math.tau)),
            scale=(length, length, length),
        )


def _mix(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def _edge_alpha(signed, texels):
    # signed > 0 is inside. The image spans -1..1, so one pixel is 2/texels.
    px = 2.0 / texels
    return max(0.0, min(1.0, signed / px + 0.5))


def _speck(u, v):
    n = math.sin(u * 127.1 + v * 311.7) * 43758.5453
    return n - math.floor(n)


def paint_image(name, width, height, painter):
    image = bpy.data.images.new(name, width, height, alpha=True, float_buffer=False)
    image.colorspace_settings.name = "sRGB"
    image.alpha_mode = "STRAIGHT"
    buf = array.array("f", [0.0]) * (width * height * 4)
    for y in range(height):
        v = (y + 0.5) / height * 2.0 - 1.0
        row = y * width
        for x in range(width):
            u = (x + 0.5) / width * 2.0 - 1.0
            r, g, b, a = painter(u, v)
            i = (row + x) * 4
            buf[i] = r
            buf[i + 1] = g
            buf[i + 2] = b
            buf[i + 3] = a
    image.pixels.foreach_set(buf)
    image.update()
    folder = os.path.join(KIT_DIR, "textures")
    os.makedirs(folder, exist_ok=True)
    image.filepath_raw = os.path.join(folder, name + ".png")
    image.file_format = "PNG"
    image.save()
    return image


def card_mat(name, image, roughness):
    # Alpha is clipped in the shader so glTF exports MASK and both sides stay visible.
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "BLENDED"
    if hasattr(material, "use_transparent_shadow"):
        material.use_transparent_shadow = True
    tree = material.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    specular = bsdf.inputs.get("Specular IOR Level")
    if specular is not None:
        specular.default_value = 0.16
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    tex.extension = "CLIP"
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    clip = tree.nodes.new("ShaderNodeMath")
    clip.operation = "GREATER_THAN"
    clip.inputs[1].default_value = 0.5
    tree.links.new(tex.outputs["Alpha"], clip.inputs[0])
    tree.links.new(clip.outputs["Value"], bsdf.inputs["Alpha"])
    return material


def paint_maple(u, v, vein, base, tip):
    y = v * 0.92 + 0.08
    ang = math.atan2(u, max(y, -0.2))
    rad = math.hypot(u, max(y, 0.0))
    lobe = abs(math.cos(ang * 2.5)) ** 0.5
    radius = (0.16 + 0.78 * lobe) * (0.94 + 0.06 * abs(math.cos(ang * 17.0)))
    signed = radius - rad
    stem = 0.055 - abs(u) if -0.95 < v < -0.02 else -1.0
    signed = max(signed if y > -0.05 else -1.0, stem)
    alpha = _edge_alpha(signed, 160)
    if alpha <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    t = max(0.0, min(1.0, (y + 0.2) / 1.15))
    color = _mix(base, tip, t * (0.65 + 0.35 * lobe))
    if abs(u) < 0.035 + 0.02 * max(y, 0.0) or abs(math.sin(ang * 2.5)) < 0.07:
        color = _mix(color, vein, 0.55)
    color = _mix(color, vein, (_speck(u * 5.0, v * 5.0) - 0.55) * 0.18)
    return (*color, alpha)


def paint_sprig(u, v, dark, mid, light, count, reach):
    alpha = 0.0
    color = mid
    if abs(u) < 0.03 and -0.92 < v < 0.05:
        alpha = _edge_alpha(0.03 - abs(u), 160)
        color = dark
    for i in range(count):
        ang = (i - (count - 1) * 0.5) * 0.42
        origin = -0.35 + i * (0.62 / max(count - 1, 1))
        dx = u
        dy = v - origin
        ca, sa = math.cos(ang), math.sin(ang)
        lx = dx * ca + dy * sa
        ly = -dx * sa + dy * ca
        ly = (ly - 0.08) / reach
        lx = lx / (reach * 0.42)
        e = abs(lx) ** 1.65 + abs(ly) ** 2.15
        signed = 1.0 - e
        leaf_alpha = _edge_alpha(signed * reach * 0.5, 160) if ly > -0.15 else 0.0
        if leaf_alpha > alpha:
            alpha = leaf_alpha
            tone = max(0.0, min(1.0, (ly + 0.2) * 0.7))
            color = _mix(dark, light, tone)
            if abs(lx) < 0.12:
                color = _mix(color, dark, 0.65)
            color = _mix(color, mid, (_speck(u * 6.0 + i, v * 6.0) - 0.5) * 0.2)
    if alpha <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    return (*color, alpha)


def paint_blossom(u, v, petals, base, edge, throat, spread):
    ang = math.atan2(u, v + 0.02)
    rad = math.hypot(u, v)
    wave = 0.5 + 0.5 * math.cos(ang * petals)
    radius = 0.12 + spread * (0.25 + 0.62 * wave ** 1.2)
    alpha = _edge_alpha(radius - rad, 128)
    if rad < 0.09:
        alpha = max(alpha, _edge_alpha(0.09 - rad, 128))
        return (*throat, alpha)
    if alpha <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    color = _mix(base, edge, max(0.0, min(1.0, rad / max(radius, 0.01))))
    if abs(math.sin(ang * petals)) < 0.08:
        color = _mix(color, throat, 0.4)
    if 0.1 < rad < 0.22 and abs((ang + math.pi) % (math.tau / petals) - math.pi / petals) < 0.05:
        color = (0.93, 0.78, 0.18)
    return (*color, alpha)


def paint_cluster(u, v, blossom):
    spots = ((0.0, 0.08, 0.36), (-0.46, -0.22, 0.30), (0.42, -0.18, 0.32), (-0.18, 0.5, 0.28), (0.36, 0.46, 0.27), (0.02, -0.55, 0.24))
    best = (0.0, 0.0, 0.0, 0.0)
    for sx, sy, scale in spots:
        sample = blossom((u - sx) / scale, (v - sy) / scale)
        if sample[3] > best[3]:
            best = sample
    return best


def paint_peony(u, v, inner, mid, outer):
    best_a = 0.0
    best_col = mid
    for count, ring, rx, ry, col, phase in (
        (11, 0.52, 0.20, 0.36, outer, 0.0),
        (8, 0.30, 0.16, 0.28, mid, 0.2),
        (6, 0.12, 0.11, 0.18, inner, 0.45),
    ):
        for i in range(count):
            ang = phase + i / count * math.tau
            cx = math.sin(ang) * ring
            cy = math.cos(ang) * ring * 0.88
            dx = u - cx
            dy = v - cy
            ca, sa = math.cos(ang), math.sin(ang)
            lx = dx * ca + dy * sa
            ly = -dx * sa + dy * ca
            e = (lx / rx) ** 2 + ((ly - ry * 0.1) / ry) ** 2
            px = (2.0 / 160) / min(rx, ry)
            alpha = max(0.0, min(1.0, (1.0 - e) / px + 0.5))
            if alpha > best_a:
                best_a = alpha
                best_col = tuple(channel * (0.78 + 0.22 * max(0.0, 1.0 - e)) for channel in col)
    rad = math.hypot(u, v)
    if rad < 0.11:
        alpha = max(best_a, _edge_alpha((0.11 - rad) * 0.2, 160))
        return (*_mix(inner, (0.78, 0.62, 0.16), 0.45 if rad < 0.06 else 0.15), alpha)
    if best_a <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    return (*best_col, best_a)


def add_card(bm, center, axis_u, axis_v, width, height, mat_index):
    axis_u = axis_u.normalized()
    axis_v = axis_v.normalized()
    if abs(axis_u.dot(axis_v)) > 0.98:
        axis_u = axis_v.cross(Vector((0.0, 0.0, 1.0)))
        if axis_u.length < 1e-5:
            axis_u = Vector((1.0, 0.0, 0.0))
        axis_u.normalize()
    hw = width * 0.5
    hh = height * 0.5
    verts = [
        bm.verts.new(center - axis_u * hw - axis_v * hh),
        bm.verts.new(center + axis_u * hw - axis_v * hh),
        bm.verts.new(center + axis_u * hw + axis_v * hh),
        bm.verts.new(center - axis_u * hw + axis_v * hh),
    ]
    face = bm.faces.new(verts)
    face.material_index = mat_index
    face.smooth = False
    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for loop, uv in zip(face.loops, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
        loop[uv_layer].uv = uv


def add_leaf_card(bm, origin, tip_dir, length, width, mat_index, roll):
    tip = tip_dir.normalized()
    side = tip.cross(Vector((0.0, 0.0, 1.0)))
    if side.length < 1e-5:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    normal = (side * math.sin(roll) + tip.cross(side) * math.cos(roll)).normalized()
    axis_u = tip.cross(normal).normalized()
    add_card(bm, origin + tip * (length * 0.5), axis_u, tip, width, length, mat_index)


def load_card_image(name, filename):
    path = os.path.join(KIT_DIR, "textures", filename)
    image = bpy.data.images.load(path, check_existing=True)
    image.name = name
    image.alpha_mode = "STRAIGHT"
    return image


def add_facing_card(bm, center, normal, size, mat_index, twist):
    # The card faces out of the bush so the flower texture is seen from the side, not edge-on.
    normal = normal.normalized()
    up = Vector((math.sin(twist) * 0.35, math.cos(twist) * 0.35, 1.0))
    axis_u = up.cross(normal)
    if axis_u.length < 1e-4:
        axis_u = Vector((1.0, 0.0, 0.0))
    axis_u.normalize()
    axis_v = normal.cross(axis_u).normalized()
    add_card(bm, center, axis_u, axis_v, size, size, mat_index)


def build_azalea(name, seed, height, radius, cards, materials):
    rng = random.Random(seed)
    bm = bmesh.new()
    scale = max(radius / 1.25, 0.45)
    for _index in range(cards):
        cos_e = 0.18 + 0.82 * (rng.random() ** 0.75)
        sin_e = math.sqrt(max(0.0, 1.0 - cos_e * cos_e))
        ang = rng.uniform(0.0, math.tau)
        shell = rng.uniform(0.9, 1.02)
        x = math.cos(ang) * sin_e * radius * shell
        y = math.sin(ang) * sin_e * radius * 0.92 * shell
        z = max(0.06, cos_e * height * shell)
        outward = Vector((math.cos(ang), math.sin(ang) * 0.92, 0.22))
        roll = rng.random()
        if roll < 0.72:
            mat_index = 4
            size = rng.uniform(0.3, 0.46) * scale
        elif roll < 0.86:
            mat_index = 3
            size = rng.uniform(0.11, 0.17) * scale
        else:
            mat_index = 1
            size = rng.uniform(0.18, 0.28) * scale
        add_facing_card(bm, Vector((x, y, z)), outward, max(size, 0.09), mat_index, rng.uniform(-0.35, 0.35))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for material in materials:
        mesh.materials.append(material)
    return mesh


def add_bloom(bm, center, size, mat_index, rng, form):
    count = 3 if form == "peony" else 2
    for i in range(count):
        yaw = rng.uniform(0.0, math.tau)
        tilt = rng.uniform(0.35, 0.95) if form == "hedge" else rng.uniform(0.5, 1.3)
        normal = Vector((math.sin(tilt) * math.cos(yaw), math.sin(tilt) * math.sin(yaw), math.cos(tilt)))
        axis_u = Vector((0.0, 0.0, 1.0)).cross(normal)
        if axis_u.length < 1e-4:
            axis_u = Vector((1.0, 0.0, 0.0))
        axis_u.normalize()
        axis_v = normal.cross(axis_u).normalized()
        add_card(bm, center + normal * (0.006 * i), axis_u, axis_v, size, size, mat_index)


def add_stem(bm, base, height, radius, lean):
    direction = Vector((lean[0], lean[1], height))
    length = max(direction.length, 0.05)
    direction.normalize()
    quat = Vector((0.0, 0.0, 1.0)).rotation_difference(direction)
    add_cone(
        bm, 0, cap_ends=True, cap_tris=True, segments=6,
        radius1=radius, radius2=radius * 0.28, depth=length,
        matrix=Matrix.Translation(base + direction * (length * 0.5)) @ quat.to_matrix().to_4x4(),
    )


def sample_foliage(rng, form, height, radius, on_shell):
    if form == "hedge":
        face = rng.randrange(5)
        along = rng.uniform(-radius, radius)
        depth = rng.uniform(-radius * 0.42, radius * 0.42)
        if face == 0:
            pos = Vector((along, depth, height * rng.uniform(0.78, 1.08)))
            outward = Vector((0.0, 0.0, 1.0))
        elif face < 3:
            side = 1.0 if face == 1 else -1.0
            pos = Vector((side * radius * rng.uniform(0.82, 1.06), depth, height * rng.uniform(0.15, 0.95)))
            outward = Vector((side, 0.0, 0.35))
        else:
            pos = Vector((along, radius * 0.42 * (1.0 if rng.random() < 0.5 else -1.0), height * rng.uniform(0.2, 0.95)))
            outward = Vector((0.0, 1.0 if pos.y > 0 else -1.0, 0.3))
        return pos, outward
    ang = rng.uniform(0.0, math.tau)
    if form == "maple":
        z = height * rng.uniform(0.5, 1.05)
        rad = radius * rng.uniform(0.15, 1.0) * (0.35 + 0.7 * min(z / height, 1.0))
        pos = Vector((math.cos(ang) * rad, math.sin(ang) * rad * 0.82, z))
        outward = Vector((math.cos(ang), math.sin(ang), rng.uniform(-0.2, 0.35)))
        return pos, outward
    # Crown leaves radiate. A few lower cards point up so the stems stay covered.
    if rng.random() < 0.28:
        z_frac = rng.uniform(0.1, 0.42)
        rad_frac = math.sqrt(rng.random()) * 0.45
        outward = Vector((math.cos(ang) * 0.3, math.sin(ang) * 0.3, 1.0))
    else:
        z_frac = rng.uniform(0.32, 1.02)
        rad_frac = math.sqrt(rng.random()) * (1.0 if on_shell else 0.6)
        outward = Vector((math.cos(ang), math.sin(ang) * 0.85, rng.uniform(0.05, 0.5)))
    pos = Vector((math.cos(ang) * radius * rad_frac, math.sin(ang) * radius * 0.85 * rad_frac, height * z_frac))
    return pos, outward


def build_plant(name, seed, form, height, radius, stems, leaves, flowers, materials):
    # Alpha-cutout cards. Each leaf card is a sprig or a maple leaf; each flower card is a whole bloom.
    if form == "azalea":
        return build_azalea(name, seed, height, radius, leaves, materials)
    rng = random.Random(seed)
    bm = bmesh.new()
    if form != "hedge":
        for index in range(stems):
            ang = index / max(stems, 1) * math.tau + rng.uniform(-0.3, 0.3)
            spread = radius * (0.42 if form == "maple" else 0.18)
            lean = (math.cos(ang) * spread, math.sin(ang) * spread * 0.6)
            add_stem(bm, Vector((lean[0] * 0.15, lean[1] * 0.15, 0.0)), height * rng.uniform(0.45, 0.95), 0.035 + radius * 0.03, lean)
    for _index in range(leaves):
        pos, outward = sample_foliage(rng, form, height, radius, rng.random() < 0.8)
        if outward.length < 1e-5:
            outward = Vector((0.0, 0.0, 1.0))
        if form == "maple":
            length = rng.uniform(0.36, 0.66)
            width = length * rng.uniform(0.92, 1.08)
        elif form == "hedge":
            length = rng.uniform(0.22, 0.40)
            width = length * 0.72
        elif form == "peony":
            length = rng.uniform(0.24, 0.42)
            width = length * 0.78
        else:
            length = rng.uniform(0.20, 0.36)
            width = length * 0.7
        mat_index = 1 if rng.random() < 0.72 else 2
        add_leaf_card(bm, pos, outward, length, width, mat_index, rng.uniform(-1.1, 1.1))
    for index in range(flowers):
        if form == "peony":
            ang = index / max(flowers, 1) * math.tau
            pos = Vector((
                math.cos(ang) * radius * rng.uniform(0.12, 0.68),
                math.sin(ang) * radius * 0.62,
                rng.uniform(height * 0.48, height * 0.98),
            ))
            size = rng.uniform(0.28, 0.44)
        elif form == "hedge":
            pos = Vector((
                rng.uniform(-radius * 0.92, radius * 0.92),
                rng.uniform(-radius * 0.32, radius * 0.32),
                height * rng.uniform(0.72, 1.08),
            ))
            size = rng.uniform(0.14, 0.24)
        else:
            pos, _outward = sample_foliage(rng, form, height, radius, True)
            pos.z = max(pos.z, height * 0.4)
            size = rng.uniform(0.12, 0.2)
        add_bloom(bm, pos, size, 3 if rng.random() < 0.62 else 4, rng, form)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for material in materials:
        mesh.materials.append(material)
    return mesh


def prepare_garden():
    if "maple_large" in KIT_DEFS:
        return
    maple_red = paint_image("maple_red", 160, 160, lambda u, v: paint_maple(u, v, (0.32, 0.05, 0.03), (0.55, 0.08, 0.05), (0.93, 0.28, 0.06)))
    maple_orange = paint_image("maple_orange", 160, 160, lambda u, v: paint_maple(u, v, (0.45, 0.12, 0.03), (0.78, 0.24, 0.05), (0.96, 0.55, 0.1)))
    azalea_leaf = paint_image("azalea_sprig", 160, 160, lambda u, v: paint_sprig(u, v, (0.08, 0.2, 0.05), (0.16, 0.38, 0.1), (0.32, 0.58, 0.16), 5, 0.62))
    azalea_leaf_b = paint_image("azalea_sprig_deep", 160, 160, lambda u, v: paint_sprig(u, v, (0.05, 0.16, 0.04), (0.1, 0.28, 0.07), (0.2, 0.42, 0.1), 4, 0.55))
    pink_leaf = paint_image("pink_sprig", 160, 160, lambda u, v: paint_sprig(u, v, (0.1, 0.22, 0.05), (0.2, 0.4, 0.1), (0.45, 0.62, 0.18), 5, 0.58))
    hedge_green = paint_image("hedge_sprig", 128, 128, lambda u, v: paint_sprig(u, v, (0.06, 0.18, 0.04), (0.14, 0.34, 0.08), (0.28, 0.5, 0.12), 6, 0.5))
    hedge_red = paint_image("hedge_red_sprig", 128, 128, lambda u, v: paint_sprig(u, v, (0.28, 0.04, 0.04), (0.52, 0.08, 0.07), (0.72, 0.16, 0.1), 5, 0.52))
    peony_leaf = paint_image("peony_sprig", 160, 160, lambda u, v: paint_sprig(u, v, (0.06, 0.16, 0.04), (0.12, 0.32, 0.08), (0.24, 0.48, 0.12), 3, 0.72))
    azalea_flower = paint_image("azalea_flower", 128, 128, lambda u, v: paint_blossom(u, v, 5, (0.78, 0.16, 0.38), (0.98, 0.55, 0.68), (0.62, 0.1, 0.28), 0.95))
    azalea_flower_deep = paint_image("azalea_flower_deep", 128, 128, lambda u, v: paint_blossom(u, v, 5, (0.62, 0.08, 0.32), (0.9, 0.32, 0.55), (0.42, 0.05, 0.2), 0.9))
    pink_flower = paint_image("pink_flower", 128, 128, lambda u, v: paint_blossom(u, v, 5, (0.9, 0.45, 0.6), (0.99, 0.78, 0.84), (0.72, 0.22, 0.42), 0.88))
    pink_flower_deep = paint_image("pink_flower_deep", 128, 128, lambda u, v: paint_blossom(u, v, 5, (0.78, 0.22, 0.45), (0.96, 0.55, 0.7), (0.55, 0.1, 0.28), 0.86))
    white_cluster = paint_image("white_cluster", 128, 128, lambda u, v: paint_cluster(u, v, lambda pu, pv: paint_blossom(pu, pv, 5, (0.9, 0.86, 0.78), (0.98, 0.97, 0.93), (0.95, 0.82, 0.28), 0.8)))
    pink_cluster = paint_image("pink_cluster", 128, 128, lambda u, v: paint_cluster(u, v, lambda pu, pv: paint_blossom(pu, pv, 5, (0.9, 0.45, 0.6), (0.99, 0.75, 0.82), (0.7, 0.2, 0.4), 0.78)))
    peony_white = paint_image("peony_white", 160, 160, lambda u, v: paint_peony(u, v, (0.96, 0.78, 0.82), (0.98, 0.94, 0.9), (0.97, 0.95, 0.92)))
    peony_pink = paint_image("peony_pink", 160, 160, lambda u, v: paint_peony(u, v, (0.72, 0.18, 0.36), (0.94, 0.48, 0.62), (0.98, 0.75, 0.82)))
    peony_red = paint_image("peony_red", 160, 160, lambda u, v: paint_peony(u, v, (0.38, 0.04, 0.07), (0.7, 0.08, 0.12), (0.88, 0.18, 0.2)))
    cards = {
        "maple_red": card_mat("Maple Red Card", maple_red, 0.58),
        "maple_orange": card_mat("Maple Orange Card", maple_orange, 0.58),
        "azalea_leaf": card_mat("Azalea Leaf Card", azalea_leaf, 0.62),
        "azalea_leaf_b": card_mat("Azalea Leaf Deep Card", azalea_leaf_b, 0.62),
        "pink_leaf": card_mat("Pink Leaf Card", pink_leaf, 0.62),
        "hedge_green": card_mat("Hedge Green Card", hedge_green, 0.66),
        "hedge_red": card_mat("Hedge Red Card", hedge_red, 0.66),
        "peony_leaf": card_mat("Peony Leaf Card", peony_leaf, 0.6),
        "azalea_flower": card_mat("Azalea Flower Card", azalea_flower, 0.4),
        "azalea_flower_deep": card_mat("Azalea Flower Deep Card", azalea_flower_deep, 0.4),
        "pink_flower": card_mat("Pink Flower Card", pink_flower, 0.38),
        "pink_flower_deep": card_mat("Pink Flower Deep Card", pink_flower_deep, 0.38),
        "white_cluster": card_mat("White Cluster Card", white_cluster, 0.4),
        "pink_cluster": card_mat("Pink Cluster Card", pink_cluster, 0.4),
        "peony_white": card_mat("Peony White Card", peony_white, 0.34),
        "peony_pink": card_mat("Peony Pink Card", peony_pink, 0.34),
        "peony_red": card_mat("Peony Red Card", peony_red, 0.34),
        "azalea_ai_flower": card_mat("Azalea AI Flower", load_card_image("azalea_ai_flower", "azalea_ai_flower.png"), 0.42),
        "azalea_ai_sprig": card_mat("Azalea AI Sprig", load_card_image("azalea_ai_sprig", "azalea_ai_sprig.png"), 0.55),
        "azalea_ai_cluster": card_mat("Azalea AI Cluster", load_card_image("azalea_ai_cluster", "azalea_ai_cluster.png"), 0.42),
    }
    specs = (
        ("maple_large", "红枫灌木，大型", "maple", 2.35, 1.55, 5, 110, 0, 11),
        ("maple_medium", "红枫灌木，中型", "maple", 1.7, 1.15, 4, 72, 0, 12),
        ("maple_small", "红枫灌木，小型", "maple", 1.15, 0.8, 3, 40, 0, 13),
        ("maple_sparse", "红枫灌木，疏枝", "maple", 1.85, 1.05, 4, 26, 0, 14),
        ("maple_clump", "红枫灌木，丛生", "maple", 1.45, 1.25, 7, 90, 0, 15),
        ("azalea_large", "杜鹃花丛，大型", "azalea", 1.05, 1.2, 0, 260, 0, 21),
        ("azalea_medium", "杜鹃花丛，中型", "azalea", 0.85, 0.9, 0, 130, 0, 22),
        ("azalea_small", "杜鹃花丛，小型", "azalea", 0.58, 0.62, 0, 72, 0, 23),
        ("azalea_sparse", "杜鹃花丛，疏枝", "azalea", 0.95, 0.85, 0, 64, 0, 24),
        ("pink_shrub_large", "粉花灌木，大型", "airy", 1.55, 1.2, 5, 36, 34, 31),
        ("pink_shrub_medium", "粉花灌木，中型", "airy", 1.15, 0.9, 4, 24, 22, 32),
        ("pink_shrub_small", "粉花灌木，小型", "airy", 0.8, 0.62, 3, 16, 14, 33),
        ("pink_shrub_sparse", "粉花灌木，疏枝", "airy", 1.25, 0.8, 4, 12, 10, 34),
        ("hedge_white", "白花绿篱", "hedge", 0.55, 1.35, 0, 120, 40, 41),
        ("hedge_mixed", "混色绿篱", "hedge", 0.58, 1.35, 0, 120, 36, 42),
        ("hedge_red", "红叶绿篱", "hedge", 0.52, 1.25, 0, 100, 10, 43),
        ("groundcover", "低矮地被", "hedge", 0.22, 1.5, 0, 80, 18, 44),
        ("peony_white", "牡丹花丛，白色", "peony", 0.72, 0.85, 5, 40, 8, 51),
        ("peony_pink", "牡丹花丛，粉色", "peony", 0.75, 0.88, 5, 40, 8, 52),
        ("peony_red", "牡丹花丛，红色", "peony", 0.7, 0.82, 5, 40, 8, 53),
        ("peony_mixed", "牡丹花丛，混色", "peony", 0.78, 1.05, 6, 48, 11, 54),
    )
    palettes = {
        "maple_large": (BARK, cards["maple_red"], cards["maple_orange"], cards["maple_red"], cards["maple_orange"]),
        "maple_medium": (BARK, cards["maple_red"], cards["maple_orange"], cards["maple_red"], cards["maple_orange"]),
        "maple_small": (BARK, cards["maple_orange"], cards["maple_red"], cards["maple_red"], cards["maple_orange"]),
        "maple_sparse": (BARK, cards["maple_red"], cards["maple_orange"], cards["maple_red"], cards["maple_orange"]),
        "maple_clump": (BARK, cards["maple_red"], cards["maple_orange"], cards["maple_red"], cards["maple_orange"]),
        "azalea_large": (BARK, cards["azalea_ai_sprig"], cards["azalea_ai_sprig"], cards["azalea_ai_flower"], cards["azalea_ai_cluster"]),
        "azalea_medium": (BARK, cards["azalea_ai_sprig"], cards["azalea_ai_sprig"], cards["azalea_ai_flower"], cards["azalea_ai_cluster"]),
        "azalea_small": (BARK, cards["azalea_ai_sprig"], cards["azalea_ai_sprig"], cards["azalea_ai_flower"], cards["azalea_ai_cluster"]),
        "azalea_sparse": (BARK, cards["azalea_ai_sprig"], cards["azalea_ai_sprig"], cards["azalea_ai_flower"], cards["azalea_ai_cluster"]),
        "pink_shrub_large": (BARK, cards["pink_leaf"], cards["azalea_leaf"], cards["pink_flower"], cards["pink_flower_deep"]),
        "pink_shrub_medium": (BARK, cards["pink_leaf"], cards["azalea_leaf"], cards["pink_flower"], cards["pink_flower_deep"]),
        "pink_shrub_small": (BARK, cards["pink_leaf"], cards["azalea_leaf"], cards["pink_flower"], cards["pink_flower_deep"]),
        "pink_shrub_sparse": (BARK, cards["pink_leaf"], cards["azalea_leaf"], cards["pink_flower"], cards["pink_flower_deep"]),
        "hedge_white": (BARK, cards["hedge_green"], cards["hedge_green"], cards["white_cluster"], cards["white_cluster"]),
        "hedge_mixed": (BARK, cards["hedge_green"], cards["hedge_red"], cards["white_cluster"], cards["pink_cluster"]),
        "hedge_red": (BARK, cards["hedge_red"], cards["hedge_green"], cards["pink_cluster"], cards["white_cluster"]),
        "groundcover": (BARK, cards["hedge_green"], cards["azalea_leaf"], cards["white_cluster"], cards["pink_cluster"]),
        "peony_white": (BARK, cards["peony_leaf"], cards["hedge_green"], cards["peony_white"], cards["peony_white"]),
        "peony_pink": (BARK, cards["peony_leaf"], cards["hedge_green"], cards["peony_pink"], cards["pink_flower"]),
        "peony_red": (BARK, cards["peony_leaf"], cards["hedge_green"], cards["peony_red"], cards["peony_pink"]),
        "peony_mixed": (BARK, cards["peony_leaf"], cards["hedge_green"], cards["peony_pink"], cards["peony_red"]),
    }
    for kit_id, description, form, height, radius, stems, leaves, flowers, seed in specs:
        mesh = build_plant(kit_id, seed, form, height, radius, stems, leaves, flowers, palettes[kit_id])
        register_kit(kit_id, description + "，原点在根部", "base")
        KIT_DEFS[kit_id]["mesh"] = mesh


def place_garden():
    # Decorative only, outside the 14.5 m combat circle. Rocks and lanterns reuse existing kits.
    prepare_bamboo()
    prepare_garden()
    spots = (
        ("maple_large", -34, -30, 0.4),
        ("maple_clump", -30, -34, 1.1),
        ("maple_medium", 32, -28, 0.2),
        ("maple_small", 36, -24, 2.0),
        ("maple_sparse", -40, -16, 0.8),
        ("azalea_large", -28, 12, 0.5),
        ("azalea_medium", -28, 4, 1.4),
        ("azalea_small", -28, -6, 0.3),
        ("azalea_sparse", -34, 18, 2.2),
        ("pink_shrub_large", 28, 14, 0.6),
        ("pink_shrub_medium", 28, 4, 1.7),
        ("pink_shrub_small", 28, -6, 0.9),
        ("pink_shrub_sparse", 34, 18, 2.4),
        ("hedge_white", -22, 21, 0.0),
        ("hedge_mixed", -30, 21, 0.15),
        ("hedge_red", 22, 21, 0.1),
        ("groundcover", 30, 21, 0.0),
        ("hedge_white", -22, -26, 0.0),
        ("hedge_red", 22, -26, 0.2),
        ("peony_white", -26, 28, 0.4),
        ("peony_pink", -18, 29, 1.2),
        ("peony_red", 18, 29, 0.7),
        ("peony_mixed", 26, 28, 2.1),
    )
    for kit_id, x, z, yaw in spots:
        place_kit(kit_id, kit_id + "_%d_%d" % (int(x), int(z)), KIT_DEFS[kit_id]["mesh"], (x, 0.0, z), rot=(0.0, 0.0, yaw))
    for x, z, scale in ((-32.4, -31.2, 0.22), (28.5, 29.2, 0.28), (-29.5, 13.2, 0.18)):
        place_kit(
            BAMBOO_LIB["kit:rock"], "GardenRock_%d_%d" % (int(x), int(z)), BAMBOO_LIB["rock"],
            (x, scale * 0.45, z), scale=(scale, scale * 0.8, scale * 0.55),
        )
    place_lantern("GardenLanternMaple", -37.5, -32.5)
    place_lantern("GardenLanternPeony", 30.5, 30.5)


def place_paving_sample():
    # A few pavers on the inner court, just south of the 14.5 m combat circle.
    build_paving_kits()
    y = 0.045
    place_kit("paving_square", "PavingSquare", KIT_DEFS["paving_square"]["mesh"], (5.5, y, 18.5))
    place_kit("paving_square_crack", "PavingSquareCrack", KIT_DEFS["paving_square_crack"]["mesh"], (6.5, y, 18.5))
    place_kit("paving_rect", "PavingRect", KIT_DEFS["paving_rect"]["mesh"], (6.0, y, 17.5))
    place_kit("paving_corner", "PavingCorner", KIT_DEFS["paving_corner"]["mesh"], (8.0, y, 18.0))


def mountain(name, x, z, radius, height):
    bpy.ops.mesh.primitive_cone_add(vertices=9, radius1=radius, radius2=radius * 0.08, depth=height, location=(x, -z, height * 0.5 - 0.3))
    obj = bpy.context.object
    obj.name = name
    finish(obj, MOUNTAIN, 0.18)


def _paving_image_mat(name, filename, roughness, repeat=False):
    path = os.path.join(KIT_DIR, "textures", filename)
    image = bpy.data.images.load(path, check_existing=True)
    image.name = name
    image.colorspace_settings.name = "sRGB"
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    specular = bsdf.inputs.get("Specular IOR Level")
    if specular is not None:
        specular.default_value = 0.16
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    tex.extension = "REPEAT" if repeat else "EXTEND"
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return material


def _paver_mesh(name, points, top_mat, side_mat, height=0.15, bevel=0.04):
    # points are Blender XY. Bottom sits on Z=0 so the kit origin is the footprint center.
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, 0.0)) for x, y in points]
    face = bm.faces.new(verts)
    if face.normal.z < 0.0:
        face.normal_flip()
    extruded = bmesh.ops.extrude_face_region(bm, geom=[face])
    new_verts = [item for item in extruded["geom"] if isinstance(item, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=new_verts, vec=(0.0, 0.0, height))
    top_edges = [
        edge for edge in bm.edges
        if all(abs(vert.co.z - height) < 1e-5 for vert in edge.verts)
    ]
    if top_edges and bevel > 0.0:
        try:
            bmesh.ops.bevel(
                bm, geom=top_edges, offset=bevel, segments=2, profile=0.55,
                affect="EDGES", clamp_overlap=True,
            )
        except TypeError:
            bmesh.ops.bevel(bm, geom=top_edges, offset=bevel, segments=2, profile=0.55, vertex_only=False)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    spanx = max(maxx - minx, 1e-6)
    spany = max(maxy - miny, 1e-6)
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        face.smooth = False
        on_top = min(vert.co.z for vert in face.verts) > height - 0.002 and face.normal.z > 0.5
        if on_top:
            face.material_index = 0
            for loop in face.loops:
                loop[uv].uv = ((loop.vert.co.x - minx) / spanx, (loop.vert.co.y - miny) / spany)
        else:
            face.material_index = 1
            use_y = abs(face.normal.x) >= abs(face.normal.y)
            for loop in face.loops:
                along = loop.vert.co.y if use_y else loop.vert.co.x
                loop[uv].uv = (along * 1.2, loop.vert.co.z * 1.2)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(top_mat)
    mesh.materials.append(side_mat)
    return mesh


def build_paving_kits():
    # Not placed in the arena. Square tiles sit on a 1 m grid; the long paver is 2 x 1;
    # the corner occupies a 2 m square and leaves the +X/+Y quadrant empty in Blender.
    if KIT_DEFS.get("paving_square", {}).get("mesh"):
        return
    side = _paving_image_mat("Paving Side", "paving_side.png", 0.84, repeat=True)
    square = ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5))
    rect = ((-1.0, -0.5), (1.0, -0.5), (1.0, 0.5), (-1.0, 0.5))
    # Notch is Blender +X/+Y, which is Godot +X/-Z after the Y-up export.
    corner = ((-1.0, -1.0), (1.0, -1.0), (1.0, 0.0), (0.0, 0.0), (0.0, 1.0), (-1.0, 1.0))
    specs = (
        ("paving_square", "青灰方砖，1 米见方、厚 0.15 米，对角裂纹带青苔，原点在底面中心", square, "paving_square.png"),
        ("paving_square_crack", "青灰方砖，1 米见方、厚 0.15 米，上沿裂纹，原点在底面中心", square, "paving_square_crack.png"),
        ("paving_rect", "青灰长砖，2×1 米、厚 0.15 米，长边沿局部 X，原点在底面中心", rect, "paving_rect.png"),
        ("paving_corner", "青灰 L 形转角砖，外框 2 米、臂宽 1 米、厚 0.15 米，缺角在 Godot +X/−Z，原点在底面中心", corner, "paving_corner.png"),
    )
    for kit_id, description, points, filename in specs:
        top = _paving_image_mat(kit_id, filename, 0.84)
        # Flat top, same as the arena-center tiles. A chamfer makes the rim face the sun.
        mesh = _paver_mesh(kit_id, points, top, side, bevel=0.0)
        register_kit(kit_id, description, "base")
        KIT_DEFS[kit_id]["mesh"] = mesh


def _merge_paving_catalog():
    with open(CATALOG_PATH, encoding="utf-8") as handle:
        catalog = json.load(handle)
    kits = catalog["kits"]
    index = {item["id"]: item_index for item_index, item in enumerate(kits)}
    for kit_id, spec in KIT_DEFS.items():
        entry = {
            "id": kit_id,
            "file": kit_id + ".glb",
            "origin": spec["origin"],
            "description": spec["description"],
        }
        if kit_id in index:
            kits[index[kit_id]] = entry
        else:
            kits.append(entry)
    with open(CATALOG_PATH, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def _render_paving_preview():
    layout = (
        ("paving_square", (-1.15, 1.35, 0.0)),
        ("paving_square_crack", (1.15, 1.35, 0.0)),
        ("paving_rect", (-0.15, -0.85, 0.0)),
        ("paving_corner", (2.35, 0.15, 0.0)),
    )
    for kit_id, loc in layout:
        obj = bpy.data.objects.new(kit_id + "_preview", KIT_DEFS[kit_id]["mesh"])
        obj.location = loc
        bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.light_add(type="SUN", location=(2.0, -3.0, 6.0))
    sun = bpy.context.object
    sun.rotation_euler = (math.radians(42), math.radians(-12), math.radians(28))
    sun.data.energy = 3.2
    sun.data.color = (1.0, 0.96, 0.9)
    bpy.ops.object.camera_add(location=(3.4, -4.6, 2.4))
    camera = bpy.context.object
    direction = Vector((0.55, 0.15, 0.08)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = os.path.join(SOURCE_DIR, "paving_tiles_preview.png")
    scene.world.color = (0.02, 0.02, 0.02)
    bpy.ops.render.render(write_still=True)


def _rack_image(filename):
    path = os.path.join(KIT_DIR, "textures", filename)
    image = bpy.data.images.load(path, check_existing=True)
    image.colorspace_settings.name = "sRGB"
    image.alpha_mode = "STRAIGHT"
    return image


def _weapon_wood_mat():
    material = bpy.data.materials.new("WeaponRackWood")
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.62
    specular = bsdf.inputs.get("Specular IOR Level")
    if specular is not None:
        specular.default_value = 0.22
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = _rack_image("weapon_rack_wood.png")
    tex.interpolation = "Linear"
    tex.extension = "REPEAT"
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return material


def _weapon_decal_mat(filename):
    material = bpy.data.materials.new("WeaponDecal_%s" % filename)
    material.use_nodes = True
    material.use_backface_culling = False
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "BLENDED"
    tree = material.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.4
    specular = bsdf.inputs.get("Specular IOR Level")
    if specular is not None:
        specular.default_value = 0.35
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = _rack_image(filename)
    tex.interpolation = "Linear"
    tex.extension = "CLIP"
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    return material


def _uv_wood(obj, tile=0.32):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    layer = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        normal = face.normal
        for loop in face.loops:
            co = loop.vert.co
            if abs(normal.z) > 0.6:
                uv = (co.x / tile, co.y / tile)
            elif abs(normal.x) > abs(normal.y):
                uv = (co.y / tile, co.z / tile)
            else:
                uv = (co.x / tile, co.z / tile)
            loop[layer].uv = uv
    bm.to_mesh(mesh)
    bm.free()


def _rack_box(name, center, size, material):
    bpy.ops.mesh.primitive_cube_add(location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    _uv_wood(obj)
    return obj


def _weapon_card(name, material, width, height):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    half = width * 0.5
    front = [(-half, 0.0, 0.0), (half, 0.0, 0.0), (half, 0.0, height), (-half, 0.0, height)]
    front_uv = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    verts = [bm.verts.new(co) for co in front]
    face = bm.faces.new(verts)
    for loop, coord in zip(face.loops, front_uv):
        loop[uv_layer].uv = coord
    back = [(-half, -0.008, 0.0), (-half, -0.008, height), (half, -0.008, height), (half, -0.008, 0.0)]
    back_uv = [(1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]
    back_verts = [bm.verts.new(co) for co in back]
    back_face = bm.faces.new(back_verts)
    for loop, coord in zip(back_face.loops, back_uv):
        loop[uv_layer].uv = coord
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build_weapon_rack():
    if KIT_DEFS.get("weapon_rack", {}).get("root"):
        return KIT_DEFS["weapon_rack"]["root"]
    wood = _weapon_wood_mat()
    brass = mat("WeaponRackBrass", (0.66, 0.46, 0.18), 0.34, 1.0)
    parts = []

    def box(name, center, size, material):
        obj = _rack_box(name, center, size, material)
        parts.append(obj)
        return obj

    for side in (-1, 1):
        box("RackPost_%d" % side, (side * 0.98, 0.0, 0.88), (0.10, 0.12, 1.76), wood)
        box("RackFoot_%d" % side, (side * 0.98, 0.05, 0.04), (0.28, 0.40, 0.08), wood)
        box("RackCap_%d" % side, (side * 0.98, 0.0, 1.79), (0.15, 0.17, 0.05), brass)
        box("RackBand_%d_a" % side, (side * 0.98, 0.0, 0.58), (0.12, 0.14, 0.03), brass)
        box("RackBand_%d_b" % side, (side * 0.98, 0.0, 1.32), (0.12, 0.14, 0.03), brass)
    box("RackTop", (0.0, 0.0, 1.66), (2.16, 0.10, 0.07), wood)
    box("RackSwordRail", (0.0, 0.08, 1.52), (1.88, 0.05, 0.04), wood)
    box("RackSpearRail", (0.0, 0.09, 0.40), (1.96, 0.12, 0.06), wood)
    box("RackStretcher", (0.0, -0.02, 0.16), (1.88, 0.06, 0.045), wood)
    for index, x in enumerate((-0.64, -0.32, 0.0, 0.32, 0.64)):
        box("RackSlat_%d" % index, (x, -0.075, 1.00), (0.04, 0.022, 1.08), wood)
    jian_h = 1.05
    spear_h = 1.95
    dao_h = 1.90
    jian = _weapon_decal_mat("weapon_jian.png")
    spear_mat = _weapon_decal_mat("weapon_spear.png")
    dao_mat = _weapon_decal_mat("weapon_guandao.png")
    for index, (x, yaw) in enumerate(((-0.46, 0.04), (0.0, -0.02), (0.46, 0.05))):
        card = _weapon_card("Jian_%d" % index, jian, jian_h * 0.174, jian_h)
        card.location = (x, 0.30, 0.50)
        card.rotation_euler = (0.0, 0.0, yaw)
        parts.append(card)
    for index, (x, yaw) in enumerate(((-0.82, 0.03), (0.82, -0.03))):
        card = _weapon_card("Spear_%d" % index, spear_mat, spear_h * 0.198, spear_h)
        card.location = (x, 0.08, 0.0)
        card.rotation_euler = (0.0, 0.0, yaw)
        parts.append(card)
    dao = _weapon_card("Guandao", dao_mat, dao_h * 0.148, dao_h)
    dao.location = (-1.22, 0.14, 0.0)
    dao.rotation_euler = (0.0, 0.0, -0.05)
    parts.append(dao)
    bpy.context.view_layer.update()
    root = bpy.data.objects.new("weapon_rack", None)
    bpy.context.scene.collection.objects.link(root)
    for part in parts:
        world = part.matrix_world.copy()
        part.parent = root
        part.matrix_world = world
    bpy.context.view_layer.update()
    register_kit(
        "weapon_rack",
        "兵器架，深色木架上挂三把剑、两侧立枪并靠一把关刀，原点在地面中心",
        "base",
    )
    KIT_DEFS["weapon_rack"]["root"] = root
    return root


def _render_weapon_rack_preview():
    bpy.ops.object.light_add(type="SUN", location=(1.5, -2.5, 4.0))
    sun = bpy.context.object
    sun.data.energy = 3.4
    sun.data.color = (1.0, 0.94, 0.86)
    sun.rotation_euler = (math.radians(50), math.radians(8), math.radians(20))
    bpy.ops.object.light_add(type="AREA", location=(-1.6, 1.8, 2.2))
    fill = bpy.context.object
    fill.data.energy = 250
    fill.data.size = 2.5
    bpy.ops.object.camera_add(location=(0.35, 4.6, 1.45))
    camera = bpy.context.object
    look = Vector((0.1, 0.0, 0.95)) - camera.location
    camera.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = os.path.join(SOURCE_DIR, "weapon_rack_preview.png")
    scene.world.color = (0.16, 0.17, 0.18)
    bpy.ops.render.render(write_still=True)


if "--paving-only" in sys.argv:
    build_paving_kits()
    export_kits()
    _merge_paving_catalog()
    try:
        _render_paving_preview()
    except Exception as exc:
        print("PAVING_PREVIEW_FAILED %s" % exc)
    print("PAVING_KITS_BUILT %s" % ", ".join(KIT_DEFS))
    raise SystemExit(0)


if "--weapon-rack-only" in sys.argv:
    build_weapon_rack()
    try:
        _render_weapon_rack_preview()
    except Exception as exc:
        print("WEAPON_RACK_PREVIEW_FAILED %s" % exc)
    export_kits()
    _merge_paving_catalog()
    print("WEAPON_RACK_BUILT")
    raise SystemExit(0)


# Foundation and central fighting plaza.
cube("Ground", (0, -0.24, 0), (108, 0.45, 88), STONE, 0.08)
cube("InnerCourt", (0, 0.015, 0), (74, 0.05, 56), STONE_LIGHT, 0.03)

# Perimeter walls with repeated caps.
for z in (-43.5, 43.5):
    cube(f"WallZ_{z}", (0, 1.55, z), (108, 3.1, 0.75), PLASTER, 0.06)
    cube(f"WallCapZ_{z}", (0, 3.2, z), (109, 0.25, 1.25), ROOF, 0.06)
for x in (-53.5, 53.5):
    cube(f"WallX_{x}", (x, 1.55, 0), (0.75, 3.1, 86), PLASTER, 0.06)
    cube(f"WallCapX_{x}", (x, 3.2, 0), (1.25, 0.25, 87), ROOF, 0.06)

hall("NorthernTemple", (0, 0, -35), 32, 9, 5.7)
stairs("TempleSteps", (0, 0, -29.0), 14.0, 5.0, 7)
pavilion("WestPavilion", (-43, 0, 2))
pavilion("EastPavilion", (43, 0, 2))
gate()

for x in (-29, 29):
    for z in (-18, 18):
        stone_lantern(f"StoneLantern_{x}_{z}", x, z)

# Low decorative railings frame the arena without closing the main routes.
for side in (-1, 1):
    for x in range(-34, 35, 4):
        if abs(x) < 10:
            continue
        cube(f"NorthRail_{side}_{x}", (x, 0.55, side * 24.5), (3.5, 0.7, 0.14), STONE_LIGHT, 0.04)

# Groves sit against the walls. Clumps stay outside the 14.5 m combat circle.
bamboo_cluster("BambooGroveNW", -48, -24, "grove")
bamboo_cluster("BambooGroveNE", 48, -24, "grove")
bamboo_cluster("BambooGroveSW", -47, 22, "grove")
bamboo_cluster("BambooGroveSE", 47, 22, "grove")
bamboo_cluster("BambooClumpSW", -36, 31, "clump")
bamboo_cluster("BambooClumpSE", 36, 31, "clump")
bamboo_cluster("BambooClumpSouthWest", -22, 20, "clump")
bamboo_cluster("BambooClumpSouthEast", 22, 20, "clump")
bamboo_cluster("BambooSingleWest", -50, -6, "single")
bamboo_cluster("BambooSingleEast", 50, 8, "single")
place_garden()
place_paving_sample()

# Background mountains are outside gameplay walls.
for i, (x, z, r, h) in enumerate([(-42, -61, 17, 25), (-17, -68, 22, 34), (12, -72, 25, 39), (42, -62, 18, 29), (64, -50, 14, 23), (-67, -48, 15, 24)]):
    mountain(f"Mountain_{i}", x, z, r, h)

# Shallow ornamental pools near the side pavilions.
for x in (-34, 34):
    cube(f"PoolRim_{x}", (x, 0.03, -13), (9.5, 0.12, 7.0), STONE_LIGHT, 0.12)
    cube(f"PoolWater_{x}", (x, 0.10, -13), (8.7, 0.035, 6.2), WATER, 0.04)

for kit_id in ("stone_lantern", "palace_lantern", "main_hall"):
    if KIT_DEFS.get(kit_id, {}).get("root"):
        stash_master(KIT_DEFS[kit_id]["root"])
bpy.context.view_layer.update()
placements = [godot_placement(obj) for obj in INSTANCES]
_check_kit_transforms(placements)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

# Preview render.
bpy.ops.object.camera_add(location=(72, -82, 62))
camera = bpy.context.object
camera.name = "PreviewCamera"
direction = Vector((0, 0, 1.5)) - camera.location
camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
bpy.context.scene.camera = camera
bpy.ops.object.light_add(type="SUN", location=(20, -30, 55))
sun = bpy.context.object
sun.rotation_euler = (math.radians(28), math.radians(-18), math.radians(145))
sun.data.energy = 3.0
sun.data.color = (1.0, 0.73, 0.48)
bpy.ops.object.light_add(type="AREA", location=(-20, -5, 45))
fill = bpy.context.object
fill.data.energy = 1600
fill.data.shape = "DISK"
fill.data.size = 38
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = PREVIEW_PATH
scene.world.color = (0.12, 0.20, 0.30)
scene.view_settings.look = "AgX - Medium High Contrast"

def render_preview(path, location, target):
    camera.location = location
    look = Vector(target) - camera.location
    camera.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    try:
        bpy.ops.render.render(write_still=True)
    except RuntimeError as exc:
        print("PREVIEW_SKIPPED %s %s" % (path, exc))

render_preview(PREVIEW_PATH, (72, -82, 62), (0, 0, 1.5))
render_preview(BAMBOO_PREVIEW_PATH, (52, -36, 3.4), (34, -22, 2.2))
render_preview(GARDEN_PREVIEW_PATH, (-23.4, -7.8, 1.2), (-28.0, -12.0, 0.5))
render_preview(HALL_PREVIEW_PATH, (26.0, 6.0, 11.0), (0.0, 34.5, 4.0))

for extra in (camera, sun, fill):
    if extra and extra.name in bpy.data.objects:
        bpy.data.objects.remove(extra, do_unlink=True)
for obj in list(INSTANCES):
    for node in list(walk_tree(obj)):
        if node.name in bpy.data.objects:
            bpy.data.objects.remove(node, do_unlink=True)
build_paving_kits()
build_weapon_rack()
stash_master(KIT_DEFS["weapon_rack"]["root"])
export_kits()
bpy.ops.export_scene.gltf(filepath=SHELL_GLB_PATH, export_format="GLB", export_apply=True, export_cameras=False, export_lights=False)
bpy.ops.wm.obj_export(filepath=SHELL_OBJ_PATH, export_materials=True, export_uv=False, export_normals=True, export_triangulated_mesh=True)
catalog = {
    "units": "meters",
    "axis": "Godot Y-up after GLB import",
    "collision": "none; gameplay shapes stay in combat/mountain_arena_layout.gd",
    "kits": [
        {"id": kit_id, "file": kit_id + ".glb", "origin": spec["origin"], "description": spec["description"]}
        for kit_id, spec in KIT_DEFS.items()
    ],
}
with open(CATALOG_PATH, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(catalog, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
def _placements_are_authored():
    # The map builder owns this file after the first save.
    if not os.path.exists(PLACEMENTS_PATH):
        return False
    try:
        with open(PLACEMENTS_PATH, encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return False
    return bool(document.get("authored"))


authored_placements = _placements_are_authored()
if authored_placements:
    print("PLACEMENTS_KEPT map editor owns kit_placements.json")
else:
    with open(PLACEMENTS_PATH, "w", encoding="utf-8", newline="\n") as handle:
        json.dump({"placements": placements}, handle, ensure_ascii=False)
        handle.write("\n")
for stale in (
    os.path.join(OUT_DIR, "mountain_arena.obj"),
    os.path.join(OUT_DIR, "mountain_arena.mtl"),
    os.path.join(OUT_DIR, "mountain_arena.glb"),
):
    if os.path.exists(stale):
        os.remove(stale)
def _share_textures():
    script = os.path.join(ROOT, "tools", "externalize_glb_textures.py")
    spec = importlib.util.spec_from_file_location("externalize_glb_textures", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.main([os.path.join(ROOT, "assets", "environment")])


def _keep_rock_rear():
    # build_rock_kit.py owns these pieces. A full arena rebuild rewrites the catalog.
    extra_path = os.path.join(ROOT, "assets", "environment", "rock_kit", "catalog_extra.json")
    rear_path = os.path.join(ROOT, "assets", "environment", "rock_kit", "rear_placements.json")
    if not (os.path.exists(extra_path) and os.path.exists(rear_path)):
        return
    with open(extra_path, encoding="utf-8") as handle:
        extra = json.load(handle)
    with open(rear_path, encoding="utf-8") as handle:
        rear = json.load(handle)
    ids = {item["id"] for item in extra}
    with open(CATALOG_PATH, encoding="utf-8") as handle:
        catalog_doc = json.load(handle)
    catalog_doc["kits"] = [item for item in catalog_doc["kits"] if item["id"] not in ids] + extra
    with open(CATALOG_PATH, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(catalog_doc, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    if authored_placements:
        print("ROCK_REAR_CATALOG_ONLY kits=%d" % len(extra))
        return
    with open(PLACEMENTS_PATH, encoding="utf-8") as handle:
        placed = json.load(handle)
    placed["placements"] = [item for item in placed["placements"] if item.get("kit") not in ids] + rear
    with open(PLACEMENTS_PATH, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(placed, handle, ensure_ascii=False)
        handle.write("\n")
    print("ROCK_REAR_KEPT kits=%d placements=%d" % (len(extra), len(rear)))


_keep_rock_rear()
_share_textures()
print("MOUNTAIN_ARENA_BUILT kits=%d placements=%d shell=%s" % (len(KIT_DEFS), len(placements), SHELL_OBJ_PATH))
