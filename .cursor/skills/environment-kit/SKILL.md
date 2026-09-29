---
name: environment-kit
description: 按设计图复用或新增演武场环境构件（竹、石灯、柱、屋面、花草等），用生成或裁剪的贴图做成资产，导出独立 GLB 并摆进地图。在用户给出素材图、地图设计图、环境概念图，或要求复用、拆分、生成场景道具时使用。
---

# 环境构件

先读 `assets/environment/kits/catalog.json`。碰撞不从模型读取，玩法形状仍写在地图 layout。

## 从设计图到资产

用户给出设计图、素材图或地图方案时，按这个顺序做：

1. 先对照 catalog。同一类道具复用已有 kit，只加摆放。
2. 要接近设计图的表面（花、叶、瓦、石纹），用贴图。纯色块只适合还没做贴图的灰盒。
3. 贴图两种来源都可以：按设计图用脚本或 AI 生成；或从设计图里裁出叶子、花、纹样的一块。不要把整张设计图（含标注、多品种拼版、背景）原样贴到模型上。
4. 花和叶贴到透明卡片上，按透明边缘裁切。贴图只放在 `assets/environment/kits/textures/`，GLB 引用这一份，不要把同一张图嵌进每个模型，也不要在模型旁边再存一份。花丛用小张花团铺在冠层表面，花朝外，避免几片大叶子插在能看见的茎上。
5. 新资产注册成 kit。网格仍由 Blender 导出；摆到场上用地图搭建场景，不要为了挪位置去改 `place_kit`。

## 已有构件就复用

参考图和某个 kit 的 `description` 是同一类道具时，不要重新建模。

1. 在 Godot 中打开 `tools/map_builder/map_builder.tscn`，按 F6。从左侧把已有 kit 拖到场地上，Ctrl+S 保存。
2. 不要为了挪一件已有道具去改 `place_kit`，也不要为此重跑整张地图。
3. 保存后的 `kit_placements.json` 带 `authored`。此后 Blender 全量重建保留这份摆放，只更新 GLB 和 catalog。新资产进 catalog 后，重新打开搭建场景就能拖。
4. 不要把该道具的网格再写进 `mountain_arena_shell`。

## 没有才新增

1. 在 `tools/build_mountain_arena.py` 里做网格：重复件用共享 mesh，多部件道具用一个空父级。花和叶用上一节的透明贴图卡片。
2. `register_kit(id, 描述, origin)`。`origin` 用 `base`（地面接触点）或 `center`。
3. 导出前把网格放进 `KIT_DEFS[id]["mesh"]`，或把父级放进 `KIT_DEFS[id]["root"]`。
4. id 用小写加下划线，和文件名一致。跑 Blender 写出 `assets/environment/kits/<id>.glb` 并更新 catalog。文件已是手搭摆放时，脚本不会覆盖 `kit_placements.json`。
5. 打开地图搭建场景，把新 kit 拖进场地并保存。

```text
D:\Blender\blender.exe --background --python tools/build_mountain_arena.py
```

工作目录是仓库根目录。构件不加入碰撞体。若参考图是会挡住人的建筑，另在 `combat/mountain_arena_layout.gd` 写盒子或圆柱，并保持客户端、预测、权威三处仍读这一份布局。
