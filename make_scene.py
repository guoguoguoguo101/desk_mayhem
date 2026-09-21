"""Generate an editable Godot scene using only built-in primitive meshes."""
from pathlib import Path

resources = []
nodes = []
mesh_ids = {}
material_ids = {}
shape_ids = {}
rid = 1


def resource(kind, props):
    global rid
    key = str(rid)
    rid += 1
    resources.append(f'[sub_resource type="{kind}" id="{key}"]\n' + '\n'.join(f'{k} = {v}' for k, v in props.items()))
    return key


def mat(color):
    if color not in material_ids:
        material_ids[color] = resource('StandardMaterial3D', {
            'albedo_color': f'Color({color})',
            'roughness': '0.83',
        })
    return material_ids[color]


def mesh(kind, size):
    key = (kind, tuple(size))
    if key not in mesh_ids:
        if kind == 'BoxMesh':
            props = {'size': f'Vector3({", ".join(map(str, size))})'}
        elif kind == 'SphereMesh':
            props = {'radius': str(size[0]), 'height': str(size[0] * 2), 'radial_segments': '16', 'rings': '8'}
        else:
            props = {'top_radius': str(size[0]), 'bottom_radius': str(size[0]), 'height': str(size[1])}
        mesh_ids[key] = resource(kind, props)
    return mesh_ids[key]


def shape(size):
    key = tuple(size)
    if key not in shape_ids:
        shape_ids[key] = resource('BoxShape3D', {'size': f'Vector3({", ".join(map(str, size))})'})
    return shape_ids[key]


def node(name, kind, parent='.', props=None, groups=None):
    props = props or {}
    parent_attr = '' if parent is None else f' parent="{parent}"'
    group_attr = '' if not groups else ' groups=["' + '", "'.join(groups) + '"]'
    nodes.append(f'[node name="{name}" type="{kind}"{parent_attr}{group_attr}]\n' + '\n'.join(f'{k} = {v}' for k, v in props.items()))


def pos(v):
    return f'Vector3({", ".join(map(str, v))})'


def part(name, parent, xyz, size, color, kind='BoxMesh', solid=False):
    node(name, 'MeshInstance3D', parent, {
        'position': pos(xyz),
        'mesh': f'SubResource("{mesh(kind, size)}")',
        'surface_material_override/0': f'SubResource("{mat(color)}")',
    })
    if solid:
        node(name + 'Body', 'StaticBody3D', parent, {'position': pos(xyz)})
        node('CollisionShape3D', 'CollisionShape3D', parent + '/' + name + 'Body', {
            'shape': f'SubResource("{shape(size)}")',
        })


node('OfficeDemo', 'Node3D', None)
node('Environment', 'WorldEnvironment', props={'environment': 'SubResource("ENV")'})
node('Sun', 'DirectionalLight3D', props={
    'rotation_degrees': pos((-48, -35, 0)),
    'light_energy': '1.05',
    'shadow_enabled': 'true',
})
node('CameraRig', 'Node3D', props={'script': 'ExtResource("2")'})
node('PitchPivot', 'Node3D', 'CameraRig', {'rotation_degrees': pos((-30, 0, 0))})
node('SpringArm3D', 'SpringArm3D', 'CameraRig/PitchPivot', {
    'spring_length': '6.0',
    'margin': '0.15',
})
node('Shaker', 'Node3D', 'CameraRig/PitchPivot/SpringArm3D')
node('Camera3D', 'Camera3D', 'CameraRig/PitchPivot/SpringArm3D/Shaker', {
    'current': 'true',
    'fov': '68.0',
    'near': '0.1',
})
node('CombatFeedback', 'Node3D', props={'script': 'ExtResource("4")'})
node('Architecture', 'Node3D')
part('Floor', 'Architecture', (0, -0.17, 0), (110, .3, 80), '0.46, 0.53, 0.54, 1', solid=True)
for name, xyz, size in [
    ('NorthWall', (0, 1.25, -40), (110, 2.5, .28)),
    ('SouthWall', (0, 1.25, 40), (110, 2.5, .28)),
    ('WestWall', (-55, 1.25, 0), (.28, 2.5, 80)),
    ('EastWall', (55, 1.25, 0), (.28, 2.5, 80)),
]:
    part(name, 'Architecture', xyz, size, '0.31, 0.40, 0.43, 1', solid=True)
