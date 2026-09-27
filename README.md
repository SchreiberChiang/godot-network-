# RoomKit：独立的本地房间框架

在 Windows 本机运行的多游戏房间框架，从零开发：一个独立管理后台，加上邀请码账号和永久资产，每个房间是一个独立的 Godot 进程。当前示例有横版射击和取石子。开发分支 `codex/shooter-framework`；实际通过、失败和未验收的项目只看 [STATUS](STATUS.md)。目前只在同一台电脑上验证过，第二台设备、Linux 和公网都还没有验收。

## 环境

- Windows 10/11，自带 Windows PowerShell 5.1 和系统 `winsqlite3.dll`；不需要 Node、数据库服务或其它后端。
- 从源码运行需要 Godot **4.7.2**。默认路径：

  ```text
  D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe
  ```

  脚本可以用 `-Godot '完整路径'` 指定其它可执行文件，但换版本后要重新验收。

## 从源码启动（推荐）

1. 双击 **`StartManagement.cmd`**，浏览器会打开 <http://127.0.0.1:28291/>。首次运行时设置管理员账号；管理员只能管理后台，不能作为玩家入房。
2. 在网页点“启动服务器”，然后在邀请码页创建邀请码。
3. 双击 **`StartShooterClient.cmd`**，用邀请码注册玩家账号并登录。再开第二个客户端，用另一个账号登录（同一账号不能同时在线）。在大厅或后台创建射击房间，两人加入后开始自由混战：左右移动/跳跃，鼠标瞄准射击；死亡后可打开背包选枪，再手动复活。
4. 取石子客户端用 **`StartManagedTurns.cmd`**，与射击共用同一套账号和资产服务。
5. 结束：网页上的“停止服务器”只停游戏宿主，后台保持运行；**`StopManagement.cmd`** 关闭整个管理服务。

私有数据在 `data/framework/`（账号库、资产库、配置、私钥），不会进入 Git 或玩家分发包。源码更新后按这个顺序重启：先退出旧客户端，然后 `StopManagement.cmd` → `StartManagement.cmd` → 在网页启动服务器并建房 → 重新打开客户端。账号和资产会保留。

管理后台的“玩家 → 详情 → 停用账号”会撤销玩家登录并保留账号与所有游戏资产；需要时用“恢复账号”。停用默认无限期，**不是删除数据**。这次界面更新尚未人工验收。

测试阶段要永久删除某个玩家时，用同一页面单独的“删除测试账号”：它清除该玩家在当前账号库和资产库中的账号与全部游戏资产，不可恢复；旧备份不改写，后台会列出并标注可能仍含该账号的备份。源码版已通过隔离测试，用户从项目目录启动并试玩后反馈删除正常。新独立 ZIP 已包含此功能，但自动包测试没有单独执行删除流程。说明见 [规划第七节](docs/17_framework_shooter_plan.md#七测试阶段账号删除2026-09-27已实现待复核)。

新注册、改密及管理员重置的密码长度为 8–128 字符；已有密码继续有效。源码和最新独立 ZIP 均已包含。

房间规则设置、背包与复活、局域网配置、备份恢复、客户端窗口排查和命令行等价入口，见 [本机启动与验证](docs/22_framework_operations.md)。

## 独立 Windows 包（无需 Godot 编辑器）

运行 `tools/build_framework_release.ps1` 构建。最新 ZIP 和解压位置记录在 `artifacts/framework-release.json`。解压后按顺序：`CheckFramework.cmd` 校验 → `StartPanel.cmd` 打开管理后台 → 玩家用 `StartShooter.cmd` / `StartTurns.cmd` → 全部关闭用 `StopFramework.cmd`；`PublishClients.cmd` 生成给玩家的公开连接配置。只分发构建时的干净 ZIP，不要分发跑过测试的解压目录。

最新包已在 2026-09-27 重建，包含测试账号删除与收尾修正、常驻存储试点和 8 字符最低密码长度。默认使用常驻模式；需要回退时，在启动前设置环境变量 `ROOMKIT_STORAGE_MODE=oneshot`。从 ZIP 全新解压后的自动包测试为 44/0，覆盖原生启动、房间和基本联机，不包含删除操作；新包的旧路径与人工试玩尚未验证。准确包名、哈希与验收范围见 [STATUS](STATUS.md#当前交付物)。

## 接入自己的游戏

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new_game.ps1 -Managed -GameId my_game
```

生成的工程自带 SDK、账号客户端、房间程序、资产目录/策略和结果 Schema；不需要修改宿主核心。步骤和自动验证见 [新游戏接入](docs/24_managed_game_template.md)，SDK 接口见 [SDK README](sdk/roomkit/README.md)。

## 测试

基础回归：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit`。各模式的成功标记，以及账号、管理、射击、托管模板等专项命令，见 [docs/22 测试入口](docs/22_framework_operations.md#测试入口)。测试日志写在 `logs/`，它和 `data/`、`run/`、`artifacts/` 一样都不进入 Git。

## 文档导航

| 需要了解 | 文档 |
|---|---|
| 当前状态、验证范围、已知问题 | [STATUS](STATUS.md) |
| 启动、数据维护、局域网、测试与人工验收夹具 | [22 本机启动与验证](docs/22_framework_operations.md) |
| 分支范围与阶段规格 | [17 框架与射击计划](docs/17_framework_shooter_plan.md) |
| 跨游戏术语与后续方向 | [CONTEXT](CONTEXT.md)、[17 后续方向（第五节）](docs/17_framework_shooter_plan.md) |
| 管理后台与 HTTP 接口 | [19 管理后台](docs/19_admin_ui.md) |
| 射击玩法与房间规则 | [20 射击示例](docs/20_shooter.md)、[25 房间规则](docs/25_shooter_room_rules.md) |
| 账号/资产/管理协议与错误码 | [21 托管协议](docs/21_managed_protocol.md)（契约唯一来源为 `schemas/`） |
| 资产基础 | [18 资产基础](docs/18_asset_foundation.md) |
| 版本与决策 | [07 版本与决策](docs/07_versions_decisions.md)、[CHANGELOG](CHANGELOG.md) |
| 架构与代码目录 | [01 范围与架构](docs/01_scope_architecture.md)；原始设计 [00](docs/00_greenfield_start.md)、[02](docs/02_contracts.md)、[03](docs/03_sdk_integration.md)、[04](docs/04_data_security.md)、[05](docs/05_deployment_operations.md)、[06](docs/06_roadmap_acceptance.md) |
| 环境记录 | [10 环境](docs/10_environment.md) |
| 协作规则 | [AGENTS.md](AGENTS.md)；首轮 M0/M1 任务原文 [CODEX_START](CODEX_START.md)（历史） |
| 历史过程、早期演示入口、设计包记录 | [归档目录](docs/archive/README.md) |

早期无账号演示入口（仓库根目录的 `StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`）和 0.1.0 候选包仍然保留，但不推荐使用，说明见 [早期入口](docs/archive/early_entrypoints.md)。注意：仓库根目录的 `StartPanel.cmd` 是早期只读面板，与独立包里同名的管理后台入口不是同一个东西。
