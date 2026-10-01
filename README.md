# RoomKit：独立的本地房间框架

从零开发的多游戏房间框架：一个独立管理后台，加上邀请码账号和永久资产，每个房间是一个独立的 Godot 进程。当前示例有横版射击和取石子。当前主线 `main`（已整合原 `codex/shooter-framework` 成果）；实际通过、失败和未验收的项目只看 [STATUS](STATUS.md)。Windows 本机功能已有验收；Linux 同机完整对局、备份等待和 60 分钟耐久通过功能门槛，原始环境对照失败保留，退出补修另经复验。Windows → Linux 基础跨设备自动验收也已通过；跨机完整一局/耐久、真人画面、公网和 Linux 导出服务器包仍未验收。

**想先了解项目有什么、做到哪一步：双击根目录 `ROADMAP.html`**（项目地图，不需要启动后台或联网），可以按模块或开发顺序查看、搜索、筛选并展开详情。

## 环境

- Windows 10/11，自带 Windows PowerShell 5.1 和系统 `winsqlite3.dll`；不需要 Node、数据库服务或其它后端。
- 从源码运行需要 Godot **4.7.2**。默认路径：

  ```text
  D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe
  ```

  脚本可以用 `-Godot '完整路径'` 指定其它可执行文件，但换版本后要重新验收。

## 从源码启动（推荐）

已生成的独立射击客户端可直接双击根目录 **`StartPlayerClient.cmd`**；首次生成或更新仍用 `PreparePlayerClient.cmd`。入口只启动游戏，不重建客户端、不重启服务器；发给朋友仍复制完整玩家目录。

