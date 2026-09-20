# M1 控制协议实施说明

本文件记录 M1 宿主与本次启动房间的回环 TCP 控制连接。2026-09-20 已增加 M2 标准 WebSocket JSON 大厅和控制消息扩展，详见 docs/11_m2_implementation.md。下表是仍可独立运行的 M1 消息子集；未实现的设计操作不得发送到控制端口。

## 契约来源和兼容性

`schemas/control.schema.json` 引用 `schemas/envelope.schema.json`，两者共同定义本轮全部字段。`Protocol.validate()` 从这些文件验证消息；代码不另维护消息字段清单。`schema_validator.gd` 只支持本仓库用到的 JSON Schema 子集，不是通用 Draft 2020-12 完整实现。不会访问网络解析 `$ref`。导出时必须包含 `schemas/*.json`；本轮开发工程启动不等于导出验证。

所有控制消息的 `version=1`、`kind=event`，必须带 `event_id/room_id/launch_id/game_id/build_id`；禁止未知字段、未知 type、request_id、idempotency_key。事件生成器用 16 随机字节产生 event_id。event_id 是事件标识，不承诺数据库幂等；注册、READY 和心跳各自通过连接绑定、状态与递增序号抵抗重放。停止期间已在途心跳会被忽略。

envelope 外壳由控制协议和 M2 大厅分别通过严格子 Schema 约束。增加消息或字段须同步 schema、例子、测试和版本决定，不能让发送端单方面添加接收端拒绝的字段。`examples/control_messages.example.json` 为 M1 结构样例，M2 扩展见 `examples/m2_messages.example.json`；全零 token/ticket 是占位值，不能用于真实认证。

| type | 方向 | payload | 额外运行时条件 |
|---|---|---|---|
| room.register | 房间→宿主 | token、pid | 每次启动的 32 随机字节 token，PID 和四个身份字段均匹配；仅注册一次 |
| room.ready | 房间→宿主 | udp_port | 已注册，房间实际 ENet 绑定成功；端口等于分配端口 |
| room.heartbeat | 房间→宿主→房间 | sequence、step | READY 后 sequence 严格增加，step 不倒退；宿主回声确认控制链路存活 |
| room.drain | 宿主→房间 | reason | 先停止接收；M1 无玩家资源，因此为停止阶段通知 |
| room.stop | 宿主→房间 | reason | 请求关闭 ENet、通知停止并退出 |
| room.stopped | 房间→宿主 | 空对象 | 仅为退出意图，宿主仍须核实进程退出并检查端口再回收 |
| room.failed | 房间→宿主 | code | 必须先有有效控制连接；失败不代表资源已经回收 |

PID 只是认证信息的一部分，不能取代启动身份核验。私有启动文件不进入客户端；命令行仅含 launch_id 和配置路径。宿主不打印 token 或完整控制报文。

## 分帧与背压

每帧是 4 字节无符号大端正文长度，加 UTF-8 JSON 正文；长度以字节计算。正文最大 65,536 字节，禁止零长度、超长前缀、非法 UTF-8、非对象 JSON、非有限数、超过 16 层的容器嵌套。未收齐保存缓冲；粘包逐条解码。解析错误会使连接 codec 保持失败状态，由调用方关闭连接，不能继续接收后续报文。

接收缓冲与发送队列均有限额，具体常量见 `ControlTransport`。`flush()` 使用 `StreamPeer.put_partial_data()` 的已写入字节数移动队列游标；写入 0 字节保留队列等待后续 poll，不把暂时背压当成成功发送或断线。每次读写限制工作量，避免一个连接长时间占用主循环。`flush_with_writer()` 是同一路径的测试注入点，用于稳定重现部分写入、0 字节写入及 I/O 错误；这类测试会标为模拟，不代表内核必然发生过部分写入。

## 错误码和清理

`room.failed.payload.code` 仅允许 `PORT_BIND_FAILED`、`AUTH_FAILED`、`CONTROL_UNAVAILABLE`、`INVALID_OPTIONS`、`BUILD_MISMATCH`。其余错误由宿主本地状态记录，包括程序缺失/无法启动、启动超时、心跳超时、逻辑停滞、异常退出和身份无法核验。具体本地错误见对应返回值及 STATUS 测试结果，不能作为未经 schema 扩展的房间消息发送。

非法结构和认证失败关闭该控制连接，不将客户端提供的错误内容写入有效房间；未注册连接有认证期限。清理只认领本次启动的 launch_id 和已核实进程身份；`room.stopped`、FAILED 状态或一次 kill 调用均不能替代确认退出。无法确认身份或端口仍被占用时保留隔离状态。

已认证控制连接断开立即使 STARTING/READY 房间失败并进入清理；子进程仍存活时记为 `CONTROL_UNAVAILABLE`，已确认退出时记为 `PROCESS_EXITED`。正常 STOPPING 和已有 FAILED 不覆盖原原因。

本地 API 错误码（不是远程 payload 的额外枚举）：

| 类别 | 错误码 |
|---|---|
| 注册与选项 | INVALID_MANIFEST、ARTIFACT_NOT_FOUND、UNTRUSTED_ARTIFACT、GAME_ALREADY_REGISTERED、GAME_NOT_FOUND、INVALID_OPTIONS |
| 宿主与启动 | UNSUPPORTED_PLATFORM、PRIVATE_CONFIG_FAILED、CONTROL_UNAVAILABLE、HOST_CAPACITY_EXCEEDED、PROGRAM_NOT_FOUND、PROCESS_LAUNCH_FAILED、PROCESS_IDENTITY_UNVERIFIED |
| 房间失败 | PORT_BIND_FAILED、START_TIMEOUT、HEARTBEAT_TIMEOUT、LOGIC_STALLED、PROCESS_EXITED |
| 清理隔离 | PORT_QUARANTINED；无法核实身份时保留 PROCESS_IDENTITY_UNVERIFIED |

`create_room()` 返回 `{ok, code, room_id?}`；有 room_id 的失败可以继续查询清理状态。`snapshot().cleaned` 与 `exit_confirmed` 独立于 `state=FAILED`。停止宽限结束后只尝试终止已核实身份的本次子进程；不能确认退出时持续隔离，不报告已回收。

测试入口 `tests/run_unit.gd` 加载 `tests/test_transport.gd`，覆盖契约正反例、拆包/粘包、部分写入和背压、边界与失败状态。真实进程/TCP/ENet 验证由 `tests/run_integration.gd` 承担，以 STATUS 中实际执行记录为准。

实现 API 参考：[Godot StreamPeer.put_partial_data](https://docs.godotengine.org/en/stable/classes/class_streampeer.html#class-streampeer-method-put-partial-data)。
