# RoomKit：独立的本地房间框架

更新：2026-09-21。现在有两个可以打开窗口操作的最小游戏：方块移动和回合取石子。回合结果可保存到本地SQLite，关闭重开后仍能查看；未确认结果可在宿主重启后补存。每间房运行在独立Godot进程中，工程从零编写，不依赖以前的游戏或服务器。

**直接试玩：双击 `StartPlay.cmd`，打开两个方块游戏窗口。** 点击其中一个窗口，用 WASD 或方向键移动；切到另一窗口操作另一个玩家。橙色方块是当前玩家。点“退出房间”可以回大厅，再点“重新入房”加入。关闭两个窗口后自动回收本次房间。

**第二个游戏：双击 `StartTurns.cmd`。** 每回合取1或2颗石子，拿走最后一颗得1分并开始下一局。轮流在两个窗口点击按钮。两个启动器建议依次运行，便于分清窗口。每次会话最长30分钟。

`StartDemo.cmd` 仍保留原来的纯文字自动入房/退房测试。所有入口都需要本机已安装下述 Godot；目前仅支持本机回环，不能直接给另一台电脑或公网玩家连接。

**查看战绩：先运行 `StartTurns.cmd`，轮流取完一局石子，再关闭两个窗口，双击 `ShowResults.cmd`。** 会显示保存的局数与每局玩家分数；这些是本地开发身份的结果记录，重新进入后的实时分数仍按示例原规则计算，不是账号累计积分。数据库位于 `data/showcase-results/results.sqlite`，不会上传GitHub。完整路线见[docs/06_roadmap_acceptance.md](docs/06_roadmap_acceptance.md)，当前M4仅完成结果存储部分。

**实际通过、失败和未运行项见 [STATUS.md](STATUS.md)。** 本文描述当前代码和启动入口，不代替验收记录。原文档包的 v0.2 是设计包编号；当前工程尚不代表正式框架发布版。

## 本机启动与验证

当前记录的环境是 Windows 10.0.26200.0、Godot `4.7.2.stable.steam.ed1daf0bf`、Git `2.55.0.windows.3`。Godot 路径：

```text
D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe
```

在正常 PowerShell 中执行，无需额外后端或下载玩法资源：

```powershell
Set-Location 'F:\文档\GodotGame\Net\RoomKit'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode integration
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode demo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode players
```

| 模式 | 执行内容 | 成功时应出现的标记 |
|---|---|---|
| `unit` | 注册与端口检查、协议/分帧测试、模拟进程生命周期 | `UNIT_RESULT passed=... failed=0` |
| `launcher` | 10 轮真实进程身份核验和 Windows 句柄回收 | `REAL_LAUNCHER_RESULT passed=... failed=0` |
| `integration` | 真实 Godot 子进程、TCP 控制、ENet 端口、故障与连续开关房测试 | `INTEGRATION_RESULT passed=... failed=0` |
| `demo` | 自动创建一房，收到至少四次心跳后停止并退出 | `DEMO_PASS` |
| `players` | 真实 WebSocket 大厅、两名独立 ENet 测试玩家进入/退房、非法票据/满员拒绝与资源回收 | `PLAYERS_RESULT passed=33 failed=0` |
| `games` | 两个独立游戏、四名真实客户端、玩法/退房重入与实际回合结果落库 | `GAMES_RESULT passed=47 failed=0` |
| `persistence` | 真实SQLite、丢ACK重试、宿主终止/房间自退、离线补存、备份与中文读写 | `PERSISTENCE_RESULT passed=... failed=0` |

每种模式还必须出现 `ROOMKIT_EXIT mode=<模式> code=0`。脚本检查真实退出码、脚本错误和成功标记，并设置整体超时。`-Mode all` 按 unit → launcher → integration → demo → players → games → persistence 运行。`-Mode games -Visual` 会打开真实图形窗口并额外保存4张截图。`-Godot '完整路径'` 可指定可执行文件，但更换引擎版本需要重新验收。所有入口让子进程使用当前启动宿主的Godot。

