# 托管账号、资产、管理与维护协议（SDK 0.5）

本页记录 `codex/shooter-framework` 当前实现，不是公网发布承诺。开发路线见 [17_framework_shooter_plan.md](17_framework_shooter_plan.md)，实际完成与未运行项目以 [STATUS.md](../STATUS.md) 为准。宿主、房间和客户端使用同一批构建；本页不把旧示例的访客会话当作账号登录。

## 契约来源与验证边界

`schemas/` 是唯一机器可读契约来源。下表和 [managed_messages.example.json](../examples/managed_messages.example.json) 是说明及测试输入，不维护第二份字段定义。

| 通道或数据 | 权威 Schema | 验证范围 |
| --- | --- | --- |
| 玩家大厅请求/响应 | [managed_lobby_request](../schemas/managed_lobby_request.schema.json)、[managed_lobby_response](../schemas/managed_lobby_response.schema.json)，引用 [envelope](../schemas/envelope.schema.json) 及原大厅 Schema | 消息外壳、已声明请求类型及请求字段；新响应 payload 是对象，账号/资产内容还需对应内层 Schema |
| 内部账号请求/响应 | [account_request](../schemas/account_request.schema.json)、[account_response](../schemas/account_response.schema.json) | 账号服务字段；不能证明 token 真实、角色有效或邀请码可用 |
| 宿主与房间控制 | [control](../schemas/control.schema.json) | 包括 `asset.initial/begin/permit/refresh/finish` 的严格字段；实际进程身份和成员状态由运行时验证 |
| Operator 与托管宿主 RPC | [local_rpc](../schemas/local_rpc.schema.json) | 握手、请求、响应及事件外壳；`action` 的 body 未统一做逐操作 Schema 分派 |
| 管理面板请求 | [admin_request](../schemas/admin_request.schema.json) | 每个 action 的严格 payload；Bearer 在 HTTP 头，不在 JSON 内 |
| 永久资产 | [asset_state](../schemas/asset_state.schema.json)、[asset_command](../schemas/asset_command.schema.json)、[asset_catalog](../schemas/asset_catalog.schema.json) | 状态、内部命令、目录配置 |
| 成绩与奖励 | [result_record](../schemas/result_record.schema.json)、[result_submission](../schemas/result_submission.schema.json)、[result_ack](../schemas/result_ack.schema.json)、[result_rewards](../schemas/result_rewards.schema.json) | 成绩签名包、确认、受信任奖励数组；签名、重复提交和事务由服务/数据库验证 |

目前没有独立 `admin_response` 或维护 helper Schema。它们的实际形状见下文和实现；不应声称所有 RPC body、管理响应已经逐操作完整验证。例子中的 `rpc.account.execute.typed` 会在 RPC 外壳之后，额外按 `account_request` 验证 payload。其他内部 RPC 依靠已认证本机进程边界和被调用服务检查，不能直接暴露给客户端。

测试 [run_managed_contracts.gd](../tests/run_managed_contracts.gd) 读取例子文件中的全部用例，执行对应 Schema、必要的嵌套 Schema，并拒绝客户端夹带的身份/权限/余额字段、成功却为空的资产状态等。测试也直接调用管理 HTTP 的重复键检查函数；不创建 socket，不验证真实 token，不创建账号数据库，不启动房间。一个由 64 个零组成的 token 可以通过格式检查，仍然不能通过实际认证。

## 通道与版本

玩家通过 WSS 发送 UTF-8 JSON，战斗继续使用 ENet/DTLS。大厅请求形状为：

```json
{"version":1,"kind":"request","type":"asset.purchase","request_id":"ui_request_1","payload":{"game_id":"shooter","item_id":"smg","operation_id":"purchase_1"}}
```

响应保留 `type/request_id`，成功带 `ok:true,payload:{...}`；失败带 `ok:false,payload:{},error:{code,message,retryable}`。客户端必须检查 `ok`。`request_id` 用于匹配一次消息，`payload.operation_id` 用于持久化资产幂等，两者不能混用。新资产请求不接受外层 `idempotency_key`。

房间控制与本机 RPC 都使用回环 TCP、4 字节大端长度前缀 JSON，但外壳不同。房间控制事件有 `version/kind/type/event_id/game_id/build_id/room_id/launch_id/payload`。本机 RPC 使用以下形状：

```json
{"version":1,"kind":"hello","token":"0000000000000000000000000000000000000000000000000000000000000000","launch_id":"11111111111111111111111111111111"}
{"version":1,"kind":"hello_ok"}
{"version":1,"kind":"request","id":"rpc_1","action":"asset.initial","payload":{"user_id":"user_example","game_id":"shooter"}}
{"version":1,"kind":"response","id":"rpc_1","payload":{"ok":false,"code":"AUTH_FAILED","payload":{}}}
```

实际 RPC 握手必须匹配 Operator 本次产生的随机 token 和 launch_id；上述占位值不可使用。默认握手期限 5 秒、心跳间隔 1 秒、空闲断开 30 秒，最多 16 个连接及 64 个等待请求。普通请求默认 60 秒超时；独立阻塞 worker 请求默认 30 秒。响应除匹配 id 外，还必须来自原请求对应的 peer。业务响应嵌套在 RPC `payload`，不能只看 TCP 发送成功。

SDK 0.5 的新增内容是可选托管账号客户端、永久资产接入、通用异步资产刷新与对应控制消息。外层 `version:1` 没变，不等于旧 SDK 自动理解新消息。原 `RoomClient` 与访客/预配置身份演示入口仍可独立使用；托管大厅不接受把 `session.create` 当作账号登录。启用托管资产的游戏须同时更新 SDK、构建身份、控制消息与适配器；不要将 0.4 房间直接接入 0.5 托管宿主。