for i, x in enumerate(range(-50, 51, 10)):
    part(f'FloorLineX{i}', 'Architecture', (x, .005, 0), (.045, .015, 79), '0.56, 0.63, 0.62, 1')
for i, z in enumerate(range(-35, 36, 10)):
    part(f'FloorLineZ{i}', 'Architecture', (0, .005, z), (109, .015, .045), '0.56, 0.63, 0.62, 1')
part('CenterCircle', 'Architecture', (0, .012, 0), (3.3, .02), '0.8, 0.65, 0.35, 1', 'CylinderMesh')

node('Furniture', 'Node3D')
desk_color = '0.64, 0.43, 0.28, 1'
metal = '0.28, 0.35, 0.37, 1'
screen = '0.22, 0.38, 0.48, 1'
for i, (x, z) in enumerate([(-6, -4), (-2, -4), (2, -4), (-6, 0), (-2, 0), (2, 0)]):
    p = f'Furniture/Desk{i+1}'
    node(f'Desk{i+1}', 'Node3D', 'Furniture', {'position': pos((x, 0, z))})
    part('Top', p, (0, .88, 0), (2.5, .18, 1.2), desk_color, solid=True)
    for j, sx in enumerate((-.98, .98)):
        part(f'Leg{j+1}', p, (sx, .42, 0), (.12, .84, .8), metal)
    part('Monitor', p, (0, 1.35, -.29), (.9, .62, .08), screen)
    part('MonitorStem', p, (0, 1.05, -.29), (.07, .3, .07), metal)
    part('Keyboard', p, (0, 1.005, .27), (.85, .04, .24), '0.86, 0.86, 0.8, 1')
    part('ChairSeat', p, (0, .48, 1.25), (.68, .15, .62), '0.35, 0.51, 0.56, 1')
    part('ChairBack', p, (0, .91, 1.53), (.68, .8, .13), '0.35, 0.51, 0.56, 1')
    part('ChairBase', p, (0, .23, 1.25), (.1, .4, .1), metal)

node('MeetingArea', 'Node3D')
part('MeetingTable', 'MeetingArea', (6.5, .85, 2.2), (4.1, .18, 1.65), '0.51, 0.34, 0.25, 1', solid=True)
for i, (x, z) in enumerate([(5.1, .7), (7.8, .7), (5.1, 3.7), (7.8, 3.7)]):
    part(f'Stool{i+1}', 'MeetingArea', (x, .48, z), (.6, .2, .6), '0.43, 0.56, 0.57, 1')
part('Whiteboard', 'MeetingArea', (7.2, 1.35, -10), (3.2, 1.35, .09), '0.94, 0.94, 0.86, 1')

node('BreakArea', 'Node3D')
part('CoffeeCounter', 'BreakArea', (-7.2, .8, 5.7), (3.8, 1.5, 1.15), '0.48, 0.61, 0.58, 1', solid=True)
part('CoffeeMachine', 'BreakArea', (-8, 1.75, 5.55), (.55, .5, .48), metal)
part('CoffeeCup', 'BreakArea', (-6.7, 1.62, 5.5), (.16, .26), '0.94, 0.8, 0.58, 1', 'CylinderMesh')
part('FilingCabinet', 'BreakArea', (-9.2, .95, -5.7), (1.35, 1.9, .9), '0.39, 0.53, 0.54, 1', solid=True)
for i in range(3):
    part(f'Drawer{i+1}', 'BreakArea', (-9.2, .5 + i*.5, -5.21), (.95, .37, .05), '0.71, 0.78, 0.73, 1')
for i, (x, z) in enumerate([(9.4, 6.5), (9.3, -6.5), (-9.2, 2.6)]):
    part(f'Planter{i+1}', 'BreakArea', (x, .38, z), (.42, .72, .42), '0.68, 0.46, 0.31, 1')
    part(f'Plant{i+1}', 'BreakArea', (x, 1.06, z), (.58,), '0.29, 0.55, 0.4, 1', 'SphereMesh')

