# 独立战斗服验证

## 启动和试玩

在项目根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/start_battle_server.ps1
```

独立 Headless 常开房间 1 使用 UDP 24680 和原庭院。地图 2 用 `tools/start_battle_server.ps1 -Port 24681 -Map mountain_courtyard` 启动，对应菜单“加入独立战斗服2 · 山门演武场”。两边最多两名玩家及两只不占席位的稻草人。本机地址 127.0.0.1，另一台电脑填服务器 IP。协议已升级至 5，旧游戏进程需重新运行。

Q 冲锋再 Q 挑飞，E 旋伞，F 飞锅/召回，C 扣锅，Shift 闪现（冷却 3 秒，硬直、浮空、击飞中可放），空格跳，左键连拳，右键踢，F8 退出。稻草人坐标 -8/-8 与 8/8，2000 HP，死后 3 秒复活，不影响 PvP 比分。玩家 400 HP，回合结束 2.5 秒重置。

山门演武场额外固定 1/2 鼠标技能：1 甩出鼠标，最远约 16 米，仅飞行中的鼠标本体碰撞挂线；连接期间再按 1 拉回目标。无连接时 2 剪切闪，先穿行、后以大 X 路径爆发击飞；连接时 2 交换双方位置。连接持续 5 秒，Q/Shift 不主动断线。按键动作和命中最终以服务器为准。

## 自动回归

```powershell
godot_console.exe --headless --path . --script res://tests/battle_world_test.gd
godot_console.exe --headless --path . --script res://tests/arena_layout_test.gd
godot_console.exe --headless --path . --script res://tests/mountain_arena_test.gd
godot_console.exe --headless --path . --script res://tests/battle_entities_test.gd
godot_console.exe --headless --path . --script res://tests/battle_combo_test.gd
godot_console.exe --headless --path . --script res://tests/attack_direction_test.gd
godot_console.exe --headless --path . --script res://tests/battle_mouse_test.gd
godot_console.exe --headless --path . --script res://tests/battle_core_test.gd
godot_console.exe --headless --path . --script res://tests/combat_core_test.gd
powershell -ExecutionPolicy Bypass -File tools/run_battle_test.ps1
powershell -ExecutionPolicy Bypass -File tools/run_battle_test.ps1 -Impaired
powershell -ExecutionPolicy Bypass -File tools/run_battle_test.ps1 -Combo -Impaired
```

- battle_world_test：360 Tick 完整世界对照、周期性快照恢复重放、真实时间轴挑飞→旋伞→飞锅→再次挑飞→空中扣锅、飞锅中途恢复、快照编解码/乱序分包、重复动作、双方同时挑飞、预测误命中的整世界恢复、死亡复活与旧 life 输入拒绝。
- arena_layout_test：客户端可见庭院与客户端预测/Headless 权威碰撞逐项核对 ID、位置和简单形状，并验证玩家与稻草人出生点来自同一布局。
- mountain_arena_test：第二张山门演武场的客户端碰撞、预测/权威碰撞、出生点、地图 ID 和 Blender 导出资产一致性。
- battle_entities_test：动态阻挡、共享受击、墙边反弹/落地、飞锅去回各一次、死亡防重、NPC/PvP 隔离、同 Tick 多人命中、相互致死平局。同一世界 Tick 判断命中。
- battle_combo_test：保留击飞高度、旋伞续空、冷却、预输入、空中扣锅等数值回归；不是单独以此证明联网连招。
- attack_direction_test：30° 瞄准修正、雨伞 Q 锁定身体面向、旋伞显示分离，以及本地预测位置直出/纠偏偏移限时消除。
- battle_mouse_test：鼠标飞行挂线及预测、交换、落空与冷却、向下甩的离脚距离、较高浮空目标、远距离目标、拉回、剪切闪多人路径命中和地面击飞、空中滞空、特效运行。
- battle_core_test / combat_core_test：基础运动、可靠通道和伤害规则。
- 默认双客户端测试：真实场景加入、移动、出拳、同步扣血、浮空、飞锅、闪现、准星。
- -Combo：两游戏客户端分别接近两只稻草人，按 Tick 操作整套连招，以服务器确认事件断言两次挑飞、旋伞、飞锅去程、空中扣锅。
- -Impaired：每方向 50±20 ms 延迟，5% 丢包、2% 重复包。不是所有公网条件的保证。

真实 UDP 协议脚本使用另一个**隔离房间**：

```powershell
godot_console.exe --headless --path . --script res://server/battle_server.gd -- --port=24786
python tests/battle_npc_protocol_test.py 24786
python tests/battle_protocol_test.py 24786
```

NPC 脚本验证晚加入 HP/位置、飞锅两段和人数限制；生命周期脚本验证伪造结果、重复攻击、比分、回合、超时重连。勿针对真人正在使用的房间运行。这两份脚本使用协议 5 的输入帧格式。验收不用 `battle_transport_client`。

## 排查

日志在 test_output。BATTLE_SYNC 显示服务器 Tick、本地提前量、RTT、未确认输入数、同 Tick 最大实体位置差、恢复重放后本地位置差、迟到重排次数和累计重放步数。初次入场的出生距离不当作纠偏错误。测试输出有 PASS 才表示相应断言通过；证书存储、用户日志路径和 dummy renderer 材质警告与 GDScript 错误应分开处理。

本轮通过世界一致性、数值回归、正常/弱网双客户端、弱网完整连招与 NPC 协议验证。自动化是无画面客户端，不能替代真机画面和手感验收。

两台电脑仍应连续对打 10～15 分钟：墙边浮空、互相打断、同时上勾、飞锅召回、死亡重开、F8 重连。遇到拉扯请保留双方日志和发生时间。未知远端输入仍需纠偏，不能宣称零回滚。咖啡、椅子、AI、组队、多人数、公网防护不在本轮范围。
