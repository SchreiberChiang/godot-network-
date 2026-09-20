# M2：两个本地测试玩家进入同一房间

2026-09-20，用户在 M0/M1 验收后要求继续。本轮按 docs/06 推进 M2 的本地接入闭环；AGENTS/CODEX_START 中“本轮 M0/M1”指首次任务。本轮仍不接旧项目、不部署公网，不做账号商城或游戏美术。

实现顺序：契约与席位/票据 → 标准 WebSocket JSON 大厅 → 房间/客户端 SDK 与认证、加载屏障 → 两个真实客户端进程 → 本地演示与验收。执行结果统一记录 STATUS，不预先宣称通过。

开发身份为每条本地 WebSocket 连接生成的随机 user_id；名称不代表账号所有权。连接断开注销会话并取消未入房预留；正式房间成员由 ENet 断开/房间控制失联释放。席位状态 RESERVED→ADMITTING→CONNECTED；票据仅保存摘要，一次连接尝试可重试核销，新 attempt_id 不可重放。

大厅只监听 127.0.0.1，使用 WebSocketPeer 的标准文本 JSON；房间使用 ENet 和 SceneMultiplayer.auth_callback。认证完成前没有玩家实体/RPC；认证完成后还须加载并确认初始快照，才进入 IN_ROOM。公网加密/WSS、账号身份、断线续局、持久化均不在此轮。

协议唯一来源为 schemas/。新增大厅/认证/初始快照契约与控制消息是 control_protocol=1 的本地未发布增量；新 SDK 与宿主必须同步升级，旧 M1 房间仍只使用原消息子集。新增错误码至少包括 AUTH_REQUIRED、AUTH_FAILED、BUILD_MISMATCH、ROOM_NOT_FOUND、ROOM_STARTING、ROOM_DRAINING、ROOM_FULL、ALREADY_RESERVED、ALREADY_IN_ROOM、TICKET_EXPIRED、TICKET_ALREADY_USED、IDEMPOTENCY_CONFLICT、RATE_LIMITED、LOAD_TIMEOUT。

实现依据：[Godot SceneMultiplayer 认证接口](https://docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html)、[WebSocketPeer 标准文本连接](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html)。API 行为最终以本机精确引擎运行测试为准。

## 实际协议与调用顺序

大厅单条消息是标准 WebSocket 文本 JSON，最大 16 KiB；禁止二进制消息和未知字段。`session.create` 获取本地身份，随后支持 `room.list`、`room.create`、`room.get`、`room.reserve`、`room.stop`。创建请求必须带 idempotency_key；幂等范围是当前会话，最多缓存 128 项，断线不会恢复。只有创建者能停止房间。房间列表只列出 READY 且构建匹配的房间。

完整字段见 schemas/lobby_request.schema.json 和 lobby_response.schema.json；认证见 admission_hello.schema.json、admission_reply.schema.json；初始名单见 room_snapshot.schema.json。examples/m2_messages.example.json 有 17 条可校验样例，全零 ticket 仅作占位。单元测试会逐条检查这些样例。

| 新增控制事件 | 方向 | 用途 |
|---|---|---|
| admission.consume | 房间→宿主 | 校验票据、业务身份、构建、房间和启动实例，预留转为接入中 |
| admission.result | 宿主→房间 | 给出认证结果与可信显示身份 |
| admission.revoke | 宿主→房间 | 加载超时或房间失效时撤销接入 |
| member.joined | 房间→宿主 | 客户端加载并确认初始快照后请求正式占位 |
| member.accepted | 宿主→房间 | 确认席位仍有效后才能调用适配器并发送 IN_ROOM |
| member.left | 房间→宿主 | 释放指定 user_id 与 attempt_id 的席位，旧离房消息不能释放新连接 |

加载过期检查同时位于席位确认和周期清理中，避免到期后消息抢先于清理运行。正式成员只占一份容量；临时 ENet peer_id 只用于传输寻址。服务端关闭转发，不为未通过认证的连接生成玩家。当前 GameAdapter 的示例仅记录业务身份，无角色场景。

| 错误类别 | 当前错误码与含义 |
|---|---|
| 身份和权限 | AUTH_REQUIRED 未建立会话；AUTH_FAILED 票据/身份/停止权限无效 |
| 构建与房间 | BUILD_MISMATCH 不兼容；ROOM_NOT_FOUND 无记录；ROOM_STARTING 未就绪；ROOM_DRAINING 停止中或已停止 |
| 席位 | ROOM_FULL 无空位；ALREADY_RESERVED 已有接入；ALREADY_IN_ROOM 已正式入房 |
| 票据 | TICKET_EXPIRED 过期/取消；TICKET_ALREADY_USED 已核销且不能供新尝试使用 |
| 请求 | IDEMPOTENCY_CONFLICT 同 key 不同正文；RATE_LIMITED 频率/缓存上限；INVALID_OPTIONS 参数不合法 |
| 客户端 | CONTROL_UNAVAILABLE 连接/响应不可用；LOAD_TIMEOUT 加载超时；LOAD_FAILED 场景准备失败；INVALID_SNAPSHOT 快照不合法；DISCONNECTED 连接中断 |

房间启动类错误沿用 docs/09。ENet 认证拒绝对客户端归并为 AUTH_FAILED；精细票据错误保留在宿主内部认证结果中，不承诺作为客户端 UI 错误区分。

## 验证边界

tests/run_players.gd 实际启动 2 个房间进程（先验证非法票据，再运行双人房）和 3 个客户端进程（非法票据客户端及两名正常玩家）。正常流程全程调用 SDK 公开接口；非法票据攻击夹具有意使用内部方法。两名正常玩家的快照均包含两人业务身份，主动离房后保留同一大厅会话；最后验证子进程退出、端口和席位归零。

创建幂等用例是在收到第一次响应后，以相同 key 再发请求；没有注入真实网络丢包。过期、重放、跨房/跨游戏和最后一席位由单元测试覆盖，不等于这些场景全部经过真实网络测试。慢加载使用异步计时器模拟，初始状态只有成员名单，没有玩法/装备资源。未验证 16 人、浏览器、跨机器、公网、导出产物或 Linux。