node('ArenaCover', 'Node3D')
for zone, (cx, cz) in enumerate([(-29, -19), (29, -19), (-29, 19), (29, 19)], 1):
    part(f'ZoneRug{zone}', 'ArenaCover', (cx, .018, cz), (15, .025, 11),
         '0.34, 0.52, 0.54, 1' if zone % 2 else '0.56, 0.42, 0.35, 1')
    for j, (dx, dz) in enumerate([(-4, -2), (4, -2), (-4, 3), (4, 3)]):
        part(f'CoverDesk{zone}_{j}', 'ArenaCover', (cx+dx, .85, cz+dz),
             (2.7, .75, 1.3), desk_color, solid=True)
        part(f'CoverMonitor{zone}_{j}', 'ArenaCover', (cx+dx, 1.46, cz+dz-.25),
             (.8, .55, .12), screen)
    part(f'ZoneDivider{zone}', 'ArenaCover', (cx, .65, cz), (1.0, 1.3, 8.0),
         '0.42, 0.62, 0.62, 1', solid=True)
for i, (x, z) in enumerate([(-44,-30),(-44,0),(-44,30),(44,-30),(44,0),(44,30),
                            (-18,-31),(18,-31),(-18,31),(18,31)]):
    part(f'Crate{i}', 'ArenaCover', (x, .65, z), (2.2, 1.3, 2.2),
         '0.61, 0.43, 0.28, 1', solid=True)

node('Player', 'CharacterBody3D', props={
    'position': pos((0, .96, 4.8)),
    'script': 'ExtResource("1")',
})
node('CollisionShape3D', 'CollisionShape3D', 'Player', {
    'shape': f'SubResource("{resource("CapsuleShape3D", {"radius": "0.38", "height": "1.7"})}")',
})
node('Visual', 'Node3D', 'Player')
dog = '0.76, 0.49, 0.3, 1'
cream = '0.95, 0.84, 0.64, 1'
dark = '0.14, 0.13, 0.14, 1'
shirt = '0.27, 0.48, 0.72, 1'
part('Body', 'Player/Visual', (0, -.14, 0), (.48,), shirt, 'SphereMesh')
part('Head', 'Player/Visual', (0, .49, -.11), (.45,), dog, 'SphereMesh')
part('Muzzle', 'Player/Visual', (0, .36, -.48), (.24,), cream, 'SphereMesh')
part('Nose', 'Player/Visual', (0, .43, -.7), (.085,), dark, 'SphereMesh')
for side, x in [('L', -.31), ('R', .31)]:
    part(f'Ear{side}', 'Player/Visual', (x, .88, -.01), (.19, .42, .23), dark)
    part(f'Eye{side}', 'Player/Visual', (x*.72, .62, -.46), (.07,), dark, 'SphereMesh')
    part(f'Arm{side}', 'Player/Visual', (x*1.7, -.12, -.03), (.18, .44, .2), dog)
    part(f'Foot{side}', 'Player/Visual', (x*.85, -.69, -.1), (.23, .33, .32), dark)
part('Collar', 'Player/Visual', (0, .15, -.08), (.7, .11, .55), '0.88, 0.3, 0.28, 1')
part('Badge', 'Player/Visual', (.18, -.15, -.48), (.16, .22, .04), '0.97, 0.86, 0.36, 1')
part('Tail', 'Player/Visual', (0, -.3, .49), (.15,), dog, 'SphereMesh')

node('Umbrella', 'Node3D', 'Player/Visual', {
    'position': pos((0.42, 0.04, -0.67)),
    'visible': 'false',
})
part('UmbrellaHandle', 'Player/Visual/Umbrella', (0, 0, 0), (.07, .9, .07), '0.24, 0.26, 0.3, 1')
umbrella_mesh = resource('CylinderMesh', {
    'top_radius': '0.04',
    'bottom_radius': '0.67',
    'height': '0.32',
    'radial_segments': '12',
})
node('UmbrellaCanopy', 'MeshInstance3D', 'Player/Visual/Umbrella', {
    'position': pos((0, .56, 0)),
    'mesh': f'SubResource("{umbrella_mesh}")',
    'surface_material_override/0': f'SubResource("{mat("0.89, 0.25, 0.26, 1")}")',
})