## 玩家账号

备份进行时，注册、登录、修改密码和昵称请求最多等待 **10 秒**，期间不占存储线程；同一次备份结束后执行原请求一次，不自动重发。等待队列最多 64 个，满时返回 `RATE_LIMITED`；截止时返回 `STORAGE_MAINTENANCE`，客户端显示“服务器维护中，请稍后再试”。恢复备份、改配置及关机直接拒绝，不把账号操作排到这些操作之后。

玩家在等待期间退出，大厅通过已认证内部 RPC 发送 `request.cancel` 事件，payload 只含该 RPC 的 32 位十六进制 `request_id`。Operator 按原通道实例、宿主 peer 和请求号核对；不保存未知取消，不记录账号内容。取消在执行前被处理时不会执行账号请求；已经执行的请求仍接收原回复，若登录成功则将新会话交给有限注销清理，不丢失令牌也不重发登录。取消不能撤销已经完成的注册。

资产、grant 和比赛结果不进入账号等待队列。维护期间它们保留原来的 `STORAGE_UNAVAILABLE`，尤其 `result.ack` 的契约不变，房间仍保留尚未成功确认的 outbox 结果，稍后按既有规则补交。

公共请求不能包含 `user_id/role/token/client_ip/identity` 等身份覆盖字段。注册创建普通玩家，随后单独登录；管理员由本机管理面板的首次设置建立。服务端把实际来源 IP、已认证连接的 token 加入内部账号请求，不能使用客户端声称的 IP。

| 大厅 type | payload | 成功行为 |
| --- | --- | --- |
| `account.register` | `username,password,display_name,invite_code` | 消耗有效邀请码次数，返回新身份；尚未登录 |
| `account.login` | `username,password` | 将服务端返回身份绑定到当前 WSS 连接；返回 token、identity、expires |
| `account.logout` | `{}` | 内部执行 `session.logout`，撤销会话并关闭玩家连接 |
| `account.change_password` | `password,new_password` | 验证旧密码，保存新密码，撤销会话；玩家重新登录 |
| `account.rename` | `display_name` | 仅修改当前玩家昵称 |

登录成功的大厅 `payload` 是账号服务结果，例如：

```json
{"ok":true,"code":"","token":"0000000000000000000000000000000000000000000000000000000000000000","identity":{"user_id":"user_example","display_name":"示例玩家","role":"player"},"expires":2000000000}
```

`user_id` 是持久身份，不是昵称，也不是 ENet peer_id。用户名为 3–32 位指定 ASCII 字符，比较不区分大小写；密码 8–128 字符、昵称 1–32 字符，服务拒绝控制字符。会话有效期当前为 12 小时。玩家已有有效会话时再次登录返回 `ALREADY_LOGGED_IN`；管理员用正确密码再次登录会替换旧管理员会话，避免浏览器关闭后长时间无法进入。错误密码不会取得或替换会话。

内部 `session.authenticate` 返回 identity/expires，不返回明文口令。改密、管理员重置密码、封禁会撤销会话；封禁/重置后 Operator 通知在线宿主撤销房间准入并踢出玩家。正常退出、WSS 断开、宿主退出也清理相关会话。跨进程异步撤销不能被理解为客户端断网瞬间已经完成数据库写入。

密码采用系统 .NET PBKDF2-HMAC-SHA256、600000 次迭代及独立随机盐；数据库仅保存派生值，session token 和邀请码仅保存摘要。账号请求（含密码、session token、邀请码）经 Godot 管道以一行 base64 UTF-8 JSON 写入有界 helper 的标准输入，再转给 `account_store.ps1` 的标准输入；不写任何请求文件，也不进入进程命令行（2026-09-27 起，此前使用会在宿主中途崩溃时残留的短期请求文件）。请求体上限仍为 8192 字节，超限或格式错误返回 `INVALID_ACCOUNT_REQUEST`。Godot 在确认 helper 退出后按已验证的 4.7.2 句柄规则释放进程句柄。结果授权 `grant` 请求带每房结果签名密钥，2026-09-27 起同样经标准输入交给 `sqlite_store.ps1`，密钥只写入资产库，不再出现在临时请求文件中；授权表、256 条上限、`STORAGE_CAPACITY_EXCEEDED` 与失败时的 `STORAGE_UNAVAILABLE` 均不变。其余资产、结果与维护请求不含账号口令、session token 或签名密钥，仍用原私有请求文件。

常驻存储（2026-09-27 起，内部实现，线上协议和错误码不变）：资产库的 `asset.read`、`asset.snapshot`、`asset.commit` 和账号库的 `session.authenticate`，由各自数据库唯一的一个常驻工作进程 `tools/storage_worker.ps1` 处理。工作进程在进程内调用原有的 `sqlite_store.ps1` / `account_store.ps1`，请求在内存中传递，不写文件。Godot 持有进程句柄，对请求排队（上限 16，超过返回 `STORAGE_UNAVAILABLE`），每次请求限时 10 秒，超时就结束该进程。工作进程无响应、超时或崩溃时，同一请求会经原一次性路径再执行一次；这只对上述四个可以安全重复的操作进行，`asset.commit` 沿用原 `request_id`，由回执检查保证只扣一次。空闲 300 秒后工作进程自行退出，下次请求再启动。设置环境变量 `ROOMKIT_STORAGE_MODE=oneshot` 可以整体回到一次性路径。注册、登录、grant、创建邀请码和结算等仍走一次性路径。

