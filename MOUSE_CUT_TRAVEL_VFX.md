# X 剪切闪：穿行特效实现与改进方案

本文只讨论山门演武场 X 剪切闪从起手到穿行结束的**客户端画面**。停身后的地裂、光柱、冲击环和伤害结算不在本文范围。玩法边界见 `MOUSE_WEAPON_DESIGN.md`，当前操作见 `PROJECT_CONTEXT.md`。

## 目标画面

以本次讨论提供的四张参考图为方向：

1. 起步时，狐狸身后出现明显的蓝金弧形尾气；路径上有数量多、亮度高的蓝金长光条。
2. 穿行时，依次留下三只狐狸残影，每只残影都有向后的拖尾。第一只初始最亮，第二只中等，第三只较暗；各自随后继续淡出。
3. 后半程光条逐渐稀疏，残影逐渐碎成越来越多的蓝色方块。尾声只补少量金色方块。
4. 穿行本身仅 9 Tick，约 0.15 秒。残影与碎片应在停身后保留短暂余韵，才能看清上述变化。

这里的“阶段”是重叠的视觉轨道，不是前一轨完全结束后才启动下一轨。计划中的数量、透明度和寿命是美术调参项，需在预览场景和实战镜头下确定。

参考图保存在仓库中，便于后续对照：

| 图 | 观察重点 |
| --- | --- |
| [图 1：残影层次](docs/mouse_cut_references/01_ghost_sequence.png) | 狐狸残影的明暗顺序、轮廓和各自拖尾 |
| [图 2：整段冲锋](docs/mouse_cut_references/02_full_path.png) | 起步到残影之间的蓝金光路与地面能量感 |
| [图 3：起步尾气](docs/mouse_cut_references/03_start_exhaust.png) | 起点处弯曲的蓝金大弧线 |
| [图 4：路径光条](docs/mouse_cut_references/04_speed_streaks.png) | 密集、细长、方向一致的蓝金速度条 |

## 2026-09-30 实现更新

2026-10-01 梭形 GPU 粒子版本（当前）：`mouse_cut_spindle.png` 替换旧彗星形光条贴图，两头尖、中间宽，真实透明背景。每段真实路径生成一次性 GPUParticles3D 批次，`mouse_cut_drop_process.gdshader` 控制大小、亮度、前下方速度、重力、独立寿命及单次轻反弹；`mouse_cut_drop_draw.gdshader` 让面片面向镜头、长轴沿投影速度，并采样贴图染成蓝金色。大光滴概率 18%，金色概率 22%，可反弹概率 25%；反弹恢复系数 0.28，水平速度保留 65%，竖直速度最多 1.6。触地后非反弹粒子立即消失；反弹粒子第二次触地也消失。每批射线读取出生点地面高度，预览无碰撞时按角色脚底高度回退；这是局部地面平面的视觉近似，不是全地形碰撞。路径纠偏、life 与死亡清理沿用统一管理。旧静态光条网格停用。

新贴图使用内置 imagegen 生成，提示要求：单颗横向梭形能量光滴、左右两端尖、中间最宽、灰白亮核和柔光、实际透明背景、无彗星头尾及文字，供蓝金染色。

2026-10-01 贴图版本：生成并接入透明雨滴能量贴图 `assets/vfx/mouse_cut_raindrop.png`，保留原始 alpha。路径光条现在由合并网格承载贴图，Shader 染色并控制透明度；不是 GPU 光条粒子。大光滴约占 22%，其余为长短粗细不一的小光滴；下倾角和横向散开独立随机，形成方向一致但凌乱的分布。起点高密、后段低疏的编排继续保留。

2026-10-01 光条调整：路径直线光条使用独立的雨滴轮廓 Shader 分支，具有较宽的亮头、渐细尾巴及柔光边；每段数量按自身进度从约 30 条递减至 2 条，最后一段不再补充。网格宽度方向以竖直方向为主，避免常用侧视镜头把水平条带看成丝线。弧形尾气、残影拖尾沿用细带分支，不受此次加宽影响。

客户端穿行视觉已统一到 `MouseSkillVFX._sync_cut_track()`，实战与两份预览仅注册狐狸视觉源，复用同一条生命周期。三只能量狐狸在路径索引 1、3、5 生成，使用蓝色主体、青白轮廓与消散亮边，初始透明度为 0.9、0.6、0.35，并附带渐细拖尾。起步弧线与蓝金长光条使用合并程序网格；光条按各段自己的进度从密到疏。蓝色方块延迟、分批启动，金色方块在尾声点缀。旧竖直 Ribbon 已移除，保留较淡的水平底光。

路径保存深复制副本，逐段比较坐标；同段数坐标变化和路径缩短都会清理旧视觉并重建。动作 Tick 与 life 区分施放，死亡和实体移除清理视觉。跳帧补段会回补残影年龄，避免全部同时出生。光路在路径停止增长后按自己的寿命淡出，不等待整个技能恢复结束。两份预览使用统一时间倍率覆盖位移、Shader、残影及 GPU 粒子。