node('ChairWeapon', 'Node3D', 'Player/Visual', {
    'position': pos((0.52, 0.16, -0.5)),
    'visible': 'false',
})
part('ChairWeaponSeat', 'Player/Visual/ChairWeapon', (0, 0, 0), (.62, .13, .6), '0.34, 0.56, 0.7, 1')
part('ChairWeaponBack', 'Player/Visual/ChairWeapon', (0, .36, .26), (.62, .72, .12), '0.34, 0.56, 0.7, 1')
part('ChairWeaponStem', 'Player/Visual/ChairWeapon', (0, -.26, 0), (.08, .46, .08), metal)

dummy_shape = resource('CapsuleShape3D', {'radius': '0.48', 'height': '1.8'})
for index, (x, z) in enumerate([
    (0, 1.0), (0, -1.6), (0, -8.4), (-4.5, 8.0), (0, 9.2),
    (4.5, 8.0), (8.5, -2.0), (-8.5, -1.0),
    (-20, -15), (20, -15), (-20, 15), (20, 15),
    (-40, -18), (40, -18), (-40, 18), (40, 18),
], 1):
    name = f'TrainingDummy{index}'
    node(name, 'CharacterBody3D', props={
        'position': pos((x, 0, z)),
        'script': 'ExtResource("3")',
    }, groups=['training_dummies', 'combat_targets'])
    node('CollisionShape3D', 'CollisionShape3D', name, {
        'position': pos((0, 1.0, 0)),
        'shape': f'SubResource("{dummy_shape}")',
    })
    node('Visual', 'Node3D', name)
    part('Post', name + '/Visual', (0, .85, 0), (.18, 1.7, .18), '0.54, 0.34, 0.2, 1')
    part('Head', name + '/Visual', (0, 1.55, 0), (.34,), '0.78, 0.66, 0.45, 1', 'SphereMesh')
    part('Body', name + '/Visual', (0, .95, 0), (.48, .78, .25), '0.72, 0.59, 0.39, 1')
    part('Crossbar', name + '/Visual', (0, 1.18, 0), (1.25, .13, .13), '0.54, 0.34, 0.2, 1')
    part('Base', name + '/Visual', (0, .08, 0), (1.1, .16, 1.1), '0.38, 0.43, 0.39, 1')
    node('HitLabel', 'Label3D', name, {
        'position': pos((0, 2.2, 0)),
        'text': '"训练稻草人"',
        'font_size': '40',
        'pixel_size': '0.006',
        'billboard': '1',
        'modulate': 'Color(1, 0.9, 0.56, 1)',
    })

node('HUD', 'CanvasLayer')
node('Instructions', 'Label', 'HUD', {
    'offset_left': '24.0',
    'offset_top': '20.0',
    'offset_right': '650.0',
    'offset_bottom': '80.0',
    'theme_override_font_sizes/font_size': '20',
    'text': '"WASD 移动  |  鼠标转视角  |  Shift 闪现  |  空格跳跃\\n左键文件夹  |  右键咖啡  |  Q 冲刺→Q 挑飞  |  F 踢  |  E 椅子"',
})
env = resource('Environment', {
    'background_mode': '1',
    'background_color': 'Color(0.67, 0.76, 0.79, 1)',
    'ambient_light_source': '2',
    'ambient_light_color': 'Color(1, 0.96, 0.88, 1)',
    'ambient_light_energy': '0.6',
    'tonemap_mode': '2',
})
resources[-1] = resources[-1].replace(f'id="{env}"', 'id="ENV"')

header = '[gd_scene load_steps=' + str(len(resources)+5) + ' format=3]\n\n[ext_resource type="Script" path="res://player.gd" id="1"]\n[ext_resource type="Script" path="res://follow_camera.gd" id="2"]\n[ext_resource type="Script" path="res://dummy.gd" id="3"]\n[ext_resource type="Script" path="res://combat_feedback.gd" id="4"]'
Path('office_demo.tscn').write_text(header + '\n\n' + '\n\n'.join(resources) + '\n\n' + '\n\n'.join(nodes) + '\n', encoding='utf-8')
print('Generated office_demo.tscn with', len(nodes), 'nodes')
