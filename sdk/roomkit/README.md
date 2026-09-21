# RoomKit 本地开发 SDK 源码

当前分支新增源码 SDK **0.5.0** 的可选账号/资产接口。此前 0.4.0 开发身份流程继续保留；新 managed 宿主和双端构建需同步升级，不混用旧游戏产物。实际导出与运行验收见仓库 STATUS，版本号不代表所有发布门禁通过。

`client/account_client.gd` 继承 RoomClient，使用同一个 WebSocket 大厅和 ENet 房间流程。配置除游戏清单外包含 `managed=true`、WSS `url`、`ca_certificate`、`server_hostname`、`secure_enet=true`。调用 `register_account(username,password,display_name,invite_code)` 或 `login(username,password)` 后，在登录成功的连接上创建/进入房间。支持 `logout()`、`rename()`、`change_password()`、`read_assets()`、`purchase(item_id,operation_id)`、`select_item(slot,item_id,operation_id)`。密码变更后旧会话失效；未确认的资产请求保留原 operation_id 重试。

可选资产接入：GameAdapter 的 `on_asset_state(user_id,state)` 接收服务端确认的永久状态；`asset_context(user_id)` 返回游戏自己的可信上下文，具体策略只在游戏注册层解释。`set_asset_busy` 标记正在处理的事务。游戏需要刷新状态后再转阶段时，发出 `asset_refresh_requested(user_id,operation)`；SDK 调用 `complete_asset_refresh(user_id,operation,state)` 或 `cancel_asset_refresh(user_id,operation)`。操作名由游戏定义，SDK 不解释死亡、复活、枪械或赛车。初始状态在 `on_player_admitted` 前送达；超时、离房与重连使旧操作失效。永久钱包由宿主保存，比赛临时经济可选用 `server/match_wallet.gd`，二者不共享余额。

下面是继续保留的开发身份接入方式。共享传输、房间运行时和 GameAdapter 不引用具体游戏资源；SDK 是源码包，不是编辑器插件面板。

客户端将 RoomClient 加入 SceneTree，调用 `configure({url, game_id, build_id, compatibility_id, game_protocol})`，然后依次 `await open_session(display_name)`、`await create_room(options, idempotency_key)` / `await list_rooms()`、等待 READY、`await join_room(room_id)`、`await leave_room()`。退出时 `close()`。网络请求返回 `{ok, payload, code?}`；退出房间保留当前大厅会话。

可选 `prepare_scene` Callable 接收初始快照，允许异步加载并返回 bool。`join_progress` 报告 CONNECTING→AUTHENTICATING→LOADING→SYNCHRONIZING→IN_ROOM；只有 `room_joined` 才表示正式入房。`roster_changed` 提供新名单，`room_left` 表示离房。当前快照只含成员身份，不含装备或玩法状态。

单个客户端进程使用一个 RoomClient；SDK 设置 SceneTree 的默认 SceneMultiplayer、关闭自动 poll，并建立 `/root/NetRoom` 共享 RPC 节点，项目需保留该路径。不得同时添加第二套默认 MultiplayerAPI。当前 URL 支持本机开发 `ws://127.0.0.1:<port>` 和安全 `wss://localhost:<port>`。后者必须配置 ca_certificate、secure_enet=true 和预配 credential；SDK验证证书并为ENet启用DTLS。凭据不能经明文WS发送。

房间入口继承 `server/room_runtime.gd`，在 `_initialize()` 设置 `build_identity` 和 `adapter` 后调用 `super._initialize()`。适配器继承 GameAdapter，实现 `configure_room`、`on_player_admitted`、`on_player_left`、`on_shutdown_requested`。正式入房回调发生在票据认证、场景准备、初始名单确认以及宿主席位确认之后；业务身份使用 user_id。

可运行示例：`examples/minimal/multiplayer_room.gd`、`empty_adapter.gd` 和 `test_player.gd`。正常玩家只调用公开 SDK；非法票据测试刻意调用内部连接方法注入错误凭据，不属于游戏接入 API。启动 `StartDemo.cmd` 可自动执行两人流程。

Schema 文件必须随源码/导出包一起提供，已经分别验证Windows开发工程与正式导出模板。详见 `docs/11_m2_implementation.md` 和 `STATUS.md`。