登录、注册及改密失败计数按用户名和真实 IP 独立持久化；当前窗口 900 秒，用户名 5 次、IP 20 次。限流跨用户名/IP 的测试属于账号后台专项，不属于本页契约测试。

### 登录验证与工作预算（2026-10-02）

登录先只读检查限流并取得凭据快照，在 SQLite 写事务之外完成原有的 60 万次密码验证。签发会话时才开启写事务，重新检查限流、身份及全部密码凭据、封禁和已有会话；验证期间改密、删除或同名重建均不能借旧凭据登录。审计身份只来自事务内确认的账号，不使用过期快照。注册和改密的事务规则未改，单玩家有效会话限制仍然保留。

Operator 的工作线程仍最多 8 个，账号上下文总计最多 72 个；名额满时账号请求在主循环有限等待，不占用额外工作线程，不承诺严格先到先执行。原 30 秒内部预算包含排队、全部备份等待和后续一次性助手预算，启动助手时重新计算剩余时间，少于 100 毫秒直接拒绝。每个实际观察到的备份窗口仍最多等 10 秒；多次备份也不能重置账号的总预算。恢复、配置变化或错过维护窗口会使排队请求失效。登录不会自动重发，也没有提高助手超时。Windows 助手启动、管道读取和回收仍可能带来预算之外的开销，这不是绝对墙钟返回保证。

