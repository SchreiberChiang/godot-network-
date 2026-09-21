# 03 SDK与项目接入契约

## 1. 交付形态

建议运行时代码与编辑器辅助工具放在 `addons/roomkit/`，分为 client、server、shared、editor。Godot 编辑器插件遵循 addons/plugin_name 目录，可用 GDScript 和场景制作。[S6] 编辑器插件不是运行时通信的必要条件；打包时不要让服务端依赖编辑器对象。

插件版本独立发布并锁定，禁止每个项目复制后自行修改插件核心。项目扩展通过接口、配置和自己的适配器完成。小版本升级也要运行两个示例的测试。

建议框架仓库目录：

```text
host/                 宿主及业务、进程、存储适配层
sdk/roomkit/          可分发SDK源代码
schemas/             消息与配置schema的唯一来源（版本与样例见docs/examples）
templates/           client与dedicated-server入口模板
examples/minimal/    不含美术依赖的最小例子
examples/turn_based/  第二玩法，验证无角色/无碰撞也可接入
tools/               本地启动、导出、发布、检查脚本
tests/               单元、契约、进程、端到端测试
docs/                设计、接入、部署、排障
```

## 2. 客户端公开接口草案

以下名字是待实现接口，不是 Godot 内置功能或已经存在的插件 API。

`configure(config)`；`open_session(credentials)`；`list_rooms(filters)`；`create_room(options)`；`join_room(room_id)`；`leave_room()`；`close()`。

统一用结构化 Result 返回成功或带 code 的错误，异步结果关联 request_id。对 UI 公开 session_changed、rooms_updated、join_progress、room_joined、room_left、request_failed 信号。

join_room 内部负责申请名额、取得 endpoint/票据、建立连接、认证、版本检查和超时清理。玩法场景不直接启动宿主进程，不触碰端口表或账号表。

推荐客户端 SDK 独立维护 LobbyConnection（WebSocket）与 GameConnection（ENet）。进入房间不等于退出账号会话；结束对局回大厅也不要求重新登录。

客户端连接状态应区分 CONNECTING、AUTHENTICATING、LOADING、SYNCHRONIZING、IN_ROOM。网络认证通过不代表场景和初始状态已就绪。项目通过客户端加载/初始同步钩子准备地图、已存在玩家、装备和对局状态，并回报就绪；SDK提供就绪屏障，模板在这之前不启用玩法输入。复制节点的可见性/生成时序须与场景加载配合测试，不能一收到peer_connected就假定客户端有对应节点。最终room_joined信号应只在可进入玩法时触发。

## 3. 服务器公开回调草案

每个游戏实现一个 GameAdapter，最少：

| 回调 | 时机/内容 |
|---|---|
| configure_room(context) | 配置已通过宿主校验，加载本项目地图和规则 |
| on_player_admitted(identity) | 认证通过后建立业务成员；实体生成需配合客户端场景就绪 |
| on_player_left(identity, reason) | 执行移除、托管或项目自己的离线策略 |
| on_shutdown_requested(reason) | 停止玩法、形成结果、清理资源 |

异步加载必须显式通知 ready，不能在 configure_room 开始时提前宣布可加入。游戏调用 SDK 的 `mark_ready()`、`set_joinable()`、`set_phase()`、`submit_result()`，不自行操纵宿主房间表。

游戏输入和同步仍由项目维护；SDK不要求统一的 send_input(direction) 或玩家节点基类。实时同步契约建议在项目内独立保存，说明输入校验、权威、可靠性、频率、迟到加入初始状态。

## 4. 节点路径与共享代码

建议保留稳定联网入口，例如 `/root/NetRoom`，共享RPC声明和协议文件在客户端与服务端使用同一份源码。游戏世界可挂在其下，2D/3D由项目决定。

Godot 高层RPC要求两端对应节点路径一致；RPC配置也有兼容性要求。[S7] 不要把框架入口绑到 `/root/某个射击游戏主场景`，也不要只修改一端的方法。

神秘的“RPC checksum失败”不应成为正常版本拒绝方式；先在接入阶段检查兼容标识。

## 5. 每个新项目必须提供的内容

客户端：SDK、公共连接配置、接入UI或自己的UI、兼容标识。

服务端：专用导出、游戏清单、GameAdapter、地图/玩法资源、项目游戏协议文档。

宿主：注册可信 server_artifact，配置部署路径与外部可达 endpoint。路径是管理员配置，不由客户端传入。

配置分三份：公共客户端配置；管理员游戏清单；每次启动私有 launch配置。数据库密码、控制凭据、签名/证书私钥绝不能进入客户端公共资源包。

## 6. 清单

结构示例：`examples/game_manifest.example.json`。服务器端清单应验证 game_id、build_id、control_protocol、game_protocol、兼容标识、最大人数、模式和地图allowlist。清单不能替代复杂游戏规则校验。

`server_artifact` 只引用宿主预注册产物；不得通过远程输入下载或执行任意文件。服务端启动时再校验自身编译/打包写入的build身份，避免标签与真实程序不一致。

## 7. 开箱即用的验收含义

2026-09-21当前结果API：GameAdapter在完成一局时发出result_requested(match_key, status, payload)信号，RoomRuntime调用submit_result并在发送前写持久outbox。宿主组合入口创建ResultService，传入game_id到payload Schema的映射，再赋给RoomManager.result_service。核心不引用玩法。configure_room收到的results_enabled不包含数据库路径、密钥或控制token。回合示例见examples/turn_based/adapter.gd。上文mark_ready/set_joinable/set_phase仍是设计接口，不能当作本轮新增的可调用API。

把新项目接入说明交给未参与框架开发的人，仅按文档新增配置与适配器，就能本地启动宿主、房间和两个客户端并完成一次完整流程。无需修改 host/core、SDK核心或继承射击角色。

网页实时游戏另做传输配置与认证/导出测试；仅大厅改WSS不代表整个ENet游戏已支持浏览器。Godot网页平台不提供原始TCP/UDP，支持范围与原生端不同。[S7]
# 2026-09-21 SDK 0.4.0 补充

当前已提供可复制的SDK及空工程模板：`tools/new_game.ps1 -GameId my_game`，生成路径见artifacts/template.json。`tools/run.ps1 -Mode template`真实验证独立房间与模板客户端，无需修改宿主核心。

安全连接配置在已有清单字段之外提供`url=wss://localhost:<port>`、`secure_enet=true`、`ca_certificate=<固定验证证书文件>`和`credential=<预配随机凭据>`。私钥只在宿主/服务器，客户端只收自己的凭据和公开证书。不得把凭据写进代码、命令行或日志；示例通过当前用户私有文件一次性交付。缺失/不受信任证书或错误主机名拒绝连接；过期会话关闭。详细身份提供方接口、独立包与维护限制见docs/15_release_operations.md。以下原设计/早期实施说明应结合此补充与STATUS阅读。
