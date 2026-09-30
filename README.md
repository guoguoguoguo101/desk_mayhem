# 工位失控

Godot 4 第三人称乱斗原型。用 Godot 打开 `project.godot`，运行后在菜单选择单人练习、局域网比武大厅，或加入独立战斗服。

**接手项目请先读 [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)**：当前玩法、操作、地图、联机范围，以及尚未落地的内容。游戏内 HUD 显示实际按键和武器冷却。

独立战斗服的同步见 [NETWORK_ARCHITECTURE.md](NETWORK_ARCHITECTURE.md)，启动和回归见 [BATTLE_TESTING.md](BATTLE_TESTING.md)。

## 首次拉取与资源导入

图片、模型和音频使用 Git LFS。首次克隆前先安装 Git LFS；在仓库目录运行 `git lfs install` 和 `git lfs pull`，确认真实资源已下载，再用 Godot 编辑器打开 `project.godot`，等待资源导入完成后运行游戏。

以后正常 `git pull` 会在 Git LFS 已安装且正常工作时下载新资源。如果此前没装 LFS、下载中断，或文件仍是以 `version https://git-lfs.github.com/spec/v1` 开头的文本指针，安装 LFS 后在仓库目录重新运行 `git lfs pull`。例如 `res://assets/vfx/spark.png` 的预加载报错通常先检查这一点；资源下载完成后重新打开 Godot，让编辑器导入图片。