退出时先收完在途账号结果，再等待由这些结果产生的会话清理，防止宿主已断开后才完成的登录留下有效令牌。取消、准入和关停检查见 [账号准入专项](../tests/run_operator_account_admission.gd)、[关停清理专项](../tests/run_operator_shutdown_cleanup.gd)；真实数据库竞态见 [登录写锁专项](../tests/test_account_login_lock.ps1)。实际平台结果见 [当前阶段](17_framework_shooter_plan.md#small-group-stability)。

## 维护、停服公告与准入竞争

已登录玩家发送 `server.notice`，payload 为 `{}`，成功响应的 payload 仍只有 `maintenance` 和 `message`，例如：

```json
{"maintenance":true,"message":"服务器将在 57 秒后停止，请保存操作。"}
```

普通维护返回管理员设置的公告；优雅停服时，宿主保存单调时钟截止时间，每次处理 `server.notice` 都以当前服务端时间重新计算剩余秒数：`max(0, ceil((deadline - now) / 1000))`。客户端显示服务端给出的 `message`，不依赖客户端时钟，也不把第一次读到的秒数长期缓存。管理 `status.host.countdown` 是现有的整数秒快照，更新频率与取整可能和刚读取的文本相差一秒。

这次修复没有新增或改名请求字段、响应字段、错误码或协议版本；继续使用现有 `server.notice.payload.message` 和 `ROOM_DRAINING`。SDK 0.5 客户端不需要解析新增倒计时字段。对应 Schema 仍以本页契约表为准。

宿主一旦接受停服，重复优雅停服不能延后原截止时间；立即停服可以将其提前。此时 `maintenance.set` 无论开启或关闭，都返回 `ROOM_DRAINING`，不能解除停止期间的准入限制，也不能用自定义维护公告覆盖停服公告。普通维护在尚未停服时仍可开启和关闭，已连接成员不会仅因维护开关被立即踢下线。

准入限制覆盖实际生命周期，而不仅是大厅按钮：

1. 维护或停服期间，玩家新建房间和申请预订返回 `ROOM_DRAINING`；禁止加入的房间拒绝新预订。
2. 房间消费已经签发的票据时，再检查当前维护/停服状态、房间 READY、joinable 和 launch 身份。先取得票据不代表之后仍可进入；拒绝时只回收该票据匹配的待准入席位。
3. 初始资产读取跨越异步等待。宿主在读取前、结果返回后都检查当前准入条件，再确认 `member.accepted`；中途停服或禁止加入不能让旧请求完成 CONNECTED。失败会清理对应 ADMITTING 席位。这个阶段的拒绝通过房间控制和 ENet 断开体现，SDK 不保证所有晚到的失败都以大厅 `ROOM_DRAINING` 返回。
4. `room.recreate` 等待旧进程退出之后还会重新检查停服状态。如果此时已经停服，返回 `ROOM_DRAINING`，不创建替代房间。

上述行为的真实 WSS/DTLS 客户端及子进程专项见 [22_framework_operations.md](22_framework_operations.md) 中的 `managed_shutdown`。其中账号/资产/成绩的可信内部 RPC 响应使用测试夹具；该专项不替代账号数据库验证。

## 永久资产与房间内授权

公共玩家资产请求只有以下输入；所有目标用户、资产空间、价格、授予权限来自服务器。

| type | payload | 成功 payload |
| --- | --- | --- |
| `asset.read` | `game_id` | `state,space,level,catalog,slots` |
| `asset.purchase` | `game_id,item_id,operation_id` | 含事务结果和 `state` |
| `asset.select` | `game_id,item_id,slot,operation_id` | 含事务结果和 `state` |

`state` 是 `{revision,credits,experience,owned,profiles}`。`profiles` 按 game_id 保存默认配置，金币/经验/物品属于配置选定的资产空间。多个游戏可使用独立空间，也可以共享空间而保留各自配置。服务器返回的目录决定合法物品、价格和槽位。玩家不能上传余额、拥有列表或管理员命令。

重试一次没有收到回复的购买/选择，必须保留同一个 `operation_id`。相同用户、相同操作键和相同命令返回已提交回执，不再扣款/加余额/增加 revision；相同键但不同命令返回 `REQUEST_CONFLICT`。若 SDK 每次调用都省略 operation_id，它会生成新键，调用者需要自己保留首次的键才能显式重试同一操作。

大厅资产访问使用 `{location:"lobby"}` 的受信上下文。玩家在房间时，宿主先查实际 CONNECTED 准入，确认 game_id 一致，再执行以下过程：

1. 宿主发 `asset.begin {operation_id,attempt_id,user_id}`。房间验证当前成员、准入尝试、停止状态与未完成资产操作，设置该玩家资产忙碌状态。
2. 房间发 `asset.permit {operation_id,attempt_id,user_id,ok,context}`。`context` 来自游戏的 `GameAdapter.asset_context(user_id)`，不是客户端 payload。宿主默认最多等待 5 秒。
3. Operator 用 token 重新认证玩家，核对稳定 user_id；游戏 `policy.authorize(identity,context,command)` 决定此刻是否允许。通过后才运行永久资产事务。
4. 宿主发 `asset.finish {operation_id,user_id,ok,state}`。房间核对自己记录的操作、准入尝试和当前成员。成功必须携带完整 `asset_state`；失败允许空对象，不能用空成功覆盖资产。

控制层的 operation_id 是一次房间状态同步标识，公共购买 operation_id 是持久化回执键；运行时分别保存，游戏不要自行复用两种含义。房间忽略未知、过期或已离开的操作回复。资产操作默认 60 秒超时，未确定的事务不会被当作成功后继续游戏；超时事务会撤销对应成员，刷新超时则回调取消。玩家离开也会取消其未完成刷新。

入场另有 `asset.initial {attempt_id,user_id,state}`：宿主读库后发送初始状态，房间必须在 WAIT_HOST 阶段收到与当前准入匹配的完整资产，才能完成 `member.accepted` 并进入 IN_ROOM。初始资产等待期限为 60 秒。

## 换游戏或模式时需要实现什么

通用框架负责身份、进程、准入、权限来源、异步协调与永久事务；玩法判断留在游戏。射击死亡后换枪、赛车停进维修站才可换车、战术模式购买阶段限时购买，都应由各自 policy 和 adapter 实现。不要把 `life_state == dead`、重生、枪械或比赛回合判断加入 `host/core` 或通用 SDK。

游戏端按需要覆盖：

| GameAdapter 接口 | 用途 |
| --- | --- |
| `asset_context(user_id)` | 返回当前权威玩法状态，供该游戏自己的 policy 判断 |
| `on_asset_state(user_id,state)` | 接收已确认的永久状态；游戏自行投影到角色/车辆/外观 |
| `set_asset_busy(user_id,busy)` | 在异步操作期间阻止会与配置变更冲突的玩法动作 |
| `asset_refresh_requested.emit(user_id,operation)` | 请求异步读取最新永久资产；operation 是游戏自己的回调标识 |
| `complete_asset_refresh(user_id,operation,state)` | 最新状态已读回，游戏继续原动作 |
| `cancel_asset_refresh(user_id,operation)` | 状态无法确认、超时或成员离开，游戏取消原动作 |

例如射击游戏可把 `operation` 解释为一次出生请求，赛车可解释为发车准备。SDK 只跟踪请求、准入、超时和回调，没有“刷新成功就重生”的硬编码。刷新在线上使用 `asset.refresh {operation_id,attempt_id,user_id}`，结果继续通过 `asset.finish` 返回；游戏 operation 字符串保存在本地操作记录中，不需要改变控制协议。

永久解锁/金币/默认武器与一局内的金钱、临时装备、比分必须分开。`sdk/roomkit/server/match_wallet.gd` 是按比赛和 launch 隔离的内存钱包，不能拿来代替持久资产库，也不能因为本局重置而清空账号余额。比赛奖励由受信游戏奖励计算器转换成永久奖励，再交给通用原子提交。

添加新模式主要改游戏 policy、adapter 和该游戏配置；添加新游戏还需登记 manifest、构建、目录、结果 Schema 及可选奖励规则。Operator 从受信本地游戏登记加载这些服务，示例组合包含 shooter 和 turns，也可显式登记新游戏；不会从玩家或管理 HTTP 请求载入路径或脚本。登记结构见 [managed_game_registry.schema.json](../schemas/managed_game_registry.schema.json)。仍不需要把赛车或战术回合规则塞进通用核心。战术射击完整规则尚不在当前实现范围。

## 本机管理 HTTP API

管理服务默认监听 `127.0.0.1:28291`。GET `/` 或 `/index.html` 返回面板；POST `/api` 接收 `Content-Type: application/json` 和 `{action,payload}`。Host 必须匹配实际本机地址与端口；若提供 Origin，必须同源。没有跨域开放；鉴权头是 `Authorization: Bearer <token>`。请求体最多 16384 字节、头部最多 8192 字节，并拒绝重复 HTTP 头、重复 JSON 对象键和等价 Unicode 转义键。最多 16 个连接；读取/业务等待/写入分别有 5/60/10 秒期限。

只有 `setup.status/setup.create/admin.login` 无需已有管理员会话，其余 action 均认证当前 token 的真实管理员角色。首次设置只能成功建立一个管理员；玩家即使提交 `role:"admin"` 也不能取得权限。

| 操作组 | action 与 payload 摘要 |
| --- | --- |
| 首次设置/登录 | `setup.status {}`；`setup.create/admin.login {username,password}`；`admin.logout {}` |
| 总览/进程 | `status {}`；`server.start {}`；`server.stop/server.restart {immediate,reason}` |
| 维护入口 | `maintenance.set {enabled,message}`；维护期间拒绝新建/加入，公告可通过 `server.notice` 读取；已接受停服后返回 `ROOM_DRAINING` |
| 房间 | `room.create {game_id,mode,map,capacity}`；`room.stop/room.recreate {room_id,reason}`；`room.joinable {room_id,joinable,reason}` |
| 玩家 | `player.kick {user_id,reason}`；`account.list {query?,offset?,limit?}`；`account.get {user_id}` |
| 账号修改 | `account.rename {user_id,display_name,reason}`；`account.reset_password {user_id,password,reason}`；`account.ban {user_id,hours,reason}`；`account.unban {user_id,reason}`；测试阶段删除 `account.delete {user_id,confirm_username,reason}`（见下节） |
| 邀请码 | `invite.create {uses,expires_hours,reason}`；`invite.list {}`；`invite.revoke {invite_id,reason}` |
| 资产管理 | `asset.read {user_id,game_id}`；`asset.adjust {user_id,game_id,coins_delta,xp_delta,operation_id,reason}`；`asset.grant/asset.revoke {user_id,game_id,item_id,operation_id,reason}`；`asset.select` 还含 `slot` |
| 备份/恢复 | `backup.create {reason}`；`backup.list {}`；`backup.restore {backup_id,reason}` |
| 日志/审计 | `logs.list {}`；`logs.read {label}`，label 仅 operator/host；`audit.list {limit?}`，当前组合结果上限固定 100 |
| 配置 | `config.get {}`；`config.set {config,reason}`，仅 Schema 白名单网络地址、端口、房间数量、资产空间映射 |

准确的必填、默认与范围以 Schema 为准。`hours:0` 表示永久封禁；内部账号接口将其转换为 `until:0`，账号输出的 `ban_until:-1` 表示永久封禁。邀请创建把相对小时转换成服务端绝对 expires。管理员不能通过重置/封禁接口封禁或重置管理员自身；内部账号服务支持验证旧密码后的自身改密，但当前管理 HTTP action 表尚未暴露管理员改密入口。资产 `coins_delta/xp_delta` 分别转换成内部 credits/experience，选择转换成管理员 `configure` 命令。客户端不能指定资产 actor、启动可执行文件或任意日志路径。

管理后台把 `account.ban/unban` 显示为“停用账号/恢复账号”；停用表单默认 `hours:0`（无限期，之后可恢复）。这是界面措辞与默认值变化，协议 action 未改。停用只撤销会话并拒绝继续登录，不删除账号、资产、回执或比赛结果。永久删除是另一个 action `account.delete`，见下一节；两者在后台是不同按钮。停用界面的措辞变化没有单独的人工点击验收。

常见响应形状是 `{ok:true,payload:{...}}` 或 `{ok:false,code,payload:{}}`；账号 helper 原生 `ok/code/identity/...` 常嵌套于外层 payload。HTTP 200 本身不代表业务成功；AUTH_FAILED/AUTH_REQUIRED 通常返回 401，其他业务失败可能仍是 200。`status.payload` 包含 host、rooms、players、metrics、games；room 行还含 pid、port、heartbeats、heartbeat_age_ms、cleaned、joinable、options。这里的玩家在线状态来自托管宿主快照，账号列表的 active 则来自有效会话。

管理员身份检查必须区分凭据无效与暂时无法检查：账号 helper 返回的 `STORAGE_UNAVAILABLE` 或工作线程入口的 `RATE_LIMITED` 原样作为业务错误返回，不转换为 `AUTH_FAILED`，也不撤销浏览器会话。真正的 `AUTH_FAILED/AUTH_REQUIRED/SESSION_EXPIRED/ADMIN_REQUIRED` 才使管理页面回到登录页并显示原因。每次浏览器请求绑定发送时的 token；旧请求晚到的认证失败不得清除后来成功登录的新 token。

优雅停服设置最多 60 秒倒计时，立即停服跳过倒计时，随后仍走房间退出和资源确认流程。重复请求不会延长已经接受的停止期限，维护开关也不能取消停服。启动成功的操作回复、READY 状态、进程确认退出是不同阶段；使用 status 查看最终结果。`room.recreate` 先等待旧房间清理，再次确认尚未停服才创建，不能凭旧 pid 猜测资源可复用。`config.set` 需要服务停止；更换共享资产空间选择已有空间，不自动复制余额。

`config.set.config.asset_spaces` 是 1–32 项的游戏 ID → 空间 ID 映射。Schema 只验证数量和已有 ID 字符规则；Operator 的受信登记另要求键集合恰好等于已注册游戏，值仅可为该游戏资产目录的默认空间或 `shared`，并拒绝共享目录内冲突的物品定义。游戏 ID 与默认空间可以不同，例如已注册 `racer` 的默认空间为 `garage`。`status.games[].asset_space` 返回该默认空间，管理页面只提供它和 `shared`，实际当前选择来自 `config.get.asset_spaces`。旧 status 缺少此字段时页面兼容回退到 game_id；新服务应始终提供字段。原 shooter/turns 配置继续兼容；合法 ID 并不授权新增游戏、资产目录、可执行路径或脚本。运行时不合法映射返回 `INVALID_OPTIONS`。

审计把操作者、目标、动作、原因和结果归档。账号审计不会记录原始密码、密码派生值、token 或邀请码明文；资产流水包含可审阅的原状态与新状态。内部仓储只读操作 `{"op":"asset.audit_all"}` 使用固定 SQL 返回最近 100 条，每行字段为 `user_id/request_id/space_id/actor_id/command/previous_body/body/created_at`。其中 command、previous_body、body 是 JSON 字符串；无额外 SQL、筛选、排序、limit 入参。Operator 将账户、资产与操作审计合并成 `audit.list.payload.entries`，资产前后状态解码为对象。这个仓储入口自身不是鉴权边界，只能由已验证管理员的 Operator 调用。

## 测试阶段账号删除

2026-09-27 起（设计与取舍见 [docs/17 第七节](17_framework_shooter_plan.md)）。管理 API `account.delete {user_id, confirm_username, reason}` 永久删除一名**玩家**在当前 `accounts.sqlite` 中的账号、会话和登录限流记录，以及当前 `assets.sqlite` 中所有资产空间的状态和交易回执；比赛结果正文、审计和其他玩家回执里该玩家的 `user_id` 换成匿名代号 `deleted_<32 位十六进制>`（SHA-256(user_id) 的前 32 位）。管理员账号不能删除。`confirm_username` 必须与服务端按 `user_id` 查出的用户名一致（不区分大小写）；客户端不能选择数据库、表或 SQL。

成功回复只含代号，不含 user_id 或用户名，例如：

```json
{"ok":true,"payload":{"state":"done","job_id":"deletion_…","subject":"deleted_…","resumed":false,"was_online":true,"still_online":false,"sessions_revoked":1,
 "assets":{"spaces":["shooter","turns"],"asset_states":2,"asset_receipts":3,"actor_receipts":0,"results_deidentified":0,"receipt_texts_scrubbed":1},
 "account":{"job_id":"deletion_…","subject":"deleted_…","state":"operator_pending","audit_rows_deidentified":2,"audit_texts_scrubbed":1,"rate_limits_removed":0,"sessions_revoked":0},
 "operator_audit_rows_deidentified":2,
 "backups_may_restore":[{"backup_id":"backup-…","created_at":1790514643,"kind":"manual"}],
 "residual_files":{"outbox_pending":0,"outbox_rejected":0,"files":[]}}}
```

`assets`/`account` 是本次请求实际执行的数据库步骤；如果数据库步骤在之前的请求里已经完成、本次只补做 Operator 收尾，二者为空对象，`resumed` 为 true。`backups_may_restore` 是收尾时已存在、且创建时间不早于该账号注册时间的备份（作业未完成期间做的备份也在内）；从中恢复会把账号和资产带回来。`residual_files` 列出本次没有改写、但仍提及该 user_id 的文件：待处理的结果文件（下次入库时只存代号、不给已删除玩家发奖，然后删除）、已拒绝的结果文件，以及数据目录下的日志与私有日志。

内部步骤：账号库 `account.delete_begin`（管理员 token；写作业、停用账号、删会话）→ 资产库 `asset.purge_user {user_id, username?}`（一个事务；写墓碑；可重复）→ 账号库 `local.deletion_finish`（删账号行、审计去标识化；作业进入 `operator_pending`）→ Operator 收尾（重写并读回校验 `operator-audit.jsonl`、`.previous`、`maintenance-audit.jsonl`，重新取备份列表，把备份清单写入并读回删除日志）→ 账号库 `local.deletion_close`（作业完成，清掉作业里的 user_id、用户名和原因；尚未到 `operator_pending` 时返回 `DELETION_NOT_READY`）。`local.*` 不在账号请求 Schema、大厅或 RPC 白名单中；`asset.purge_user` 只由 Operator 在管理员开始删除后或启动恢复时调用。第 1 步之后任何一步失败都返回 `ACCOUNT_DELETION_INCOMPLETE`，`payload` 含 `job_id/subject/user_id/stage/cause/backups_may_restore/was_online/still_online`，`stage` 为 `assets/account/operator/close/worker`，Operator 收尾的 `cause` 可为 `AUDIT_WRITE_FAILED/AUDIT_READ_FAILED/BACKUP_LIST_UNAVAILABLE/JOURNAL_WRITE_FAILED`。再次提交同一删除（账号行已删、只差收尾时也接受，仍核对输入的用户名）或 Operator 重启都会继续完成。管理员填写的 `reason` 中出现的 user_id 或输入的用户名（不区分大小写）在写入任何审计前换成代号。账号列表和详情的每个账号新增布尔字段 `deletion_pending`。

删除之后：对该 user_id 的资产写入返回 `ACCOUNT_DELETED`；新的签名结果照常入库，其余玩家照常发奖，资产库回复可能带 `rewards_skipped`（发给房间的 `result.ack` 不变）；再次删除或读取账号返回 `ACCOUNT_ALREADY_DELETED`。同一用户名可以重新注册，得到新的 user_id 和空资产。`backup.list` 的每一行新增 `deleted_accounts`（该备份可能含有的已删除账号数），依据是数据目录中不随恢复覆盖的 `account-deletions.jsonl`（只记代号、作业号、备份号和计数）。删除进行中，`backup.create/backup.restore/config.set` 返回 `MAINTENANCE_BUSY`，自动备份顺延 1 分钟。

兼容：账号库新增 `account_deletions` 表、资产库新增 `deleted_subjects` 表，`user_version` 仍为 1 / 2，旧备份可以恢复，缺表时自动补建。旧版本管理页面没有删除按钮；旧 Operator 不认识 `account.delete`，按 Schema 拒绝为 `INVALID_REQUEST`。

## 成绩与永久奖励同事务

房间按既有 `result.submit/result.ack` 流程发送签名成绩；宿主先验证本次 launch 的授权、game/build/room/launch 身份及游戏结果 Schema，再由可信奖励计算器生成奖励。不能信任房间结果里自报的永久金币金额。

`result_rewards` 是最多 256 项的数组，每项严格为 `{user_id,space_id,credits,experience}`；增量为 0–1000000 的整数。存储另检查同批同一 user_id 不重复，空间标识合法，以及累计 credits/experience 不超过 1000000000、revision 不超过 2147483647。256 是历史参与者上限，不是同时在线容量。

成绩记录、每位玩家永久状态、每条奖励回执都写入同一个 `assets.sqlite` 的 `BEGIN IMMEDIATE` 事务。后面任一奖励不合法、余额溢出或 SQL 写入失败，都回滚整批，包括前面已经更新的玩家和成绩。相同 result_id/record_hash 重试返回 `DUPLICATE`，不增加余额或 revision；同一 ID 不同内容返回 `RESULT_CONFLICT`，同一 game/match/final 的不同结果返回 `MATCH_RESULT_CONFLICT`。

当前成绩最多 10000 条，资产回执最多 100000 条；整批奖励预先检查剩余回执容量。已经存在的重复提交在容量满时仍能确认；空奖励的结果不需要奖励回执空间。这是本地首版有界存储策略，不是自动归档系统。真实原子性、并发重复、后续玩家失败回滚和容量测试见 [run_result_rewards.gd](../tests/run_result_rewards.gd)。

## 备份、恢复与主机指标

管理 API 只允许选择服务器列出的 backup_id。内部 [operator_maintenance.ps1](../tools/operator_maintenance.ps1) 通过私有请求文件接收：

```text
{op: metrics | backup.create | backup.list | backup.restore,
 root: 当前工程 data 下的绝对私有目录,
 backup_id?: 列举得到的 ID, automatic?: boolean, reason?: string}
```

这是内部 helper 调用约定，不是客户端 API，也不是独立 Schema。root 必须是当前项目 `data` 的子目录，ACL 仅允许当前用户，并拒绝路径中的 reparse point。调用方不能指定任意源数据库、备份目标、SQL 或 shell。生产目录通常是 `data/framework`。

备份包含原生 SQLite 在线备份得到的 `accounts.sqlite/assets.sqlite`，以及存在时的 `config.json/server.crt/server.key`。数据库必需，配置与 TLS 文件按实际存在情况纳入；私有 manifest 记录校验值。列表返回 `{backup_id,created_at,automatic,kind,size_bytes}`；大小来自已验证 manifest 的文件字节数总和，不包含 manifest 本身，不返回文件路径、凭据或密钥。Operator 当前每 30 分钟安排自动备份，最多保留 48 个自动备份；手工备份与恢复前备份不随此策略删除。

恢复要求 Operator 已停止并确认自己持有的宿主及房间退出，排空存储工作。helper 会独立拒绝仍存在的 `host-running.json` 标记，不会以用户声称停服为依据。恢复依次校验已列举 ID、文件校验值及两库 integrity_check，创建恢复前备份，检查数据库/文件占用，用暂存目录和持久日志替换已关闭文件，并撤销恢复库的全部会话（包括管理员）。恢复完成后必须重新登录，不能继续使用备份中的旧 token。

成功恢复可返回 `backup_id/previous_backup_id/sessions_revoked`。恢复前后记录写入不会被数据库恢复覆盖的 `maintenance-audit.jsonl`，恢复库也保留该次恢复审计。中断留下的恢复日志会在下次非 metrics 操作前检查和回滚/收尾；若无法安全恢复，则报告 `RESTORE_RECOVERY_REQUIRED`。目录外文件不参与恢复或清理。

`metrics` 返回 `system_cpu_percent/system_memory_used_bytes/system_memory_total_bytes/data_disk_free_bytes/data_disk_total_bytes`；不支持或采集失败的值为 null，不伪装成 0。磁盘指标针对私有数据所在盘，不枚举任意用户进程。顶层 `recovery_required` 表示是否存在未完成恢复。运行中备份、恢复、会话撤销、文件锁、目录联接拒绝和自动保留测试见 [test_operator_maintenance.ps1](../tests/test_operator_maintenance.ps1)。它们验证本机 Windows SQLite/文件系统，不代表 Linux 或公网部署。

## 错误处理

错误码可能由不同层返回，客户端不能按 HTTP 状态或是否收到消息来替代业务判断。旧房间/准入错误沿用 [02_contracts.md](02_contracts.md)、[09_m1_control.md](09_m1_control.md) 和既有 Schema；本轮常见增量如下。

| 错误码 | 含义与处理 |
| --- | --- |
| `INVALID_REQUEST/INVALID_ACCOUNT_REQUEST/INVALID_ASSET_COMMAND/INVALID_OPTIONS` | 输入类型、额外字段或动作不合法；修正请求后再发 |
| `AUTH_REQUIRED/AUTH_FAILED/ADMIN_REQUIRED` | 缺少登录、会话无效或角色不足；账号和管理入口各自认证 |
| `LOG_NOT_FOUND/LOG_READ_FAILED` | 管理后台允许的日志尚未生成或当前不可读；合法空文件返回成功和空 text，不伪装为读取失败 |
| `SETUP_REQUIRED/SETUP_COMPLETE` | 尚未首次设置，或已完成首次设置不能再次创建管理员 |
| `INVITE_INVALID/INVITE_NOT_FOUND/USERNAME_UNAVAILABLE` | 邀请过期/撤销/耗尽、未知邀请或用户名已占用 |
| `ACCOUNT_NOT_FOUND/ACCOUNT_BANNED/ADMIN_SELF_PROTECTION` | 未知账号、封禁中，或管理员自身保护规则拒绝操作（含删除管理员） |
| `DELETE_CONFIRMATION_MISMATCH` | 删除时输入的用户名与目标账号不一致；没有改动任何数据 |
| `ACCOUNT_DELETION_PENDING/ACCOUNT_DELETION_INCOMPLETE` | 该账号的删除已开始但未完成：账号保持停用，不能解封、改名或重置；再次执行删除或重启 Operator 继续 |
| `ACCOUNT_DELETED/ACCOUNT_ALREADY_DELETED` | 账号已被删除：拒绝再写入资产、再次删除或读取；不是存储故障 |
| `ALREADY_LOGGED_IN/ALREADY_CONNECTED` | 玩家有效会话已存在，或当前连接已登录 |
| `RATE_LIMITED` | 失败限流、单连接账号操作或单玩家资产操作正在进行；勿立即紧密重试 |
| `ACCOUNT_CAPACITY_EXCEEDED/INVITE_CAPACITY_EXCEEDED` | 本地账号或邀请码有界表达到容量 |
| `UNKNOWN_GAME/UNKNOWN_ITEM/INVALID_CONFIGURATION/ITEM_NOT_OWNED` | 不在服务器目录或玩家尚未拥有合法配置 |
| `ALREADY_OWNED/INSUFFICIENT_CREDITS/ASSET_OPERATION_DENIED` | 已解锁、余额不足，或游戏当前阶段不允许操作 |
| `REQUEST_CONFLICT/ASSET_VERSION_CONFLICT/ASSET_LIMIT_EXCEEDED` | 重试键冲突、并发 revision 变化，或永久状态超界；先读取状态，不伪造成功 |
| `INVALID_RESULT/INVALID_REWARD/RESULT_CONFLICT/MATCH_RESULT_CONFLICT` | 成绩或奖励无效/冲突；整批拒绝，不发放部分奖励 |
| `DUPLICATE` | 成功返回既有回执/成绩确认；不应再次执行发奖或购买 |
| `ROOM_DRAINING/ROOM_NOT_FOUND/CONTROL_UNAVAILABLE` | 房间停止/维护、未知房间或控制链路不可用 |
| `STORAGE_UNAVAILABLE/STORAGE_CAPACITY_EXCEEDED/STORAGE_MAINTENANCE` | 存储故障/容量满/维护中；保留原操作键，不能用新键假装原请求失败 |
| `STOP_SERVER_FIRST/SERVER_RUNNING` | 管理层或 helper 检测到服务尚未确认停止 |
| `INVALID_BACKUP_ID/BACKUP_NOT_FOUND/BACKUP_NOT_READY` | 备份标识、已列举备份或所需文件不满足恢复条件 |
| `BACKUP_INTEGRITY_FAILED/BACKUP_VERSION_UNSUPPORTED` | 校验失败或数据库版本不支持，不覆盖当前数据 |
| `MAINTENANCE_BUSY/DATABASE_BUSY/FILES_IN_USE` | 维护互斥（含账号删除进行中）、SQLite 占用或文件仍被持有 |
| `INVALID_DATA_PATH/REPARSE_POINT_REFUSED/PRIVATE_DATA_FAILED` | 私有目录边界或 ACL 不满足要求 |
| `RESTORE_RECOVERY_REQUIRED` | 先解决未完成恢复日志；不要继续启动写入 |

客户端遇到超时只能知道“没有得到确认”，不能断言“没有提交”。资产重试保留 operation_id，成绩重试保留 result_id 和相同签名内容；已经撤销/过期的身份必须重新登录。不能从 Schema 验证通过推导出账号存在、权限合法、比赛完成或数据落库。

## 本机运行本文测试

在项目目录，用实际安装的 Godot 启动 `--headless --path <项目绝对路径> --script res://tests/run_managed_contracts.gd`；Windows 图形版 exe 用 `Start-Process -PassThru -WindowStyle Hidden` 并等待该进程退出，读取真实退出码。2026-09-22 使用 Godot 4.7.2.stable 实际结果：`MANAGED_CONTRACTS_RESULT passed=241 failed=0`，退出码 0，证据 `logs/managed-contracts-console.log` 和 stderr 日志。首次测试有两项测试调用对象错误，改为管理 HTTP 实际重复键检查后全量重跑；首次日志保留为 `managed-contracts-initial-*`。

2026-09-26 通用资产空间配置回归：同一 Godot 4.7.2 实际执行上述脚本，`MANAGED_CONTRACTS_RESULT passed=260 failed=0`、退出码 0，证据 `logs/admin-generic-contracts-20260926-console.log`，stderr 无脚本错误。新增覆盖第三游戏与不同默认空间、共享空间、非法键值及 32 项上限。`node tests/test_admin_asset_spaces.cjs` 为 12/0、`node tests/test_admin_auth_errors.cjs` 为 12/0，均退出 0；它们运行页面的实际 JavaScript 函数，使用 DOM/API 替身检查显示选项、配置提交和会话错误处理，不代表真实浏览器、HTTP 权限或玩家联机验收。

资产全局审计短专项命令：

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/test_asset_audit.ps1
```

真实 SQLite 结果：`ASSET_AUDIT_RESULT passed=14 failed=0`，退出码 0，证据 `logs/asset-audit-console.log`；测试创建自己的私有 `data/test-asset-audit-*` 数据目录。241 项是纯契约/解析函数检查，14 项是本机数据库检查；两者均不是玩家真实联机、浏览器面板操作或公网通过证明。

## 2026-09-26 房间自定义规则

room.create / room.recreate 新增可选 rules，整数映射由 schemas/room_rules.schema.json 限定，再由可信游戏清单校验名称、上下界并补默认值。重建先验证后停旧房；room.stop 拒绝 rules。面板 status.games 暴露 room_rules 元数据，status.rooms[].options.rules 显示实际值。旧游戏和省略 rules 的请求仍受支持。结构不符 INVALID_REQUEST，游戏不支持或超界 INVALID_OPTIONS。射击状态兼容标识升级和完整验证见 [房间规则说明](25_shooter_room_rules.md)。
