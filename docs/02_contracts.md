# 02 控制协议与生命周期

## 当前分支指引（2026-09-22）

`codex/shooter-framework` 已接入账号 WSS 大厅、房间永久资产授权/初始状态/异步刷新、管理员 HTTP 和本机 RPC；不能再用早期“内部资产尚未接网络”描述当前实现。现行消息、错误处理与 SDK 0.5 兼容边界见 [21_managed_protocol.md](21_managed_protocol.md)，唯一机器可读契约仍是 [`schemas/`](../schemas/)。结构校验通过不代替身份、权限、生命周期或数据库事务验证。

开发范围见 [17_framework_shooter_plan.md](17_framework_shooter_plan.md)，逐项真实结果及未运行边界见 [STATUS](../STATUS.md)，可复跑命令见 [22_framework_operations.md](22_framework_operations.md)。当前公共资产操作的持久幂等键为 `payload.operation_id`，不要把下方早期通用操作表中的字段直接套到所有新接口。

## 初始设计与历史阶段记录

以下保留整体设计与 M1/S0 时点说明；“尚未接入”“后续阶段”等描述仅代表原记录时点，不覆盖上面的当前分支协议与验收记录。

2026-09-21 新分支增加内部资产目录、永久状态和交易命令 Schema，见 [18_asset_foundation.md](18_asset_foundation.md)。这些尚未接入大厅/控制网络消息，现有线协议保持严格拒绝未知消息，不能把内部服务当作已上线账号接口。

状态：以下为整体设计。M1 已实现的 control_protocol=1 子集、payload 与错误码见 [09_m1_control.md](09_m1_control.md) 和 `schemas/control.schema.json`；其余操作仍为后续阶段设计。JSON Schema 不能替代认证与生命周期语义检查。

## 1. 通用消息

消息外壳见 `schemas/envelope.schema.json`。ID 使用字符串。必需字段：`version`、`kind`、`type`、`payload`；请求/响应必须有 `request_id`；事件必须有 `event_id`。响应带 `ok`，失败带 `error.code/message/retryable`。

创建房间等有副作用的请求额外使用 `idempotency_key`。同一用户同一操作同一 key 重试必须返回同一结果；相同 key 不同请求体返回 `IDEMPOTENCY_CONFLICT`。request_id 仅用于关联某次请求，不自动提供持久化幂等。

公共外壳允许向后兼容的字段演进须先修改 schema 与契约版本策略；不能让发送方默默增加接收方拒绝的字段。v0.1 默认严格字段校验，只接受列明的 type。

## 2. 通道分帧

WebSocket：一条文本消息承载一个 JSON 外壳。

本机 TCP：`4字节无符号大端正文长度 + UTF-8 JSON正文`。长度只计算正文的字节数，不计算字符数或前缀。建议初值正文上限 64 KiB；拒绝 0 长度、超限、非法 UTF-8、非对象 JSON及过深嵌套。未收齐时保存缓冲；一次读取可能含半条或多条消息。发送队列也必须处理部分写入和背压。

TCP 提供字节流，不负责保留应用写入的消息边界。[S4] 超时不能以“本次没有数据”立即判定断线。

## 3. 操作表

| 方向 | type | 主要作用 |
|---|---|---|
| 客户端→宿主 | session.create | 第一阶段仅受限开发游客身份；公网身份提供方另行接入 |
| 客户端→宿主 | room.list | 按 game_id/兼容版本过滤公开房间，分页 |
| 客户端→宿主 | room.create | 校验模式、配额、人数后创建，先返回 room_id/STARTING |
| 客户端→宿主 | room.reserve | 为身份分配目标房间席位并发放短期票据 |
| 客户端→宿主 | room.get | 查询创建结果，不以启动进程成功替代房间就绪 |
| 房间→宿主 | room.register | 用本次启动凭据绑定 room_id/launch_id/构建身份 |
| 房间→宿主 | room.ready | 确认实际监听、配置校验、地图加载、认证门禁均已就绪 |
| 房间→宿主 | room.heartbeat | 上报序号、阶段、进程/逻辑健康、人数快照 |
| 房间→宿主 | admission.consume | 原子核销票据，绑定当前身份与连接尝试 |
| 房间→宿主 | member.joined/left | 带稳定事件ID同步名单；定期快照用于校正 |
| 房间→宿主 | result.submit | 提交可幂等持久化的结算事件 |
| 宿主→房间 | room.drain/stop | 停止接收新成员，再有序关闭 |
| 房间→宿主 | room.stopped | 正常退出通知；不替代宿主核实进程终止 |

实际实现每种消息前，补充 payload schema、权限、超时、错误码和至少一条失败测试。

## 4. 创建与入房

