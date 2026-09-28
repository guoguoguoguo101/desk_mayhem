"""Standalone model of the north hall (武修堂).

Not placed in the arena. Saves a packed Blender file, a GLB, and preview stills.
Run: D:\\Blender\\blender.exe --background --python tools/build_wuxiu_hall.py
"""
import array
import bmesh
import bpy
import math
import os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "environment", "main_hall")
TEX_DIR = os.path.join(OUT_DIR, "textures")
SRC_DIR = os.path.join(ROOT, "source_art", "main_hall")
BLEND_PATH = os.path.join(SRC_DIR, "wuxiu_hall.blend")
GLB_PATH = os.path.join(OUT_DIR, "wuxiu_hall.glb")
PREVIEW_PATH = os.path.join(OUT_DIR, "wuxiu_hall_preview.png")
FRONT_PATH = os.path.join(OUT_DIR, "wuxiu_hall_front.png")
SIDE_PATH = os.path.join(OUT_DIR, "wuxiu_hall_side.png")

# Blender Z-up. The court / front is -Y. Origin is the platform center on the ground.
PLAT_W, PLAT_D, PLAT_H = 16.8, 10.6, 1.18
FRONT_Y = -4.42
WALL_Y = -3.35
COL_X = (-7.15, -4.29, -1.43, 1.43, 4.29, 7.15)
COL_H = 3.72
BEAM_Z = PLAT_H + COL_H + 0.16


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def finish(obj, material):
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)
    return obj


def box(name, loc, size, material, uv=(1.0, 1.0)):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mesh = obj.data
    if mesh.uv_layers.active:
        for loop in mesh.uv_layers.active.data:
            loop.uv.x *= uv[0]
            loop.uv.y *= uv[1]
    return finish(obj, material)


def cyl(name, loc, radius, depth, material, vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, material)