1. 双击 **`StartManagement.cmd`**，浏览器会打开 <http://127.0.0.1:28291/>。首次运行时设置管理员账号；管理员只能管理后台，不能作为玩家入房。
2. 在网页点“启动服务器”，然后在邀请码页创建邀请码。
3. 双击 **`StartShooterClient.cmd`**，用邀请码注册玩家账号并登录。再开第二个客户端，用另一个账号登录（同一账号不能同时在线）。在大厅或后台创建射击房间，两人加入后开始自由混战：左右移动/跳跃，鼠标瞄准射击；死亡后可打开背包选枪，再手动复活。客户端右上角可以静音、调节音效音量（`M` 键切换静音），设置会保存在本机。

   给朋友的独立客户端（无需安装 Godot）：服务器运行时双击 **`PreparePlayerClient.cmd`**，把生成的 `PlayerClient` 整个目录发给朋友，朋友双击 `StartGame.cmd`。给局域网朋友用之前，先在后台把对外 IP 设为本机局域网地址。GitHub 获取方式见 [docs/17](docs/17_framework_shooter_plan.md#独立射击客户端实施2026-09-28)（未发布）。
4. 取石子客户端用 **`StartManagedTurns.cmd`**，与射击共用同一套账号和资产服务。
5. 结束：网页上的“停止服务器”只停游戏宿主，后台保持运行；**`StopManagement.cmd`** 关闭整个管理服务。

私有数据在 `data/framework/`（账号库、资产库、配置、私钥），不会进入 Git 或玩家分发包。源码更新后按这个顺序重启：先退出旧客户端，然后 `StopManagement.cmd` → `StartManagement.cmd` → 在网页启动服务器并建房 → 重新打开客户端。账号和资产会保留。

管理后台的“玩家 → 详情 → 停用账号”会撤销玩家登录并保留账号与所有游戏资产；需要时用“恢复账号”。停用默认无限期，**不是删除数据**。用户已反馈新版后台登录、退出重登和建房正常；具体范围见 STATUS。

测试阶段要永久删除某个玩家时，用同一页面单独的“删除测试账号”：它清除该玩家在当前账号库和资产库中的账号与全部游戏资产，不可恢复；旧备份不改写，后台会列出并标注可能仍含该账号的备份。源码版已通过隔离测试，用户从项目目录启动并试玩后反馈删除正常。新独立 ZIP 已包含此功能，但自动包测试没有单独执行删除流程。说明见 [规划第七节](docs/17_framework_shooter_plan.md#七测试阶段账号删除2026-09-27已实现)。

新注册、改密及管理员重置的密码长度为 8–128 字符；已有密码继续有效。源码和最新独立 ZIP 均已包含。

房间规则设置、背包与复活、局域网配置、备份恢复、客户端窗口排查和命令行等价入口，见 [本机启动与验证](docs/22_framework_operations.md)。

## Linux 源码启动

需要 Godot 4.7.2 官方 Linux 版、pwsh 7.6 和系统的 `libsqlite3.so.0`；引擎和 pwsh 的位置默认在 `~/roomkit/tools`，也可以用 `ROOMKIT_GODOT`、`ROOMKIT_PWSH` 指定。在项目目录下：

```bash
bash tools/roomkit_linux.sh start     # 打印面板地址，默认 http://127.0.0.1:28491/
bash tools/roomkit_linux.sh status
bash tools/roomkit_linux.sh stop      # 只请求退出并等待，不发信号
```

每个实例的数据、游戏索引、公开配置和 HOME/XDG/tmp 都在 `data/instance-<名>/`（默认 `l3`），默认只绑定 127.0.0.1；端口可以用 `--panel-port`、`--lobby-port`、`--control-port`、`--udp-range`、`--bind` 指定，但只在实例第一次创建时生效。已在一台 x86_64 笔记本上完成同机验收，以及 Windows 客户端直连 Linux 的局域网自动验收；公网和 Linux 导出服务器包尚未验收。

本机专用的 Linux 联机客户端：双击 **`OpenLinuxPlayerClient.cmd`** 打开独立目录，再双击其中的 `Client.exe`。它连接笔记本测试实例，保留原 `PlayerClient`；生成的程序和连接配置不进入 Git。邀请码、启停和复验说明见 [Linux 跨机试玩](docs/17_framework_shooter_plan.md#linux-lan)。

**从台式机打开 Linux 后台：双击根目录 `OpenLinuxManagement.cmd`，保持窗口打开。** 入口建立 SSH 转发，再在浏览器打开 <http://127.0.0.1:28491/>；按回车或关闭入口窗口只断开这次转发，不停 Linux 服务。后台只监听笔记本自己的回环地址，不能直接打开 `http://192.168.10.105:28491/`。网址填在浏览器地址栏，不是 SSH 终端命令；测试管理员与 Windows 管理员不同，信息在本机私有 `data/codex-linux-lan-20261001224135-8dd5ca/admin.json`。入口不启动远程服务，SSH 认证不可用时明确报错，不修改 SSH 配置。说明见 [后台访问与下一阶段](docs/17_framework_shooter_plan.md#linux-management-entry)。

## 独立 Windows 包（无需 Godot 编辑器）

运行 `tools/build_framework_release.ps1` 构建。最新 ZIP 和解压位置记录在 `artifacts/framework-release.json`。解压后按顺序：`CheckFramework.cmd` 校验 → `StartPanel.cmd` 打开管理后台 → 玩家用 `StartShooter.cmd` / `StartTurns.cmd` → 全部关闭用 `StopFramework.cmd`；`PublishClients.cmd` 生成给玩家的公开连接配置。只分发构建时的干净 ZIP，不要分发跑过测试的解压目录。

包默认使用常驻存储；需要回退时，在启动前设置环境变量 `ROOMKIT_STORAGE_MODE=oneshot`。最新包的名称、哈希、包含的功能和验收范围只看 [STATUS 当前交付物](STATUS.md#当前交付物)。

## 接入自己的游戏

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new_game.ps1 -Managed -GameId my_game
```

生成的工程自带 SDK、账号客户端、房间程序、资产目录/策略和结果 Schema；不需要修改宿主核心。步骤和自动验证见 [新游戏接入](docs/24_managed_game_template.md)，SDK 接口见 [SDK README](sdk/roomkit/README.md)。

## 测试

基础回归：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit`。各模式的成功标记，以及账号、管理、射击、托管模板等专项命令，见 [docs/22 测试入口](docs/22_framework_operations.md#测试入口)。测试日志写在 `logs/`，它和 `data/`、`run/`、`artifacts/` 一样都不进入 Git。

## 文档导航

目前已完成项目地图、主线整理、独立客户端、后台 UI 和基础音效，Linux 同机阶段验收已交付并待复核，见 [阶段交付](docs/17_framework_shooter_plan.md#l3-stage-delivery)；分工见 [协作总览](docs/17_framework_shooter_plan.md#coordination-current)。见 [已确认规划](docs/17_framework_shooter_plan.md#next-plan)、[清理候选表](docs/17_framework_shooter_plan.md#清理候选表) 和 [下一阶段建议](docs/17_framework_shooter_plan.md#下一阶段实施建议与验收门槛)。

| 需要了解 | 文档 |
|---|---|
| 模块、状态与开发顺序一览 | `ROADMAP.html`（双击打开） |
| 项目分析：模块耦合、Windows 依赖、跨平台边界、性能待测项 | [01 项目分析](docs/01_scope_architecture.md#项目分析2026-09-28) |
| 当前状态、验证范围、已知问题 | [STATUS](STATUS.md) |
| 启动、数据维护、局域网、测试与人工验收夹具 | [22 本机启动与验证](docs/22_framework_operations.md) |
| 分支范围与阶段规格 | [17 框架与射击计划](docs/17_framework_shooter_plan.md) |
| 跨游戏术语与后续方向 | [CONTEXT](CONTEXT.md)、[17 后续方向（第五节）](docs/17_framework_shooter_plan.md) |
| 管理后台与 HTTP 接口 | [19 管理后台](docs/19_admin_ui.md) |
| 后台改版界面预览（演示数据，不连接服务；正式后台已接入该布局） | `ADMIN_PREVIEW.html`（双击打开） |
| 射击玩法与房间规则 | [20 射击示例](docs/20_shooter.md)、[25 房间规则](docs/25_shooter_room_rules.md) |
| 账号/资产/管理协议与错误码 | [21 托管协议](docs/21_managed_protocol.md)（契约唯一来源为 `schemas/`） |
| 资产基础 | [18 资产基础](docs/18_asset_foundation.md) |
| 版本与决策 | [07 版本与决策](docs/07_versions_decisions.md)、[CHANGELOG](CHANGELOG.md) |
| 架构与代码目录 | [01 范围与架构](docs/01_scope_architecture.md)；原始设计 [00](docs/00_greenfield_start.md)、[02](docs/02_contracts.md)、[03](docs/03_sdk_integration.md)、[04](docs/04_data_security.md)、[05](docs/05_deployment_operations.md)、[06](docs/06_roadmap_acceptance.md) |
| 环境记录 | [10 环境](docs/10_environment.md) |
| 协作规则 | [AGENTS.md](AGENTS.md)；首轮 M0/M1 任务原文 [CODEX_START](CODEX_START.md)（历史） |
| 历史过程、早期演示入口、设计包记录 | [归档目录](docs/archive/README.md) |

早期无账号演示入口（仓库根目录的 `StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`）和 0.1.0 候选包仍然保留，但不推荐使用，说明见 [早期入口](docs/archive/early_entrypoints.md)。注意：仓库根目录的 `StartPanel.cmd` 是早期只读面板，与独立包里同名的管理后台入口不是同一个东西。