客户端提交 game_id、兼容标识、模式、地图ID、人数；不能提交可执行文件路径、shell指令或任意资源路径。

宿主校验并记录幂等请求 → 预留容量与端口 → 生成 room_id/launch_id 和私有启动配置 → 启动 allowlist 中的构建 → 认证注册 → 等待 ready → 对外可加入。

玩家入房使用两阶段名额管理：预留名额 → 连接与认证 → 正式成员。名额从 reserved 转为 admitting/connected 必须是原子迁移，不能重复计数，也不能遗漏认证中的席位。维持 `reserved + admitting + connected <= capacity`；重连保位未来作为独立状态设计。

v0.1 建议采用高熵随机一次性票据：宿主保存票据摘要、user_id/game_id/build_id/room_id/launch_id、到期时间与核销状态。票据只用于这一间房，不携带账号密码。房间通过已认证的控制连接请求核销；相同连接尝试的重试可返回原结果，新的连接重放不得通过。连接中断后重新申请票据，不能重复使用已消费票据。

必须在生成玩家节点和允许游戏 RPC 之前完成认证。Godot SceneMultiplayer 提供 auth_callback、send_auth、complete_auth；待认证阶段只收发认证数据，双方完成后才进入正式 peer_connected。[S3]

票据防重放不等于加密。公网原生房间须完成经验证的安全传输适配；优先验证所锁定 Godot 版本的 ENet DTLS 集成，未完成时仅限受控测试。官方 ENetConnection 有显式 DTLS 配置接口，不是普通创建 ENet 后就自动启用。[S5]

## 5. 分开记录两类状态

进程生命周期：`ALLOCATING → STARTING → READY → DRAINING → STOPPING → STOPPED`。

玩法阶段：项目报告如 `waiting/loading/playing/finished`。框架只使用明确的 joinable 与生命周期决定接入，不能硬编码“playing 一律禁止加入”。

异常可记录 FAILED，但**状态变为 FAILED 不代表端口与进程已回收**。资源必须保持隔离，直到确认对应 launch_id 的进程终止和端口可重新绑定。

## 6. 失败政策与初始参数

下面只是首轮可调初值：启动超时30秒；心跳间隔2秒；失联判定10秒；空房回收60秒；票据有效期30秒。它们不是 Godot 默认值或性能结论。长地图加载等应按测量调整。

心跳正常不必然代表模拟正常，应包含模拟步计数或逻辑健康指标。控制失联先禁止新接入；v0.1 默认在有界宽限后中止并退出，不承诺断线续局。宿主重启时先处理遗留实例，不能清空端口表后盲目启动新房。仅凭 PID 不足以认领或终止进程，需结合启动记录、进程身份及 launch_id。

正常结束先 drain、提交结果、等待持久化确认，再退出；超时未确认的结果写入持久化 outbox，由恢复流程重发。进程崩溃重启产生新 launch_id，不能宣称原对局已经恢复。

## 7. 错误码

至少包括：AUTH_REQUIRED、AUTH_FAILED、GAME_NOT_FOUND、BUILD_MISMATCH、INVALID_OPTIONS、ROOM_STARTING、ROOM_FULL、ROOM_DRAINING、HOST_CAPACITY_EXCEEDED、PORT_BIND_FAILED、START_TIMEOUT、TICKET_EXPIRED、TICKET_ALREADY_USED、IDEMPOTENCY_CONFLICT、RATE_LIMITED、CONTROL_UNAVAILABLE。

错误附可否重试。客户端对失败应返回可操作状态，不能无限快速重试或只弹“网络错误”。

## M4已实现的结果增量（2026-09-21）

唯一契约为schemas/result_record.schema.json、result_submission.schema.json和result_ack.schema.json，由control.schema.json引用；回合示例使用summary_result.schema.json。结构例子见examples/result_messages.example.json，全零signature/record_hash仅演示格式，不能认证或清除真实记录。运行时验证JSON有限数、深度与Schema，正文最大16KiB；按递归字典排序、整数规范化后的完整精度UTF-8 JSON计算SHA-256和每launch独立HMAC-SHA256。match_id以m_<launch_id>_开头，SDK局内key限1—64个字母/数字/下划线/连字符。

result.submit身份必须与已认证控制连接及持久启动授权一致；result.ack同时绑定result_id和record_hash。DUPLICATE是成功确认；RESULT_CONFLICT、MATCH_RESULT_CONFLICT、AUTH_FAILED、INVALID_RESULT、RESULT_EXPIRED是不可自动覆盖的失败，outbox保留为.rejected.json。STORAGE_UNAVAILABLE与STORAGE_CAPACITY_EXCEEDED保留文件重试。SDK本地未启用服务返回RESULTS_DISABLED；初始化可返回UNSUPPORTED_STORAGE或PRIVATE_DATA_FAILED，这些本地错误不作为线上ACK。