结果专项和本地管理命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode persistence
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\results.ps1 -Operation inspect
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\results.ps1 -Operation recover
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\results.ps1 -Operation backup
```

先关闭演示窗口再手动恢复或备份；重新启动试玩也会自动补存已落盘的待确认结果。`-Store 'res://data/某测试目录'`可指定本项目的其它结果库。备份会打印新文件路径，不覆盖现有数据库。详细语义、限制与测试边界见[docs/13_m4_results.md](docs/13_m4_results.md)。

日志位于 `logs/`：每种模式的 `*-console.log`、`*-stderr.log`、`*-godot.log`，集成测试另写 `integration-result.json`。分帧部分写入由可控写入器模拟；它不等于证明操作系统此次真实发生部分写入。进程集成测试运行开发工程，不等于专用服务器导出验证。

## 配置与核心边界

[config/development.json](config/development.json) 的默认 UDP 范围为 `28100–28131`，控制 TCP 端口 `0` 表示由系统分配空闲端口；启动、心跳失联和停止宽限分别为 `15000 / 5000 / 3000` 毫秒。集成测试会使用专门的测试超时。所有网络监听只绑定 `127.0.0.1`。

游戏清单位于 [examples/minimal/game_manifest.json](examples/minimal/game_manifest.json)。清单引用产物标签，由宿主本地配置映射成可信程序和参数数组；创建请求只能提供已登记的游戏、模式、地图与容量，不能指定可执行路径。

| 目录/文件 | 当前用途 |
|---|---|
| `project.godot`、`host/main.*` | 开发宿主和自动结束的 demo 入口 |
| `host/core/` | GameRegistry、RoomManager、PortAllocator；不引用具体游戏路径或场景 |
| `host/platform/`、`tools/process_identity.ps1` | Windows 进程启动、身份核验与确认退出 |
| `host/development.gd` | 将最小房间和本地可信产物注册到宿主 |
| `sdk/roomkit/shared/` | 控制协议、Schema 校验、严格 JSON 和 TCP 分帧 |
| `host/lobby_server.gd`、`host/core/admission_store.gd` | 标准 WebSocket 大厅、开发身份、席位和一次性票据 |
| `sdk/roomkit/client/`、`sdk/roomkit/server/` | 客户端 SDK、房间运行时、GameAdapter 回调 |
| `schemas/` | 唯一契约来源；修改协议时同步例子、错误说明和测试 |
| `examples/minimal/` | 无玩法的房间程序与清单 |
| `examples/blocks/`、`examples/turn_based/` | 两个独立玩法各自的房间入口、适配器、游戏逻辑、清单 |
| `examples/showcase/` | 演示宿主、共享客户端外壳和中文窗口 |
| `tools/build_games.ps1`、`tools/play.ps1` | 独立工程打包与可操作窗口启动 |
| `tests/`、`tools/run.ps1` | 单元/模拟与真实进程验证入口 |
| `templates/` | 尚未实现可分发项目模板 |

私有启动配置放在仅当前用户可访问的 `run/`，注册成功后删除；控制凭据不放进命令行或公开快照。`run/` 和 `logs/` 不进入 Git。失败或停止通知都不能直接释放端口：必须确认对应子进程退出，且 UDP 端口可重新绑定。身份无法核验或端口仍占用时保持隔离。

## 当前范围与后续阶段

M0/M1 房间生命周期与 M2 本地双端接入闭环已经实现。M2 使用标准 WebSocket JSON 大厅、开发会话身份、一次性入房票据和 ENet 认证；场景准备和初始名单确认完成后才成为正式成员。会话身份仅在当前连接内有效，不是账号系统。两人测试是 Windows 同机回环真实联机，不代表两台电脑或公网已经通过。

游戏通过配置与 GameAdapter 接入，核心不依赖具体角色、枪械或地图。M3 的方块和第二玩法已实现，本轮未修改 host/core 或 SDK 核心。独立产物是带 SDK 的 Godot 开发工程，尚非服务器可执行文件导出。可分发插件、项目模板及正式发布包仍待实施。账号、商城、持久化和公网发布未实现；Linux、导出产物、16 人和100轮压力未验证。

新增接入方法见 [SDK 使用说明](sdk/roomkit/README.md)，契约和边界见 [M2 实施说明](docs/11_m2_implementation.md)。`logs/players-result.json` 保存两名玩家的阶段、名单和返回大厅结果；具体子进程日志目录在其 `evidence_dir` 字段。

两个可操作游戏的规则、构建、协议与测试范围见 [M3 使用说明](docs/12_m3_games.md)。`logs/games-result.json` 保存最新双玩法测试结果；截图与各客户端日志目录在 `evidence_dir`。独立工程生成在 `artifacts/games-<编号>/`，只使用当前仓库源码。

阅读入口：[本轮任务](docs/00_greenfield_start.md)、[架构](docs/01_scope_architecture.md)、[控制协议实施说明](docs/09_m1_control.md)、[环境与权限](docs/10_environment.md)、[阶段验收](docs/06_roadmap_acceptance.md)。`VALIDATION.md` 仅记录原设计包检查，运行时结果以 `STATUS.md` 为准。