已运行 `tools/test_cut_travel_vfx.gd` 验证跳帧补齐、同段数纠偏、路径缩短、换 life 和死亡清理；两份预览通过运行检查。`tools/cut_vfx_review.gd` 可输出原速穿行结束附近的实际渲染图。美术仍需实战镜头下评估，模型表面消散与碎片出生位置尚未做到逐点对应；透明绘制成本尚未用性能分析器验收。

## 改动前实现：主线程、Tick 与画面帧

客户端的 `_physics_process()` 和 `_process()` 是 Godot 以不同节奏调用的脚本回调，并非两个由项目创建的并行线程。前者按固定物理频率推进预测世界，后者每个画面帧更新显示节点。网格、材质、粒子配置由脚本提交，实际像素由渲染系统绘制。

按 X 后，`player.gd` 把 `mouse_secondary` 交给 `BattleClientSession.request_action()`。在没有有效挂线或飞行鼠标时，它被映射为 `mouse_cut`，暂存于 `queued_actions`。下一个物理 Tick，`battle_client_session.gd::_physics_process()` 将动作放入命令并调用 `WorldPrediction.predict()`；后者同步调用 `CombatWorld.step()`。`step()` 当次执行 `_resolve_attack()`，设置 `action = "mouse_cut"`、`action_tick`、锁定方向并清空 `mouse_cut_path`。`queued_actions` 是等待下一个物理 Tick 的输入数组；`predict()` 和 `step()` 不是延后执行的任务队列。

设接受动作的 Tick 为 **T**，当前穿行时间线如下：

| Tick | 物理 Tick 内的工作 | 下一个画面帧看到的结果 |
| --- | --- | --- |
| T | 开始动作；路径为空；同 Tick 调用 `_advance_mouse_cut()`，因经过时间为 0，不移动 | `sync_world()` 识别新 `action_tick`，清空该次冲锋的光带显示记录 |
| T+1～T+3 | 起手，路径仍为空 | 不产生路径光带 |
| T+4～T+12 | `_advance_mouse_cut()` 每 Tick 尝试前进 `8 / 9` 米，取碰撞后的实际位置，将 `[start, finish]` 加入路径；撞墙则停止后续穿行 | 路径段数增加时，重建 Ribbon 和速度线；部分新段触发残影、线框 |
| T+12 后 | 穿行停止，动作状态仍可持续 | 实战中路径光带仍显示并流动，待动作退出 `mouse_cut` 后才开始约 0.3 秒淡出 |

每个画面帧的调用链是：

```text
BattleClientSession._process(delta)
  -> _render(delta)
    -> MouseSkillVFX.sync_world(预测实体状态, 当前 Tick, delta)
```

`sync_world()` 比较本次 `mouse_cut_path.size()` 与上次绘制的 `cut_segments`。段数变了，便用 `SurfaceTool` 根据全部已有段重建一张贴地加竖直的 Ribbon 网格，以及一张包含四道细线的速度线网格；段数没变时不重建形状。每个画面帧仍更新 Shader 的 `time` 参数，让亮纹沿 UV 流动。物理 Tick 与画面帧不是一一对应：高帧率下可能多帧共用一条路径；低帧率下一帧可能处理多个新增段。

当前客户端还会在路径段索引 1、3、5、7 复制狐狸视觉模型作为残影，立刻创建蓝色方块 GPU 粒子；`sync_world()` 在索引 4、6、8 创建短命发光线框。穿行中的狐狸使用 `UmbrellaDash` 姿态，并有轻微前倾。

### 当前节点与数据分工

| 对象 | 现有形式 | 更新方式 |
| --- | --- | --- |
| `mouse_cut_path` | 预测战斗状态中的实际路径段数组 | 物理 Tick 增加，快照恢复与重放可重算 |
| `MouseCutPathRibbon`、`MouseCutSpeedLines` | 每名玩家各一个 `MeshInstance3D` | 路径变长时 CPU 重建网格；Shader 绘制流动亮纹；不在 `bursts` |
| 狐狸残影 | 复制的狐狸视觉节点，带消散 Shader 与 Tween | 创建后定时清理；不在 `bursts` |
| 残影方块 | 每只残影一个 `GPUParticles3D` 发射器 | 粒子在 GPU 上运动；发射器结束时清理；不在 `bursts` |
| 发光线框 | 一个 `Node3D` 根节点与数根细圆柱网格 | 每组在 `bursts` 中一条记录，按画面帧 `delta` 更新年龄、缩放和透明度 |

`bursts` 是**已创建的短命视觉组存活表**，不是待执行任务队列，也不是战斗快照中的业务实体。冲锋主体光带无需进入它；线框目前需要它来管理寿命。

## 改进方案：共用一条视觉进度

穿行进度使用现有路径计算：`progress = mouse_cut_path.size() / 9.0`。`entity_id + action_tick + life` 标识一次穿行视觉。新增段只处理一次；画面帧跳过多个物理 Tick 时，循环补齐全部新增段。预测纠偏使路径缩短时，移除超出新路径的残影和光条并重建实例，避免保留未走过的画面。

