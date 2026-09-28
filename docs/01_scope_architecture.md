# 01 范围与架构

## 当前分支指引（2026-09-28 更新）

`codex/shooter-framework` 的现行规格与开发顺序见 [17_framework_shooter_plan.md](17_framework_shooter_plan.md#next-plan)，实际完成和未验收项见 [STATUS](../STATUS.md)，启动步骤见 [22_framework_operations.md](22_framework_operations.md)，模块与状态一览见根目录 `ROADMAP.html`。当前已实现独立 Operator、托管宿主、账号、永久资产与结果奖励服务，以及射击和取石子示例；所有验证都在同一台 Windows 电脑上完成，不据此宣称跨设备、Linux 或正式发布通过。

分层继续是“通用框架 → 可选类型模块 → 具体游戏/模式”。玩法按相反方向依赖框架；类型模块只有真实复用需要时才提取，不能成为所有游戏的必需依赖。永久资产与比赛临时经济分离，死亡、武器、回合与赛车规则仍由游戏决定。当前 SDK 源码位于 `sdk/roomkit/`，接入接口与 SDK 0.5 边界见 [SDK README](../sdk/roomkit/README.md) 和 [21_managed_protocol.md](21_managed_protocol.md)。

### 当前代码目录（2026-09-28 核对）

| 目录/文件 | 用途 |
|---|---|
| `host/operator.gd`、`host/admin_http.gd`、`host/admin.html` | 独立管理服务、回环 HTTP 后台与页面 |
| `host/managed_host.gd`、`host/managed_lobby.gd` | 托管游戏宿主与 WSS 账号大厅 |
| `host/core/` | GameRegistry、托管游戏注册表、RoomManager、PortAllocator、准入、账号/资产/结果/删除服务、恢复保护；不引用具体游戏 |
| `host/platform/`、`host/storage/`，`tools/process_identity.ps1`、`sqlite_store.ps1`、`account_store.ps1`、`storage_worker.ps1` | Windows 进程启动与身份核验、有界 PowerShell 助手、SQLite 适配与常驻存储 |
| `host/lobby_server.gd`、`host/development.gd` | 早期写成，但**仍被当前代码使用**：`managed_lobby.gd` 继承 `lobby_server.gd`，`managed_host.gd` 调用 `development.gd` 注册构建 |
| `host/main.*`、`host/dashboard*` | 早期开发宿主与只读状态面板（根 `StartPanel.cmd` 与基础回归使用） |
| `sdk/roomkit/` | 源码 SDK：`client/`（RoomClient、AccountClient）、`server/`（RoomRuntime、GameAdapter、资产策略、MatchWallet、结果 outbox）、`shared/`（协议、严格 JSON、Schema 校验、TCP 分帧、安全传输） |
| `schemas/` | 唯一契约来源；修改协议时同步 `examples/`、错误码与测试 |
| `examples/framework/`、`examples/shooter/`、`examples/turn_based/` | 当前账号客户端外壳、横版射击、取石子（当前第二玩法） |
| `examples/minimal/`、`examples/blocks/`、`examples/showcase/` | 无玩法房间、早期方块示例与演示宿主；`minimal` 的清单被 `new_game.ps1` 和开发宿主读取，其余被基础回归和 0.1.0 包引用 |
| `templates/managed_game/`、`templates/game/`，`tools/new_game.ps1` | 托管新游戏模板与早期开发身份模板及生成器 |
| `tools/run_framework.ps1`、`build_framework*.ps1` 与根目录 `Start*/Stop*.cmd` | 当前启动与构建入口 |
| `tests/`、`tools/run.ps1` | 单元/模拟与真实进程测试 |
| `release/`、`tools/build_release.ps1`、`package_release.ps1` | 早期 0.1.0 候选包 |

## 项目分析（2026-09-28）

第一阶段只读核对 `b0a707d` 的源码、构建脚本、测试与证据。下文“推测”表示没有实测、只根据代码判断；这些判断不作为重构依据。

### 按模块

| 模块 | 现在是什么 | 关键文件 | 真实耦合与观察 | 状态 |
|---|---|---|---|---|
| 账号 | 邀请码注册、登录、单会话、管理员重置/停用/踢出、测试账号删除 | `tools/account_store.ps1`、`host/core/account_service.gd`、`host/core/account_deletion.gd` | 业务规则、SQL 与 PBKDF2 全在 PowerShell 脚本里；GDScript 侧只做 Schema 校验和分发。会话校验走常驻进程，其余走一次性助手 | 本机自动测试通过；删除的包内端到端未测 |
| 房间与进程 | Operator 启停托管宿主；宿主为每房启动一个 Godot 进程，分配 UDP 端口，回环 TCP 控制 | `host/operator.gd`、`host/managed_host.gd`、`host/core/room_manager.gd`、`host/platform/process_launcher.gd` | 进程身份核验与句柄回收依赖 `process_identity.ps1`（CIM）和经验证的 Godot 4.7.2 Windows 行为；`room_manager.gd`、`account_service.gd` 在非 Windows 上直接拒绝启动 | 本机通过；第二台设备与 Linux 未验证 |
| 资产与结算 | 永久钱包、所有权、默认配置、资产空间；签名结果与奖励同事务 | `host/core/asset_service.gd`、`host/core/result_service.gd`、`tools/sqlite_store.ps1` | 幂等与版本检查在 SQLite 事务里；结果授权每房一条、从不删除，累计上限 256 | 本机通过；授权回收与迟到结算窗口是规划 |
| 存储 | 两个 SQLite 文件（`accounts.sqlite`、`assets.sqlite`），经 PowerShell 用 P/Invoke 调系统 `winsqlite3.dll` | `host/storage/sqlite_repository.gd`、`host/storage/resident_store.gd`、`tools/bounded_helper.ps1`、`tools/storage_worker.ps1` | 数据库文件本身是标准 SQLite，可跨平台；访问层完全绑定 Windows PowerShell 5.1 与 .NET | 本机通过 |
| 运维 | 备份/恢复、指标、私有目录 ACL、后台页面、停服与崩溃重启 | `tools/operator_maintenance.ps1`、`tools/protect_data.ps1`、`tools/protect_runtime.ps1`、`host/admin.html` | 备份用 SQLite 在线备份 API（同一 C# 绑定）；私有目录保护用 Windows ACL 并拒绝 reparse point | 本机通过；新表单未做真实浏览器点击 |
| SDK / 游戏接入 | SDK 0.5 与 `new_game.ps1 -Managed` 模板；受信注册表组装服务 | `sdk/roomkit/`、`templates/managed_game/`、`host/core/managed_game_registry.gd`、`tools/build_framework.ps1` | 宿主核心和 SDK 不含具体游戏分支；新游戏需要进入 `artifacts/framework-games.json` 注册表（由构建脚本生成）才能被 Operator 使用 | 模板 74/0；图形界面未人工验收 |
| 具体游戏 | 横版射击、取石子 | `examples/shooter/`、`examples/turn_based/`、`examples/framework/` | 射击为服务器权威、每秒 20 次完整状态、无预测/回溯；取石子证明框架不依赖射击 | 本机通过，用户试玩反馈正常 |

### 真实 Windows 依赖

- `powershell.exe`（Windows PowerShell 5.1）：所有存储、账号、备份、进程身份与目录保护脚本；Godot 侧调用点在 `host/platform/bounded_helper.gd`、`host/storage/resident_store.gd`、`host/core/account_service.gd`、`host/storage/sqlite_repository.gd`、`host/core/room_manager.gd`、`host/core/recovery_guard.gd`、`host/operator.gd`、`host/platform/process_launcher.gd`。
- 系统 `winsqlite3.dll` 与 C# `Add-Type` 绑定（`tools/sqlite_store.ps1` 内定义，账号脚本与维护脚本复用）。
- .NET `Rfc2898DeriveBytes` 做 PBKDF2-SHA256（账号密码）。
- CIM `Win32_Process` 查询进程身份（`tools/process_identity.ps1`）；句柄回收门槛绑定 Godot 4.7.2 Windows 版本哈希。
- Windows ACL 与 reparse point 检查（`tools/protect_data.ps1`、`protect_runtime.ps1`、`operator_maintenance.ps1`）。
- 启动入口是 `.cmd`；导出使用 Windows 模板；PowerShell 脚本须保持纯 ASCII（5.1 读无 BOM 文件用系统代码页）。

### 跨平台需要替换的边界

1. **存储访问层**：替换 `sqlite_repository.gd` / `account_service.gd` 背后的助手，保留 SQL 语义、事务、幂等、`schemas/` 契约和现有数据库文件格式。候选方向（未选型）：Godot 原生 SQLite 扩展（需下载第三方库，之前暂缓）或其他实现。
2. **密码派生**：已有 GDScript PBKDF2 探针与 .NET 结果逐字节一致（约 1.7 秒，`tests/perf/run_gd_pbkdf2_probe.gd`），说明现有密码哈希可以在不改格式的情况下迁移（推测仍需在 Linux 上实测耗时）。
3. **进程身份与回收**：`process_launcher.gd` + `process_identity.ps1` 需要 Linux 对应实现（例如基于 `/proc` 的 PID、启动时间与可执行路径核对，推测）。
4. **私有目录保护与备份维护**：ACL/reparse 检查和备份恢复脚本需要 Linux 版本。
5. **启动与安装脚本**：`.cmd` 与 PowerShell 构建脚本需要对应的 Linux 脚本；Windows 一键运行保留。
6. 其余部分（Godot 宿主、SDK、游戏、WSS/DTLS/ENet、Schema 校验）是 GDScript，理论上可移植（推测；09-21 在 WSL 上跑过 215 项协议/准入/玩法可移植检查，但**不是** Linux 宿主验证）。

### 性能待测项

- 仍走一次性助手的操作每次约 1.0–1.2 秒：注册、登录（另有约 1.9 秒 PBKDF2）、登出、结算、grant、邀请码和后台写操作。
- 常驻存储进程数小时以上的耐久与内存。
- 8 人以上房间的每秒 20 次完整状态带宽和 CPU（推测随人数线性增长，未测）。
- 删除账号时 Operator 在主线程改写审计文件（文件上限约 2 MB 加轮换副本），大文件下的停顿未测。
- 16 人满房只持续过 17.5 秒；托管宿主长期运行未测。

### 接入障碍（新游戏）

- 需要按模板提供清单、GameAdapter、资产目录/策略、结果 Schema 和奖励计算器，并由构建脚本写入 `artifacts/framework-games.json`；目前没有“只放入游戏目录就被发现”的机制。
- 客户端交付目前只有整包 ZIP；独立客户端目录与 GitHub 获取方式是第二阶段任务（`Client.exe` 约 104 MiB，超过 GitHub 普通文件上限）。

## 初始设计与历史阶段记录

以下保留早期设计及当时的实现说明；其中建议名称、交付目录或阶段状态不代表当前分支的完成状态。约束继续适用，实际入口和协议以以上当前指引及 `schemas/` 为准。

## 1. 核心边界

2026-09-21新增分支决策见[17](17_framework_shooter_plan.md)：通用核心管理身份、资产事务、配置、房间与运维；可选类型模块提供同类玩法能力；具体游戏决定允许操作的条件和胜负。永久资产与比赛临时资产使用不同服务和生命周期，不能仅用界面区分同一个余额。射击的死亡状态、武器属性或赛车的维修区均不得成为通用核心字段。

通用的是身份、房间分配、接入资格、生命周期、版本校验、结果接收与运维。不是所有玩法的移动、碰撞、伤害、AI和同步算法。

建议三个可交付物：独立宿主 RoomHost；可复用 Godot SDK `addons/roomkit`；含客户端入口和专用服务器入口的项目模板。名称暂定。

Godot 支持 Headless 与专用服务器导出，服务端导出可剥离部分视觉资源。[S1] 视觉逻辑、UI、摄像机和与判定无关的特效，仍应由项目入口主动排除。

## 2. 逻辑结构

```text
客户端 ── 大厅 JSON/WSS ── RoomHost
   │                         ├─ 身份与会话
   │                         ├─ 游戏/构建注册表
   │                         ├─ 房间与名额管理
   │                         ├─ 进程/端口管理
   │                         └─ 持久化与结果接收
   │                                │ 本机 TCP
   └──── Godot ENet ────── 游戏房间进程
                                  ├─ Room SDK
                                  └─ 项目自己的玩法与同步
```

这些宿主模块第一版可以在同一个程序中运行。数据库只由宿主业务层访问，房间不直接打开共享账号数据库。

建议代码依赖方向：项目玩法 → SDK 公共接口 → 框架核心抽象。框架核心不得反向引用项目路径、角色脚本或具体武器数据。基础核心可以使用 Godot Node、信号和数据类，不必为了未来换语言而实现一套自己的引擎。

## 3. 三条网络通道

| 通道 | 建议 | 约束 |
|---|---|---|
| 客户端—大厅 | 标准 WebSocket JSON；公网 WSS | 只传登录、房间、入房授权和状态，不转发每帧输入 |
| 宿主—房间 | 本机 TCP，长度前缀 JSON | 仅回环接口，按房间凭据认证，不接受客户端接入 |
| 客户端—房间 | ENet + Godot MultiplayerAPI | 只属于对应游戏；安全与兼容性独立测试 |

Godot WebSocketPeer 能处理标准 WebSocket 文本消息，也能接受 TCP/TLS 流作为服务器端连接；因此采用标准 JSON 不要求立即换掉 Godot 宿主。[S2] 不用 WebSocketMultiplayerPeer 包装大厅 RPC，以免再次绑定高层场景协议。

Godot 的高层多人协议是内部实现，并不面向非 Godot 服务器。[S3] 因而“以后替换大厅语言”与“换掉战斗服务器”是两项不同工作；本方案只承诺前者可通过保持控制契约完成。

## 4. 稳定身份

`user_id`：业务身份，不能用临时 ENet peer_id 代替。

`game_id`：项目命名空间；`build_id`：不可变构建；`room_id`：逻辑房间；`launch_id`：某次进程启动；`match_id`：一局/一次结算。

同一房间以后可以运行多局，但 v0.1 可先实现一局结束后回收。不要把 match_id 与进程 PID 或端口等同。

## 5. 复用模块层次

核心：房间、身份、连接、进程、版本、结果。

可选玩法包：射击输入、命中回溯、2D移动、3D移动、回合流程等。只有第二个真实项目需要相同代码时才抽取。

具体项目：地图、武器、角色、UI、AI、胜负和奖励算法。核心不内置 `guns`，也不要求每个玩家有 CharacterBody2D。
