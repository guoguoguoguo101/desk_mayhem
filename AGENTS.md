# 项目入口

开始分析或修改本项目之前，先阅读仓库根目录的 `PROJECT_CONTEXT.md`。它是当前玩法、操作、地图和联机范围的简要快照。代码改动使这些描述失效时，同步更新该文件。

涉及战斗同步时，再阅读 `NETWORK_ARCHITECTURE.md`。局域网 ENet 开房和独立 UDP 战斗服都已实现，是两条分开的路径。

独立 UDP 战斗服的协议或共享战斗规则改动需要客户端与服务端同步更新时，按 `.cursor/rules/network-combat-prediction.mdc` 的流程更新版本、验证并直接重启本机正在运行的战斗服；不要停 Godot 编辑器或 ENet 房间。