| 进度 | 建议视觉编排 |
| --- | --- |
| 0～0.3 | 起步蓝金弧形尾气最亮；每段生成最多的蓝金长光条 |
| 0.2～0.7 | 依次生成三组带拖尾的狐狸残影；初始强度建议为 0.9、0.6、0.35，之后各自按年龄淡出 |
| 0.5～0.9 | 长光条逐段减少；分批启动蓝色方块发射，数量逐批增加；残影消散程度同步提高 |
| 0.85～1.0 | 停止补充长光条；蓝色方块达到高点，最后启动少量金色方块 |
| 穿行后 | 残影拖尾、光路和碎片按各自寿命淡出，视觉余韵可超过位移的 0.15 秒 |

计划中的客户端节点职责：

```text
MouseSkillVFX
  PathRibbon            沿真实路径延伸的连续底光，复用现有节点
  StartExhaust          起步时程序生成的两三道弧形尾气网格
  SpeedStreaks          蓝金长光条，优先用 MultiMeshInstance3D 批量绘制
  Ghosts[最多 3 组]
    FoxGhost            狐狸模型轮廓与消散 Shader
    GhostTrail           与该残影同生同灭的渐细拖尾网格
    BlueSquares         后半程才启动的 GPUParticles3D
  FinalGoldSquares      尾声一次性 GPUParticles3D
```

`StartExhaust` 用固定局部曲线生成弧形网格，随角色的起步位置和锁定方向摆放；蓝金渐变、亮核和淡出由 Shader 控制。`SpeedStreaks` 在每条新路径段上按确定性种子配置实例位置、长度和颜色，前段密集、后段稀疏；实例只在新段到来或纠偏重建时提交，不每帧逐条修改。`GhostTrail` 可将角色背部、尾部及脚边的几条渐细带合并成一张网格，沿冲锋反方向拉出；先在预览中校准实际狐狸姿态与锚点。

蓝色方块使用分批的一次性粒子发射器，并让残影消散曲线与粒子出现曲线相接。动态修改粒子总量可能重启发射，故先为每批设置固定数量，再按进度触发。金色方块使用独立的小批量发射器。光条、尾气和残影拖尾优先用程序网格与 Shader；现有狐狸材质和小方块贴图可先复用。只有在轮廓拖尾需要参考图中的笔刷或毛发细节时，再制作专用透明贴图。

### 客户端代码入口建议

沿用 `sync_world()` 读取路径的结构，拆出明确的视觉方法：

```gdscript
func sync_cut_travel(state: Dictionary, delta: float) -> void:
    var path: Array = state.get("mouse_cut_path", [])
	reconcile_action_and_path(state, path)      # 新动作或纠偏时重置视觉
	for segment_index in range(seen_segments, path.size()):
		var progress := float(segment_index + 1) / 9.0
        append_path_ribbon(path, segment_index)
        append_speed_streaks(path, segment_index, progress)
        maybe_spawn_ghost(path, segment_index)
        maybe_start_square_particles(path, segment_index)
	update_shader_time_and_fades(delta, float(path.size()) / 9.0)
```

这是**设计伪代码**，不是现有函数。`progress` 用于决定生成阶段；每个已经生成的视觉组另有自己的 `age` 和寿命。分层之后，后半程的方块粒子无需加入 `bursts`，残影和光条也不必按每个碎片创建独立 Node。

## 调试与验收

`vfx/MouseCutDashPreview.tscn` 可单独循环预览穿行，按 1 看原速，按 2～4 慢放。该预览在第 9 段结束时就把 `action` 清空，当前淡出时机与实战中动作继续持续的表现不同；实现方案时应使预览也能检查实战的视觉余韵。

验收时分别观察：三只残影是否有清楚的明暗层次和各自拖尾；蓝金光条是否从密到疏；蓝块是否只在后半程开始且逐批增加；金块是否只作尾声点缀。还需看低帧率下同时新增多个路径段、近墙提前停止、预测纠偏使路径缩短，以及连续施放时旧视觉是否及时清理。用 Godot 性能分析器确认主线程节点更新和透明材质绘制成本，再决定是否进一步合批或复用节点。

## 代码索引

- `player.gd`：X 按键入口。
- `client/battle_client_session.gd`：`request_action()`、`_physics_process()`、`_process()`、`_render()` 与残影触发。
- `client/world_prediction.gd`：同步预测、快照恢复与输入重放。
- `combat/combat_world.gd`：`step()`、`_resolve_attack()`、`_advance_mouse_cut()` 与路径状态。
- `combat/battle_rules.gd`：起手 4 Tick、穿行 9 Tick、距离 8 米。
- `vfx/mouse_skill_vfx.gd`：`sync_world()`、Ribbon、速度线、残影、线框与 `bursts`。
- `vfx/mouse_cut_ribbon.gdshader`、`vfx/mouse_cut_streaks.gdshader`、`vfx/mouse_cut_ghost.gdshader`：当前材质表现。
