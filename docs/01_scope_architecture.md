# 01 范围与架构

## 当前分支指引（2026-09-22）

`codex/shooter-framework` 的现行规格见 [17_framework_shooter_plan.md](17_framework_shooter_plan.md)，实际完成和未验收项见 [STATUS](../STATUS.md)，启动步骤见 [22_framework_operations.md](22_framework_operations.md)。当前已实现独立 Operator、托管宿主、账号、永久资产与结果奖励服务，以及射击和取石子示例；具体测试范围分别记录，不据此宣称跨设备或完整正式发布通过。

分层继续是“通用框架 → 可选类型模块 → 具体游戏/模式”。玩法按相反方向依赖框架；类型模块只有真实复用需要时才提取，不能成为所有游戏的必需依赖。永久资产与比赛临时经济分离，死亡、武器、回合与赛车规则仍由游戏决定。当前 SDK 源码位于 `sdk/roomkit/`，接入接口与 SDK 0.5 边界见 [SDK README](../sdk/roomkit/README.md) 和 [21_managed_protocol.md](21_managed_protocol.md)。

### 当前代码目录（2026-09-27 核对）

| 目录/文件 | 用途 |
|---|---|
| `host/operator.gd`、`host/admin_http.gd`、`host/admin.html` | 独立管理服务、回环 HTTP 后台与页面 |
| `host/managed_host.gd`、`host/managed_lobby.gd` | 托管游戏宿主与 WSS 账号大厅 |
| `host/core/` | GameRegistry、托管游戏注册表、RoomManager、PortAllocator、准入、账号/资产/结果服务、恢复保护；不引用具体游戏 |
| `host/platform/`、`host/storage/`，`tools/process_identity.ps1`、`sqlite_store.ps1`、`account_store.ps1` | Windows 进程启动与身份核验、有界 PowerShell 助手、SQLite 适配 |
| `host/main.*`、`host/development.gd`、`host/lobby_server.gd`、`host/dashboard*` | 早期开发宿主、无账号大厅和只读状态面板 |
| `sdk/roomkit/` | 源码 SDK：`client/`（RoomClient、AccountClient）、`server/`（RoomRuntime、GameAdapter、资产策略、MatchWallet、结果 outbox）、`shared/`（协议、严格 JSON、Schema 校验、TCP 分帧、安全传输） |
| `schemas/` | 唯一契约来源；修改协议时同步 `examples/`、错误码与测试 |
| `examples/framework/`、`examples/shooter/`、`examples/turn_based/` | 当前账号客户端外壳、横版射击、取石子 |
| `examples/minimal/`、`examples/blocks/`、`examples/showcase/` | 无玩法房间、早期方块示例与演示宿主 |
| `templates/managed_game/`、`templates/game/`，`tools/new_game.ps1` | 托管新游戏模板与早期开发身份模板及生成器 |
| `tools/run_framework.ps1`、`build_framework*.ps1` 与根目录 `Start*/Stop*.cmd` | 当前启动与构建入口 |
| `tests/`、`tools/run.ps1` | 单元/模拟与真实进程测试 |
| `release/` | 早期 0.1.0 候选包的包内脚本与说明 |

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
