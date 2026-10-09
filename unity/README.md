# Unity 第一阶段：山门演武场 1v1 竖切片

## 内容

- 两个玩家连接一台专用战斗服；第三人拒绝进入。
- 共用 C# 固定 60 Hz 战斗模拟。客户端预测移动与旋伞，服务器裁决命中和血量；30 Hz 全世界快照用于恢复、重演未确认输入。
- 仅有占位几何。旋伞按 E，移动用 WASD，鼠标控制观察方向；靠近另一个玩家约 3 米可命中。双方各 100 HP，旋伞造成 25 伤害，死亡后 3 秒复活。
- 这不是旧 Godot UDP 协议的兼容客户端，也没有其余技能、正式山门美术或房间匹配。

## 本机 C# 验证

已安装到 D:\dotnet 的 SDK 可运行：

```powershell
& D:\dotnet\dotnet.exe run --project .\Validation\Validation.csproj
& D:\dotnet\dotnet.exe run --project .\Validation\SyntaxCheck\SyntaxCheck.csproj
```

第一个验证命中、冷却和恢复重演；第二个解析 Unity 代码语法。Unity 6000.3.26f1 已完成实际编译、Windows 客户端与 Linux Dedicated Server 导出，并用本机 Windows 进程验证两人入场、快照、输入和服务器旋伞扣血。Visual Studio 不是 Unity 编译 C# 的必需组件。

## 打开与运行

1. 安装 Unity 6000.3.26f1，以及 Linux Dedicated Server Build Support 模块。用 Unity Hub 打开本目录。Package Manager 会拉取固定提交的 FishNet 4.7.3。
2. 首次导入后，编辑器脚本自动创建并打开 `Assets/Scenes/Arena.unity`。若没有自动打开，可从菜单 `Desk Mayhem/Prepare Arena Scene` 执行。
3. 菜单 `Desk Mayhem/Build Client And Linux Server` 构建两种包，输出在 `Builds/`。
4. Linux 上运行服务端：`./DeskMayhemServer -batchmode -nographics --port 24681`。在两台客户端运行 `DeskMayhemClient`，输入服务器 IP 和端口连接。开发时可在 Unity 编辑器中按 Play，连接同一服务端。

本机编辑器位于 `D:\unity\Editor\6000.3.26f1`，.NET SDK 位于 `D:\dotnet`。本机联机冒烟测试使用两个无界面 Windows 客户端和一个 Windows 战斗服进程，已验证服务器两次命中后双方血量为 75/75。Linux 包已成功构建，尚未在 Linux 主机运行；第三人拒绝、断线席位回收以及公网延迟/丢包下的纠偏仍需专项验收。