结果授权的补交窗口由服务器核实房间进程退出的第一时刻起算 7 天（604800 秒），不读取比赛记录或玩家提交的时间。仍在运行或身份未核实的房间不因年代久远而回收；旧库缺少结束证据的授权保持未结束。结束时间先写进进程日志，数据库结束标记用首次值，重试不延长窗口；记录结束失败时保留房间/日志并重试，关停等结果任务完成。跨运行恢复仅在只读核实原进程退出和端口可重新绑定后补记。

管理服务控制连接丢失时，宿主先等所有房间真实退出、首次退出时间写入磁盘日志及在途结果 RPC 结束，再退出；此路径只关闭传输，不声称数据库收尾成功、不删除日志或释放未确认的租约。新管理服务按原日志核实退出后补做授权结束。无法核实的进程、未知旧日志和失败的持久化继续阻止安全恢复。

新授权的事务先回收已确认结束且窗口已到期的授权，再检查 256 条容量；没有可回收项时继续拒绝，不提高上限。回收清掉授权密钥，仅留下轻量过期标记，已接受成绩和奖励回执不删除。正式带签名的 accept 在同一 SQLite 写事务里复核密钥、身份和截止时间；排队期间过期的新成绩返回 RESULT_EXPIRED，不发奖励。已接受成绩在授权回收后仅允许原 record_hash 与原签名完全一致的 DUPLICATE，不会再发奖励。旧内部存储夹具的无签名 accept 仍为受信测试接口，玩家不能调用；极旧成绩缺少签名回执且正文已被账号删除匿名化时，不合成新的签名，回收后重放保守拒绝。成绩 10000 条和资产回执 100000 条上限保留，这不是无限历史保存承诺。

旧已接受成绩缺少签名回执时，授权密钥尚存期间可用原提交正文验签、比较保存的原 record_hash 后补回执并返回 DUPLICATE，即使补交窗口已结束也不再发奖；不对匿名化后的存储正文重算哈希。密钥已回收后不能用此兼容路径绕过签名回执。

兼容说明：result.ack 新增 RESULT_EXPIRED 枚举；进程日志 v1 新增可选 exit_confirmed_at 字段；数据库 user_version=2 下做添加列/表升级，旧 launches.ended_at 为 NULL。配套服务和房间需一同更新，旧 Schema 不认识该新 ACK；版本/签名/加密门禁不放宽。

正常停止最多额外等待1.5秒发送/确认；超时留存outbox，后续恢复。尚未生成、未成功写入outbox的内存结果不保证恢复。未实现奖励或外部业务副作用。

## SDK 0.4.0 本机安全与恢复增量

session.create 的可选 credential 为64个小写十六进制字符，唯一约束来源为 lobby_request.schema.json。无身份提供方的开发 WS 使用原流程；启用提供方必须为 WSS。示例见 m2_messages.example.json 的 authenticated session.create，全零值只演示格式。认证失败 AUTH_FAILED，同用户已连接 ALREADY_CONNECTED；会话到期后断开。session响应只含user_id/display_name，不把role、过期时间或凭据返回给游戏。普通玩家停房须为创建者，admin允许跨创建者停房；拒绝返回AUTH_FAILED。

身份摘要文件契约为 identities.schema.json；重启端口/进程记录为 process_journal.schema.json。二者是私有宿主文件，不是客户端协议。身份文件最多128项；日志中的未知owned={}必须持续隔离。RECOVERY_REQUIRED表示日志不可安全恢复，ROOM_MEMORY_LIMIT表示采样超限，HELPER_TIMEOUT/HELPER_FAILED只在本地助手边界使用，存储边界转换为STORAGE_UNAVAILABLE。资源上限使用已有HOST_CAPACITY_EXCEEDED。客户端TLS错误统一表现为AUTH_FAILED或CONTROL_UNAVAILABLE，不回传密钥路径或底层敏感错误。

控制协议仍为1、游戏协议仍为1；SDK和构建兼容标识同步升版。0.3.0旧宿主/旧客户端没有新安全功能，不声称跨版本互通。详细配对见docs/07；配置、过期及证书失败分别由单元和真实secure专项验证。

本机管理面板独立API版本1：GET /api/status，响应唯一契约为schemas/dashboard_status.schema.json，示例为examples/dashboard_status.example.json。需要每次宿主生成的Bearer授权；没有写接口，不改变游戏控制协议。HTTP 401/403/404/405/400分别为缺少授权、错误来源/主机、未知路径、非GET、非法头；完整字段投影和边界见docs/16_dashboard.md，真实HTTP/Schema测试见tests/run_panel.gd。