def color_mat(name, color, roughness=0.55, metallic=0.0, emission=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return material


def image_mat(name, filename, roughness, repeats=True):
    image = bpy.data.images.load(os.path.join(TEX_DIR, filename))
    image.pack()
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    tree = material.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    tex.extension = "REPEAT" if repeats else "CLIP"
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return material


def card_mat(name, image, roughness):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "BLENDED"
    tree = material.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.extension = "CLIP"
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    clip = tree.nodes.new("ShaderNodeMath")
    clip.operation = "GREATER_THAN"
    clip.inputs[1].default_value = 0.45
    tree.links.new(tex.outputs["Alpha"], clip.inputs[0])
    tree.links.new(clip.outputs["Value"], bsdf.inputs["Alpha"])
    return material


def key_banner():
    src = os.path.join(TEX_DIR, "wx_banner.png")
    image = bpy.data.images.load(src)
    width, height = image.size
    pixels = array.array("f", [0.0]) * (width * height * 4)
    image.pixels.foreach_get(pixels)
    key = (pixels[0], pixels[1], pixels[2])

    def near(index, limit):
        return (
            abs(pixels[index] - key[0])
            + abs(pixels[index + 1] - key[1])
            + abs(pixels[index + 2] - key[2])
        ) < limit

    seen = bytearray(width * height)
    stack = []
    for x in range(width):
        stack.append(x)
        stack.append(x + (height - 1) * width)
    for y in range(height):
        stack.append(y * width)
        stack.append(width - 1 + y * width)
    while stack:
        cell = stack.pop()
        if seen[cell] or not near(cell * 4, 0.55):
            continue
        seen[cell] = 1
        pixels[cell * 4 + 3] = 0.0
        cx, cy = cell % width, cell // width
        if cx > 0:
            stack.append(cell - 1)
        if cx + 1 < width:
            stack.append(cell + 1)
        if cy > 0:
            stack.append(cell - width)
        if cy + 1 < height:
            stack.append(cell + width)
    for cell in range(width * height):
        if near(cell * 4, 0.28):
            pixels[cell * 4 + 3] = 0.0
    image.pixels.foreach_set(pixels)
    image.pack()
    return image


def front_card(name, center, size, material):
    # Faces -Y. UV puts image-left on the viewer's left when the camera sits in front.
    x, y, z = center
    w, h = size
    bm = bmesh.new()
    verts = [
        bm.verts.new(co)
        for co in ((x - w * 0.5, y, z - h * 0.5), (x + w * 0.5, y, z - h * 0.5), (x + w * 0.5, y, z + h * 0.5), (x - w * 0.5, y, z + h * 0.5))
    ]
    face = bm.faces.new(verts)
    uv = bm.loops.layers.uv.new("UVMap")
    for loop, coord in zip(face.loops, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
        loop[uv].uv = coord
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    return link(obj)


def roof_point(u, v, hw, hd, rise, lift, flare):
    x = -hw + 2.0 * hw * u
    y = -hd + 2.0 * hd * v
    ax = abs(x) / hw
    ay = abs(y) / hd
    side = max(0.0, (ax - 0.52) / 0.48)
    slope = max(side, ay) ** 0.9
    end = max(0.0, (ax - 0.8) / 0.2)
    near = max(0.0, (ay - 0.75) / 0.25)
    fly = (end ** 1.15) * near
    z = rise * (1.0 - slope) + lift * fly
    x += math.copysign(flare * fly, x) if ax > 0.02 else 0.0
    y += math.copysign(flare * 0.62 * fly, y) if ay > 0.02 else 0.0
    return (x, y, z), 1.0 - slope


def build_roof(name, width, depth, rise, lift, flare, tile_mat, edge_mat):
    nu, nv = 36, 18
    hw, hd = width * 0.5, depth * 0.5
    bm = bmesh.new()
    grid = []
    slope_of = []
    for j in range(nv + 1):
        row = []
        slopes = []
        for i in range(nu + 1):
            co, slope = roof_point(i / nu, j / nv, hw, hd, rise, lift, flare)
            row.append(bm.verts.new(co))
            slopes.append(slope)
        grid.append(row)
        slope_of.append(slopes)
    uv = bm.loops.layers.uv.new("UVMap")
    for j in range(nv):
        for i in range(nu):
            face = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            row = 1.0 - abs(j / nv * 2.0 - 1.0)
            row_next = 1.0 - abs((j + 1) / nv * 2.0 - 1.0)
            coords = (
                (i / nu * 8.0, row * 4.0),
                ((i + 1) / nu * 8.0, row * 4.0),
                ((i + 1) / nu * 8.0, row_next * 4.0),
                (i / nu * 8.0, row_next * 4.0),
            )
            for loop, coord in zip(face.loops, coords):
                loop[uv].uv = coord
    bmesh.ops.recalc_face_normals(bm)
    extruded = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for vert in extruded["geom"]:
        if isinstance(vert, bmesh.types.BMVert):
            vert.co.z -= 0.14
    rings = (
        [Vector(grid[0][i].co) for i in range(nu + 1)],
        [Vector(grid[nv][i].co) for i in range(nu, -1, -1)],
        [Vector(grid[j][0].co) for j in range(nv, -1, -1)],
        [Vector(grid[j][nu].co) for j in range(nv + 1)],
    )
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(tile_mat)
    obj = bpy.data.objects.new(name, mesh)
    link(obj)

    skirt = bmesh.new()

    def skirt_ring(loop_cos):
        top = [skirt.verts.new(co) for co in loop_cos]
        bot = []
        for co in loop_cos:
            out = Vector((co.x, co.y, 0.0))
            if out.length > 1e-5:
                out.normalize()
            bot.append(skirt.verts.new(co + out * 0.05 + Vector((0.0, 0.0, -0.34))))
        for i in range(len(top) - 1):
            skirt.faces.new((top[i], top[i + 1], bot[i + 1], bot[i]))

    for ring in rings:
        skirt_ring(ring)
    skirt_mesh = bpy.data.meshes.new(name + "Edge")
    skirt.to_mesh(skirt_mesh)
    skirt.free()
    skirt_mesh.materials.append(edge_mat)
    edge = bpy.data.objects.new(name + "Edge", skirt_mesh)
    link(edge)
    edge.parent = obj
    edge.matrix_parent_inverse = obj.matrix_world.inverted()
    return obj


def add_bracket(name, x, y, z, wood):
    # One bay of dougong under the eave, projecting toward -Y.
    box(name + "_dou", (x, y - 0.05, z), (0.34, 0.34, 0.16), wood, (1, 1))
    box(name + "_arm_x", (x, y - 0.08, z + 0.18), (1.05, 0.22, 0.12), wood, (2, 1))
    box(name + "_arm_y", (x, y - 0.28, z + 0.32), (0.22, 0.72, 0.12), wood, (1, 2))
    box(name + "_dou2", (x, y - 0.42, z + 0.46), (0.28, 0.28, 0.14), wood, (1, 1))
    box(name + "_arm2", (x, y - 0.55, z + 0.58), (0.72, 0.46, 0.1), wood, (1, 1))


def add_column(name, x, y, wood, stone):
    base_z = PLAT_H + 0.16
    box(name + "_base", (x, y, base_z), (0.78, 0.78, 0.32), stone, (1, 1))
    cyl(name, (x, y, PLAT_H + 0.32 + COL_H * 0.5), 0.28, COL_H, wood, 20)


def add_rafters(wood, eave_z):
    count = 28
    width = 18.6
    for i in range(count):
        u = i / (count - 1)
        x = -width * 0.5 + width * u
        ax = abs(x) / (width * 0.5)
        fly = (max(0.0, (ax - 0.55) / 0.45) ** 1.5) * 1.15
        y = -6.55 - 0.35 * fly
        z = eave_z + fly - 0.08
        box("Rafter_%02d" % i, (x, y, z), (0.08, 0.55, 0.08), wood, (1, 1))


def add_chiwen(name, x, z, sign, gold):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.075
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(3)
    coords = ((0.0, 0.0, 0.0), (sign * 0.28, 0.0, 0.22), (sign * 0.42, 0.05, 0.55), (sign * 0.12, 0.02, 0.92))
    for point, co in zip(spline.bezier_points, coords):
        point.co = co
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    obj.location = (x, 0.0, z)
    link(obj)
    finish(obj, gold)
    return obj


def add_lantern(name, x, y, z, wood, glow):
    box(name + "_cap", (x, y, z - 0.08), (0.42, 0.42, 0.1), wood, (1, 1))
    cyl(name + "_body", (x, y, z - 0.48), 0.16, 0.62, glow, 6)
    box(name + "_frame_x", (x, y, z - 0.48), (0.36, 0.06, 0.66), wood, (1, 1))
    box(name + "_frame_y", (x, y, z - 0.48), (0.06, 0.36, 0.66), wood, (1, 1))
    cyl(name + "_tassel", (x, y, z - 0.95), 0.025, 0.28, wood, 6)


def add_stair_lantern(name, x, y, stone, wood, glow):
    box(name + "_foot", (x, y, 0.18), (0.55, 0.55, 0.36), stone, (1, 1))
    cyl(name + "_post", (x, y, 0.7), 0.08, 0.7, stone, 8)
    box(name + "_lamp", (x, y, 1.2), (0.36, 0.36, 0.42), glow, (1, 1))
    cyl(name + "_roof", (x, y, 1.52), 0.28, 0.16, wood, 4)


def build():
    os.makedirs(TEX_DIR, exist_ok=True)
    os.makedirs(SRC_DIR, exist_ok=True)
    reset_scene()
    wood = image_mat("Wood", "wx_wood.png", 0.52)
    tile = image_mat("Tile", "wx_tile.png", 0.48)
    stone = image_mat("Stone", "wx_stone.png", 0.86)
    lattice = image_mat("Lattice", "wx_lattice.png", 0.5, repeats=False)
    door = image_mat("Door", "wx_door.png", 0.48, repeats=False)
    plaque = image_mat("Plaque", "wx_plaque.png", 0.4, repeats=False)
    banner = card_mat("Banner", key_banner(), 0.42)
    gold = color_mat("Gold", (0.62, 0.42, 0.12), 0.38, 0.65)
    edge = color_mat("EaveEdge", (0.10, 0.11, 0.12), 0.6)
    glow = color_mat("Glow", (1.0, 0.62, 0.28), 0.35, emission=6.0)
    ground_mat = color_mat("Ground", (0.83, 0.81, 0.76), 0.9)
    dark = color_mat("ShadowGap", (0.08, 0.06, 0.045), 0.8)

    box("Ground", (0, 0, -0.04), (40, 40, 0.08), ground_mat, (4, 4))
    box("PlatformLower", (0, 0.15, 0.28), (PLAT_W + 0.7, PLAT_D + 0.9, 0.56), stone, (6, 4))
    box("PlatformUpper", (0, 0.05, PLAT_H - 0.28), (PLAT_W, PLAT_D, 0.62), stone, (5, 3))

    stair_w = 5.6
    for i in range(7):
        tread = 0.42
        y = -PLAT_D * 0.5 - 0.15 - tread * (6.5 - i)
        h = 0.17 * (i + 1)
        box("Step_%02d" % i, (0, y, h * 0.5), (stair_w, tread + 0.02, h), stone, (2, 1))

    for index, x in enumerate(COL_X):
        add_column("FrontCol_%d" % index, x, FRONT_Y, wood, stone)
    for index, y in enumerate((-1.35, 1.55, 4.05)):
        for side, x in enumerate((-7.15, 7.15)):
            add_column("SideCol_%d_%d" % (index, side), x, y, wood, stone)

    box("BackWall", (0, 4.35, PLAT_H + 1.85), (14.6, 0.38, 3.7), wood, (5, 2))
    box("SideWallL", (-6.55, 0.35, PLAT_H + 1.85), (0.28, 7.4, 3.7), wood, (3, 2))
    box("SideWallR", (6.55, 0.35, PLAT_H + 1.85), (0.28, 7.4, 3.7), wood, (3, 2))
    box("FrontLintel", (0, WALL_Y - 0.02, PLAT_H + 3.55), (14.8, 0.28, 0.22), wood, (6, 1))

    front_card("Door", (0, WALL_Y - 0.08, PLAT_H + 1.72), (2.55, 3.15), door)
    for index, x in enumerate((-5.72, -2.86, 2.86, 5.72)):
        front_card("Lattice_%d" % index, (x, WALL_Y - 0.08, PLAT_H + 2.05), (2.15, 2.45), lattice)
    box("Sill", (0, WALL_Y, PLAT_H + 0.08), (14.4, 0.16, 0.16), wood, (6, 1))

    box("Beam", (0, FRONT_Y + 0.05, BEAM_Z), (15.3, 0.48, 0.36), wood, (8, 1))
    bracket_x = []
    for i in range(len(COL_X) - 1):
        bracket_x.append(COL_X[i])
        bracket_x.append((COL_X[i] + COL_X[i + 1]) * 0.5)
    bracket_x.append(COL_X[-1])
    for index, x in enumerate(bracket_x):
        add_bracket("Bracket_%02d" % index, x, FRONT_Y + 0.15, BEAM_Z + 0.22, wood)

    lower = build_roof("LowerRoof", 19.4, 13.4, 2.45, 1.05, 0.42, tile, edge)
    lower.location = (0.0, -0.15, 5.28)
    add_rafters(wood, 5.22)
    upper = build_roof("UpperRoof", 12.2, 8.4, 2.05, 0.85, 0.32, tile, edge)
    upper.location = (0.0, 0.15, 7.72)
    box("Clerestory", (0, 0.1, 7.35), (10.4, 6.2, 1.05), wood, (4, 2))
    box("UpperBeam", (0, -2.55, 7.95), (10.6, 0.36, 0.28), wood, (4, 1))
    for index, x in enumerate((-4.2, -2.1, 0.0, 2.1, 4.2)):
        add_bracket("UpperBracket_%d" % index, x, -2.15, 8.15, wood)

    box("Ridge", (0, 0.15, 9.95), (6.4, 0.28, 0.22), gold, (1, 1))
    for index, x in enumerate((-2.4, -1.2, 0.0, 1.2, 2.4)):
        cyl("RidgePin_%d" % index, (x, 0.15, 10.18), 0.07, 0.28, gold, 8)
    add_chiwen("ChiwenL", -3.15, 9.85, -1, gold)
    add_chiwen("ChiwenR", 3.15, 9.85, 1, gold)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(
                "Bell_%d_%d" % (sx, sy),
                (sx * 9.3, sy * 6.3 - 0.2, 6.55),
                0.07,
                0.28,
                gold,
                8,
            )

    front_card("Plaque", (0, FRONT_Y - 0.42, 4.72), (4.4, 1.15), plaque)
    for index, x in enumerate((-2.95, 2.95)):
        front_card("Banner_%d" % index, (x, FRONT_Y - 0.72, 3.15), (1.35, 3.05), banner)
    for index, x in enumerate((-1.55, 1.55, -4.55, 4.55)):
        add_lantern("Lantern_%d" % index, x, FRONT_Y - 0.85, 4.85, wood, glow)
    for index, x in enumerate((-3.55, 3.55)):
        add_stair_lantern("StairLantern_%d" % index, x, -7.15, stone, wood, glow)

    rail_z = PLAT_H + 0.42
    for side, x0, x1 in ((-1, -8.0, -3.15), (1, 3.15, 8.0)):
        mid = (x0 + x1) * 0.5
        span = abs(x1 - x0)
        y = -PLAT_D * 0.5 + 0.28
        box("RailTop_%d" % side, (mid, y, rail_z + 0.28), (span, 0.08, 0.08), wood, (3, 1))
        box("RailLow_%d" % side, (mid, y, rail_z), (span, 0.06, 0.06), wood, (3, 1))
        post = x0
        n = 0
        while post <= x1 + 0.01:
            box("RailPost_%d_%d" % (side, n), (post, y, rail_z + 0.12), (0.08, 0.08, 0.55), wood, (1, 1))
            post += 1.35
            n += 1
    box("Interior", (0, 0.4, PLAT_H + 1.6), (12.8, 6.4, 3.2), dark, (1, 1))

    root = bpy.data.objects.new("WuxiuHall", None)
    link(root)
    for obj in list(bpy.context.scene.objects):
        if obj is root or obj.name == "Ground":
            continue
        world = obj.matrix_world.copy()
        obj.parent = root
        obj.matrix_world = world
    return root


def look_at(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_stills():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1440
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "use_raytracing"):
        scene.eevee.use_raytracing = True

    bpy.ops.object.light_add(type="SUN", location=(0, -6, 14))
    sun = bpy.context.object
    sun.data.energy = 4.5
    sun.data.color = (1.0, 0.93, 0.84)
    sun.data.angle = math.radians(6)
    sun.rotation_euler = Vector((0.25, 0.85, -0.7)).to_track_quat("-Z", "Z").to_euler()
    bpy.ops.object.light_add(type="AREA", location=(1.5, -9.5, 6.5))
    fill = bpy.context.object
    fill.data.energy = 2500
    fill.data.size = 14
    fill.data.color = (1.0, 0.95, 0.88)
    fill.rotation_euler = Vector((0, 1, -0.15)).to_track_quat("-Z", "Z").to_euler()

    world = bpy.data.worlds.new("Studio")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.74, 0.74, 0.72, 1.0)
    background.inputs["Strength"].default_value = 0.7

    bpy.ops.object.camera_add(location=(12.4, -15.2, 6.6))
    camera = bpy.context.object
    scene.camera = camera
    shots = (
        (PREVIEW_PATH, (12.4, -15.2, 6.6), (0.0, -0.4, 4.4), False, 18),
        (FRONT_PATH, (0.0, -20.0, 4.6), (0.0, 0.0, 4.6), True, 22),
        (SIDE_PATH, (20.0, 0.2, 4.6), (0.0, 0.2, 4.6), True, 18),
    )
    for path, location, target, ortho, scale in shots:
        camera.location = location
        look_at(camera, target)
        camera.data.type = "ORTHO" if ortho else "PERSP"
        camera.data.ortho_scale = scale
        camera.data.lens = 38
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
    for obj in (sun, fill, camera):
        bpy.data.objects.remove(obj, do_unlink=True)


def export_files(root):
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print("WUXIU_HALL_BUILT blend=%s glb=%s" % (BLEND_PATH, GLB_PATH))


if __name__ == "__main__":
    hall = build()
    render_stills()
    export_files(hall)
